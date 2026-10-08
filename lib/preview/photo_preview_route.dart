import 'package:flutter/material.dart';

import 'package:fastphoto/shared/interaction_tuning.dart';

/// Fade the preview chrome while PhotoHero moves the image itself.
class PhotoPreviewRoute extends PageRouteBuilder<void> {
  PhotoPreviewRoute({
    required WidgetBuilder builder,
    required bool reduceMotion,
  }) : super(
         allowSnapshotting: false,
         transitionDuration: reduceMotion
             ? Duration.zero
             : InteractionTuning.previewOpen,
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : InteractionTuning.previewClose,
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) =>
             FadeTransition(opacity: animation, child: child),
       );
}
