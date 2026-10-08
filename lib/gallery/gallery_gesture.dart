import 'dart:async';

import 'package:flutter/gestures.dart';

import 'package:fastphoto/shared/interaction_tuning.dart';

/// A long press claims the pointer; ordinary swipes yield to the scroll view.
class GalleryGestureRecognizer extends OneSequenceGestureRecognizer {
  void Function(int pointer, Offset position)? onHold;
  void Function(Offset position)? onMove;
  void Function(bool cancelled)? onEnd;
  void Function(double scale)? onPinch;
  bool Function(Offset position)? canStart;
  Timer? _timer;
  final _points = <int, Offset>{};
  Offset? _origin;
  int? _primary;
  bool _holding = false, _pinching = false;
  double _initialDistance = 1;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_holding) {
      return;
    }
    startTrackingPointer(event.pointer, event.transform);
    _points[event.pointer] = event.position;
    if (_points.length == 1) {
      _primary = event.pointer;
      _origin = event.position;
      if (canStart?.call(event.position) ?? false) {
        _timer = Timer(InteractionTuning.hold, () {
          if (_points.length != 1) {
            return;
          }
          _holding = true;
          resolve(GestureDisposition.accepted);
          onHold?.call(_primary!, _points[_primary]!);
        });
      }
    } else if (_points.length == 2) {
      _timer?.cancel();
      _pinching = true;
      _initialDistance = (_points.values.first - _points.values.last).distance
          .clamp(1, double.infinity);
      resolve(GestureDisposition.accepted);
      onPinch?.call(1);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_points.containsKey(event.pointer)) {
      return;
    }
    if (event is PointerMoveEvent) {
      _points[event.pointer] = event.position;
      if (_pinching && _points.length >= 2) {
        onPinch?.call(
          (_points.values.first - _points.values.elementAt(1)).distance /
              _initialDistance,
        );
      } else if (_holding && event.pointer == _primary) {
        onMove?.call(event.position);
      } else if (!_pinching &&
          (event.position - _origin!).distance > kTouchSlop) {
        _timer?.cancel();
        resolve(GestureDisposition.rejected);
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_holding && event.pointer == _primary) {
        onEnd?.call(event is PointerCancelEvent);
      }
      _timer?.cancel();
      _points.remove(event.pointer);
      stopTrackingPointer(event.pointer);
      if (!_holding && !_pinching) {
        resolve(GestureDisposition.rejected);
      }
    }
  }

  @override
  void rejectGesture(int pointer) {
    _timer?.cancel();
    _points.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _timer?.cancel();
    _points.clear();
    _holding = false;
    _pinching = false;
    _primary = null;
  }

  @override
  String get debugDescription => 'photo hold / pinch';
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
