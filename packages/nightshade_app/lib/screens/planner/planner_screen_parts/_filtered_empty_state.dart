// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Empty-state card shown when filters strip every candidate; ranks which filters caused the most exclusions and offers a one-tap reset.
part of '../planner_screen.dart';

// ============================================================================
// Empty state (filters applied) — explains which filter excluded the most
// ============================================================================

class _FilteredEmptyState extends ConsumerWidget {
  final NightshadeColors colors;

  const _FilteredEmptyState({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(plannerFilterExclusionProvider);
    final ranked = breakdown.excludedByFilter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SizedBox(
      width: double.infinity,
      child: NightshadeCard(
        variant: CardVariant.subtle,
        borderRadius: NightshadeTokens.radiusLg,
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.filterX,
                  size: NightshadeTokens.iconLg, color: colors.warning),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  breakdown.total == 0
                      ? 'No targets available'
                      : 'No targets match these filters',
                  style: NightshadeTypography.h4.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (breakdown.total == 0) ...[
            // Why: when the suggestion pool is fully empty, the dominant
            // real-world cause is "the OpenNGC catalog hasn't been
            // downloaded yet" — not "your filters/altitude/twilight are
            // wrong." Detect that case and surface the actual fix.
            Builder(builder: (ctx) {
              final catalogState = ref.watch(catalogStateProvider);
              final catalogReady = catalogState.dsoCatalogStatus.isInstalled;
              if (!catalogReady) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The OpenNGC catalog is not installed. Without it, the planner can only score targets you have already saved to your library.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: NightshadeTokens.spaceMd),
                    NightshadeButton(
                      label: 'Open catalog settings',
                      onPressed: () => context.go('/settings/plate-solving'),
                      icon: LucideIcons.download,
                      size: ButtonSize.small,
                    ),
                  ],
                );
              }
              return Text(
                'The scoring engine returned zero candidates for tonight. Verify your location, twilight window, and your minimum altitude/score in suggestion config.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              );
            }),
          ] else ...[
            Text(
              '${breakdown.total} candidate${breakdown.total == 1 ? '' : 's'} were scored, '
              '${breakdown.passed} passed the filters.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            if (ranked.isNotEmpty) ...[
              Text(
                'Filters with the largest impact:',
                style: NightshadeTypography.h6.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              for (final entry in ranked.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.minusCircle,
                          size: 12, color: colors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '−${entry.value}',
                        style: NightshadeTypography.h6.copyWith(
                          color: colors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: NightshadeTokens.spaceLg),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: 'Reset filters',
              icon: LucideIcons.rotateCcw,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () {
                ref.read(suggestionFilterProvider.notifier).state =
                    const SuggestionFilterState();
                ref.read(_plannerVisibleCountProvider.notifier).state =
                    _kPlannerPageSize;
              },
            ),
          ),
        ],
        ),
      ),
    );
  }
}
