import 'package:fastphoto/l10n/generated/app_localizations.dart';
import 'package:fastphoto/l10n/localization.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/transfer_result.dart';
import 'package:fastphoto/organizer/organizer_sheet.dart';
import 'package:fastphoto/settings/settings_sheet.dart';
import 'package:fastphoto/preview/photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_library.dart';
import 'gallery_test.dart' show startApp, photo;

class EnglishLibrary extends FakeLibrary {
  EnglishLibrary({super.permission, bool tutorial = false})
    : super(photoCount: 3, albumCount: 0) {
    albums = [
      const Album(path: 'Pictures/Travel/'),
      const Album(path: 'Pictures/Family/'),
    ];
    settings.tutorialSeen = !tutorial;
  }
}

class ReadErrorLibrary extends EnglishLibrary {
  @override
  Future<LibrarySnapshot> load() async =>
      throw PlatformException(code: 'media_error', message: 'photoUnavailable');
}

class TransferErrorLibrary extends EnglishLibrary {
  @override
  Future<TransferResult> transfer(
    List<String> ids,
    Album album,
    bool copy,
  ) async => TransferResult(
    failures: [
      for (final id in ids)
        TransferFailure(photoId: id, reason: 'crossVolumeMoveUnsupported'),
    ],
  );

  @override
  Future<Map<Object?, Object?>> details(String id, bool location) async => {
    'locationStatus': 'locationPermissionRequired',
  };
}

void expectEnglishUi(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final chinese = RegExp(r'[\u3400-\u9fff]');
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    expect(
      chinese.hasMatch(text) && text != '中文',
      false,
      reason: 'Untranslated text: $text',
    );
  }
}

void main() {
  for (final size in [const Size(360, 740), const Size(430, 900)]) {
    testWidgets('English gallery, settings, plans and preview fit $size', (
      tester,
    ) async {
      final library = EnglishLibrary();
      await startApp(
        tester,
        library,
        size: size,
        locale: const Locale('en', 'US'),
      );
      expect(find.text('All photos'), findsOneWidget);
      expect(find.text('3 photos · 3 pending'), findsOneWidget);
      expectEnglishUi(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsOneWidget);
      expect(find.text('Your preferences'), findsOneWidget);
      expect(find.text('Group by date'), findsOneWidget);
      expectEnglishUi(tester);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Scope & plans'));
      await tester.tap(find.byTooltip('Scope & plans'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizerSheet), findsOneWidget);
      for (final tab in ['Targets', 'Rules', 'Plans']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expectEnglishUi(tester);
      }
      expect(find.text('Default plan'), findsOneWidget);
      await tester.tap(find.byTooltip('Close scope settings'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();

      await tester.tap(photo(0));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPreview), findsOneWidget);
      expectEnglishUi(tester);
      await tester.tap(find.byTooltip('Photo details'));
      await tester.pumpAndSettle();
      expect(find.text('Photo location'), findsOneWidget);
      expectEnglishUi(tester);
    });
  }

  testWidgets('English permission screen and tutorial are translated', (
    tester,
  ) async {
    await startApp(
      tester,
      EnglishLibrary(permission: 'denied', tutorial: true),
      size: const Size(360, 640),
      locale: const Locale('en'),
    );
    expect(find.text('Organize photos in three steps'), findsOneWidget);
    expectEnglishUi(tester);
    await tester.tap(find.text('Start organizing'));
    await tester.pumpAndSettle();
    expect(find.text('A place for every photo'), findsOneWidget);
    expect(find.text('Allow photo access'), findsOneWidget);
    expectEnglishUi(tester);
  });

  testWidgets(
    'an existing read error is retranslated after a language change',
    (tester) async {
      await startApp(tester, ReadErrorLibrary(), locale: const Locale('en'));
      expect(
        find.text(
          'The photo no longer exists or access permission has changed.',
        ),
        findsOneWidget,
      );
      tester.platformDispatcher.localesTestValue = [const Locale('zh')];
      await tester.pumpAndSettle();
      expect(find.text('照片已不存在或访问权限已变更'), findsOneWidget);
    },
  );

  testWidgets('native location status is translated in photo details', (
    tester,
  ) async {
    final library = TransferErrorLibrary()..settings.showLocation = true;
    await startApp(tester, library, locale: const Locale('en'));
    await tester.tap(photo(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Photo details'));
    await tester.pumpAndSettle();
    expect(
      find.text('Allow access to photo location metadata to view it.'),
      findsOneWidget,
    );
    expectEnglishUi(tester);
  });

  testWidgets(
    'native transfer failures show translated reasons and retain selection',
    (tester) async {
      await startApp(
        tester,
        TransferErrorLibrary(),
        locale: const Locale('en'),
      );
      await tester.longPress(photo(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to album'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('album-external_primary|Pictures/Travel/')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          '1 photo was not processed: Moving between storage volumes is not supported. Switch to copying.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 selected'), findsOneWidget);
      expectEnglishUi(tester);
    },
  );

  testWidgets(
    'user album and plan names stay unchanged when the language changes',
    (tester) async {
      final library = EnglishLibrary();
      library.albums.add(const Album(path: 'Pictures/我的 Album/'));
      library.settings.plans.add(library.settings.capturePlan('我的 Plan'));
      await startApp(tester, library, locale: const Locale('en'));
      await tester.ensureVisible(find.byTooltip('Scope & plans'));
      await tester.tap(find.byTooltip('Scope & plans'));
      await tester.pumpAndSettle();
      expect(find.text('我的 Album'), findsOneWidget);
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      expect(find.text('Default plan'), findsOneWidget);
      expect(find.text('我的 Plan'), findsOneWidget);
      tester.platformDispatcher.localesTestValue = [const Locale('zh')];
      await tester.pumpAndSettle();
      expect(find.text('默认方案'), findsOneWidget);
      expect(find.text('我的 Plan'), findsOneWidget);
    },
  );

  test('count messages use singular and plural forms and unknown errors have a fallback', () {
    final strings = lookupAppLocalizations(const Locale('en'));
    expect(strings.photoCountFull(1), '1 photo');
    expect(strings.photoCountFull(2), '2 photos');
    expect(
      localizedMessage(strings, 'crossVolumeMoveUnsupported'),
      'Moving between storage volumes is not supported. Switch to copying.',
    );
    expect(
      localizedMessage(strings, 'unexpected system error'),
      strings.operationRetry,
    );
  });
}
