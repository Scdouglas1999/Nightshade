import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/plan_tonight_sequencer_helper.dart';
import 'one_tap_target_provider.dart';
import 'one_tap_tonight_controller.dart';

/// The opinionated one-tap "image this target tonight" screen.
///
/// One screen, one decision, one primary action. It picks tonight's best
/// target (the same pick the autopilot would slew to), shows a single confirm
/// card, and a GO button that chains auto-frame → Smart Night plan → start the
/// unattended run. The morning report is surfaced as the payoff.
///
/// This does NOT replace the deep planner/sequencer — an "Advanced" link keeps
/// the full toolset one tap away.
class TonightScreen extends ConsumerStatefulWidget {
  const TonightScreen({super.key});

  @override
  ConsumerState<TonightScreen> createState() => _TonightScreenState();
}

class _TonightScreenState extends ConsumerState<TonightScreen> {
  OneTapTonightController? _controller;

  /// Build the live controller lazily once `ref` is usable. The seams are
  /// wired to the real providers/helpers here, where a [WidgetRef] is in hand.
  OneTapTonightController _liveController() {
    return _controller ??= OneTapTonightController(
      pick: () => ref.read(oneTapTargetProvider.future),
      frame: (target) =>
          ref.read(framingProvider.notifier).setTargetSuggestion(target),
      plan: (target) => buildPlanTonightTargetSequenceFromSuggestion(
        ref: ref,
        target: target,
      ),
      run: (plan) async {
        ref.read(currentSequenceProvider.notifier).loadSequence(
              plan.sequence,
              discardUnsaved: true,
            );
        await ref.read(sequenceExecutorProvider).start();
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final controller = _liveController();
    final targetAsync = ref.watch(oneTapTargetProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return TonightBodyView(
              colors: colors,
              state: controller.state,
              targetAsync: targetAsync,
              onGo: controller.go,
              onReset: controller.reset,
              onRefreshPick: () => ref.invalidate(oneTapTargetProvider),
            );
          },
        ),
      ),
    );
  }
}

/// Stateless body so a golden test (and any future seeded preview) can drive
/// it with a seeded [OneTapTonightState] + [AsyncValue] without spinning up the
/// live providers, framing assistant, or executor.
class TonightBodyView extends StatelessWidget {
  final NightshadeColors colors;
  final OneTapTonightState state;
  final AsyncValue<TargetSuggestion?> targetAsync;
  final Future<void> Function() onGo;
  final VoidCallback onReset;
  final VoidCallback onRefreshPick;

  const TonightBodyView({
    super.key,
    required this.colors,
    required this.state,
    required this.targetAsync,
    required this.onGo,
    required this.onReset,
    required this.onRefreshPick,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      children: [
        _Header(colors: colors),
        const SizedBox(height: NightshadeTokens.spaceLg),
        _TargetConfirmCard(
          colors: colors,
          state: state,
          targetAsync: targetAsync,
          onRefreshPick: onRefreshPick,
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        _PrimaryAction(
          colors: colors,
          state: state,
          targetAsync: targetAsync,
          onGo: onGo,
          onReset: onReset,
        ),
        if (state.error != null) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          _ErrorBanner(colors: colors, message: state.error!),
        ],
        const SizedBox(height: NightshadeTokens.spaceXl),
        _MorningPayoff(colors: colors, running: state.phase == OneTapPhase.running),
        const SizedBox(height: NightshadeTokens.spaceLg),
        _AdvancedFooter(colors: colors),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final NightshadeColors colors;
  const _Header({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.moonStar, size: 22, color: colors.primary),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Tonight',
              style: NightshadeTypography.h2.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'One tap and Nightshade frames, plans, and runs the best target for '
          'you. Wake up to a finished master.',
          style: NightshadeTypography.bodySm
              .copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// The single confirm card: which target the chain will image, and why.
class _TargetConfirmCard extends StatelessWidget {
  final NightshadeColors colors;
  final OneTapTonightState state;
  final AsyncValue<TargetSuggestion?> targetAsync;
  final VoidCallback onRefreshPick;

  const _TargetConfirmCard({
    required this.colors,
    required this.state,
    required this.targetAsync,
    required this.onRefreshPick,
  });

  @override
  Widget build(BuildContext context) {
    // Once the chain is running it owns the headline target; before that the
    // confirm card mirrors the live pick provider.
    final running = state.target;
    if (running != null && state.phase != OneTapPhase.idle) {
      return _cardForTarget(running);
    }
    return targetAsync.when(
      loading: () => _SkeletonCard(colors: colors),
      error: (e, _) => _NoTargetCard(
        colors: colors,
        title: 'Could not pick a target',
        body: '$e',
        onRetry: onRefreshPick,
      ),
      data: (target) {
        if (target == null) {
          return _NoTargetCard(
            colors: colors,
            title: 'Nothing imageable right now',
            body: 'The sky may be below your horizon or your location is not '
                'set. Check Settings, then refresh.',
            onRetry: onRefreshPick,
          );
        }
        return _cardForTarget(target);
      },
    );
  }

  Widget _cardForTarget(TargetSuggestion target) {
    final peakAlt =
        target.visibility.peakAltitude ?? target.visibility.currentAltitude;
    final hoursAbove = target.visibility.hoursAboveMinAlt ?? 0.0;
    final ra = CoordinateUtils.formatRA(target.raHours);
    final dec = CoordinateUtils.formatDec(target.decDegrees);

    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radar, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                "TONIGHT'S PICK",
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            target.targetName,
            style:
                NightshadeTypography.h3.copyWith(color: colors.textPrimary),
          ),
          if (target.objectType != null) ...[
            const SizedBox(height: 2),
            Text(
              target.objectType!,
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              _StatChip(
                colors: colors,
                icon: LucideIcons.arrowUpRight,
                label: 'Peak alt',
                value: '${peakAlt.toStringAsFixed(0)}°',
              ),
              _StatChip(
                colors: colors,
                icon: LucideIcons.clock,
                label: 'Hours up',
                value: '${hoursAbove.toStringAsFixed(1)} h',
              ),
              _StatChip(
                colors: colors,
                icon: LucideIcons.crosshair,
                label: 'RA / Dec',
                value: '$ra  $dec',
              ),
            ],
          ),
          if (target.reasoning.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Text(
              target.reasoning,
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            '$label ',
            style: NightshadeTypography.caption
                .copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: NightshadeTypography.caption.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The single primary action. One button. Its label narrates the active
/// phase so progress is legible without a second control.
class _PrimaryAction extends StatelessWidget {
  final NightshadeColors colors;
  final OneTapTonightState state;
  final AsyncValue<TargetSuggestion?> targetAsync;
  final Future<void> Function() onGo;
  final VoidCallback onReset;

  const _PrimaryAction({
    required this.colors,
    required this.state,
    required this.targetAsync,
    required this.onGo,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final hasPick = targetAsync.valueOrNull != null || state.target != null;

    if (state.phase == OneTapPhase.running) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.checkCircle2, size: 18, color: colors.success),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Running tonight',
                style: NightshadeTypography.bodyMedium.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'Open imaging',
            icon: LucideIcons.camera,
            variant: ButtonVariant.outline,
            size: ButtonSize.large,
            onPressed: () => context.goNamed('imaging'),
          ),
        ],
      );
    }

    if (state.phase == OneTapPhase.failed) {
      return NightshadeButton(
        label: 'Try again',
        icon: LucideIcons.refreshCw,
        variant: ButtonVariant.primary,
        size: ButtonSize.large,
        onPressed: () {
          onReset();
          onGo();
        },
      );
    }

    return NightshadeButton(
      label: _label(state.phase),
      icon: state.isBusy ? null : LucideIcons.play,
      variant: ButtonVariant.primary,
      size: ButtonSize.large,
      isLoading: state.isBusy,
      onPressed: (hasPick && !state.isBusy) ? onGo : null,
    );
  }

  String _label(OneTapPhase phase) {
    switch (phase) {
      case OneTapPhase.picking:
        return 'Choosing target…';
      case OneTapPhase.framing:
        return 'Framing…';
      case OneTapPhase.planning:
        return 'Planning the night…';
      case OneTapPhase.starting:
        return 'Starting run…';
      case OneTapPhase.idle:
      case OneTapPhase.running:
      case OneTapPhase.failed:
        return 'Image this target tonight';
    }
  }
}

/// The morning payoff: a path to the morning report / session review.
class _MorningPayoff extends StatelessWidget {
  final NightshadeColors colors;
  final bool running;

  const _MorningPayoff({required this.colors, required this.running});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.subtle,
      onTap: () => context.go('/session-review'),
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Row(
        children: [
          Icon(LucideIcons.sunrise, size: 20, color: colors.warning),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Morning report',
                  style: NightshadeTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? "When the night wraps, your graded master and a full "
                          'briefing land here.'
                      : 'Last night graded, stacked, and explained — see your '
                          'best frames and what to improve.',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: colors.textSecondary),
        ],
      ),
    );
  }
}

/// Keeps the deep planner/sequencer one tap away (never replaced).
class _AdvancedFooter extends StatelessWidget {
  final NightshadeColors colors;
  const _AdvancedFooter({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: () => context.go('/planner'),
          icon: Icon(LucideIcons.sliders, size: 15, color: colors.textSecondary),
          label: Text(
            'Advanced: full planner & sequencer',
            style: NightshadeTypography.bodySm
                .copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final NightshadeColors colors;
  final String message;

  const _ErrorBanner({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertCircle, size: 16, color: colors.error),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              message,
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoTargetCard extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String body;
  final VoidCallback onRetry;

  const _NoTargetCard({
    required this.colors,
    required this.title,
    required this.body,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.standard,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cloudOff, size: 16, color: colors.warning),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: NightshadeTypography.bodyMedium
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            body,
            style: NightshadeTypography.bodySm
                .copyWith(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeButton(
            label: 'Refresh',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final NightshadeColors colors;
  const _SkeletonCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(width: 110, height: 10),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _bar(width: 180, height: 20),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _bar(width: double.infinity, height: 14),
        ],
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      ),
    );
  }
}
