import 'package:fastphoto/app/fast_photo_app.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

Finder scopeCard(OrganizerTab tab, String name) =>
    find.byKey(ValueKey('scope-${tab.name}-external_primary|Pictures/$name/'));
Finder galleryList() => find
    .byWidgetPredicate((w) => w is CustomScrollView && w.controller != null)
    .first;

class WorkflowLibrary extends FakeLibrary {
  WorkflowLibrary() : super(photoCount: 5, albumCount: 0) {
    albums = const [
      Album(path: 'Pictures/阿宝/', sortName: 'abao', updated: 10),
      Album(path: 'Pictures/旅行/', sortName: 'luxing', updated: 20),
      Album(path: 'Pictures/Apple/', updated: 50),
      Album(path: 'Pictures/com.example.app/', updated: 100),
    ];
  }
  @override
  Future<LibrarySnapshot> load() async => LibrarySnapshot(
    photos: photos,
    emptyAlbums: albums,
    permission: permission,
    sortNames: const {'阿宝': 'abao', '旅行': 'luxing'},
  );
}

void main() {
  test('old settings migrate without auto classification, manual ordering or auto plans', () {
    final migrated = AppSettings.fromMap({
      'sourceKeys': ['v|Pictures/QQ/'],
      'targetKeys': ['v|Pictures/收藏/'],
      'albumSort': 'manual',
      'recentPlans': [
        {'name': '最近整理', 'sources': [], 'targets': []},
      ],
      'plans': [
        {
          'name': '收藏整理',
          'sources': ['v|Pictures/QQ/'],
          'targets': ['v|Pictures/收藏/'],
          'sort': 'manual',
        },
      ],
    });
    expect(migrated.sourceAll, false);
    expect(migrated.targetAll, false);
    expect(migrated.albumSort, AlbumSort.smart);
    expect(migrated.albumOrganized('v|Pictures/收藏/'), false);
    expect(migrated.availablePlans.map((p) => p.name), ['默认方案', '收藏整理']);
    expect(migrated.toMap().containsKey('recentPlans'), false);
    migrated.applyPlan(migrated.availablePlans.first);
    expect(migrated.sourceAll && migrated.targetAll, true);
  });

  testWidgets(
    'all photos includes Pictures root and children despite a restricted organizing source',
    (tester) async {
      final library = FakeLibrary(photoCount: 0, albumCount: 0);
      library.photos = [
        for (var i = 0; i < 3; i++)
          Photo(
            id: 'p$i',
            name: 'transfer$i.jpg',
            path: ['DCIM/Camera/', 'Pictures/', 'Pictures/LocalSend/'][i],
            volume: 'external_primary',
            date: DateTime(2026, 10, 4),
          ),
      ];
      library.settings
        ..sourceAll = false
        ..sourceKeys = ['external_primary|DCIM/Camera/'];
      await startApp(tester, library);
      expect(photo(1), findsOneWidget);
      expect(photo(2), findsOneWidget);
      await tester.tap(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(photo(0), findsOneWidget);
      expect(photo(1), findsNothing);
      await tester.tap(find.text('全部照片'));
      await tester.pumpAndSettle();
      expect(photo(1), findsOneWidget);
    },
  );

  testWidgets(
    'browsing is highlighted and closable without changing source, target or classification',
    (tester) async {
      final library = FakeLibrary(photoCount: 30, albumCount: 0);
      library.settings
        ..sourceAll = false
        ..sourceKeys = ['external_primary|DCIM/Camera/']
        ..targetAll = false
        ..targetKeys = ['external_primary|Pictures/旅行/'];
      final settings = library.settings.toMap();
      await startApp(tester, library);
      await tester.tap(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '相册'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅行'));
      await tester.pumpAndSettle();
      expect(photo(12), findsOneWidget);
      expect(photo(0), findsNothing);
      final chip = tester.widget<InputChip>(
        find.byKey(const ValueKey('browsing-album')),
      );
      expect(chip.selected, true);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((c) => !c.selected),
        true,
      );
      expect(find.text('待整理'), findsOneWidget);
      expect(find.text('已归类'), findsOneWidget);
      expect(library.settings.toMap(), settings);
      await tester.tap(find.byTooltip('退出相册浏览'));
      await tester.pumpAndSettle();
      expect(photo(0), findsOneWidget);
      expect(find.byKey(const ValueKey('browsing-album')), findsNothing);
      expect(library.settings.toMap(), settings);
    },
  );

  testWidgets(
    'browser uses the same smart and recent album order as organizer',
    (tester) async {
      final library = WorkflowLibrary();
      await startApp(tester, library);
      await tester.tap(find.widgetWithText(ActionChip, '相册'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('阿宝')).dx,
        lessThan(tester.getTopLeft(find.text('旅行')).dx),
      );
      await tester.tap(find.byKey(const ValueKey('album-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最近更新优先').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Apple')).dx,
        lessThan(tester.getTopLeft(find.text('旅行')).dx),
      );
      expect(library.settings.albumSort, AlbumSort.recent);
      await tester.tap(find.byTooltip('关闭相册'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(find.text('最近更新优先'), findsOneWidget);
      final row = find.byKey(const ValueKey('selected-albums-source'));
      expect(
        tester
            .getTopLeft(find.descendant(of: row, matching: find.text('Apple')))
            .dx,
        lessThan(
          tester
              .getTopLeft(find.descendant(of: row, matching: find.text('旅行')))
              .dx,
        ),
      );
    },
  );

  testWidgets(
    'source, target and classification move albums between horizontal selection and vertical grid',
    (tester) async {
      await startApp(tester, WorkflowLibrary());
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      for (final tab in [
        OrganizerTab.source,
        OrganizerTab.target,
        OrganizerTab.classification,
      ]) {
        if (tab != OrganizerTab.source) {
          await tester.tap(
            find.text(tab == OrganizerTab.target ? '目标相册' : '归类规则'),
          );
          await tester.pumpAndSettle();
        }
        if (tab != OrganizerTab.classification) {
          await tester.tap(find.text('清空').hitTestable());
          await tester.pumpAndSettle();
        }
        final grid = find.byKey(ValueKey('remaining-albums-${tab.name}'));
        expect(
          find.descendant(of: grid, matching: scopeCard(tab, '阿宝')),
          findsOneWidget,
        );
        await tester.tap(scopeCard(tab, '阿宝'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(ValueKey('selected-albums-${tab.name}')),
            matching: scopeCard(tab, '阿宝'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: grid, matching: scopeCard(tab, '阿宝')),
          findsNothing,
        );
      }
      await tester.tap(find.byKey(const ValueKey('album-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最近更新优先').last);
      await tester.pumpAndSettle();
      final grid = find.byKey(
        const ValueKey('remaining-albums-classification'),
      );
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: grid,
                matching: scopeCard(OrganizerTab.classification, 'Apple'),
              ),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(
                  of: grid,
                  matching: scopeCard(OrganizerTab.classification, '旅行'),
                ),
              )
              .dx,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('apply-scope')));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizerSheet), findsNothing);
    },
  );

  testWidgets(
    'default plan cannot be deleted and explicit saves are the only way to create a plan',
    (tester) async {
      final library = WorkflowLibrary();
      await startApp(tester, library);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(scopeCard(OrganizerTab.source, '阿宝'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-scope')));
      await tester.pumpAndSettle();
      expect(library.settings.plans, isEmpty);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存方案'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '手动方案',
      );
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(library.settings.plans.map((p) => p.name), ['手动方案']);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方案'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('default-plan')),
          matching: find.byTooltip('删除方案'),
        ),
        findsNothing,
      );
      expect(find.text('最近使用'), findsNothing);
      await tester.tap(find.text('默认方案'));
      await tester.pumpAndSettle();
      expect(library.settings.sourceAll && library.settings.targetAll, true);
      expect(library.settings.plans, hasLength(1));
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放入相册'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阿宝'));
      await tester.pumpAndSettle();
      expect(library.settings.plans, hasLength(1));
    },
  );

  testWidgets(
    'a small reverse scroll restores title well before returning to top',
    (tester) async {
      await startApp(tester, FakeLibrary(photoCount: 500));
      await tester.drag(photo(3), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.text('速理').hitTestable(), findsNothing);
      await tester.drag(galleryList(), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.text('速理').hitTestable(), findsOneWidget);
      expect(
        tester.widget<CustomScrollView>(galleryList()).controller!.offset,
        greaterThan(200),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first-run tutorial is acknowledged once and no idle footer is left',
    (tester) async {
      final library = FakeLibrary()..settings.tutorialSeen = false;
      await startApp(tester, library);
      expect(find.byKey(const ValueKey('first-run-tutorial')), findsOneWidget);
      await tester.tap(find.text('开始整理'));
      await tester.pumpAndSettle();
      expect(library.settings.tutorialSeen, true);
      expect(find.text('长按选图，再长按拖入相册'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(FastPhotoApp(library: library));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first-run-tutorial')), findsNothing);
    },
  );
}
