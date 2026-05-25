// Wave 5 Agent 1 — inline framing assistant for the sequencer.
//
// Wraps the planetarium's `FramingView` widget in a sequencer-friendly
// modal. The user picks a target from the properties panel, taps
// "Frame target", and gets a full-screen framing view with the
// target's sky context. Rotating the FOV on the assistant writes
// directly back to the selected TargetHeaderNode.rotation.
//
// The dialog also pre-syncs the equipmentFOVProvider with the active
// equipment profile / connected camera so the rendered FOV matches the
// rig the user is about to use.
//
// The "Use current rotator" button reads `rotatorStateProvider` and
// applies the live mechanical angle — useful when the rotator is
// already on-target and the user just wants to lock the sequence to
// what's installed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Public entry point: open the framing assistant for a TargetHeader.
/// Returns the resulting rotation if the user applied a change, or
/// `null` if cancelled.
Future<double?> showFramingAssistantDialog({
  required BuildContext context,
  required WidgetRef ref,
  required TargetHeaderNode target,
}) async {
  // Pre-seed the planetarium's equipmentFOVProvider from the active
  // profile + connected camera so the FOV box reflects the user's
  // rig. We do this *before* the dialog opens so the first paint
  // shows the right size.
  _syncEquipmentFOVFromProfile(ref);

  final initialRotation = target.rotation ?? 0;
  ref
      .read(equipmentFOVProvider.notifier)
      .setRotation(initialRotation.toDouble());

  return showDialog<double?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FramingAssistantDialog(target: target),
  );
}

/// Sync the planetarium-side equipmentFOVProvider from the user's
/// active equipment profile + connected camera. Used by the framing
/// assistant so the FOV box on the framing view matches what's
/// actually installed on the scope.
///
/// Reads `opticalConfigProvider` (which already does the heavy
/// lifting: profile + connected camera capabilities → unified
/// telescope + sensor view), then forwards into the planetarium's
/// `equipmentFOVProvider`. If sensor dimensions are not available
/// (no connected camera), we approximate using a typical 4096×2731
/// sensor so the FOV outline still renders.
void _syncEquipmentFOVFromProfile(WidgetRef ref) {
  final config = ref.read(opticalConfigProvider);
  if (config == null) return;

  final fl = config.focalLength;
  if (fl == null || fl <= 0) return;

  ref.read(equipmentFOVProvider.notifier).setTelescope(TelescopeSpecs(
        name: config.telescopeName ?? 'Telescope',
        focalLengthMm: fl,
        apertureMm: config.aperture ?? 0,
      ));

  final pixelSize = config.pixelSize;
  if (pixelSize == null || pixelSize <= 0) return;

  final pixelsX = config.sensorWidth ?? 4096;
  final pixelsY = config.sensorHeight ?? 2731;
  final widthMm = pixelsX * pixelSize / 1000.0;
  final heightMm = pixelsY * pixelSize / 1000.0;
  ref.read(equipmentFOVProvider.notifier).setCamera(
        CameraSensorSpecs(
          name: config.cameraName ?? 'Profile camera',
          widthMm: widthMm,
          heightMm: heightMm,
          pixelsX: pixelsX,
          pixelsY: pixelsY,
          pixelSizeMicrons: pixelSize,
        ),
      );
}

class FramingAssistantDialog extends ConsumerStatefulWidget {
  final TargetHeaderNode target;

  const FramingAssistantDialog({super.key, required this.target});

  @override
  ConsumerState<FramingAssistantDialog> createState() =>
      _FramingAssistantDialogState();
}

class _FramingAssistantDialogState
    extends ConsumerState<FramingAssistantDialog> {
  late double _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = widget.target.rotation ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final equipmentFOV = ref.watch(equipmentFOVProvider);
    final fovTuple = equipmentFOV.fov;

    return NightshadeDialog(
      title: 'Frame target — ${widget.target.targetName}',
      icon: LucideIcons.scanLine,
      width: 900,
      height: 720,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(null),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(_rotation),
          icon: Icons.check,
          label: 'Apply rotation',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
      child: Row(
        children: [
          SizedBox(
            width: AdaptiveDialogConstraints.clampPanelWidth(
              context,
              designWidth: 260,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ContextCard(
                    colors: colors,
                    target: widget.target,
                    fov: fovTuple,
                  ),
                  const SizedBox(height: 12),
                  _RotationControls(
                    colors: colors,
                    rotation: _rotation,
                    onChanged: (v) {
                      setState(() => _rotation = v);
                      ref.read(equipmentFOVProvider.notifier).setRotation(v);
                    },
                    onUseLiveRotator: () {
                      final rotatorState = ref.read(rotatorStateProvider);
                      final live = rotatorState.position;
                      if (live == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'No rotator connected; cannot read live angle.')),
                        );
                        return;
                      }
                      setState(() => _rotation = live);
                      ref.read(equipmentFOVProvider.notifier).setRotation(live);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(NightshadeTokens.radiusLg),
                bottomRight: Radius.circular(NightshadeTokens.radiusLg),
              ),
              child: FramingView(
                target: CelestialCoordinate(
                  ra: widget.target.raHours,
                  dec: widget.target.decDegrees,
                ),
                onRotationChanged: (value) {
                  // The framing view drives the planetarium FOV
                  // rotation directly when the user drags the
                  // rotation handle; mirror it into our local state
                  // so the slider stays in sync.
                  setState(() => _rotation = value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final (double, double)? fov;

  const _ContextCard({
    required this.colors,
    required this.target,
    required this.fov,
  });

  @override
  Widget build(BuildContext context) {
    final fovLabel = fov == null
        ? 'No camera FOV — pick equipment profile'
        : '${fov!.$1.toStringAsFixed(2)}° × ${fov!.$2.toStringAsFixed(2)}°';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 12, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  target.targetName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'RA ${target.raHours.toStringAsFixed(4)}h  '
            'Dec ${target.decDegrees.toStringAsFixed(3)}°',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
          const Divider(height: 14),
          Row(
            children: [
              Icon(LucideIcons.camera, size: 12, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fovLabel,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RotationControls extends StatelessWidget {
  final NightshadeColors colors;
  final double rotation;
  final ValueChanged<double> onChanged;
  final VoidCallback onUseLiveRotator;

  const _RotationControls({
    required this.colors,
    required this.rotation,
    required this.onChanged,
    required this.onUseLiveRotator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.rotateCw, size: 13, color: colors.textMuted),
              const SizedBox(width: 6),
              Text('Rotation',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  )),
              const Spacer(),
              Text(
                '${rotation.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Slider(
            value: rotation.clamp(-180, 180),
            min: -180,
            max: 180,
            divisions: 360,
            onChanged: onChanged,
            activeColor: colors.primary,
          ),
          const SizedBox(height: 4),
          NightshadeButton(
            onPressed: onUseLiveRotator,
            icon: LucideIcons.activity,
            label: 'Use live rotator',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
          ),
          const SizedBox(height: 6),
          Text(
            'Drag the FOV outline on the sky view to adjust rotation '
            'visually. Drag inside the box to nudge the target centre.',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
