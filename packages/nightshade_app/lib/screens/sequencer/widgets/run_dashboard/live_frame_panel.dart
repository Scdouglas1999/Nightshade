import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../imaging/widgets/image_display.dart';

/// Large live-frame thumbnail for the Run dashboard.
///
/// Reuses the existing `ImageDisplayWidget` from the Imaging screen so the
/// dashboard never reimplements stretch/decoding logic.
class RunDashboardLiveFrame extends ConsumerWidget {
  const RunDashboardLiveFrame({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final currentImage = ref.watch(currentImageProvider);

    return NightshadeCard(
      padding: EdgeInsets.zero,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(NightshadeTokens.radiusLg),
          child: Stack(
            children: [
              Container(color: colors.background),
              if (currentImage != null)
                Positioned.fill(
                  child: ImageDisplayWidget(
                    imageData: currentImage,
                    zoomLevel: 1.0,
                    panOffset: Offset.zero,
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.image,
                          size: 36, color: colors.textMuted),
                      const SizedBox(height: NightshadeTokens.spaceSm),
                      Text(
                        'Waiting for first frame…',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              if (currentImage != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _FrameBadge(colors: colors, image: currentImage),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FrameBadge extends StatelessWidget {
  final NightshadeColors colors;
  final CapturedImageData image;

  const _FrameBadge({required this.colors, required this.image});

  @override
  Widget build(BuildContext context) {
    final filter = image.settings.filter;
    final exposure = image.settings.exposureTime;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.filter, size: 10, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            filter ?? 'no filter',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: colors.border),
          const SizedBox(width: 8),
          Text(
            '${exposure.toStringAsFixed(exposure >= 10 ? 0 : 1)}s',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
