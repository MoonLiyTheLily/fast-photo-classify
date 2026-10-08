import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fastphoto/app/fast_photo_app.dart';
import 'package:fastphoto/data/media_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 * 1024 * 1024;
  runApp(FastPhotoApp(library: AndroidMediaLibrary()));
}
