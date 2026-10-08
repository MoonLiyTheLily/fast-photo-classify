import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

Finder get galleryScroll => find.byType(CustomScrollView).first;

List<PhotoTile> visibleTiles(WidgetTester tester) {
  final filters = tester.getRect(
    find
        .descendant(
          of: find.byType(PinnedHeaderSliver),
          matching: find.byType(ColoredBox),
        )
        .first,
  );
  return tester.widgetList<PhotoTile>(find.byType(PhotoTile)).where((tile) {
    final rect = tester.getRect(find.byKey(tile.key!));
    return rect.top > filters.bottom && rect.bottom < 730;
  }).toList();
}

void main() {
  for (final revealTitle in [false, true]) {
    testWidgets(
      'native header preserves sweep and drop coordinates, floating=$revealTitle',
      (tester) async {
        final library = FakeLibrary(photoCount: 500);
        await startApp(tester, library);
        expect(
          tester.widget<SliverAppBar>(find.byType(SliverAppBar)).floating,
          true,
        );
        await tester.drag(photo(3), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.text('速理').hitTestable(), findsNothing);
        if (revealTitle) {
          await tester.drag(galleryScroll, const Offset(0, 40));
          await tester.pumpAndSettle();
          expect(find.text('速理').hitTestable(), findsOneWidget);
        }
        expect(find.text('待整理').hitTestable(), findsOneWidget);
        final tiles = visibleTiles(tester);
        expect(tiles.length, greaterThanOrEqualTo(3));
        final first = find.byKey(tiles[0].key!);
        final last = find.byKey(tiles[2].key!);
        final gesture = await tester.startGesture(tester.getCenter(first));
        await tester.pump(const Duration(milliseconds: 420));
        await gesture.moveTo(tester.getCenter(last));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        final selected = tester
            .widgetList<PhotoTile>(find.byType(PhotoTile))
            .where((tile) => tile.selected)
            .map((tile) => tile.photo.id);
        expect(selected, tiles.take(3).map((tile) => tile.photo.id));

        final drag = await tester.startGesture(tester.getCenter(first));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pumpAndSettle();
        final album = find.byKey(
          const ValueKey('album-external_primary|Pictures/相册 00/'),
        );
        await drag.moveTo(tester.getCenter(album));
        await tester.pumpAndSettle();
        await drag.moveTo(tester.getCenter(album));
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          library.transferred,
          tiles.take(3).map((tile) => tile.photo.id).toList(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pinned filters stay usable with limited access and larger text',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await startApp(
        tester,
        FakeLibrary(photoCount: 500, permission: 'limited'),
        size: const Size(360, 740),
      );
      await tester.drag(galleryScroll, const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(find.text('速理').hitTestable(), findsNothing);
      expect(find.text('待整理').hitTestable(), findsOneWidget);
      expect(find.text('调整范围').hitTestable(), findsOneWidget);
      await tester.longPress(find.text('待整理'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview returns above pinned filters after paging back up the library',
    (tester) async {
      await startApp(tester, FakeLibrary(photoCount: 500));
      await tester.drag(photo(3), const Offset(0, -650));
      await tester.pumpAndSettle();
      final tile = visibleTiles(tester).last;
      await tester.tap(find.byKey(tile.key!));
      await tester.pumpAndSettle();
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(2);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(photo(2).hitTestable(), findsOneWidget);
      final filters = tester.getRect(
        find
            .descendant(
              of: find.byType(PinnedHeaderSliver),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        tester.getTopLeft(photo(2)).dy,
        greaterThanOrEqualTo(filters.bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pinching a scrolled sliver gallery preserves the center photo', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary(photoCount: 500));
    await tester.drag(photo(3), const Offset(0, -650));
    await tester.pumpAndSettle();
    final center = tester.getCenter(galleryScroll) + const Offset(0, 20);
    final before = tester
        .widgetList<PhotoTile>(find.byType(PhotoTile))
        .firstWhere(
          (tile) => tester.getRect(find.byKey(tile.key!)).contains(center),
        );
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
    expect(find.byKey(before.key!).hitTestable(), findsOneWidget);
    expect(tester.getSize(find.byKey(before.key!)).width, greaterThan(180));
    expect(find.byKey(const ValueKey('selection-count')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
