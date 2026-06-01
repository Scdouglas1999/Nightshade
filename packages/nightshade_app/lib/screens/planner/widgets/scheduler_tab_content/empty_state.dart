part of '../scheduler_tab_content.dart';

class _NoTargetsEmptyState extends StatefulWidget {
  /// True when the scheduler has not yet produced any decision (Start
  /// has not been pressed); false when a decision exists but the scored
  /// list is empty (no candidates in the database).
  final bool awaitingFirstEval;

  const _NoTargetsEmptyState({required this.awaitingFirstEval});

  @override
  State<_NoTargetsEmptyState> createState() => _NoTargetsEmptyStateState();
}

class _NoTargetsEmptyStateState extends State<_NoTargetsEmptyState> {
  bool _learnMoreExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final headline =
        widget.awaitingFirstEval ? 'No decision yet' : 'No targets to schedule';
    final body = widget.awaitingFirstEval
        ? 'The scheduler has not evaluated any targets yet. Press Start '
            'in the panel on the left, or tap Re-evaluate to compute an '
            'initial decision against the current target catalog.'
        : 'The scheduler needs targets with integration goals. Add a '
            'target to your catalog, then set how many frames you want '
            'in each filter.';

    return Padding(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.target,
                  size: NightshadeTokens.iconMd, color: colors.textMuted),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                label: 'Open target catalog',
                icon: LucideIcons.listOrdered,
                size: ButtonSize.small,
                onPressed: () => context.go('/planner'),
              ),
              NightshadeButton(
                label: _learnMoreExpanded ? 'Hide details' : 'Learn more',
                icon: _learnMoreExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: ButtonSize.small,
                variant: ButtonVariant.ghost,
                onPressed: () =>
                    setState(() => _learnMoreExpanded = !_learnMoreExpanded),
              ),
            ],
          ),
          if (_learnMoreExpanded) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Container(
              width: double.infinity,
              padding: NightshadeTokens.paddingMd,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How the scheduler picks targets',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every 60 seconds the engine scores every target in '
                    'your catalog. The score is a weighted blend of how '
                    'high the target sits above the horizon, how far it '
                    'is from the meridian, its angular separation from '
                    'the moon (weighted by moon illumination), and how '
                    'much time tonight still works for it. Targets that '
                    'still need integration in some filter score higher '
                    'than fully-imaged ones. Switching between targets '
                    'is gated by a hysteresis ratio so the scheduler '
                    'does not flip-flop between two close scores.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
