import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../../widgets/catalog_setup_dialog.dart';
import '../../widgets/tutorial_overlay.dart';
import '../../widgets/welcome_flow.dart';
import '../../widgets/mobile_sequence_overlay.dart';
import '../../widgets/notification_toast_overlay.dart';
import '../../widgets/weather/weather_alert_banner.dart';
import 'widgets/title_bar.dart';
import 'widgets/status_bar.dart';
import 'widgets/side_navigation.dart';
import 'widgets/nightshade_bottom_navigation.dart';

// Conditional import for window_manager (desktop only)
import 'app_shell_stub.dart'
    if (dart.library.io) 'app_shell_desktop.dart' as window_impl;

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _fallbackSideNavExpanded = true;
  bool _hasCheckedCatalogs = false;

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
    // Check catalogs after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCatalogsIfNeeded();
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
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Close Nightshade?',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'A capture session is in progress. Are you sure you want to close the application? The current capture will be aborted.',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(true),
              label: 'Close Anyway',
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

  int _getCurrentIndex(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      final matches = router.routerDelegate.currentConfiguration.matches;
      if (matches.isEmpty) return 0;
      final location = matches.last.matchedLocation;

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
        default:
          return 0;
      }
    } catch (e) {
      // Fallback if router not available
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
    final appSettingsAsync = ref.watch(appSettingsProvider);
    final settings = appSettingsAsync.valueOrNull;
    final currentIndex = _getCurrentIndex(context);
    final isSideNavExpanded =
        settings != null ? !settings.sidebarCollapsed : _fallbackSideNavExpanded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < NightshadeTokens.breakpointTablet;

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
                    child: const Text(
                      'Error: not connected to server',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

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
                          ],
                          currentIndex: currentIndex,
                          onTabSelected: (index) => _onTabSelected(index, context),
                          isExpanded: isSideNavExpanded,
                          onToggleExpanded: () {
                            final currentSettings = ref.read(appSettingsProvider).valueOrNull;
                            if (currentSettings != null) {
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setSidebarCollapsed(!currentSettings.sidebarCollapsed);
                            } else {
                              setState(() {
                                _fallbackSideNavExpanded = !_fallbackSideNavExpanded;
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
                              if (isMobile && currentIndex == 4)
                                const MobileSequenceOverlay(),
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
                    currentIndex: currentIndex,
                    onTabSelected: (index) => _onTabSelected(index, context),
                  )
                : null,
          ),
        );
      },
    );
  }
}
