import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import 'sidebar_shared_widgets.dart';

/// Schematic colors offered for FOV framing overlays. High-contrast hues that
/// read cleanly over the dark sky canvas and stay distinct when several rigs
/// are shown at once.
const List<Color> _kPresetColors = [
  Color(0xFF00E676), // green
  Color(0xFF42A5F5), // blue
  Color(0xFFFFB300), // amber
  Color(0xFFFF5252), // red
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // cyan
];

/// Manager for multi-rig FOV framing presets shown on the planetarium sky.
///
/// Lists each preset (with FOV / image-scale readout, visibility toggle and
/// delete), lets the user add one from the bundled telescope + camera catalog,
/// and edits the active preset's position angle and sky anchor (snap to the
/// selected target / un-pin to follow the view). Edits flow through
/// [fovPresetsProvider]; the host screen persists them.
class FovPresetsPanel extends ConsumerWidget {
  final NightshadeColors colors;

  /// The currently selected sky target, used for "snap to target".
  final SelectedObjectState selectedObject;

  const FovPresetsPanel({
    super.key,
    required this.colors,
    required this.selectedObject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fovPresetsProvider);
    final notifier = ref.read(fovPresetsProvider.notifier);

    return InfoCard(
      title: 'FOV Framing',
      icon: NightshadeIcons.frame,
      color: colors.accent,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.presets.isEmpty)
            Text(
              'Add a rig to overlay its sensor field of view on the sky. '
              'Show several at once, drag to reposition and rotate to set the '
              'camera angle.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textSecondary,
              ),
            )
          else
            for (final preset in state.presets)
              _PresetRow(
                preset: preset,
                isActive: preset.id == state.activeId,
                colors: colors,
                onSelect: () => notifier.setActive(preset.id),
                onToggleVisible: () => notifier.toggleVisible(preset.id),
                onDelete: () => notifier.remove(preset.id),
              ),
          if (state.active != null) ...[
            const SizedBox(height: 12),
            _ActivePresetControls(
              preset: state.active!,
              colors: colors,
              selectedObject: selectedObject,
              onRotate: notifier.setActivePositionAngle,
              onSnapToTarget: () {
                final coords = selectedObject.coordinates ??
                    selectedObject.object?.coordinates;
                if (coords != null) notifier.setActiveCenter(coords);
              },
              onUnpin: notifier.clearActiveCenter,
            ),
          ],
          const SizedBox(height: 12),
          NightshadeButton(
            label: 'Add Rig',
            icon: NightshadeIcons.add,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => _showAddRigSheet(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddRigSheet(BuildContext context, WidgetRef ref) async {
    final existing = ref.read(fovPresetsProvider).presets.length;
    final result = await showDialog<FovPreset>(
      context: context,
      builder: (context) => _AddRigDialog(
        colors: colors,
        nextColor: _kPresetColors[existing % _kPresetColors.length],
      ),
    );
    if (result != null) {
      ref.read(fovPresetsProvider.notifier).add(result);
    }
  }
}

class _PresetRow extends StatelessWidget {
  final FovPreset preset;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback onSelect;
  final VoidCallback onToggleVisible;
  final VoidCallback onDelete;

  const _PresetRow({
    required this.preset,
    required this.isActive,
    required this.colors,
    required this.onSelect,
    required this.onToggleVisible,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fov = preset.fovDegrees;
    final scale = preset.imageScaleArcsecPerPx;
    final summary = fov == null
        ? 'invalid optics'
        : '${fov.$1.toStringAsFixed(2)}° × ${fov.$2.toStringAsFixed(2)}°'
            '${scale == null ? '' : '  ·  ${scale.toStringAsFixed(2)}"/px'}';

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? preset.color.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color:
                isActive ? preset.color.withValues(alpha: 0.55) : colors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: preset.color,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: preset.visible ? 'Hide on sky' : 'Show on sky',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(
                preset.visible
                    ? NightshadeIcons.visible
                    : NightshadeIcons.hidden,
                color: preset.visible ? colors.accent : colors.textMuted,
              ),
              onPressed: onToggleVisible,
            ),
            IconButton(
              tooltip: 'Delete preset',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(NightshadeIcons.delete, color: colors.textMuted),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivePresetControls extends StatelessWidget {
  final FovPreset preset;
  final NightshadeColors colors;
  final SelectedObjectState selectedObject;
  final ValueChanged<double> onRotate;
  final VoidCallback onSnapToTarget;
  final VoidCallback onUnpin;

  const _ActivePresetControls({
    required this.preset,
    required this.colors,
    required this.selectedObject,
    required this.onRotate,
    required this.onSnapToTarget,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final hasTarget =
        selectedObject.coordinates != null || selectedObject.object != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Position angle',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${preset.positionAngleDeg.toStringAsFixed(0)}°',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        Slider(
          value: preset.positionAngleDeg.clamp(0, 360),
          max: 360,
          divisions: 360,
          activeColor: preset.color,
          onChanged: onRotate,
        ),
        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                label: preset.center == null ? 'Snap to target' : 'Re-snap',
                icon: NightshadeIcons.target,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: hasTarget ? onSnapToTarget : null,
              ),
            ),
            if (preset.center != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: NightshadeButton(
                  label: 'Follow view',
                  icon: NightshadeIcons.move,
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                  onPressed: onUnpin,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Dialog for composing a new preset from the bundled telescope + camera
/// catalog, with an optional reducer/Barlow multiplier. Shows a live FOV /
/// image-scale preview so the user can confirm the rig before adding it.
class _AddRigDialog extends StatefulWidget {
  final NightshadeColors colors;
  final Color nextColor;

  const _AddRigDialog({required this.colors, required this.nextColor});

  @override
  State<_AddRigDialog> createState() => _AddRigDialogState();
}

class _AddRigDialogState extends State<_AddRigDialog> {
  late TelescopeSpecs _telescope = TelescopeSpecs.commonTelescopes.first;
  late CameraSensorSpecs _camera = CameraSensorSpecs.commonCameras.first;
  double _multiplier = 1.0;

  static const List<(String, double)> _multipliers = [
    ('0.7× reducer', 0.7),
    ('0.8× reducer', 0.8),
    ('Native (1.0×)', 1.0),
    ('1.5× Barlow', 1.5),
    ('2.0× Barlow', 2.0),
  ];

  FovPreset _buildPreset() {
    return FovPreset.fromEquipment(
      id: 'fov-${DateTime.now().microsecondsSinceEpoch}',
      camera: _camera,
      telescope: _telescope,
      focalMultiplier: _multiplier,
      color: widget.nextColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final preview = _buildPreset();
    final fov = preview.fovDegrees;
    final scale = preview.imageScaleArcsecPerPx;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text('Add FOV Rig', style: TextStyle(color: colors.textPrimary)),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 360,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Telescope', colors),
              DropdownButton<TelescopeSpecs>(
                isExpanded: true,
                value: _telescope,
                dropdownColor: colors.surfaceAlt,
                items: [
                  for (final t in TelescopeSpecs.commonTelescopes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        '${t.name} · ${t.focalLengthMm.toStringAsFixed(0)}mm '
                        'f/${t.focalRatio.toStringAsFixed(1)}',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _telescope = v ?? _telescope),
              ),
              const SizedBox(height: 8),
              _label('Camera', colors),
              DropdownButton<CameraSensorSpecs>(
                isExpanded: true,
                value: _camera,
                dropdownColor: colors.surfaceAlt,
                items: [
                  for (final c in CameraSensorSpecs.commonCameras)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.name} · ${c.widthMm.toStringAsFixed(1)}×'
                        '${c.heightMm.toStringAsFixed(1)}mm',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _camera = v ?? _camera),
              ),
              const SizedBox(height: 8),
              _label('Reducer / Barlow', colors),
              DropdownButton<double>(
                isExpanded: true,
                value: _multiplier,
                dropdownColor: colors.surfaceAlt,
                items: [
                  for (final (label, value) in _multipliers)
                    DropdownMenuItem(
                      value: value,
                      child: Text(label,
                          style: TextStyle(color: colors.textPrimary)),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _multiplier = v ?? _multiplier),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.nextColor.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  border: Border.all(
                      color: widget.nextColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(NightshadeIcons.frame,
                        size: 16, color: widget.nextColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fov == null
                            ? 'Invalid optics'
                            : '${fov.$1.toStringAsFixed(2)}° × '
                                '${fov.$2.toStringAsFixed(2)}°'
                                '${scale == null ? '' : '   ${scale.toStringAsFixed(2)}"/px'}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        NightshadeButton(
          label: 'Add',
          size: ButtonSize.small,
          onPressed: fov == null
              ? null
              : () => Navigator.of(context).pop(_buildPreset()),
        ),
      ],
    );
  }

  Widget _label(String text, NightshadeColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textSecondary,
          ),
        ),
      );
}
