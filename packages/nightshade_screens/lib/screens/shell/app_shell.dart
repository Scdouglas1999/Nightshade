import 'dart:io' show Platform;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../../widgets/catalog_setup_dialog.dart';
import 'widgets/title_bar.dart';
import 'widgets/status_bar.dart';
import 'widgets/side_navigation.dart';

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
      window_impl.initWindowManager(this);
    }
    // Check catalogs after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCatalogsIfNeeded();
    });
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
      debugPrint('Error checking catalog status: $e');
    }
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    switch (location) {
      case '/dashboard':
        return 0;
      case '/equipment':
        return 1;
      case '/imaging':
        return 2;
      case '/sequencer':
        return 3;
      case '/planetarium':
        return 4;
      case '/framing':
        return 5;
      case '/analytics':
        return 6;
      default:
        return 0;
    }
  }

  void _onTabSelected(int index) {
    final routes = [
      '/dashboard',
      '/equipment',
      '/imaging',
      '/sequencer',
      '/planetarium',
      '/framing',
      '/analytics',
    ];
    if (index < routes.length) {
      context.go(routes[index]);
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

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          // Custom title bar with window controls
          const TitleBar(),

          // Main content with side nav
          Expanded(
            child: Row(
              children: [
                // Side navigation
                SideNavigation(
                  currentIndex: currentIndex,
                  onTabSelected: _onTabSelected,
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
                        left: BorderSide(
                          color: colors.border,
                          width: 1,
                        ),
                      ),
                    ),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),

          // Status bar at bottom
          const StatusBar(),
        ],
      ),
    );
  }
}
