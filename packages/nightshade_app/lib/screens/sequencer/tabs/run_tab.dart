import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sequencer_screen.dart' show sequencerTabProvider;
import '../widgets/run_dashboard/critical_event_banner.dart';
import '../widgets/run_dashboard/customize_menu.dart';
import '../widgets/run_dashboard/equipment_telemetry_panel.dart';
import '../widgets/run_dashboard/exposure_progress_panel.dart';
import '../widgets/run_dashboard/filter_integration_panel.dart';
import '../widgets/run_dashboard/guiding_panel_card.dart';
import '../widgets/run_dashboard/live_frame_panel.dart';
import '../widgets/run_dashboard/playback_footer.dart';
import '../widgets/run_dashboard/run_dashboard_prefs.dart';
import '../widgets/run_dashboard/run_dashboard_providers.dart';
import '../widgets/run_dashboard/session_warnings_panel.dart';
import '../widgets/run_dashboard/target_header_panel.dart';
import '../widgets/run_dashboard/trigger_feed_panel.dart';
import '../widgets/run_dashboard/weather_safety_card.dart';
import 'history_tab.dart' show historyOpenRunIdProvider;

/// "Run" dashboard tab — one-glance, read-only view of an in-progress
/// imaging session.
///
/// Layout:
///   * Wide (>= desktop breakpoint): 3-column grid (telemetry, frame +
///     progress, guiding + weather + feed) with a header above and a
///     playback footer below.
///   * Mobile (< 768px): single vertically-stacked column with the
///     identical panels, breakpoint-matched against the Builder tab
///     (`_NarrowDesktopLayout` / `_MobileBuilderLayout`).
///
/// All panel visibility is toggleable via the top-right Customize menu
/// (persisted by `runDashboardPrefsProvider`).
class RunTab extends ConsumerWidget {
  const RunTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final executionState = ref.watch(sequenceExecutionStateProvider);

    // Activate the critical-event bridge. The provider has no value but
    // its build subscribes to the executor's event history and forwards
    // critical entries to the dashboard banner + in-app notifications.
    // Watching it here is what keeps it alive while the dashboard is
    // visible. If the user navigates away the bridge will tear down with
    // the provider scope.
    ref.watch(runDashboardCriticalEventsBridgeProvider);

    if (executionState == SequenceExecutionState.idle) {
      return _IdleState(colors: colors);
    }

    final isMobile = Responsive.isMobile(context);
    return Column(
      children: [
        // Critical event banner — pinned above the header so the
        // operator sees it regardless of which panels are visible.
        const RunDashboardCriticalBanner(),
        _DashboardHeaderBar(colors: colors),
        Expanded(
          child: isMobile
              ? const _MobileBody()
              : const _WideBody(),
        ),
        const RunDashboardPlaybackFooter(),
      ],
    );
  }
}

class _DashboardHeaderBar extends ConsumerWidget {
  final NightshadeColors colors;
  const _DashboardHeaderBar({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runDashboardPrefsProvider).valueOrNull ??
        RunDashboardPrefs.defaults();
    final showTarget = prefs.isVisible(RunDashboardPanelId.targetHeader);

    return Container(
      color: colors.surface,
      child: Stack(
        children: [
          if (showTarget) const RunDashboardTargetHeader(),
          if (!showTarget)
            Container(
              height: 12,
              color: colors.surface,
            ),
          const Positioned(
            top: 4,
            right: 4,
            child: Row(
              children: [
                RunDashboardCustomizeMenu(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleState extends ConsumerWidget {
  final NightshadeColors colors;
  const _IdleState({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull the most recent completed (or aborted) run if one exists so we
    // can offer a "Jump to last run in History" affordance. We don't need
    // a stream here — runs change rarely and we re-watch each rebuild.
    final runsAsync = ref.watch(sequenceRunsProvider);
    SequenceRun? mostRecent;
    final runs = runsAsync.valueOrNull;
    if (runs != null) {
      for (final r in runs) {
        // sequenceRunsProvider returns newest-first ordered.
        mostRecent = r;
        break;
      }
    }

    final actionRow = Wrap(
      alignment: WrapAlignment.center,
      spacing: NightshadeTokens.spaceMd,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        ElevatedButton.icon(
          onPressed: () =>
              ref.read(sequencerTabProvider.notifier).state = 0,
          icon: const Icon(LucideIcons.workflow, size: 16),
          label: const Text('Go to Builder'),
        ),
        if (mostRecent != null)
          OutlinedButton.icon(
            onPressed: () {
              // Set the hint first so HistoryTab's first build reads it
              // and schedules the post-session dialog.
              ref.read(historyOpenRunIdProvider.notifier).state =
                  mostRecent!.id;
              // History tab is index 5 in the sequencer's TabController
              // (Builder=0, Run=1, Targets=2, Templates=3, Library=4,
              // History=5). Keep this in sync with sequencer_screen.dart.
              ref.read(sequencerTabProvider.notifier).state = 5;
            },
            icon: const Icon(LucideIcons.history, size: 16),
            label: Text('Open last run · ${mostRecent.sequenceName}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textSecondary,
              side: BorderSide(color: colors.border),
            ),
          ),
      ],
    );

    return Center(
      child: EmptyState(
        icon: LucideIcons.activity,
        title: 'No sequence running',
        body: 'Open the Builder tab and press Start to begin imaging.\n'
            'Once a run is underway, this view shows live progress, frames, '
            'guiding, and safety status.',
        action: actionRow,
      ),
    );
  }
}

/// Wide (desktop) layout: three columns with the same panel ordering
/// the spec calls for.
class _WideBody extends ConsumerWidget {
  const _WideBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runDashboardPrefsProvider).valueOrNull ??
        RunDashboardPrefs.defaults();

    final left = <Widget>[
      if (prefs.isVisible(RunDashboardPanelId.equipmentTelemetry))
        const RunDashboardEquipmentPanel(),
    ];
    final center = <Widget>[
      if (prefs.isVisible(RunDashboardPanelId.liveFrame))
        const RunDashboardLiveFrame(),
      if (prefs.isVisible(RunDashboardPanelId.exposureProgress))
        const RunDashboardExposureProgress(),
      if (prefs.isVisible(RunDashboardPanelId.filterIntegration))
        const RunDashboardFilterIntegration(),
    ];
    final right = <Widget>[
      if (prefs.isVisible(RunDashboardPanelId.guidingGraph))
        const RunDashboardGuidingCard(),
      if (prefs.isVisible(RunDashboardPanelId.weatherSafety))
        const RunDashboardWeatherSafetyCard(),
      // Session warnings sit between safety and the trigger feed so a
      // user scanning the right column sees: "weather safe → warnings
      // accumulated this run → live event feed".
      const RunDashboardSessionWarningsPanel(),
      if (prefs.isVisible(RunDashboardPanelId.triggerFeed))
        const RunDashboardTriggerFeed(),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _PanelColumn(children: left),
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          Expanded(
            flex: 4,
            child: _PanelColumn(children: center),
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          Expanded(
            flex: 3,
            child: _PanelColumn(children: right),
          ),
        ],
      ),
    );
  }
}

class _MobileBody extends ConsumerWidget {
  const _MobileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runDashboardPrefsProvider).valueOrNull ??
        RunDashboardPrefs.defaults();

    final all = <Widget>[
      if (prefs.isVisible(RunDashboardPanelId.liveFrame))
        const RunDashboardLiveFrame(),
      if (prefs.isVisible(RunDashboardPanelId.exposureProgress))
        const RunDashboardExposureProgress(),
      if (prefs.isVisible(RunDashboardPanelId.equipmentTelemetry))
        const RunDashboardEquipmentPanel(),
      if (prefs.isVisible(RunDashboardPanelId.filterIntegration))
        const RunDashboardFilterIntegration(),
      if (prefs.isVisible(RunDashboardPanelId.guidingGraph))
        const RunDashboardGuidingCard(),
      if (prefs.isVisible(RunDashboardPanelId.weatherSafety))
        const RunDashboardWeatherSafetyCard(),
      const RunDashboardSessionWarningsPanel(),
      if (prefs.isVisible(RunDashboardPanelId.triggerFeed))
        const RunDashboardTriggerFeed(),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: _PanelColumn(children: all),
    );
  }
}

/// Internal: vertical stack with consistent spacing between panels.
class _PanelColumn extends StatelessWidget {
  final List<Widget> children;

  const _PanelColumn({required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const SizedBox(height: NightshadeTokens.spaceLg),
        ],
      ],
    );
  }
}
