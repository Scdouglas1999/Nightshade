import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        FirstLaunchCoachStatus,
        ReadinessLevel,
        firstLaunchCoachDaoProvider,
        firstLaunchCoachStatusProvider;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/readiness/readiness_panel.dart'
    show readinessItemIcon, readinessLevelColor;
import 'first_launch_coach_progress.dart';

/// The single, self-contained surface for the rich progressive first-launch
/// coach.
///
/// This widget renders *content only* — where and when it appears (the
/// auto-launch gate, the 800ms defer, the dashboard placement) is owned by the
/// coach launcher (C7). [FirstLaunchCoachPanel] simply assumes it has been
/// mounted because the coach is live, and draws the appropriate state.
///
/// ## What it shows
///
/// It fuses two providers:
///   * [firstLaunchCoachProgressProvider] (C4) — the live per-step progress,
///     derived entirely from the readiness engine, so checkmarks tick as the
///     user does the real work.
///   * [firstLaunchCoachStatusProvider] (C2) — the persisted status, used to
///     suppress the panel the instant persistence says the coach was already
///     completed or dismissed (avoiding a flash of stale content between the
///     side-effect write and the launcher's gate re-resolving).
///
/// Two visual modes:
///   * **Checklist** — a step-by-step list with a progress bar, one row per
///     [CoachStepProgress] (status dot, item icon, title, why-it-matters, and a
///     "Do it now" deep-link button while the step is outstanding).
///   * **Celebration** — shown once every step is complete: a rocket icon chip,
///     a congratulatory line, and a primary "Capture first light" call to
///     action. Mirrors the onboarding wizard's terminal "you're all set" panel
///     so the two finish surfaces speak the same visual language.
///
/// ## Self-retiring (without unmounting the celebration)
///
/// On the first transition to [CoachProgress.allComplete] the panel persists
/// [FirstLaunchCoachDao.markCompleted] so the coach never auto-returns on the
/// *next* launch. It deliberately does **not** invalidate
/// [firstLaunchCoachStatusProvider]: doing so would flip the launcher's gate
/// from `pending` to `completed` mid-session and tear this panel — and the
/// celebration body the user has just earned — straight back off the screen.
/// Instead the persisted `completed` flag closes the auto-launch gate on the
/// next run, while the launcher (which last read `pending`) keeps this panel
/// mounted for the remainder of the current session so the "Capture first
/// light" hand-off is actually reachable and tappable.
///
/// Dismissal is different: the user opted out, so [markDismissed] *does*
/// invalidate the status provider to collapse the surface immediately.
///
/// The completion side-effect runs from a `mounted`-guarded [ref.listen]
/// callback (per the project's event-listener rule), which is why this is a
/// [ConsumerStatefulWidget] rather than a [ConsumerWidget]: a stateless build
/// cannot safely fire a one-shot persistence write without re-firing on every
/// rebuild.
class FirstLaunchCoachPanel extends ConsumerStatefulWidget {
  const FirstLaunchCoachPanel({super.key});

  @override
  ConsumerState<FirstLaunchCoachPanel> createState() =>
      _FirstLaunchCoachPanelState();
}

class _FirstLaunchCoachPanelState
    extends ConsumerState<FirstLaunchCoachPanel> {
  /// Guards the one-shot "mark completed" persistence so it fires exactly once
  /// per mounted lifetime, even though the progress provider may emit several
  /// `allComplete` values in a row (e.g. an unrelated readiness recompute).
  bool _completionPersisted = false;

  @override
  void initState() {
    super.initState();
    // Drive the self-retiring write off a listener rather than off `build` so a
    // rebuild for any other reason (theme change, ancestor relayout) cannot
    // re-trigger the persistence write. The listener is `mounted`-guarded per
    // the project's StateNotifier/event-listener rule.
    ref.listenManual<CoachProgress>(
      firstLaunchCoachProgressProvider,
      (previous, next) => _maybePersistCompletion(next),
      fireImmediately: true,
    );
  }

  /// Persist completion the first time the coach reaches "all complete".
  ///
  /// Idempotent via [_completionPersisted]. The write is fire-and-forget on
  /// purpose: we never await it on the UI path, and — critically — we do **not**
  /// invalidate [firstLaunchCoachStatusProvider] afterward. Flipping the status
  /// to `completed` mid-session would re-resolve the launcher's gate (which only
  /// shows on `pending`) and unmount this very panel, snatching the celebration
  /// and its "Capture first light" hand-off away the instant they appear. The
  /// persisted `completed` flag is enough to close the auto-launch gate on the
  /// next run; the launcher keeps the panel mounted for the rest of *this*
  /// session because the status it already read is still `pending`.
  void _maybePersistCompletion(CoachProgress progress) {
    if (_completionPersisted) return;
    if (!progress.allComplete) return;
    _completionPersisted = true;
    _retireCoachAsCompleted();
  }

  /// Records the coach as completed in persistence so it never auto-returns on
  /// the next launch.
  ///
  /// `mounted`-guarded only so a write that resolves after the panel is torn
  /// down does not touch a disposed `WidgetRef`. Note there is intentionally no
  /// `ref.invalidate(firstLaunchCoachStatusProvider)` here — see
  /// [_maybePersistCompletion] for why keeping the in-session gate on `pending`
  /// is what makes the celebration reachable.
  Future<void> _retireCoachAsCompleted() async {
    await ref.read(firstLaunchCoachDaoProvider).markCompleted();
  }

  Future<void> _dismiss() async {
    await ref.read(firstLaunchCoachDaoProvider).markDismissed();
    if (!mounted) return;
    ref.invalidate(firstLaunchCoachStatusProvider);
  }

  /// "Capture first light" — hand off to the imaging screen's guided
  /// first-light flow and ensure the coach is retired as completed (the user
  /// has reached the finish line, even if a late readiness flicker had not yet
  /// driven the listener).
  void _captureFirstLight() {
    if (!_completionPersisted) {
      _completionPersisted = true;
      _retireCoachAsCompleted();
    }
    context.go('/imaging?firstLight=1');
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final progress = ref.watch(firstLaunchCoachProgressProvider);
    final status = ref.watch(firstLaunchCoachStatusProvider);

    final persisted = status.valueOrNull;

    // Render nothing until persistence has spoken (`unknown` → null while the
    // DAO read is in flight). We never flash content before knowing the coach
    // wasn't already retired.
    if (persisted == null) {
      return const SizedBox.shrink();
    }

    // A dismissed coach hides immediately — the user opted out, so collapse the
    // surface the instant the dismiss write lands (the launcher's gate is also
    // closed, this just removes the visible frame without waiting on it).
    if (persisted == FirstLaunchCoachStatus.dismissed) {
      return const SizedBox.shrink();
    }

    // The `completed` status is NOT suppressed here, and the completion write
    // deliberately does not invalidate the status provider (see
    // `_maybePersistCompletion`). When the user reaches the end this session,
    // the listener persists completion so the coach never auto-returns *next*
    // launch — but the launcher's gate stays on the `pending` it already read,
    // so this panel remains mounted and the celebration stays on screen now,
    // letting the user take the "Capture first light" hand-off. Once mounted,
    // the live `progress` drives which body renders.

    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: NightshadeTokens.cardPadding,
      child: progress.allComplete
          ? _CelebrationBody(
              colors: colors,
              onCaptureFirstLight: _captureFirstLight,
            )
          : _ChecklistBody(
              colors: colors,
              progress: progress,
              onDismiss: _dismiss,
            ),
    );
  }
}

/// The default, in-progress mode: header + progress bar + per-step checklist.
class _ChecklistBody extends StatelessWidget {
  const _ChecklistBody({
    required this.colors,
    required this.progress,
    required this.onDismiss,
  });

  final NightshadeColors colors;
  final CoachProgress progress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final steps = progress.steps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(colors: colors, onDismiss: onDismiss),
        const SizedBox(height: NightshadeTokens.spaceLg),
        NightshadeProgressBar(
          value: progress.totalCount == 0
              ? 0
              : progress.completeCount / progress.totalCount,
          style: NightshadeProgressStyle.thin,
          state: progress.allComplete
              ? NightshadeProgressState.success
              : NightshadeProgressState.normal,
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          '${progress.completeCount} of ${progress.totalCount} complete',
          style: NightshadeTypography.caption.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        for (var i = 0; i < steps.length; i++) ...[
          _CoachStepRow(colors: colors, progress: steps[i]),
          if (i != steps.length - 1)
            Divider(
              height: NightshadeTokens.spaceLg,
              thickness: 1,
              color:
                  colors.border.withValues(alpha: NightshadeTokens.opacityHalf),
            ),
        ],
      ],
    );
  }
}

/// The coach's header: branded icon chip, title, and the dismiss control.
class _Header extends StatelessWidget {
  const _Header({required this.colors, required this.onDismiss});

  final NightshadeColors colors;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: NightshadeTokens.iconXl,
          height: NightshadeTokens.iconXl,
          alignment: Alignment.center,
          decoration: NightshadeDecorations.iconChip(colors.primary),
          child: Icon(
            LucideIcons.sparkles,
            size: NightshadeTokens.iconMd,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Text(
            'Get set up for first light',
            style:
                NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        IconButton(
          icon: const Icon(LucideIcons.x),
          iconSize: NightshadeTokens.iconMd,
          color: colors.textMuted,
          tooltip: 'Dismiss — reopen from Settings → Help',
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

/// A single checklist row: status indicator, item icon, title + why-it-matters,
/// and (while outstanding) a "Do it now" deep-link button.
///
/// Visual structure deliberately tracks `ReadinessPanel`'s `_ReadinessRow` so
/// the coach and the readiness checklist read as one family.
class _CoachStepRow extends StatelessWidget {
  const _CoachStepRow({required this.colors, required this.progress});

  final NightshadeColors colors;
  final CoachStepProgress progress;

  @override
  Widget build(BuildContext context) {
    final step = progress.step;
    final complete = progress.isComplete;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Optically align the leading indicator with the first text line.
          padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs + 1),
          child: complete
              ? Icon(
                  LucideIcons.checkCircle2,
                  size: NightshadeTokens.iconSm,
                  color: colors.success,
                )
              : StatusDot(
                  color: readinessLevelColor(progress.level, colors),
                  variant: progress.level == ReadinessLevel.blocked
                      ? StatusDotVariant.urgent
                      : StatusDotVariant.static,
                ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    readinessItemIcon(step.id),
                    size: NightshadeTokens.iconSm,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      step.title,
                      style: NightshadeTypography.bodyMedium.copyWith(
                        // A completed step recedes to muted text — the
                        // "struck-through" look without literal strikethrough,
                        // matching the codebase's quiet-done convention.
                        color:
                            complete ? colors.textMuted : colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              // Hide the rationale once the step is done to keep the finished
              // checklist compact; an outstanding step keeps its "why".
              if (!complete) ...[
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  step.whyItMatters,
                  style: NightshadeTypography.caption
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (!complete) ...[
          const SizedBox(width: NightshadeTokens.spaceMd),
          NightshadeButton(
            label: step.actionLabel,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => context.go(step.deepLinkRoute),
          ),
        ],
      ],
    );
  }
}

/// The terminal celebration mode, shown once every step is complete.
///
/// Mirrors the onboarding wizard's "you're all set" summary panel — a success
/// rocket icon chip, a congratulatory line, and a single primary action — so
/// the two finish surfaces share one visual vocabulary.
class _CelebrationBody extends StatelessWidget {
  const _CelebrationBody({
    required this.colors,
    required this.onCaptureFirstLight,
  });

  final NightshadeColors colors;
  final VoidCallback onCaptureFirstLight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: NightshadeTokens.iconXl,
              height: NightshadeTokens.iconXl,
              alignment: Alignment.center,
              decoration: NightshadeDecorations.iconChip(colors.success),
              child: Icon(
                LucideIcons.rocket,
                size: NightshadeTokens.iconMd,
                color: colors.success,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Text(
                "You're ready for first light",
                style:
                    NightshadeTypography.h5.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Text(
          'Every setup step is done — your rig is configured and ready to '
          'capture. Point at a target and take the shot.',
          style: NightshadeTypography.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        Align(
          alignment: Alignment.centerLeft,
          child: NightshadeButton(
            label: 'Capture first light',
            icon: LucideIcons.aperture,
            onPressed: onCaptureFirstLight,
          ),
        ),
      ],
    );
  }
}
