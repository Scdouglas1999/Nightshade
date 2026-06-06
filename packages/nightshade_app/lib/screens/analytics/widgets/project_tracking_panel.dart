import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../../../utils/snackbar_helper.dart';
import 'campaign_rollup_dialog.dart';

// =============================================================================
// Sort Mode
// =============================================================================

enum ProjectSortMode {
  completion,
  totalTime,
  lastImaged,
  name,
}

// =============================================================================
// Per-Filter Breakdown Provider
// =============================================================================

/// Computes per-target, per-filter integration time from captured images.
///
/// Returns a map of target ID to (filter name -> total seconds).
final perFilterIntegrationProvider =
    Provider<AsyncValue<Map<int, Map<String, double>>>>((ref) {
  final imagesAsync = ref.watch(allDbImagesProvider);

  if (imagesAsync.hasError) {
    return AsyncValue.error(
      imagesAsync.error!,
      imagesAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (imagesAsync.isLoading) {
    return const AsyncValue.loading();
  }

  final images = imagesAsync.value ?? const <DbCapturedImage>[];
  final result = <int, Map<String, double>>{};

  for (final image in images) {
    final targetId = image.targetId;
    if (targetId == null) continue;
    if (image.frameType != 'light') continue;
    if (!image.isAccepted) continue;

    final filterName = image.filter ?? 'Unfiltered';
    final targetMap = result.putIfAbsent(targetId, () => <String, double>{});
    targetMap[filterName] =
        (targetMap[filterName] ?? 0.0) + image.exposureDuration;
  }

  return AsyncValue.data(result);
});

// =============================================================================
// Untracked-Targets Cleanup Count
// =============================================================================

/// Number of "untracked" library targets eligible for the opt-in cleanup, or
/// `null` when the active backend can't compute it (remote host). Re-evaluates
/// whenever the targets or sessions data changes so the button count stays live.
///
/// "Untracked" is defined in [TargetsDao.deleteUntrackedTargets]: no integration
/// goal, not a favorite, no captured subs, no integration time, and not
/// referenced by any imaging session.
final untrackedTargetsCountProvider = FutureProvider<int?>((ref) async {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    // The cleanup runs a session-aware SQL predicate against the local Drift DB.
    // There is no equivalent host RPC, so signal "unavailable" rather than fake
    // a count. The UI disables the button with an explanatory tooltip.
    return null;
  }
  // Recompute when the underlying data changes.
  ref.watch(allDbTargetsProvider);
  ref.watch(allSessionsProvider);
  return ref.read(targetsDaoProvider).countUntrackedTargets();
});

// =============================================================================
// Project Tracking Panel
// =============================================================================

/// Full-featured project tracking panel for the analytics screen.
///
/// Displays multi-night target progress with:
/// - Summary stats header (total targets, total integration, sessions this month)
/// - Sort options (completion %, total time, last imaged, name)
/// - Per-target cards with filter breakdown, progress bars, and goal editing
class ProjectTrackingPanel extends ConsumerStatefulWidget {
  const ProjectTrackingPanel({super.key});

  @override
  ConsumerState<ProjectTrackingPanel> createState() =>
      _ProjectTrackingPanelState();
}

class _ProjectTrackingPanelState extends ConsumerState<ProjectTrackingPanel> {
  ProjectSortMode _sortMode = ProjectSortMode.completion;

  List<ProjectProgress> _sortProjects(List<ProjectProgress> projects) {
    final sorted = List<ProjectProgress>.from(projects);
    switch (_sortMode) {
      case ProjectSortMode.completion:
        sorted.sort((a, b) {
          // Tracked projects first, then by completion ascending (least complete first)
          final aPriority = a.isTracked ? 0 : 1;
          final bPriority = b.isTracked ? 0 : 1;
          if (aPriority != bPriority) return aPriority.compareTo(bPriority);
          if (a.isTracked && b.isTracked) {
            return a.completionFraction.compareTo(b.completionFraction);
          }
          return b.integratedSecs.compareTo(a.integratedSecs);
        });
      case ProjectSortMode.totalTime:
        sorted.sort((a, b) => b.integratedSecs.compareTo(a.integratedSecs));
      case ProjectSortMode.lastImaged:
        sorted.sort((a, b) {
          final aTime = a.lastSessionAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.lastSessionAt?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });
      case ProjectSortMode.name:
        sorted.sort((a, b) =>
            a.target.name.toLowerCase().compareTo(b.target.name.toLowerCase()));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final progressAsync = ref.watch(projectProgressListProvider);
    final filterDataAsync = ref.watch(perFilterIntegrationProvider);

    return progressAsync.when(
      data: (projects) {
        if (projects.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.target, size: 48, color: colors.textMuted),
                const SizedBox(height: 16),
                Text(
                  context.l10n.text('analyticsNoProjects'),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize16,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add targets and capture images to track multi-night progress.',
                  style: TextStyle(fontSize: NightshadeTypography.fontSize13, color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final sorted = _sortProjects(projects);
        final filterData =
            filterDataAsync.valueOrNull ?? <int, Map<String, double>>{};

        return Column(
          children: [
            // Header actions: opt-in cleanup of phantom/untracked targets.
            const _CleanupHeaderRow(),
            // Summary stats header
            _SummaryStatsHeader(projects: projects, colors: colors),
            const SizedBox(height: 12),

            // Sort bar
            _SortBar(
              currentSort: _sortMode,
              onSortChanged: (mode) => setState(() => _sortMode = mode),
              colors: colors,
            ),
            const SizedBox(height: 12),

            // Project list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final progress = sorted[index];
                  final targetFilterData =
                      filterData[progress.target.id] ?? <String, double>{};
                  return _EnhancedProjectCard(
                    progress: progress,
                    filterBreakdown: targetFilterData,
                  );
                },
              ),
            ),
          ],
        );
      },
      // Shimmer card placeholders so the panel keeps its real geometry.
      loading: () => _ProjectsLoadingSkeleton(colors: colors),
      error: (error, stackTrace) => Center(
        child: Text(
          'Error loading projects: $error',
          style: TextStyle(color: colors.error),
        ),
      ),
    );
  }
}

// =============================================================================
// Cleanup Header Row
// =============================================================================

/// Opt-in affordance to remove "untracked" library targets (no goal, no
/// favorite, no captured data, no sessions) that accumulated as phantom rows.
/// Hidden entirely when there is nothing to remove; disabled with an
/// explanatory tooltip when running against a remote imaging host where the
/// session-aware cleanup can't be performed.
class _CleanupHeaderRow extends ConsumerWidget {
  const _CleanupHeaderRow();

  Future<void> _runCleanup(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove untracked targets?'),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 420,
            ),
            child: Text(
              'This permanently removes $count target'
              '${count == 1 ? '' : 's'} that have no integration goal, no '
              'captured data, and no imaging sessions. Favorites and any target '
              'you have imaged are kept. This cannot be undone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final deleted =
          await ref.read(targetsDaoProvider).deleteUntrackedTargets();
      // Refresh the library-backed views and this panel's count.
      ref.invalidate(allDbTargetsProvider);
      ref.invalidate(favoriteDbTargetsProvider);
      ref.invalidate(untrackedTargetsCountProvider);
      if (!context.mounted) return;
      context.showSuccessSnackBar(
        'Removed $deleted untracked target${deleted == 1 ? '' : 's'}',
      );
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Failed to remove untracked targets: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final countAsync = ref.watch(untrackedTargetsCountProvider);
    final backend = ref.watch(backendProvider);
    final isRemote = backend is NetworkBackend;

    // On a remote host the cleanup can't run; surface a disabled, explained
    // button instead of hiding it or silently no-op'ing.
    if (isRemote) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: 'Available on the imaging host',
            child: TextButton.icon(
              onPressed: null,
              icon: const Icon(LucideIcons.trash2, size: 14),
              label: const Text(
                'Remove untracked targets',
                style: TextStyle(fontSize: NightshadeTypography.fontSize12),
              ),
            ),
          ),
        ),
      );
    }

    final count = countAsync.valueOrNull ?? 0;
    if (count <= 0) {
      // Nothing to clean up — don't clutter the header.
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _runCleanup(context, ref, count),
          icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
          label: Text(
            'Remove untracked targets ($count)',
            style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.error),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Summary Stats Header
// =============================================================================

class _SummaryStatsHeader extends StatelessWidget {
  final List<ProjectProgress> projects;
  final NightshadeColors colors;

  const _SummaryStatsHeader({
    required this.projects,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final totalTargets = projects.length;
    final trackedTargets = projects.where((p) => p.isTracked).length;
    final completedTargets = projects.where((p) => p.isCompleted).length;
    final totalIntegrationHours =
        projects.fold<double>(0.0, (sum, p) => sum + p.integratedSecs) / 3600.0;

    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final sessionsThisMonth = projects.fold<int>(0, (sum, p) {
      if (p.lastSessionAt != null && p.lastSessionAt!.isAfter(thisMonthStart)) {
        return sum + 1;
      }
      return sum;
    });

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.star,
                label: 'Targets',
                value: '$totalTargets',
                colors: colors,
              ),
            ),
            _divider(),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.target,
                label: 'Tracked',
                value: '$trackedTargets',
                colors: colors,
              ),
            ),
            _divider(),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.checkCircle,
                label: 'Completed',
                value: '$completedTargets',
                colors: colors,
              ),
            ),
            _divider(),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.timer,
                label: 'Total Integration',
                value: '${totalIntegrationHours.toStringAsFixed(1)}h',
                colors: colors,
              ),
            ),
            _divider(),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.calendar,
                label: 'Active This Month',
                value: '$sessionsThisMonth',
                colors: colors,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: colors.border,
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colors.textSecondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize16,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// =============================================================================
// Sort Bar
// =============================================================================

class _SortBar extends StatelessWidget {
  final ProjectSortMode currentSort;
  final ValueChanged<ProjectSortMode> onSortChanged;
  final NightshadeColors colors;

  const _SortBar({
    required this.currentSort,
    required this.onSortChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.arrowUpDown, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Text(
          'Sort by:',
          style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
        ),
        const SizedBox(width: 8),
        _sortChip('Completion', ProjectSortMode.completion),
        const SizedBox(width: 6),
        _sortChip('Total Time', ProjectSortMode.totalTime),
        const SizedBox(width: 6),
        _sortChip('Last Imaged', ProjectSortMode.lastImaged),
        const SizedBox(width: 6),
        _sortChip('Name', ProjectSortMode.name),
      ],
    );
  }

  Widget _sortChip(String label, ProjectSortMode mode) {
    final isSelected = currentSort == mode;
    return GestureDetector(
      onTap: () => onSortChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: isSelected
            ? NightshadeDecorations.selectedSurface(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: colors.border),
              ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Enhanced Project Card
// =============================================================================

class _EnhancedProjectCard extends ConsumerWidget {
  final ProjectProgress progress;
  final Map<String, double> filterBreakdown;

  const _EnhancedProjectCard({
    required this.progress,
    required this.filterBreakdown,
  });

  String _formatHours(double seconds) =>
      '${(seconds / 3600.0).toStringAsFixed(1)}h';

  Future<void> _editGoal(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final controller = TextEditingController(
      text: progress.goalIntegrationSecs > 0
          ? (progress.goalIntegrationSecs / 3600.0).toStringAsFixed(1)
          : '',
    );
    final submitted = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            l10n.text(
              'analyticsGoalDialogTitle',
              params: {'target': progress.target.name},
            ),
          ),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 420,
            ),
            child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.text('analyticsGoalHours'),
              hintText: 'e.g. 10.0',
              suffixText: 'hours',
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.text('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(0.0),
              child: Text(l10n.text('analyticsClearGoal')),
            ),
            FilledButton(
              onPressed: () {
                final hours = double.tryParse(controller.text.trim());
                if (hours == null || hours < 0) return;
                Navigator.of(dialogContext).pop(hours);
              },
              child: Text(l10n.text('analyticsSave')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (submitted == null) return;

    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      await backend.updateTarget(progress.target.id, {
        'goalIntegrationSecs': submitted * 3600.0,
      });
      ref.invalidate(allDbTargetsProvider);
      ref.invalidate(projectProgressListProvider);
    } else {
      await ref
          .read(targetsDaoProvider)
          .setGoalIntegrationSecs(progress.target.id, submitted * 3600.0);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final completionPct = progress.completionFraction * 100.0;
    final l10n = context.l10n;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name, catalog ID, edit goal button
            Row(
              children: [
                // Status indicator
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: progress.isCompleted
                        ? colors.success
                        : progress.isTracked
                            ? colors.primary
                            : colors.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress.target.name,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (progress.target.catalogId != null ||
                          progress.target.objectType != null)
                        Text(
                          progress.target.catalogId ??
                              progress.target.objectType ??
                              '',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => CampaignRollupDialog.show(
                    context,
                    progress.target.id,
                  ),
                  icon: const Icon(LucideIcons.lineChart, size: 14),
                  label: const Text(
                    'View Campaign',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize12),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _editGoal(context, ref),
                  icon: const Icon(LucideIcons.target, size: 14),
                  label: Text(
                    progress.isTracked
                        ? l10n.text('analyticsEditGoal')
                        : l10n.text('analyticsSetGoal'),
                    style: const TextStyle(fontSize: NightshadeTypography.fontSize12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            if (progress.isTracked) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
                      child: LinearProgressIndicator(
                        value: progress.completionFraction,
                        minHeight: 10,
                        backgroundColor: colors.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress.isCompleted
                              ? colors.success
                              : colors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${completionPct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      fontWeight: FontWeight.w700,
                      color: progress.isCompleted
                          ? colors.success
                          : colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Stats row
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: LucideIcons.timer,
                  label: 'Integrated',
                  value: _formatHours(progress.integratedSecs),
                  colors: colors,
                ),
                _MetricChip(
                  icon: LucideIcons.target,
                  label: 'Goal',
                  value: progress.isTracked
                      ? _formatHours(progress.goalIntegrationSecs)
                      : 'Not set',
                  colors: colors,
                ),
                _MetricChip(
                  icon: LucideIcons.hourglass,
                  label: 'Remaining',
                  value: progress.isTracked
                      ? _formatHours(progress.remainingSecs)
                      : '-',
                  colors: colors,
                ),
                _MetricChip(
                  icon: LucideIcons.layers,
                  label: 'Sessions',
                  value: '${progress.sessionCount}',
                  colors: colors,
                ),
                _MetricChip(
                  icon: LucideIcons.image,
                  label: 'Frames',
                  value: '${progress.successfulExposures}',
                  colors: colors,
                ),
              ],
            ),

            // Per-filter breakdown
            if (filterBreakdown.isNotEmpty) ...[
              const SizedBox(height: 12),
              _FilterBreakdownRow(
                filterData: filterBreakdown,
                colors: colors,
              ),
            ],

            // Last imaged date
            if (progress.lastSessionAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last imaged: ${DateFormat('MMM d, yyyy HH:mm').format(progress.lastSessionAt!)}',
                style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Metric Chip
// =============================================================================

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
            ),
            Text(
              value,
              style: NightshadeTypography.labelStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Filter Breakdown Row
// =============================================================================

class _FilterBreakdownRow extends StatelessWidget {
  final Map<String, double> filterData;
  final NightshadeColors colors;

  const _FilterBreakdownRow({
    required this.filterData,
    required this.colors,
  });

  Color _filterColor(String filterName) {
    switch (filterName.toUpperCase()) {
      case 'L':
      case 'LUMINANCE':
        return const Color(0xFFD4D4D8);
      case 'R':
      case 'RED':
        return const Color(0xFFF87171);
      case 'G':
      case 'GREEN':
        return const Color(0xFF4ADE80);
      case 'B':
      case 'BLUE':
        return const Color(0xFF60A5FA);
      case 'HA':
      case 'H-ALPHA':
        return const Color(0xFFB91C1C);
      case 'OIII':
      case 'O-III':
        return const Color(0xFF2DD4BF);
      case 'SII':
      case 'S-II':
        return const Color(0xFFFB923C);
      default:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sort filters by total time descending
    final sortedEntries = filterData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: sortedEntries.map((entry) {
        final hours = entry.value / 3600.0;
        final color = _filterColor(entry.key);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: NightshadeDecorations.statusChip(
            color,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${entry.key}: ${hours.toStringAsFixed(1)}h',
                style: NightshadeTypography.labelStrongSm.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Skeleton placeholder for the project list while progress data loads.
/// Renders card-shaped shimmer rows that match the production tile height
/// so the layout doesn't shift when the data resolves.
class _ProjectsLoadingSkeleton extends StatelessWidget {
  final NightshadeColors colors;

  const _ProjectsLoadingSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(4, (_) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerLoading(
            child: NightshadeCard(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 220, height: 16),
                    SizedBox(height: 10),
                    SkeletonBox(height: 8, borderRadius: 4),
                    SizedBox(height: 12),
                    SkeletonBox(width: 160, height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
