import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/catalog_setup_dialog.dart';
import '../../widgets/tutorial_overlay.dart';
import '../../widgets/welcome_flow.dart';
import '../../widgets/mobile_sequence_overlay.dart';
import '../../widgets/notification_toast_overlay.dart';
import '../../widgets/autofocus_progress_overlay.dart';
import '../../widgets/connection_stale_banner.dart';
import '../../widgets/ios_background_banner.dart';
import '../../widgets/weather/weather_alert_banner.dart';
import 'widgets/title_bar.dart';
import 'widgets/status_bar.dart';
import 'widgets/side_navigation.dart';
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
        final colors = Theme.of(context).extension<NightshadeColors>()!;
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
      debugPrint('[AppShell] Error checking catalog status: $e');
    }
  }

  Future<void> _checkCheckpointIfNeeded() async {
    if (_hasCheckedCheckpoint) return;
    _hasCheckedCheckpoint = true;

    try {
      final backend = ref.read(backendProvider);
      final hasCheckpoint = await backend.hasCheckpoint();
      if (!hasCheckpoint) return;

      final info = await backend.getCheckpointInfo();
      if (info == null || !info.canResume) return;

      if (!mounted) return;

      final colors = Theme.of(context).extension<NightshadeColors>()!;

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
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: colors.border),
            ),
            title: Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 22, color: colors.warning),
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
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
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
        await backend.resumeFromCheckpoint();
      } else {
        await backend.discardCheckpoint();
      }
    } catch (e) {
      debugPrint('[AppShell] Error checking checkpoint: $e');
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
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
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

    switch (location) {
      case '/dashboard':
        return 0;
      case '/equipment':
        return 1;
      case '/imaging':
        return 2;
      case '/guiding':
        return 3;
      case '/sequencer':
        return 4;
      case '/planetarium':
        return 5;
      case '/framing':
        return 6;
      case '/analytics':
        return 7;
      case '/flat-wizard':
        return 8;
      case '/weather':
        return 9;
      case '/planner':
        return 10;
      case '/diagnostics':
        return 11;
      case '/settings':
      case '/polar-alignment':
      case '/transients':
        return -1;
      default:
        return 0;
    }
  }

  void _onTabSelected(int index, BuildContext context) {
    final routes = [
      '/dashboard',
      '/equipment',
      '/imaging',
      '/guiding',
      '/sequencer',
      '/planetarium',
      '/framing',
      '/analytics',
      '/flat-wizard',
      '/weather',
      '/planner',
      '/diagnostics',
    ];
    if (index < routes.length) {
      try {
        context.go(routes[index]);
      } catch (e) {
        // Router might not be available yet, ignore
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final l10n = context.l10n;
    final appSettingsAsync = ref.watch(appSettingsProvider);
    final settings = appSettingsAsync.valueOrNull;
    final currentLocation = _getCurrentLocation(context);
    final currentIndex = _getCurrentIndex(context);

    // Activate the error notification bridge so backend errors show as toast notifications
    ref.watch(errorNotificationBridgeProvider);
    final isSideNavExpanded = settings != null
        ? !settings.sidebarCollapsed
        : _fallbackSideNavExpanded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;

        // Check if we should show the welcome flow for first-time users
        final showWelcomeFlow = ref.watch(shouldShowWelcomeFlowProvider);

        // If first launch, show WelcomeFlow instead of the app
        if (showWelcomeFlow) {
          return Scaffold(
            backgroundColor: colors.background,
            body: WelcomeFlow(
              onComplete: () {
                // WelcomeFlow handles marking the tour as seen
                // The widget will rebuild with showWelcomeFlow = false
              },
            ),
          );
        }

        return TutorialOverlay(
          child: Scaffold(
            backgroundColor: colors.background,
            body: Column(
              children: [
                // Custom title bar with window controls
                const TitleBar(),

                // Disconnected Banner
                if (ref.watch(backendProvider) is DisconnectedBackend)
                  Container(
                    width: double.infinity,
                    color: colors.error,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      l10n.text('disconnectedBanner'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // iOS background-monitoring advisory (audit §3.2). Renders
                // above the weather banner so it's the first thing the
                // operator sees while a sequence is running on iOS.
                const IosBackgroundBanner(),

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
                      if (!isMobile)
                        SideNavigation(
                          key: TutorialKeys.sideNavigation,
                          tutorialKeys: [
                            TutorialKeys.navDashboard,
                            TutorialKeys.navEquipment,
                            TutorialKeys.navImaging,
                            TutorialKeys.navGuiding,
                            TutorialKeys.navSequencer,
                            TutorialKeys.navPlanetarium,
                            TutorialKeys.navFraming,
                            TutorialKeys.navAnalytics,
                            TutorialKeys.navFlatWizard,
                            TutorialKeys.navWeather,
                            TutorialKeys.navPlanner,
                            TutorialKeys.navDiagnostics,
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
                              left: isMobile
                                  ? BorderSide.none
                                  : BorderSide(
                                      color: colors.border,
                                      width: 1,
                                    ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              widget.child,
                              // Mobile sequence overlay (only on mobile and sequencer screen)
                              if (isMobile && currentLocation == '/sequencer')
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

                // Status bar at bottom
                const StatusBar(),
              ],
            ),
            bottomNavigationBar: isMobile
                ? NightshadeBottomNavigation(
                    currentRoute: currentLocation,
                    onRouteSelected: (route) {
                      try {
                        context.go(route);
                      } catch (_) {
                        // Router might not be available yet, ignore.
                      }
                    },
                  )
                : null,
          ),
        );
      },
    );
  }
}
