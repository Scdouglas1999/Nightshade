import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../scheduler/widgets/integration_goals_editor.dart';
import '../../sequencer/widgets/smart_night_dialog.dart';

part 'projects_tab_content/project_header.dart';
part 'projects_tab_content/progress_widgets.dart';
part 'projects_tab_content/project_dialogs.dart';
part 'projects_tab_content/terminal_states.dart';

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
    final progress = await ref.read(activeProjectProgressProvider.future);
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
