import 'package:flutter/material.dart';
import 'package:fastphoto/l10n/localization.dart';

import 'package:fastphoto/data/media_library.dart';
import 'package:fastphoto/data/thumbnail_cache.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';
import 'package:fastphoto/shared/photo_hero.dart';
import 'package:fastphoto/shared/interaction_tuning.dart';

class PhotoPreview extends StatefulWidget {
  const PhotoPreview({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.cache,
    required this.library,
    required this.settings,
    required this.selected,
    required this.onToggle,
    this.onPhotoChanged,
  });
  final List<Photo> photos;
  final int initialIndex;
  final ThumbnailCache cache;
  final MediaLibrary library;
  final AppSettings settings;
  final Set<String> selected;
  final void Function(Photo) onToggle;
  final ValueChanged<Photo>? onPhotoChanged;
  @override
  State<PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<PhotoPreview> {
  late int index = widget.initialIndex;
  late final pages = PageController(initialPage: index);
  bool zoomed = false;
  bool detailsOpen = false, swipeEligible = false;
  final pointers = <int>{};
  Offset? swipeStart;
  Offset swipeDelta = Offset.zero;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${index + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.photoDetails,
            icon: const Icon(Icons.info_outline),
            onPressed: () => _details(photo),
          ),
          IconButton(
            tooltip: widget.selected.contains(photo.id)
                ? context.l10n.deselect
                : context.l10n.selectPhoto,
            icon: Icon(
              widget.selected.contains(photo.id)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () => setState(() => widget.onToggle(photo)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Listener(
              onPointerDown: (event) {
                pointers.add(event.pointer);
                if (pointers.length == 1) {
                  swipeEligible = !zoomed;
                  swipeStart = event.position;
                  swipeDelta = Offset.zero;
                } else {
                  swipeEligible = false;
                }
              },
              onPointerMove: (event) {
                if (swipeStart != null) {
                  swipeDelta = event.position - swipeStart!;
                }
              },
              onPointerCancel: (event) {
                pointers.remove(event.pointer);
                swipeEligible = false;
              },
              onPointerUp: (event) {
                pointers.remove(event.pointer);
                if (pointers.isNotEmpty ||
                    !swipeEligible ||
                    zoomed ||
                    detailsOpen) {
                  return;
                }
                swipeEligible = false;
                if (swipeDelta.dy.abs() < InteractionTuning.previewSwipe ||
                    swipeDelta.dy.abs() < swipeDelta.dx.abs() * 1.4) {
                  return;
                }
                if (swipeDelta.dy < 0) {
                  _details(widget.photos[index]);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: PageView.builder(
                controller: pages,
                itemCount: widget.photos.length,
                physics: zoomed ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (page) {
                  setState(() {
                    index = page;
                    zoomed = false;
                  });
                  widget.onPhotoChanged?.call(widget.photos[page]);
                },
                itemBuilder: (context, i) => _ZoomPhoto(
                  key: ValueKey(widget.photos[i].id),
                  photo: widget.photos[i],
                  cache: widget.cache,
                  heroEnabled: i == index && !zoomed,
                  onZoom: (v) {
                    if (i == index && v != zoomed) {
                      setState(() => zoomed = v);
                    }
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
              child: Column(
                children: [
                  Text(
                    photo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${photoDate(context, photo.date)} · ${photo.displayAlbumName(context.l10n)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.l10n.previewHint,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _details(Photo photo) async {
    if (detailsOpen) return;
    detailsOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints.tightFor(
        width: MediaQuery.sizeOf(context).width,
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: .65,
        minChildSize: .35,
        maxChildSize: .94,
        expand: false,
        builder: (context, controller) => SizedBox(
          width: double.infinity,
          child: _PhotoDetails(
            photo: photo,
            settings: widget.settings,
            library: widget.library,
            controller: controller,
          ),
        ),
      ),
    );
    detailsOpen = false;
  }
}

class _PhotoDetails extends StatefulWidget {
  const _PhotoDetails({
    required this.photo,
    required this.settings,
    required this.library,
    required this.controller,
  });
  final Photo photo;
  final AppSettings settings;
  final MediaLibrary library;
  final ScrollController controller;
  @override
  State<_PhotoDetails> createState() => _PhotoDetailsState();
}

class _PhotoDetailsState extends State<_PhotoDetails> {
  late final details = widget.library.details(
    widget.photo.id,
    widget.settings.showLocation,
  );
  Future<String?>? address;
  String? addressLocale;
  Future<void> _open(double lat, double lon, String provider) async {
    try {
      await widget.library.openMap(
        lat,
        lon,
        provider,
        label: context.l10n.photoLocation,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.openMapFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    if (addressLocale != context.l10n.localeName) {
      addressLocale = context.l10n.localeName;
      address = null;
    }
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      children: [
        Text(
          context.l10n.photoDetails,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 22),
        SelectableText(
          photo.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(photoDate(context, photo.date, includeTime: true)),
        const SizedBox(height: 8),
        Text(
          '${photo.width} × ${photo.height} · ${(photo.size / 1024 / 1024).toStringAsFixed(2)} MB',
        ),
        const SizedBox(height: 8),
        SelectableText(photo.path),
        const SizedBox(height: 8),
        Text(
          widget.settings.isOrganized(photo)
              ? context.l10n.organized
              : context.l10n.pending,
        ),
        if (photo.copyAlbums.isNotEmpty)
          Text(
            context.l10n.copiedToAlbums(
              photo.copyAlbums.join(context.l10n.listSeparator),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
        Text(
          context.l10n.photoLocation,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (!widget.settings.showLocation)
          Text(context.l10n.enableLocationHint)
        else
          FutureBuilder<Map<Object?, Object?>>(
            future: details,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(context.l10n.locationReadFailed);
              }
              final data = snapshot.data;
              if (data == null) return const LinearProgressIndicator();
              if (data['latitude'] == null) {
                return Text(
                  localizedMessage(
                    context.l10n,
                    data['locationStatus'] as String? ?? 'noPhotoLocation',
                  ),
                );
              }
              final lat = (data['latitude'] as num).toDouble(),
                  lon = (data['longitude'] as num).toDouble();
              if (widget.settings.resolveAddress) {
                address ??= widget.library
                    .reverseGeocode(lat, lon, locale: context.l10n.localeName)
                    .timeout(const Duration(seconds: 7), onTimeout: () => null)
                    .catchError((Object _) => null);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                    key: const ValueKey('photo-coordinates'),
                  ),
                  if (address != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FutureBuilder<String?>(
                        future: address,
                        builder: (context, place) => Text(
                          place.connectionState != ConnectionState.done
                              ? context.l10n.lookingUpAddress
                              : (place.data?.isNotEmpty == true
                                    ? place.data!
                                    : context.l10n.addressLookupFailed),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _open(lat, lon, 'amap'),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(context.l10n.amap),
                      ),
                      OutlinedButton(
                        onPressed: () => _open(lat, lon, 'google'),
                        child: Text(context.l10n.googleMaps),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ZoomPhoto extends StatefulWidget {
  const _ZoomPhoto({
    super.key,
    required this.photo,
    required this.cache,
    required this.onZoom,
    required this.heroEnabled,
  });
  final Photo photo;
  final ThumbnailCache cache;
  final ValueChanged<bool> onZoom;
  final bool heroEnabled;
  @override
  State<_ZoomPhoto> createState() => _ZoomPhotoState();
}

class _ZoomPhotoState extends State<_ZoomPhoto> {
  final transform = TransformationController();
  Offset doubleTap = Offset.zero;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: (d) => doubleTap = d.localPosition,
    onDoubleTap: () {
      final isZoomed = transform.value.getMaxScaleOnAxis() > 1.01;
      transform.value = isZoomed
          ? Matrix4.identity()
          : (Matrix4.identity()
              ..translateByDouble(
                -doubleTap.dx * 1.5,
                -doubleTap.dy * 1.5,
                0,
                1,
              )
              ..scaleByDouble(2.5, 2.5, 1, 1));
      widget.onZoom(!isZoomed);
    },
    child: InteractiveViewer(
      transformationController: transform,
      maxScale: 5,
      onInteractionUpdate: (_) =>
          widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.01),
      onInteractionEnd: (_) =>
          widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.01),
      child: Center(child: _buildPhoto()),
    ),
  );

  Widget _buildPhoto() {
    final image = PhotoHero(
      photo: widget.photo,
      cache: widget.cache,
      imageSize: 3200,
      fit: BoxFit.contain,
      enabled: widget.heroEnabled,
    );
    // Size the Hero to the image, not the black letterbox around it.
    final aspectRatio = widget.photo.displayAspectRatio;
    if (aspectRatio == null) return image;
    return AspectRatio(aspectRatio: aspectRatio, child: image);
  }
}
