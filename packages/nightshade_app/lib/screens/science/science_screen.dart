import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import '../analytics/widgets/science_analytics_tab.dart';
import '../analytics/widgets/science_export_hub.dart';
import '../transients/transients_screen.dart';

/// Identifies a Science sub-tab for deep-linking via `?tab=` query param.
enum ScienceTab {
  workspace,
  transients,
}

/// Maps the router `?tab=` query value to a [ScienceTab]. Returns null for an
/// unrecognised value so the caller can fall back. Public so router code can
/// share the same canonical mapping (notably `?tab=transients` from the legacy
/// `/transients` redirect).
ScienceTab? scienceTabFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'workspace':
      return ScienceTab.workspace;
    case 'transients':
    case 'alerts':
      return ScienceTab.transients;
  }
  return null;
}

class ScienceScreen extends ConsumerStatefulWidget {
  final String? initialTabQuery;

  const ScienceScreen({super.key, this.initialTabQuery});

  @override
  ConsumerState<ScienceScreen> createState() => _ScienceScreenState();
}

class _ScienceScreenState extends ConsumerState<ScienceScreen> {
  late int _currentSubTab;

  @override
  void initState() {
    super.initState();
    final resolved =
        scienceTabFromQuery(widget.initialTabQuery) ?? ScienceTab.workspace;
    _currentSubTab = resolved.index;
  }

  @override
  void didUpdateWidget(ScienceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router keys pages by path, not query, so navigating to a different
    // `?tab=` while this screen is already mounted reuses this State without
    // re-running initState. Re-resolve so deep-links (and the in-screen
    // "Observing alerts" nav card via /transients) select the target tab.
    if (widget.initialTabQuery != oldWidget.initialTabQuery) {
      final resolved = scienceTabFromQuery(widget.initialTabQuery);
      if (resolved != null && resolved.index != _currentSubTab) {
        setState(() => _currentSubTab = resolved.index);
      }
    }
  }

  List<AdaptiveTab> _tabs(BuildContext context) {
    final l10n = context.l10n;
    return [
      AdaptiveTab(
        label: l10n.text('analyticsScience'),
        icon: LucideIcons.flaskConical,
      ),
      const AdaptiveTab(
        label: 'Observing Alerts',
        icon: LucideIcons.satellite,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          ScreenHeader(
            icon: LucideIcons.flaskConical,
            title: l10n.text('analyticsScience'),
            padding: const EdgeInsets.all(NightshadeTokens.spaceXl),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_currentSubTab == ScienceTab.transients.index) ...[
                  IconButton(
                    icon: Icon(
                      NightshadeIcons.refresh,
                      size: NightshadeTokens.iconMd,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => refreshTransientAlerts(ref),
                    tooltip: 'Refresh alerts',
                    constraints: const BoxConstraints(
                      minWidth: NightshadeTokens.minTouchTarget,
                      minHeight: NightshadeTokens.minTouchTarget,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      NightshadeIcons.settings,
                      size: NightshadeTokens.iconMd,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => showTransientSettingsDialog(context, ref),
                    tooltip: 'Alert settings',
                    constraints: const BoxConstraints(
                      minWidth: NightshadeTokens.minTouchTarget,
                      minHeight: NightshadeTokens.minTouchTarget,
                    ),
                  ),
                ],
                Tooltip(
                  message: 'Export science data',
                  child: IconButton(
                    icon: Icon(
                      LucideIcons.database,
                      size: NightshadeTokens.iconMd,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ScienceExportHub(),
                    ),
                    padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
                    constraints: const BoxConstraints(
                      minWidth: NightshadeTokens.minTouchTarget,
                      minHeight: NightshadeTokens.minTouchTarget,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: AdaptiveTabBar(
              tabs: _tabs(context),
              selectedIndex: _currentSubTab,
              onSelected: (index) => setState(() => _currentSubTab = index),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentSubTab,
              children: const [
                ScienceAnalyticsTab(),
                TransientsView(showHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
