import 'dart:ui' as ui;

import 'package:fastphoto/data/media_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Isolated emulator fixture: an 800 x 600 JPEG with EXIF orientation 6 (90°),
/// named FP_HERO_ROTATED_032.jpg. The displayed image must be 600 x 800.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('preview ratio agrees with Android rotated image decoding', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final library = AndroidMediaLibrary();
    final snapshot = await library.load();
    expect(snapshot.permission, 'full');
    final photo = snapshot.photos.singleWhere(
      (photo) => photo.name == 'FP_HERO_ROTATED_032.jpg',
    );
    expect(photo.width, 800);
    expect(photo.height, 600);
    expect(photo.rotation, 90);
    expect(photo.displayAspectRatio, .75);
    for (final size in [360, 3200]) {
      final bytes = await library.thumbnail(photo.id, size);
      expect(bytes, isNotEmpty);
      final codec = await ui.instantiateImageCodec(bytes!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width / frame.image.height, closeTo(.75, .005));
      frame.image.dispose();
      codec.dispose();
    }
  });
}
