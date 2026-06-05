import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../utils/plan_tonight_sequencer_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../../sequencer/widgets/smart_night_dialog.dart';
import 'glass_card.dart';

final _tonightOptimizationPlanProvider =
    FutureProvider.autoDispose<SessionOptimizationPlan>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  if ((settings.latitude == 0.0 && settings.longitude == 0.0)) {
    return SessionOptimizationPlan(
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      primaryTarget: null,
      alternates: [],
      recommendedExposureSeconds: 0,
      estimatedUsableHours: 0,
      rationale: ['Set an observing location to generate target plans.'],
      riskFactors: [],
    );
  }

  final suggestions = await ref.watch(tonightSuggestionsProvider.future);
  final exposureContext = suggestions.isEmpty
      ? null
      : await ref.watch(smartNightExposureContextProvider.future);
  final optimizer = SessionOptimizerService(
    suggestionService: ref.watch(targetSuggestionServiceProvider),
  );

  return optimizer.buildPlanFromSuggestions(
    suggestions,
    generatedAt: DateTime.now(),
    exposureContext: exposureContext,
  );
});

class TonightCard extends ConsumerWidget {
  final NightshadeColors colors;

  const TonightCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moonInfo = ref.watch(moonInfoProvider);
    final optimization =
        ref.watch(_tonightOptimizationPlanProvider).valueOrNull;

    // Use select() to only watch the time field
    final now = ref.watch(observationTimeProvider.select((s) => s.time));

    // Format astro twilight time
    String astroTwilightTime = '--:--';
    if (twilight.astronomicalDusk != null) {
      final dusk = twilight.astronomicalDusk!;
      // If dusk is in the future (relative to simulation time), show it
      if (dusk.isAfter(now)) {
        astroTwilightTime =
            '${dusk.hour.toString().padLeft(2, '0')}:${dusk.minute.toString().padLeft(2, '0')}';
      } else {
        // Dusk already passed, show dawn
        if (twilight.astronomicalDawn != null) {
          final dawn = twilight.astronomicalDawn!;
          astroTwilightTime =
              '${dawn.hour.toString().padLeft(2, '0')}:${dawn.minute.toString().padLeft(2, '0')}';
        }
      }
    }

    // Format moon info - compact version without moonrise time
    final moonValue = '${moonInfo.illumination.toStringAsFixed(0)}%';

    // Calculate imaging window (darkness duration)
    String imagingWindow = '--:--';
    if (twilight.astronomicalDusk != null &&
        twilight.astronomicalDawn != null) {
      final duration =
          twilight.astronomicalDawn!.difference(twilight.astronomicalDusk!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      imagingWindow = '${hours}h ${minutes}m';
    }

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.moon,
            title: 'Tonight',
            accent: colors.warning,
          ),
          const SizedBox(height: DashboardCardStyle.headerGap),
          _TonightRow(
            icon: LucideIcons.sunset,
            label: 'Twilight',
            value: astroTwilightTime,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.moonStar,
            label: 'Moon',
            value: moonValue,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.timer,
            label: 'Window',
            value: imagingWindow,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.target,
            label: 'Target',
            value: optimization?.primaryTarget?.targetName ?? 'Planning...',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.camera,
            label: 'Exposure',
            value: optimization == null || !optimization.hasRecommendation
                ? '--'
                : '${optimization.recommendedExposureSeconds.toStringAsFixed(0)}s',
            colors: colors,
          ),
          if (optimization != null && optimization.hasRecommendation) ...[
            const SizedBox(height: 6),
            _TonightRow(
              icon: LucideIcons.aperture,
              label: 'Filters',
              value: _formatRecommendedFilters(optimization),
              colors: colors,
            ),
          ],
          if (optimization != null && optimization.rationale.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              optimization.rationale.first,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (optimization != null && optimization.alternates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '+ ${optimization.alternates.length} more target${optimization.alternates.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ],
          if (optimization != null && optimization.hasRecommendation) ...[
            const SizedBox(height: 10),
            _TonightTargetActions(
              colors: colors,
              target: optimization.primaryTarget!,
              onSendToFraming: () => _sendPrimaryToFraming(
                  context, ref, optimization.primaryTarget!),
              onAddToSequencer: () => _addPrimaryToSequencer(
                context,
                ref,
                optimization.primaryTarget!,
                optimization,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => context.go('/planner'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See Full Plan',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          fontWeight: FontWeight.w500,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _SmartNightTonightAction(colors: colors),
        ],
      ),
    );
  }

  void _sendPrimaryToFraming(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion target,
  ) {
    ref.read(framingProvider.notifier).setTargetSuggestion(target);
    context.goNamed('framing');
  }

  Future<void> _addPrimaryToSequencer(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion target,
    SessionOptimizationPlan plan,
  ) async {
    try {
      final built = await buildPlanTonightTargetSequence(
        ref: ref,
        target: target,
        plan: plan,
      );
      if (!context.mounted) return;
      final added = await loadPlanTonightSequenceIntoEditor(
        context: context,
        ref: ref,
        result: built,
        replaceSequence: false,
      );

      if (added && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Added ${target.targetName} to sequence '
              '(${planTonightSequenceSummary(built)})',
            ),
          ),
        );
      }
    } on SmartNightBuildException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }
}

class _SmartNightTonightAction extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _SmartNightTonightAction({required this.colors});

  @override
  ConsumerState<_SmartNightTonightAction> createState() =>
      _SmartNightTonightActionState();
}

class _SmartNightTonightActionState
    extends ConsumerState<_SmartNightTonightAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(activeEquipmentProfileProvider);
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final locked = _sequenceIsActive(executionState);
    final lookup = profile == null
        ? null
        : SmartNightDraftLookup(
            profileId: profile.id?.toString() ?? profile.name,
            astronomicalDay: _astronomicalDay(DateTime.now()),
          );
    final draftAsync = lookup == null
        ? const AsyncValue<SmartNightDraft?>.data(null)
        : ref.watch(pendingSmartNightDraftProvider(lookup));
    final draft = draftAsync.valueOrNull;
    final label = locked
        ? 'Sequence running'
        : draft == null
            ? 'Plan tonight'
            : 'View tonight\'s plan';
    final icon = locked
        ? LucideIcons.lock
        : draft == null
            ? LucideIcons.sparkles
            : LucideIcons.fileClock;

    return Align(
      alignment: Alignment.centerRight,
      child: NightshadeButton(
        label: label,
        icon: icon,
        variant: ButtonVariant.primary,
        size: ButtonSize.small,
        isLoading: _busy,
        onPressed: locked || _busy
            ? null
            : draft == null
                ? () => _openPlanner(lookup)
                : () => _loadDraft(draft),
      ),
    );
  }

  Future<void> _openPlanner(SmartNightDraftLookup? lookup) async {
    setState(() => _busy = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => const SmartNightDialog(),
      );
      if (lookup != null) {
        ref.invalidate(pendingSmartNightDraftProvider(lookup));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDraft(SmartNightDraft draft) async {
    setState(() => _busy = true);
    try {
      ref
          .read(currentSequenceProvider.notifier)
          .loadSequence(draft.plan.sequence, discardUnsaved: true);
      if (!mounted) return;
      context.showSuccessSnackBar(
        'Smart Night plan loaded - '
        '${draft.plan.plannedTargets.length} target(s), '
        '${(draft.plan.totalIntegrationSecs / 3600).toStringAsFixed(1)}h.',
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not load Smart Night plan: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

bool _sequenceIsActive(SequenceExecutionState state) {
  switch (state) {
    case SequenceExecutionState.idle:
    case SequenceExecutionState.completed:
    case SequenceExecutionState.failed:
      return false;
    case SequenceExecutionState.running:
    case SequenceExecutionState.paused:
    case SequenceExecutionState.stopping:
    case SequenceExecutionState.recovering:
      return true;
  }
}

DateTime _astronomicalDay(DateTime now) {
  final local = now.toLocal();
  final day = local.hour < 12 ? local.subtract(const Duration(days: 1)) : local;
  return DateTime.utc(day.year, day.month, day.day);
}

String _formatRecommendedFilters(SessionOptimizationPlan plan) {
  if (plan.recommendedFilterNames.isNotEmpty) {
    return plan.recommendedFilterNames.join(' · ');
  }
  if (plan.recommendedFilterName != null) {
    return plan.recommendedFilterName!;
  }
  return '--';
}

class _TonightTargetActions extends StatelessWidget {
  final NightshadeColors colors;
  final TargetSuggestion target;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToSequencer;

  const _TonightTargetActions({
    required this.colors,
    required this.target,
    required this.onSendToFraming,
    required this.onAddToSequencer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            target.catalogId ?? target.targetName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ),
        Tooltip(
          message: 'Frame target',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onSendToFraming,
            icon: Icon(LucideIcons.frame, size: 15, color: colors.primary),
          ),
        ),
        Tooltip(
          message: 'Add to sequence',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onAddToSequencer,
            icon: Icon(LucideIcons.listPlus, size: 15, color: colors.primary),
          ),
        ),
      ],
    );
  }
}

class _TonightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TonightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
