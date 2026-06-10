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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final isVeryCompact = constraints.maxWidth < 720;
        final horizontalPadding =
            isVeryCompact ? 12.0 : (isCompact ? 16.0 : 20.0);
        final itemSpacing = isVeryCompact ? 8.0 : (isCompact ? 12.0 : 20.0);

        final items = <Widget>[
          InfoItem(
            label: 'Center RA',
            value: CoordinateFormatUtils.formatRAShort(viewState.centerRA),
            colors: colors,
            compact: isCompact,
          ),
          SizedBox(width: itemSpacing),
          InfoItem(
            label: 'Center Dec',
            value: isCompact
                ? CoordinateFormatUtils.formatDecCompact(viewState.centerDec)
                : CoordinateFormatUtils.formatDec(viewState.centerDec),
            colors: colors,
            compact: isCompact,
          ),
          SizedBox(width: itemSpacing),
          InfoItem(
            label: 'FOV',
            value: CoordinateFormatUtils.formatFOV(viewState.fieldOfView),
            colors: colors,
            compact: isCompact,
          ),
          if (!isVeryCompact) ...[
            SizedBox(width: itemSpacing),
            InfoItem(
              label: 'Bortle',
              value: '$bortle (lim ${limMag.toStringAsFixed(1)}m)',
              colors: colors,
              compact: isCompact,
              valueColor: bortle <= 3
                  ? colors.success
                  : bortle <= 5
                      ? colors.warning
                      : colors.error,
            ),
          ],
          if (!isCompact && selectedObject.currentAltAz != null) ...[
            SizedBox(width: itemSpacing * 2),
            InfoItem(
              label: 'Selected Alt',
              value: CoordinateFormatUtils.formatAltitude(
                  selectedObject.currentAltAz!.$1),
              colors: colors,
              compact: isCompact,
              valueColor: selectedObject.currentAltAz!.$1 > 0
                  ? colors.success
                  : colors.error,
            ),
            SizedBox(width: itemSpacing),
            InfoItem(
              label: 'Az',
              value: CoordinateFormatUtils.formatAzimuth(
                  selectedObject.currentAltAz!.$2),
              colors: colors,
              compact: isCompact,
            ),
          ],
        ];

        return Container(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isCompact ? 8 : 12,
            horizontalPadding,
            (isCompact ? 8 : 12) + MediaQuery.viewPaddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                // absolute: bottom scrim over the planetarium sky canvas
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
          child: isVeryCompact
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: items),
                )
              : Row(children: items),
        );
      },
    );
  }
}

class InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;
  final bool compact;

  const InfoItem({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${compact ? label.split(' ').first : label}:',
          style: TextStyle(
            fontSize: compact
                ? NightshadeTypography.fontSize10
                : NightshadeTypography.fontSize11,
            // absolute: HUD label over the planetarium sky canvas
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: compact
                ? NightshadeTypography.fontSize11
                : NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w500,
            // absolute: HUD value over the planetarium sky canvas
            color: valueColor ?? Colors.white70,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
