import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';

import 'package:fastphoto/models/app_settings.dart';

class AlbumSortControl extends StatelessWidget {
  const AlbumSortControl({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final AlbumSort value;
  final ValueChanged<AlbumSort> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<AlbumSort>(
      key: const ValueKey('album-sort'),
      value: value,
      isDense: true,
      isExpanded: true,
      items: [
        DropdownMenuItem(
          value: AlbumSort.smart,
          child: Text(
            context.l10n.sortSmart,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownMenuItem(
          value: AlbumSort.recent,
          child: Text(
            context.l10n.sortRecent,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}
