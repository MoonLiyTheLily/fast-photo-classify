import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/gallery/selection_state.dart';
import 'package:fastphoto/models/transfer_result.dart';

/// Only one gallery gesture can own the photo grid at a time.
enum GalleryInteraction { idle, sweeping, dragging }

String describeGalleryError(Object error) => switch (error) {
  PlatformException() => error.message ?? 'operationIncomplete',
  StateError() => error.message,
  _ => 'operationRetry',
};

/// Owns photo data, filtering, transfers and the refresh queue. The page owns
/// coordinates, animations, navigation and selection-mode presentation.
/// Selection has its own per-photo listeners: sweeping never notifies this
/// controller, so changing a selection does not rebuild the whole gallery.
class GalleryController extends ChangeNotifier {
  GalleryController({
    required this.library,
    required this.settings,
    required this.onNotice,
  }) {
    _changes = library.changes.listen((_) => requestReload(), onError: (_) {});
  }

  final MediaLibrary library;
  final AppSettings settings;
  final ValueChanged<String> onNotice;
  final selection = PhotoSelection();
  late final StreamSubscription<void> _changes;
  bool _disposed = false;

  LibrarySnapshot _snapshot = const LibrarySnapshot();
  LibrarySnapshot get snapshot => _snapshot;
  List<Album> _albums = [];
  List<Album> _browseAlbums = [];
  List<Album> _destinationAlbums = [];
  List<Photo> _visiblePhotos = [];
  Map<String, Photo> _photosById = {};
  Map<String, int> _visibleIndices = {};
  Set<String> _organizedIds = {};
  int _unorganizedCount = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isTransferring = false;
  String? _loadError;

  List<Album> get albums => _albums;
  List<Album> get browseAlbums => _browseAlbums;
  List<Album> get destinationAlbums => _destinationAlbums;
  List<Photo> get visiblePhotos => _visiblePhotos;
  Map<String, Photo> get photosById => _photosById;
  Map<String, int> get visibleIndices => _visibleIndices;
  Set<String> get organizedIds => _organizedIds;
  int get unorganizedCount => _unorganizedCount;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isTransferring => _isTransferring;
  String? get loadError => _loadError;

  PhotoFilter _filter = PhotoFilter.all;
  PhotoFilter get filter => _filter;
  String? _browsedAlbumKey;
  String? get browsedAlbumKey => _browsedAlbumKey;

  GalleryInteraction _interaction = GalleryInteraction.idle;
  GalleryInteraction get interaction => _interaction;
  bool _previewOpen = false;
  bool get isPreviewOpen => _previewOpen;

  // This is the single policy for when an incoming snapshot may replace data.
  bool get _canRefresh =>
      _interaction == GalleryInteraction.idle &&
      !_previewOpen &&
      !_isTransferring;
  bool _reloadRequested = false;
  bool _scanRequested = false;
  Future<void>? _refreshTask;

  Future<void> initialize() async {
    await requestReload();
    if (!_disposed && snapshot.accessible) await refreshFromStorage();
  }

  void setInteraction(GalleryInteraction interaction) {
    _interaction = interaction;
    _resumeRefresh();
  }

  void setPreviewOpen(bool open) {
    _previewOpen = open;
    _resumeRefresh();
  }

  Future<void> refreshFromStorage() {
    _scanRequested = true;
    return requestReload();
  }

  /// Coalesces requests from storage events, lifecycle changes and actions.
  /// While interacting, requests stay pending instead of replacing the grid.
  Future<void> requestReload() {
    if (_disposed) return Future.value();
    _reloadRequested = true;
    return _resumeRefresh();
  }

  Future<void> _resumeRefresh() {
    if (_disposed || !_canRefresh || !_reloadRequested) return Future.value();
    if (_refreshTask != null) return _refreshTask!;
    final completion = Completer<void>();
    _refreshTask = completion.future;
    _drainRefreshQueue().whenComplete(() {
      _refreshTask = null;
      completion.complete();
      _resumeRefresh();
    });
    return completion.future;
  }

  Future<void> _drainRefreshQueue() async {
    while (!_disposed && _canRefresh && _reloadRequested) {
      _reloadRequested = false;
      final scanFirst = _scanRequested;
      _scanRequested = false;
      if (scanFirst) {
        _isRefreshing = true;
        notifyListeners();
        try {
          await library.rescanPhotos();
        } catch (error) {
          if (!_disposed) onNotice(describeGalleryError(error));
        }
      }
      try {
        if (_disposed) return;
        final fresh = await library.load();
        if (_disposed) return;
        if (!_canRefresh) {
          // A gesture or preview may have started while the query was running.
          _reloadRequested = true;
          continue;
        }
        _snapshot = fresh;
        _albums = fresh.albums;
        if (_browsedAlbumKey != null &&
            !_albums.any((album) => album.key == _browsedAlbumKey)) {
          _browsedAlbumKey = null;
        }
        _deriveView();
        selection.removeWhere((id) => !_photosById.containsKey(id));
        _isLoading = false;
        _loadError = null;
      } catch (error) {
        if (_disposed) return;
        if (!_canRefresh) {
          _reloadRequested = true;
          continue;
        }
        _isLoading = false;
        _loadError = describeGalleryError(error);
      } finally {
        _isRefreshing = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void _deriveView() {
    _photosById = {for (final photo in snapshot.photos) photo.id: photo};
    _organizedIds = snapshot.photos
        .where(settings.isOrganized)
        .map((photo) => photo.id)
        .toSet();
    final sourceKeys = settings.sourceKeys.toSet();
    bool isPending(Photo photo) =>
        (settings.sourceAll || sourceKeys.contains(photo.albumKey)) &&
        !_organizedIds.contains(photo.id);
    _unorganizedCount = snapshot.photos.where(isPending).length;
    _destinationAlbums = settings.destinations(_albums);
    _browseAlbums = settings.sortedAlbums(_albums);
    _visiblePhotos = snapshot.photos.where((photo) {
      if (_browsedAlbumKey != null) return photo.albumKey == _browsedAlbumKey;
      return switch (_filter) {
        PhotoFilter.all => true,
        PhotoFilter.unorganized => isPending(photo),
        PhotoFilter.organized => _organizedIds.contains(photo.id),
      };
    }).toList();
    _visibleIndices = {
      for (var index = 0; index < _visiblePhotos.length; index++)
        _visiblePhotos[index].id: index,
    };
  }

  void showFilter(PhotoFilter filter) {
    _filter = filter;
    _browsedAlbumKey = null;
    _updateView();
  }

  void browseAlbum(Album album) {
    _browsedAlbumKey = album.key;
    _updateView();
  }

  void closeAlbum() {
    _browsedAlbumKey = null;
    _updateView();
  }

  void _updateView() {
    _deriveView();
    notifyListeners();
  }

  Future<void> settingsChanged() async {
    _updateView();
    await saveSettings();
  }

  Future<void> saveSettings() async {
    try {
      await library.saveSettings(settings);
    } catch (_) {
      if (!_disposed) onNotice('settingsSaveFailed');
    }
  }

  Future<void> applyOrganizerSettings(AppSettings draft) {
    settings.sourceKeys = List.of(draft.sourceKeys);
    settings.targetKeys = List.of(draft.targetKeys);
    settings.sourceAll = draft.sourceAll;
    settings.targetAll = draft.targetAll;
    settings.albumRules = Map.of(draft.albumRules);
    settings.albumSort = draft.albumSort;
    settings.hideTechnical = draft.hideTechnical;
    settings.excludedTargets = List.of(draft.excludedTargets);
    settings.plans = List.of(draft.plans);
    selection.clear();
    return settingsChanged();
  }

  Future<void> requestPermission() async {
    await library.requestPermission();
    if (!_disposed) await refreshFromStorage();
  }

  Future<void> createAlbum(String name) async {
    await library.createAlbum(name);
    if (_disposed) return;
    if (!settings.targetAll) {
      final key = 'external_primary|Pictures/$name/';
      if (!settings.targetKeys.contains(key)) settings.targetKeys.add(key);
      await saveSettings();
    }
    await requestReload();
  }

  Future<TransferResult?> transferSelectionTo(Album album) async {
    if (selection.isEmpty || _isTransferring || _disposed) return null;
    if (!album.isSupportedDestination) {
      throw StateError('unsupportedDestination');
    }
    _isTransferring = true;
    notifyListeners();
    try {
      final result = await library.transfer(
        selection.toList(),
        album,
        settings.copy,
      );
      if (_disposed) return result;
      selection.removeAll([...result.successfulIds, ...result.skippedIds]);
      if (result.successfulIds.isNotEmpty) {
        settings.recentTargets[album.key] =
            DateTime.now().millisecondsSinceEpoch;
        await saveSettings();
      }
      return result;
    } finally {
      _isTransferring = false;
      if (!_disposed) {
        notifyListeners();
        await requestReload();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _changes.cancel();
    selection.dispose();
    super.dispose();
  }
}
