import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'image_display.dart';

/// Fullscreen, pinch-to-zoom inspect view of a captured frame.
///
/// Pushed when the operator taps the live preview on a phone, where the in-place
/// preview otherwise shares the short cover-screen height with the controls
/// panel. System back or the close button exits; [InteractiveViewer] gives
/// pinch-zoom + pan so a frame can actually be inspected on a small screen.
class FullscreenImageViewer extends StatelessWidget {
  final CapturedImageData image;

  const FullscreenImageViewer({super.key, required this.image});

  static Future<void> show(BuildContext context, CapturedImageData image) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        // absolute: fullscreen image is viewed on pure black, not theme surface
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => FullscreenImageViewer(image: image),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Scaffold(
      // absolute: image canvas backdrop stays pure black regardless of theme
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 8.0,
              child: Center(
                child: ImageDisplayWidget(
                  imageData: image,
                  zoomLevel: 1.0,
                  panOffset: Offset.zero,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: colors.surface.withValues(alpha: 0.72),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon:
                        Icon(NightshadeIcons.close, color: colors.textPrimary),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
