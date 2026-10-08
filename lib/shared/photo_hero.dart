import 'package:flutter/material.dart';

import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/shared/photo_image.dart';

/// The same photo surface in the grid and preview. Selection controls stay
/// outside this widget so only the image travels between the two routes.
class PhotoHero extends StatelessWidget {
  const PhotoHero({
    super.key,
    required this.photo,
    required this.cache,
    this.radius = 0,
    this.imageSize = 360,
    this.fit = BoxFit.cover,
    this.enabled = true,
  });

  final Photo photo;
  final ThumbnailCache cache;
  final double radius;
  final int imageSize;
  final BoxFit fit;
  final bool enabled;

  static String tagFor(String photoId) => 'photo-hero-$photoId';

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: enabled && !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tagFor(photo.id),
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: _buildFlight,
      child: _PhotoSurface(
        radius: radius,
        child: PhotoImage(
          photo: photo,
          cache: cache,
          size: imageSize,
          placeholderSize: imageSize > 360 ? 360 : null,
          fit: fit,
        ),
      ),
    ),
  );

  Widget _buildFlight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = (fromContext.widget as Hero).child as _PhotoSurface;
    final to = (toContext.widget as Hero).child as _PhotoSurface;
    final opening = direction == HeroFlightDirection.push;
    // Hero's animation runs from 1 to 0 on return.
    final corners = Tween<double>(
      begin: opening ? from.radius : to.radius,
      end: opening ? to.radius : from.radius,
    );
    return AnimatedBuilder(
      animation: animation,
      child: PhotoImage(
        photo: photo,
        cache: cache,
        // Decode the same image used by the preview during the flight. Keep
        // the grid thumbnail until the first full-size frame is available.
        size: 3200,
        placeholderSize: 360,
        // The changing rectangle gradually reveals the cropped thumbnail.
        fit: photo.width > 0 && photo.height > 0
            ? BoxFit.cover
            : BoxFit.contain,
      ),
      builder: (context, child) => _PhotoSurface(
        key: ValueKey('photo-flight-${photo.id}'),
        radius: corners.evaluate(animation),
        child: child!,
      ),
    );
  }
}

class _PhotoSurface extends StatelessWidget {
  const _PhotoSurface({super.key, required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
}
