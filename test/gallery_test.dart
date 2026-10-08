import 'package:fastphoto/gallery/gallery_layout.dart';
import 'package:fastphoto/app/fast_photo_app.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/gallery/selection_state.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:fastphoto/gallery/photo_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';

Future<void> startApp(
  WidgetTester tester,
  FakeLibrary library, {
  Size size = const Size(430, 900),
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(library.controller.close);
  await tester.pumpWidget(FastPhotoApp(library: library));
  await tester.pumpAndSettle();
}

Finder photo(int i) => find.byKey(ValueKey('photo-p$i'));
Finder check(int i) => find.byKey(ValueKey('check-p$i'));
Future<TestGesture> hold(WidgetTester tester, int i, {int pointer = 1}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(photo(i)),
    pointer: pointer,
  );
  await tester.pump(const Duration(milliseconds: 420));
  return gesture;
}

void main() {
  test(
    'range selection retracts new range while preserving older selections',
    () {
      final photos = FakeLibrary(photoCount: 12).photos;
      expect(rangeSelection(photos, {'p9'}, 2, 6), {
        'p2',
        'p3',
        'p4',
        'p5',
        'p6',
        'p9',
      });
      expect(rangeSelection(photos, {'p9'}, 2, 3), {'p2', 'p3', 'p9'});
      expect(rangeSelection(photos, {'p9'}, 5, 2), {
        'p2',
        'p3',
        'p4',
        'p5',
        'p9',
      });
    },
  );
  test('layout excludes date headers and missing cells in partial rows', () {
    final items = FakeLibrary(photoCount: 5).photos;
    final layout = GalleryLayout(items, 3, 306, true);
    expect(layout.indexAt(const Offset(20, 20)), isNull);
    expect(layout.indexAt(const Offset(20, 65)), 0);
    expect(layout.indexAt(const Offset(250, 200)), isNull);
    expect(layout.indexAt(const Offset(400, 100)), isNull);
  });
  test('organized state defaults to false and uses explicit album rules and copy references', () {
    final settings = AppSettings();
    final p = Photo(
      id: '1',
      name: 'a',
      path: 'dcim/camera/',
      volume: 'external_primary',
      date: DateTime(2026),
    );
    expect(settings.isOrganized(p), false);
    settings.albumRules['external_primary|Pictures/旅行/'] = true;
    expect(
      settings.isOrganized(
        Photo(
          id: '2',
          name: 'b',
          path: 'DCIM/Camera/',
          volume: 'external_primary',
          date: DateTime(2026),
          copyAlbums: ['Pictures/旅行/'],
        ),
      ),
      true,
    );
  });

  testWidgets('sweep, reverse, checkbox toggle and body preview coexist', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    final gesture = await hold(tester, 0);
    await gesture.moveTo(tester.getCenter(photo(5)));
    await tester.pump();
    expect(find.text('已选 6 张'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(photo(2)));
    await tester.pump();
    expect(find.text('已选 3 张'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(check(4));
    await tester.pump();
    expect(find.text('已选 4 张'), findsOneWidget);
    await tester.tap(photo(4));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoPreview), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('已选 4 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary vertical swipes scroll without selecting', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    await tester.drag(photo(3), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-count')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final edge in TrayEdge.values) {
    testWidgets('drop into album from ${edge.name}', (tester) async {
      final library = FakeLibrary()..settings.edge = edge;
      await startApp(tester, library);
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      final drag = await hold(tester, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PhotoStack), findsOneWidget);
      final destination = find.text('相册 00');
      await drag.moveTo(tester.getCenter(destination));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(library.transferred, ['p0']);
      expect(library.target?.name, '相册 00');
      expect(library.copied, false);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelled pointer does not transfer and preserves selection', (
    tester,
  ) async {
    final library = FakeLibrary();
    await startApp(tester, library);
    await tester.longPress(photo(0));
    await tester.pumpAndSettle();
    final drag = await hold(tester, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(library.transferred, isNull);
    expect(find.text('已选 1 张'), findsOneWidget);
    expect(find.byType(PhotoStack), findsNothing);
  });

  testWidgets('second finger scrolls tray while first finger retains stack', (
    tester,
  ) async {
    final library = FakeLibrary(albumCount: 60);
    await startApp(tester, library);
    await tester.longPress(photo(0));
    await tester.pumpAndSettle();
    final drag = await hold(tester, 0, pointer: 1);
    await tester.pump(const Duration(milliseconds: 300));
    final grid = find.byType(GridView);
    final center = tester.getCenter(grid);
    final second = await tester.startGesture(
      center + const Offset(0, 80),
      pointer: 2,
    );
    await second.moveBy(const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 200));
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoStack), findsOneWidget);
    final scroll = tester.widget<GridView>(grid).controller!;
    expect(scroll.offset, greaterThan(0));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(library.transferred, isNull);
  });

  testWidgets('hover at tray edge scrolls without lifting drag finger', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary(albumCount: 60));
    await tester.longPress(photo(0));
    await tester.pumpAndSettle();
    final drag = await hold(tester, 0);
    await tester.pump(const Duration(milliseconds: 300));
    final grid = find.byType(GridView);
    final bottom = tester.getBottomLeft(grid);
    await drag.moveTo(Offset(bottom.dx + 70, bottom.dy - 12));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(tester.widget<GridView>(grid).controller!.offset, greaterThan(100));
    await drag.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('pinch changes photo density without selecting', (tester) async {
    await startApp(tester, FakeLibrary());
    final center = tester.getCenter(photo(4));
    final first = await tester.startGesture(
      center - const Offset(60, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PhotoTile).first).width,
      greaterThan(180),
    );
    expect(find.byKey(const ValueKey('selection-count')), findsNothing);
  });

  testWidgets('partial failures retain only failed selection', (tester) async {
    final library = FakeLibrary()..failTransfer = true;
    await startApp(tester, library);
    final sweep = await hold(tester, 0);
    await sweep.moveTo(tester.getCenter(photo(2)));
    await sweep.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放入相册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相册 00'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 张'), findsOneWidget);
  });

  testWidgets('denied access offers request and settings', (tester) async {
    await startApp(tester, FakeLibrary(permission: 'denied'));
    expect(find.text('允许访问照片'), findsOneWidget);
    expect(find.text('在系统设置中授权'), findsOneWidget);
    expect(find.byType(PhotoTile), findsNothing);
  });
  testWidgets('limited access banner and settings fit a small phone', (
    tester,
  ) async {
    await startApp(
      tester,
      FakeLibrary(permission: 'limited'),
      size: const Size(360, 740),
    );
    expect(find.text('仅显示你授权的照片'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('按你的习惯整理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dark theme and dense side tray have no overflow', (
    tester,
  ) async {
    final library = FakeLibrary()
      ..settings.theme = ThemeMode.dark
      ..settings.edge = TrayEdge.right
      ..settings.albumColumns = 4;
    await startApp(tester, library, size: const Size(360, 740));
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('浏览相册'), findsOneWidget);
  });
}
