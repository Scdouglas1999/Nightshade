import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../imaging/widgets/guiding_panel.dart' show CompactGuidingGraph;

/// Read-only guiding card: graph + RMS values, reusing
/// `CompactGuidingGraph` from the Imaging screen.
class RunDashboardGuidingCard extends ConsumerWidget {
  const RunDashboardGuidingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final guider = ref.watch(guiderStateProvider);
    final graphData = ref.watch(guideGraphProvider);
    final isConnected =
        guider.connectionState == DeviceConnectionState.connected;

    // Effective imaging scale (arcsec/pixel) from the active equipment +
    // connected camera. When available we grade guiding RMS as a fraction of
    // the pixel scale (good < 0.5 px, fair < 1 px) instead of fixed 1"/2"
    // thresholds that are meaningless at a wildly different scale — sub-arcsec
    // RMS is poor at 0.5"/px but excellent at 3"/px.
    final scaleAsync = ref.watch(framingFOVProvider);
    final scale = scaleAsync.valueOrNull;
    final arcsecPerPixel = (scale != null &&
            scale.status == EquipmentStatus.ready &&
            scale.equipment != null &&
            scale.equipment!.imageScale > 0)
        ? scale.equipment!.imageScale
        : null;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.crosshair, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'GUIDING',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              if (isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: NightshadeDecorations.statusChip(
                    guider.isGuiding ? colors.success : colors.textMuted,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusXs),
                    bordered: false,
                  ),
                  child: Text(
                    guider.isGuiding
                        ? 'Guiding'
                        : guider.isCalibrating
                            ? 'Calibrating'
                            : 'Idle',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      fontWeight: FontWeight.w700,
                      color: guider.isGuiding
                          ? colors.success
                          : guider.isCalibrating
                              ? colors.warning
                              : colors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          CompactGuidingGraph(
            colors: colors,
            data: graphData,
            isGuiding: guider.isGuiding,
            isConnected: isConnected,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RmsStat(
                colors: colors,
                label: 'RA',
                value: guider.rmsRa,
                arcsecPerPixel: arcsecPerPixel,
              ),
              _RmsStat(
                colors: colors,
                label: 'Dec',
                value: guider.rmsDec,
                arcsecPerPixel: arcsecPerPixel,
              ),
              _RmsStat(
                colors: colors,
                label: 'Total',
                value: guider.rmsTotal,
                isTotal: true,
                arcsecPerPixel: arcsecPerPixel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RmsStat extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double? value;
  final bool isTotal;

  /// Effective imaging scale (arcsec/pixel). When non-null the RMS (reported
  /// in arcsec) is graded as a fraction of a pixel; when null we fall back to
  /// the conventional fixed arcsec thresholds.
  final double? arcsecPerPixel;

  const _RmsStat({
    required this.colors,
    required this.label,
    required this.value,
    this.isTotal = false,
    this.arcsecPerPixel,
  });

  Color _color() {
    final v = value;
    if (v == null) return colors.textMuted;
    final scale = arcsecPerPixel;
    if (scale != null && scale > 0) {
      // Grade by guiding error in *pixels* of the imaging train. Sub-half-pixel
      // RMS is excellent; under a pixel is acceptable; more smears stars.
      final px = v / scale;
      if (px < 0.5) return colors.success;
      if (px < 1.0) return colors.warning;
      return colors.error;
    }
    // No scale available: fixed arcsec thresholds (legacy behaviour).
    if (v < 1.0) return colors.success;
    if (v < 2.0) return colors.warning;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: colors.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value != null ? '${value!.toStringAsFixed(2)}"' : '—',
          style: NightshadeTypography.withTabular(
            TextStyle(
              fontSize: isTotal ? NightshadeTypography.fontSize14 : NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w700,
              color: _color(),
            ),
          ),
        ),
      ],
    );
  }
}
