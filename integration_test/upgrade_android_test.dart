import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Non-destructive native checks on the isolated FastPhotoQA emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android persists nested plans, transliterates Chinese and falls back from geocoding',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('FastPhoto 0.2 · 原生接口验证'))),
        ),
      );
      final library = AndroidMediaLibrary();
      if ((await library.load()).permission != 'full') {
        await library.requestPermission();
      }
      final before = await library.loadSettings();
      final settings = AppSettings.fromMap(before.toMap());
      settings.sourceKeys = [
        'external_primary|Pictures/QQ/',
        'external_primary|Pictures/Weixin/',
      ];
      settings.targetKeys = [
        'external_primary|Pictures/旅行/',
        'external_primary|Pictures/阿宝/',
      ];
      settings.albumRules = {'external_primary|Pictures/QQ/': false};
      settings.albumSort = AlbumSort.recent;
      settings.sourceAll = false;
      settings.targetAll = false;
      settings.plans = [settings.capturePlan('测试：QQ 和微信')];
      try {
        await library.saveSettings(settings);
        final restored = await library.loadSettings();
        expect(restored.toMap(), settings.toMap());
        for (final name in ['旅行', '阿宝', 'Apple', 'com.example.qa']) {
          await library.createAlbum(name);
        }
        final snapshot = await library.load();
        expect(snapshot.sortNames['旅行'], 'luxing');
        expect(snapshot.sortNames['阿宝'], 'abao');
        final albums = snapshot.albums
            .where(
              (a) => ['旅行', '阿宝', 'Apple', 'com.example.qa'].contains(a.name),
            )
            .toList();
        expect(AppSettings().destinations(albums).map((a) => a.name), [
          '阿宝',
          '旅行',
          'Apple',
          'com.example.qa',
        ]);
        expect(snapshot.photos, isNotEmpty);
        expect(snapshot.photos.first.modified, greaterThan(0));
        final address = await library
            .reverseGeocode(31.2304, 121.4737)
            .timeout(const Duration(seconds: 9));
        expect(address == null || address.isNotEmpty, true);
        final image = await library.thumbnail(snapshot.photos.first.id, 360);
        expect(
          image,
          isNotEmpty,
          reason: 'Address lookup must not block photo reads.',
        );
      } finally {
        await library.saveSettings(before);
      }
    },
  );
}
