part of '../suggestion_filters.dart';

// ============================================================================
// Slider Controls
// ============================================================================

/// Slider control with label and value display.
class _SliderControl extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) valueFormatter;
  final NightshadeColors colors;
  final ValueChanged<double> onChanged;
  final bool showLabel;

  const _SliderControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueFormatter,
    required this.colors,
    required this.onChanged,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: showLabel ? 13 : 11,
                fontWeight: showLabel ? FontWeight.w500 : FontWeight.normal,
                color: showLabel ? colors.textSecondary : colors.textMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Text(
                valueFormatter(value),
                style: NightshadeTypography.labelStrongSm.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
            overlayColor: colors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Range slider control with label and two value badges showing min–max.
class _RangeSliderControl extends StatelessWidget {
  final String label;
  final double currentMin;
  final double currentMax;
  final double rangeMin;
  final double rangeMax;
  final int divisions;
  final String Function(double) minValueFormatter;
  final String Function(double) maxValueFormatter;
  final NightshadeColors colors;
  final void Function(double min, double max) onChanged;
  final String? minLabel;
  final String? maxLabel;
  final bool showLabel;

  const _RangeSliderControl({
    required this.label,
    required this.currentMin,
    required this.currentMax,
    required this.rangeMin,
    required this.rangeMax,
    required this.divisions,
    required this.minValueFormatter,
    required this.maxValueFormatter,
    required this.colors,
    required this.onChanged,
    this.minLabel,
    this.maxLabel,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    // Clamp values to the valid range
    final clampedMin = currentMin.clamp(rangeMin, rangeMax);
    final clampedMax = currentMax.clamp(rangeMin, rangeMax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: showLabel ? 13 : 11,
                fontWeight: showLabel ? FontWeight.w500 : FontWeight.normal,
                color: showLabel ? colors.textSecondary : colors.textMuted,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _valueBadge(minValueFormatter(clampedMin)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '–',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
                  ),
                ),
                _valueBadge(maxValueFormatter(clampedMax)),
              ],
            ),
          ],
        ),
        // Optional min/max semantic labels
        if (minLabel != null || maxLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (minLabel != null)
                Text(
                  minLabel!,
                  style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
                ),
              if (maxLabel != null)
                Text(
                  maxLabel!,
                  style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
            overlayColor: colors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: RangeSlider(
            values: RangeValues(clampedMin, clampedMax),
            min: rangeMin,
            max: rangeMax,
            divisions: divisions,
            onChanged: (values) => onChanged(values.start, values.end),
          ),
        ),
      ],
    );
  }

  Widget _valueBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      ),
      child: Text(
        text,
        style: NightshadeTypography.labelStrongSm.copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
