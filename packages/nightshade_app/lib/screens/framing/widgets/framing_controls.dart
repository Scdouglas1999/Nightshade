import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

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
              fontSize: NightshadeTypography.fontSize11,
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
              fontSize: NightshadeTypography.fontSize11,
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
          borderRadius: NightshadeTokens.borderRadiusMd,
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: isActive ? colors.primary : colors.textSecondary,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
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
              borderRadius: NightshadeTokens.borderRadiusMd,
              border: Border.all(color: widget.colors.border),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered
                  ? widget.colors.textPrimary
                  : widget.colors.textSecondary,
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
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize9,
                      color: colors.textMuted)),
              Text('10°',
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
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _SpinnerButton(
                icon: NightshadeIcons.remove,
                onTap: value > min ? () => onChanged(value - 1) : null,
                colors: colors,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              _SpinnerButton(
                icon: NightshadeIcons.add,
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
      borderRadius: NightshadeTokens.borderRadiusInline4,
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
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(
              color: widget.isSelected
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              // Flexible + ellipsis so the label never overflows a narrow
              // Expanded cell (e.g. the mosaic Serpentine/Numbers pair in a
              // ~270px phone-landscape controls panel).
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isSelected
                        ? widget.colors.primary
                        : widget.colors.textSecondary,
                  ),
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
        borderRadius: NightshadeTokens.borderRadiusMd,
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
            borderRadius: NightshadeTokens.borderRadiusInline4,
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
                  fontSize: NightshadeTypography.fontSize8,
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

/// Gradient button that persists the framed mosaic as a DURABLE mosaic
/// project (the same `mosaic_projects` + per-panel `mosaic_panels`/`targets`
/// structure the mosaic wizard's "Create Project" writes) and routes the user
/// to the project screen (`/mosaic/:id`) so the scheduler/sequencer can consume
/// it.
///
/// This replaces the old export-to-targets behaviour, which wrote orphaned
/// `targets` rows (`objectType: 'mosaic'`) that no project or sequence could
/// drive — a dead end. The grid geometry is taken from the live framing state
/// via [FramingNotifier.createDurableMosaicProject], so the persisted project
/// matches the panels shown on the canvas.
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

  Future<void> _createProject() async {
    if (_isExporting || widget.panels.isEmpty) return;

    setState(() => _isExporting = true);

    try {
      // Persist the framed grid as a durable mosaic project (project row +
      // per-panel target/panel rows) rather than orphaned target rows, then
      // route to the project screen so the scheduler/sequencer can drive it.
      final projectId = await ref
          .read(framingProvider.notifier)
          .createDurableMosaicProject(name: widget.targetName);

      if (!mounted) return;
      if (projectId == null) {
        context.showErrorSnackBar(
          'Could not create mosaic project: no framed target or rig field of '
          'view available.',
        );
        return;
      }

      context.showSuccessSnackBar(
          'Created mosaic project with ${widget.panels.length} panels');
      unawaited(context.push('/mosaic/$projectId'));
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not create mosaic project: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _createProject,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.primary.withValues(alpha: 0.92)
                : widget.colors.primary,
            borderRadius: NightshadeTokens.borderRadiusInline8,
            border: Border.all(
              color: widget.colors.primary.withValues(alpha: 0.85),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isExporting)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onPrimary,
                  ),
                )
              else
                Icon(
                  NightshadeIcons.download,
                  size: 14,
                  color: onPrimary,
                ),
              const SizedBox(width: 8),
              Text(
                _isExporting
                    ? 'Creating project...'
                    : 'Create Mosaic Project (${widget.panels.length} panels)',
                style: NightshadeTypography.labelStrongSm
                    .copyWith(color: onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
