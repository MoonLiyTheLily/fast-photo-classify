import 'package:flutter/services.dart';

/// Shared adjustment points for later motion and tactile feedback tuning.
abstract final class InteractionTuning {
  static const hold = Duration(milliseconds: 380);
  static const selection = Duration(milliseconds: 120);
  static const gather = Duration(milliseconds: 240);
  static const tray = Duration(milliseconds: 220);
  static const previewOpen = Duration(milliseconds: 320);
  static const previewClose = Duration(milliseconds: 240);
  static const previewSwipe = 72.0;
  static const backgroundBlur = 7.0;
  static void pickedUp() => HapticFeedback.selectionClick();
  static void targetChanged() => HapticFeedback.selectionClick();
  static void completed() => HapticFeedback.lightImpact();
}
