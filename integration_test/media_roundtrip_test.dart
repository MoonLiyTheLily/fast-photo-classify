import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run only on an isolated emulator seeded with FP_QA_*.jpg test images.
/// FASTPHOTO_TEST_GROUP can isolate another fixture set without deleting old ones.
/// MediaStore system consent is intentionally left visible for the test operator.
void main() {
  const fixtureGroup = String.fromEnvironment(
    'FASTPHOTO_TEST_GROUP',
    defaultValue: 'QA',
  );
  const fixturePrefix = 'FP_${fixtureGroup}_';
  const targetName = 'FastPhoto_${fixtureGroup}_target';
  const copyTargetName = 'FastPhoto_${fixtureGroup}_copy';
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real MediaStore: cancel, move, collision, copy and thumbnails', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('FastPhoto · MediaStore 验证'))),
      ),
    );
    final library = AndroidMediaLibrary();
    var initial = await library.load();
    if (initial.permission != 'full') {
      await library.requestPermission();
      initial = await library.load();
    }
    expect(
      initial.permission,
      'full',
      reason:
          'Choose ALLOW ALL in the isolated emulator photo permission prompt.',
    );
    final photos = initial.photos
        .where((p) => p.name.startsWith(fixturePrefix))
        .toList();
    expect(
      photos.length,
      2,
      reason:
          'Seed exactly two photos with prefix $fixturePrefix in different albums. '
          'Visible files: ${initial.photos.map((photo) => photo.name).join(', ')}',
    );
    final first = photos.first;
    expect(await library.thumbnail(first.id, 360), isNotEmpty);
    expect(await library.thumbnail(first.id, 1600), isNotEmpty);
    final location = await library.details(first.id, true);
    expect(location['locationStatus'], isNotNull);

    await library.createAlbum(targetName);
    const target = Album(path: 'Pictures/$targetName/');
    // Operator: deny the FIRST consent dialog; allow all remaining dialogs.
    final cancelled = await library.transfer([first.id], target, false);
    expect(cancelled.cancelled, true);
    final afterCancel = await library.load();
    expect(
      afterCancel.photos.firstWhere((p) => p.id == first.id).path,
      first.path,
    );

    final moved = await library.transfer(
      photos.map((p) => p.id).toList(),
      target,
      false,
    );
    expect(moved.failures, isEmpty);
    expect(moved.successfulIds.length, 2);
    final afterMove = await library.load();
    final movedPhotos = afterMove.photos
        .where((p) => p.path == target.path)
        .toList();
    expect(movedPhotos.length, 2);
    expect(
      movedPhotos.map((p) => p.name).toSet().length,
      2,
      reason: 'Same-name files must not overwrite one another.',
    );
    expect(afterMove.photos.length, initial.photos.length);

    const copyTarget = Album(path: 'Pictures/$copyTargetName/');
    await library.createAlbum(copyTargetName);
    final copied = await library.transfer([first.id], copyTarget, true);
    expect(copied.failures, isEmpty);
    expect(copied.successfulIds, [first.id]);
    final afterCopy = await library.load();
    expect(afterCopy.photos.length, initial.photos.length + 1);
    expect(
      afterCopy.photos.firstWhere((p) => p.id == first.id).copyAlbums,
      contains(copyTarget.path),
    );
    expect(afterCopy.photos.where((p) => p.path == copyTarget.path).length, 1);

    final skipped = await library.transfer([first.id], target, false);
    expect(skipped.skippedIds, [first.id]);
    expect(skipped.successfulIds, isEmpty);

    final settings = AppSettings()
      ..edge = TrayEdge.left
      ..copy = true
      ..albumColumns = 4;
    await library.saveSettings(settings);
    final saved = await library.loadSettings();
    expect(saved.edge, TrayEdge.left);
    expect(saved.copy, true);
    expect(saved.albumColumns, 4);
    await library.saveSettings(AppSettings());
  });
}
