import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/coordinate_format_utils.dart';


class BottomInfoBar extends ConsumerWidget {
  final NightshadeColors colors;

  const BottomInfoBar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(skyViewStateProvider);
    final selectedObject = ref.watch(selectedObjectProvider);
    final bortle = ref.watch(bortleClassProvider);
    final limMag = BortleScale.limitingMagnitude(bortle);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          InfoItem(
            label: 'Center RA',
            value: CoordinateFormatUtils.formatRAShort(viewState.centerRA),
            colors: colors,
          ),
          const SizedBox(width: 20),
          InfoItem(
            label: 'Center Dec',
            value: CoordinateFormatUtils.formatDec(viewState.centerDec),
            colors: colors,
          ),
          const SizedBox(width: 20),
          InfoItem(
            label: 'FOV',
            value: CoordinateFormatUtils.formatFOV(viewState.fieldOfView),
            colors: colors,
          ),
          const SizedBox(width: 20),
          InfoItem(
            label: 'Bortle',
            value: '$bortle (lim ${limMag.toStringAsFixed(1)}m)',
            colors: colors,
            valueColor: bortle <= 3
                ? colors.success
                : bortle <= 5
                    ? Colors.amber
                    : colors.error,
          ),
          if (selectedObject.currentAltAz != null) ...[
            const SizedBox(width: 40),
            InfoItem(
              label: 'Selected Alt',
              value: CoordinateFormatUtils.formatAltitude(
                  selectedObject.currentAltAz!.$1),
              colors: colors,
              valueColor: selectedObject.currentAltAz!.$1 > 0
                  ? colors.success
                  : colors.error,
            ),
            const SizedBox(width: 20),
            InfoItem(
              label: 'Az',
              value: CoordinateFormatUtils.formatAzimuth(
                  selectedObject.currentAltAz!.$2),
              colors: colors,
            ),
          ],
        ],
      ),
    );
  }
}

class InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;

  const InfoItem({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label:',
          style: TextStyle(
              fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor ?? Colors.white70,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
