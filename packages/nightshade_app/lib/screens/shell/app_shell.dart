import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/catalog_setup_dialog.dart';
import '../../widgets/onboarding_tour_replay_launcher.dart';
import '../../widgets/tutorial_overlay.dart';
import '../../widgets/mobile_sequence_overlay.dart';
import '../../widgets/running_sequence_mini_bar.dart';
import '../sequencer/sequencer_screen.dart' show kSequencerRoutePath;
import '../../widgets/notification_toast_overlay.dart';
import '../../widgets/autofocus_progress_overlay.dart';
import '../../widgets/connection_stale_banner.dart';
import '../../widgets/ios_background_banner.dart';
import '../../widgets/android_notifications_banner.dart';
import '../../widgets/weather/weather_alert_banner.dart';
import 'widgets/title_bar.dart';
import 'widgets/status_bar.dart';
import 'widgets/side_navigation.dart';
import 'shell_chrome.dart';
import 'shell_navigation.dart';
import 'immersive_chrome.dart';
import 'widgets/immersive_bottom_chrome.dart';
import 'widgets/nightshade_bottom_navigation.dart';

// Conditional import for window_manager (desktop only)
import 'app_shell_stub.dart' if (dart.library.io) 'app_shell_desktop.dart'
    as window_impl;

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _fallbackSideNavExpanded = true;
  bool _hasCheckedCatalogs = false;
  bool _hasCheckedCheckpoint = false;
  String? _lastImmersiveLocation;

  @override
  void initState() {
    super.initState();
    // Initialize window manager if on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      window_impl.initWindowManager(
        this,
        onCloseRequested: _onCloseRequested,
      );
    }
    // Check catalogs and checkpoint after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCatalogsIfNeeded();
      _checkCheckpointIfNeeded();
    });
  }

  /// Handle window close request - show confirmation if needed
  Future<bool> _onCloseRequested() async {
    final settings = ref.read(appSettingsProvider).valueOrNull;

    // If confirm before closing is disabled, allow close
    if (settings?.confirmBeforeClosing != true) {
      return true;
    }

    // Check if capture is in progress
    final sessionState = ref.read(sessionStateProvider);
    final isCapturing = sessionState.isCapturing;

    // If not capturing, allow close
    if (!isCapturing) {
      return true;
    }

    // Show confirmation dialog
    final shouldClose = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final colors = NightshadeColors.of(context);
        final l10n = context.l10n;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            l10n.text('closeNightshadeTitle'),
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            l10n.text('closeNightshadeBody'),
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: l10n.text('cancel'),
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(true),
              label: l10n.text('closeAnyway'),
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
            ),
          ],
        );
      },
    );

    return shouldClose ?? false;
  }

  @override
  void dispose() {
    // Dispose window manager if on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      window_impl.disposeWindowManager(this);
    }
    super.dispose();
  }

  Future<void> _checkCatalogsIfNeeded() async {
    if (_hasCheckedCatalogs) return;
    _hasCheckedCatalogs = true;

    try {
      final starStatus = await CatalogManager.instance.getStarCatalogStatus();
      final dsoStatus = await CatalogManager.instance.getDsoCatalogStatus();

      // If neither catalog is installed, show setup dialog
      if (!starStatus.isInstalled && !dsoStatus.isInstalled) {
        if (mounted) {
          await CatalogSetupDialog.show(context);
        }
      }
    } catch (e) {
      ref.read(loggingServiceProvider).warning(
          '[AppShell] Error checking catalog status: $e',
          source: 'AppShell',
          fields: {'error': e.toString()});
    }
  }

  Future<void> _checkCheckpointIfNeeded() async {
    if (_hasCheckedCheckpoint) return;
    _hasCheckedCheckpoint = true;

    try {
      final backend = ref.read(sequencerBackendProvider);

      // Initialize the checkpoint directory on desktop so checkpoints are
      // actually persisted this session. The desktop GUI never set it, so no
      // checkpoint was ever written and a mid-night crash was unrecoverable
      // (no resume banner, all sequence state lost). Mobile sets its own
      // checkpoint dir in its bootstrap, so restrict this to desktop to avoid
      // overriding the mobile path with a different directory.
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          await backend.sequencerSetCheckpointDir(supportDir.path);
        } catch (e) {
          ref.read(loggingServiceProvider).warning(
              '[AppShell] Failed to initialize checkpoint directory: $e',
              source: 'AppShell',
              fields: {'error': e.toString()});
        }
      }

      final hasCheckpoint = await backend.hasCheckpoint();
      if (!hasCheckpoint) return;

      final info = await backend.getCheckpointInfo();
      if (info == null || !info.canResume) return;

      if (!mounted) return;

      final colors = NightshadeColors.of(context);

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final ageMinutes = info.ageSeconds ~/ 60;
          final ageStr = ageMinutes < 60
              ? '${ageMinutes}m ago'
              : '${ageMinutes ~/ 60}h ${ageMinutes % 60}m ago';
          final integrationMins = (info.completedIntegrationSecs / 60).round();

          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: NightshadeTokens.borderRadiusInline8,
              side: BorderSide(color: colors.border),
            ),
            title: Row(
              children: [
                Icon(NightshadeIcons.warning, size: 22, color: colors.warning),
                const SizedBox(width: 12),
                Text(
                  'Recover Sequence?',
                  style: TextStyle(color: colors.textPrimary),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A previous sequence was interrupted and can be resumed.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13,
                  ),
                ),
                const SizedBox(height: 16),
                NightshadeCard(
                  variant: CardVariant.standard,
                  borderRadius: NightshadeTokens.radiusInline8,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _checkpointInfoRow(colors, 'Sequence', info.sequenceName),
                      const SizedBox(height: 6),
                      _checkpointInfoRow(colors, 'Saved', ageStr),
                      const SizedBox(height: 6),
                      _checkpointInfoRow(colors, 'Completed',
                          '${info.completedExposures} frames (${integrationMins}m integration)'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              NightshadeButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                label: 'Discard',
                variant: ButtonVariant.destructive,
              ),
              NightshadeButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: 'Resume',
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      if (result == true) {
        // Route through the SequenceExecutor provider — it re-seeds the
        // runtime config from current settings and issues the
        // sequencerStart() that actually begins execution. Calling the
        // backend's resumeFromCheckpoint() directly only prepares the
        // native tree and leaves the executor idle.
        await ref.read(sequenceExecutorProvider).resumeFromCheckpoint();
      } else {
        await backend.discardCheckpoint();
      }
    } catch (e) {
      ref.read(loggingServiceProvider).error(
          '[AppShell] Error checking checkpoint: $e',
          source: 'AppShell',
          fields: {'error': e.toString()});
    }
  }

  Widget _checkpointInfoRow(
      NightshadeColors colors, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style:
                NightshadeTypography.labelSm.copyWith(color: colors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }

  String _getCurrentLocation(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      final matches = router.routerDelegate.currentConfiguration.matches;
      if (matches.isEmpty) {
        return '/dashboard';
      }
      return matches.last.matchedLocation;
    } catch (_) {
      return '/dashboard';
    }
  }

  int _getCurrentIndex(BuildContext context) {
    final location = _getCurrentLocation(context);

    // Update current screen provider for smart notifications
    // Use Future.microtask to avoid modification during build
    final screen = locationToAppScreen(location);
    Future.microtask(() {
      if (mounted) {
        ref.read(currentScreenProvider.notifier).state = screen;
      }
    });

    final primaryIndex = ShellNavigation.primaryIndexForLocation(location);
    if (primaryIndex >= 0) {
      return primaryIndex;
    }

    // Scheduler / diagnostics redirect into tabbed parents; settings and
    // polar alignment are title-bar or overflow routes.
    switch (location.split('?').first) {
      case '/scheduler':
      case '/diagnostics':
      case '/settings':
      case '/polar-alignment':
        return -1;
      default:
        return 0;
    }
  }

  void _onTabSelected(int index, BuildContext context) {
    final route = ShellNavigation.primaryRouteForIndex(index);
    if (route == null) return;
    try {
      context.go(route);
    } catch (e) {
      // Router might not be available yet, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final appSettingsAsync = ref.watch(appSettingsProvider);
    final settings = appSettingsAsync.valueOrNull;
    final currentLocation = _getCurrentLocation(context);
    final currentIndex = _getCurrentIndex(context);

    // Activate the error notification bridge so backend errors show as toast notifications
    ref.watch(errorNotificationBridgeProvider);
    // Why: keep the meridian-flip disconnect guard alive
    // for the shell's lifetime so a mount disconnect during an in-flight flip
    // resets `flipExecutionStateProvider` to `aborted` and unsticks the UI.
    ref.watch(meridianFlipDisconnectGuardProvider);
    // Why: the standalone meridian monitor must be kept
    // alive while the shell is mounted so the Sequencer Settings ->
    // "Standalone monitoring" toggle actually does something — when enabled,
    // it polls mount HA against the configured trigger and alerts the
    // operator when the meridian is crossed outside of a sequence run.
    ref.watch(meridianFlipStandaloneMonitorProvider);
    // Scheduler lifetime: keep auto-reevaluation listeners mounted
    // with the shell, not only while Plan Tonight -> Target Queue is visible.
    // Otherwise target/goals/constraint edits made elsewhere can stop waking
    // the scheduler once the operator navigates away from that tab.
    ref.watch(schedulerAutoReevalProvider);
    final isSideNavExpanded = settings != null
        ? !settings.sidebarCollapsed
        : _fallbackSideNavExpanded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useBottomNav =
            ShellChrome.useBottomNavigation(constraints.maxWidth);

        // Phone "immersive" chrome: the bottom nav + status bar auto-hide when
        // idle so content gets the (very short, on a foldable cover) height,
        // and reappear on any interaction or a swipe up from the grabber.
        // Pinned visible on desktop/tablet (enabled = false → no timer).
        final chromeVisible = ref.watch(immersiveChromeProvider);
        final immersive = ref.read(immersiveChromeProvider.notifier);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          immersive.enabled = useBottomNav;
          // Reveal the chrome (and re-arm the one-shot idle auto-hide) whenever
          // the operator navigates to a different screen.
          if (useBottomNav && currentLocation != _lastImmersiveLocation) {
            _lastImmersiveLocation = currentLocation;
            immersive.onRouteChanged();
          }
        });

        // The first-launch tour is replay-only (C13): OnboardingTourReplayLauncher
        // watches firstLaunchTourStatusProvider and overlays OnboardingOverlay on
        // top of the whole shell when the user re-runs it from Settings → Help.
        // Mounted at the shell level so the spotlight cutouts can target the
        // live side-navigation TutorialKeys.
        //
        // The progressive first-launch "coach" popup was removed (it was an
        // intrusive readiness nudge whose info is reachable from the Equipment
        // "Ready to image" panel).
        final Widget shell = OnboardingTourReplayLauncher(
          child: TutorialOverlay(
            child: Scaffold(
              backgroundColor: colors.background,
              body: Column(
                children: [
                  // Desktop title bar (window drag + global actions). Hidden on
                  // mobile — bottom nav covers primary routes; saves vertical space.
                  if (!useBottomNav) const TitleBar(),

                  // Mobile gear strip. Settings left the bottom bar in the
                  // six-tab consolidation, so this thin app-bar action keeps it
                  // one tap away on phones.
                  if (useBottomNav)
                    SafeArea(
                      bottom: false,
                      child: _MobileSettingsBar(
                        onOpenSettings: () {
                          try {
                            context.go('/settings');
                          } catch (_) {}
                        },
                      ),
                    ),

                  // Disconnected banner — DESKTOP ONLY. On phone the dedicated
                  // connection strip is gone (it wasted the cover screen's scarce
                  // height); remote-connection state lives as a small ambient dot
                  // in the status bar (tap → connection sheet). On desktop the
                  // indicator stays in the TitleBar and this full-width banner
                  // still flags a dropped server connection.
                  if (!useBottomNav &&
                      ref.watch(sequencerBackendProvider)
                          is DisconnectedBackend)
                    Container(
                      width: double.infinity,
                      color: colors.error,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        l10n.text('disconnectedBanner'),
                        textAlign: TextAlign.center,
                        style: NightshadeTypography.labelQuiet.copyWith(
                            color: Theme.of(context).colorScheme.onError),
                      ),
                    ),

                  // iOS background-monitoring advisory (audit §3.2). Renders
                  // above the weather banner so it's the first thing the
                  // operator sees while a sequence is running on iOS.
                  const IosBackgroundBanner(),

                  // Android POST_NOTIFICATIONS advisory. Visible
                  // whenever the runtime permission is denied on Android 13+
                  // so the operator knows sequence/safety alerts will not
                  // wake them and points to System Settings.
                  const AndroidNotificationsBanner(),

                  // Stale-connection advisory (audit §3.6). Visible during
                  // the WS reconnect grace window so the operator knows
                  // controls may be momentarily out of date.
                  const ConnectionStaleBanner(),

                  // Weather Alert Banner
                  const WeatherAlertBanner(),

                  // Main content
                  Expanded(
                    child: Row(
                      children: [
                        // Side navigation (Desktop only)
                        if (!useBottomNav)
                          SideNavigation(
                            key: TutorialKeys.sideNavigation,
                            tutorialKeys: [
                              TutorialKeys.navDashboard,
                              TutorialKeys.navEquipment,
                              TutorialKeys.navImaging,
                              TutorialKeys.navSequencer,
                              TutorialKeys.navAnalytics,
                              null,
                              TutorialKeys.navPlanner,
                              TutorialKeys.navSettings,
                            ],
                            currentIndex: currentIndex,
                            onTabSelected: (index) =>
                                _onTabSelected(index, context),
                            isExpanded: isSideNavExpanded,
                            onToggleExpanded: () {
                              final currentSettings =
                                  ref.read(appSettingsProvider).valueOrNull;
                              if (currentSettings != null) {
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setSidebarCollapsed(
                                        !currentSettings.sidebarCollapsed);
                              } else {
                                setState(() {
                                  _fallbackSideNavExpanded =
                                      !_fallbackSideNavExpanded;
                                });
                              }
                            },
                          ),

                        // Main content area
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.background,
                              border: Border(
                                left: useBottomNav
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: colors.border,
                                        width: 1,
                                      ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // Both chromes own the top inset above this
                                // content: desktop via the TitleBar, mobile via
                                // the gear strip, so the content never re-insets
                                // the notch/status-bar edge itself.
                                SafeArea(
                                  top: false,
                                  bottom: false,
                                  child: widget.child,
                                ),
                                // Mobile sequence overlay (only on mobile and
                                // sequencer screen). §14: gated on the shared
                                // route constant instead of a literal string so
                                // the router and this check stay in sync. The
                                // app-wide running-sequence mini-player (run
                                // controls reachable off the sequencer route)
                                // lives in the bottom chrome below as
                                // [RunningSequenceMiniBar].
                                if (useBottomNav &&
                                    currentLocation.split('?').first ==
                                        kSequencerRoutePath)
                                  const MobileSequenceOverlay(),
                                // Autofocus progress overlay
                                const AutofocusProgressOverlay(),
                                // Toast notifications - always on top
                                const NotificationToastOverlay(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // App-wide running-sequence mini-player. Persistent across
                  // every route so pause/stop/skip stay reachable after the
                  // operator navigates away from the sequencer mid-run; it
                  // self-hides on the sequencer route (full controls live there)
                  // and whenever no sequence is active. Sits just above the
                  // bottom chrome so it reads as part of the persistent
                  // run-control surface.
                  RunningSequenceMiniBar(currentLocation: currentLocation),

                  // Bottom chrome. On phone the status bar + bottom nav live in
                  // one auto-hiding block (immersive) so they reclaim the short
                  // cover-screen height when idle; on desktop the status bar is
                  // pinned and navigation is the side rail (no bottom nav).
                  if (useBottomNav)
                    ImmersiveBottomChrome(
                      visible: chromeVisible,
                      onToggle: immersive.toggle,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StatusBar(compact: true),
                          NightshadeBottomNavigation(
                            currentRoute: currentLocation,
                            onRouteSelected: (route) {
                              try {
                                context.go(route);
                              } catch (_) {
                                // Router might not be available yet, ignore.
                              }
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    const StatusBar(compact: false),
                ],
              ),
            ),
          ),
        );

        if (!useBottomNav) return shell;
        // Dynamic UI shrink for phones: scale text down as the screen's short
        // side falls below a ~440px reference so dense cover screens (e.g. a
        // foldable ~369px) fit more without manual zoom. Multiplies (respects)
        // the user's own accessibility text scaling. Tablets (short side >=
        // 440) and desktop are unscaled.
        final mq = MediaQuery.of(context);
        final uiScale = (mq.size.shortestSide / 440.0).clamp(0.82, 1.0);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * uiScale),
          ),
          child: shell,
        );
      },
    );
  }
}

class _MobileSettingsBar extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _MobileSettingsBar({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Container(
      height: ShellChromeMetrics.titleBarHeight,
      color: colors.surface,
      padding:
          const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: NightshadeTokens.borderRadiusMd,
            ),
            child: Icon(NightshadeIcons.sparkle, size: 14, color: onPrimary),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm + 2),
          Text(
            'NIGHTSHADE',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          InkWell(
            key: TutorialKeys.navSettings,
            onTap: onOpenSettings,
            borderRadius: NightshadeTokens.borderRadiusInline4,
            child: Padding(
              padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
              child: Icon(
                NightshadeIcons.settings,
                size: NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
