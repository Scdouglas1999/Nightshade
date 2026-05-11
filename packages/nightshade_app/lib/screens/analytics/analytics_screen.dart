// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart'
    show CapturedImage, ImagingSession;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../localization/nightshade_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/analytics_keys.dart';
import 'widgets/science_export_hub.dart';
import 'widgets/session_chart.dart';
import 'widgets/image_thumbnail_strip.dart';
import 'widgets/project_tracking_panel.dart';
import 'widgets/science_analytics_tab.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _currentSubTab = 0;

  List<String> _tabs(BuildContext context) {
    final l10n = context.l10n;
    return [
      l10n.text('analyticsSession'),
      l10n.text('analyticsHistory'),
      l10n.text('analyticsProjects'),
      l10n.text('analyticsEquipmentStats'),
      l10n.text('analyticsScience'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final l10n = context.l10n;
    final tabs = _tabs(context);

    return ContextualTourPrompt(
      screenId: 'analytics',
      tourCategory: TutorialCategory.analyticsTour,
      title: l10n.text('analyticsTourTitle'),
      description: l10n.text('analyticsTourDescription'),
      durationMinutes: 2,
      alignment: Alignment.bottomRight,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          children: [
            // Sub-tabs
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  ...tabs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final label = entry.value;
                    // Attach tutorial keys to the tab buttons, not content
                    final Key? key = switch (index) {
                      0 => AnalyticsTutorialKeys.sessionTab,
                      1 => AnalyticsTutorialKeys.historyTab,
                      3 => AnalyticsTutorialKeys.equipmentTab,
                      _ => null,
                    };
                    return SubTabButton(
                      key: key,
                      label: label,
                      isSelected: index == _currentSubTab,
                      onTap: () => setState(() => _currentSubTab = index),
                    );
                  }),
                  const Spacer(),
                  if (_currentSubTab == 4) ...[
                    Tooltip(
                      message: 'Export science data',
                      child: IconButton(
                        icon: Icon(
                          LucideIcons.database,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const ScienceExportHub(),
                        ),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

            // Content
            Expanded(
              child: IndexedStack(
                index: _currentSubTab,
                children: const [
                  _SessionTab(),
                  _HistoryTab(),
                  _ProjectsTab(),
                  _EquipmentStatsTab(),
                  ScienceAnalyticsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTab extends ConsumerWidget {
  const _SessionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sessionState = ref.watch(sessionStateProvider);
    final duration = ref.watch(sessionDurationProvider);
    final l10n = context.l10n;

    // Get current session images if active, otherwise show standalone captures
    final bool isStandaloneMode = sessionState.dbSessionId == null;
    final imagesAsyncValue = sessionState.dbSessionId != null
        ? ref.watch(sessionImagesProvider(sessionState.dbSessionId!))
        : ref.watch(standaloneImagesProvider);
    void retryImages() {
      if (sessionState.dbSessionId != null) {
        ref.invalidate(sessionImagesProvider(sessionState.dbSessionId!));
      } else {
        ref.invalidate(standaloneImagesProvider);
      }
    }

    final String headerTitle;
    final String headerSubtitle;
    if (sessionState.isActive) {
      headerTitle = l10n.text('analyticsCurrentSession');
      headerSubtitle = sessionState.startTime != null
          ? l10n.text(
              'analyticsStarted',
              params: {
                'time': DateFormat('MMM d, yyyy HH:mm')
                    .format(sessionState.startTime!),
              },
            )
          : l10n.text('analyticsSessionInProgress');
    } else if (isStandaloneMode) {
      headerTitle = l10n.text('analyticsQuickCapture');
      headerSubtitle = l10n.text('analyticsQuickCaptureSubtitle');
    } else {
      headerTitle = l10n.text('analyticsNoActiveSession');
      headerSubtitle = l10n.text('analyticsNoSessionInProgress');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Session summary bar
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headerSubtitle,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _SummaryItem(
                        label: l10n.text('analyticsDuration'),
                        value: duration,
                      ),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: l10n.text('analyticsExposures'),
                        value: sessionState.isActive
                            ? '${sessionState.completedExposures}/${sessionState.totalExposures}'
                            : '---',
                      ),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: l10n.text('analyticsIntegration'),
                        value: sessionState.isActive
                            ? '${(sessionState.totalIntegrationSecs / 60).toStringAsFixed(1)}m'
                            : '---',
                      ),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: l10n.text('analyticsAvgHfr'),
                        value: sessionState.avgHfr != null
                            ? sessionState.avgHfr!.toStringAsFixed(2)
                            : '---',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Graph grid
          imagesAsyncValue.when(
            data: (images) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child: HfrChart(
                            key: AnalyticsTutorialKeys.hfrChart,
                            images: images)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: GuidingRmsChart(
                            key: AnalyticsTutorialKeys.guidingChart,
                            images: images)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: FocuserPositionChart(images: images)),
                    const SizedBox(width: 16),
                    Expanded(child: TemperatureChart(images: images)),
                  ],
                ),
              ],
            ),
            loading: () => _AnalyticsAsyncState(
              colors: colors,
              icon: LucideIcons.lineChart,
              message: 'Loading analytics charts...',
            ),
            error: (err, stack) => _AnalyticsAsyncState(
              colors: colors,
              icon: LucideIcons.alertTriangle,
              message: 'Failed to load analytics charts',
              detail: err.toString(),
              onRetry: retryImages,
            ),
          ),

          const SizedBox(height: 24),

          // Captured images strip
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('analyticsCapturedImages'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.text('analyticsQualityAdvisory'),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  imagesAsyncValue.when(
                    data: (images) => ImageThumbnailStrip(
                        key: AnalyticsTutorialKeys.thumbnails, images: images),
                    loading: () => SizedBox(
                      height: 100,
                      child: _AnalyticsAsyncState(
                        colors: colors,
                        icon: LucideIcons.image,
                        message: 'Loading images...',
                        compact: true,
                      ),
                    ),
                    error: (err, stack) => SizedBox(
                      height: 100,
                      child: _AnalyticsAsyncState(
                        colors: colors,
                        icon: LucideIcons.alertTriangle,
                        message: 'Failed to load images',
                        detail: err.toString(),
                        compact: true,
                        onRetry: retryImages,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsAsyncState extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final bool compact;

  const _AnalyticsAsyncState({
    required this.colors,
    required this.icon,
    required this.message,
    this.detail,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onRetry == null ? colors.primary : colors.error,
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: colors.textSecondary,
                ),
                maxLines: compact ? 2 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: compact ? 8 : 12),
              NightshadeButton(
                label: 'Retry',
                icon: LucideIcons.refreshCw,
                size: compact ? ButtonSize.small : ButtonSize.medium,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Provider for watching session images
final sessionImagesProvider =
    StreamProvider.family<List<CapturedImage>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteSessionImages(backend, sessionId);
  }
  return ref.watch(imagesDaoProvider).watchImagesForSession(sessionId);
});

/// Provider for watching standalone (sessionless) images
final standaloneImagesProvider = StreamProvider<List<CapturedImage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteStandaloneImages(backend);
  }
  return ref.watch(imagesDaoProvider).watchStandaloneImages();
});

/// Provider for unique target names derived from sessions
/// Returns a list of unique session names to use as target filter options
final sessionTargetNamesProvider = Provider<AsyncValue<List<String>>>((ref) {
  final sessionsAsync = ref.watch(allSessionsProvider);
  return sessionsAsync.when(
    data: (sessions) {
      // Extract unique non-null session names
      final uniqueNames = sessions
          .map((s) => s.name)
          .where((name) => name != null && name.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()
        ..sort();
      return AsyncValue.data(['All Targets', ...uniqueNames]);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({super.key});

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _searchQuery = '';
  String _timeFilter = 'All Time';
  String _targetFilter = 'All Targets';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sessionsAsyncValue = ref.watch(allSessionsProvider);
    final targetNamesAsync = ref.watch(sessionTargetNamesProvider);
    final l10n = context.l10n;

    // Get target list from sessions, fallback to default if loading/error
    final targetList = targetNamesAsync.when(
      data: (targets) => targets,
      loading: () => const ['All Targets'],
      error: (_, __) => const ['All Targets'],
    );

    // Reset target filter if current selection no longer exists
    if (!targetList.contains(_targetFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _targetFilter = 'All Targets');
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Filters
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  hint: l10n.text('analyticsSearchSessions'),
                  prefixIcon: LucideIcons.search,
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 16),
              NightshadeDropdown(
                value: _timeFilter,
                items: const ['All Time', 'This Month', 'This Year'],
                onChanged: (v) => setState(() => _timeFilter = v ?? 'All Time'),
              ),
              const SizedBox(width: 16),
              NightshadeDropdown(
                value: _targetFilter,
                items: targetList,
                onChanged: (v) =>
                    setState(() => _targetFilter = v ?? 'All Targets'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Session list
          Expanded(
            child: sessionsAsyncValue.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.folderOpen,
                            size: 48, color: colors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          l10n.text('analyticsNoSessionHistory'),
                          style: TextStyle(
                              fontSize: 14, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.text('analyticsNoSessionHistoryDesc'),
                          style:
                              TextStyle(fontSize: 12, color: colors.textMuted),
                        ),
                      ],
                    ),
                  );
                }

                // Filter sessions based on search query and target filter
                final filteredSessions = sessions.where((session) {
                  // Search filter
                  final nameMatch = _searchQuery.isEmpty ||
                      (session.name
                              ?.toLowerCase()
                              .contains(_searchQuery.toLowerCase()) ??
                          false);
                  // Target filter
                  final targetMatch = _targetFilter == 'All Targets' ||
                      session.name == _targetFilter;
                  // Time filter
                  bool timeMatch = true;
                  if (_timeFilter == 'This Month') {
                    final now = DateTime.now();
                    timeMatch = session.startTime.year == now.year &&
                        session.startTime.month == now.month;
                  } else if (_timeFilter == 'This Year') {
                    timeMatch = session.startTime.year == DateTime.now().year;
                  }
                  return nameMatch && targetMatch && timeMatch;
                }).toList();

                return ListView.builder(
                  itemCount: filteredSessions.length,
                  itemBuilder: (context, index) {
                    final session = filteredSessions[index];
                    return _SessionHistoryCard(session: session);
                  },
                );
              },
              // Skeleton list mirrors the real history card geometry so the
              // page doesn't reflow when sessions resolve.
              loading: () => const _SessionHistorySkeletonList(),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 48, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading sessions',
                      style: TextStyle(fontSize: 14, color: colors.error),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      err.toString(),
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: ProjectTrackingPanel(),
    );
  }
}

/// Session history card widget
class _SessionHistoryCard extends ConsumerWidget {
  final ImagingSession session;

  const _SessionHistoryCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final duration = session.endTime != null
        ? session.endTime!.difference(session.startTime)
        : DateTime.now().difference(session.startTime);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: NightshadeCard(
        child: InkWell(
          onTap: () => _showSessionDetail(context, ref, session),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Session info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            session.name ??
                                context.l10n.text('analyticsUnnamedSession'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(session.status, colors),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              session.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: colors.background,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy HH:mm')
                            .format(session.startTime),
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),

                // Statistics
                Row(
                  children: [
                    _StatChip(
                      icon: LucideIcons.clock,
                      label: _formatDuration(duration),
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: LucideIcons.image,
                      label: '${session.successfulExposures}',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: LucideIcons.timer,
                      label:
                          '${(session.totalIntegrationSecs / 3600).toStringAsFixed(1)}h',
                      colors: colors,
                    ),
                    if (session.avgHfr != null) ...[
                      const SizedBox(width: 12),
                      _StatChip(
                        icon: LucideIcons.focus,
                        label: session.avgHfr!.toStringAsFixed(2),
                        colors: colors,
                      ),
                    ],
                  ],
                ),

                const SizedBox(width: 12),
                Icon(LucideIcons.chevronRight,
                    size: 20, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, NightshadeColors colors) {
    switch (status.toLowerCase()) {
      case 'completed':
        return colors.success;
      case 'active':
        return colors.info;
      case 'aborted':
        return colors.warning;
      case 'error':
        return colors.error;
      default:
        return colors.textMuted;
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  void _showSessionDetail(
      BuildContext context, WidgetRef ref, ImagingSession session) {
    showDialog(
      context: context,
      builder: (context) => _SessionDetailDialog(session: session),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Session detail dialog with export functionality
class _SessionDetailDialog extends ConsumerWidget {
  final ImagingSession session;

  const _SessionDetailDialog({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final imagesAsyncValue = ref.watch(sessionImagesProvider(session.id));
    final l10n = context.l10n;

    return Dialog(
      backgroundColor: colors.surface,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name ?? l10n.text('analyticsUnnamedSession'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy HH:mm')
                              .format(session.startTime),
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Export buttons
                  IconButton(
                    icon: const Icon(LucideIcons.fileJson, size: 18),
                    onPressed: () => _exportJson(context, ref),
                    tooltip: l10n.text('analyticsExportJson'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                    onPressed: () => _exportCsv(context, ref),
                    tooltip: l10n.text('analyticsExportCsv'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileText, size: 18),
                    onPressed: () => _exportReport(context, ref),
                    tooltip: l10n.text('analyticsExportHtml'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.share, size: 18),
                    onPressed: () => _exportAndShare(context, ref),
                    tooltip: l10n.text('share'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistics
                    _buildStatisticsSection(context, colors),
                    const SizedBox(height: 16),

                    // Images
                    imagesAsyncValue.when(
                      data: (images) =>
                          _buildImagesSection(context, colors, images),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Text(
                        'Error loading images: $err',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsSection(
      BuildContext context, NightshadeColors colors) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('analyticsStatistics'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStat(
              l10n.text('analyticsTotalExposures'),
              session.totalExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsSuccessful'),
              session.successfulExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsFailed'),
              session.failedExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsIntegration'),
              '${(session.totalIntegrationSecs / 3600).toStringAsFixed(2)}h',
              colors,
            ),
            if (session.avgHfr != null)
              _buildStat(
                l10n.text('analyticsAvgHfr'),
                session.avgHfr!.toStringAsFixed(2),
                colors,
              ),
            if (session.avgGuidingRms != null)
              _buildStat(
                l10n.text('analyticsAvgRms'),
                session.avgGuidingRms!.toStringAsFixed(2),
                colors,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection(
    BuildContext context,
    NightshadeColors colors,
    List<CapturedImage> images,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text(
            'analyticsImages',
            params: {'count': images.length.toString()},
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ImageThumbnailStrip(images: images),
      ],
    );
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'json');
        if (context.mounted) {
          context.showSuccessSnackBar('Exported to: $filePath');
        }
        return;
      }
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      final filePath = await exportService.exportToJson(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'csv');
        if (context.mounted) {
          context.showSuccessSnackBar('Exported to: $filePath');
        }
        return;
      }
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      final filePath = await exportService.exportToCsv(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportAndShare(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'csv');
        await Share.shareXFiles([XFile(filePath)],
            text: 'Session data for ${session.name ?? "session"}');
        return;
      }
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      // Export to CSV for sharing (more universal format)
      final filePath = await exportService.exportToCsv(session.id);

      // Share the file
      await Share.shareXFiles([XFile(filePath)],
          text: 'Session data for ${session.name ?? "session"}');
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Share failed: $e');
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'html');
        if (context.mounted) {
          context.showSuccessSnackBar('Report exported to: $filePath');
        }
        return;
      }
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      final filePath = await exportService.exportToHtml(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Report exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Report export failed: $e');
      }
    }
  }
}

Stream<List<CapturedImage>> _pollRemoteSessionImages(
  NetworkBackend backend,
  int sessionId,
) async* {
  yield await _fetchRemoteSessionImages(backend, sessionId);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteSessionImages(backend, sessionId);
  }
}

Stream<List<CapturedImage>> _pollRemoteStandaloneImages(
  NetworkBackend backend,
) async* {
  yield await _fetchRemoteStandaloneImages(backend);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteStandaloneImages(backend);
  }
}

Future<List<CapturedImage>> _fetchRemoteSessionImages(
  NetworkBackend backend,
  int sessionId,
) async {
  final rows = await backend.getSessionImageRows(sessionId);
  return rows.map(CapturedImage.fromJson).toList(growable: false);
}

Future<List<CapturedImage>> _fetchRemoteStandaloneImages(
  NetworkBackend backend,
) async {
  final rows = await backend.getStandaloneImageRows();
  return rows.map(CapturedImage.fromJson).toList(growable: false);
}

Future<String> _saveRemoteExport(
  NetworkBackend backend,
  int sessionId,
  String format,
) async {
  final bytes = await backend.downloadSessionExport(sessionId, format);
  final docsDir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
  if (!await exportDir.exists()) {
    await exportDir.create(recursive: true);
  }
  final fileName =
      'session_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.$format';
  final filePath = path.join(exportDir.path, fileName);
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}

class _EquipmentStatsTab extends StatelessWidget {
  const _EquipmentStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Access colors to ensure theme extension is available
    Theme.of(context).extension<NightshadeColors>()!;

    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: ResponsiveCardGrid(
        children: [
          _EquipmentStatCard(
            title: 'Camera',
            stats: [
              _Stat(label: 'Total Exposures', value: '---'),
              _Stat(label: 'Total Integration', value: '---'),
              _Stat(label: 'Avg Temperature', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Mount',
            stats: [
              _Stat(label: 'Total Slews', value: '---'),
              _Stat(label: 'Total Tracking Time', value: '---'),
              _Stat(label: 'Meridian Flips', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Focuser',
            stats: [
              _Stat(label: 'Autofocus Runs', value: '---'),
              _Stat(label: 'Avg HFR Achieved', value: '---'),
              _Stat(label: 'Total Movements', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Guider',
            stats: [
              _Stat(label: 'Total Guide Time', value: '---'),
              _Stat(label: 'Avg RMS', value: '---'),
              _Stat(label: 'Star Lost Events', value: '---'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _Stat {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});
}

class _EquipmentStatCard extends StatelessWidget {
  final String title;
  final List<_Stat> stats;

  const _EquipmentStatCard({required this.title, required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...stats.map((stat) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        stat.label,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                      Text(
                        stat.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder used while session history loads. Rendering a list of
/// card-sized shimmer rows (rather than a centred spinner) preserves the
/// final layout so the page doesn't pop when the real data arrives.
class _SessionHistorySkeletonList extends StatelessWidget {
  const _SessionHistorySkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, _) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: ShimmerLoading(
          child: NightshadeCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SkeletonBox(width: 180, height: 14),
                          SizedBox(height: 8),
                          SkeletonBox(width: 120, height: 12),
                        ],
                      ),
                    ),
                    SkeletonBox(width: 220, height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
