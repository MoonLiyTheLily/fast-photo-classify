import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';

import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/shared/photo_image.dart';

class AlbumPickerLabels {
  const AlbumPickerLabels({
    required this.selected,
    required this.unselected,
    required this.selectAll,
    required this.clear,
    required this.emptySelection,
    required this.allSelected,
  });
  final String selected,
      unselected,
      selectAll,
      clear,
      emptySelection,
      allSelected;

  static AlbumPickerLabels scope(BuildContext context) => AlbumPickerLabels(
    selected: context.l10n.selected,
    unselected: context.l10n.unselected,
    selectAll: context.l10n.selectAll,
    clear: context.l10n.clear,
    emptySelection: context.l10n.emptyAlbumSelection,
    allSelected: context.l10n.allAlbumsSelected,
  );
  static AlbumPickerLabels classification(BuildContext context) =>
      AlbumPickerLabels(
        selected: context.l10n.organized,
        unselected: context.l10n.unorganized,
        selectAll: context.l10n.organizeAll,
        clear: context.l10n.unorganizeAll,
        emptySelection: context.l10n.emptyClassification,
        allSelected: context.l10n.allAlbumsOrganized,
      );
}

/// Presentation only: shelves, search results and cards. The caller supplies
/// selection state and actions; no source/target/classification rules live here.
class AlbumPicker extends StatelessWidget {
  const AlbumPicker({
    super.key,
    required this.pickerId,
    required this.albums,
    required this.selectedKeys,
    this.includesAll = false,
    required this.labels,
    required this.searchQuery,
    required this.cache,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    required this.onRemoveUnavailable,
    this.filterAction,
  });
  final String pickerId;
  final List<Album> albums;
  final Set<String> selectedKeys;
  final bool includesAll;
  final AlbumPickerLabels labels;
  final String searchQuery;
  final ThumbnailCache cache;
  final ValueChanged<Album> onToggle;
  final VoidCallback onSelectAll, onClear;
  final ValueChanged<String> onRemoveUnavailable;
  final Widget? filterAction;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final chosen = albums
        .where((album) => includesAll || selectedKeys.contains(album.key))
        .toList();
    final chosenKeys = chosen.map((album) => album.key).toSet();
    final remaining = albums
        .where(
          (album) =>
              (keyboard || !chosenKeys.contains(album.key)) &&
              album.searchText.contains(searchQuery),
        )
        .toList();
    final shownChosen = chosen
        .where((album) => album.searchText.contains(searchQuery))
        .toList();
    final availableKeys = albums.map((album) => album.key).toSet();
    final missing = selectedKeys.difference(availableKeys);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!keyboard) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${labels.selected} · ${chosen.length}${includesAll ? context.l10n.allAlbumsSuffix : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: onSelectAll,
                    child: Text(
                      labels.selectAll,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: onClear,
                    child: Text(
                      labels.clear,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (chosen.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(
                labels.emptySelection,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            SizedBox(
              height: 116,
              child: ListView.separated(
                key: ValueKey('selected-albums-$pickerId'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: shownChosen.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                  width: 100,
                  child: _card(context, shownChosen[i], true),
                ),
              ),
            ),
          if (missing.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final key in missing)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(
                          context.l10n.unavailableAlbum(key.split('|').last),
                        ),
                        onDeleted: () => onRemoveUnavailable(key),
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (!keyboard)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Text(
                  '${labels.unselected} · ${remaining.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                ?filterAction,
              ],
            ),
          ),
        Expanded(
          child: remaining.isEmpty
              ? Center(
                  child: Text(
                    searchQuery.isNotEmpty
                        ? context.l10n.noMatchingAlbums
                        : labels.allSelected,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    key: ValueKey('remaining-albums-$pickerId'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (constraints.maxWidth / 118)
                          .floor()
                          .clamp(2, 4),
                      mainAxisExtent: 134,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: remaining.length,
                    itemBuilder: (_, i) => _card(
                      context,
                      remaining[i],
                      chosenKeys.contains(remaining[i].key),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Album album, bool selected) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.albumSelectionSemantics(
        album.displayName(context.l10n),
        selected ? labels.selected : labels.unselected,
        album.path,
      ),
      child: InkWell(
        key: ValueKey('scope-$pickerId-${album.key}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => onToggle(album),
        onLongPress: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(album.displayName(context.l10n)),
            content: SelectableText(
              '${album.path}\n${album.volume == 'external_primary' ? context.l10n.internalStorage : album.volume}\n${context.l10n.photoCountFull(album.count)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.close),
              ),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: selected
                      ? Border.all(color: colors.primary, width: 2)
                      : null,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (album.cover != null)
                      PhotoImage(photo: album.cover!, cache: cache)
                    else
                      Icon(
                        Icons.folder_outlined,
                        size: 30,
                        color: colors.primary,
                      ),
                    Positioned(
                      right: 5,
                      top: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primary
                              : colors.surface.withValues(alpha: .85),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            selected ? Icons.check : Icons.add,
                            size: 16,
                            color: selected
                                ? colors.onPrimary
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              album.displayName(context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              '${context.l10n.photoCount(album.count)}${album.volume == 'external_primary' ? '' : ' · SD'}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
