import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/shared/interaction_tuning.dart';
import 'package:fastphoto/shared/photo_hero.dart';

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.photo,
    required this.cache,
    required this.selected,
    required this.selecting,
    required this.organized,
    required this.onToggle,
    required this.onPreview,
  });
  final Photo photo;
  final ThumbnailCache cache;
  final bool selected, selecting, organized;
  final VoidCallback onToggle, onPreview;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: context.l10n.photoSemantics(
        photo.name,
        organized ? context.l10n.organized : context.l10n.pending,
      ),
      selected: selected,
      child: GestureDetector(
        onTap: onPreview,
        child: ColoredBox(
          color: primary.withValues(alpha: .15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPadding(
                duration: ModalRoute.isCurrentOf(context) == false
                    ? Duration.zero
                    : InteractionTuning.selection,
                padding: EdgeInsets.all(selected ? 6 : 0),
                child: PhotoHero(
                  photo: photo,
                  cache: cache,
                  radius: selected ? 10 : 2,
                ),
              ),
              if (selected)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: primary, width: 2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              if (organized)
                Positioned(
                  left: selected ? 10 : 5,
                  bottom: selected ? 10 : 5,
                  child: Tooltip(
                    message: (photo.copyAlbums.isNotEmpty
                        ? context.l10n.photoInMultipleAlbums(
                            photo.displayAlbumName(context.l10n),
                          )
                        : context.l10n.photoInAlbum(
                            photo.displayAlbumName(context.l10n),
                          )),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xDE173C37),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        child: Icon(
                          Icons.folder_copy_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selecting)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Semantics(
                    button: true,
                    label: selected
                        ? context.l10n.deselectPhotoNamed(photo.name)
                        : context.l10n.selectPhotoNamed(photo.name),
                    child: GestureDetector(
                      key: ValueKey('check-${photo.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? primary : Colors.black38,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
