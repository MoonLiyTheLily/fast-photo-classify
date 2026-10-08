import 'package:fastphoto/data/media_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Seed Pictures/FP_PICTURES_ROOT_03.jpg and Pictures/LocalSend/FP_PICTURES_CHILD_03.jpg
/// in the isolated emulator without sending a media scanner broadcast.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'discovers transferred images in Pictures root and child folders',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Pictures 照片发现验证'))),
        ),
      );
      final library = AndroidMediaLibrary();
      if ((await library.load()).permission != 'full') {
        await library.requestPermission();
      }
      await library.rescanPhotos();
      final snapshot = await library.load();
      final root = snapshot.photos.singleWhere(
        (p) => p.name == 'FP_PICTURES_ROOT_03.jpg',
      );
      final child = snapshot.photos.singleWhere(
        (p) => p.name == 'FP_PICTURES_CHILD_03.jpg',
      );
      expect(root.path, 'Pictures/');
      expect(child.path, 'Pictures/LocalSend/');
      expect(snapshot.albums.any((a) => a.path == 'Pictures/'), true);
      expect(await library.thumbnail(root.id, 360), isNotEmpty);
      expect(await library.thumbnail(child.id, 360), isNotEmpty);
    },
  );
}
