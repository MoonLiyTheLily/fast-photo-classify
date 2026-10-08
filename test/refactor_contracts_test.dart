import 'package:fastphoto/organizer/album_tray_layout.dart';
import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/organizer/organizer_selection.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android transfer adapter decodes success, skip, failure and cancellation together', () async {
    const channel = MethodChannel('app.fastphoto/media');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'transfer');
      expect(call.arguments, {
        'ids': ['a', 'b', 'c'],
        'path': 'Pictures/旅行/',
        'volume': 'external_primary',
        'copy': false,
      });
      return {
        'success': ['a'],
        'skipped': ['b'],
        'failures': [
          {'id': 'c', 'reason': '照片只读'},
        ],
        'cancelled': true,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final result = await AndroidMediaLibrary().transfer(
      ['a', 'b', 'c'],
      const Album(path: 'Pictures/旅行/'),
      false,
    );
    expect(result.successfulIds, ['a']);
    expect(result.skippedIds, ['b']);
    expect(result.failures.single.photoId, 'c');
    expect(result.failures.single.reason, '照片只读');
    expect(result.cancelled, true);
  });

  test('destination paths agree with Android while unsupported albums remain browsable', () {
    const valid = ['Pictures/', 'Pictures/旅行/', 'DCIM/', 'DCIM/Camera/'];
    const invalid = [
      'Download/',
      'Movies/',
      'Android/data/app/',
      'pictures/a/',
      'Pictures',
      'PicturesBackup/a/',
      'Pictures/../Download/',
      'Pictures/./a/',
      'Pictures/a\\b/',
    ];
    final albums = [
      for (final path in [...valid, ...invalid]) Album(path: path),
    ];
    final settings = AppSettings();
    expect(
      settings.destinations(albums).map((album) => album.path).toSet(),
      valid.toSet(),
    );
    expect(settings.sortedAlbums(albums), hasLength(albums.length));
    settings.targetAll = false;
    settings.targetKeys = albums.map((album) => album.key).toList();
    expect(settings.destinations(albums), hasLength(valid.length));
  });

  test('source and target scopes share selection rules but never change classification', () {
    const albums = [Album(path: 'Pictures/A/'), Album(path: 'Pictures/B/')];
    final draft = AppSettings();
    for (final scope in AlbumScope.values) {
      final editor = AlbumScopeEditor(draft, scope);
      editor.toggle(albums.first, albums);
      expect(editor.includesAll, false);
      expect(editor.selectedKeys, [albums.last.key]);
      editor.toggle(albums.first, albums);
      expect(
        editor.selectedKeys.toSet(),
        albums.map((album) => album.key).toSet(),
      );
      editor.clear();
      expect(editor.includesAll, false);
      expect(editor.selectedKeys, isEmpty);
      editor.selectAll();
      expect(editor.includesAll, true);
    }
    expect(draft.albumRules, isEmpty);
  });

  test('classify all affects present albums; new albums stay unclassified and scopes stay intact', () {
    const album = Album(path: 'Download/');
    final draft = AppSettings(
      sourceKeys: [album.key],
      targetKeys: ['external_primary|Pictures/旅行/'],
    );
    final editor = AlbumClassificationEditor(draft);
    editor.classifyAll([album]);
    expect(editor.organizedKeys, {album.key});
    expect(draft.albumOrganized('external_primary|Pictures/new/'), false);
    editor.toggle(album);
    expect(editor.organizedKeys, isEmpty);
    expect(draft.sourceKeys, [album.key]);
    expect(draft.targetKeys, ['external_primary|Pictures/旅行/']);
  });

  testWidgets(
    'unsupported destinations still appear as sources and in the independent browser',
    (tester) async {
      final library = FakeLibrary(photoCount: 3, albumCount: 0);
      library.albums.add(const Album(path: 'Download/'));
      await startApp(tester, library);
      await tester.tap(find.widgetWithText(ActionChip, '相册'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('album-external_primary|Download/')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('关闭相册'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scope-source-external_primary|Download/')),
        findsOneWidget,
      );
      await tester.tap(find.text('目标相册'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scope-target-external_primary|Download/')),
        findsNothing,
      );
      expect(find.byType(OrganizerSheet), findsOneWidget);
    },
  );

  for (final columns in [2, 3, 4]) {
    testWidgets(
      'album hit testing matches actual GridView cards with $columns columns after resizing and scrolling',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final geometry = AlbumTrayLayout(columns: columns);
        const gridKey = ValueKey('test-album-grid');
        const albumCount = 13;
        for (final width in [300.0, 420.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    height: 350,
                    child: GridView.builder(
                      key: gridKey,
                      controller: scroll,
                      padding: AlbumTrayLayout.padding,
                      gridDelegate: geometry.gridDelegate,
                      itemCount: albumCount,
                      itemBuilder: (_, index) => ColoredBox(
                        key: ValueKey('card-$index'),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final offset in [
            0.0,
            scroll.position.maxScrollExtent / 2,
            scroll.position.maxScrollExtent,
          ]) {
            scroll.jumpTo(offset);
            await tester.pumpAndSettle();
            final viewport = tester.getRect(find.byKey(gridKey));
            int? hit(Offset globalPosition) => geometry.indexAt(
              position: globalPosition - viewport.topLeft,
              viewportSize: viewport.size,
              scrollOffset: scroll.offset,
              albumCount: albumCount,
            );
            for (var index = 0; index < albumCount; index++) {
              final card = find.byKey(ValueKey('card-$index'));
              if (card.evaluate().isEmpty) continue;
              final bounds = tester.getRect(card);
              if (viewport.contains(bounds.center)) {
                expect(hit(bounds.center), index);
                expect(
                  hit(Offset(bounds.right + 3, bounds.center.dy)),
                  isNull,
                  reason: 'Spacing beside a visible card must not select its neighbor.',
                );
              }
            }
            expect(hit(viewport.topLeft + const Offset(4, 100)), isNull);
            if (offset == scroll.position.maxScrollExtent) {
              expect(hit(viewport.bottomCenter - const Offset(0, 2)), isNull);
            }
          }
        }
      },
    );
  }
}
