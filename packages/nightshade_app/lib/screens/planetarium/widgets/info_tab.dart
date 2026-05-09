import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'sidebar_shared_widgets.dart';

class InfoTab extends ConsumerWidget {
  final NightshadeColors colors;
  final SelectedObjectState selectedObject;

  const InfoTab({
    super.key,
    required this.colors,
    required this.selectedObject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedObject.object == null && selectedObject.coordinates == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.info, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Select an object',
              style: TextStyle(color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Click on the sky to select',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    final obj = selectedObject.object;

    // If we have a celestial object, use the ObjectDetailsPanel + imaging history
    if (obj != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: ObjectDetailsPanel(
          object: obj,
          backgroundColor: colors.surfaceAlt,
          textColor: colors.textPrimary,
          accentColor: colors.accent,
          showVisibilityGraph: true,
          cloudCoverPercent:
              ref.watch(cloudCoverPercentageProvider).valueOrNull,
          extraContent: ImagingHistorySection(
            object: obj,
            colors: colors,
          ),
          onGoTo: () {
            final coords = obj.coordinates;
            ref.read(mountCommandServiceProvider).slewTo(coords.ra, coords.dec);
          },
          onAddToTargets: () {
            final coords = obj.coordinates;
            ref.read(currentSequenceProvider.notifier).addTargetHeader(
                  TargetHeaderNode(
                    targetName: obj.name,
                    raHours: coords.ra,
                    decDegrees: coords.dec,
                  ),
                );
            context.showSuccessSnackBar('Added ${obj.name} to sequence');
          },
        ),
      );
    }

    // Fallback for coordinates-only selection (rare case)
    final coords = selectedObject.coordinates;
    final altAz = selectedObject.currentAltAz;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected Coordinates',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Coordinates',
            icon: LucideIcons.compass,
            color: colors.info,
            colors: colors,
            child: Column(
              children: [
                if (coords != null) ...[
                  InfoRow(
                      label: 'RA',
                      value: coords
                          .toString()
                          .split(',')[0]
                          .replaceAll('RA: ', ''),
                      colors: colors),
                  InfoRow(
                      label: 'Dec',
                      value: coords
                          .toString()
                          .split(',')[1]
                          .replaceAll(' Dec: ', ''),
                      colors: colors),
                ],
                if (altAz != null) ...[
                  InfoRow(
                    label: 'Altitude',
                    value: '${altAz.$1.toStringAsFixed(1)}\u00b0',
                    colors: colors,
                    valueColor: altAz.$1 > 30
                        ? colors.success
                        : altAz.$1 > 0
                            ? colors.warning
                            : colors.error,
                  ),
                  InfoRow(
                      label: 'Azimuth',
                      value: '${altAz.$2.toStringAsFixed(1)}\u00b0',
                      colors: colors),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows imaging history for a celestial object, queried from the local database.
class ImagingHistorySection extends ConsumerWidget {
  final CelestialObject object;
  final NightshadeColors colors;

  const ImagingHistorySection({
    super.key,
    required this.object,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ImagingHistoryQuery(
      objectName: object.name,
      raHours: object.coordinates.ra,
      decDegrees: object.coordinates.dec,
    );

    final historyAsync = ref.watch(imagingHistoryProvider(query));

    return historyAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Failed to load imaging history: $error',
          style: TextStyle(color: colors.error, fontSize: 12),
        ),
      ),
      data: (history) {
        if (!history.hasData) {
          return _buildNoDataSection();
        }
        return _buildHistorySection(history);
      },
    );
  }

  Widget _buildNoDataSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.textMuted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(LucideIcons.camera, size: 14, color: colors.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No imaging data',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ImagingHistory history) {
    final totalHours = history.totalIntegrationSecs / 3600.0;
    final totalMinutes = (history.totalIntegrationSecs / 60.0).round();

    // Format total integration nicely.
    String integrationStr;
    if (totalHours >= 1.0) {
      final h = totalHours.floor();
      final m = ((totalHours - h) * 60).round();
      integrationStr = '${h}h ${m}m';
    } else {
      integrationStr = '${totalMinutes}m';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child:
                    Icon(LucideIcons.camera, size: 14, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Imaging History',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary stats row
          Row(
            children: [
              _buildStatChip(
                label: 'Integration',
                value: integrationStr,
                icon: LucideIcons.clock,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                label: 'Sessions',
                value: history.sessionCount.toString(),
                icon: LucideIcons.calendar,
              ),
            ],
          ),

          // Completion bar (if goal is set)
          if (history.hasGoal) ...[
            const SizedBox(height: 12),
            _buildCompletionBar(history),
          ],

          // Last imaged
          if (history.lastImaged != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.clock3, size: 12, color: colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Last imaged: ${DateFormat('MMM d, yyyy').format(history.lastImaged!.toLocal())}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          // Per-filter breakdown
          if (history.filterCounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Per-Filter Breakdown',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...history.filterCounts.entries.map((entry) {
              final filterSecs =
                  history.filterIntegrationSecs[entry.key] ?? 0.0;
              return _buildFilterRow(
                filterName: entry.key,
                frameCount: entry.value,
                integrationSecs: filterSecs,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: colors.textMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionBar(ImagingHistory history) {
    final pct = (history.completionFraction * 100).round();
    final goalHours = history.goalIntegrationSecs / 3600.0;

    Color barColor;
    if (history.completionFraction >= 1.0) {
      barColor = colors.success;
    } else if (history.completionFraction > 0.5) {
      barColor = colors.primary;
    } else {
      barColor = colors.warning;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Completion',
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
            Text(
              '$pct% of ${goalHours.toStringAsFixed(1)}h goal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: barColor,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: history.completionFraction,
              backgroundColor: colors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow({
    required String filterName,
    required int frameCount,
    required double integrationSecs,
  }) {
    String integStr;
    if (integrationSecs >= 3600) {
      final h = (integrationSecs / 3600).floor();
      final m = ((integrationSecs % 3600) / 60).round();
      integStr = '${h}h ${m}m';
    } else {
      integStr = '${(integrationSecs / 60).round()}m';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _filterColor(filterName),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filterName,
              style: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            '$frameCount subs',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(
              integStr,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Color for common astrophotography filter names.
  Color _filterColor(String name) {
    final lower = name.toLowerCase();
    if (lower == 'l' || lower == 'luminance' || lower == 'lum') {
      return Colors.white70;
    } else if (lower == 'r' || lower == 'red') {
      return Colors.red;
    } else if (lower == 'g' || lower == 'green') {
      return Colors.green;
    } else if (lower == 'b' || lower == 'blue') {
      return Colors.blue;
    } else if (lower == 'ha' || lower.contains('alpha')) {
      return Colors.redAccent;
    } else if (lower == 'oiii' || lower.contains('oxygen')) {
      return Colors.tealAccent;
    } else if (lower == 'sii' ||
        lower.contains('sulphur') ||
        lower.contains('sulfur')) {
      return Colors.orangeAccent;
    } else {
      return Colors.purple;
    }
  }
}
