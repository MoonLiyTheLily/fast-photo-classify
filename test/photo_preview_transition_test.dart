import 'dart:async';
import 'dart:typed_data';

import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:fastphoto/shared/photo_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

Finder flight(String id) => find.byKey(ValueKey('photo-flight-$id'));
Finder previewHero() => find.descendant(
  of: find.byType(PhotoPreview),
  matching: find.byWidgetPredicate(
    (widget) => widget is PhotoHero && widget.enabled,
  ),
);

Future<void> decodeGridThumbnail(WidgetTester tester, int index) async {
  final tile = tester.widget<PhotoTile>(photo(index));
  final bytes = tile.cache.peek(tile.photo.id, 360)!;
  // Widget tests use a fake clock; pumping widgets alone need not finish the
  // engine's decoder. These tests start with a genuinely visible thumbnail.
  await tester.runAsync(
    () => precacheImage(MemoryImage(bytes), tester.element(photo(index))),
  );
  await tester.pump();
  expect(
    tester
        .widget<RawImage>(
          find.descendant(of: photo(index), matching: find.byType(RawImage)),
        )
        .image,
    isNotNull,
  );
}

class PreviewLibrary extends FakeLibrary {
  final fullImage = Completer<Uint8List?>();
  bool delayFullImage = false;
  int loads = 0;

  @override
  Future<LibrarySnapshot> load() {
    loads++;
    return super.load();
  }

  @override
  Future<Uint8List?> thumbnail(String id, int size) =>
      delayFullImage && size == 3200
      ? fullImage.future
      : super.thumbnail(id, size);
}

void main() {
  test('platform rotation is applied only to the displayed aspect ratio', () {
    final photo = Photo.fromMap({
      'id': 'rotated',
      'width': 4000,
      'height': 3000,
      'rotation': 270,
    });
    expect(photo.width, 4000);
    expect(photo.height, 3000);
    expect(photo.displayAspectRatio, .75);
    expect(Photo.fromMap({'id': 'unknown'}).displayAspectRatio, isNull);
  });

  testWidgets('photo flies from its tile to its fitted preview and back', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    final tile = tester.getRect(photo(0));
    await tester.tap(photo(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getRect(flight('p0'));
    expect(opening.width, greaterThan(tile.width));
    expect(opening.width, lessThan(430));
    expect(flight('p1'), findsNothing);
    await tester.pumpAndSettle();
    final preview = tester.getRect(previewHero());
    expect(preview.width, 430);
    expect(preview.width / preview.height, closeTo(4 / 3, .001));

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final closing = tester.getRect(flight('p0'));
    expect(closing.width, greaterThan(tile.width));
    expect(closing.width, lessThan(preview.width));
    await tester.pumpAndSettle();
    expect(tester.getRect(photo(0)), tile);
    expect(flight('p0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed full image keeps the cached thumbnail visible', (
    tester,
  ) async {
    final library = PreviewLibrary()..delayFullImage = true;
    await startApp(tester, library);
    await decodeGridThumbnail(tester, 0);
    await tester.tap(photo(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(of: flight('p0'), matching: find.byType(Image)),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: previewHero(), matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: previewHero(),
        matching: find.byIcon(Icons.image_outlined),
      ),
      findsNothing,
    );
    library.fullImage.complete(await library.thumbnail('p0', 360));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paging to an offscreen photo returns to that photo in the grid',
    (tester) async {
      await startApp(tester, FakeLibrary());
      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(40);
      await tester.pumpAndSettle();
      expect(find.text('41 / 90'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(flight('p40'), findsOneWidget);
      expect(flight('p0'), findsNothing);
      await tester.pumpAndSettle();
      expect(photo(40).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('media refresh waits until the reverse flight has landed', (
    tester,
  ) async {
    final library = PreviewLibrary();
    await startApp(tester, library);
    await tester.tap(photo(0));
    await tester.pumpAndSettle();
    final initialLoads = library.loads;
    library.controller.add(null);
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(flight('p0'), findsOneWidget);
    expect(library.loads, initialLoads);
    await tester.pumpAndSettle();
    expect(library.loads, initialLoads + 1);
  });

  testWidgets(
    'selecting after paging keeps the return target above the toolbar',
    (tester) async {
      await startApp(tester, FakeLibrary());
      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(40);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('选择照片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(photo(40).hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(photo(40)).dy,
        lessThan(tester.getTopLeft(find.text('放入相册')).dy),
      );
      expect(find.text('已选 1 张'), findsOneWidget);
    },
  );

  testWidgets('back during the opening flight leaves the gallery usable', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    await tester.tap(photo(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    Navigator.of(tester.element(find.byType(PhotoPreview))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoPreview), findsNothing);
    await tester.tap(photo(1));
    await tester.pumpAndSettle();
    expect(find.text('2 / 90'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected image flies without its checkbox and selection survives',
    (tester) async {
      await startApp(tester, FakeLibrary());
      await decodeGridThumbnail(tester, 0);
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      await tester.tap(photo(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(flight('p0'), findsOneWidget);
      expect(
        find.descendant(of: flight('p0'), matching: find.byType(Icon)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 张'), findsOneWidget);
    },
  );

  testWidgets('zoomed return fades safely; resetting zoom restores Hero', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary());
    for (final resetZoom in [false, true]) {
      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      Future<void> doubleTap() async {
        final center = tester.getCenter(find.byType(InteractiveViewer).first);
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pumpAndSettle();
      }

      await doubleTap();
      expect(previewHero(), findsNothing);
      if (resetZoom) await doubleTap();
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(flight('p0'), resetZoom ? findsOneWidget : findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion skips the flight and still opens and closes', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await startApp(tester, FakeLibrary());
    await tester.tap(photo(0));
    await tester.pump();
    await tester.pump();
    expect(flight('p0'), findsNothing);
    expect(find.byType(PhotoPreview), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoPreview), findsNothing);
    expect(photo(0).hitTestable(), findsOneWidget);
  });

  for (final dimensions in [(1200, 1600, 0), (1600, 1200, 90), (0, 0, 0)]) {
    testWidgets('preview fits dimensions and rotation $dimensions', (
      tester,
    ) async {
      final library = FakeLibrary();
      library.photos[0] = Photo(
        id: 'p0',
        name: 'portrait.jpg',
        path: 'DCIM/Camera/',
        volume: 'external_primary',
        date: DateTime(2026),
        width: dimensions.$1,
        height: dimensions.$2,
        rotation: dimensions.$3,
      );
      await startApp(tester, library);
      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      final rect = tester.getRect(previewHero());
      if (dimensions.$1 > 0) {
        expect(rect.width / rect.height, closeTo(3 / 4, .001));
      }
      expect(rect.width, lessThanOrEqualTo(430));
      expect(rect.height, lessThan(900));
      expect(tester.takeException(), isNull);
    });
  }
}
