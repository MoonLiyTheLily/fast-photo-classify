import 'dart:async';

import 'package:flutter/services.dart';

import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/models/transfer_result.dart';

abstract class MediaLibrary {
  Stream<void> get changes;
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<String> requestPermission();
  Future<bool> requestLocation();
  Future<void> openSettings();
  Future<LibrarySnapshot> load();
  Future<int> rescanPhotos();
  Future<Uint8List?> thumbnail(String id, int size);
  Future<Map<Object?, Object?>> details(String id, bool location);
  Future<String?> reverseGeocode(
    double latitude,
    double longitude, {
    String? locale,
  });
  Future<void> openMap(
    double latitude,
    double longitude,
    String provider, {
    String? label,
  });
  Future<void> createAlbum(String name);
  Future<TransferResult> transfer(List<String> ids, Album album, bool copy);
}

class AndroidMediaLibrary implements MediaLibrary {
  static const _channel = MethodChannel('app.fastphoto/media');
  static const _events = EventChannel('app.fastphoto/changes');
  @override
  Stream<void> get changes => _events.receiveBroadcastStream().map((_) {});
  @override
  Future<AppSettings> loadSettings() async => AppSettings.fromMap(
    await _channel.invokeMapMethod<Object?, Object?>('loadSettings') ?? {},
  );
  @override
  Future<void> saveSettings(AppSettings settings) =>
      _channel.invokeMethod('saveSettings', settings.toMap());
  @override
  Future<String> requestPermission() async =>
      await _channel.invokeMethod<String>('requestPermission') ?? 'denied';
  @override
  Future<bool> requestLocation() async =>
      await _channel.invokeMethod<bool>('requestLocation') ?? false;
  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
  @override
  Future<int> rescanPhotos() async =>
      await _channel.invokeMethod<int>('rescanPhotos') ?? 0;
  @override
  Future<LibrarySnapshot> load() async {
    final m =
        await _channel.invokeMapMethod<Object?, Object?>('loadLibrary') ?? {};
    return LibrarySnapshot(
      sortNames: (m['sortNames'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      permission: m['permission'] as String? ?? 'denied',
      photos: (m['photos'] as List? ?? [])
          .map((p) => Photo.fromMap(p as Map))
          .toList(),
      emptyAlbums: (m['albums'] as List? ?? [])
          .map(
            (a) => Album(
              path: (a as Map)['path'] as String,
              volume: a['volume'] as String,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<Uint8List?> thumbnail(String id, int size) =>
      _channel.invokeMethod<Uint8List>('thumbnail', {'id': id, 'size': size});
  @override
  Future<Map<Object?, Object?>> details(String id, bool location) async =>
      await _channel.invokeMapMethod<Object?, Object?>('details', {
        'id': id,
        'location': location,
      }) ??
      {};
  @override
  Future<void> createAlbum(String name) =>
      _channel.invokeMethod('createAlbum', {'name': name});
  @override
  Future<String?> reverseGeocode(
    double latitude,
    double longitude, {
    String? locale,
  }) => _channel.invokeMethod<String>('reverseGeocode', {
    'latitude': latitude,
    'longitude': longitude,
    'locale': ?locale,
  });
  @override
  Future<void> openMap(
    double latitude,
    double longitude,
    String provider, {
    String? label,
  }) => _channel.invokeMethod('openMap', {
    'latitude': latitude,
    'longitude': longitude,
    'provider': provider,
    'label': ?label,
  });
  @override
  Future<TransferResult> transfer(
    List<String> ids,
    Album album,
    bool copy,
  ) async => TransferResult.fromMap(
    await _channel.invokeMapMethod<Object?, Object?>('transfer', {
          'ids': ids,
          'path': album.path,
          'volume': album.volume,
          'copy': copy,
        }) ??
        {},
  );
}
