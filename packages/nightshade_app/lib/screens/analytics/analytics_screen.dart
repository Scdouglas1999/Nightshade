// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../localization/nightshade_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/analytics_keys.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../sequencer/widgets/session_report_dialog.dart';
import 'widgets/science_export_hub.dart';
import 'widgets/session_chart.dart';
import 'widgets/image_thumbnail_strip.dart';
import 'widgets/project_tracking_panel.dart';
import 'widgets/science_analytics_tab.dart';
part 'analytics_screen/session_tab.dart';
part 'analytics_screen/history_tab.dart';
part 'analytics_screen/history_cards.dart';
part 'analytics_screen/session_detail_dialog.dart';
part 'analytics_screen/equipment_stats.dart';
part 'analytics_screen/skeletons.dart';

/// Identifies an Analytics sub-tab for deep-linking via `?tab=` query param.
/// Order here matches the rendered tab order â€” Diagnostics is right-most.
enum AnalyticsTab {
  session,
  history,
  projects,
  equipment,
  science,
  diagnostics,
}

/// Maps the router `?tab=` query value to an [AnalyticsTab]. Returns null
/// for an unrecognised value so the caller can decide on a fallback. Public
/// so router code (and tests) can share the same canonical mapping.
AnalyticsTab? analyticsTabFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'session':
      return AnalyticsTab.session;
    case 'history':
      return AnalyticsTab.history;
    case 'projects':
      return AnalyticsTab.projects;
    case 'equipment':
    case 'equipment-stats':
    case 'equipmentstats':
      return AnalyticsTab.equipment;
    case 'science':
      return AnalyticsTab.science;
    case 'diagnostics':
      return AnalyticsTab.diagnostics;
  }
  return null;
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  /// Optional initial tab selection. When null, falls back to
  /// [initialTabQuery] parsing, then to [AnalyticsTab.session].
  final AnalyticsTab? initialTab;

  /// Raw `?tab=` value parsed from the router. Lets deep-links select a
  /// specific Analytics tab (notably `?tab=diagnostics` from the legacy
  /// `/diagnostics` redirect).
  final String? initialTabQuery;

  const AnalyticsScreen({
    super.key,
    this.initialTab,
    this.initialTabQuery,
  });

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late int _currentSubTab;

  @override
  void initState() {
    super.initState();
    final resolved = widget.initialTab ??
        analyticsTabFromQuery(widget.initialTabQuery) ??
        AnalyticsTab.session;
    _currentSubTab = resolved.index;
  }

  List<String> _tabs(BuildContext context) {
    final l10n = context.l10n;
    return [
      l10n.text('analyticsSession'),
      l10n.text('analyticsHistory'),
      l10n.text('analyticsProjects'),
      l10n.text('analyticsEquipmentStats'),
      l10n.text('analyticsScience'),
      l10n.text('analyticsDiagnostics'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
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
                  if (_currentSubTab == AnalyticsTab.science.index) ...[
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

            // Content. Order must match the AnalyticsTab enum.
            Expanded(
              child: IndexedStack(
                index: _currentSubTab,
                children: const [
                  _SessionTab(),
                  _HistoryTab(),
                  _ProjectsTab(),
                  _EquipmentStatsTab(),
                  ScienceAnalyticsTab(),
                  DiagnosticsTabContent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
