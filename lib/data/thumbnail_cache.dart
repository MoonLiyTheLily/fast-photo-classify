import 'dart:async';
import 'dart:typed_data';

import 'package:fastphoto/data/media_library.dart';

/// Bounded compressed-byte cache; Flutter separately limits decoded image memory.
class ThumbnailCache {
  ThumbnailCache(this.library);
  final MediaLibrary library;
  final _cache = <String, _ThumbnailJob>{};
  final _queue = <_ThumbnailJob>[];
  int _active = 0, _bytes = 0;
  static const concurrency = 4, maxBytes = 32 * 1024 * 1024;

  /// Reuses loaded bytes immediately, without starting another request.
  Uint8List? peek(String id, int size) => _cache['$id@$size']?.data;

  Future<Uint8List?> get(String id, int size) {
    final key = '$id@$size';
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      existing.users++;
      return existing.result.future;
    }
    final job = _ThumbnailJob(key, id, size);
    _cache[key] = job;
    _queue.add(job);
    _pump();
    return job.result.future;
  }

  void release(String id, int size) {
    final key = '$id@$size';
    final job = _cache[key];
    if (job == null) return;
    if (job.users > 0) job.users--;
    if (job.users == 0 && !job.started) {
      _queue.remove(job);
      _cache.remove(key);
      job.result.complete(null);
    }
    _trim();
  }

  void _pump() {
    while (_active < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      job.started = true;
      _active++;
      library
          .thumbnail(job.id, job.size)
          .then(
            (data) {
              job.data = data;
              job.bytes = data?.lengthInBytes ?? 0;
              if (identical(_cache[job.key], job)) _bytes += job.bytes;
              job.result.complete(data);
            },
            onError: (Object _) {
              job.result.complete(null);
            },
          )
          .whenComplete(() {
            _active--;
            _trim();
            _pump();
          });
    }
  }

  void _trim() {
    if (_cache.length <= 180 && _bytes <= maxBytes) return;
    for (final key in _cache.keys.toList()) {
      if (_cache.length <= 180 && _bytes <= maxBytes) break;
      final job = _cache[key]!;
      if (job.users == 0 && job.result.isCompleted) {
        _cache.remove(key);
        _bytes -= job.bytes;
      }
    }
  }

  void clear() {
    for (final job in _queue) {
      job.result.complete(null);
    }
    _queue.clear();
    _cache.clear();
    _bytes = 0;
  }
}

class _ThumbnailJob {
  _ThumbnailJob(this.key, this.id, this.size);
  final String key, id;
  final int size;
  final result = Completer<Uint8List?>();
  Uint8List? data;
  int users = 1, bytes = 0;
  bool started = false;
}
