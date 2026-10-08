import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:fastphoto/shared/photo_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

class ImageLibrary extends FakeLibrary {
  ImageLibrary(this.smallBytes, this.largeBytes);
  final Uint8List smallBytes, largeBytes;
  @override
  Future<Uint8List?> thumbnail(String id, int size) async =>
      size == 3200 ? largeBytes : smallBytes;
}

Future<ui.Image> coloredImage(Color color, int size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

class DecodingFixture {
  DecodingFixture(this.library, this.smallImage, this.largeImage);
  final ImageLibrary library;
  final ui.Image smallImage, largeImage;
  final largeFrame = Completer<ImageInfo>();

  static Future<DecodingFixture> create(WidgetTester tester) async {
    final source = FakeLibrary();
    final bytes = (await source.thumbnail('p0', 360))!;
    await source.controller.close();
    final library = ImageLibrary(bytes, Uint8List.fromList(bytes));
    final images = await tester.runAsync(
      () => Future.wait([
        coloredImage(Colors.blue, 4),
        coloredImage(Colors.red, 24),
      ]),
    );
    final fixture = DecodingFixture(library, images![0], images[1]);
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.putIfAbsent(
      MemoryImage(library.smallBytes),
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: fixture.smallImage.clone())),
      ),
    );
    imageCache.putIfAbsent(
      MemoryImage(library.largeBytes),
      () => OneFrameImageStreamCompleter(fixture.largeFrame.future),
    );
    addTearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
      fixture.smallImage.dispose();
      fixture.largeImage.dispose();
    });
    return fixture;
  }

  void completeFrame() =>
      largeFrame.complete(ImageInfo(image: largeImage.clone()));
}

void expectPaintedImage(WidgetTester tester, Finder within, int width) {
  final images = tester.widgetList<RawImage>(
    find.descendant(of: within, matching: find.byType(RawImage)),
  );
  expect(images, isNotEmpty);
  expect(
    images.any((image) => image.image?.width == width),
    isTrue,
    reason:
        'A decoded image must actually be painted, not just an Image widget.',
  );
}

void main() {
  testWidgets('first grid image keeps its placeholder while its bytes decode', (
    tester,
  ) async {
    final fixture = await DecodingFixture.create(tester);
    addTearDown(fixture.library.controller.close);
    final cache = ThumbnailCache(fixture.library);
    await cache.get('p0', 3200);
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoImage(
          photo: fixture.library.photos.first,
          cache: cache,
          size: 3200,
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    fixture.completeFrame();
    await tester.pumpAndSettle();
    expectPaintedImage(tester, find.byType(PhotoImage), 24);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    cache.release('p0', 3200);
  });

  for (final failDecode in [false, true]) {
    testWidgets(
      'cold full image retains thumbnail until frame, failure=$failDecode',
      (tester) async {
        final fixture = await DecodingFixture.create(tester);
        addTearDown(fixture.library.controller.close);
        final cache = ThumbnailCache(fixture.library);
        await cache.get('p0', 360);
        await cache.get('p0', 3200);
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 300,
              height: 300,
              child: PhotoImage(
                photo: fixture.library.photos.first,
                cache: cache,
                size: 3200,
                placeholderSize: 360,
              ),
            ),
          ),
        );
        await tester.pump();
        // Full bytes are already cached, but their decoder is deliberately held.
        expect(cache.peek('p0', 3200), isNotNull);
        expectPaintedImage(tester, find.byType(PhotoImage), 4);
        if (failDecode) {
          fixture.largeFrame.completeError(StateError('decoder failed'));
        } else {
          fixture.completeFrame();
        }
        await tester.pumpAndSettle();
        expectPaintedImage(
          tester,
          find.byType(PhotoImage),
          failDecode ? 4 : 24,
        );
        expect(tester.takeException(), isNull);
        cache.release('p0', 360);
        cache.release('p0', 3200);
      },
    );
  }

  testWidgets(
    'first Hero flight hands over a painted thumbnail when decoding is slow',
    (tester) async {
      final fixture = await DecodingFixture.create(tester);
      await startApp(tester, fixture.library);
      await tester.tap(photo(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectPaintedImage(
        tester,
        find.byKey(const ValueKey('photo-flight-p0')),
        4,
      );
      // Check every frame through the handoff, not just the settled page.
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final flight = find.byKey(const ValueKey('photo-flight-p0'));
        expectPaintedImage(
          tester,
          flight.evaluate().isNotEmpty ? flight : find.byType(PhotoPreview),
          4,
        );
      }
      expectPaintedImage(tester, find.byType(PhotoPreview), 4);
      fixture.completeFrame();
      await tester.pumpAndSettle();
      expectPaintedImage(tester, find.byType(PhotoPreview), 24);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
