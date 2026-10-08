import 'package:flutter/material.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/shared/interaction_tuning.dart';
import 'package:fastphoto/shared/photo_image.dart';

class PhotoStack extends StatelessWidget {
  const PhotoStack({
    super.key,
    required this.photos,
    required this.cache,
    required this.count,
    this.origins = const [],
  });
  final List<Photo> photos;
  final ThumbnailCache cache;
  final int count;
  final List<Offset> origins;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : InteractionTuning.gather,
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => SizedBox(
      width: 112,
      height: 126,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = photos.length - 1; i >= 0; i--)
            Transform.translate(
              offset:
                  Offset((i - 1) * 8 * value, i * 4 * value) +
                  (i < origins.length ? origins[i] : Offset.zero) * (1 - value),
              child: Transform.rotate(
                angle: (i - 1) * .12 * value,
                child: Container(
                  width: 92,
                  height: 104,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 16,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: PhotoImage(photo: photos[i], cache: cache),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
