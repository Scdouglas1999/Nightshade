import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart'
    show IosBackgroundBanner, ConnectionStaleBanner;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'tabs/camera_tab.dart';
import 'tabs/devices_tab.dart';
import 'tabs/log_tab.dart';
import 'tabs/mount_tab.dart';
import 'tabs/sequencer_tab.dart';
import 'tabs/settings_tab.dart';

/// Phone-tailored landing screen (audit §3.5).
///
/// The pre-existing `NightshadeApp(isMobile: true)` shrinks the desktop UI
/// to fit a phone screen, which leaves tap targets below the 44 pt minimum
/// and crams 16-column dashboards into 360 px viewports. This dashboard is
/// the phone-native alternative: five bottom tabs, each full-viewport,
/// reading from the same `nightshade_core` providers as the desktop UI so
/// behaviour stays in lock-step.
///
/// Tablet (>= 768 px) routing intentionally keeps the desktop UI — the
/// extra real estate is enough that the cramming problem doesn't apply and
/// the multi-pane layouts are more useful than tabs.
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
    _DashboardTab(
      icon: LucideIcons.cpu,
      label: 'Devices',
      child: DevicesTab(),
    ),
    _DashboardTab(
      icon: LucideIcons.move,
      label: 'Mount',
      child: MountTab(),
    ),
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
      icon: LucideIcons.scrollText,
      label: 'Log',
      child: LogTab(),
    ),
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
              children: [
                for (final t in _tabs) t.child,
              ],
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
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                color: tint,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
