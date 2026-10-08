import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fastphoto/models/media_models.dart';

class GalleryRow {
  const GalleryRow({
    required this.top,
    required this.height,
    required this.start,
    required this.end,
    this.date,
  });
  final double top, height;
  final int start, end;
  final DateTime? date;
  bool get header => date != null;
}

class GalleryLayout {
  GalleryLayout(this.photos, this.columns, this.width, bool group) {
    cell = (width - gap * (columns - 1)) / columns;
    var i = 0;
    var y = 0.0;
    while (i < photos.length) {
      var end = photos.length;
      if (group) {
        final d = photos[i].date;
        end = i + 1;
        while (end < photos.length &&
            DateUtils.isSameDay(d, photos[end].date)) {
          end++;
        }
        rows.add(GalleryRow(top: y, height: 58, start: i, end: end, date: d));
        y += 58;
      }
      while (i < end) {
        final next = math.min(end, i + columns);
        final row = GalleryRow(top: y, height: cell + gap, start: i, end: next);
        rows.add(row);
        for (var index = i; index < next; index++) {
          photoRows.add(row);
        }
        y += cell + gap;
        i = next;
      }
    }
    height = y;
  }
  static const gap = 3.0;
  final List<Photo> photos;
  final int columns;
  final double width;
  late final double cell, height;
  final rows = <GalleryRow>[];
  final photoRows = <GalleryRow>[];
  int? indexAt(Offset position) {
    if (position.dx < 0 ||
        position.dx >= width ||
        position.dy < 0 ||
        position.dy >= height) {
      return null;
    }
    var lo = 0, hi = rows.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final row = rows[mid];
      if (position.dy < row.top) {
        hi = mid - 1;
      } else if (position.dy >= row.top + row.height) {
        lo = mid + 1;
      } else {
        if (row.header) {
          return null;
        }
        final column = (position.dx / (cell + gap)).floor();
        final index = row.start + column;
        return index < row.end ? index : null;
      }
    }
    return null;
  }

  double topOf(int index) => photoRows[index].top;

  Offset centerOf(int index) {
    final row = photoRows[index];
    return Offset(
      (index - row.start) * (cell + gap) + cell / 2,
      row.top + cell / 2,
    );
  }
}
