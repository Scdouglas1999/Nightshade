import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';

/// Result from the mount unpark dialog
enum MountUnparkResult {
  /// User chose to unpark and continue
  unparkAndContinue,

  /// User cancelled the sequence
  cancel,
}

/// Dialog shown when the mount is parked before starting a sequence.
/// Provides a 15-second countdown with options to unpark immediately or cancel.
class MountUnparkDialog extends ConsumerStatefulWidget {
  /// Callback when the user chooses to unpark and continue
  final VoidCallback onUnparkAndContinue;

  /// Callback when the user cancels
  final VoidCallback onCancel;

  /// Countdown duration in seconds
  final int countdownSeconds;

  const MountUnparkDialog({
    super.key,
    required this.onUnparkAndContinue,
    required this.onCancel,
    this.countdownSeconds = 15,
  });

  @override
  ConsumerState<MountUnparkDialog> createState() => _MountUnparkDialogState();
}

class _MountUnparkDialogState extends ConsumerState<MountUnparkDialog>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _countdownTimer;
  bool _isUnparking = false;

  /// Set the moment the operator presses Cancel, and checked again AFTER the
  /// unpark round-trip.
  ///
  /// The countdown used to become unbeatable the instant it expired: the
  /// Cancel button was disabled for the whole `unpark()` await, so a press in
  /// that window did nothing at all and the sequence started anyway. Cancel
  /// stays live and this latch is what makes it authoritative — a cancel that
  /// lands mid-unpark still aborts the start.
  bool _cancelled = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _startCountdown();

    // Started by the OnScreenAnimationGate in build(), not here: a repeat that
    // outlives visibility schedules a frame on every vsync and stops the whole
    // app from idling.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _handleUnparkAndContinue();
      }
    });
  }

  Future<void> _handleUnparkAndContinue() async {
    if (_isUnparking || _cancelled) return;

    _countdownTimer?.cancel();

    setState(() {
      _isUnparking = true;
    });

    final mountState = ref.read(mountStateProvider);
    final isAlreadyUnparked =
        mountState.connectionState == DeviceConnectionState.connected &&
            !mountState.isParked;
    if (!isAlreadyUnparked) {
      final result = await ref.read(mountCommandServiceProvider).unpark();
      // Re-read the latch after the await: the operator had a live Cancel
      // button for the whole round-trip and may have used it.
      if (_cancelled) return;
      if (!result.isSuccess) {
        if (mounted) {
          setState(() {
            _isUnparking = false;
          });
          context.showCommandActionResult(result);
        }
        return;
      }
    }

    if (_cancelled) return;
    if (mounted) {
      Navigator.of(context).pop();
      widget.onUnparkAndContinue();
    }
  }

  void _handleCancel() {
    if (_cancelled) return;
    _cancelled = true;
    _countdownTimer?.cancel();
    Navigator.of(context).pop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 420,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with pulse animation
              OnScreenAnimationGate(
                controller: _pulseController,
                repeating: true,
                reverse: true,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(
                            alpha: 0.1 + _pulseController.value * 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.warning.withValues(
                                alpha: 0.2 * _pulseController.value),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        LucideIcons.parkingCircle,
                        size: 40,
                        color: colors.warning,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                'Mount is Parked',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              // Description
              Text(
                'Your mount is currently parked. The sequence will automatically unpark the mount and continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              // Countdown timer display
              if (!_isUnparking) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.timer,
                        size: 20,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Unparking in ',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14,
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        '$_remainingSeconds',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize24,
                          fontWeight: FontWeight.w700,
                          color: colors.warning,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        ' seconds',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Progress bar
                Container(
                  height: 4,
                  width: 200,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _remainingSeconds / widget.countdownSeconds,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.warning,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline2),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Unparking in progress
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Unparking mount...',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 28),

              // Action buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: NightshadeButton(
                      // Deliberately NOT disabled while unparking: this button
                      // is the operator's only way out, and disabling it for
                      // the duration of the mount round-trip made the expiring
                      // countdown unbeatable. [_cancelled] is what makes a
                      // press here win the race with the timer.
                      onPressed: _handleCancel,
                      label: 'Cancel Sequence',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Unpark now button
                  Expanded(
                    child: NightshadeButton(
                      onPressed: _isUnparking ? null : _handleUnparkAndContinue,
                      icon: LucideIcons.play,
                      label: _isUnparking ? 'Unparking...' : 'Unpark Now',
                      variant: ButtonVariant.primary,
                      isLoading: _isUnparking,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the mount unpark dialog and returns the result
Future<MountUnparkResult?> showMountUnparkDialog(BuildContext context) async {
  MountUnparkResult? result;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => MountUnparkDialog(
      onUnparkAndContinue: () {
        result = MountUnparkResult.unparkAndContinue;
      },
      onCancel: () {
        result = MountUnparkResult.cancel;
      },
    ),
  );

  return result;
}
