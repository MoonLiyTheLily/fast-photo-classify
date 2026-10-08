package app.fastphoto.fastphoto

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.icu.text.Transliterator
import android.location.Address
import android.location.Geocoder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt

/** All image IO and MediaStore queries stay off the Android main thread. */
class MediaBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val resolver = activity.contentResolver
    private val prefs = activity.getSharedPreferences("fastphoto", 0)
    private val io = Executors.newFixedThreadPool(4)
    private val operations = Executors.newSingleThreadExecutor()
    private val geocoding = Executors.newSingleThreadExecutor()
    private val addressCache = LinkedHashMap<String, String>()
    private val sortNames = HashMap<String, String>()
    private val transliterator by lazy { Transliterator.getInstance("Han-Latin; Latin-ASCII; Lower") }
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "app.fastphoto/media")
    private val events = EventChannel(messenger, "app.fastphoto/changes")
    private var sink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var locationResult: MethodChannel.Result? = null
    private var job: MoveJob? = null
    private var copying = false
    private var disposed = false
    private val changed = Runnable { sink?.success(true) }
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            main.removeCallbacks(changed)
            main.postDelayed(changed, 700)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        resolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer)
    }

    private fun granted(permission: String) = activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun permission(): String = when {
        Build.VERSION.SDK_INT >= 33 && granted(Manifest.permission.READ_MEDIA_IMAGES) -> "full"
        Build.VERSION.SDK_INT < 33 && granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> "full"
        Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> "limited"
        else -> "denied"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "loadSettings" -> result.success(jsonMap(JSONObject(prefs.getString("settings", "{}")!!)))
                "saveSettings" -> {
                    prefs.edit().putString("settings", JSONObject(call.arguments as Map<*, *>).toString()).apply()
                    result.success(null)
                }
                "requestPermission" -> {
                    if (permissionResult != null) { result.error("busy", "photoPermissionBusy", null); return }
                    permissionResult = result
                    val permissions = when {
                        Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                        Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
                        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                    }
                    activity.requestPermissions(permissions, 101)
                }
                "requestLocation" -> {
                    if (granted(Manifest.permission.ACCESS_MEDIA_LOCATION)) { result.success(true); return }
                    if (locationResult != null) { result.error("busy", "locationPermissionBusy", null); return }
                    locationResult = result
                    activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_MEDIA_LOCATION), 102)
                }
                "openSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                }
                "loadLibrary" -> background(result) { library() }
                "rescanPhotos" -> background(result) { rescanPhotos() }
                "thumbnail" -> background(result) { thumbnail(mediaUri(call.argument<String>("id")!!), call.argument<Int>("size") ?: 360) }
                "details" -> background(result) { details(mediaUri(call.argument<String>("id")!!), call.argument<Boolean>("location") == true) }
                "reverseGeocode" -> reverseGeocode(call, result)
                "openMap" -> {
                    val lat = call.argument<Double>("latitude")!!
                    val lon = call.argument<Double>("longitude")!!
                    require(lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0)
                    val label = call.argument<String>("label") ?: activity.getString(R.string.photo_location)
                    val url = if (call.argument<String>("provider") == "amap")
                        "https://uri.amap.com/marker?position=$lon,$lat&coordinate=wgs84&name=${Uri.encode(label)}&src=fastphoto&callnative=1"
                    else "https://www.google.com/maps/search/?api=1&query=$lat,$lon"
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    result.success(null)
                }
                "createAlbum" -> {
                    val name = call.argument<String>("name")!!.trim()
                    require(name.isNotEmpty() && name.length <= 60 && !Regex("[\\\\/:*?\"<>|\\p{Cntrl}]").containsMatchIn(name) && name != "." && name != "..") { "nativeInvalidAlbumName" }
                    val albums = prefs.getStringSet("albums", emptySet())!!.toMutableSet()
                    albums.add("Pictures/$name/")
                    prefs.edit().putStringSet("albums", albums).apply()
                    result.success(null)
                }
                "transfer" -> transfer(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("media_error", e.message ?: "mediaOperationFailed", null) }
    }

    private fun background(result: MethodChannel.Result, task: () -> Any?) {
        io.execute {
            try { val value = task(); main.post { if (!disposed) result.success(value) } }
            catch (e: Exception) { main.post { if (!disposed) result.error("media_error", e.message ?: "photoReadFailed", null) } }
        }
    }
    private fun jsonValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> jsonMap(value)
        is JSONArray -> (0 until value.length()).map { jsonValue(value.opt(it)) }
        else -> value
    }
    private fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { jsonValue(json.opt(it)) }
    private fun mediaUri(value: String): Uri {
        val uri = Uri.parse(value)
        require(uri.scheme == "content" && uri.authority == "media" && uri.pathSegments.contains("images")) { "invalidPhotoUri" }
        return uri
    }

    private val projection = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DISPLAY_NAME,
        MediaStore.Images.Media.RELATIVE_PATH, MediaStore.Images.Media.VOLUME_NAME,
        MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATE_ADDED,
        MediaStore.Images.Media.WIDTH, MediaStore.Images.Media.HEIGHT, MediaStore.Images.Media.SIZE, MediaStore.Images.Media.DATE_MODIFIED,
        MediaStore.Images.Media.ORIENTATION)

    private fun library(): Map<String, Any> {
        val access = permission()
        val photos = mutableListOf<MutableMap<String, Any>>()
        if (access != "denied") {
            val volumes = MediaStore.getExternalVolumeNames(activity).ifEmpty { setOf(MediaStore.VOLUME_EXTERNAL_PRIMARY) }
            var queried = false
            var lastError: Exception? = null
            for (queriedVolume in volumes) {
            try { resolver.query(MediaStore.Images.Media.getContentUri(queriedVolume), projection,
                "(${MediaStore.Images.Media.IS_PENDING} = 0 OR ${MediaStore.Images.Media.IS_PENDING} IS NULL) AND (${MediaStore.Images.Media.IS_TRASHED} = 0 OR ${MediaStore.Images.Media.IS_TRASHED} IS NULL)", null, null)?.use { c ->
                queried = true
                while (c.moveToNext()) {
                    val volume = c.getString(3) ?: queriedVolume
                    val uri = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(volume), c.getLong(0))
                    photos.add(mutableMapOf("id" to uri.toString(), "name" to (c.getString(1) ?: ""),
                        "path" to (c.getString(2) ?: ""), "volume" to volume,
                        "date" to (if (c.getLong(4) > 0) c.getLong(4) else c.getLong(5) * 1000),
                        "width" to c.getInt(6), "height" to c.getInt(7), "size" to c.getLong(8), "modified" to c.getLong(9) * 1000,
                        "rotation" to c.getInt(10)))
                }
            } } catch (e: Exception) { lastError = e }
            }
            if (!queried && lastError != null) throw lastError
        }
        photos.sortByDescending { it["date"] as Long }
        val byId = photos.associateBy { it["id"] as String }
        val links = JSONObject(prefs.getString("copies", "{}")!!)
        photos.forEach { photo ->
            val refs = links.optJSONArray(photo["id"] as String) ?: JSONArray()
            val paths = mutableSetOf<String>()
            val keys = mutableSetOf<String>()
            for (i in 0 until refs.length()) { byId[refs.getString(i)]?.let { target -> paths.add(target["path"] as String); keys.add("${target["volume"]}|${target["path"]}") } }
            photo["copyAlbums"] = paths.toList()
            photo["copyAlbumKeys"] = keys.toList()
        }
        val albums = prefs.getStringSet("albums", emptySet())!!.map { mapOf("path" to it, "volume" to MediaStore.VOLUME_EXTERNAL_PRIMARY) }
        val names = (photos.map { it["path"] as String } + albums.map { it["path"]!! }).map { it.trimEnd('/').substringAfterLast('/') }.distinct()
        val sorting = synchronized(sortNames) {
            names.associateWith { name -> sortNames.getOrPut(name) { transliterator.transliterate(name).replace(" ", "") } }
        }
        return mapOf("photos" to photos, "albums" to albums, "permission" to access, "sortNames" to sorting)
    }

    /** Discover newly transferred public images, including Pictures/ itself.
     * Only missing index entries are scanned; no file is moved or modified. */
    @Suppress("DEPRECATION")
    private fun rescanPhotos(): Int {
        if (permission() != "full") return 0
        val indexed = mutableSetOf<String>()
        resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, arrayOf(MediaStore.Images.Media.DATA), null, null, null)?.use { c ->
            while (c.moveToNext()) c.getString(0)?.let { indexed.add(it) }
        }
        val storage = activity.getSystemService(StorageManager::class.java)
        val roots = storage.storageVolumes.mapNotNull { it.directory }.ifEmpty { listOf(Environment.getExternalStorageDirectory()) }
        val extensions = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif", "avif", "dng", "tif", "tiff")
        val missing = mutableSetOf<String>()
        for (root in roots) {
            for (name in listOf(Environment.DIRECTORY_PICTURES, Environment.DIRECTORY_DCIM, Environment.DIRECTORY_DOWNLOADS)) {
                val directory = File(root, name)
                if (!directory.isDirectory) continue
                directory.walkTopDown().onEnter { dir -> !dir.name.startsWith(".") && !File(dir, ".nomedia").exists() && dir.canonicalFile == dir.absoluteFile }.forEach { file ->
                    if (file.isFile && file.extension.lowercase(Locale.ROOT) in extensions && file.absolutePath !in indexed && file.canRead()) missing.add(file.absolutePath)
                }
            }
        }
        var scanned = 0
        for (batch in missing.chunked(200)) {
            val latch = CountDownLatch(batch.size)
            MediaScannerConnection.scanFile(activity, batch.toTypedArray(), null) { _, _ -> latch.countDown() }
            if (!latch.await(30, TimeUnit.SECONDS)) break
            scanned += batch.size
        }
        return scanned
    }

    private fun reverseGeocode(call: MethodCall, result: MethodChannel.Result) {
        val lat = call.argument<Double>("latitude")!!
        val lon = call.argument<Double>("longitude")!!
        require(lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0)
        val locale = call.argument<String>("locale")?.let { Locale.forLanguageTag(it.replace('_', '-')) }
            ?: activity.resources.configuration.locales[0]
        val key = locale.toLanguageTag() + ":" + String.format(Locale.ROOT, "%.4f,%.4f", lat, lon)
        addressCache[key]?.let { result.success(it); return }
        if (!Geocoder.isPresent()) { result.success(null); return }
        val done = AtomicBoolean(false)
        fun finish(address: String?) {
            main.post {
                if (done.compareAndSet(false, true) && !disposed) {
                    if (!address.isNullOrBlank()) {
                        addressCache[key] = address
                        if (addressCache.size > 64) addressCache.remove(addressCache.keys.first())
                    }
                    result.success(address)
                }
            }
        }
        main.postDelayed({ finish(null) }, 6000)
        val geocoder = Geocoder(activity, locale)
        fun label(addresses: List<Address>?) = addresses?.firstOrNull()?.let {
            it.getAddressLine(0) ?: listOfNotNull(it.countryName, it.adminArea, it.locality, it.subLocality).distinct().joinToString(" ")
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                geocoder.getFromLocation(lat, lon, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<Address>) { finish(label(addresses)) }
                    override fun onError(errorMessage: String?) { finish(null) }
                })
            } else {
                geocoding.execute {
                    try {
                        @Suppress("DEPRECATION")
                        val addresses = geocoder.getFromLocation(lat, lon, 1)
                        finish(label(addresses))
                    } catch (_: Exception) { finish(null) }
                }
            }
        } catch (_: Exception) { finish(null) }
    }

    private fun thumbnail(uri: Uri, requestedSize: Int): ByteArray {
        val size = requestedSize.coerceIn(96, 3200)
        val bitmap = if (size <= 600) resolver.loadThumbnail(uri, Size(size, size), null) else {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val ratio = size.toDouble() / max(info.size.width, info.size.height)
                if (ratio < 1) decoder.setTargetSize(max(1, (info.size.width * ratio).roundToInt()), max(1, (info.size.height * ratio).roundToInt()))
            }
        }
        return try {
            ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.JPEG, if (size > 600) 94 else 82, out); out.toByteArray() }
        } finally { bitmap.recycle() }
    }

    private fun details(uri: Uri, location: Boolean): Map<String, Any> {
        val data = mutableMapOf<String, Any>()
        if (!location) return data
        if (!granted(Manifest.permission.ACCESS_MEDIA_LOCATION)) { data["locationStatus"] = "locationPermissionRequired"; return data }
        try {
            resolver.openInputStream(MediaStore.setRequireOriginal(uri))?.use { stream ->
                val coordinates = FloatArray(2)
                val exif = ExifInterface(stream)
                if (exif.getLatLong(coordinates)) {
                    data["latitude"] = coordinates[0].toDouble()
                    data["longitude"] = coordinates[1].toDouble()
                } else data["locationStatus"] = "noPhotoLocation"
            }
        } catch (_: Exception) { data["locationStatus"] = "photoLocationReadFailed" }
        return data
    }

    private data class Source(val uri: Uri, val path: String, val volume: String, val name: String, val mime: String, val date: Long)
    private fun source(uri: Uri): Source {
        val columns = arrayOf(MediaStore.Images.Media.RELATIVE_PATH, MediaStore.Images.Media.VOLUME_NAME,
            MediaStore.Images.Media.DISPLAY_NAME, MediaStore.Images.Media.MIME_TYPE, MediaStore.Images.Media.DATE_TAKEN)
        resolver.query(uri, columns, null, null, null)?.use { c ->
            require(c.moveToFirst()) { "photoUnavailable" }
            return Source(uri, c.getString(0) ?: "", c.getString(1) ?: MediaStore.VOLUME_EXTERNAL_PRIMARY,
                c.getString(2) ?: "photo.jpg", c.getString(3) ?: "image/jpeg", c.getLong(4))
        }
        error("cannotReadPhoto")
    }
    private class MoveJob(val result: MethodChannel.Result, val sources: List<Source>, val path: String,
        val failures: MutableList<Map<String, String>>, val skipped: MutableList<String>) {
        var offset = 0
        var batchEnd = 0
        val success = mutableListOf<String>()
    }

    private fun transfer(call: MethodCall, result: MethodChannel.Result) {
        check(job == null && !copying) { "transferBusy" }
        val ids = call.argument<List<String>>("ids")!!.distinct()
        require(ids.isNotEmpty()) { "selectPhotosFirst" }
        val path = call.argument<String>("path")!!
        val volume = call.argument<String>("volume")!!
        require(path.endsWith('/') && (path.startsWith("Pictures/") || path.startsWith("DCIM/")) &&
            path.split('/').none { it == ".." || it == "." } && !path.contains('\\')) { "unsupportedDestination" }
        require(MediaStore.getExternalVolumeNames(activity).contains(volume)) { "storageDisconnected" }
        copying = true // Reserves the operation slot while querying sources.
        operations.execute {
            val failures = mutableListOf<Map<String, String>>()
            val skipped = mutableListOf<String>()
            val sources = mutableListOf<Source>()
            val copy = call.argument<Boolean>("copy") == true
            ids.forEach { id ->
                try {
                    val item = source(mediaUri(id))
                    if (item.path == path && item.volume == volume) skipped.add(id)
                    else if (!copy && item.volume != volume) failures.add(mapOf("id" to id, "reason" to "crossVolumeMoveUnsupported"))
                    else sources.add(item)
                } catch (e: Exception) { failures.add(mapOf("id" to id, "reason" to (e.message ?: "readFailed"))) }
            }
            if (copy) {
                val success = mutableListOf<String>()
                val links = JSONObject(prefs.getString("copies", "{}")!!)
                sources.forEach { item ->
                    try {
                        val copied = copyPhoto(item, path, volume)
                        val refs = links.optJSONArray(item.uri.toString()) ?: JSONArray()
                        refs.put(copied.toString())
                        links.put(item.uri.toString(), refs)
                        // Persist per completed photo, including when the process later exits.
                        prefs.edit().putString("copies", links.toString()).commit()
                        success.add(item.uri.toString())
                    } catch (e: Exception) { failures.add(mapOf("id" to item.uri.toString(), "reason" to (e.message ?: "copyFailed"))) }
                }
                main.post { copying = false; if (!disposed) result.success(report(success, skipped, failures, false)) }
            } else {
                main.post {
                    copying = false
                    if (!disposed) { job = MoveJob(result, sources, path, failures, skipped); authorizeNext() }
                }
            }
        }
    }

    private fun copyPhoto(item: Source, path: String, volume: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, item.name)
            put(MediaStore.Images.Media.MIME_TYPE, item.mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, path)
            put(MediaStore.Images.Media.DATE_TAKEN, item.date)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val destination = resolver.insert(MediaStore.Images.Media.getContentUri(volume), values) ?: error("createDestinationFailed")
        try {
            val readable = if (granted(Manifest.permission.ACCESS_MEDIA_LOCATION)) MediaStore.setRequireOriginal(item.uri) else item.uri
            resolver.openInputStream(readable)?.use { input ->
                resolver.openOutputStream(destination, "w")?.use { output -> input.copyTo(output) } ?: error("writeDestinationFailed")
            } ?: error("readOriginalFailed")
            val published = resolver.update(destination, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
            check(published == 1) { "finishCopyFailed" }
            return destination
        } catch (e: Exception) { resolver.delete(destination, null, null); throw e }
    }

    private fun authorizeNext() {
        val active = job ?: return
        if (active.offset >= active.sources.size) { finishMove(false); return }
        active.batchEnd = (active.offset + 500).coerceAtMost(active.sources.size)
        val uris = active.sources.subList(active.offset, active.batchEnd).map { it.uri }
        try {
            val request = MediaStore.createWriteRequest(resolver, uris)
            activity.startIntentSenderForResult(request.intentSender, 201, null, 0, 0, 0)
        } catch (e: Exception) {
            active.sources.subList(active.offset, active.sources.size).forEach { active.failures.add(mapOf("id" to it.uri.toString(), "reason" to (e.message ?: "movePermissionFailed"))) }
            finishMove(false)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != 201) return
        val active = job ?: return
        if (resultCode != Activity.RESULT_OK) { finishMove(true); return }
        operations.execute {
            for (index in active.offset until active.batchEnd) {
                val item = active.sources[index]
                try {
                    // MediaStore handles renaming conflicts; never delete or overwrite source bytes.
                    val changed = resolver.update(item.uri, ContentValues().apply { put(MediaStore.Images.Media.RELATIVE_PATH, active.path) }, null, null)
                    check(changed == 1 && source(item.uri).path == active.path) { "systemMoveFailed" }
                    active.success.add(item.uri.toString())
                } catch (e: Exception) { active.failures.add(mapOf("id" to item.uri.toString(), "reason" to (e.message ?: "moveFailed"))) }
            }
            main.post { active.offset = active.batchEnd; if (!disposed) authorizeNext() }
        }
    }

    private fun report(success: List<String>, skipped: List<String>, failures: List<Map<String, String>>, cancelled: Boolean) =
        mapOf("success" to success, "skipped" to skipped, "failures" to failures, "cancelled" to cancelled)
    private fun finishMove(cancelled: Boolean) {
        val active = job ?: return
        job = null
        active.result.success(report(active.success, active.skipped, active.failures, cancelled))
    }
    fun onPermissions(code: Int) {
        if (code == 101) { permissionResult?.success(permission()); permissionResult = null }
        if (code == 102) { locationResult?.success(granted(Manifest.permission.ACCESS_MEDIA_LOCATION)); locationResult = null }
    }
    fun dispose() {
        disposed = true
        resolver.unregisterContentObserver(observer)
        main.removeCallbacks(changed)
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        io.shutdown()
        operations.shutdown()
        geocoding.shutdownNow()
    }
}
