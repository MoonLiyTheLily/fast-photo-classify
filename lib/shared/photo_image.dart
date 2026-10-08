import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';

class PhotoImage extends StatefulWidget {
  const PhotoImage({
    super.key,
    required this.photo,
    required this.cache,
    this.size = 360,
    this.fit = BoxFit.cover,
    this.placeholderSize,
  });
  final Photo photo;
  final ThumbnailCache cache;
  final int size;
  final BoxFit fit;

  /// An already loaded thumbnail to show until the larger image has a frame.
  final int? placeholderSize;
  @override
  State<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends State<PhotoImage> {
  late Future<Uint8List?> future = widget.cache.get(
    widget.photo.id,
    widget.size,
  );
  @override
  void didUpdateWidget(PhotoImage old) {
    super.didUpdateWidget(old);
    if (old.photo.id != widget.photo.id ||
        old.size != widget.size ||
        old.cache != widget.cache) {
      old.cache.release(old.photo.id, old.size);
      future = widget.cache.get(widget.photo.id, widget.size);
    }
  }

  @override
  void dispose() {
    widget.cache.release(widget.photo.id, widget.size);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: FutureBuilder<Uint8List?>(
      key: ValueKey((widget.photo.id, widget.size, widget.cache)),
      future: future,
      initialData: widget.cache.peek(widget.photo.id, widget.size),
      builder: (context, snapshot) {
        final thumbnail = widget.placeholderSize == null
            ? null
            : widget.cache.peek(widget.photo.id, widget.placeholderSize!);
        final data = snapshot.data ?? thumbnail;
        if (data == null) {
          return _placeholder(
            context,
            failed: snapshot.connectionState == ConnectionState.done,
          );
        }
        return Image.memory(
          data,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          // Loaded bytes do not imply a decoded frame. This also protects a
          // newly mounted preview when Hero removes its in-flight image.
          frameBuilder: (context, child, frame, synchronous) {
            if (synchronous || frame != null) return child;
            if (thumbnail != null && !identical(data, thumbnail)) {
              return _thumbnail(thumbnail);
            }
            return _placeholder(context);
          },
          errorBuilder: (_, _, _) => thumbnail == null
              ? _placeholder(context, failed: true)
              : _thumbnail(thumbnail),
        );
      },
    ),
  );

  Widget _thumbnail(Uint8List bytes) => Image.memory(
    bytes,
    fit: widget.fit,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    frameBuilder: (context, child, frame, synchronous) =>
        synchronous || frame != null ? child : _placeholder(context),
    errorBuilder: (context, _, _) => _placeholder(context, failed: true),
  );

  Widget _placeholder(BuildContext context, {bool failed = false}) =>
      ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            failed ? Icons.broken_image_outlined : Icons.image_outlined,
            size: 24,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .45),
          ),
        ),
      );
}
