import 'dart:async';

import 'package:fastphoto/gallery/gallery_controller.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/transfer_result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';

class DelayedLibrary extends FakeLibrary {
  DelayedLibrary() : super(photoCount: 3, albumCount: 0);

  bool delayReads = false;
  final reads = <Completer<LibrarySnapshot>>[];
  int loadCount = 0;
  int scanCount = 0;
  Completer<int>? scan;
  Completer<TransferResult>? transferResult;

  LibrarySnapshot get currentSnapshot =>
      LibrarySnapshot(photos: List.of(photos), permission: permission);

  @override
  Future<LibrarySnapshot> load() {
    loadCount++;
    if (!delayReads) return Future.value(currentSnapshot);
    final read = Completer<LibrarySnapshot>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<int> rescanPhotos() {
    scanCount++;
    return scan?.future ?? Future.value(0);
  }

  @override
  Future<TransferResult> transfer(List<String> ids, Album album, bool copy) =>
      transferResult?.future ?? super.transfer(ids, album, copy);
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  late DelayedLibrary library;
  late GalleryController gallery;
  late List<String> notices;

  setUp(() async {
    library = DelayedLibrary();
    notices = [];
    gallery = GalleryController(
      library: library,
      settings: library.settings,
      onNotice: notices.add,
    );
    await gallery.requestReload();
  });
  tearDown(() async {
    gallery.dispose();
    await library.controller.close();
  });

  for (final interaction in [
    GalleryInteraction.sweeping,
    GalleryInteraction.dragging,
  ]) {
    test(
      'a query that finishes during ${interaction.name} is deferred and repeated events coalesce',
      () async {
        gallery.selection.add('p0');
        library.delayReads = true;
        final inFlight = gallery.requestReload();
        gallery.setInteraction(interaction);
        library.photos.removeAt(0);
        for (var event = 0; event < 10; event++) {
          library.controller.add(null);
        }
        await flushEvents();
        library.reads.single.complete(library.currentSnapshot);
        await inFlight;
        expect(gallery.snapshot.photos, hasLength(3));
        expect(gallery.selection, contains('p0'));
        expect(library.reads, hasLength(1));

        gallery.setInteraction(GalleryInteraction.idle);
        expect(library.reads, hasLength(2));
        library.reads.last.complete(library.currentSnapshot);
        await flushEvents();
        expect(gallery.snapshot.photos, hasLength(2));
        expect(gallery.selection, isEmpty);
        expect(library.reads, hasLength(2));
      },
    );
  }

  test('preview and gesture holds are independent; both must finish before refreshing', () async {
    gallery.setPreviewOpen(true);
    gallery.setInteraction(GalleryInteraction.sweeping);
    library.photos.removeLast();
    await gallery.requestReload();
    gallery.setInteraction(GalleryInteraction.idle);
    await flushEvents();
    expect(library.loadCount, 1);
    gallery.setPreviewOpen(false);
    await flushEvents();
    expect(library.loadCount, 2);
    expect(gallery.visiblePhotos, hasLength(2));
  });

  test(
    'scan requests wait for an existing read and do not overlap reads',
    () async {
      library.delayReads = true;
      final reload = gallery.requestReload();
      library.scan = Completer<int>();
      final refresh = gallery.refreshFromStorage();
      expect(library.scanCount, 0);
      library.reads.single.complete(library.currentSnapshot);
      await flushEvents();
      expect(library.scanCount, 1);
      expect(gallery.isRefreshing, true);
      expect(library.reads, hasLength(1));
      library.scan!.complete(1);
      await flushEvents();
      expect(library.reads, hasLength(2));
      library.reads.last.complete(library.currentSnapshot);
      await Future.wait([reload, refresh]);
      expect(gallery.isRefreshing, false);
    },
  );

  test('failed in-flight reads cannot replace an active gesture with an error screen', () async {
    library.delayReads = true;
    final reload = gallery.requestReload();
    gallery.setInteraction(GalleryInteraction.dragging);
    library.reads.single.completeError(
      PlatformException(code: 'temporarily_unavailable'),
    );
    await reload;
    expect(gallery.loadError, isNull);
    expect(gallery.visiblePhotos, hasLength(3));
    gallery.setInteraction(GalleryInteraction.idle);
    library.reads.last.complete(library.currentSnapshot);
    await flushEvents();
    expect(gallery.loadError, isNull);
  });

  test('transfer blocks refresh, removes only completed ids, and does not create plans', () async {
    const album = Album(path: 'Pictures/整理/');
    gallery.selection.addAll(['p0', 'p1', 'p2']);
    library.transferResult = Completer<TransferResult>();
    final transfer = gallery.transferSelectionTo(album);
    expect(gallery.isTransferring, true);
    for (var event = 0; event < 10; event++) {
      library.controller.add(null);
    }
    await flushEvents();
    expect(library.loadCount, 1);
    library.transferResult!.complete(
      const TransferResult(
        successfulIds: ['p0'],
        skippedIds: ['p1'],
        failures: [TransferFailure(photoId: 'p2', reason: '不可写入')],
        cancelled: true,
      ),
    );
    final result = await transfer;
    expect(result!.cancelled, true);
    expect(gallery.selection.toSet(), {'p2'});
    expect(gallery.isTransferring, false);
    expect(library.loadCount, 2);
    expect(gallery.settings.recentTargets, contains(album.key));
    expect(gallery.settings.plans, isEmpty);
  });

  test(
    'transfer errors release the refresh hold and preserve selection',
    () async {
      gallery.selection.add('p0');
      library.transferResult = Completer<TransferResult>();
      final transfer = gallery.transferSelectionTo(
        const Album(path: 'Pictures/整理/'),
      );
      final failure = expectLater(transfer, throwsA(isA<PlatformException>()));
      library.transferResult!.completeError(
        PlatformException(code: 'write_failed'),
      );
      await failure;
      expect(gallery.isTransferring, false);
      expect(gallery.selection, contains('p0'));
      expect(library.loadCount, 2);
    },
  );

  test(
    'scan errors still reload indexed photos and leave refresh usable',
    () async {
      library.scan = Completer<int>();
      final refresh = gallery.refreshFromStorage();
      library.scan!.completeError(
        PlatformException(code: 'scan_failed', message: '扫描失败'),
      );
      await refresh;
      expect(notices, ['扫描失败']);
      expect(gallery.visiblePhotos, hasLength(3));
      expect(gallery.isRefreshing, false);
      library.scan = null;
      await gallery.refreshFromStorage();
      expect(library.scanCount, 2);
    },
  );

  test('only the controller is notified for data changes, not individual photo selections', () async {
    var galleryNotifications = 0;
    gallery.addListener(() => galleryNotifications++);
    gallery.selection.addAll(['p0', 'p1']);
    gallery.selection.remove('p1');
    expect(galleryNotifications, 0);
    await gallery.requestReload();
    expect(galleryNotifications, 1);
  });

  test(
    'dispose during a pending read ignores its result and stops later requests',
    () async {
      final other = GalleryController(
        library: library,
        settings: library.settings,
        onNotice: notices.add,
      );
      library.delayReads = true;
      var notifications = 0;
      other.addListener(() => notifications++);
      final pending = other.requestReload();
      other.dispose();
      library.reads.single.complete(library.currentSnapshot);
      await pending;
      await other.requestReload();
      expect(notifications, 0);
      expect(library.reads, hasLength(1));
    },
  );
}
