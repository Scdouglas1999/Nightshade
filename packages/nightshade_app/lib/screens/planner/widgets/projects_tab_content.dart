import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../scheduler/widgets/integration_goals_editor.dart';
import '../../sequencer/widgets/smart_night_dialog.dart';

/// Projects tab body for the multi-night planner (component C9).
///
/// Surfaces the campaign layer of the planning stack built in C6/C8:
///
///   * a project selector ([projectListProvider]) bound to
///     [activeProjectIdProvider], with create / edit / delete affordances;
///   * the active project's targets with an accrued-vs-remaining roll-up
///     ([activeProjectProgressProvider]) — a project-level bar, per-target
///     cards, and a per-filter captured/goal breakdown;
///   * an add-target flow that attaches catalog targets
///     ([allDbTargetsProvider]) to the project, and a per-target "Edit goals"
///     affordance that reuses the existing [IntegrationGoalsEditor] rather than
///     rebuilding per-filter goal UI.
///
/// All mutations route through [projectServiceProvider]; the derived providers
/// recompute off the service's change stream and the captures/goals streams, so
/// this widget never denormalizes progress.
class ProjectsTabContent extends ConsumerStatefulWidget {
  const ProjectsTabContent({super.key});

  @override
  ConsumerState<ProjectsTabContent> createState() => _ProjectsTabContentState();
}

class _ProjectsTabContentState extends ConsumerState<ProjectsTabContent> {
  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final projectsAsync = ref.watch(projectListProvider);

    return projectsAsync.when(
      loading: () => const _ProjectsSkeleton(),
      error: (err, _) => _ProjectsError(
        error: err,
        onRetry: () => ref.invalidate(projectListProvider),
      ),
      data: (projects) {
        if (projects.isEmpty) {
          return _NoProjectsState(onCreate: _openCreateDialog);
        }
        return _buildBody(
          colors: colors,
          projects: projects,
          onCreate: _openCreateDialog,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Create / edit / delete project
  // ---------------------------------------------------------------------------

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_ProjectFormResult>(
      context: context,
      builder: (_) => const _ProjectFormDialog(),
    );
    if (result == null || !mounted) return;
    final service = ref.read(projectServiceProvider);
    final newId = await service.createProject(
      name: result.name,
      description: result.description,
    );
    if (!mounted) return;
    await ref.read(activeProjectIdProvider.notifier).setActiveProject(newId);
  }

  Future<void> _openEditDialog(Project project) async {
    final result = await showDialog<_ProjectFormResult>(
      context: context,
      builder: (_) => _ProjectFormDialog(existing: project),
    );
    if (result == null || !mounted) return;
    final service = ref.read(projectServiceProvider);
    await service.updateProject(
      project.copyWith(
        name: result.name,
        description: result.description,
        clearDescription: result.description == null,
      ),
    );
  }

  Future<void> _confirmDelete(Project project) async {
    final colors = NightshadeColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: NightshadeTokens.borderRadiusMd,
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            'Delete project?',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          content: Text(
            'Deleting "${project.name}" removes the campaign and detaches its '
            'targets. Your captured frames and integration goals are kept — '
            'only the project grouping is removed.',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            NightshadeButton(
              label: 'Delete',
              icon: LucideIcons.trash2,
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final id = project.id;
    if (id == null) {
      throw StateError('Cannot delete a project with no persisted id');
    }
    final service = ref.read(projectServiceProvider);
    await service.deleteProject(id);
    if (!mounted) return;

    // If the deleted project was active, fall back to the most-recent remaining
    // project (or clear the selection when none remain) so the body never
    // points at a dangling id.
    final activeId = ref.read(activeProjectIdProvider);
    if (activeId == id) {
      final remaining = await service.listProjects();
      final next = remaining.isEmpty ? null : remaining.first.id;
      if (!mounted) return;
      await ref.read(activeProjectIdProvider.notifier).setActiveProject(next);
    }
  }

  // ---------------------------------------------------------------------------
  // Add target
  // ---------------------------------------------------------------------------

  Future<void> _openAddTargetDialog(int projectId, Set<int> attachedIds) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _AddTargetDialog(attachedTargetIds: attachedIds),
    );
    if (result == null || !mounted) return;
    final service = ref.read(projectServiceProvider);
    await service.addTarget(projectId: projectId, targetId: result);
  }

  Future<void> _removeTarget(int projectId, int targetId) async {
    final service = ref.read(projectServiceProvider);
    await service.removeTarget(projectId: projectId, targetId: targetId);
  }

  // ---------------------------------------------------------------------------
  // Edit goals
  // ---------------------------------------------------------------------------

  Future<void> _openGoalsDialog(int targetId, String targetName) async {
    final profile = ref.read(activeEquipmentProfileProvider);
    final availableFilters =
        profile != null ? List<String>.from(profile.filterNames) : <String>[];
    await showDialog<void>(
      context: context,
      builder: (_) => NightshadeDialog(
        title: 'Integration goals — $targetName',
        icon: LucideIcons.target,
        width: 720,
        child: IntegrationGoalsEditor(
          targetId: targetId,
          targetName: targetName,
          availableFilters: availableFilters,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Smart Night handoff (component C11)
  // ---------------------------------------------------------------------------

  /// One-click handoff of the active project's still-incomplete targets into
  /// the Smart Night planner. Reads the active project's roll-up, pulls out the
  /// targets that still need data, and opens [SmartNightDialog] seeded with
  /// those ids so the wizard plans the campaign rather than the generic
  /// "best of everything tonight" set.
  ///
  /// Fail-loud: if the roll-up is unavailable (provider error / no active
  /// project) we surface a snackbar rather than opening an empty wizard, and if
  /// the project has no incomplete targets we tell the operator there is
  /// nothing left to plan instead of opening an unseeded dialog that would
  /// silently fall back to the generic set.
  Future<void> _planInSmartNight(Project active) async {
    final progress =
        await ref.read(activeProjectProgressProvider.future);
    if (!mounted) return;

    if (progress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a project before planning in Smart Night.'),
        ),
      );
      return;
    }

    final incompleteIds = progress.incompleteTargets
        .map((t) => t.targetId)
        .toList(growable: false);
    if (incompleteIds.isEmpty) {
      final colors = NightshadeColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${active.name}" has no incomplete targets left to '
              'plan — every target has met its integration goals.'),
          backgroundColor: colors.success,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => SmartNightDialog(
        seedTargetIds: incompleteIds,
        seedSourceLabel: active.name,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody({
    required NightshadeColors colors,
    required List<Project> projects,
    required Future<void> Function() onCreate,
  }) {
    final activeId = ref.watch(activeProjectIdProvider);
    // Resolve the active project. When the persisted id is absent or stale,
    // fall back to the first (most-recently-updated) project so the tab always
    // shows something actionable; the selector reflects that resolved choice.
    final active = projects.firstWhere(
      (p) => p.id == activeId,
      orElse: () => projects.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectHeaderBar(
          colors: colors,
          projects: projects,
          active: active,
          onSelect: (id) =>
              ref.read(activeProjectIdProvider.notifier).setActiveProject(id),
          onCreate: onCreate,
          onEdit: () => _openEditDialog(active),
          onDelete: () => _confirmDelete(active),
          onPlanInSmartNight: () => _planInSmartNight(active),
        ),
        Expanded(
          child: _ActiveProjectProgress(
            colors: colors,
            onAddTarget: _openAddTargetDialog,
            onRemoveTarget: _removeTarget,
            onEditGoals: _openGoalsDialog,
          ),
        ),
      ],
    );
  }
}

/// Result returned by [_ProjectFormDialog] on save.
class _ProjectFormResult {
  final String name;
  final String? description;
  const _ProjectFormResult({required this.name, this.description});
}

// =============================================================================
// Header bar: project selector + create / edit / delete.
// =============================================================================

class _ProjectHeaderBar extends StatelessWidget {
  final NightshadeColors colors;
  final List<Project> projects;
  final Project active;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onCreate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPlanInSmartNight;

  const _ProjectHeaderBar({
    required this.colors,
    required this.projects,
    required this.active,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onPlanInSmartNight,
  });

  @override
  Widget build(BuildContext context) {
    // Project names are not guaranteed unique, so the dropdown value space is
    // the set of decimal ids (stable, unique), with names supplied as labels.
    final ids = projects
        .map((p) => p.id)
        .whereType<int>()
        .map((id) => id.toString())
        .toList();
    final labels = projects.map((p) => p.name).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: NightshadeDropdown(
                value: active.id?.toString(),
                items: ids,
                itemLabels: labels,
                isExpanded: true,
                onChanged: (raw) {
                  if (raw == null) return;
                  final id = int.tryParse(raw);
                  if (id != null) onSelect(id);
                },
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          AccessibleIconButton(
            icon: LucideIcons.pencil,
            label: 'Edit project',
            tooltip: 'Edit project',
            size: NightshadeTokens.iconMd,
            onPressed: onEdit,
          ),
          AccessibleIconButton(
            icon: LucideIcons.trash2,
            label: 'Delete project',
            tooltip: 'Delete project',
            color: colors.error,
            size: NightshadeTokens.iconMd,
            onPressed: onDelete,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'Plan in Smart Night',
            icon: LucideIcons.sparkles,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onPlanInSmartNight,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'New Project',
            icon: LucideIcons.folderPlus,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => onCreate(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Active project progress: targets + accrued-vs-remaining roll-up.
// =============================================================================

class _ActiveProjectProgress extends ConsumerWidget {
  final NightshadeColors colors;
  final Future<void> Function(int projectId, Set<int> attachedIds) onAddTarget;
  final Future<void> Function(int projectId, int targetId) onRemoveTarget;
  final Future<void> Function(int targetId, String targetName) onEditGoals;

  const _ActiveProjectProgress({
    required this.colors,
    required this.onAddTarget,
    required this.onRemoveTarget,
    required this.onEditGoals,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(activeProjectProgressProvider);

    return progressAsync.when(
      loading: () => const _ProjectsSkeleton(),
      error: (err, _) => _ProjectsError(
        error: err,
        onRetry: () => ref.invalidate(activeProjectProgressProvider),
      ),
      data: (progress) {
        if (progress == null) {
          // No active project resolved — the header still lets the operator
          // pick one. This is a transient state during selection settling.
          return const EmptyState.compact(
            icon: LucideIcons.folderOpen,
            title: 'Select a project',
            body: 'Choose a campaign above to see its targets and progress.',
          );
        }

        final project = progress.project;
        final projectId = project.id;
        if (projectId == null) {
          throw StateError('Active project progress has a null project id');
        }

        final targets = progress.targets;
        final attachedIds = targets.map((t) => t.targetId).toSet();

        // Sort incomplete-first; within each group, least-complete first, then
        // by name for a stable order between rebuilds.
        final sorted = List<ProjectTargetProgress>.of(targets)
          ..sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }
            final c = a.percentComplete.compareTo(b.percentComplete);
            if (c != 0) return c;
            return a.targetName
                .toLowerCase()
                .compareTo(b.targetName.toLowerCase());
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectSummaryHeader(
              colors: colors,
              totalTargets: progress.totalTargets,
              completeTargets: progress.completeTargets,
              percentComplete: progress.totalPercentComplete,
              accruedSeconds: progress.totalAccruedSeconds,
              goalSeconds: progress.totalGoalSeconds,
              onAddTarget: () => onAddTarget(projectId, attachedIds),
            ),
            Expanded(
              child: targets.isEmpty
                  ? EmptyState.compact(
                      icon: LucideIcons.target,
                      title: 'No targets yet',
                      body: 'Add catalog targets to this campaign and set '
                          'per-filter integration goals to track progress.',
                      action: NightshadeButton(
                        label: 'Add Target',
                        icon: LucideIcons.plus,
                        size: ButtonSize.small,
                        onPressed: () => onAddTarget(projectId, attachedIds),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        NightshadeTokens.spaceLg,
                        NightshadeTokens.spaceSm,
                        NightshadeTokens.spaceLg,
                        NightshadeTokens.space2xl,
                      ),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: NightshadeTokens.spaceSm),
                      itemBuilder: (context, index) {
                        final t = sorted[index];
                        return _TargetProgressCard(
                          key: ValueKey('project-target-${t.targetId}'),
                          colors: colors,
                          target: t,
                          onEditGoals: () =>
                              onEditGoals(t.targetId, t.targetName),
                          onRemove: () =>
                              onRemoveTarget(projectId, t.targetId),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Project-level summary + "Add Target" action, shown above the target list.
class _ProjectSummaryHeader extends StatelessWidget {
  final NightshadeColors colors;
  final int totalTargets;
  final int completeTargets;
  final double percentComplete;
  final double accruedSeconds;
  final double goalSeconds;
  final VoidCallback onAddTarget;

  const _ProjectSummaryHeader({
    required this.colors,
    required this.totalTargets,
    required this.completeTargets,
    required this.percentComplete,
    required this.accruedSeconds,
    required this.goalSeconds,
    required this.onAddTarget,
  });

  @override
  Widget build(BuildContext context) {
    final pctFraction = percentComplete;
    final pct = (pctFraction * 100).clamp(0.0, 100.0);
    final accruedLabel = _formatHours(accruedSeconds);
    final goalLabel = _formatHours(goalSeconds);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        0,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceSm,
      ),
      child: NightshadeCard(
        padding: NightshadeTokens.cardPadding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$totalTargets target${totalTargets == 1 ? '' : 's'}',
                        style: NightshadeTypography.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (totalTargets > 0) ...[
                        const SizedBox(width: NightshadeTokens.spaceSm),
                        Text(
                          '· $completeTargets complete',
                          style: NightshadeTypography.labelSm.copyWith(
                            color: completeTargets == totalTargets &&
                                    totalTargets > 0
                                ? colors.success
                                : colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeProgressBar(
                          value: pctFraction,
                          style: NightshadeProgressStyle.thick,
                          state: pctFraction >= 1.0
                              ? NightshadeProgressState.success
                              : NightshadeProgressState.normal,
                        ),
                      ),
                      const SizedBox(width: NightshadeTokens.spaceMd),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: NightshadeTypography.telemetryMd.copyWith(
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  Text(
                    '$accruedLabel / $goalLabel integration',
                    style: NightshadeTypography.monoSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            NightshadeButton(
              label: 'Add Target',
              icon: LucideIcons.plus,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onAddTarget,
            ),
          ],
        ),
      ),
    );
  }
}

/// One per-target card with a project-level bar, accrued-vs-goal hours, percent,
/// completion indicator, and a per-filter captured/goal breakdown.
class _TargetProgressCard extends StatelessWidget {
  final NightshadeColors colors;
  final ProjectTargetProgress target;
  final VoidCallback onEditGoals;
  final VoidCallback onRemove;

  const _TargetProgressCard({
    super.key,
    required this.colors,
    required this.target,
    required this.onEditGoals,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final pctFraction = target.percentComplete;
    final pct = (pctFraction * 100).clamp(0.0, 100.0);
    final accruedLabel = _formatHours(target.accruedSeconds);
    final goalLabel = _formatHours(target.goalSeconds);
    final hasGoals = target.goalSeconds > 0.0;

    return NightshadeCard(
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.targetName,
                      style: NightshadeTypography.h5.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (!hasGoals)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: NightshadeTokens.spaceXs,
                        ),
                        child: Text(
                          'No integration goals set',
                          style: NightshadeTypography.captionSm.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (target.isComplete) ...[
                const StatusPill(
                  icon: LucideIcons.checkCircle2,
                  label: '',
                  value: 'Complete',
                  status: StatusPillStatus.success,
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
              ],
              AccessibleIconButton(
                icon: LucideIcons.sliders,
                label: 'Edit goals',
                tooltip: 'Edit goals',
                size: NightshadeTokens.iconMd,
                onPressed: onEditGoals,
              ),
              AccessibleIconButton(
                icon: LucideIcons.x,
                label: 'Remove from project',
                tooltip: 'Remove from project',
                color: colors.textMuted,
                size: NightshadeTokens.iconMd,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              Expanded(
                child: NightshadeProgressBar(
                  value: pctFraction,
                  state: target.isComplete
                      ? NightshadeProgressState.success
                      : NightshadeProgressState.normal,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.monoSm,
                ).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Text(
                '$accruedLabel / $goalLabel',
                style: NightshadeTypography.monoSm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          if (target.filters.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _FilterBreakdown(colors: colors, filters: target.filters),
          ],
        ],
      ),
    );
  }
}

/// Per-filter captured/goal frame breakdown for a target card.
class _FilterBreakdown extends StatelessWidget {
  final NightshadeColors colors;
  final List<FilterProgressLine> filters;

  const _FilterBreakdown({required this.colors, required this.filters});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: NightshadeTokens.spaceSm,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        for (final f in filters) _FilterChip(colors: colors, filter: f),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final NightshadeColors colors;
  final FilterProgressLine filter;

  const _FilterChip({required this.colors, required this.filter});

  @override
  Widget build(BuildContext context) {
    // Color the chip by completion: success when the goal is met, primary while
    // in progress. A zero-frame goal is inert (treated as in-progress).
    final complete = filter.goalFrames > 0 && filter.isComplete;
    final tint = complete ? colors.success : colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: NightshadeDecorations.tintedBadge(
        tint,
        borderRadius: NightshadeTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (complete) ...[
            Icon(
              LucideIcons.check,
              size: NightshadeTokens.iconXs,
              color: tint,
            ),
            const SizedBox(width: NightshadeTokens.spaceXs),
          ],
          Text(
            filter.filter,
            style: NightshadeTypography.labelSm.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            '${filter.capturedFrames} / ${filter.goalFrames}',
            style: NightshadeTypography.monoXs.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Create / edit project dialog.
// =============================================================================

class _ProjectFormDialog extends StatefulWidget {
  final Project? existing;

  const _ProjectFormDialog({this.existing});

  @override
  State<_ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<_ProjectFormDialog> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _descCtl;
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtl =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Project name is required');
      return;
    }
    final desc = _descCtl.text.trim();
    Navigator.of(context).pop(
      _ProjectFormResult(
        name: name,
        description: desc.isEmpty ? null : desc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeDialog(
      title: _isEdit ? 'Edit Project' : 'New Project',
      icon: _isEdit ? LucideIcons.pencil : LucideIcons.folderPlus,
      width: 480,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: _isEdit ? 'Save' : 'Create',
          icon: LucideIcons.check,
          size: ButtonSize.small,
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Group several targets into a multi-night campaign to track '
            'integration goals across clear nights.',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          NightshadeTextField(
            controller: _nameCtl,
            label: 'Name',
            hint: 'e.g. Winter Nebulae',
            prefixIcon: LucideIcons.folder,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeTextField(
            controller: _descCtl,
            label: 'Description (optional)',
            hint: 'Notes about this campaign',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Add-target dialog: searchable catalog picker.
// =============================================================================

class _AddTargetDialog extends ConsumerStatefulWidget {
  final Set<int> attachedTargetIds;

  const _AddTargetDialog({required this.attachedTargetIds});

  @override
  ConsumerState<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends ConsumerState<_AddTargetDialog> {
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final targetsAsync = ref.watch(allDbTargetsProvider);

    return NightshadeDialog(
      title: 'Add Target',
      icon: LucideIcons.plus,
      width: 560,
      height: 560,
      scrollableBody: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeTextField(
            controller: _searchCtl,
            hint: 'Search targets…',
            prefixIcon: LucideIcons.search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Expanded(
            child: targetsAsync.when(
              loading: () => Center(
                child: SizedBox(
                  width: NightshadeTokens.iconLg,
                  height: NightshadeTokens.iconLg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
              error: (err, _) => NightshadeAlert(
                severity: NightshadeAlertSeverity.error,
                title: 'Failed to load targets',
                message: err.toString(),
              ),
              data: (targets) {
                final available = targets
                    .where((t) =>
                        !widget.attachedTargetIds.contains(t.id))
                    .where((t) => _query.isEmpty ||
                        t.name.toLowerCase().contains(_query))
                    .toList()
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                if (targets.isEmpty) {
                  return const EmptyState.compact(
                    icon: LucideIcons.star,
                    title: 'No targets in the catalog',
                    body: 'Add targets to your library first, then attach '
                        'them to this campaign.',
                  );
                }
                if (available.isEmpty) {
                  return EmptyState.compact(
                    icon: LucideIcons.searchX,
                    title: 'No matching targets',
                    body: _query.isEmpty
                        ? 'Every catalog target is already in this campaign.'
                        : 'No catalog target matches "$_query".',
                  );
                }

                return ListView.separated(
                  itemCount: available.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: NightshadeTokens.spaceXs),
                  itemBuilder: (context, index) {
                    final t = available[index];
                    return _CatalogTargetTile(
                      colors: colors,
                      name: t.name,
                      onTap: () => Navigator.of(context).pop(t.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogTargetTile extends StatelessWidget {
  final NightshadeColors colors;
  final String name;
  final VoidCallback onTap;

  const _CatalogTargetTile({
    required this.colors,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: NightshadeTokens.borderRadiusSm,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceMd,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.target,
                size: NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  name,
                  style: NightshadeTypography.body.copyWith(
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                LucideIcons.plus,
                size: NightshadeTokens.iconSm,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Empty / loading / error states.
// =============================================================================

class _NoProjectsState extends StatelessWidget {
  final Future<void> Function() onCreate;

  const _NoProjectsState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.folderOpen,
      title: 'No campaigns yet',
      body: 'Create a multi-night project to track targets and integration '
          'goals across clear nights.',
      action: NightshadeButton(
        label: 'New Project',
        icon: LucideIcons.folderPlus,
        variant: ButtonVariant.primary,
        onPressed: () => onCreate(),
      ),
    );
  }
}

class _ProjectsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ProjectsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: NightshadeAlert(
            severity: NightshadeAlertSeverity.error,
            title: 'Failed to load projects',
            message: error.toString(),
            action: NightshadeButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              size: ButtonSize.small,
              onPressed: onRetry,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectsSkeleton extends StatelessWidget {
  const _ProjectsSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return ShimmerLoading(
      child: ListView.separated(
        padding: NightshadeTokens.screenPadding,
        itemCount: 4,
        separatorBuilder: (_, __) =>
            const SizedBox(height: NightshadeTokens.spaceSm),
        itemBuilder: (_, __) => Container(
          padding: NightshadeTokens.cardPadding,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: NightshadeTokens.borderRadiusLg,
            border: Border.all(color: colors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 180, height: 14),
              SizedBox(height: NightshadeTokens.spaceMd),
              SkeletonBox(height: 8),
              SizedBox(height: NightshadeTokens.spaceMd),
              Row(
                children: [
                  SkeletonBox(width: 64, height: 20),
                  SizedBox(width: NightshadeTokens.spaceSm),
                  SkeletonBox(width: 64, height: 20),
                  SizedBox(width: NightshadeTokens.spaceSm),
                  SkeletonBox(width: 64, height: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Format a duration in seconds as a compact hour label, matching the
/// progress-tab convention ('4.2h', '12h').
String _formatHours(double seconds) {
  final hours = seconds / 3600.0;
  if (hours < 0.05) return '0h';
  if (hours < 10) return '${hours.toStringAsFixed(1)}h';
  return '${hours.toStringAsFixed(0)}h';
}
