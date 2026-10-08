import 'package:fastphoto/app/fast_photo_app.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

class SavedLanguageLibrary extends FakeLibrary {
  Map<Object?, Object?> saved = {};

  @override
  Future<void> saveSettings(AppSettings settings) async {
    saved = settings.toMap();
    await super.saveSettings(settings);
  }

  @override
  Future<AppSettings> loadSettings() async =>
      saved.isEmpty ? settings : AppSettings.fromMap(saved);
}

Future<void> chooseLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('language-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String appBarTitle(WidgetTester tester) =>
    (tester.widget<SliverAppBar>(find.byType(SliverAppBar)).title! as Text)
        .data!;

void main() {
  test('old settings follow the system and each language choice survives serialization', () {
    expect(AppSettings.fromMap({}).language, AppLanguage.system);
    expect(
      AppSettings.fromMap({'language': 'unsupported'}).language,
      AppLanguage.system,
    );
    for (final language in AppLanguage.values) {
      final settings = AppSettings(
        language: language,
        copy: true,
        theme: ThemeMode.dark,
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.language, language);
      expect(restored.copy, true);
      expect(restored.theme, ThemeMode.dark);
    }
  });

  testWidgets(
    'language selection updates the open settings and title and system mode keeps following the device',
    (tester) async {
      final library = SavedLanguageLibrary();
      await startApp(
        tester,
        library,
        size: const Size(360, 740),
        locale: const Locale('en', 'US'),
      );
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await chooseLanguage(tester, '中文');
      expect(appBarTitle(tester), '速理');
      expect(find.text('语言'), findsOneWidget);
      expect(library.saved['language'], 'chinese');

      await chooseLanguage(tester, 'English');
      expect(appBarTitle(tester), 'Fastphoto');
      expect(find.text('Language'), findsOneWidget);
      expect(library.saved['language'], 'english');

      tester.platformDispatcher.localesTestValue = [const Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      expect(appBarTitle(tester), 'Fastphoto');
      await chooseLanguage(tester, 'System');
      expect(appBarTitle(tester), '速理');
      expect(library.saved['language'], 'system');
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
      await tester.pumpAndSettle();
      expect(appBarTitle(tester), 'Fastphoto');
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the chosen language is restored when the app starts again', (
    tester,
  ) async {
    final library = SavedLanguageLibrary();
    await startApp(tester, library, locale: const Locale('en'));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await chooseLanguage(tester, '中文');
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(FastPhotoApp(library: library));
    await tester.pumpAndSettle();
    expect(appBarTitle(tester), '速理');
    expect(find.text('全部照片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
