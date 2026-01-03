import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
import 'package:nightshade_core/src/database/database.dart' show CapturedImage, ImagingSession;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'widgets/session_chart.dart';
import 'widgets/image_thumbnail_strip.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _currentSubTab = 0;

  static const _tabs = ['Session', 'History', 'Equipment Stats'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
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
              ..._tabs.asMap().entries.map((entry) {
                final index = entry.key;
                final label = entry.value;
                return SubTabButton(
                  label: label,
                  isSelected: index == _currentSubTab,
                  onTap: () => setState(() => _currentSubTab = index),
                );
              }),
              const Spacer(),
            ],
          ),
        ),

        // Content
        Expanded(
          child: IndexedStack(
            index: _currentSubTab,
            children: [
              _SessionTab(),
              _HistoryTab(),
              _EquipmentStatsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sessionState = ref.watch(sessionStateProvider);
    final duration = ref.watch(sessionDurationProvider);

    // Get current session images if active
    final imagesAsyncValue = sessionState.dbSessionId != null
        ? ref.watch(sessionImagesProvider(sessionState.dbSessionId!))
        : const AsyncValue<List<CapturedImage>>.data([]);

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
                        sessionState.isActive ? 'Current Session' : 'No Active Session',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sessionState.isActive && sessionState.startTime != null
                            ? 'Started: ${DateFormat('MMM d, yyyy HH:mm').format(sessionState.startTime!)}'
                            : 'No session in progress',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _SummaryItem(label: 'Duration', value: duration),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: 'Exposures',
                        value: sessionState.isActive
                            ? '${sessionState.completedExposures}/${sessionState.totalExposures}'
                            : '---',
                      ),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: 'Integration',
                        value: sessionState.isActive
                            ? '${(sessionState.totalIntegrationSecs / 60).toStringAsFixed(1)}m'
                            : '---',
                      ),
                      const SizedBox(width: 32),
                      _SummaryItem(
                        label: 'Avg HFR',
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
                    Expanded(child: HfrChart(images: images)),
                    const SizedBox(width: 16),
                    Expanded(child: GuidingRmsChart(images: images)),
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
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text(
                'Error loading charts: $err',
                style: TextStyle(color: colors.error),
              ),
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
                    'Captured Images',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  imagesAsyncValue.when(
                    data: (images) => ImageThumbnailStrip(images: images),
                    loading: () => const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, stack) => SizedBox(
                      height: 100,
                      child: Center(
                        child: Text(
                          'Error loading images: $err',
                          style: TextStyle(color: colors.error),
                        ),
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

/// Provider for watching session images
final sessionImagesProvider =
    StreamProvider.family<List<CapturedImage>, int>((ref, sessionId) {
  return ref.watch(imagesDaoProvider).watchImagesForSession(sessionId);
});

class _HistoryTab extends ConsumerStatefulWidget {
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Filters
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  hint: 'Search sessions...',
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
                items: const ['All Targets', 'M31', 'M42', 'NGC 7000'],
                onChanged: (v) => setState(() => _targetFilter = v ?? 'All Targets'),
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
                        Icon(LucideIcons.folderOpen, size: 48, color: colors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'No session history',
                          style: TextStyle(fontSize: 14, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete an imaging session to see history here',
                          style: TextStyle(fontSize: 12, color: colors.textMuted),
                        ),
                      ],
                    ),
                  );
                }

                // Filter sessions based on search query
                final filteredSessions = sessions.where((session) {
                  final nameMatch = _searchQuery.isEmpty ||
                      (session.name?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                          false);
                  return nameMatch;
                }).toList();

                return ListView.builder(
                  itemCount: filteredSessions.length,
                  itemBuilder: (context, index) {
                    final session = filteredSessions[index];
                    return _SessionHistoryCard(session: session);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle, size: 48, color: colors.error),
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
                            session.name ?? 'Unnamed Session',
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
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy HH:mm').format(session.startTime),
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
                      label: '${(session.totalIntegrationSecs / 3600).toStringAsFixed(1)}h',
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
                Icon(LucideIcons.chevronRight, size: 20, color: colors.textMuted),
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
        return Colors.green;
      case 'active':
        return Colors.blue;
      case 'aborted':
        return Colors.orange;
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

  void _showSessionDetail(BuildContext context, WidgetRef ref, ImagingSession session) {
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
                          session.name ?? 'Unnamed Session',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy HH:mm').format(session.startTime),
                          style: TextStyle(fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Export buttons
                  IconButton(
                    icon: const Icon(LucideIcons.fileJson, size: 18),
                    onPressed: () => _exportJson(context, ref),
                    tooltip: 'Export to JSON',
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                    onPressed: () => _exportCsv(context, ref),
                    tooltip: 'Export to CSV',
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.share, size: 18),
                    onPressed: () => _exportAndShare(context, ref),
                    tooltip: 'Share',
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
                    _buildStatisticsSection(colors),
                    const SizedBox(height: 16),

                    // Images
                    imagesAsyncValue.when(
                      data: (images) => _buildImagesSection(colors, images),
                      loading: () => const Center(child: CircularProgressIndicator()),
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

  Widget _buildStatisticsSection(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics',
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
            _buildStat('Total Exposures', session.totalExposures.toString(), colors),
            _buildStat('Successful', session.successfulExposures.toString(), colors),
            _buildStat('Failed', session.failedExposures.toString(), colors),
            _buildStat(
              'Integration',
              '${(session.totalIntegrationSecs / 3600).toStringAsFixed(2)}h',
              colors,
            ),
            if (session.avgHfr != null)
              _buildStat('Avg HFR', session.avgHfr!.toStringAsFixed(2), colors),
            if (session.avgGuidingRms != null)
              _buildStat('Avg RMS', session.avgGuidingRms!.toStringAsFixed(2), colors),
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

  Widget _buildImagesSection(NightshadeColors colors, List<CapturedImage> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Images (${images.length})',
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
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      final filePath = await exportService.exportToJson(session.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to: $filePath')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
      );

      final filePath = await exportService.exportToCsv(session.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to: $filePath')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportAndShare(BuildContext context, WidgetRef ref) async {
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }
}

class _EquipmentStatsTab extends StatelessWidget {
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

class _GraphCard extends StatelessWidget {
  final String title;
  final String yLabel;

  const _GraphCard({required this.title, required this.yLabel});

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
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'No data',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
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
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
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

