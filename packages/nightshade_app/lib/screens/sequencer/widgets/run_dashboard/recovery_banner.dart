/// Wave 4 Recovery Mode — visible Run Dashboard banner + status LED.
///
/// When the executor enters `Recovering`, this banner pins to the top of
/// the Run Dashboard (above [RunDashboardCriticalBanner]) and surfaces:
///   * cause description (humanised)
///   * attempt counter ("Attempt 2 of 9")
///   * countdown until the next auto-retry
///   * "Try Now" button (forces an immediate retry)
///   * "Skip Node" button (skips the currently failing node and continues)
///   * "Abort" button, hold-to-confirm (exits the loop, marks Failed)
///
/// Reuses the design-system colour tokens from [NightshadeColors] so the
/// red palette matches the existing critical-event banner.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Persistent banner that renders the in-flight recovery context. Returns
/// an empty widget when [currentRecoveryProvider] is `null`.
///
/// Auto-rebuilds every 500ms while the recovery is in the `Waiting`
/// phase so the countdown stays smooth without the executor needing to
/// emit ProgressUpdated events for the timer alone.
class RunDashboardRecoveryBanner extends ConsumerStatefulWidget {
  const RunDashboardRecoveryBanner({super.key});

  @override
  ConsumerState<RunDashboardRecoveryBanner> createState() =>
      _RunDashboardRecoveryBannerState();
}

class _RunDashboardRecoveryBannerState
    extends ConsumerState<RunDashboardRecoveryBanner>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      // Rebuild every 500ms so the countdown ticks smoothly. We don't
      // store this as state — we just trigger a setState to re-read
      // `nextAttemptInSecs(now)`. The timer is cheap (no setState body)
      // because it's only re-evaluating an in-memory DateTime delta.
      if ((d - _elapsed).inMilliseconds < 500) return;
      _elapsed = d;
      if (mounted) setState(() {});
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(currentRecoveryProvider);
    if (ctx == null) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);
    final control = ref.read(recoveryControlProvider);
    final now = DateTime.now().toUtc();
    final nextAttemptSecs = ctx.nextAttemptInSecs(now);
    final remainingBudgetSecs =
        ctx.remainingSecs(now).clamp(0.0, double.infinity);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.20),
        border: Border(
          top: BorderSide(color: colors.error, width: 1.8),
          bottom: BorderSide(color: colors.error.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.space2xl,
          vertical: NightshadeTokens.spaceMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StatusDot(
                color: colors.error,
                size: 12,
                variant: StatusDotVariant.urgent),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'RECOVERING',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
                          fontWeight: FontWeight.w800,
                          color: colors.error,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          ctx.cause.displayLabel,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusLine(ctx, nextAttemptSecs, remainingBudgetSecs),
                    style: NightshadeTypography.withTabular(
                      NightshadeTypography.labelSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (ctx.lastError != null && ctx.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Last error: ${ctx.lastError}',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            _RecoveryActionButtons(colors: colors, control: control),
          ],
        ),
      ),
    );
  }

  String _statusLine(
      RecoveryStatus ctx, double nextAttemptSecs, double remainingBudgetSecs) {
    final attempts = 'Attempt ${ctx.attemptCount} of ${ctx.maxAttempts}';
    if (ctx.isAttempting) {
      return '$attempts · attempting now…';
    }
    if (ctx.isWaiting) {
      if (nextAttemptSecs <= 1.0) {
        return '$attempts · next attempt firing now';
      }
      return '$attempts · next retry in ${_formatSecs(nextAttemptSecs)}'
          ' · budget left ${_formatSecs(remainingBudgetSecs)}';
    }
    if (ctx.isRecovered) {
      return '$attempts · recovered — resuming sequence';
    }
    if (ctx.isGaveUp) {
      return '$attempts · loop ended';
    }
    return attempts;
  }

  String _formatSecs(double s) {
    if (s < 60) {
      return '${s.round()}s';
    }
    final mins = (s / 60).floor();
    final secs = (s - mins * 60).round();
    return secs == 0 ? '${mins}m' : '${mins}m ${secs}s';
  }
}

/// Trio of recovery-mode buttons: Try Now, Skip Node, Abort.
///
/// Extracted from the banner body so the same affordance can be reused by
/// the companion mobile [SequencerTab] (audit P1-8 — recovery actions on
/// mobile). Each button tracks its own in-flight state so a busy "Abort"
/// hold-and-release does not freeze the "Try Now" spinner.
///
/// The Abort button is wrapped in [HoldToConfirmButton] (1500ms hold) so a
/// stray click cannot kill a multi-hour overnight run; the same gating is
/// applied on the mobile companion. Errors thrown by the underlying
/// [RecoveryControl] surface to the operator via a [ScaffoldMessenger]
/// SnackBar rather than being swallowed — per CLAUDE.md "errors are a
/// feature".
class _RecoveryActionButtons extends StatefulWidget {
  final NightshadeColors colors;
  final RecoveryControl control;

  const _RecoveryActionButtons({
    required this.colors,
    required this.control,
  });

  @override
  State<_RecoveryActionButtons> createState() => _RecoveryActionButtonsState();
}

class _RecoveryActionButtonsState extends State<_RecoveryActionButtons> {
  bool _tryNowBusy = false;
  bool _skipBusy = false;
  bool _abortBusy = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _tryNow() async {
    if (_tryNowBusy) return;
    setState(() => _tryNowBusy = true);
    try {
      await widget.control.tryNow();
    } catch (e) {
      _showError(extractRecoveryActionError('Retry failed', e));
    } finally {
      if (mounted) setState(() => _tryNowBusy = false);
    }
  }

  Future<void> _skipNode() async {
    if (_skipBusy) return;
    setState(() => _skipBusy = true);
    try {
      await widget.control.skipNode();
    } catch (e) {
      _showError(extractRecoveryActionError('Skip failed', e));
    } finally {
      if (mounted) setState(() => _skipBusy = false);
    }
  }

  Future<void> _abort() async {
    if (_abortBusy) return;
    setState(() => _abortBusy = true);
    try {
      await widget.control.abort();
    } catch (e) {
      _showError(extractRecoveryActionError('Abort failed', e));
    } finally {
      if (mounted) setState(() => _abortBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NightshadeButton(
          key: const Key('recovery_try_now'),
          label: 'Try Now',
          icon: LucideIcons.rotateCw,
          size: ButtonSize.small,
          isLoading: _tryNowBusy,
          onPressed: _tryNowBusy ? null : _tryNow,
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        NightshadeButton(
          key: const Key('recovery_skip_node'),
          label: 'Skip Node',
          icon: LucideIcons.skipForward,
          size: ButtonSize.small,
          variant: ButtonVariant.outline,
          isLoading: _skipBusy,
          onPressed: _skipBusy ? null : _skipNode,
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        // Abort exits the recovery loop and marks the sequence Failed —
        // an unrecoverable user decision. Wrap in [HoldToConfirmButton]
        // so a stray click on a phone, trackpad, or accidental keyboard
        // activation can't kill an overnight run. The inner button stays
        // keyed `recovery_abort` for backward-compat with widget tests;
        // tests targeting the destructive path now drive a long-press.
        HoldToConfirmButton(
          key: const Key('recovery_abort_hold'),
          enabled: !_abortBusy,
          holdColor: widget.colors.error,
          confirmText: 'Hold to abort',
          semanticsLabel: 'Press and hold to abort recovery',
          onConfirmed: _abort,
          child: IgnorePointer(
            child: NightshadeButton(
              key: const Key('recovery_abort'),
              label: 'Abort',
              icon: LucideIcons.xOctagon,
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              isLoading: _abortBusy,
              onPressed: _abort,
            ),
          ),
        ),
      ],
    );
  }
}

/// Best-effort error formatter for the recovery action buttons.
///
/// [NightshadeError] from the network backend carries a userMessage that
/// is already operator-friendly; anything else falls back to the raw
/// `toString()` after stripping the `Exception:` prefix common to
/// Dart `Exception` subclasses.
String extractRecoveryActionError(String prefix, Object error) {
  if (error is NightshadeError) {
    return '$prefix: ${error.userMessage}';
  }
  final raw = error.toString();
  final cleaned =
      raw.startsWith('Exception: ') ? raw.substring('Exception: '.length) : raw;
  return '$prefix: $cleaned';
}

/// Status-LED widget used by the sequencer screen's top bar and the
/// dashboard header. Reads [sequenceProgressProvider] for the canonical
/// state and renders a small dot with a colour that matches the state.
/// Recovering pulses red; Failed is solid red; Paused is orange; Running
/// is green; Idle is grey.
class SequencerStatusLed extends ConsumerWidget {
  final double size;
  final bool showLabel;

  const SequencerStatusLed({
    super.key,
    this.size = 10.0,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(sequenceProgressProvider);
    final colors = NightshadeColors.of(context);
    final state = progress.state;

    Color color;
    String label;
    StatusDotVariant variant = StatusDotVariant.static;
    switch (state) {
      case SequenceExecutionState.idle:
        color = colors.textMuted;
        label = 'Idle';
        break;
      case SequenceExecutionState.running:
        color = colors.success;
        label = 'Running';
        break;
      case SequenceExecutionState.paused:
        color = colors.warning;
        label = 'Paused';
        break;
      case SequenceExecutionState.stopping:
        color = colors.warning;
        label = 'Stopping';
        break;
      case SequenceExecutionState.completed:
        color = colors.success;
        label = 'Completed';
        break;
      case SequenceExecutionState.failed:
        color = colors.error;
        label = 'Failed';
        variant = StatusDotVariant.urgent;
        break;
      case SequenceExecutionState.recovering:
        color = colors.error;
        label = 'Recovering';
        variant = StatusDotVariant.urgent;
        break;
    }

    final dot = StatusDot(color: color, size: size, variant: variant);

    if (!showLabel) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
