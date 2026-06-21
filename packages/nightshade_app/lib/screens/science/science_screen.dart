import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import '../analytics/widgets/science_analytics_tab.dart';
import '../analytics/widgets/science_export_hub.dart';
import '../first_light/first_light_view.dart';
import '../transients/transients_screen.dart';

/// Identifies a Science sub-tab for deep-linking via `?tab=`/`?view=` query.
enum ScienceTab {
  workspace,
  firstLight,
  transients,
}

/// Maps the router `?tab=`/`?view=` query value to a [ScienceTab]. Returns null
/// for an unrecognised value so the caller can fall back. Public so router code
/// can share the same canonical mapping (notably `view=transients` from the
/// legacy `/transients` redirect).
ScienceTab? scienceTabFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'workspace':
      return ScienceTab.workspace;
    case 'firstlight':
    case 'first_light':
    case 'discovery':
      return ScienceTab.firstLight;
    case 'transients':
    case 'alerts':
      return ScienceTab.transients;
  }
  return null;
}

/// Scaffold-free science workspace body: the photometry / first-light /
/// observing-alerts tab host. Folded into Analytics → Science (`showHeader:
/// false`), and also wrapped by [ScienceScreen] for the redirected standalone
/// `/science` route. When embedded, the screen-level header is suppressed and the
/// per-tab actions (export, alert refresh/settings) ride a slim toolbar beside
/// the sub-tab bar, since Analytics owns the outer chrome.
class ScienceWorkspaceView extends ConsumerStatefulWidget {
  /// Selects the initial sub-tab (workspace / first light / observing alerts).
  final String? initialViewQuery;

  /// When true, renders the standalone [ScreenHeader] with the actions in its
  /// trailing slot. When false (embedded in Analytics), the header is omitted
  /// and the actions sit inline with the sub-tab bar.
  final bool showHeader;

  const ScienceWorkspaceView({
    super.key,
    this.initialViewQuery,
    this.showHeader = true,
  });

  @override
  ConsumerState<ScienceWorkspaceView> createState() =>
      _ScienceWorkspaceViewState();
}

class _ScienceWorkspaceViewState extends ConsumerState<ScienceWorkspaceView> {
  late int _currentSubTab;

  @override
  void initState() {
    super.initState();
    final resolved =
        scienceTabFromQuery(widget.initialViewQuery) ?? ScienceTab.workspace;
    _currentSubTab = resolved.index;
  }

  @override
  void didUpdateWidget(ScienceWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host (Analytics / Science route) keys pages by path, not query, so a
    // new `?view=` while already mounted reuses this State without re-running
    // initState. Re-resolve so deep-links (notably the /transients alert link)
    // select the target sub-tab.
    if (widget.initialViewQuery != oldWidget.initialViewQuery) {
      final resolved = scienceTabFromQuery(widget.initialViewQuery);
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
        label: 'First Light',
        icon: LucideIcons.sparkles,
      ),
      const AdaptiveTab(
        label: 'Observing Alerts',
        icon: LucideIcons.satellite,
      ),
    ];
  }

  /// The per-tab action affordances: alert refresh/settings (transients sub-tab
  /// only) plus the always-present science export hub. Shared by the standalone
  /// header trailing slot and the embedded inline toolbar.
  List<Widget> _actions(BuildContext context, NightshadeColors colors) {
    return [
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;

    final tabBar = AdaptiveTabBar(
      tabs: _tabs(context),
      selectedIndex: _currentSubTab,
      onSelected: (index) => setState(() => _currentSubTab = index),
    );

    return Column(
      children: [
        if (widget.showHeader)
          ScreenHeader(
            icon: LucideIcons.flaskConical,
            title: l10n.text('analyticsScience'),
            padding: const EdgeInsets.all(NightshadeTokens.spaceXl),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: _actions(context, colors),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          // Embedded in Analytics the screen header is gone, so the per-tab
          // actions ride inline at the end of the sub-tab bar instead.
          child: widget.showHeader
              ? tabBar
              : Row(
                  children: [
                    Expanded(child: tabBar),
                    ..._actions(context, colors),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                  ],
                ),
        ),
        Expanded(
          child: IndexedStack(
            index: _currentSubTab,
            children: const [
              ScienceAnalyticsTab(),
              FirstLightView(showHeader: false),
              TransientsView(showHeader: false),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thin Scaffold wrapper kept for the redirected standalone `/science` route.
/// The reusable body lives in [ScienceWorkspaceView], also hosted by
/// Analytics → Science.
class ScienceScreen extends StatelessWidget {
  final String? initialTabQuery;

  const ScienceScreen({super.key, this.initialTabQuery});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NightshadeColors.of(context).background,
      body: ScienceWorkspaceView(initialViewQuery: initialTabQuery),
    );
  }
}
