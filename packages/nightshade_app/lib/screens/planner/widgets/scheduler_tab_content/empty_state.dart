part of '../scheduler_tab_content.dart';

/// Why the queue came back empty.
///
/// The scheduler's candidate query is project-scoped (an INNER JOIN against
/// `project_targets` whenever a project is active), so an empty queue has
/// several genuinely different causes and only one of them is "you have not
/// added targets yet". Telling every operator to go add catalog targets and
/// integration goals sends the ones who already did that to redo work they
/// have done, and hides the real cause — an active project with no members.
enum _EmptyQueueCause {
  /// The engine has produced no decision yet (Start / Re-evaluate not pressed).
  awaitingFirstEval,

  /// A project is active and has no member targets, so the project-scoped
  /// candidate query can never return a row.
  activeProjectEmpty,

  /// The target catalog itself is empty.
  catalogEmpty,

  /// Targets exist in scope but none of them carries an integration goal.
  noIntegrationGoals,

  /// Everything above looks populated (or is still loading). Say only what is
  /// actually known rather than naming a cause we have not established.
  unknown,
}

class _NoTargetsEmptyState extends ConsumerStatefulWidget {
  /// True when the scheduler has not yet produced any decision (Start
  /// has not been pressed); false when a decision exists but the scored
  /// list is empty (no candidates in the database).
  final bool awaitingFirstEval;

  const _NoTargetsEmptyState({required this.awaitingFirstEval});

  @override
  ConsumerState<_NoTargetsEmptyState> createState() =>
      _NoTargetsEmptyStateState();
}

class _NoTargetsEmptyStateState extends ConsumerState<_NoTargetsEmptyState> {
  bool _learnMoreExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // The same three inputs the candidate loader reads, so the diagnosis names
    // the condition that actually produced the empty queue instead of guessing.
    final activeProjectId = ref.watch(activeProjectIdProvider);
    final activeProject = ref.watch(activeProjectProgressProvider).valueOrNull;
    final catalogCount = ref.watch(allDbTargetsProvider).valueOrNull?.length;
    final goals = ref.watch(integrationGoalsStreamProvider).valueOrNull;

    final cause = _diagnose(
      activeProjectId: activeProjectId,
      activeProject: activeProject,
      catalogCount: catalogCount,
      goals: goals,
    );
    final projectName = activeProject?.project.name ?? 'the active project';

    final String headline;
    final String body;
    switch (cause) {
      case _EmptyQueueCause.awaitingFirstEval:
        headline = 'No decision yet';
        body = 'The scheduler has not evaluated any targets yet. Press Start '
            'in the panel on the left, or tap Re-evaluate to compute an '
            'initial decision against the current target catalog.';
      case _EmptyQueueCause.activeProjectEmpty:
        headline = 'Project "$projectName" has no targets';
        body = 'The scheduler only considers targets that belong to the '
            'active project, and $projectName is empty. Add targets to it, '
            'or clear the active project to schedule from the whole catalog.';
      case _EmptyQueueCause.catalogEmpty:
        headline = 'No targets in your catalog';
        body = 'Add a target to your catalog, then set how many frames you '
            'want in each filter.';
      case _EmptyQueueCause.noIntegrationGoals:
        headline = 'No integration goals set';
        body = activeProjectId == null
            ? 'Your catalog has targets, but none of them says how much data '
                'it still needs. Open a target and set how many frames you '
                'want in each filter.'
            : 'The targets in $projectName have no integration goals. Open a '
                'target and set how many frames you want in each filter.';
      case _EmptyQueueCause.unknown:
        headline = 'No targets to schedule';
        body = 'The last evaluation produced no candidate targets. '
            'Re-evaluate, or open the target catalog to check that the '
            'targets in scope still need data.';
    }

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
                        fontSize: NightshadeTypography.fontSize14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
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
                label: cause == _EmptyQueueCause.activeProjectEmpty
                    ? 'Open project'
                    : 'Open target catalog',
                icon: LucideIcons.listOrdered,
                size: ButtonSize.small,
                // The add-target / integration-goals surface is the Projects
                // tab, not the default (Recommendation) landing page that a
                // bare `/planner` resolves to.
                onPressed: () => context.go('/planner?tab=projects'),
              ),
              // Only offered for the one cause it actually resolves: dropping
              // the project scope makes the whole catalog eligible again.
              if (cause == _EmptyQueueCause.activeProjectEmpty)
                NightshadeButton(
                  key: const ValueKey('scheduler-clear-active-project'),
                  label: 'Schedule whole catalog',
                  icon: LucideIcons.globe,
                  size: ButtonSize.small,
                  variant: ButtonVariant.outline,
                  onPressed: () => unawaited(
                    ref
                        .read(activeProjectIdProvider.notifier)
                        .setActiveProject(null),
                  ),
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
            SizedBox(
              width: double.infinity,
              child: NightshadeCard(
                padding: NightshadeTokens.paddingMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How the scheduler picks targets',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Every 60 seconds the engine scores every target in '
                      'scope — the active project\'s members when a project '
                      'is active, otherwise your whole catalog. The score is '
                      'a weighted blend of how high the target sits above the '
                      'horizon, how far it is from the meridian, its angular '
                      'separation from the moon (weighted by moon '
                      'illumination), and how much time tonight still works '
                      'for it. Targets that still need integration in some '
                      'filter score higher than fully-imaged ones. Switching '
                      'between targets is gated by a hysteresis ratio so the '
                      'scheduler does not flip-flop between two close scores.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _EmptyQueueCause _diagnose({
    required int? activeProjectId,
    required CampaignProgress? activeProject,
    required int? catalogCount,
    required List<IntegrationGoal>? goals,
  }) {
    if (widget.awaitingFirstEval) return _EmptyQueueCause.awaitingFirstEval;

    // Project scope is checked first: it is the only cause that can hide a
    // fully-populated catalog, and it is the one the old copy never named.
    if (activeProjectId != null &&
        activeProject != null &&
        activeProject.project.id == activeProjectId &&
        activeProject.totalTargets == 0) {
      return _EmptyQueueCause.activeProjectEmpty;
    }
    if (catalogCount != null && catalogCount == 0) {
      return _EmptyQueueCause.catalogEmpty;
    }
    if (goals != null) {
      // Goals only count when they belong to a target the scheduler can see,
      // so a goal on an out-of-project target does not mask the real cause.
      final inScope = activeProjectId == null || activeProject == null
          ? goals
          : goals.where((g) {
              return activeProject.targets.any((t) => t.targetId == g.targetId);
            });
      if (inScope.isEmpty) return _EmptyQueueCause.noIntegrationGoals;
    }
    return _EmptyQueueCause.unknown;
  }
}
