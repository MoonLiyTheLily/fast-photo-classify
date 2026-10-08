class Photo {
  const Photo({
    required this.id,
    required this.name,
    required this.path,
    required this.volume,
    required this.date,
    this.width = 0,
    this.height = 0,
    this.rotation = 0,
    this.size = 0,
    this.copyAlbums = const [],
    this.copyAlbumKeys = const [],
    this.modified = 0,
  });
  factory Photo.fromMap(Map<Object?, Object?> m) => Photo(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    path: m['path'] as String? ?? '',
    volume: m['volume'] as String? ?? 'external_primary',
    date: DateTime.fromMillisecondsSinceEpoch(
      (m['date'] as num?)?.toInt() ?? 0,
    ),
    width: (m['width'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    rotation: (m['rotation'] as num?)?.toInt() ?? 0,
    size: (m['size'] as num?)?.toInt() ?? 0,
    copyAlbums: (m['copyAlbums'] as List?)?.cast<String>() ?? const [],
    copyAlbumKeys: (m['copyAlbumKeys'] as List?)?.cast<String>() ?? const [],
    modified: (m['modified'] as num?)?.toInt() ?? 0,
  );
  final String id, name, path, volume;
  final DateTime date;
  final int width, height, rotation, size, modified;

  /// MediaStore dimensions describe stored pixels; decoded images apply EXIF
  /// rotation. Use the displayed ratio when sizing a preview or transition.
  double? get displayAspectRatio {
    if (width <= 0 || height <= 0) return null;
    return rotation % 180 == 90 ? height / width : width / height;
  }

  final List<String> copyAlbums, copyAlbumKeys;
  String get albumKey => '$volume|$path';
  String get albumName =>
      path.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
}

class Album {
  const Album({
    required this.path,
    this.volume = 'external_primary',
    this.count = 0,
    this.cover,
    this.updated = 0,
    this.sortName = '',
  });
  final String path, volume;
  final int count, updated;
  final String sortName;
  final Photo? cover;
  String get key => '$volume|$path';
  String get name =>
      path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
  bool get technical =>
      RegExp(r'^[a-zA-Z][\w]*(\.[\w-]+){2,}$').hasMatch(name) ||
      path.toLowerCase().contains('android/data/');
  bool get chinese => RegExp(r'[\u3400-\u9fff]').hasMatch(name);
  String get searchText => '$name $path $sortName'.toLowerCase();

  /// Mirrors MediaBridge's destination-directory restriction. Other albums
  /// remain readable and can still be sources or have classification rules.
  bool get isSupportedDestination =>
      path.endsWith('/') &&
      (path.startsWith('Pictures/') || path.startsWith('DCIM/')) &&
      !path.contains('\\') &&
      !path.split('/').any((part) => part == '.' || part == '..');
}

class LibrarySnapshot {
  const LibrarySnapshot({
    this.photos = const [],
    this.emptyAlbums = const [],
    this.permission = 'denied',
    this.sortNames = const {},
  });
  final List<Photo> photos;
  final List<Album> emptyAlbums;
  final String permission;
  final Map<String, String> sortNames;
  bool get accessible => permission == 'full' || permission == 'limited';
  List<Album> get albums {
    final grouped = <String, List<Photo>>{};
    for (final p in photos) {
      (grouped[p.albumKey] ??= []).add(p);
    }
    final result = <String, Album>{
      for (final a in emptyAlbums)
        a.key: Album(
          path: a.path,
          volume: a.volume,
          count: a.count,
          cover: a.cover,
          updated: a.updated,
          sortName:
              sortNames[a.name] ?? (a.sortName.isEmpty ? a.name : a.sortName),
        ),
    };
    for (final g in grouped.values) {
      result[g.first.albumKey] = Album(
        path: g.first.path,
        volume: g.first.volume,
        count: g.length,
        cover: g.first,
        updated: g.fold<int>(0, (v, p) => p.modified > v ? p.modified : v),
        sortName: sortNames[g.first.albumName] ?? g.first.albumName,
      );
    }
    return result.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
