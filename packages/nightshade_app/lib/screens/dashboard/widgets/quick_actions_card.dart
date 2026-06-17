import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../imaging/centering_dialog.dart';
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
    final isCameraConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isFocuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final isMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final hasTarget = session.targetRa != null && session.targetDec != null;

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
        onTap: isMountConnected
            ? () async {
                if (!mountState.canPark) {
                  context.showErrorSnackBar(
                      'Mount driver does not support parking');
                  return;
                }
                try {
                  await ref.read(mountCommandServiceProvider).park();
                } catch (e) {
                  if (context.mounted) {
                    context.showErrorSnackBar('Failed to park mount: $e');
                  }
                }
              }
            : null,
      ),
    ];

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.zap,
            title: 'Quick Actions',
            accent: colors.primary,
          ),

          const SizedBox(height: DashboardCardStyle.headerGap),

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
      var settings = ref.read(exposureSettingsProvider);
      if (cameraState.gain != null) {
        settings = settings.copyWith(gain: cameraState.gain);
      }
      if (cameraState.offset != null) {
        settings = settings.copyWith(offset: cameraState.offset);
      }
      if (cameraState.binning != null) {
        final binParts = cameraState.binning!.split('x');
        if (binParts.length == 2) {
          final bx = int.tryParse(binParts[0]);
          final by = int.tryParse(binParts[1]);
          if (bx != null && by != null) {
            settings = settings.copyWith(binningX: bx, binningY: by);
          }
        }
      }

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
        builder: (ctx) => CenteringDialog(
          targetRa: targetRa,
          targetDec: targetDec,
          targetName: session.targetName ?? 'Target',
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        child: GestureDetector(
          onTap: isEnabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isActiveHover
                  ? widget.colors.primary.withValues(alpha: 0.1)
                  : widget.colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(
                color: isActiveHover
                    ? widget.colors.primary
                    : widget.colors.border,
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
                    style: NightshadeTypography.labelSm.copyWith(
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
