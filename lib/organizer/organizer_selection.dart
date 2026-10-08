import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';

enum AlbumScope { source, target }

/// Source and target scopes share the same all-or-explicit-keys rule.
/// This editor writes only to the sheet's draft, never the active settings.
class AlbumScopeEditor {
  AlbumScopeEditor(this.draft, this.scope);

  final AppSettings draft;
  final AlbumScope scope;

  bool get includesAll => switch (scope) {
    AlbumScope.source => draft.sourceAll,
    AlbumScope.target => draft.targetAll,
  };
  List<String> get selectedKeys => switch (scope) {
    AlbumScope.source => draft.sourceKeys,
    AlbumScope.target => draft.targetKeys,
  };

  void _setIncludesAll(bool value) {
    switch (scope) {
      case AlbumScope.source:
        draft.sourceAll = value;
      case AlbumScope.target:
        draft.targetAll = value;
    }
  }

  void toggle(Album album, List<Album> availableAlbums) {
    if (includesAll) {
      _setIncludesAll(false);
      selectedKeys
        ..clear()
        ..addAll(
          availableAlbums
              .where((other) => other.key != album.key)
              .map((other) => other.key),
        );
    } else if (!selectedKeys.remove(album.key)) {
      selectedKeys.add(album.key);
    }
  }

  void selectAll() {
    _setIncludesAll(true);
    selectedKeys.clear();
  }

  void clear() {
    _setIncludesAll(false);
    selectedKeys.clear();
  }

  void removeUnavailable(String key) => selectedKeys.remove(key);
}

/// Classification is an explicit rule, independent of source/target scope.
/// "全部归类" marks today's albums; future albums still start unclassified.
class AlbumClassificationEditor {
  AlbumClassificationEditor(this.draft);

  final AppSettings draft;
  Set<String> get organizedKeys =>
      draft.albumRules.keys.where(draft.albumOrganized).toSet();

  void toggle(Album album) {
    if (draft.albumOrganized(album.key)) {
      draft.albumRules.remove(album.key);
    } else {
      draft.albumRules[album.key] = true;
    }
  }

  void classifyAll(Iterable<Album> albums) {
    draft.albumRules
      ..clear()
      ..addEntries(albums.map((album) => MapEntry(album.key, true)));
  }

  void clear() => draft.albumRules.clear();
  void removeUnavailable(String key) => draft.albumRules.remove(key);
}
