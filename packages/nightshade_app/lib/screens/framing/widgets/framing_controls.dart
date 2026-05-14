import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;

import 'package:nightshade_app/utils/snackbar_helper.dart';

/// Generic label/slider/value row used for rotation, overlap, and similar
/// scalar controls in the right-hand control panel.
class FramingSliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<double> onChanged;

  const FramingSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${value.toInt()}${suffix ?? ''}',
            style: TextStyle(
              fontSize: 11,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Small toggle pill (rectangle chip with active/inactive states), used for
/// quick on/off toggles in the framing controls (Grid, Labels, Directions).
class FramingToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const FramingToggleChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.2)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? colors.primary : colors.textSecondary,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Action button (icon + label) used in the Actions panel; supports a primary
/// gradient variant with hover shadow, and a disabled state.
class FramingActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isEnabled;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const FramingActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.isEnabled = true,
    required this.colors,
    this.onTap,
  });

  @override
  State<FramingActionButton> createState() => _FramingActionButtonState();
}

class _FramingActionButtonState extends State<FramingActionButton> {
  bool _isHovered = false;

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isEnabled && widget.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isPrimary && enabled
                ? LinearGradient(
                    colors: [
                      widget.colors.primary,
                      _darkenColor(widget.colors.primary, 0.08),
                    ],
                  )
                : null,
            color: widget.isPrimary
                ? null
                : enabled
                    ? (_isHovered
                        ? widget.colors.surfaceAlt
                        : widget.colors.background)
                    : widget.colors.surfaceAlt.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: enabled
                        ? widget.colors.border
                        : widget.colors.border.withValues(alpha: 0.5),
                  ),
            boxShadow: widget.isPrimary && _isHovered && enabled
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isPrimary
                    ? (enabled ? Colors.white : Colors.white60)
                    : (enabled
                        ? widget.colors.textSecondary
                        : widget.colors.textMuted),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? (enabled ? Colors.white : Colors.white60)
                      : (enabled
                          ? widget.colors.textSecondary
                          : widget.colors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact icon button with tooltip and hover state, used next to the manual
/// RA/Dec entry fields.
class FramingSmallIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const FramingSmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
  });

  @override
  State<FramingSmallIconButton> createState() => _FramingSmallIconButtonState();
}

class _FramingSmallIconButtonState extends State<FramingSmallIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  _isHovered ? widget.colors.primary : widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.colors.border),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? Colors.white : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${value.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (hasEquipment && equipmentFov != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: colors.info.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Equipment: ${equipmentFov!.toStringAsFixed(2)}°',
                    style: TextStyle(
                      fontSize: 9,
                      color: colors.info,
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
              max: 10.0,
              divisions: 99,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.1°',
                  style: TextStyle(fontSize: 9, color: colors.textMuted)),
              Text('10°',
                  style: TextStyle(fontSize: 9, color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          // Quick presets
          Row(
            children: [
              _FovPresetButton(
                  label: '0.5°',
                  value: 0.5,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(0.5)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '1°',
                  value: 1.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(1.0)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '2°',
                  value: 2.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(2.0)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '5°',
                  value: 5.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(5.0)),
              if (hasEquipment && equipmentFov != null) ...[
                const SizedBox(width: 6),
                _FovPresetButton(
                  label: 'Equip',
                  value: equipmentFov!,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(equipmentFov!),
                  isEquipment: true,
                ),
              ],
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
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.frame, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Equipment FOV Overlay',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.info,
                  ),
                ),
              ),
              Switch(
                value: showOverlay,
                onChanged: (_) => onToggle(),
                activeThumbColor: colors.info,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          if (showOverlay) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Opacity',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
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
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Shows your actual equipment field of view as an overlay',
              style: TextStyle(fontSize: 9, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Integer spinner (label + -/+ buttons) used for mosaic columns / rows.
class FramingMosaicSpinner extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final NightshadeColors colors;

  const FramingMosaicSpinner({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _SpinnerButton(
                icon: LucideIcons.minus,
                onTap: value > min ? () => onChanged(value - 1) : null,
                colors: colors,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _SpinnerButton(
                icon: LucideIcons.plus,
                onTap: value < max ? () => onChanged(value + 1) : null,
                colors: colors,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpinnerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final NightshadeColors colors;

  const _SpinnerButton({
    required this.icon,
    this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null ? colors.textPrimary : colors.textMuted,
        ),
      ),
    );
  }
}

/// Selectable pill button (icon + label) used for mosaic capture pattern
/// options (Serpentine, Numbers).
class FramingOptionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const FramingOptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<FramingOptionButton> createState() => _FramingOptionButtonState();
}

class _FramingOptionButtonState extends State<FramingOptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.15)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : widget.colors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: widget.isSelected
                      ? widget.colors.primary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-cell start-corner selector for the mosaic capture pattern.
class FramingStartCornerSelector extends StatelessWidget {
  final MosaicStartCorner selected;
  final ValueChanged<MosaicStartCorner> onChanged;
  final NightshadeColors colors;

  const FramingStartCornerSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _CornerOption(
            corner: MosaicStartCorner.topLeft,
            label: 'TL',
            icon: LucideIcons.arrowUpLeft,
            isSelected: selected == MosaicStartCorner.topLeft,
            onTap: () => onChanged(MosaicStartCorner.topLeft),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.topRight,
            label: 'TR',
            icon: LucideIcons.arrowUpRight,
            isSelected: selected == MosaicStartCorner.topRight,
            onTap: () => onChanged(MosaicStartCorner.topRight),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.bottomLeft,
            label: 'BL',
            icon: LucideIcons.arrowDownLeft,
            isSelected: selected == MosaicStartCorner.bottomLeft,
            onTap: () => onChanged(MosaicStartCorner.bottomLeft),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.bottomRight,
            label: 'BR',
            icon: LucideIcons.arrowDownRight,
            isSelected: selected == MosaicStartCorner.bottomRight,
            onTap: () => onChanged(MosaicStartCorner.bottomRight),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _CornerOption extends StatelessWidget {
  final MosaicStartCorner corner;
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _CornerOption({
    required this.corner,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? colors.primary : colors.textMuted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient button that writes each computed mosaic panel into the targets
/// database as an individual target named "<targetName> - Panel <n>".
class FramingExportMosaicButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final List<FramingMosaicPanel> panels;
  final String targetName;

  const FramingExportMosaicButton({
    super.key,
    required this.colors,
    required this.panels,
    required this.targetName,
  });

  @override
  ConsumerState<FramingExportMosaicButton> createState() =>
      _FramingExportMosaicButtonState();
}

class _FramingExportMosaicButtonState
    extends ConsumerState<FramingExportMosaicButton> {
  bool _isHovered = false;
  bool _isExporting = false;

  Future<void> _exportToTargets() async {
    if (_isExporting || widget.panels.isEmpty) return;

    setState(() => _isExporting = true);

    try {
      final targetsDao = ref.read(targetsDaoProvider);

      // Save each panel as a target
      for (final panel in widget.panels) {
        await targetsDao.createTarget(TargetsCompanion.insert(
          name: '${widget.targetName} - Panel ${panel.index + 1}',
          ra: panel.centerRaHours,
          dec: panel.centerDecDegrees,
          objectType: const Value('mosaic'),
        ));
      }

      if (!mounted) return;
      context.showSuccessSnackBar(
          'Exported ${widget.panels.length} panels to targets');
    } catch (e) {
      context.showErrorSnackBar('Error exporting: $e');
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _exportToTargets,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.colors.primary,
                widget.colors.primary.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isExporting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  LucideIcons.download,
                  size: 14,
                  color: Colors.white,
                ),
              const SizedBox(width: 8),
              Text(
                _isExporting
                    ? 'Exporting...'
                    : 'Export ${widget.panels.length} Panels to Targets',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A styled tab button for the framing screen tabs.
class FramingTabButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const FramingTabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  State<FramingTabButton> createState() => _FramingTabButtonState();
}

class _FramingTabButtonState extends State<FramingTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.isSelected
                    ? widget.colors.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            color: _isHovered && !widget.isSelected
                ? widget.colors.surfaceHover
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isSelected
                      ? widget.colors.primary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
