import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';

import 'package:fastphoto/organizer/album_sort_control.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/organizer/album_picker.dart';
import 'package:fastphoto/organizer/organizer_selection.dart';

enum OrganizerTab { source, target, classification, plans }

/// Editing a scope never changes the gallery's independent album browser.
class OrganizerSheet extends StatefulWidget {
  const OrganizerSheet({
    super.key,
    required this.settings,
    required this.albums,
    required this.cache,
    this.initialTab = OrganizerTab.source,
  });
  final AppSettings settings;
  final List<Album> albums;
  final ThumbnailCache cache;
  final OrganizerTab initialTab;
  @override
  State<OrganizerSheet> createState() => _OrganizerSheetState();
}

class _OrganizerSheetState extends State<OrganizerSheet>
    with SingleTickerProviderStateMixin {
  late final draft = AppSettings.fromMap(widget.settings.toMap());
  late final tabs = TabController(
    length: OrganizerTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );
  String query = '';
  bool get keyboardOpen => MediaQuery.viewInsetsOf(context).bottom > 0;
  @override
  void initState() {
    super.initState();
    tabs.addListener(_tabChanged);
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  bool get valid =>
      (draft.sourceAll || draft.sourceKeys.isNotEmpty) &&
      (draft.targetAll || draft.targetKeys.isNotEmpty);
  String _names(List<String> keys, bool all) => all
      ? context.l10n.allAlbums
      : keys
            .map(
              (key) =>
                  widget.albums
                      .where((a) => a.key == key)
                      .firstOrNull
                      ?.displayName(context.l10n) ??
                  key.split('|').last,
            )
            .join(context.l10n.listSeparator);
  void _apply() {
    if (valid) Navigator.pop(context, draft);
  }

  Future<void> _savePlan() async {
    if (!valid) return;
    final input = TextEditingController();
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.l10n.saveOrganizingPlan),
          content: TextField(
            controller: input,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(
              hintText: context.l10n.planNameHint,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = input.text.trim();
                if (value.isEmpty ||
                    value == context.l10n.defaultPlan ||
                    value == SortPlan.defaultPlan().name ||
                    draft.plans.any((p) => p.name == value)) {
                  update(() => error = context.l10n.invalidPlanName);
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(context.l10n.saveAndApply),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
    if (name != null && mounted) {
      draft.plans.add(draft.capturePlan(name));
      _apply();
    }
  }

  Widget _scopePicker(AlbumScope scope) {
    final editor = AlbumScopeEditor(draft, scope);
    final eligibleAlbums = scope == AlbumScope.target
        ? widget.albums.where((album) => album.isSupportedDestination).toList()
        : widget.albums;
    return AlbumPicker(
      pickerId: scope.name,
      albums: draft.sortedAlbums(eligibleAlbums),
      selectedKeys: editor.selectedKeys.toSet(),
      includesAll: editor.includesAll,
      labels: AlbumPickerLabels.scope(context),
      searchQuery: query,
      cache: widget.cache,
      onToggle: (album) => setState(() => editor.toggle(album, eligibleAlbums)),
      onSelectAll: () => setState(editor.selectAll),
      onClear: () => setState(editor.clear),
      onRemoveUnavailable: (key) =>
          setState(() => editor.removeUnavailable(key)),
      filterAction: scope == AlbumScope.target ? _targetFilters() : null,
    );
  }

  Widget _classificationPicker() {
    final editor = AlbumClassificationEditor(draft);
    return AlbumPicker(
      pickerId: 'classification',
      albums: draft.sortedAlbums(widget.albums),
      selectedKeys: editor.organizedKeys,
      labels: AlbumPickerLabels.classification(context),
      searchQuery: query,
      cache: widget.cache,
      onToggle: (album) => setState(() => editor.toggle(album)),
      onSelectAll: () => setState(() => editor.classifyAll(widget.albums)),
      onClear: () => setState(editor.clear),
      onRemoveUnavailable: (key) =>
          setState(() => editor.removeUnavailable(key)),
    );
  }

  Widget _targetFilters() => PopupMenuButton<String>(
    tooltip: context.l10n.targetFilter,
    icon: const Icon(Icons.filter_list, size: 21),
    onSelected: (value) => setState(() {
      if (value == 'packages') {
        draft.hideTechnical = !draft.hideTechnical;
      } else {
        draft.excludedTargets.clear();
      }
    }),
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        value: 'packages',
        checked: draft.hideTechnical,
        child: Text(context.l10n.hideTechnicalTargets),
      ),
      if (draft.excludedTargets.isNotEmpty)
        PopupMenuItem(
          value: 'restore',
          child: Text(
            context.l10n.restoreTargets(draft.excludedTargets.length),
          ),
        ),
    ],
  );

  Widget _plans() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(context.l10n.planCreationHint, style: TextStyle(fontSize: 13)),
      const SizedBox(height: 12),
      for (final plan in draft.availablePlans)
        Card(
          child: ListTile(
            key: plan.builtin
                ? const ValueKey('default-plan')
                : ValueKey('plan-${plan.name}'),
            leading: Icon(
              plan.builtin ? Icons.home_outlined : Icons.bookmark_outline,
            ),
            title: Text(plan.displayName(context.l10n)),
            subtitle: Text(
              '${_names(plan.sources, plan.sourceAll)} → ${_names(plan.targets, plan.targetAll)}',
            ),
            onTap: () {
              draft.applyPlan(plan);
              _apply();
            },
            trailing: plan.builtin
                ? Tooltip(
                    message: context.l10n.defaultPlanLocked,
                    child: Icon(Icons.lock_outline, size: 18),
                  )
                : IconButton(
                    tooltip: context.l10n.deletePlan,
                    onPressed: () => setState(() => draft.plans.remove(plan)),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: valid ? _savePlan : null,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(context.l10n.saveCurrentScope),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      children: [
        if (!keyboardOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.organizerTitle,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.closeOrganizer,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        TabBar(
          controller: tabs,
          tabs: [
            Tab(text: context.l10n.sourceAlbums),
            Tab(text: context.l10n.targetAlbums),
            Tab(text: context.l10n.classificationRules),
            Tab(text: context.l10n.plans),
          ],
        ),
        if (OrganizerTab.values[tabs.index] != OrganizerTab.plans &&
            !keyboardOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.sort, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: AlbumSortControl(
                    value: draft.albumSort,
                    onChanged: (v) => setState(() => draft.albumSort = v),
                  ),
                ),
              ],
            ),
          ),
        if (OrganizerTab.values[tabs.index] != OrganizerTab.plans)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: context.l10n.albumSearchHint,
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              _scopePicker(AlbumScope.source),
              _scopePicker(AlbumScope.target),
              _classificationPicker(),
              _plans(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valid
                        ? '${draft.sourceAll ? context.l10n.allSources : context.l10n.sourceCountShort(draft.sourceKeys.length)} → ${draft.targetAll ? context.l10n.allTargets : context.l10n.targetCountShort(draft.targetKeys.length)}'
                        : context.l10n.chooseSourcesAndTargets,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: valid ? _savePlan : null,
                  child: Text(context.l10n.savePlan),
                ),
                FilledButton(
                  key: const ValueKey('apply-scope'),
                  onPressed: valid ? _apply : null,
                  child: Text(context.l10n.apply),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
