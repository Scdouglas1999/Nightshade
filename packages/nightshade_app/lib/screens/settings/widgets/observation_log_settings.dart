import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../utils/exported_file_reveal.dart';
import '../../../utils/snackbar_helper.dart';
import '../../accessible_dropdown.dart';

/// Settings panel for viewing and managing observation logs.
class ObservationLogSettings extends ConsumerStatefulWidget {
  const ObservationLogSettings({super.key});

  @override
  ConsumerState<ObservationLogSettings> createState() =>
      _ObservationLogSettingsState();
}

class _ObservationLogSettingsState
    extends ConsumerState<ObservationLogSettings> {
  String _searchQuery = '';
  int? _filterRating;
  bool _isExporting = false;
  final Set<int> _deletingLogIds = {};

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final logsAsync = ref.watch(observationLogsProvider);
    final statsAsync = ref.watch(observationLogStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with stats
          Row(
            children: [
              Icon(LucideIcons.bookOpen, color: colors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Observation Log',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              // Export button
              NightshadeButton(
                onPressed: _isExporting ? null : () => _exportCsv(context),
                label: _isExporting ? 'Exporting...' : 'Export CSV',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                icon: LucideIcons.download,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats summary
          statsAsync.when(
            data: (stats) => _buildStats(stats, colors),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              'Could not load observation log stats.',
              style: TextStyle(color: colors.error),
            ),
          ),
          const SizedBox(height: 16),

          // Search and filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by object name or catalog ID...',
                    prefixIcon: const Icon(LucideIcons.search, size: 16),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 8),
              AccessibleDropdown<int?>(
                value: _filterRating,
                hint: const Text('Min Rating'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('All Ratings'),
                  ),
                  ...List.generate(5, (i) {
                    final r = i + 1;
                    return DropdownMenuItem<int?>(
                      value: r,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.star,
                            size: 14,
                            color: colors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text('$r+'),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _filterRating = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Log entries list
          logsAsync.when(
            data: (logs) {
              final filtered = _filterLogs(logs);
              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.star,
                          size: 48,
                          color: colors.textSecondary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          logs.isEmpty
                              ? 'No observations logged yet.\nTap an object in the planetarium and use "Log Observation".'
                              : 'No observations match your search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => Divider(
                  color: colors.border.withValues(alpha: 0.5),
                  height: 1,
                ),
                itemBuilder: (context, index) =>
                    _buildLogEntry(filtered[index], colors),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              'Could not load observation logs.',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  List<ObservationLogEntry> _filterLogs(List<ObservationLogEntry> logs) {
    var filtered = logs;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where((log) =>
              log.objectName.toLowerCase().contains(query) ||
              (log.catalogId?.toLowerCase().contains(query) ?? false))
          .toList();
    }

    if (_filterRating != null) {
      filtered = filtered
          .where((log) => log.rating != null && log.rating! >= _filterRating!)
          .toList();
    }

    return filtered;
  }

  Widget _buildStats(ObservationLogStats stats, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _StatChip(
            label: 'Total',
            value: '${stats.totalObservations}',
          ),
          const SizedBox(width: 16),
          _StatChip(
            label: 'Objects',
            value: '${stats.uniqueObjects}',
          ),
          const SizedBox(width: 16),
          _StatChip(
            label: 'Avg Rating',
            value: stats.averageRating > 0
                ? stats.averageRating.toStringAsFixed(1)
                : '-',
          ),
          if (stats.firstObservation != null) ...[
            const SizedBox(width: 16),
            _StatChip(
              label: 'Since',
              value: _formatDate(stats.firstObservation!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogEntry(ObservationLogEntry log, NightshadeColors colors) {
    final isDeleting = _deletingLogIds.contains(log.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date/time
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(log.timestamp),
                  style: NightshadeTypography.h6
                      .copyWith(color: colors.textPrimary),
                ),
                Text(
                  _formatTime(log.timestamp),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Object info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      log.objectName,
                      style: NightshadeTypography.h5
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (log.catalogId != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: NightshadeDecorations.statusChip(
                          colors.primary,
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
                          bordered: false,
                        ),
                        child: Text(
                          log.catalogId!,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (log.objectType != null) ...[
                      Text(
                        log.objectType!,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (log.altitude != null)
                      Text(
                        'Alt: ${log.altitude!.toStringAsFixed(1)}°',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textSecondary,
                        ),
                      ),
                    if (log.seeingConditions != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Seeing: ${log.seeingConditions}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (log.notes != null && log.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    log.notes!,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textPrimary.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Rating
          if (log.rating != null) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return Icon(
                  LucideIcons.star,
                  size: 14,
                  color: i < log.rating!
                      ? colors.warning
                      : colors.textSecondary.withValues(alpha: 0.2),
                );
              }),
            ),
          ],

          // Delete button
          const SizedBox(width: 8),
          IconButton(
            icon: isDeleting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(LucideIcons.trash2, size: 16, color: colors.error),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: isDeleting ? null : () => _confirmDelete(log),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ObservationLogEntry log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Observation'),
        content: Text('Delete observation of ${log.objectName}?'),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
      ),
    );

    if (confirmed != true || _deletingLogIds.contains(log.id)) return;

    final backendAtStart = ref.read(backendProvider);
    setState(() => _deletingLogIds.add(log.id));
    try {
      final deleted = await ref
          .read(observationLogNotifierProvider.notifier)
          .deleteLog(log.id);
      if (!mounted || deleted) return;

      final message = !identical(ref.read(backendProvider), backendAtStart)
          ? 'Delete cancelled because the imaging host changed.'
          : ref.read(observationLogNotifierProvider).errorMessage ??
              'Could not delete the observation.';
      context.showErrorSnackBar(message);
    } finally {
      if (mounted) {
        setState(() => _deletingLogIds.remove(log.id));
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    if (_isExporting) return;

    final backendAtStart = ref.read(backendProvider);
    setState(() => _isExporting = true);
    try {
      final csv =
          await ref.read(observationLogNotifierProvider.notifier).exportCsv();
      if (csv == null || csv.isEmpty) {
        if (!context.mounted) return;

        final error = ref.read(observationLogNotifierProvider).errorMessage;
        if (!identical(ref.read(backendProvider), backendAtStart)) {
          context.showErrorSnackBar(
            'Export cancelled because the imaging host changed.',
          );
        } else if (error != null) {
          context.showErrorSnackBar(error);
        } else {
          context.showInfoSnackBar('No observations to export.');
        }
        return;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final exportDir =
          Directory(p.join(docsDir.path, 'Nightshade', 'exports'));
      await exportDir.create(recursive: true);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(exportDir.path, 'observations_$timestamp.csv'));
      await file.writeAsString(csv);

      if (context.mounted) {
        // Share on mobile (app-docs is otherwise unreachable); path on desktop.
        await revealExportedFile(
          context,
          file.path,
          subject: 'Nightshade observation log',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
