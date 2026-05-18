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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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

    final etaText = progress.estimatedRemainingSecs != null
        ? '~${formatSeconds(progress.estimatedRemainingSecs!)} remaining'
        : 'Computing ETA…';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: NightshadeTokens.space2xl,
        vertical: isMobile
            ? NightshadeTokens.spaceMd
            : NightshadeTokens.spaceLg,
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
            onPressed:
                isRunning ? () => runSequenceAction(actionService.skip) : null,
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          _BigButton(
            colors: colors,
            icon: LucideIcons.square,
            label: 'Stop',
            variant: _BigButtonVariant.danger,
            onPressed: (isRunning || isPaused)
                ? () => runSequenceAction(actionService.stop)
                : null,
          ),
          const Spacer(),
          if (!isMobile) ...[
            Icon(LucideIcons.hourglass, size: 16, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              etaText,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
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
          Colors.white,
          widget.colors.primary,
          widget.colors.primary,
        ),
      _BigButtonVariant.warning => (
          Colors.white,
          widget.colors.warning,
          widget.colors.warning,
        ),
      _BigButtonVariant.danger => (
          Colors.white,
          widget.colors.error,
          widget.colors.error,
        ),
      _BigButtonVariant.outline => (
          widget.colors.textSecondary,
          Colors.transparent,
          widget.colors.border,
        ),
    };

    final fgFinal = enabled ? fg : widget.colors.textMuted;
    final bgFinal = enabled
        ? (_hovered
            ? Color.lerp(bgBase, Colors.white, 0.1) ?? bgBase
            : bgBase)
        : widget.colors.surfaceAlt;
    final borderFinal = enabled ? borderColor : widget.colors.border;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          curve: NightshadeTokens.curveSnappy,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile
                ? NightshadeTokens.spaceLg
                : NightshadeTokens.space2xl,
            vertical: isMobile
                ? NightshadeTokens.spaceMd
                : NightshadeTokens.spaceLg,
          ),
          decoration: BoxDecoration(
            color: bgFinal,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: borderFinal),
            boxShadow: enabled &&
                    widget.variant != _BigButtonVariant.outline
                ? NightshadeTokens.shadowMd
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: isMobile ? 18 : 22, color: fgFinal),
              SizedBox(width: isMobile ? 6 : NightshadeTokens.spaceSm),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w700,
                  color: fgFinal,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
