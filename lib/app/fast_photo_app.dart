import 'package:flutter/material.dart';
import 'package:fastphoto/gallery/gallery_page.dart';
import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/app/app_theme.dart';
import 'package:fastphoto/app/app_name.dart';
import 'package:fastphoto/l10n/generated/app_localizations.dart';

class FastPhotoApp extends StatefulWidget {
  const FastPhotoApp({super.key, required this.library});
  final MediaLibrary library;
  @override
  State<FastPhotoApp> createState() => _FastPhotoAppState();
}

class _FastPhotoAppState extends State<FastPhotoApp> {
  AppSettings settings = AppSettings();
  bool ready = false;
  String? startupError;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      settings = await widget.library.loadSettings();
    } catch (_) {
      startupError = 'settingsLoadFailed';
    }
    if (mounted) setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: appDisplayName,
    debugShowCheckedModeBanner: false,
    theme: photoTheme(Brightness.light),
    darkTheme: photoTheme(Brightness.dark),
    themeMode: settings.theme,
    locale: settings.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: ready
        ? GalleryPage(
            library: widget.library,
            settings: settings,
            startupError: startupError,
            onSettingsChanged: () => setState(() {}),
          )
        : const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}
