import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';

import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/app_settings.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.settings,
    required this.library,
    required this.onChanged,
    this.onOrganize,
    this.onTutorial,
  });
  final AppSettings settings;
  final MediaLibrary library;
  final VoidCallback onChanged;
  final VoidCallback? onOrganize;
  final VoidCallback? onTutorial;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  AppSettings get s => widget.settings;
  void change(VoidCallback callback) {
    setState(callback);
    widget.onChanged();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.settingsTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: context.l10n.closeSettings,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _label(context.l10n.language),
          DropdownButtonFormField<AppLanguage>(
            key: const ValueKey('language-selector'),
            initialValue: s.language,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: AppLanguage.system,
                child: Text(context.l10n.followSystemLanguage),
              ),
              DropdownMenuItem(
                value: AppLanguage.chinese,
                child: Text(context.l10n.chineseLanguage),
              ),
              DropdownMenuItem(
                value: AppLanguage.english,
                child: Text(context.l10n.englishLanguage),
              ),
            ],
            onChanged: (value) {
              if (value != null) change(() => s.language = value);
            },
          ),
          const SizedBox(height: 24),
          _label(context.l10n.appearance),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(context.l10n.systemTheme),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(context.l10n.lightTheme),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(context.l10n.darkTheme),
              ),
            ],
            selected: {s.theme},
            onSelectionChanged: (v) => change(() => s.theme = v.first),
          ),
          const SizedBox(height: 24),
          _label(context.l10n.trayDirection),
          SegmentedButton<TrayEdge>(
            segments: [
              ButtonSegment(
                value: TrayEdge.bottom,
                label: Text(context.l10n.bottom),
                icon: Icon(Icons.vertical_align_bottom),
              ),
              ButtonSegment(
                value: TrayEdge.top,
                label: Text(context.l10n.top),
                icon: Icon(Icons.vertical_align_top),
              ),
              ButtonSegment(
                value: TrayEdge.left,
                label: Text(context.l10n.left),
                icon: Icon(Icons.align_horizontal_left),
              ),
              ButtonSegment(
                value: TrayEdge.right,
                label: Text(context.l10n.right),
                icon: Icon(Icons.align_horizontal_right),
              ),
            ],
            showSelectedIcon: false,
            selected: {s.edge},
            onSelectionChanged: (v) => change(() => s.edge = v.first),
          ),
          const SizedBox(height: 24),
          _label(context.l10n.albumDensity(s.albumColumns)),
          Slider(
            value: s.albumColumns.toDouble(),
            min: 2,
            max: 4,
            divisions: 2,
            label: context.l10n.columnCount(s.albumColumns),
            onChanged: (v) => change(() => s.albumColumns = v.round()),
          ),
          _label(context.l10n.photoDensity(s.photoColumns)),
          Slider(
            value: s.photoColumns.toDouble(),
            min: 2,
            max: 6,
            divisions: 4,
            label: context.l10n.columnCount(s.photoColumns),
            onChanged: (v) => change(() => s.photoColumns = v.round()),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.groupByDate),
            subtitle: Text(context.l10n.groupByDateHint),
            value: s.groupByDate,
            onChanged: (v) => change(() => s.groupByDate = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.showLocation),
            subtitle: Text(context.l10n.showLocationHint),
            value: s.showLocation,
            onChanged: (v) async {
              try {
                if (v && !await widget.library.requestLocation()) {
                  if (!context.mounted) return;
                  message(context.l10n.locationPermissionDenied);
                  return;
                }
                if (mounted) change(() => s.showLocation = v);
              } catch (_) {
                if (context.mounted) {
                  message(context.l10n.locationPermissionFailed);
                }
              }
            },
          ),
          const Divider(height: 32),
          _label(context.l10n.dropAction),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(context.l10n.move),
                icon: Icon(Icons.drive_file_move_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text(context.l10n.copy),
                icon: Icon(Icons.copy_outlined),
              ),
            ],
            selected: {s.copy},
            onSelectionChanged: (v) => change(() => s.copy = v.first),
          ),
          const SizedBox(height: 10),
          Text(
            s.copy
                ? context.l10n.copyDescription
                : context.l10n.moveDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (s.showLocation)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.resolveAddress),
              subtitle: Text(context.l10n.resolveAddressHint),
              value: s.resolveAddress,
              onChanged: (v) => change(() => s.resolveAddress = v),
            ),
          const SizedBox(height: 20),
          if (widget.onOrganize != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rule_folder_outlined),
              title: Text(context.l10n.organizerTitle),
              subtitle: Text(context.l10n.organizerHint),
              onTap: widget.onOrganize,
            ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.touch_app_outlined),
            title: Text(context.l10n.tutorial),
            onTap: widget.onTutorial,
            subtitle: Text(context.l10n.gestureHint),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.security_outlined),
            title: Text(context.l10n.photoAccess),
            subtitle: Text(context.l10n.photoAccessHint),
            onTap: () async {
              try {
                await widget.library.openSettings();
              } catch (_) {
                if (context.mounted) {
                  message(context.l10n.openSettingsFailed);
                }
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.privacyFooter(context.l10n.appName),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
