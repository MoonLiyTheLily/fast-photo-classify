import 'package:flutter/rendering.dart';

/// Both the visible GridView and drag hit testing use this grid delegate.
/// Changing padding, spacing or aspect ratio here changes both together.
class AlbumTrayLayout {
  const AlbumTrayLayout({required this.columns});

  final int columns;
  static const padding = EdgeInsets.fromLTRB(16, 6, 16, 28);

  SliverGridDelegateWithFixedCrossAxisCount get gridDelegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: .78,
      );

  int? indexAt({
    required Offset position,
    required Size viewportSize,
    required double scrollOffset,
    required int albumCount,
  }) {
    if (!(Offset.zero & viewportSize).contains(position) || albumCount == 0) {
      return null;
    }
    final contentPosition =
        position + Offset(-padding.left, scrollOffset - padding.top);
    final contentWidth = viewportSize.width - padding.horizontal;
    if (contentPosition.dx < 0 ||
        contentPosition.dx >= contentWidth ||
        contentPosition.dy < 0) {
      return null;
    }

    // Ask Flutter for the same cell geometry it uses to paint the GridView.
    final grid = gridDelegate.getLayout(
      SliverConstraints(
        axisDirection: AxisDirection.down,
        growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle,
        scrollOffset: scrollOffset,
        precedingScrollExtent: 0,
        overlap: 0,
        remainingPaintExtent: viewportSize.height,
        crossAxisExtent: contentWidth,
        crossAxisDirection: AxisDirection.right,
        viewportMainAxisExtent: viewportSize.height,
        remainingCacheExtent: viewportSize.height,
        cacheOrigin: 0,
      ),
    );
    final firstIndex = grid.getMinChildIndexForScrollOffset(contentPosition.dy);
    for (
      var index = firstIndex;
      index < firstIndex + columns && index < albumCount;
      index++
    ) {
      final cell = grid.getGeometryForChildIndex(index);
      final bounds = Rect.fromLTWH(
        cell.crossAxisOffset,
        cell.scrollOffset,
        cell.crossAxisExtent,
        cell.mainAxisExtent,
      );
      if (bounds.contains(contentPosition)) return index;
    }
    return null; // Padding, gaps and unused cells are not drop targets.
  }
}
