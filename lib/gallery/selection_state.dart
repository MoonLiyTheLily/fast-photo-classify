import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:fastphoto/models/media_models.dart';

/// Only affected cells listen to individual membership changes. The footer
/// listens to count; pointer motion never asks the gallery to rebuild.
class PhotoSelection extends SetBase<String> {
  final _ids = <String>{};
  final _cells = <String, ValueNotifier<bool>>{};
  final count = ValueNotifier<int>(0);
  ValueListenable<bool> watch(String id) =>
      _cells.putIfAbsent(id, () => ValueNotifier(contains(id)));
  @override
  Iterator<String> get iterator => _ids.iterator;
  @override
  int get length => _ids.length;
  @override
  bool contains(Object? value) => _ids.contains(value);
  @override
  String? lookup(Object? value) => _ids.lookup(value);
  @override
  Set<String> toSet() => _ids.toSet();
  @override
  bool add(String value) {
    if (!_ids.add(value)) return false;
    _cells[value]?.value = true;
    count.value = length;
    return true;
  }

  @override
  bool remove(Object? value) {
    if (!_ids.remove(value)) return false;
    _cells[value]?.value = false;
    count.value = length;
    return true;
  }

  void dispose() {
    for (final cell in _cells.values) {
      cell.dispose();
    }
    count.dispose();
  }
}

class SweepSelection {
  SweepSelection(this.photos, this.selection, this.anchor)
    : baseline = selection.toSet(),
      current = anchor {
    selection.add(photos[anchor].id);
  }
  final List<Photo> photos;
  final PhotoSelection selection;
  final Set<String> baseline;
  final int anchor;
  int current;
  void move(int next) {
    if (current == next) return;
    // Only the interval between the previous and next endpoint can change.
    final low = current < next ? current : next;
    final high = current > next ? current : next;
    final start = anchor < next ? anchor : next;
    final end = anchor > next ? anchor : next;
    for (var i = low; i <= high; i++) {
      final id = photos[i].id;
      if ((i >= start && i <= end) || baseline.contains(id)) {
        selection.add(id);
      } else {
        selection.remove(id);
      }
    }
    current = next;
  }
}

/// Extends the current gesture's contiguous range without losing older selections.
Set<String> rangeSelection(
  List<Photo> photos,
  Set<String> baseline,
  int anchor,
  int current,
) {
  final result = {...baseline};
  final start = anchor < current ? anchor : current;
  final end = anchor > current ? anchor : current;
  for (var i = start; i <= end; i++) {
    result.add(photos[i].id);
  }
  return result;
}
