part of '../flat_wizard_screen.dart';

class _HistogramTargetSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _HistogramTargetSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        Row(
          children: [
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize24,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '~${FlatExposureCalculator.histogramPercentToAdu(value)} ADU',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
          ),
          child: Slider(
            value: value,
            min: 10,
            max: 90,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToleranceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ToleranceSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Text(
          '±${value.toStringAsFixed(0)}%',
          style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.surfaceAlt,
              thumbColor: colors.primary,
            ),
            child: Slider(
              value: value,
              min: 1,
              max: 25,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _FrameCountInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _FrameCountInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Keep ≥48px touch targets but let the label flex so the stepper fits a
    // narrow phone controls column without overflowing.
    return Row(
      children: [
        Flexible(
          child: Text(
            'Frames:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(LucideIcons.minus, size: 18),
          color: colors.textSecondary,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        Container(
          width: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          ),
          child: Text(
            '$value',
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(LucideIcons.plus, size: 18),
          color: colors.textSecondary,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }
}

class _TwilightModeSelector extends StatelessWidget {
  final TwilightMode mode;
  final ValueChanged<TwilightMode> onChanged;

  const _TwilightModeSelector({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunrise,
            label: 'Dawn',
            description: 'Brightening sky',
            isSelected: mode == TwilightMode.dawn,
            onTap: () => onChanged(TwilightMode.dawn),
            colors: colors,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunset,
            label: 'Dusk',
            description: 'Darkening sky',
            isSelected: mode == TwilightMode.dusk,
            onTap: () => onChanged(TwilightMode.dusk),
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _TwilightOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _TwilightOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: NightshadeTypography.h5.copyWith(color: isSelected ? colors.primary : colors.textPrimary),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
