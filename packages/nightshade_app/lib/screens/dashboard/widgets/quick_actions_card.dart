import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'glass_card.dart';

/// Quick Actions card with responsive layout.
///
/// Adapts to available width:
/// - Narrow (<280px): Single column stack
/// - Medium (280-400px): 2x2 grid
/// - Wide (>400px): Single row with all 4 buttons
class QuickActionsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const QuickActionsCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mount capabilities to gate Park button
    final cameraState = ref.watch(cameraStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final session = ref.watch(sessionStateProvider);
    final mountCapabilitiesAsync =
        ref.watch(mountCapabilitiesProvider(mountState.deviceId ?? ''));
    final mountCapabilities = mountCapabilitiesAsync.valueOrNull;
    final isCameraConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isFocuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final isMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final hasTarget = session.targetRa != null && session.targetDec != null;
    final canPark = isMountConnected && (mountCapabilities?.canPark ?? true);

    // Build action buttons with their callbacks
    final actionButtons = [
      _ActionButtonData(
        icon: LucideIcons.camera,
        label: 'Snapshot',
        onTap: isCameraConnected ? () => _handleSnapshot(context, ref) : null,
      ),
      _ActionButtonData(
        icon: LucideIcons.focus,
        label: 'Autofocus',
        onTap: isCameraConnected && isFocuserConnected
            ? () => _handleAutofocus(context, ref)
            : null,
      ),
      _ActionButtonData(
        icon: LucideIcons.crosshair,
        label: 'Center',
        onTap: isCameraConnected && isMountConnected && hasTarget
            ? () => _handleCenter(context, ref)
            : null,
      ),
      _ActionButtonData(
        icon: LucideIcons.parkingCircle,
        label: 'Park',
        onTap:
            canPark ? () => ref.read(mountCommandServiceProvider).park() : null,
      ),
    ];

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          // Responsive button layout
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (width < 280) {
                // Narrow: Single column stack
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      _ActionButton(
                        icon: actionButtons[i].icon,
                        label: actionButtons[i].label,
                        colors: colors,
                        onTap: actionButtons[i].onTap,
                      ),
                      if (i < actionButtons.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                );
              } else if (width < 400) {
                // Medium: 2x2 grid
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[0].icon,
                            label: actionButtons[0].label,
                            colors: colors,
                            onTap: actionButtons[0].onTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[1].icon,
                            label: actionButtons[1].label,
                            colors: colors,
                            onTap: actionButtons[1].onTap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[2].icon,
                            label: actionButtons[2].label,
                            colors: colors,
                            onTap: actionButtons[2].onTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[3].icon,
                            label: actionButtons[3].label,
                            colors: colors,
                            onTap: actionButtons[3].onTap,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              } else {
                // Wide: Single row with all buttons
                return Row(
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: actionButtons[i].icon,
                          label: actionButtons[i].label,
                          colors: colors,
                          onTap: actionButtons[i].onTap,
                        ),
                      ),
                      if (i < actionButtons.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleSnapshot(BuildContext context, WidgetRef ref) async {
    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      context.showErrorSnackBar('Camera not connected');
      return;
    }

    try {
      final settings = ref.read(exposureSettingsProvider);
      final imagingService = ref.read(imagingServiceProvider);
      final sessionNotifier = ref.read(sessionStateProvider.notifier);

      sessionNotifier.setCapturing(true);

      final result = await imagingService.captureImage(
        settings: settings,
        targetName: ref.read(sessionStateProvider).targetName,
      );

      if (result != null) {
        ref.read(currentImageProvider.notifier).state = result;
        ref.read(lastImageStatsProvider.notifier).state = result.stats;
        sessionNotifier.recordExposureComplete(
          exposureTime: settings.exposureTime,
          hfr: result.stats.hfr,
        );

        if (!context.mounted) return;
        context.showSuccessSnackBar('Snapshot captured');
      }
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Snapshot failed: $e');
    } finally {
      ref.read(sessionStateProvider.notifier).setCapturing(false);
    }
  }

  Future<void> _handleAutofocus(BuildContext context, WidgetRef ref) async {
    final cameraState = ref.read(cameraStateProvider);
    final focuserState = ref.read(focuserStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      context.showErrorSnackBar('Camera not connected');
      return;
    }

    if (focuserState.connectionState != DeviceConnectionState.connected) {
      context.showErrorSnackBar('Focuser not connected');
      return;
    }

    // Show progress notification - the device service will handle detailed progress
    // via activeOperationsProvider, but we show a quick snackbar for immediate feedback
    context.showInfoSnackBar(
      'Starting autofocus...',
      duration: const Duration(seconds: 2),
    );

    try {
      final deviceService = ref.read(deviceServiceProvider);
      final result = await deviceService.runAutofocus(
        exposureTime: 3.0,
        stepSize: 100,
        stepsOut: 7,
        method: 'VCurve',
        binning: 1,
      );

      if (!context.mounted) return;

      // Show success with key result metrics
      final hfrText = result.bestHfr.toStringAsFixed(2);
      final posText = result.bestPosition.toString();
      context.showSuccessSnackBar(
        'Autofocus complete: Position $posText, HFR $hfrText',
      );
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Autofocus failed: $e');
    }
  }

  void _handleCenter(BuildContext context, WidgetRef ref) {
    // Check if we have a target set
    final session = ref.read(sessionStateProvider);
    final targetRa = session.targetRa;
    final targetDec = session.targetDec;

    if (targetRa == null || targetDec == null) {
      context.showWarningSnackBar(
        'No target set. Please set a target first.',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    // Show centering dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CenteringDialog(
          ref: ref,
          targetRa: targetRa,
          targetDec: targetDec,
          targetName: session.targetName ?? 'Target',
          colors: colors,
        ),
      );
    }
  }
}

/// Data class for action button configuration.
class _ActionButtonData {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButtonData({
    required this.icon,
    required this.label,
    this.onTap,
  });
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    final isActiveHover = _isHovered && isEnabled;

    return MouseRegion(
      cursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) {
        if (isEnabled) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (_isHovered) {
          setState(() => _isHovered = false);
        }
      },
      // FocusRing surfaces keyboard focus on these GestureDetector-based
      // action buttons; without it keyboard nav silently skipped them.
      child: FocusRing(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isActiveHover
                ? widget.colors.primary.withValues(alpha: 0.1)
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isActiveHover ? widget.colors.primary : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: isEnabled
                    ? (isActiveHover
                        ? widget.colors.primary
                        : widget.colors.textSecondary)
                    : widget.colors.textMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                        ? (isActiveHover
                            ? widget.colors.primary
                            : widget.colors.textSecondary)
                        : widget.colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Centering dialog for plate solving and centering on target
class _CenteringDialog extends StatefulWidget {
  final WidgetRef ref;
  final double targetRa;
  final double targetDec;
  final String targetName;
  final NightshadeColors colors;

  const _CenteringDialog({
    required this.ref,
    required this.targetRa,
    required this.targetDec,
    required this.targetName,
    required this.colors,
  });

  @override
  State<_CenteringDialog> createState() => _CenteringDialogState();
}

class _CenteringDialogState extends State<_CenteringDialog> {
  String _status = 'Initializing...';
  bool _isRunning = true;
  int _iteration = 0;
  static const int _maxIterations = 3;
  double? _lastRaError;
  double? _lastDecError;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _runCentering();
  }

  Future<void> _runCentering() async {
    try {
      final imagingService = widget.ref.read(imagingServiceProvider);
      final mountService = widget.ref.read(mountCommandServiceProvider);
      final settings = widget.ref.read(appSettingsProvider).value;
      final astapPath = settings?.astapPath ?? '';

      // Use user-configured exposure settings for centering captures
      final userSettings = widget.ref.read(exposureSettingsProvider);
      final centeringSettings = ExposureSettings(
        exposureTime:
            userSettings.exposureTime > 0 ? userSettings.exposureTime : 5.0,
        gain: userSettings.gain,
        offset: userSettings.offset,
        binningX: userSettings.binningX > 0 ? userSettings.binningX : 2,
        binningY: userSettings.binningY > 0 ? userSettings.binningY : 2,
      );

      while (_iteration < _maxIterations && _isRunning) {
        _iteration++;

        // Step 1: Take an image
        setState(() => _status =
            'Capturing image (attempt $_iteration/$_maxIterations)...');

        final image = await imagingService.captureImage(
          settings: centeringSettings,
          targetName: 'center_${widget.targetName}',
        );

        if (image == null || image.filePath == null) {
          setState(() => _status = 'Failed to capture image');
          return;
        }

        // Step 2: Plate solve
        setState(() => _status = 'Plate solving...');

        // PlateSolveService tries backend.plateSolve() first (works for both local and remote)
        // Only falls back to local solver if backend fails
        final executablePath =
            await PlateSolverUtils.findAstapExecutable(astapPath);

        final result = await widget.ref.read(plateSolveServiceProvider).solve(
              image.filePath!,
              PlateSolverConfig(
                type: PlateSolverType.astap,
                hintRa: widget.targetRa,
                hintDec: widget.targetDec,
                searchRadius: 15.0,
                // Provide path for local fallback - backend is tried first
                executablePath: executablePath ?? '',
              ),
            );

        if (!result.success || result.ra == null || result.dec == null) {
          setState(() => _status =
              'Plate solve failed: ${result.errorMessage ?? "Unknown error"}');
          return;
        }

        // Step 3: Calculate error
        // RA is in hours, Dec is in degrees. Convert both to arcsec for display.
        // 1 hour RA = 15 degrees = 54000 arcsec
        final raErrorArcsec =
            (result.ra! - widget.targetRa) * 15.0 * 3600.0; // hours to arcsec
        final decErrorArcsec =
            (result.dec! - widget.targetDec) * 3600.0; // degrees to arcsec
        final totalErrorArcsec = math.sqrt(
            raErrorArcsec * raErrorArcsec + decErrorArcsec * decErrorArcsec);

        setState(() {
          _lastRaError = raErrorArcsec;
          _lastDecError = decErrorArcsec;
          _status =
              'Error: ${totalErrorArcsec.toStringAsFixed(1)}" (RA: ${raErrorArcsec.toStringAsFixed(1)}", Dec: ${decErrorArcsec.toStringAsFixed(1)}")';
        });

        // Check if centered enough (within 30 arcseconds)
        if (totalErrorArcsec < 30.0) {
          setState(() {
            _success = true;
            _status =
                'Centered! Error: ${totalErrorArcsec.toStringAsFixed(1)}"';
          });
          break;
        }

        // Step 4: Slew to corrected position
        setState(() => _status = 'Slewing to corrected position...');

        // Convert arcsec error back to coordinate units for correction
        // RA: arcsec / (15 * 3600) = hours, Dec: arcsec / 3600 = degrees
        final newRa = widget.targetRa -
            (raErrorArcsec / (15.0 * 3600.0)); // Correct for offset (hours)
        final newDec = widget.targetDec -
            (decErrorArcsec / 3600.0); // Correct for offset (degrees)

        // Use service without feedback - dialog shows its own status
        await mountService.slewTo(newRa, newDec, showFeedback: false);

        // Wait for slew to complete
        await Future.delayed(const Duration(seconds: 2));

        // Small delay before next iteration
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!_success && _iteration >= _maxIterations) {
        setState(() {
          _status =
              'Max iterations reached. Last error: RA ${_lastRaError?.toStringAsFixed(1)}", Dec ${_lastDecError?.toStringAsFixed(1)}"';
        });
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 400;

    return AlertDialog(
      backgroundColor: widget.colors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: widget.colors.border),
      ),
      title: Row(
        children: [
          Icon(
            _success ? LucideIcons.checkCircle : LucideIcons.crosshair,
            color: _success ? widget.colors.success : widget.colors.primary,
            size: isSmallScreen ? 20 : 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSmallScreen ? 'Centering' : 'Centering on ${widget.targetName}',
              style: TextStyle(
                color: widget.colors.textPrimary,
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isRunning)
            const LinearProgressIndicator()
          else if (_success)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle,
                      color: widget.colors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target centered successfully!',
                      style: TextStyle(
                          color: widget.colors.success,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(color: widget.colors.textSecondary, fontSize: 14),
          ),
          if (_lastRaError != null || _lastDecError != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('RA Error:',
                    style: TextStyle(
                        color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastRaError?.toStringAsFixed(1) ?? "---"}"',
                    style: TextStyle(
                        color: widget.colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dec Error:',
                    style: TextStyle(
                        color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastDecError?.toStringAsFixed(1) ?? "---"}"',
                    style: TextStyle(
                        color: widget.colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Iteration: $_iteration / $_maxIterations',
            style: TextStyle(color: widget.colors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (_isRunning)
          NightshadeButton(
            onPressed: () {
              setState(() => _isRunning = false);
            },
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          )
        else
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
      ],
    );
  }
}
