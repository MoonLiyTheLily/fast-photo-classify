import 'package:flutter/material.dart';

ThemeData photoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF356AE6),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF8CB0FF) : const Color(0xFF356AE6),
        surface: dark ? const Color(0xFF101827) : const Color(0xFFF7F9FC),
        surfaceContainer: dark ? const Color(0xFF1C293D) : Colors.white,
        onSurface: dark ? const Color(0xFFEAF0FA) : const Color(0xFF17243B),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      showDragHandle: true,
    ),
    textTheme: TextTheme(
      bodySmall: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      headlineMedium: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
      ),
    ),
  );
}
