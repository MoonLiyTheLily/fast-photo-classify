import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';
import 'package:flutter/rendering.dart' show RenderSliver, ScrollCacheExtent;

import 'package:fastphoto/gallery/gallery_gesture.dart';
import 'package:fastphoto/app/app_name.dart';
import 'package:fastphoto/gallery/gallery_layout.dart';
import 'package:fastphoto/gallery/gallery_viewport.dart';
import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:fastphoto/preview/photo_preview_route.dart';
import 'package:fastphoto/shared/photo_image.dart';
import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:fastphoto/gallery/photo_stack.dart';
import 'package:fastphoto/settings/settings_sheet.dart';
import 'package:fastphoto/gallery/selection_state.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:fastphoto/shared/interaction_tuning.dart';
import 'package:fastphoto/organizer/album_sort_control.dart';

import 'package:fastphoto/gallery/gallery_controller.dart';
import 'package:fastphoto/organizer/album_tray_layout.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    required this.library,
    required this.settings,
    required this.onSettingsChanged,
    this.startupError,
  });
  final MediaLibrary library;
  final AppSettings settings;
  final VoidCallback onSettingsChanged;
  final String? startupError;
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> with WidgetsBindingObserver {
  late final ThumbnailCache cache = ThumbnailCache(widget.library);
  final photoScroll = ScrollController();
  final albumScroll = ScrollController();
  final gridKey = GlobalKey();
  final photoRowsKey = GlobalKey();
  final filtersKey = GlobalKey();
  final trayGridKey = GlobalKey();
  final trayPanelKey = GlobalKey();
  final rootKey = GlobalKey();
  final hoverState = PhotoSelection();
  final dragPosition = ValueNotifier<Offset>(Offset.zero);
  final expandedTray = ValueNotifier<bool>(false);
  late final gallery = GalleryController(
    library: widget.library,
    settings: widget.settings,
    onNotice: _showError,
  );
  bool isBrowsingAlbums = false;
  bool isSelecting = false;
  bool isTrayOpen = false;
  bool get isDragging => gallery.interaction == GalleryInteraction.dragging;
  bool get isSweeping => gallery.interaction == GalleryInteraction.sweeping;
  bool get isTransferring => gallery.isTransferring;
  List<Album> get trayAlbums =>
      isBrowsingAlbums ? gallery.browseAlbums : gallery.destinationAlbums;
  AlbumTrayLayout get albumTrayLayout =>
      AlbumTrayLayout(columns: settings.albumColumns);
  SweepSelection? sweepSelection;
  GalleryLayout? photoLayout;
  String? hoveredAlbum;
  Offset gesturePosition = Offset.zero;
  int pinchColumns = 3;
  List<Photo> dragPhotos = [];
  List<Offset> dragOrigins = [];
  Timer? edgeTimer;
  AppSettings get settings => widget.settings;
  void _openAlbumTray({bool browse = false}) => setState(() {
    isBrowsingAlbums = browse;
    isTrayOpen = true;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gallery.addListener(_onGalleryChanged);
    albumScroll.addListener(_onAlbumScrolled);
    gallery.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !settings.tutorialSeen) _showTutorial();
    });
    if (widget.startupError != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showError(widget.startupError!),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) gallery.requestReload();
    if (state == AppLifecycleState.inactive && (isDragging || isSweeping)) {
      _finishSelectionGesture(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    gallery.removeListener(_onGalleryChanged);
    gallery.dispose();
    edgeTimer?.cancel();
    photoScroll.dispose();
    albumScroll.dispose();
    hoverState.dispose();
    dragPosition.dispose();
    expandedTray.dispose();
    super.dispose();
  }

  void _showError(String code) =>
      _showMessage(localizedMessage(context.l10n, code));

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _onGalleryChanged() {
    if (!mounted) return;
    setState(() => photoLayout = null);
  }

  Future<void> _openOrganizer([OrganizerTab tab = OrganizerTab.source]) async {
    if (isTransferring || isDragging || isSweeping) return;
    final draft = await showModalBottomSheet<AppSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints.tightFor(
        width: MediaQuery.sizeOf(context).width,
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: .94,
          child: OrganizerSheet(
            settings: settings,
            albums: gallery.albums,
            cache: cache,
            initialTab: tab,
          ),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    isSelecting = false;
    isTrayOpen = false;
    gallery.applyOrganizerSettings(draft);
    widget.onSettingsChanged();
    if (photoScroll.hasClients) photoScroll.jumpTo(0);
  }

  Future<void> _requestPhotoPermission() async {
    try {
      await gallery.requestPermission();
    } catch (e) {
      _showError(describeGalleryError(e));
    }
  }

  Future<void> _showTutorial() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('first-run-tutorial'),
          title: Text(context.l10n.tutorialTitle),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.tutorialStep1),
              SizedBox(height: 16),
              Text(context.l10n.tutorialStep2),
              SizedBox(height: 16),
              Text(context.l10n.tutorialStep3),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final failureMessage = context.l10n.tutorialSaveFailed;
                settings.tutorialSeen = true;
                Navigator.pop(context);
                try {
                  await widget.library.saveSettings(settings);
                } catch (_) {
                  _showMessage(failureMessage);
                }
              },
              child: Text(context.l10n.startOrganizing),
            ),
          ],
        ),
      ),
    );
  }

  void _applySettingsChanges() {
    gallery.settingsChanged();
    widget.onSettingsChanged();
  }

  void _openSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .92,
      child: SettingsSheet(
        settings: settings,
        library: widget.library,
        onChanged: _applySettingsChanges,
        onTutorial: () {
          Navigator.pop(context);
          _showTutorial();
        },
        onOrganize: () {
          Navigator.pop(context);
          _openOrganizer();
        },
      ),
    ),
  );
  Future<void> _createAlbum() async {
    final albumNameInput = TextEditingController();
    String? validation;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.l10n.newAlbum),
          content: TextField(
            controller: albumNameInput,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: context.l10n.albumName,
              hintText: context.l10n.albumNameHint,
              errorText: validation,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = albumNameInput.text.trim();
                if (value.isEmpty ||
                    RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(value) ||
                    value == '.' ||
                    value == '..') {
                  update(() => validation = context.l10n.invalidAlbumName);
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(context.l10n.create),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      albumNameInput.dispose,
    );
    if (name == null || !mounted) return;
    try {
      await gallery.createAlbum(name);
      if (!mounted) return;
      _showMessage(context.l10n.albumCreated(name));
    } catch (e) {
      _showError(describeGalleryError(e));
    }
  }

  void _togglePhotoSelection(Photo photo) {
    if (!isSelecting) setState(() => isSelecting = true);
    if (!gallery.selection.remove(photo.id)) {
      gallery.selection.add(photo.id);
    }
    if (gallery.isPreviewOpen) {
      // Selection can reveal a bottom toolbar and shrink the grid viewport.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gallery.isPreviewOpen) {
          _positionPreviewReturnTarget(photo);
        }
      });
    }
  }

  void _clearSelection() => setState(() {
    gallery.selection.clear();
    isSelecting = false;
    isTrayOpen = false;
  });
  Future<void> _openPreview(int index) async {
    if (isTransferring || isDragging || isSweeping || gallery.isPreviewOpen) {
      return;
    }
    final route = PhotoPreviewRoute(
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (_) => PhotoPreview(
        photos: List.of(gallery.visiblePhotos),
        initialIndex: index,
        cache: cache,
        library: widget.library,
        settings: settings,
        selected: gallery.selection,
        onToggle: _togglePhotoSelection,
        onPhotoChanged: _positionPreviewReturnTarget,
      ),
    );
    gallery.setPreviewOpen(true);
    try {
      await Navigator.of(context).push(route);
      // pop() completes when the return starts. Keep the grid stable until
      // the Hero has actually landed and the route overlay is removed.
      await route.completed;
    } finally {
      gallery.setPreviewOpen(false);
      if (mounted) setState(() {});
    }
  }

  void _positionPreviewReturnTarget(Photo photo) {
    final index = gallery.visibleIndices[photo.id];
    final layout = photoLayout;
    if (index == null || layout == null || !photoScroll.hasClients) return;
    final viewport = _galleryViewport;
    if (viewport == null) return;
    final position = photoScroll.position;
    photoScroll.jumpTo(
      viewport
          .offsetToReveal(photoTop: layout.topOf(index), photoSize: layout.cell)
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  GalleryViewport? get _galleryViewport {
    final bounds = _globalBoundsOf(gridKey);
    final filters = _globalBoundsOf(filtersKey);
    final rows = photoRowsKey.currentContext?.findRenderObject();
    if (bounds == null ||
        filters == null ||
        rows is! RenderSliver ||
        !photoScroll.hasClients ||
        rows.geometry == null) {
      return null;
    }
    return GalleryViewport(
      scrollBounds: bounds,
      filtersBottom: filters.bottom,
      contentStart: rows.constraints.precedingScrollExtent,
      scrollOffset: photoScroll.offset,
    );
  }

  Rect? _globalBoundsOf(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize
        ? object.localToGlobal(Offset.zero) & object.size
        : null;
  }

  int? _photoIndexAt(Offset position) {
    final viewport = _galleryViewport;
    if (viewport == null || !viewport.visibleBounds.contains(position)) {
      return null;
    }
    return photoLayout?.indexAt(viewport.toContent(position));
  }

  void _startSelectionGesture(int id, Offset position) {
    final index = _photoIndexAt(position);
    if (index == null || isTransferring || isTrayOpen) return;
    InteractionTuning.pickedUp();
    gesturePosition = position;
    dragPosition.value = position;
    expandedTray.value = false;
    setState(() {
      isSelecting = true;
      if (gallery.selection.contains(gallery.visiblePhotos[index].id)) {
        gallery.setInteraction(GalleryInteraction.dragging);
        isBrowsingAlbums = false;
        isTrayOpen = true;
        dragPhotos = [
          gallery.visiblePhotos[index],
          ...gallery.selection
              .where((id) => id != gallery.visiblePhotos[index].id)
              .take(2)
              .map((id) => gallery.photosById[id]!),
        ];
        final viewport = _galleryViewport;
        dragOrigins = dragPhotos.map((photo) {
          final photoIndex = gallery.visibleIndices[photo.id] ?? -1;
          if (photoIndex < 0 || viewport == null || photoLayout == null) {
            return Offset.zero;
          }
          final center = viewport.toGlobal(photoLayout!.centerOf(photoIndex));
          return viewport.visibleBounds.contains(center)
              ? center - (position + const Offset(-4, -78))
              : Offset.zero;
        }).toList();
      } else {
        gallery.setInteraction(GalleryInteraction.sweeping);
        sweepSelection = SweepSelection(
          gallery.visiblePhotos,
          gallery.selection,
          index,
        );
      }
    });
    edgeTimer?.cancel();
    edgeTimer = Timer.periodic(
      const Duration(milliseconds: 25),
      (_) => _scrollAtEdge(),
    );
  }

  void _updateSelectionGesture(Offset position) {
    gesturePosition = position;
    if (isDragging) {
      dragPosition.value = position;
      _setHoveredAlbum(_albumAtPosition(gesturePosition)?.key);
      if (!expandedTray.value &&
          (_globalBoundsOf(trayPanelKey)?.contains(gesturePosition) ?? false)) {
        expandedTray.value = true;
      }
    }
    if (isSweeping) _updateSweepSelection();
  }

  void _updateSweepSelection() {
    final index = _photoIndexAt(gesturePosition);
    if (index == null) return;
    sweepSelection?.move(index);
  }

  void _setHoveredAlbum(String? key) {
    if (key == hoveredAlbum) return;
    if (hoveredAlbum != null) hoverState.remove(hoveredAlbum);
    hoveredAlbum = key;
    if (key != null) {
      hoverState.add(key);
      InteractionTuning.targetChanged();
    }
  }

  Album? _albumAtPosition(Offset position) {
    final viewport = _globalBoundsOf(trayGridKey);
    if (viewport == null || !viewport.contains(position)) return null;
    if (!albumScroll.hasClients) return null;
    final index = albumTrayLayout.indexAt(
      position: position - viewport.topLeft,
      viewportSize: viewport.size,
      scrollOffset: albumScroll.offset,
      albumCount: trayAlbums.length,
    );
    return index == null ? null : trayAlbums[index];
  }

  void _onAlbumScrolled() {
    if (isDragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isDragging) {
          final key = _albumAtPosition(gesturePosition)?.key;
          _setHoveredAlbum(key);
        }
      });
    }
  }

  void _scrollAtEdge() {
    if (!mounted || (!isDragging && !isSweeping)) return;
    if (isDragging) _setHoveredAlbum(_albumAtPosition(gesturePosition)?.key);
    final activeScroll = isDragging ? albumScroll : photoScroll;
    final rect = isDragging
        ? _globalBoundsOf(trayGridKey)
        : _galleryViewport?.visibleBounds;
    if (rect == null ||
        !activeScroll.hasClients ||
        gesturePosition.dx < rect.left ||
        gesturePosition.dx > rect.right ||
        gesturePosition.dy < rect.top - 22 ||
        gesturePosition.dy > rect.bottom + 22) {
      return;
    }
    const zone = 52.0;
    var delta = 0.0;
    if (gesturePosition.dy < rect.top + zone) {
      delta = -14 * ((rect.top + zone - gesturePosition.dy) / zone).clamp(0, 1);
    }
    if (gesturePosition.dy > rect.bottom - zone) {
      delta =
          14 * ((gesturePosition.dy - rect.bottom + zone) / zone).clamp(0, 1);
    }
    if (delta == 0) return;
    final next = (activeScroll.offset + delta).clamp(
      0.0,
      activeScroll.position.maxScrollExtent,
    );
    if (next == activeScroll.offset) return;
    activeScroll.jumpTo(next);
    if (isSweeping) _updateSweepSelection();
  }

  void _finishSelectionGesture(bool cancelled) {
    edgeTimer?.cancel();
    final wasDragging = isDragging;
    final target = wasDragging && !cancelled
        ? _albumAtPosition(gesturePosition)
        : null;
    _setHoveredAlbum(null);
    expandedTray.value = false;
    sweepSelection = null;
    setState(() {
      hoveredAlbum = null;
      if (wasDragging) isTrayOpen = false;
    });
    // Begin a transfer before releasing the gesture's refresh hold, so an
    // already queued library update cannot slip between drop and transfer.
    if (target != null) _transferSelection(target);
    gallery.setInteraction(GalleryInteraction.idle);
  }

  void _resizePhotoGrid(double scale) {
    if (isTransferring || isDragging || isTrayOpen) return;
    if (scale == 1) {
      pinchColumns = settings.photoColumns;
      return;
    }
    final columns = (pinchColumns / scale).round().clamp(2, 6);
    if (columns == settings.photoColumns) return;
    final rect = _galleryViewport?.visibleBounds;
    final oldIndex = rect == null ? null : _photoIndexAt(rect.center);
    setState(() {
      settings.photoColumns = columns;
      photoLayout = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          photoScroll.hasClients &&
          oldIndex != null &&
          photoLayout != null &&
          _galleryViewport != null) {
        photoScroll.jumpTo(
          _galleryViewport!
              .offsetToCenter(
                photoLayout!.topOf(oldIndex) + photoLayout!.cell / 2,
              )
              .clamp(0.0, photoScroll.position.maxScrollExtent),
        );
      }
    });
    widget.library.saveSettings(settings).catchError((Object _) {});
  }

  Future<void> _transferSelection(Album album) async {
    if (gallery.selection.isEmpty || isTransferring) return;
    final copy = settings.copy;
    setState(() => isTrayOpen = false);
    try {
      final result = await gallery.transferSelectionTo(album);
      if (!mounted || result == null) return;
      setState(() => isSelecting = gallery.selection.isNotEmpty);
      if (result.successfulIds.isNotEmpty) InteractionTuning.completed();
      final parts = <String>[
        if (result.successfulIds.isNotEmpty)
          (copy
              ? context.l10n.copiedPhotos(
                  result.successfulIds.length,
                  album.displayName(context.l10n),
                )
              : context.l10n.movedPhotos(
                  result.successfulIds.length,
                  album.displayName(context.l10n),
                )),
        if (result.skippedIds.isNotEmpty)
          context.l10n.skippedPhotos(result.skippedIds.length),
        if (result.cancelled) context.l10n.transferCancelled,
        if (result.failures.isNotEmpty)
          context.l10n.failedPhotos(
            result.failures.length,
            localizedMessage(context.l10n, result.failures.first.reason),
          ),
      ];
      _showMessage(
        parts.isEmpty
            ? context.l10n.noPhotosChanged
            : parts.join(context.l10n.messageSeparator),
      );
    } catch (error) {
      _showError(describeGalleryError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !isTrayOpen && !isSelecting && !isTransferring,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || isTransferring) return;
        if (isDragging || isSweeping) {
          _finishSelectionGesture(true);
        } else if (isTrayOpen) {
          setState(() => isTrayOpen = false);
        } else {
          _clearSelection();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            key: rootKey,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: expandedTray,
                builder: (context, expanded, child) => ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: InteractionTuning.backgroundBlur,
                    sigmaY: InteractionTuning.backgroundBlur,
                  ),
                  enabled: expanded && isDragging,
                  child: child,
                ),
                child: RepaintBoundary(
                  child: Column(
                    children: [
                      Expanded(child: _buildGalleryScrollView()),
                      if (isSelecting)
                        ValueListenableBuilder<int>(
                          valueListenable: gallery.selection.count,
                          builder: (_, _, _) => _buildSelectionBar(),
                        ),
                    ],
                  ),
                ),
              ),
              if (isTrayOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: isDragging
                        ? null
                        : () => setState(() => isTrayOpen = false),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .32),
                    ),
                  ),
                ),
                _buildAlbumTray(),
              ],
              if (isDragging)
                ValueListenableBuilder<Offset>(
                  valueListenable: dragPosition,
                  builder: (_, position, child) => Positioned(
                    left:
                        position.dx -
                        (_globalBoundsOf(rootKey)?.left ?? 0) -
                        50,
                    top:
                        position.dy -
                        (_globalBoundsOf(rootKey)?.top ?? 0) -
                        130,
                    child: child!,
                  ),
                  child: IgnorePointer(
                    child: PhotoStack(
                      photos: dragPhotos,
                      origins: dragOrigins,
                      cache: cache,
                      count: gallery.selection.length,
                    ),
                  ),
                ),
              if (isTransferring)
                Positioned.fill(
                  child: ColoredBox(
                    color: colors.surface.withValues(alpha: .85),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            (settings.copy
                                ? context.l10n.copyingPhotos(
                                    gallery.selection.length,
                                  )
                                : context.l10n.movingPhotos(
                                    gallery.selection.length,
                                  )),
                          ),
                          const SizedBox(height: 8),
                          Text(context.l10n.confirmSystemPrompt),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() => SliverAppBar(
    primary: false,
    floating: true,
    snap: true,
    automaticallyImplyLeading: false,
    centerTitle: false,
    titleSpacing: 20,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    title: Text(
      appDisplayName(context),
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    actionsPadding: const EdgeInsets.only(right: 12),
    actions: [
      IconButton(
        tooltip: context.l10n.refreshPhotos,
        onPressed: isTransferring || gallery.isRefreshing
            ? null
            : gallery.refreshFromStorage,
        icon: gallery.isRefreshing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 22),
      ),
      IconButton(
        tooltip: context.l10n.newAlbum,
        onPressed: isTransferring ? null : _createAlbum,
        icon: const Icon(Icons.create_new_folder_outlined, size: 23),
      ),
      IconButton(
        tooltip: context.l10n.settings,
        onPressed: isTransferring ? null : _openSettings,
        icon: const Icon(Icons.tune, size: 23),
      ),
    ],
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(
        MediaQuery.textScalerOf(context).scale(14) + 14,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.photoSummary(
              gallery.snapshot.photos.length,
              gallery.unorganizedCount,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    ),
  );

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in [
                  (PhotoFilter.all, context.l10n.allPhotos),
                  (PhotoFilter.unorganized, context.l10n.pending),
                  (PhotoFilter.organized, context.l10n.organized),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: isTransferring
                          ? null
                          : () => _openOrganizer(
                              entry.$1 == PhotoFilter.organized
                                  ? OrganizerTab.target
                                  : OrganizerTab.source,
                            ),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected:
                            gallery.browsedAlbumKey == null &&
                            gallery.filter == entry.$1,
                        showCheckmark: false,
                        onSelected: isTransferring
                            ? null
                            : (_) => setState(() {
                                gallery.showFilter(entry.$1);
                                if (photoScroll.hasClients) {
                                  photoScroll.jumpTo(0);
                                }
                              }),
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(context.l10n.album),
                  onPressed: isTransferring
                      ? null
                      : () => _openAlbumTray(browse: true),
                ),
                IconButton(
                  tooltip: context.l10n.organizerTitle,
                  onPressed: isTransferring ? null : () => _openOrganizer(),
                  icon: const Icon(Icons.rule_folder_outlined, size: 21),
                ),
              ],
            ),
          ),
          if (gallery.browsedAlbumKey != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InputChip(
                key: const ValueKey('browsing-album'),
                avatar: const Icon(Icons.folder_open, size: 18),
                label: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width - 150,
                  ),
                  child: Text(
                    gallery.albums
                        .firstWhere((a) => a.key == gallery.browsedAlbumKey)
                        .displayName(context.l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                selected: true,
                showCheckmark: false,
                deleteIcon: const Icon(Icons.cancel, size: 24),
                deleteButtonTooltipMessage: context.l10n.exitAlbumBrowsing,
                onPressed: () => _openAlbumTray(browse: true),
                onDeleted: () => setState(() {
                  gallery.closeAlbum();
                  if (photoScroll.hasClients) photoScroll.jumpTo(0);
                }),
              ),
            ),
          if (!settings.sourceAll || !settings.targetAll)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                context.l10n.scopeHint(
                  settings.sourceAll
                      ? context.l10n.allSources
                      : context.l10n.sourceCount(settings.sourceKeys.length),
                  settings.targetAll
                      ? context.l10n.allTargets
                      : context.l10n.targetCount(settings.targetKeys.length),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (gallery.snapshot.permission == 'limited')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.photo_library_outlined, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.limitedPhotos,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestPhotoPermission,
                    child: Text(context.l10n.adjustScope),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGalleryScrollView() => LayoutBuilder(
    builder: (context, constraints) => RawGestureDetector(
      gestures: {
        GalleryGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<GalleryGestureRecognizer>(
              GalleryGestureRecognizer.new,
              (instance) => instance
                ..canStart = ((position) =>
                    !isTransferring &&
                    !isTrayOpen &&
                    _photoIndexAt(position) != null)
                ..onHold = _startSelectionGesture
                ..onMove = _updateSelectionGesture
                ..onEnd = _finishSelectionGesture
                ..onPinch = _resizePhotoGrid,
            ),
      },
      child: CustomScrollView(
        key: gridKey,
        controller: photoScroll,
        scrollCacheExtent: ScrollCacheExtent.pixels(450),
        slivers: [
          _buildAppBar(),
          PinnedHeaderSliver(
            child: ColoredBox(
              key: filtersKey,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _buildFilters(),
            ),
          ),
          _buildPhotoSliver(
            constraints.maxWidth - 2 * GalleryViewport.horizontalPadding,
          ),
        ],
      ),
    ),
  );

  Widget _buildPhotoSliver(double width) {
    if (gallery.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (gallery.loadError != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          Icons.cloud_off_outlined,
          context.l10n.photosLoadIncomplete,
          localizedMessage(context.l10n, gallery.loadError!),
          context.l10n.retry,
          gallery.requestReload,
        ),
      );
    }
    if (!gallery.snapshot.accessible) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          Icons.photo_library_outlined,
          context.l10n.permissionWelcome,
          context.l10n.permissionDescription,
          context.l10n.allowPhotoAccess,
          _requestPhotoPermission,
          secondary: TextButton(
            onPressed: () async {
              try {
                await widget.library.openSettings();
              } catch (e) {
                _showError(describeGalleryError(e));
              }
            },
            child: Text(context.l10n.grantInSettings),
          ),
        ),
      );
    }
    if (gallery.visiblePhotos.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          Icons.check_circle_outline,
          gallery.filter == PhotoFilter.unorganized
              ? context.l10n.allOrganized
              : context.l10n.noPhotos,
          gallery.snapshot.photos.isEmpty
              ? context.l10n.noPhotosHint
              : context.l10n.filterEmptyHint,
          context.l10n.refreshPhotos,
          gallery.requestReload,
        ),
      );
    }
    if (photoLayout == null ||
        photoLayout!.width != width ||
        photoLayout!.columns != settings.photoColumns) {
      photoLayout = GalleryLayout(
        gallery.visiblePhotos,
        settings.photoColumns,
        width,
        settings.groupByDate,
      );
    }
    final geometry = photoLayout!;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: GalleryViewport.horizontalPadding,
      ),
      sliver: SliverList.builder(
        key: photoRowsKey,
        itemCount: geometry.rows.length,
        itemBuilder: (context, rowIndex) {
          final row = geometry.rows[rowIndex];
          if (row.header) {
            final date = row.date!;
            final weekday = photoWeekday(context, date);
            return SizedBox(
              height: row.height,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 6),
                child: Row(
                  children: [
                    Text(
                      photoDate(context, date, hideCurrentYear: true),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(weekday, style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        isSelecting = true;
                        final ids = gallery.visiblePhotos
                            .sublist(row.start, row.end)
                            .map((p) => p.id);
                        if (ids.every(gallery.selection.contains)) {
                          gallery.selection.removeAll(ids);
                        } else {
                          gallery.selection.addAll(ids);
                        }
                      }),
                      child: Text(
                        context.l10n.photoCount(row.end - row.start),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return SizedBox(
            height: row.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = row.start; i < row.end; i++) ...[
                  if (i != row.start) const SizedBox(width: GalleryLayout.gap),
                  SizedBox(
                    width: geometry.cell,
                    height: geometry.cell,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: gallery.selection.watch(
                        gallery.visiblePhotos[i].id,
                      ),
                      builder: (_, checked, _) => PhotoTile(
                        key: ValueKey('photo-${gallery.visiblePhotos[i].id}'),
                        photo: gallery.visiblePhotos[i],
                        cache: cache,
                        selected: checked,
                        selecting: isSelecting,
                        organized: gallery.organizedIds.contains(
                          gallery.visiblePhotos[i].id,
                        ),
                        onToggle: () =>
                            _togglePhotoSelection(gallery.visiblePhotos[i]),
                        onPreview: () => _openPreview(i),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    IconData icon,
    String title,
    String subtitle,
    String button,
    VoidCallback action, {
    Widget? secondary,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 62, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 22),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: action, child: Text(button)),
          ?secondary,
        ],
      ),
    ),
  );
  Widget _buildSelectionBar() => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border(
        top: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .13),
        ),
      ),
    ),
    child: isSelecting
        ? Row(
            children: [
              IconButton(
                tooltip: context.l10n.exitSelection,
                onPressed: isTransferring ? null : _clearSelection,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  context.l10n.selectedPhotoCount(gallery.selection.length),
                  key: const ValueKey('selection-count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: TextButton(
                  onPressed: isTransferring
                      ? null
                      : () => setState(() {
                          final ids = gallery.visiblePhotos.map((p) => p.id);
                          if (ids.every(gallery.selection.contains)) {
                            gallery.selection.removeAll(ids);
                          } else {
                            gallery.selection.addAll(ids);
                          }
                        }),
                  child: Text(
                    context.l10n.selectAll,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Flexible(
                child: FilledButton.tonal(
                  onPressed: gallery.selection.isEmpty || isTransferring
                      ? null
                      : () => _openAlbumTray(),
                  child: Text(
                    context.l10n.addToAlbum,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          )
        : const SizedBox.shrink(),
  );

  Widget _buildAlbumTray() {
    final side =
        settings.edge == TrayEdge.left || settings.edge == TrayEdge.right;
    final alignment = switch (settings.edge) {
      TrayEdge.bottom => Alignment.bottomCenter,
      TrayEdge.top => Alignment.topCenter,
      TrayEdge.left => Alignment.centerLeft,
      TrayEdge.right => Alignment.centerRight,
    };
    final offset = switch (settings.edge) {
      TrayEdge.bottom => const Offset(0, 1),
      TrayEdge.top => const Offset(0, -1),
      TrayEdge.left => const Offset(-1, 0),
      TrayEdge.right => const Offset(1, 0),
    };
    final root = _globalBoundsOf(rootKey)?.size ?? MediaQuery.sizeOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: expandedTray,
      builder: (context, expanded, _) => Align(
        alignment: alignment,
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(begin: offset, end: Offset.zero),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) =>
              FractionalTranslation(translation: value, child: child),
          child: Material(
            key: trayPanelKey,
            elevation: 12,
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: AnimatedContainer(
              key: const ValueKey('album-tray'),
              duration: InteractionTuning.tray,
              curve: Curves.easeOutCubic,
              width: side ? root.width * (expanded ? .96 : .84) : root.width,
              height: side
                  ? root.height
                  : math.max(230, root.height * (expanded ? .88 : .54)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isDragging
                                ? context.l10n.releaseToAdd
                                : (isBrowsingAlbums
                                      ? context.l10n.browseAlbums
                                      : context.l10n.addToAlbum),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!isDragging && !isBrowsingAlbums)
                          IconButton(
                            tooltip: context.l10n.targetAlbumsAndSort,
                            icon: const Icon(Icons.filter_list),
                            onPressed: () =>
                                _openOrganizer(OrganizerTab.target),
                          ),
                        if (!isDragging)
                          IconButton(
                            tooltip: context.l10n.newAlbum,
                            icon: const Icon(Icons.create_new_folder_outlined),
                            onPressed: _createAlbum,
                          ),
                        if (!isDragging)
                          IconButton(
                            tooltip: context.l10n.closeAlbums,
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => isTrayOpen = false),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 13),
                    child: Text(
                      isDragging
                          ? context.l10n.dragScrollHint
                          : isBrowsingAlbums
                          ? context.l10n.browseDragHint
                          : (settings.copy
                                ? context.l10n.selectedCopyHint(
                                    gallery.selection.length,
                                  )
                                : context.l10n.selectedMoveHint(
                                    gallery.selection.length,
                                  )),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (!isDragging)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: AlbumSortControl(
                        value: settings.albumSort,
                        onChanged: (value) {
                          settings.albumSort = value;
                          _applySettingsChanges();
                        },
                      ),
                    ),
                  Expanded(
                    child: trayAlbums.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.noTargets),
                                const SizedBox(height: 10),
                                if (!isDragging)
                                  TextButton(
                                    onPressed: () =>
                                        _openOrganizer(OrganizerTab.target),
                                    child: Text(context.l10n.adjustTargets),
                                  ),
                                if (!isDragging)
                                  FilledButton.tonal(
                                    onPressed: _createAlbum,
                                    child: Text(context.l10n.newAlbum),
                                  )
                                else
                                  Text(context.l10n.newAlbumAfterRelease),
                              ],
                            ),
                          )
                        : ClipRect(
                            child: GridView.builder(
                              key: trayGridKey,
                              controller: albumScroll,
                              padding: AlbumTrayLayout.padding,
                              gridDelegate: albumTrayLayout.gridDelegate,
                              itemCount: trayAlbums.length,
                              itemBuilder: (context, i) =>
                                  ValueListenableBuilder<bool>(
                                    valueListenable: hoverState.watch(
                                      trayAlbums[i].key,
                                    ),
                                    builder: (_, hovered, _) =>
                                        _buildAlbumTile(trayAlbums[i], hovered),
                                  ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumTile(Album album, bool hovered) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.l10n.albumSemantics(
        album.displayName(context.l10n),
        album.count,
      ),
      child: GestureDetector(
        key: ValueKey('album-${album.key}'),
        onTap: isDragging
            ? null
            : () {
                if (!isBrowsingAlbums && gallery.selection.isNotEmpty) {
                  _transferSelection(album);
                } else {
                  setState(() {
                    gallery.browseAlbum(album);
                    isTrayOpen = false;
                  });
                }
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hovered ? colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: hovered ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (album.cover != null)
                        PhotoImage(photo: album.cover!, cache: cache)
                      else
                        ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.folder_outlined,
                            color: colors.primary,
                            size: 30,
                          ),
                        ),
                      if (hovered)
                        ColoredBox(
                          color: colors.primary.withValues(alpha: .45),
                          child: const Center(
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.displayName(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${context.l10n.photoCount(album.count)}${album.volume != 'external_primary' ? ' · SD' : ''}',
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
