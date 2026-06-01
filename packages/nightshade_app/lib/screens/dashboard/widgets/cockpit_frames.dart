import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../imaging/widgets/image_display.dart';
import 'cockpit_recent_frames.dart';

/// Merged "Frames" cockpit tile — the current sub-exposure on top of the
/// recent-frames strip, in a single self-chromed card.
///
/// Replaces the standalone `RunDashboardLiveFrame` (a tall 4:3 box) plus the
/// separate `CockpitRecentFrames` strip, which were redundant: a big "waiting
/// for first frame" panel sitting directly above a thumbnail strip. This
/// consolidation caps the current-frame image at [_frameMaxHeight] (NOT 4:3)
/// and, before any frame exists, collapses to a slim one-line "waiting" row so
/// idle never wastes vertical space.
///
/// - Current frame: `currentImageProvider` + `ImageDisplayWidget`, height-
///   capped, with the filter/exposure badge overlay.
/// - Below: the shared [RecentFramesStrip] (reuses the backend-thumbnail path).
class CockpitFrames extends ConsumerWidget {
  const CockpitFrames({super.key});

  /// Cap for the current-frame image. Deliberately short (a 16:9-ish band, not
  /// a full 4:3 hero) — the whole point of the density pass is fit-without-
  /// scroll, and the recent strip carries the per-frame history below.
  static const double _frameMaxHeight = 200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final currentImage = ref.watch(currentImageProvider);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentImage != null)
            _CurrentFrame(colors: colors, image: currentImage)
          else
            _WaitingRow(colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const RecentFramesStrip(),
        ],
      ),
    );
  }
}

/// Height-capped current-frame view with the filter/exposure badge overlay.
class _CurrentFrame extends StatelessWidget {
  final NightshadeColors colors;
  final CapturedImageData image;

  const _CurrentFrame({required this.colors, required this.image});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: CockpitFrames._frameMaxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: Stack(
          children: [
            Container(color: colors.background),
            Positioned.fill(
              child: ImageDisplayWidget(
                imageData: image,
                zoomLevel: 1.0,
                panOffset: Offset.zero,
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: _FrameBadge(colors: colors, image: image),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim one-line "waiting for first frame" row shown before any frame exists,
/// replacing the tall empty 4:3 box of the old live-frame panel.
class _WaitingRow extends StatelessWidget {
  final NightshadeColors colors;

  const _WaitingRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.image, size: 14, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            'Waiting for first frame…',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
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
            style: NightshadeTypography.withTabular(
              NightshadeTypography.captionSm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: colors.border),
          const SizedBox(width: 8),
          Text(
            '${exposure.toStringAsFixed(exposure >= 10 ? 0 : 1)}s',
            style: NightshadeTypography.withTabular(
              NightshadeTypography.captionSm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
