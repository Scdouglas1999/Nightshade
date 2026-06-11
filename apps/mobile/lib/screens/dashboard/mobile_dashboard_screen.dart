import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart'
    show IosBackgroundBanner, ConnectionStaleBanner;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/network_status_indicator.dart';
import '../../widgets/phone_battery_indicator.dart';
import '../replay/session_picker_screen.dart';
import '../servers/saved_servers_screen.dart';
import '../setup/first_run_setup_screen.dart';
import 'tabs/camera_tab.dart';
import 'tabs/devices_tab.dart';
import 'tabs/log_tab.dart';
import 'tabs/mount_tab.dart';
import 'tabs/science_tab.dart';
import 'tabs/sequencer_tab.dart';
import 'tabs/settings_tab.dart';

/// Ops-only companion landing screen (legacy tabbed UI).
///
/// Default mobile routing uses `NightshadeApp(isMobile: true)` so phones get
/// the same GoRouter screens as desktop/tablet remote clients. Enable this
/// dashboard with `NIGHTSHADE_COMPANION_UI=1` for field-ops workflows that
/// prefer the bottom-tab layout.
class MobileDashboardScreen extends ConsumerStatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  ConsumerState<MobileDashboardScreen> createState() =>
      _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends ConsumerState<MobileDashboardScreen> {
  int _currentIndex = 0;

  // We use an IndexedStack so each tab keeps its widget state when the
  // user switches away (Mount d-pad keeps slew speed, Log keeps filters,
  // etc.). The tabs also stay subscribed to their providers so background
  // updates land without rebuilding from scratch on every switch.
  static const _tabs = <_DashboardTab>[
    _DashboardTab(icon: LucideIcons.cpu, label: 'Devices', child: DevicesTab()),
    _DashboardTab(icon: LucideIcons.move, label: 'Mount', child: MountTab()),
    _DashboardTab(
      icon: LucideIcons.camera,
      label: 'Camera',
      child: CameraTab(),
    ),
    _DashboardTab(
      icon: LucideIcons.play,
      label: 'Sequencer',
      child: SequencerTab(),
    ),
    _DashboardTab(
      icon: LucideIcons.flaskConical,
      label: 'Science',
      child: ScienceTab(),
    ),
    _DashboardTab(icon: LucideIcons.scrollText, label: 'Log', child: LogTab()),
    _DashboardTab(
      icon: LucideIcons.settings,
      label: 'Settings',
      child: SettingsTab(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Wire the global error-event bridge so toast notifications keep
    // firing on this screen (matches the AppShell behaviour for the
    // tablet path). Without this watch, errors emitted by Rust never
    // surface as SnackBars on a phone session.
    ref.watch(errorNotificationBridgeProvider);

    // first-run-setup gate. The async detection
    // provider returns `FirstRunSetupNeeds.none` when the wizard has
    // already been completed (or the server is fully configured); we
    // intercept here so the wizard appears AFTER pairing succeeds and
    // BEFORE the dashboard renders. Once the user completes (or skips)
    // the wizard it sets the latch and invalidates the provider so this
    // branch falls through on the next build.
    final setupNeedsAsync = ref.watch(shouldRunFirstRunSetupProvider);
    final setupNeeds = setupNeedsAsync.valueOrNull;
    if (setupNeeds != null && setupNeeds.hasAnyMissing) {
      return FirstRunSetupScreen(
        needs: setupNeeds,
        onCompleted: () {
          // The wizard already invalidated the provider — a setState
          // here re-pulls the dashboard once the async re-resolves.
          if (mounted) setState(() {});
        },
      );
    }

    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final tab = _tabs[_currentIndex];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(tab.icon, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          // phone battery + power-saving badge.
          // Sits left of the network indicator so the operator sees
          // {battery, network} as a single status cluster. Hidden until
          // the OS delivers the first sample so the layout doesn't flash.
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: PhoneBatteryIndicator(compact: true),
          ),
          // Persistent connection-state indicator (audit bug 5).
          // Renders compact in the AppBar action slot so it stays visible
          // across all 7 dashboard tabs without eating title space. Tap
          // opens the details sheet with the "Reconnect now" button.
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: NetworkStatusIndicator(compact: true),
          ),
          // multi-server roaming entry point. Single overflow
          // item rather than a bottom-tab slot because the saved-servers
          // screen is a modal task (open it, switch rig, get back to the
          // dashboard) — not a parallel surface like Devices/Mount.
          PopupMenuButton<_OverflowAction>(
            icon: Icon(LucideIcons.moreVertical, color: colors.textPrimary),
            tooltip: 'More',
            onSelected: (action) {
              switch (action) {
                case _OverflowAction.savedServers:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavedServersScreen(),
                    ),
                  );
                  break;
                case _OverflowAction.sessionHistory:
                  // open the replay picker. Lives behind the
                  // overflow menu because replay is an audit / forensic
                  // action operators reach for occasionally, not a hot
                  // path that deserves a dedicated bottom-tab slot.
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionPickerScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _OverflowAction.savedServers,
                child: ListTile(
                  leading: Icon(LucideIcons.server),
                  title: Text('Saved servers'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _OverflowAction.sessionHistory,
                child: ListTile(
                  leading: Icon(LucideIcons.history),
                  title: Text('Session history / replay'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: Column(
        children: [
          // iOS background advisory must remain visible on every tab
          // because the warning is session-wide, not screen-local.
          const IosBackgroundBanner(),
          const ConnectionStaleBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [for (final t in _tabs) t.child],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _PhoneBottomNav(
        currentIndex: _currentIndex,
        tabs: _tabs,
        onSelected: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _DashboardTab {
  final IconData icon;
  final String label;
  final Widget child;

  const _DashboardTab({
    required this.icon,
    required this.label,
    required this.child,
  });
}

/// Overflow menu actions surfaced from the dashboard AppBar.
/// added `savedServers` so the operator can roam between paired rigs.
/// added `sessionHistory` for replay scrubber access.
enum _OverflowAction { savedServers, sessionHistory }

/// Bottom navigation bar tuned for the phone HIG: 48 dp minimum tap height
/// per slot, persistent icon + label, single accent for the active item.
///
/// We don't reuse `NightshadeBottomNavigation` from `nightshade_app`
/// because that widget is route-driven (it calls `context.go(route)`); the
/// dashboard is a single-route IndexedStack and instead wants an index
/// callback. Sharing the widget would force the dashboard into the
/// router-shell-per-tab pattern, which defeats the tab state-keeping.
class _PhoneBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<_DashboardTab> tabs;
  final ValueChanged<int> onSelected;

  const _PhoneBottomNav({
    required this.currentIndex,
    required this.tabs,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavSlot(
                    tab: tabs[i],
                    selected: i == currentIndex,
                    colors: colors,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final _DashboardTab tab;
  final bool selected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _NavSlot({
    required this.tab,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = selected ? colors.primary : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        // 64 dp height in parent + full slot width keeps the hit-box well
        // above 44 dp on every phone we ship to.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, size: 22, color: tint),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: tint,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
