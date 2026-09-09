import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'equipment_blocker_row.dart';

/// Retained so existing call sites and tests that toggle the old collapsible
/// panel still resolve. The side panel's System health block is always shown;
/// it is three key/value rows, not a section that needs opening.
final equipmentHealthExpandedProvider = StateProvider<bool>((ref) => false);

/// The System health block of the Equipment side panel: a [SectionTitle] with
/// the score chip, a [KeyValueList] of the facts behind it, and one row per
/// outstanding insight.
class EquipmentHealthPanel extends ConsumerWidget {
  const EquipmentHealthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final reportAsync = ref.watch(equipmentHealthReportProvider);
    final snapshots = ref.watch(deviceHealthSnapshotsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(
          icon: LucideIcons.activity,
          title: 'System health',
          trailing: _scoreChip(reportAsync),
        ),
        reportAsync.when(
          data: (report) => _body(colors, report, snapshots),
          // A score that has not arrived is not a score: the block says so in
          // its own rows rather than spinning a wheel in the side panel.
          loading: () => const KeyValueList(
            rows: [('Score', kReadoutUnknown)],
          ),
          error: (error, _) => EquipmentBlockerRow(
            toneColor: colors.error,
            title: 'Health is unavailable',
            detail: '$error',
            showDivider: false,
          ),
        ),
      ],
    );
  }

  Widget _scoreChip(AsyncValue<EquipmentHealthReport> reportAsync) {
    final report = reportAsync.valueOrNull;
    if (report == null) {
      return const NightshadeChip(label: kReadoutUnknown);
    }
    if (!report.assessed) {
      // No evidence is not evidence of health: a rig with no session history
      // and no connected devices must not be reported as a perfect 100.
      return const NightshadeChip(label: 'Not assessed');
    }
    final score = report.score.round();
    return NightshadeChip(
      label: '$score · ${_grade(report.score)}',
      tone: _tone(report.score),
    );
  }

  Widget _body(
    NightshadeColors colors,
    EquipmentHealthReport report,
    List<DeviceHealthSnapshot> snapshots,
  ) {
    final drops = snapshots.fold<int>(
      0,
      (sum, snapshot) => sum + snapshot.disconnectCountLast24h,
    );
    final healthy = snapshots.where((s) => s.isHealthy).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyValueList(
          rows: [
            (
              'Devices',
              snapshots.isEmpty
                  ? kReadoutUnknown
                  : '${snapshots.length} · $drops ${drops == 1 ? 'drop' : 'drops'}',
            ),
            (
              'Heartbeats',
              snapshots.isEmpty
                  ? kReadoutUnknown
                  : '$healthy of ${snapshots.length} healthy',
            ),
            (
              'Score',
              report.assessed ? '${report.score.round()}' : kReadoutUnknown,
            ),
          ],
        ),
        for (var i = 0; i < report.insights.length; i++)
          EquipmentBlockerRow(
            toneColor: _severityColor(report.insights[i].severity, colors),
            title: report.insights[i].title,
            detail: report.insights[i].message,
            showDivider: i < report.insights.length - 1,
          ),
      ],
    );
  }

  static Color _severityColor(
    EquipmentHealthSeverity severity,
    NightshadeColors colors,
  ) {
    return switch (severity) {
      EquipmentHealthSeverity.info => colors.info,
      EquipmentHealthSeverity.warning => colors.warning,
      EquipmentHealthSeverity.critical => colors.error,
    };
  }

  static ChipTone _tone(double score) {
    if (score >= _excellentFloor) return ChipTone.success;
    if (score >= _fairFloor) return ChipTone.warning;
    return ChipTone.error;
  }

  static String _grade(double score) {
    if (score >= _excellentFloor) return 'Excellent';
    if (score >= _goodFloor) return 'Good';
    if (score >= _fairFloor) return 'Fair';
    return 'Poor';
  }
}

/// Score floors for the health grade wording.
const double _excellentFloor = 90.0;
const double _goodFloor = 75.0;
const double _fairFloor = 60.0;
