import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/sequence_action_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../sequencer/widgets/preflight_validation_dialog.dart';

/// Inline run-control strip for the Dashboard cockpit.
///
/// Mirrors the sequencer's [MobilePlaybackBar] controls so the user can manage
/// a run (pause / resume, hold-to-stop, skip) — and launch one — without
/// leaving the cockpit.
///
/// Visibility:
///   * ACTIVE (running / paused / stopping / recovering) → pause/resume,
///     hold-to-stop, and skip controls.
///   * IDLE with a launchable sequence loaded (has a target or exposures) → a
///     Start button gated by the pre-flight dialog, plus a "Ready" badge.
///   * Otherwise (idle with nothing loaded, completed, or failed) → collapses
///     to a zero-size box so the cockpit gains no chrome.
class CockpitRunControls extends ConsumerWidget {
  final NightshadeColors colors;

  const CockpitRunControls({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sequenceExecutionStateProvider);
    final isActive = _isActive(state);
    final isIdle = state == SequenceExecutionState.idle;

    // A sequence is "launchable" once it has at least one target or exposure —
    // i.e. the user has actually built something to image (not the empty
    // auto-created default). When idle with such a sequence loaded we offer a
    // Start button so the night can be launched from the cockpit.
    final sequence = ref.watch(currentSequenceProvider);
    final hasLaunchableSequence = sequence != null &&
        (sequence.targetHeaders.isNotEmpty || sequence.totalExposures > 0);
    final showStart = isIdle && hasLaunchableSequence;

    // Self-hide when there's nothing to control: idle with no loaded sequence,
    // or a terminal completed / failed state.
    if (!isActive && !showStart) return const SizedBox.shrink();

    final Widget controls;
    if (showStart) {
      Future<void> startSequence() async {
        // Route through the same pre-flight gate the sequencer uses so the
        // cockpit Start can't skip the safety checks.
        await showDialog<void>(
          context: context,
          builder: (_) => PreFlightValidationDialog(
            onStartSequence: () async {
              final result =
                  await ref.read(sequenceActionServiceProvider).start();
              if (!context.mounted) return;
              context.showCommandActionResult(result);
            },
          ),
        );
      }

      controls = Row(
        children: [
          _ControlButton(
            colors: colors,
            icon: LucideIcons.play,
            label: 'Start',
            isActive: true,
            onPressed: startSequence,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sequence ready — start tonight’s run.',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ReadyBadge(colors: colors),
        ],
      );
    } else {
      final isRunning = state == SequenceExecutionState.running;
      final isPaused = state == SequenceExecutionState.paused;

      Future<void> pauseOrResume() async {
        final service = ref.read(sequenceActionServiceProvider);
        final result =
            isRunning ? await service.pause() : await service.resume();
        if (!context.mounted) return;
        context.showCommandActionResult(result);
      }

      Future<void> stopSequence() async {
        final result = await ref.read(sequenceActionServiceProvider).stop();
        if (!context.mounted) return;
        context.showCommandActionResult(result);
      }

      Future<void> skipNode() async {
        final result = await ref.read(sequenceActionServiceProvider).skip();
        if (!context.mounted) return;
        context.showCommandActionResult(result);
      }

      controls = Row(
        children: [
          // Play/Pause toggles on the live execution state: running shows
          // Pause, paused shows Resume. The Pause-active styling tells the
          // user the sequence is live.
          _ControlButton(
            colors: colors,
            icon: isRunning ? LucideIcons.pause : LucideIcons.play,
            label: isRunning ? 'Pause' : 'Resume',
            isActive: isRunning,
            // While stopping/recovering, pause/resume isn't a meaningful
            // action — only enable it in the running/paused states.
            isEnabled: isRunning || isPaused,
            onPressed: pauseOrResume,
          ),
          const SizedBox(width: 8),
          // Stop is hold-to-confirm so a stray click can't abort an overnight
          // run; the inner button is IgnorePointer so the hold gesture is
          // owned exclusively by HoldToConfirmButton.
          HoldToConfirmButton(
            enabled: isRunning || isPaused,
            holdColor: colors.error,
            confirmText: 'Hold to stop',
            semanticsLabel: 'Press and hold to stop the sequence',
            onConfirmed: stopSequence,
            child: IgnorePointer(
              child: _ControlButton(
                colors: colors,
                icon: LucideIcons.square,
                label: 'Stop',
                isEnabled: isRunning || isPaused,
                onPressed: stopSequence,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Skip the current instruction — only meaningful while running.
          _ControlButton(
            colors: colors,
            icon: LucideIcons.skipForward,
            label: 'Skip',
            isEnabled: isRunning,
            onPressed: skipNode,
          ),
          const Spacer(),
          _StateBadge(colors: colors, state: state),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
        boxShadow: NightshadeTokens.elevationLevel1,
      ),
      child: controls,
    );
  }

  bool _isActive(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.running:
      case SequenceExecutionState.paused:
      case SequenceExecutionState.stopping:
      case SequenceExecutionState.recovering:
        return true;
      case SequenceExecutionState.idle:
      case SequenceExecutionState.completed:
      case SequenceExecutionState.failed:
        return false;
    }
  }
}

/// Small "Ready" chip shown next to the Start button when a launchable
/// sequence is loaded but not yet running.
class _ReadyBadge extends StatelessWidget {
  final NightshadeColors colors;

  const _ReadyBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: NightshadeDecorations.statusChip(
        colors.info,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: colors.info, size: 8),
          const SizedBox(width: 6),
          Text(
            'Ready',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w700,
              color: colors.info,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isEnabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            constraints: const BoxConstraints(minWidth: 36),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.success.withValues(alpha: 0.12)
                  : isEnabled
                      ? colors.surface
                      : colors.surface.withValues(alpha: 0.5),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(
                color: isActive
                    ? colors.success.withValues(alpha: 0.5)
                    : colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? colors.success
                      : isEnabled
                          ? colors.textPrimary
                          : colors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: NightshadeTypography.h6.copyWith(
                    color: isActive
                        ? colors.success
                        : isEnabled
                            ? colors.textPrimary
                            : colors.textMuted,
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

class _StateBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState state;

  const _StateBadge({required this.colors, required this.state});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (state) {
      SequenceExecutionState.running => (
          colors.success,
          LucideIcons.activity,
          'Running',
        ),
      SequenceExecutionState.paused => (
          colors.warning,
          LucideIcons.pauseCircle,
          'Paused',
        ),
      SequenceExecutionState.stopping => (
          colors.warning,
          LucideIcons.loader,
          'Stopping',
        ),
      SequenceExecutionState.recovering => (
          colors.error,
          LucideIcons.rotateCw,
          'Recovering',
        ),
      // Inactive states never reach this widget (the strip is hidden), but
      // the switch must be exhaustive.
      SequenceExecutionState.idle => (
          colors.textMuted,
          LucideIcons.circleOff,
          'Idle',
        ),
      SequenceExecutionState.completed => (
          colors.info,
          LucideIcons.checkCircle,
          'Completed',
        ),
      SequenceExecutionState.failed => (
          colors.error,
          LucideIcons.xCircle,
          'Failed',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(
            color: color,
            size: 8,
            variant: state == SequenceExecutionState.recovering
                ? StatusDotVariant.urgent
                : StatusDotVariant.static,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
