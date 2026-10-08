import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/models/transfer_result.dart';

class FakeLibrary implements MediaLibrary {
  FakeLibrary({
    int photoCount = 90,
    int albumCount = 30,
    this.permission = 'full',
  }) {
    photos = List.generate(
      photoCount,
      (i) => Photo(
        id: 'p$i',
        name: 'IMG_$i.jpg',
        path: i % 13 == 12 ? 'Pictures/旅行/' : 'DCIM/Camera/',
        volume: 'external_primary',
        date: DateTime(2026, 10, 1).subtract(Duration(days: i ~/ 12)),
        width: 1600,
        height: 1200,
      ),
    );
    albums = List.generate(
      albumCount,
      (i) => Album(path: 'Pictures/相册 ${i.toString().padLeft(2, '0')}/'),
    );
  }
  final settings = AppSettings(tutorialSeen: true);
  String permission;
  late List<Photo> photos;
  late List<Album> albums;
  List<String>? transferred;
  Album? target;
  bool? copied;
  bool failTransfer = false;
  bool cancelTransfer = false;
  int saves = 0;
  final controller = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => controller.stream;
  @override
  Future<AppSettings> loadSettings() async => settings;
  @override
  Future<void> saveSettings(AppSettings settings) async {
    saves++;
  }

  @override
  Future<String> requestPermission() async => permission;
  @override
  Future<bool> requestLocation() async => true;
  @override
  Future<void> openSettings() async {}
  @override
  Future<int> rescanPhotos() async => 0;
  @override
  Future<String?> reverseGeocode(
    double latitude,
    double longitude, {
    String? locale,
  }) async => null;
  @override
  Future<void> openMap(
    double latitude,
    double longitude,
    String provider, {
    String? label,
  }) async {}
  @override
  Future<LibrarySnapshot> load() async => LibrarySnapshot(
    photos: permission == 'denied' ? [] : photos,
    emptyAlbums: albums,
    permission: permission,
  );
  @override
  Future<Uint8List?> thumbnail(String id, int size) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  @override
  Future<Map<Object?, Object?>> details(String id, bool location) async => {
    'latitude': 31.2304,
    'longitude': 121.4737,
  };
  @override
  Future<void> createAlbum(String name) async {
    albums.add(Album(path: 'Pictures/$name/'));
  }

  @override
  Future<TransferResult> transfer(
    List<String> ids,
    Album album,
    bool copy,
  ) async {
    transferred = ids;
    target = album;
    copied = copy;
    if (cancelTransfer) return const TransferResult(cancelled: true);
    return TransferResult(
      successfulIds: failTransfer ? ids.take(1).toList() : ids,
      failures: failTransfer
          ? ids
                .skip(1)
                .map((id) => TransferFailure(photoId: id, reason: '测试写入失败'))
                .toList()
          : [],
    );
  }
}
