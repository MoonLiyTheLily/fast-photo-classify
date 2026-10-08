import 'package:flutter/material.dart';
import 'package:fastphoto/models/media_models.dart';

enum TrayEdge { bottom, left, right, top }

enum PhotoFilter { all, unorganized, organized }

enum AlbumSort { smart, recent }

enum AppLanguage { system, chinese, english }

class AppSettings {
  AppSettings({
    this.theme = ThemeMode.system,
    this.language = AppLanguage.system,
    this.edge = TrayEdge.bottom,
    this.albumColumns = 3,
    this.photoColumns = 3,
    this.groupByDate = true,
    this.showLocation = false,
    this.copy = false,
    this.resolveAddress = true,
    List<String>? sourceKeys,
    List<String>? targetKeys,
    Map<String, bool>? albumRules,
    this.albumSort = AlbumSort.smart,
    this.hideTechnical = false,
    List<String>? excludedTargets,
    Map<String, int>? recentTargets,
    List<SortPlan>? plans,
    bool? sourceAll,
    bool? targetAll,
    this.tutorialSeen = false,
  }) : sourceKeys = sourceKeys ?? [],
       targetKeys = targetKeys ?? [],
       albumRules = albumRules ?? {},
       excludedTargets = excludedTargets ?? [],
       recentTargets = recentTargets ?? {},
       plans = plans ?? [],
       sourceAll = sourceAll ?? (sourceKeys?.isEmpty ?? true),
       targetAll = targetAll ?? (targetKeys?.isEmpty ?? true);
  ThemeMode theme;
  AppLanguage language;
  Locale? get locale => switch (language) {
    AppLanguage.system => null,
    AppLanguage.chinese => const Locale('zh'),
    AppLanguage.english => const Locale('en'),
  };
  TrayEdge edge;
  int albumColumns, photoColumns;
  bool groupByDate, showLocation, copy;
  bool sourceAll, targetAll, tutorialSeen;
  bool resolveAddress, hideTechnical;
  List<String> sourceKeys, targetKeys, excludedTargets;
  Map<String, bool> albumRules;
  Map<String, int> recentTargets;
  AlbumSort albumSort;
  List<SortPlan> plans;
  List<SortPlan> get availablePlans => [SortPlan.defaultPlan(), ...plans];

  bool albumOrganized(String key) {
    return albumRules[key] == true;
  }

  bool isOrganized(Photo p) =>
      albumOrganized(p.albumKey) ||
      (p.copyAlbumKeys.isNotEmpty
          ? p.copyAlbumKeys.any(albumOrganized)
          : p.copyAlbums.any((path) => albumOrganized('${p.volume}|$path')));

  List<Album> destinations(List<Album> albums) {
    final targets = targetKeys.toSet();
    return sortedAlbums(
      albums
          .where(
            (a) =>
                a.isSupportedDestination &&
                (targetAll || targets.contains(a.key)) &&
                !excludedTargets.contains(a.key) &&
                !(hideTechnical && a.technical),
          )
          .toList(),
    );
  }

  List<Album> sortedAlbums(Iterable<Album> albums) {
    final result = albums.toList();
    result.sort((a, b) {
      if (a.technical != b.technical) return a.technical ? 1 : -1;
      if (albumSort == AlbumSort.recent) {
        final am = recentTargets[a.key] ?? 0, bm = recentTargets[b.key] ?? 0;
        final cmp = (bm > b.updated ? bm : b.updated).compareTo(
          am > a.updated ? am : a.updated,
        );
        if (cmp != 0) return cmp;
      }
      if (a.chinese != b.chinese) return a.chinese ? -1 : 1;
      final cmp = (a.sortName.isEmpty ? a.name : a.sortName)
          .toLowerCase()
          .compareTo((b.sortName.isEmpty ? b.name : b.sortName).toLowerCase());
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    return result;
  }

  SortPlan capturePlan(String name) => SortPlan(
    name: name,
    sources: List.of(sourceKeys),
    targets: List.of(targetKeys),
    sort: albumSort,
    hideTechnical: hideTechnical,
    excluded: List.of(excludedTargets),
    sourceAll: sourceAll,
    targetAll: targetAll,
  );
  void applyPlan(SortPlan plan) {
    sourceKeys = List.of(plan.sources);
    targetKeys = List.of(plan.targets);
    sourceAll = plan.sourceAll;
    targetAll = plan.targetAll;
    albumSort = plan.sort;
    hideTechnical = plan.hideTechnical;
    excludedTargets = List.of(plan.excluded);
  }

  factory AppSettings.fromMap(Map<Object?, Object?> m) => AppSettings(
    language: AppLanguage.values.firstWhere(
      (e) => e.name == m['language'],
      orElse: () => AppLanguage.system,
    ),
    theme: ThemeMode.values.firstWhere(
      (e) => e.name == m['theme'],
      orElse: () => ThemeMode.system,
    ),
    edge: TrayEdge.values.firstWhere(
      (e) => e.name == m['edge'],
      orElse: () => TrayEdge.bottom,
    ),
    albumColumns: ((m['albumColumns'] as num?)?.toInt() ?? 3).clamp(2, 4),
    photoColumns: ((m['photoColumns'] as num?)?.toInt() ?? 3).clamp(2, 6),
    groupByDate: m['groupByDate'] != false,
    showLocation: m['showLocation'] == true,
    copy: m['copy'] == true,
    sourceAll: m['sourceAll'] as bool? ?? _strings(m['sourceKeys']).isEmpty,
    targetAll: m['targetAll'] as bool? ?? _strings(m['targetKeys']).isEmpty,
    tutorialSeen: m['tutorialSeen'] == true,
    resolveAddress: m['resolveAddress'] != false,
    sourceKeys: _strings(m['sourceKeys']),
    targetKeys: _strings(m['targetKeys']),
    excludedTargets: _strings(m['excludedTargets']),
    albumRules: (m['albumRules'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), v == true),
    ),
    recentTargets: (m['recentTargets'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    ),
    albumSort: AlbumSort.values.firstWhere(
      (e) => e.name == m['albumSort'],
      orElse: () => AlbumSort.smart,
    ),
    hideTechnical: m['hideTechnical'] == true,
    plans: (m['plans'] as List? ?? [])
        .map((e) => SortPlan.fromMap(e as Map))
        .toList(),
  );
  Map<String, Object> toMap() => {
    'language': language.name,
    'theme': theme.name,
    'edge': edge.name,
    'albumColumns': albumColumns,
    'photoColumns': photoColumns,
    'groupByDate': groupByDate,
    'showLocation': showLocation,
    'copy': copy,
    'sourceAll': sourceAll,
    'targetAll': targetAll,
    'tutorialSeen': tutorialSeen,
    'resolveAddress': resolveAddress,
    'sourceKeys': sourceKeys,
    'targetKeys': targetKeys,
    'albumRules': albumRules,
    'albumSort': albumSort.name,
    'hideTechnical': hideTechnical,
    'excludedTargets': excludedTargets,
    'recentTargets': recentTargets,
    'plans': plans.map((p) => p.toMap()).toList(),
  };
}

List<String> _strings(Object? value) =>
    (value as List? ?? []).cast<String>().toSet().toList();

class SortPlan {
  SortPlan({
    required this.name,
    required this.sources,
    required this.targets,
    this.sort = AlbumSort.smart,
    this.hideTechnical = false,
    this.excluded = const [],
    int? time,
    bool? sourceAll,
    bool? targetAll,
    this.builtin = false,
  }) : time = time ?? DateTime.now().millisecondsSinceEpoch,
       sourceAll = sourceAll ?? sources.isEmpty,
       targetAll = targetAll ?? targets.isEmpty;
  factory SortPlan.defaultPlan() => SortPlan(
    // Keep the legacy internal name; the UI localizes this built-in plan.
    name: '默认方案',
    sources: const [],
    targets: const [],
    time: 0,
    builtin: true,
  );
  final String name;
  final List<String> sources, targets, excluded;
  final AlbumSort sort;
  final bool hideTechnical;
  final bool sourceAll, targetAll, builtin;
  final int time;
  String get signature =>
      '${sources.join(';')}|${targets.join(';')}|${sort.name}|$hideTechnical|${excluded.join(';')}';
  factory SortPlan.fromMap(Map m) => SortPlan(
    name: m['name'] as String? ?? '',
    sources: _strings(m['sources']),
    targets: _strings(m['targets']),
    excluded: _strings(m['excluded']),
    sort: AlbumSort.values.firstWhere(
      (e) => e.name == m['sort'],
      orElse: () => AlbumSort.smart,
    ),
    hideTechnical: m['hideTechnical'] == true,
    time: (m['time'] as num?)?.toInt() ?? 0,
    sourceAll: m['sourceAll'] as bool?,
    targetAll: m['targetAll'] as bool?,
  );
  Map<String, Object> toMap() => {
    'name': name,
    'sources': sources,
    'targets': targets,
    'sort': sort.name,
    'hideTechnical': hideTechnical,
    'excluded': excluded,
    'time': time,
    'sourceAll': sourceAll,
    'targetAll': targetAll,
  };
}
