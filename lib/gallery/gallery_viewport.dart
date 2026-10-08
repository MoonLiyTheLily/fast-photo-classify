import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Converts between photo-content coordinates and the visible part of a
/// sliver viewport. Header sizes come from Flutter's layout, not copied values.
class GalleryViewport {
  const GalleryViewport({
    required this.scrollBounds,
    required this.filtersBottom,
    required this.contentStart,
    required this.scrollOffset,
  });

  static const horizontalPadding = 4.0;
  final Rect scrollBounds;
  final double filtersBottom, contentStart, scrollOffset;

  Rect get visibleBounds => Rect.fromLTRB(
    scrollBounds.left + horizontalPadding,
    math.min(scrollBounds.bottom, math.max(scrollBounds.top, filtersBottom)),
    scrollBounds.right - horizontalPadding,
    scrollBounds.bottom,
  );

  Offset get _contentOrigin => Offset(
    scrollBounds.left + horizontalPadding,
    scrollBounds.top + contentStart - scrollOffset,
  );

  Offset toContent(Offset globalPosition) => globalPosition - _contentOrigin;
  Offset toGlobal(Offset contentPosition) => contentPosition + _contentOrigin;

  double offsetToReveal({required double photoTop, required double photoSize}) {
    final top = toGlobal(Offset(0, photoTop)).dy;
    final bottom = top + photoSize;
    if (top < visibleBounds.top) return scrollOffset + top - visibleBounds.top;
    if (bottom > visibleBounds.bottom) {
      return scrollOffset + bottom - visibleBounds.bottom;
    }
    return scrollOffset;
  }

  double offsetToCenter(double contentY) =>
      contentStart + contentY - (visibleBounds.center.dy - scrollBounds.top);
}
