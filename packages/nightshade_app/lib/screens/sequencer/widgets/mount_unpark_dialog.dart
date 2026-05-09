import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _startCountdown();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
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
    if (_isUnparking) return;

    _countdownTimer?.cancel();

    setState(() {
      _isUnparking = true;
    });

    try {
      // Get the mount state to find the device ID
      final mountState = ref.read(mountStateProvider);
      if (mountState.deviceId != null && mountState.isParked) {
        // Unpark the mount
        final backend = ref.read(backendProvider);
        await backend.mountUnpark(mountState.deviceId!);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onUnparkAndContinue();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUnparking = false;
        });

        context.showErrorSnackBar('Failed to unpark mount: $e');
      }
    }
  }

  void _handleCancel() {
    _countdownTimer?.cancel();
    Navigator.of(context).pop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with pulse animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.warning
                        .withValues(alpha: 0.1 + _pulseController.value * 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.warning
                            .withValues(alpha: 0.2 * _pulseController.value),
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

            const SizedBox(height: 20),

            // Title
            Text(
              'Mount is Parked',
              style: TextStyle(
                fontSize: 18,
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
                fontSize: 13,
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
                  borderRadius: BorderRadius.circular(8),
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
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      '$_remainingSeconds',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: colors.warning,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' seconds',
                      style: TextStyle(
                        fontSize: 14,
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
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _remainingSeconds / widget.countdownSeconds,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.warning,
                      borderRadius: BorderRadius.circular(2),
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
                      fontSize: 14,
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
                    onPressed: _isUnparking ? null : _handleCancel,
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
