import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../services/mount_command_service.dart';
import '../screens/imaging/centering_dialog.dart';
import '../utils/snackbar_helper.dart';

/// The slew mode selection for the dropdown.
enum SlewMode {
  /// Basic slew to coordinates.
  slew,

  /// Slew followed by iterative plate-solve centering.
  slewAndCenter,

  /// Slew, center, then rotate to target angle.
  slewCenterRotate,
}

/// A dropdown button for slew operations with three options:
/// - Slew (basic slew to coordinates)
/// - Slew & Center (slew + plate solve centering loop)
/// - Slew, Center & Rotate (slew + center + rotate to target angle)
///
/// The "Slew, Center & Rotate" option is only shown if a rotator is connected
/// AND a [targetRotation] is provided.
class SlewDropdownButton extends ConsumerWidget {
  /// Right Ascension in hours.
  final double ra;

  /// Declination in degrees.
  final double dec;

  /// Optional target name for display in centering dialog.
  final String? targetName;

  /// Target rotation angle in degrees.
  /// If null, the "Slew, Center & Rotate" option is hidden.
  final double? targetRotation;

  /// Whether the button is enabled.
  final bool isEnabled;

  /// Button variant for styling.
  final ButtonVariant variant;

  /// Optional icon to display.
  final IconData? icon;

  /// Optional custom label. Defaults to "Slew".
  final String? label;

  const SlewDropdownButton({
    super.key,
    required this.ra,
    required this.dec,
    this.targetName,
    this.targetRotation,
    this.isEnabled = true,
    this.variant = ButtonVariant.primary,
    this.icon,
    this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final rotatorState = ref.watch(rotatorStateProvider);
    final hasRotator =
        rotatorState.connectionState == DeviceConnectionState.connected;
    final mountState = ref.watch(mountStateProvider);
    final isMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;

    // Determine if slew+center+rotate option should be shown
    final showRotateOption = hasRotator && targetRotation != null;

    return PopupMenuButton<SlewMode>(
      enabled: isEnabled && isMountConnected,
      onSelected: (mode) =>
          _handleSlewMode(context, ref, mode, showRotateOption),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: colors.surface,
      itemBuilder: (context) => [
        PopupMenuItem<SlewMode>(
          value: SlewMode.slew,
          child: Row(
            children: [
              Icon(LucideIcons.move, size: 16, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Slew', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem<SlewMode>(
          value: SlewMode.slewAndCenter,
          child: Row(
            children: [
              Icon(LucideIcons.target, size: 16, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Slew & Center',
                  style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        if (showRotateOption)
          PopupMenuItem<SlewMode>(
            value: SlewMode.slewCenterRotate,
            child: Row(
              children: [
                Icon(LucideIcons.rotateCw, size: 16, color: colors.textPrimary),
                const SizedBox(width: 8),
                Text('Slew, Center & Rotate',
                    style: TextStyle(color: colors.textPrimary)),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: NightshadeButton(
              label: label ?? 'Slew',
              icon: icon ?? LucideIcons.move,
              variant: variant,
              // onPressed is null since PopupMenuButton handles tap
              onPressed: null,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: (isEnabled && isMountConnected)
                ? colors.textPrimary
                : colors.textMuted,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSlewMode(
    BuildContext context,
    WidgetRef ref,
    SlewMode mode,
    bool showRotateOption,
  ) async {
    switch (mode) {
      case SlewMode.slew:
        await _handleSlew(context, ref);
        break;
      case SlewMode.slewAndCenter:
        await _handleSlewAndCenter(context, ref);
        break;
      case SlewMode.slewCenterRotate:
        await _handleSlewCenterRotate(context, ref);
        break;
    }
  }

  Future<void> _handleSlew(BuildContext context, WidgetRef ref) async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.slewTo(ra, dec);
    if (!context.mounted) return;
    context.showCommandActionResult(result);
  }

  Future<void> _handleSlewAndCenter(BuildContext context, WidgetRef ref) async {
    // First slew to approximate position
    final mountService = ref.read(mountCommandServiceProvider);
    final slewResult = await mountService.slewTo(ra, dec, showFeedback: false);

    if (!slewResult.isSuccess) {
      if (context.mounted) {
        context.showCommandActionResult(slewResult);
      }
      return;
    }

    // Wait for slew to complete, then show centering dialog
    // The centering dialog handles the plate solve loop
    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => CenteringDialog(
          targetRa: ra,
          targetDec: dec,
          targetName: targetName ?? 'Target',
        ),
      );
    }
  }

  Future<void> _handleSlewCenterRotate(
      BuildContext context, WidgetRef ref) async {
    // First do slew and center
    final mountService = ref.read(mountCommandServiceProvider);
    final slewResult = await mountService.slewTo(ra, dec, showFeedback: false);

    if (!slewResult.isSuccess) {
      if (context.mounted) {
        context.showCommandActionResult(slewResult);
      }
      return;
    }

    // Show centering dialog and wait for completion
    CenteringResult? centeringResult;
    if (context.mounted) {
      centeringResult = await showDialog<CenteringResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CenteringDialogWithResult(
          targetRa: ra,
          targetDec: dec,
          targetName: targetName ?? 'Target',
        ),
      );
    }

    // If centering failed or was cancelled, don't rotate
    if (centeringResult == null || !centeringResult.success) {
      if (context.mounted && centeringResult != null) {
        context.showWarningSnackBar('Centering failed - rotation skipped');
      }
      return;
    }

    // Now rotate to target angle
    if (targetRotation != null && context.mounted) {
      try {
        final rotatorState = ref.read(rotatorStateProvider);
        if (rotatorState.connectionState == DeviceConnectionState.connected &&
            rotatorState.deviceId != null) {
          final backend = ref.read(backendProvider);
          await backend.rotatorMoveTo(rotatorState.deviceId!, targetRotation!);
          if (context.mounted) {
            context.showSuccessSnackBar(
                'Rotating to ${targetRotation!.toStringAsFixed(1)}°');
          }
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Rotation failed: $e');
        }
      }
    }
  }
}

/// Internal version of CenteringDialog that returns the result
class _CenteringDialogWithResult extends ConsumerStatefulWidget {
  final double targetRa;
  final double targetDec;
  final String targetName;

  const _CenteringDialogWithResult({
    required this.targetRa,
    required this.targetDec,
    required this.targetName,
  });

  @override
  ConsumerState<_CenteringDialogWithResult> createState() =>
      _CenteringDialogWithResultState();
}

class _CenteringDialogWithResultState
    extends ConsumerState<_CenteringDialogWithResult> {
  bool _isCentering = false;

  CenteringConfig get _centeringConfig {
    final profile = ref.read(activeEquipmentProfileProvider);
    final exposureTime = profile?.defaultCenteringExposure ?? 5.0;
    return CenteringConfig(
      maxIterations: 5,
      toleranceArcsec: 30.0,
      exposureTime: exposureTime > 0 ? exposureTime : 5.0,
      binning: profile?.defaultBinX ?? 2,
      gain: profile?.defaultGain ?? 100,
      syncMount: false,
    );
  }

  @override
  void initState() {
    super.initState();
    // Auto-start centering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCentering();
    });
  }

  Future<void> _startCentering() async {
    setState(() {
      _isCentering = true;
    });

    final centeringService = ref.read(centeringServiceProvider);
    final appSettings = ref.read(appSettingsProvider).value;
    final executablePath =
        await PlateSolverUtils.findAstapExecutable(appSettings?.astapPath);

    final solverConfig = PlateSolverConfig(
      type: PlateSolverType.astap,
      executablePath: executablePath ?? '',
      timeoutSeconds: 60,
      searchRadius: 30.0,
    );

    try {
      final result = await centeringService.centerOnTarget(
        targetRa: widget.targetRa,
        targetDec: widget.targetDec,
        solverConfig: solverConfig,
        config: _centeringConfig,
        onStatusUpdate: (status) {
          ref.read(centeringStatusProvider.notifier).state = status;
        },
      );

      if (mounted) {
        setState(() {
          _isCentering = false;
        });

        // Return result when done
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        final failureResult = CenteringResult.failure(
          errorMessage: 'Centering error: $e',
          iterations: 0,
          iterationHistory: [],
        );
        setState(() {
          _isCentering = false;
        });
        Navigator.of(context).pop(failureResult);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final centeringStatus = ref.watch(centeringStatusProvider);
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.target, color: colors.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centering Target',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.targetName,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isCentering) ...[
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: 16),
              Text(
                centeringStatus.message ?? 'Centering...',
                style: TextStyle(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Iteration ${centeringStatus.currentIteration}/${centeringStatus.maxIterations}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
              ),
              if (centeringStatus.currentOffsetArcmin != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Offset: ${centeringStatus.currentOffsetArcmin!.toStringAsFixed(2)} arcmin',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (_isCentering)
              NightshadeButton(
                onPressed: () {
                  Navigator.of(context).pop(null);
                },
                label: 'Cancel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
          ],
        ),
      ),
    );
  }
}
