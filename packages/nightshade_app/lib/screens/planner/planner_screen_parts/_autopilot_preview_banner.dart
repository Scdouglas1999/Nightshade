// Part of ../planner_screen.dart -- extracted for maintainability.
//
// The authoritative "what the autopilot will run tonight" banner. This is a
// READ-ONLY preview of the live SchedulerEngine's decision: it renders the
// exact target the dynamic scheduler would slew to right now (same scorer,
// same hard gates, same hysteresis), so the human's headline pick IS the
// rig's pick. It does NOT dispatch, park, or mutate engine state.
//
// The suggestion-based primary card below it is the whole-night OUTLOOK
// supplement (peak altitude / transit / imaging-window hours), not a
// competing #1 ranker — see the architecture-unification plan, subsystem 1.
part of '../planner_screen.dart';

class _AutopilotPreviewBanner extends ConsumerWidget {
  final NightshadeColors colors;

  const _AutopilotPreviewBanner({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync = ref.watch(schedulerPreviewDecisionProvider);

    return previewAsync.when(
      // While the first preview computes, render nothing rather than a
      // flash of skeleton — the suggestion card below already fills the view.
      loading: () => const SizedBox.shrink(),
      // A preview failure must be loud, not silently hidden: surface a compact
      // error chip with a retry rather than pretending the autopilot has no
      // opinion (a silent fallback would hide a real scoring/loader bug).
      error: (error, _) => _buildError(context, ref),
      data: (decision) => _buildBanner(context, decision),
    );
  }

  Widget _buildBanner(BuildContext context, SchedulerDecision decision) {
    final hasPick = decision.chosenTargetId != null;
    final accent = hasPick ? colors.primary : colors.warning;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceLg),
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radar, size: 16, color: accent),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'AUTOPILOT WILL RUN',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            hasPick
                ? decision.chosenTargetName ??
                    'Target ${decision.chosenTargetId}'
                : 'Nothing eligible right now',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            hasPick
                ? 'Live scheduler pick — what the rig would slew to next '
                    '(score ${decision.score.toStringAsFixed(2)}).'
                : 'The dynamic scheduler has no eligible target at this instant. '
                    'The outlook below shows what becomes available tonight.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (hasPick && decision.reasoning.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              decision.reasoning.first,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeButton(
            label: 'Open Target Queue',
            icon: LucideIcons.listOrdered,
            variant: ButtonVariant.outline,
            onPressed: () => context.go('/planner?tab=scheduler'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceLg),
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 16, color: colors.error),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              // Keep the user-facing copy clean; the raw exception is for
              // logs, not the banner. A dumped `$error` here reads as a crash
              // and is inconsistent with the planner's other error states.
              'Autopilot preview unavailable. Tap Retry to recompute the live '
              'scheduler pick.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(schedulerPreviewDecisionProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Small header that re-frames the suggestion-based primary card below the
/// autopilot banner as the whole-night OUTLOOK supplement (peak altitude /
/// transit / imaging-window hours), not a competing authoritative pick.
class _OutlookSectionLabel extends StatelessWidget {
  final NightshadeColors colors;

  const _OutlookSectionLabel({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.moonStar, size: 14, color: colors.textSecondary),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'NIGHT OUTLOOK',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            'best for the whole night — peak altitude, transit & window hours',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
