import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/gallery/selection_state.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo, hold;

class QueuedLibrary extends FakeLibrary {
  final requests = <String, Completer<Uint8List?>>{};
  @override
  Future<Uint8List?> thumbnail(String id, int size) =>
      (requests[id] = Completer<Uint8List?>()).future;
}

void main() {
  test('incremental selection matches range semantics across reversal and previous selections', () {
    final photos = FakeLibrary(photoCount: 10000).photos;
    final selected = PhotoSelection()..addAll(['p10', 'p9999']);
    final sweep = SweepSelection(photos, selected, 4000);
    final random = Random(42);
    for (var i = 0; i < 200; i++) {
      final next = random.nextInt(10000);
      sweep.move(next);
      final expected = rangeSelection(photos, {'p10', 'p9999'}, 4000, next);
      expect(selected.length, expected.length);
      expect(selected.containsAll(expected), true);
    }
    sweep.move(8000);
    var changedCells = 0;
    for (final photo in photos) {
      selected.watch(photo.id).addListener(() => changedCells++);
    }
    sweep.move(8001);
    expect(
      changedCells,
      1,
      reason: 'A one-photo extension must not notify the rest of a 10,000-photo gallery.',
    );
    selected.dispose();
  });

  test(
    'thumbnail requests are bounded and offscreen queued images are cancelled',
    () async {
      final library = QueuedLibrary();
      final cache = ThumbnailCache(library);
      final futures = [for (var i = 0; i < 20; i++) cache.get('p$i', 360)];
      expect(library.requests.length, 4);
      for (var i = 4; i < 20; i++) {
        cache.release('p$i', 360);
      }
      for (final request in library.requests.values) {
        request.complete(Uint8List(4));
      }
      await Future.wait(futures);
      expect(library.requests.length, 4);
      expect(await cache.get('p0', 360), hasLength(4));
      expect(
        library.requests.length,
        4,
        reason: 'Drag stack must reuse existing thumbnail bytes.',
      );
      cache.clear();
      await library.controller.close();
    },
  );

  test('classification handles source, target, explicit rules and volume-aware copies', () {
    final s = AppSettings(
      sourceKeys: [
        'external_primary|Pictures/QQ/',
        'external_primary|Pictures/Weixin/',
      ],
      targetKeys: ['external_primary|Pictures/收藏/'],
    );
    expect(s.albumOrganized('external_primary|Pictures/QQ/'), false);
    expect(s.albumOrganized('external_primary|Pictures/收藏/'), false);
    s.albumRules['external_primary|Pictures/收藏/'] = true;
    expect(s.albumOrganized('external_primary|Pictures/收藏/'), true);
    s.albumRules['external_primary|Pictures/收藏/'] = false;
    expect(s.albumOrganized('external_primary|Pictures/收藏/'), false);
    s.albumRules.clear();
    final photo = Photo(
      id: 'p',
      name: 'a',
      path: 'Pictures/QQ/',
      volume: 'external_primary',
      date: DateTime(2026),
      copyAlbumKeys: ['sd-card|Pictures/收藏/'],
    );
    expect(s.isOrganized(photo), false);
    s.albumRules['sd-card|Pictures/收藏/'] = true;
    expect(s.isOrganized(photo), true);
    s.sourceKeys.clear();
    s.targetKeys.clear();
    s.albumRules['external_primary|Pictures/Weixin/'] = false;
    expect(s.albumOrganized('external_primary|Pictures/Weixin/'), false);
    expect(s.albumOrganized('external_primary|DCIM/Camera/'), false);
  });

  test('destinations use Chinese pinyin first, package names last, recency and explicit targets', () {
    const albums = [
      Album(path: 'Pictures/Zebra/', updated: 50),
      Album(path: 'Pictures/旅行/', sortName: 'luxing', updated: 30),
      Album(path: 'Pictures/阿宝/', sortName: 'abao', updated: 20),
      Album(path: 'Pictures/Apple/', updated: 60),
      Album(path: 'Pictures/com.example.app/', updated: 999),
    ];
    final s = AppSettings();
    expect(s.destinations(albums).map((a) => a.name), [
      '阿宝',
      '旅行',
      'Apple',
      'Zebra',
      'com.example.app',
    ]);
    s.albumSort = AlbumSort.recent;
    expect(s.destinations(albums).first.name, 'Apple');
    s.recentTargets[albums[1].key] = 1000;
    expect(s.destinations(albums).first.name, '旅行');
    s.hideTechnical = true;
    expect(s.destinations(albums), hasLength(4));
    s.targetKeys = [albums[0].key, albums[2].key];
    s.targetAll = false;
    s.albumSort = AlbumSort.recent;
    expect(s.destinations(albums).map((a) => a.name), ['Zebra', '阿宝']);
    s.excludedTargets = [albums[0].key];
    expect(s.destinations(albums).single.name, '阿宝');
  });

  test('settings roundtrip preserves saved plans, album rules and sorting', () {
    final s = AppSettings(
      sourceKeys: ['v|Pictures/QQ/'],
      targetKeys: ['v|Pictures/B/', 'v|Pictures/A/'],
      albumSort: AlbumSort.recent,
      albumRules: {'v|Pictures/QQ/': false},
    );
    s.plans.add(s.capturePlan('QQ 整理'));
    expect(s.availablePlans, hasLength(2));
    expect(s.availablePlans.first.name, '默认方案');
    final loaded = AppSettings.fromMap(s.toMap());
    expect(loaded.toMap(), s.toMap());
    loaded.sourceKeys.clear();
    expect(s.sourceKeys, isNotEmpty);
    loaded.applyPlan(loaded.plans.first);
    expect(loaded.targetKeys, s.targetKeys);
  });

  testWidgets(
    'sweep changes only affected tiles and drag motion does not rebuild gallery scaffold',
    (tester) async {
      await startApp(tester, FakeLibrary(photoCount: 10000));
      final gesture = await hold(tester, 0);
      final scaffold = tester.widget(find.byType(Scaffold));
      final untouched = tester.widget(photo(8));
      await gesture.moveTo(tester.getCenter(photo(4)));
      await tester.pump();
      expect(identical(scaffold, tester.widget(find.byType(Scaffold))), true);
      expect(identical(untouched, tester.widget(photo(8))), true);
      expect(tester.widget<PhotoTile>(photo(4)).selected, true);
      await gesture.up();
      await tester.pumpAndSettle();
      final drag = await hold(tester, 0);
      await tester.pump(const Duration(milliseconds: 300));
      final draggingScaffold = tester.widget(find.byType(Scaffold));
      await drag.moveBy(const Offset(20, 10));
      await tester.pump();
      expect(
        identical(draggingScaffold, tester.widget(find.byType(Scaffold))),
        true,
      );
      await drag.cancel();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'preview swipe opens full-width details and offline coordinates; down swipe exits',
    (tester) async {
      final library = FakeLibrary()..settings.showLocation = true;
      await startApp(tester, library);
      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-coordinates')), findsOneWidget);
      expect(tester.getSize(find.byType(BottomSheet)).width, 430);
      expect(find.text('暂时无法查询地名，已显示经纬度'), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPreview), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('zoomed preview pans without opening details or exiting', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    await tester.tap(photo(0));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(PageView));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(0, 170));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoPreview), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'source selection applies and long-press organized opens destination editor',
    (tester) async {
      final library = FakeLibrary();
      await startApp(tester, library);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizerSheet), findsOneWidget);
      await tester.tap(find.text('清空').hitTestable());
      await tester.pump();
      await tester.tap(find.text('旅行').first);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('apply-scope')));
      await tester.pumpAndSettle();
      expect(library.settings.sourceKeys, ['external_primary|Pictures/旅行/']);
      expect(photo(0), findsOneWidget);
      await tester.tap(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-p12')), findsOneWidget);
      expect(photo(0), findsNothing);
      await tester.longPress(find.text('已归类'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('selected-albums-target')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved plan applies directly; cancelled edits leave active settings intact',
    (tester) async {
      final library = FakeLibrary();
      library.settings.plans.add(
        SortPlan(
          name: '旅行整理',
          sources: ['external_primary|Pictures/旅行/'],
          targets: ['external_primary|Pictures/相册 00/'],
        ),
      );
      await startApp(tester, library);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅行').first);
      await tester.tap(find.byTooltip('关闭范围设置'));
      await tester.pumpAndSettle();
      expect(library.settings.sourceKeys, isEmpty);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅行整理'));
      await tester.pumpAndSettle();
      expect(library.settings.targetKeys, ['external_primary|Pictures/相册 00/']);
      expect(find.byType(OrganizerSheet), findsNothing);
    },
  );

  testWidgets(
    'entering tray expands and blurs gallery; releasing outside preserves selection',
    (tester) async {
      await startApp(tester, FakeLibrary());
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      final drag = await hold(tester, 0);
      await tester.pump(const Duration(milliseconds: 300));
      final tray = find.byKey(const ValueKey('album-tray'));
      final initial = tester.getSize(tray).height;
      await drag.moveTo(tester.getCenter(find.text('相册 00')));
      await tester.pumpAndSettle();
      expect(tester.getSize(tray).height, greaterThan(initial * 1.4));
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        true,
      );
      await drag.moveTo(const Offset(0, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('已选 1 张'), findsOneWidget);
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        false,
      );
    },
  );

  testWidgets(
    'title collapses on scroll while category chips remain reachable',
    (tester) async {
      await startApp(tester, FakeLibrary());
      await tester.drag(photo(3), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('速理').hitTestable(), findsNothing);
      expect(find.text('全部照片').hitTestable(), findsOneWidget);
      expect(find.text('待整理').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scope and target editor fit a small portrait phone', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary(), size: const Size(360, 640));
    await tester.longPress(find.text('已归类'));
    await tester.pumpAndSettle();
    expect(find.byType(OrganizerSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard keeps scope search and apply button visible on small phone',
    (tester) async {
      await startApp(tester, FakeLibrary(), size: const Size(360, 640));
      await tester.longPress(find.text('已归类'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).hitTestable(), '旅行');
      await tester.pump();
      expect(
        find
            .byKey(const ValueKey('scope-target-external_primary|Pictures/旅行/'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('apply-scope'))).dy,
        lessThanOrEqualTo(370),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit targets constrain tray and dropping after expansion still hits the visible album',
    (tester) async {
      final library = FakeLibrary();
      library.settings.targetKeys = ['external_primary|Pictures/相册 02/'];
      library.settings.targetAll = false;
      await startApp(tester, library);
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      final drag = await hold(tester, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('相册 00'), findsNothing);
      await drag.moveTo(tester.getCenter(find.text('相册 02')));
      await tester.pumpAndSettle();
      await drag.moveTo(tester.getCenter(find.text('相册 02')));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(library.target?.name, '相册 02');
      expect(library.transferred, ['p0']);
      expect(tester.takeException(), isNull);
    },
  );
}
