import 'package:fastphoto/gallery/photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

void expectAppName(WidgetTester tester, String name) {
  final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
  expect((appBar.title! as Text).data, name);
  expect(tester.widget<Title>(find.byType(Title)).title, name);
}

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
    const Locale('en', 'GB'),
    const Locale('fr', 'FR'),
  ]) {
    testWidgets('app name follows system locale $locale', (tester) async {
      await startApp(tester, FakeLibrary(), locale: locale);
      expectAppName(tester, locale.languageCode == 'zh' ? '速理' : 'Fastphoto');
    });
  }

  testWidgets('system language changes update names and keep selected photos', (
    tester,
  ) async {
    await startApp(tester, FakeLibrary(), locale: const Locale('en', 'US'));
    expectAppName(tester, 'Fastphoto');
    await tester.longPress(photo(0));
    await tester.pumpAndSettle();
    expect(tester.widget<PhotoTile>(photo(0)).selected, true);

    tester.platformDispatcher.localesTestValue = [const Locale('zh', 'CN')];
    await tester.pumpAndSettle();
    expectAppName(tester, '速理');
    expect(tester.widget<PhotoTile>(photo(0)).selected, true);

    tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
    await tester.pumpAndSettle();
    expectAppName(tester, 'Fastphoto');
    expect(tester.widget<PhotoTile>(photo(0)).selected, true);
  });
}
