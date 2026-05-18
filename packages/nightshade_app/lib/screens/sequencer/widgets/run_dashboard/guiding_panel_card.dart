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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final guider = ref.watch(guiderStateProvider);
    final graphData = ref.watch(guideGraphProvider);
    final isConnected =
        guider.connectionState == DeviceConnectionState.connected;

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
                  fontSize: 11,
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
                  decoration: BoxDecoration(
                    color: (guider.isGuiding
                            ? colors.success
                            : colors.textMuted)
                        .withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusXs),
                  ),
                  child: Text(
                    guider.isGuiding
                        ? 'Guiding'
                        : guider.isCalibrating
                            ? 'Calibrating'
                            : 'Idle',
                    style: TextStyle(
                      fontSize: 10,
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
              ),
              _RmsStat(
                colors: colors,
                label: 'Dec',
                value: guider.rmsDec,
              ),
              _RmsStat(
                colors: colors,
                label: 'Total',
                value: guider.rmsTotal,
                isTotal: true,
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

  const _RmsStat({
    required this.colors,
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  Color _color() {
    if (value == null) return colors.textMuted;
    if (value! < 1.0) return colors.success;
    if (value! < 2.0) return colors.warning;
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
            fontSize: 10,
            color: colors.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value != null ? '${value!.toStringAsFixed(2)}"' : '—',
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: FontWeight.w700,
            color: _color(),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
