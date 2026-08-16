// Preview FOV slider, presets and equipment FOV overlay controls.
part of '../framing_controls.dart';

/// Preview FOV slider with current value, optional equipment-FOV badge, and
/// quick preset buttons (0.5°, 1°, 2°, 5°, equipment).
class FramingPreviewFovSlider extends StatelessWidget {
  final NightshadeColors colors;
  final double value;
  final bool hasEquipment;
  final double? equipmentFov;
  final ValueChanged<double> onChanged;

  const FramingPreviewFovSlider({
    super.key,
    required this.colors,
    required this.value,
    required this.hasEquipment,
    this.equipmentFov,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.standard,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${value.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize16,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (hasEquipment && equipmentFov != null)
                // Flexible so the equipment badge clips/ellipsizes rather than
                // overflowing the row when this slider is hosted in a narrow
                // column (the guided framing rail inside the 250-500px sidebar).
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: NightshadeDecorations.emphasisSurface(
                      colors.info,
                      borderRadius: NightshadeTokens.borderRadiusInline4,
                    ),
                    child: Text(
                      'Equipment: ${equipmentFov!.toStringAsFixed(2)}°',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize9,
                        color: colors.info,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: 0.1,
              max: 20.0,
              divisions: 199,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.1°',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize9,
                      color: colors.textMuted)),
              Text('20°',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize9,
                      color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          // Quick presets. A Wrap (not a Row) so the preset chips reflow to a
          // second line instead of overflowing when this slider is hosted in a
          // narrow column (e.g. the guided framing rail inside the 250-500px
          // framing sidebar), where the optional "Equip" chip would otherwise
          // push the Row past its width.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FovPresetButton(
                  label: '0.5°',
                  value: 0.5,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(0.5)),
              _FovPresetButton(
                  label: '1°',
                  value: 1.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(1.0)),
              _FovPresetButton(
                  label: '2°',
                  value: 2.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(2.0)),
              _FovPresetButton(
                  label: '5°',
                  value: 5.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(5.0)),
              if (hasEquipment && equipmentFov != null)
                _FovPresetButton(
                  label: 'Equip',
                  value: equipmentFov!,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(equipmentFov!),
                  isEquipment: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FovPresetButton extends StatelessWidget {
  final String label;
  final double value;
  final double currentValue;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final bool isEquipment;

  const _FovPresetButton({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.colors,
    required this.onTap,
    this.isEquipment = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = (currentValue - value).abs() < 0.05;
    final color = isEquipment ? colors.info : colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: NightshadeTokens.borderRadiusInline4,
          border: Border.all(
            color: isSelected ? color : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? color : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Toggles the equipment-FOV overlay on/off and exposes its opacity slider.
/// Only shown when preview FOV is larger than the equipment FOV.
class FramingEquipmentFovOverlayControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool showOverlay;
  final double opacity;
  final VoidCallback onToggle;
  final ValueChanged<double> onOpacityChanged;

  const FramingEquipmentFovOverlayControls({
    super.key,
    required this.colors,
    required this.showOverlay,
    required this.opacity,
    required this.onToggle,
    required this.onOpacityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.05),
        borderRadius: NightshadeTokens.borderRadiusInline8,
        border: Border.all(color: colors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.frame, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Equipment FOV Overlay',
                  style: NightshadeTypography.labelStrongSm
                      .copyWith(color: colors.info),
                ),
              ),
              NightshadeSwitch(
                value: showOverlay,
                onChanged: (_) => onToggle(),
              ),
            ],
          ),
          if (showOverlay) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Opacity',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: colors.textSecondary),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: colors.info,
                      inactiveTrackColor: colors.border,
                      thumbColor: colors.info,
                      overlayColor: colors.info.withValues(alpha: 0.1),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: opacity,
                      min: 0.1,
                      max: 0.8,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 35,
                  child: Text(
                    '${(opacity * 100).round()}%',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize10,
                        color: colors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Shows your actual equipment field of view as an overlay',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize9,
                  color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
