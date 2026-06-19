import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../../models/command_action_result.dart';
import '../../../../services/sequence_action_service.dart';
import '../../../../utils/snackbar_helper.dart';
import '../preflight_validation_dialog.dart';
import 'run_dashboard_format.dart';

/// Large pause/resume/stop/skip footer for the Run dashboard.
///
/// The dashboard is the "watch the imaging session" view; controls live
/// here at the bottom so a tablet user can stop a run with one finger
/// without scrolling to the top. We delegate to `SequenceActionService`
/// so all sequence-control behaviour stays centralised.
class RunDashboardPlaybackFooter extends ConsumerWidget {
  const RunDashboardPlaybackFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final actionService = ref.read(sequenceActionServiceProvider);
    final isMobile = Responsive.isMobile(context);

    final isIdle = executionState == SequenceExecutionState.idle;
    final isRunning = executionState == SequenceExecutionState.running;
    final isPaused = executionState == SequenceExecutionState.paused;

    Future<void> runSequenceAction(
      Future<CommandActionResult> Function() action,
    ) async {
      final result = await action();
      if (!context.mounted) return;
      context.showCommandActionResult(result);
    }

    // "Skip target" abandons the rest of the current target and jumps to the
    // next one. The action service only exposes node-level `skip`, so we call
    // the executor's target-level primitive directly here and surface the
    // outcome with the same snackbar helpers the rest of the footer uses.
    Future<void> skipCurrentTarget() async {
      try {
        final jumpedTo =
            await ref.read(sequenceExecutorProvider).skipToTarget();
        if (!context.mounted) return;
        if (jumpedTo == null) {
          context.showInfoSnackBar('No next target — sequence finished');
        } else {
          context.showInfoSnackBar('Skipped to next target');
        }
      } catch (e) {
        if (!context.mounted) return;
        context.showErrorSnackBar('Failed to skip target: $e');
      }
    }

    final remainingSecs = progress.estimatedRemainingSecs;
    final String etaText;
    if (remainingSecs != null) {
      final finish = DateTime.now().add(
        Duration(seconds: remainingSecs.round()),
      );
      etaText = '~${formatSeconds(remainingSecs)} remaining'
          ' · done ~${formatTimeOfDay(finish)}';
    } else {
      etaText = 'Computing ETA…';
    }
    // The estimate counts planned integration only; it does NOT include
    // pending autofocus / dither / meridian-flip overhead. Surface that so
    // an operator doesn't read the finish time as a hard guarantee.
    const etaTooltip =
        'Integration time only — excludes pending autofocus, dither, '
        'and meridian-flip overhead.';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: NightshadeTokens.space2xl,
        vertical:
            isMobile ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (isPaused || isIdle)
            _BigButton(
              colors: colors,
              icon: LucideIcons.play,
              label: isIdle ? 'Start' : 'Resume',
              variant: _BigButtonVariant.primary,
              onPressed: () {
                if (isIdle) {
                  showDialog(
                    context: context,
                    builder: (context) => PreFlightValidationDialog(
                      onStartSequence: () {
                        runSequenceAction(actionService.start);
                      },
                    ),
                  );
                } else {
                  runSequenceAction(actionService.resume);
                }
              },
            )
          else
            _BigButton(
              colors: colors,
              icon: LucideIcons.pause,
              label: 'Pause',
              variant: _BigButtonVariant.warning,
              onPressed: () => runSequenceAction(actionService.pause),
            ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          _BigButton(
            colors: colors,
            icon: LucideIcons.skipForward,
            label: 'Skip',
            variant: _BigButtonVariant.outline,
            // Skip is valid while paused too — the backend skip advances the
            // node pointer regardless of running/paused (matches Stop).
            onPressed: (isRunning || isPaused)
                ? () => runSequenceAction(actionService.skip)
                : null,
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          // Skip-target abandons the remainder of the current target and jumps
          // to the next one — far more consequential than the node-level Skip,
          // so it is hold-to-confirm like Stop. Valid while running or paused
          // (matches Skip/Stop and the executor's own state gate).
          HoldToConfirmButton(
            enabled: isRunning || isPaused,
            holdColor: colors.warning,
            confirmText: 'Hold to skip target',
            semanticsLabel:
                'Press and hold to skip the rest of the current target',
            onConfirmed: skipCurrentTarget,
            child: IgnorePointer(
              child: _BigButton(
                colors: colors,
                icon: LucideIcons.fastForward,
                label: 'Skip Target',
                variant: _BigButtonVariant.outline,
                onPressed: (isRunning || isPaused) ? skipCurrentTarget : null,
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          // Stop is hold-to-confirm so a thumb-slip during an overnight
          // session can't abort the run — matching the mobile playback bar
          // and the recovery-banner Abort affordance.
          HoldToConfirmButton(
            enabled: isRunning || isPaused,
            holdColor: colors.error,
            confirmText: 'Hold to stop',
            semanticsLabel: 'Press and hold to stop the sequence',
            onConfirmed: () => runSequenceAction(actionService.stop),
            child: IgnorePointer(
              child: _BigButton(
                colors: colors,
                icon: LucideIcons.square,
                label: 'Stop',
                variant: _BigButtonVariant.danger,
                onPressed: (isRunning || isPaused)
                    ? () => runSequenceAction(actionService.stop)
                    : null,
              ),
            ),
          ),
          const Spacer(),
          if (!isMobile)
            Tooltip(
              message: etaTooltip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.hourglass,
                      size: 16, color: colors.textMuted),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    etaText,
                    style: NightshadeTypography.withTabular(
                      NightshadeTypography.label.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Icon(LucideIcons.info, size: 12, color: colors.textMuted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _BigButtonVariant { primary, outline, warning, danger }

class _BigButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final _BigButtonVariant variant;
  final VoidCallback? onPressed;

  const _BigButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.variant,
    required this.onPressed,
  });

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final enabled = widget.onPressed != null;

    final (fg, bgBase, borderColor) = switch (widget.variant) {
      _BigButtonVariant.primary => (
          widget.colors.onPrimary,
          widget.colors.primary,
          widget.colors.primary,
        ),
      _BigButtonVariant.warning => (
          widget.colors.onPrimary,
          widget.colors.warning,
          widget.colors.warning,
        ),
      _BigButtonVariant.danger => (
          widget.colors.onPrimary,
          widget.colors.error,
          widget.colors.error,
        ),
      _BigButtonVariant.outline => (
          widget.colors.textSecondary,
          Colors.transparent,
          widget.colors.border,
        ),
    };
    final filledColors = widget.variant == _BigButtonVariant.outline
        ? null
        : NightshadeDecorations.filledButtonColors(
            bgBase,
            isHovered: _hovered,
            isDisabled: !enabled,
          );

    final fgFinal = enabled ? fg : widget.colors.textMuted;
    final bgFinal = enabled
        ? (filledColors?.background ?? bgBase)
        : widget.colors.surfaceAlt;
    final borderFinal =
        enabled ? (filledColors?.border ?? borderColor) : widget.colors.border;

    final radius = BorderRadius.circular(NightshadeTokens.radiusMd);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          curve: NightshadeTokens.curveSnappy,
          decoration: BoxDecoration(
            color: bgFinal,
            borderRadius: radius,
            border: Border.all(color: borderFinal),
            boxShadow: enabled && widget.variant != _BigButtonVariant.outline
                ? NightshadeTokens.shadowMd
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: radius,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile
                      ? NightshadeTokens.spaceLg
                      : NightshadeTokens.space2xl,
                  vertical: isMobile
                      ? NightshadeTokens.spaceMd
                      : NightshadeTokens.spaceLg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: isMobile ? 18 : 22, color: fgFinal),
                    SizedBox(width: isMobile ? 6 : NightshadeTokens.spaceSm),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: isMobile
                            ? NightshadeTypography.fontSize14
                            : NightshadeTypography.fontSize16,
                        fontWeight: FontWeight.w700,
                        color: fgFinal,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
