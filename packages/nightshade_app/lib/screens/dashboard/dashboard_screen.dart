import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart' hide sessionProgressProvider;
import '../../services/mount_command_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/astro_image_viewer.dart';
import '../../widgets/capture_settings_panel.dart';
import '../../widgets/focuser_controls.dart';
import '../../widgets/operation_status_bar.dart';
import '../../widgets/tutorial_keys/dashboard_keys.dart';
import '../../widgets/weather/dashboard_weather_widget.dart';
import '../../widgets/contextual_tour_prompt.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_provider.dart';

part 'dashboard_widgets.dart';

// ============================================================================
// Device ID Formatting Helpers
// ============================================================================

/// Format a device ID into a user-friendly display name
String _formatDeviceId(String id) {
  final lowerId = id.toLowerCase();

  // Handle native device IDs: native:vendor:index or native:vendor_type:index
  if (lowerId.startsWith('native:')) {
    final parts = id.substring(7).split(':');
    if (parts.isNotEmpty) {
      final devicePart = parts[0];
      final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

      if (devicePart.contains('_')) {
        final subParts = devicePart.split('_');
        final vendor = _capitalizeVendor(subParts[0]);
        final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
        return '$vendor $type';
      }

      final vendor = _capitalizeVendor(devicePart);
      if (index != null) {
        return '$vendor #${index + 1}';
      }
      return vendor;
    }
  }

  // Handle ASCOM device IDs
  if (lowerId.startsWith('ascom:') || lowerId.startsWith('ascom.')) {
    final ascomId = lowerId.startsWith('ascom:') ? id.substring(6) : id;
    final parts = ascomId.split('.');
    if (parts.length >= 2) {
      final vendorPart = parts.length > 1 ? parts[1] : parts[0];
      return _formatAscomVendor(vendorPart);
    }
  }

  // Handle Alpaca device IDs
  if (lowerId.startsWith('alpaca:')) {
    return 'Alpaca: ${id.substring(7)}';
  }

  // Handle PHD2
  if (lowerId.contains('phd2') || lowerId.contains('phd 2')) {
    return 'PHD2';
  }

  // Handle underscore-separated IDs
  if (id.contains('_')) {
    return id.split('_').map(_capitalizeWord).join(' ');
  }

  return id;
}

String _capitalizeVendor(String vendor) {
  const knownVendors = {
    'zwo': 'ZWO',
    'asi': 'ZWO ASI',
    'qhy': 'QHY',
    'playerone': 'PlayerOne',
    'svbony': 'SVBony',
    'atik': 'Atik',
    'fli': 'FLI',
    'moravian': 'Moravian',
    'touptek': 'Touptek',
    'pegasus': 'Pegasus',
    'pegasusastro': 'Pegasus Astro',
    'ioptron': 'iOptron',
    'skywatcher': 'Sky-Watcher',
    'celestron': 'Celestron',
    'meade': 'Meade',
    'moonlite': 'MoonLite',
  };

  final lower = vendor.toLowerCase();
  if (knownVendors.containsKey(lower)) {
    return knownVendors[lower]!;
  }

  if (vendor.isEmpty) return vendor;
  return vendor[0].toUpperCase() + vendor.substring(1);
}

String _formatAscomVendor(String vendor) {
  final spaced = vendor.replaceAllMapped(
    RegExp(r'([a-z])([A-Z0-9])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  return spaced;
}

String _capitalizeWord(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}

/// Get display name for a device
String _getDeviceDisplayName(String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return _formatDeviceId(deviceId);
  }
  return fallback;
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Ensure PHD2 controller is active and listening to events
    ref.watch(phd2ControllerProvider);
    final layoutAsync = ref.watch(dashboardLayoutProvider);

    return ContextualTourPrompt(
      screenId: 'dashboard',
      tourCategory: TutorialCategory.dashboardTour,
      title: 'Dashboard Tour',
      description: 'Learn about the dashboard controls and status displays.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: layoutAsync.when(
          data: (layout) => _ZoneBasedDashboard(
            layout: layout,
            colors: colors,
            pulseController: _pulseController,
            isEditing: _isEditing,
            onToggleEdit: _toggleEdit,
            onManageWidgets: _showWidgetPicker,
            onResetLayout: _resetLayout,
            onReorder: (dragged, target) {
              ref.read(dashboardLayoutProvider.notifier).reorder(dragged, target);
            },
            onResize: (id) {
              final tile = layout.tiles.firstWhere((t) => t.widgetId == id);
              ref.read(dashboardLayoutProvider.notifier).setTileSize(id, tile.size.next());
            },
            onToggleEnabled: (id, enabled) {
              ref.read(dashboardLayoutProvider.notifier).setTileEnabled(id, enabled);
            },
            onSetZone: (id, zone) {
              ref.read(dashboardLayoutProvider.notifier).setTileZone(id, zone);
            },
          ),
          loading: () => const _DashboardLoading(),
          error: (error, _) => _DashboardLayoutError(
            error: error,
            onReset: _resetLayout,
          ),
        ),
      ),
    );
  }

  void _toggleEdit() {
    setState(() => _isEditing = !_isEditing);
  }

  Future<void> _resetLayout() async {
    await ref.read(dashboardLayoutProvider.notifier).resetLayout();
  }

  void _showWidgetPicker() {
    showDialog(
      context: context,
      builder: (context) => const _WidgetPickerDialog(),
    );
  }
}

/// Zone-based dashboard layout implementing NINA-style command center design.
///
/// Layout structure:
/// - Command Bar: Fixed header with session status, quick stats, clock, and edit controls
/// - Primary Zone (60%): Main content area with hero live preview and capture controls
/// - Secondary Zone (40%): Resizable sidebar with sequence, guiding, equipment
/// - Tertiary Zone: Bottom row with compact status cards (mount, focus, weather)
///
/// Responsive breakpoints:
/// - >1440px: Full three-zone layout
/// - 1024-1440px: Primary + collapsible secondary panel
/// - 768-1024px: Stacked (primary above secondary)
/// - <768px: Single column with tabbed navigation
class _ZoneBasedDashboard extends StatelessWidget {
  final DashboardLayout layout;
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target) onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;
  final void Function(DashboardWidgetId id, DashboardZone zone) onSetZone;

  const _ZoneBasedDashboard({
    required this.layout,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
    required this.onSetZone,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        // Responsive layout selection based on breakpoints
        if (screenWidth < NightshadeTokens.breakpointTablet) {
          return _buildCompactLayout(context);
        } else if (screenWidth < NightshadeTokens.breakpointDesktop) {
          return _buildStackedLayout(context);
        } else {
          return _buildFullLayout(context, constraints);
        }
      },
    );
  }

  /// Full three-zone layout for wide screens (>1024px)
  ///
  /// NINA-style command center layout with compact, information-dense zones:
  /// - Primary zone (left): Live preview + capture controls + some tertiary cards
  /// - Secondary zone (right): Sequence, guiding, equipment + overflow tertiary cards
  Widget _buildFullLayout(BuildContext context, BoxConstraints constraints) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final primaryTiles = layout.tilesForZone(DashboardZone.primary);
    final secondaryTiles = layout.tilesForZone(DashboardZone.secondary);
    final tertiaryTiles = layout.tilesForZone(DashboardZone.tertiary);

    // Calculate zone widths
    final availableWidth = constraints.maxWidth - 48; // padding
    final secondaryWidth = (availableWidth * layout.secondaryZoneWidth).clamp(280.0, 360.0);
    final primaryWidth = availableWidth - secondaryWidth - 16; // gap

    // On wide screens, split tertiary cards between primary and secondary zones
    // Put Mount and Focus below the preview, move Weather/Tonight/Alerts to secondary
    final tertiaryForPrimary = <DashboardTileConfig>[];
    final tertiaryForSecondary = <DashboardTileConfig>[];

    for (final tile in tertiaryTiles) {
      // Mount and Focus stay with primary (they're about the current imaging session)
      if (tile.widgetId == DashboardWidgetId.mountControl ||
          tile.widgetId == DashboardWidgetId.focus) {
        tertiaryForPrimary.add(tile);
      } else {
        // Weather, Tonight, Alerts go to secondary (environmental/planning info)
        tertiaryForSecondary.add(tile);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Command Bar (fixed)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: _CommandBar(
            colors: colors,
            pulseController: pulseController,
            isEditing: isEditing,
            onToggleEdit: onToggleEdit,
            onManageWidgets: onManageWidgets,
            onResetLayout: onResetLayout,
          ),
        ),

        if (isEditing)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _EditModeBanner(colors: colors),
          ),

        // Main content area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: Primary + Mount/Focus (scrollable)
                SizedBox(
                  width: primaryWidth,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary Zone (Live Preview + Capture)
                        _ZoneColumn(
                          zone: DashboardZone.primary,
                          tiles: primaryTiles,
                          registry: registry,
                          colors: colors,
                          pulseController: pulseController,
                          isEditing: isEditing,
                          cardVariant: CardVariant.elevated,
                          isHeroZone: true,
                          onReorder: onReorder,
                          onResize: onResize,
                          onToggleEnabled: onToggleEnabled,
                        ),

                        // Mount & Focus below primary
                        if (tertiaryForPrimary.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _TertiaryZoneRow(
                            tiles: tertiaryForPrimary,
                            registry: registry,
                            colors: colors,
                            pulseController: pulseController,
                            isEditing: isEditing,
                            onReorder: onReorder,
                            onResize: onResize,
                            onToggleEnabled: onToggleEnabled,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Right column: Secondary + Weather/Tonight/Alerts (scrollable)
                SizedBox(
                  width: secondaryWidth,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Secondary Zone (Sequence, Guiding, Equipment, Quick Actions)
                        _ZoneColumn(
                          zone: DashboardZone.secondary,
                          tiles: secondaryTiles,
                          registry: registry,
                          colors: colors,
                          pulseController: pulseController,
                          isEditing: isEditing,
                          cardVariant: CardVariant.elevated,
                          isHeroZone: false,
                          onReorder: onReorder,
                          onResize: onResize,
                          onToggleEnabled: onToggleEnabled,
                        ),

                        // Weather, Tonight, Alerts below secondary
                        if (tertiaryForSecondary.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...tertiaryForSecondary.map((tile) {
                            final definition = registry[tile.widgetId];
                            if (definition == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DashboardTile(
                                tile: tile,
                                width: double.infinity,
                                colors: colors,
                                child: Builder(
                                  builder: (context) => definition.builder(context, colors, pulseController),
                                ),
                                isEditing: isEditing,
                                cardVariant: CardVariant.standard,
                                isHero: false,
                                onReorder: onReorder,
                                onResize: onResize,
                                onToggleEnabled: onToggleEnabled,
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Stacked layout for medium screens (768-1024px)
  ///
  /// Places tertiary zone immediately after primary to maintain compact grouping.
  Widget _buildStackedLayout(BuildContext context) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final primaryTiles = layout.tilesForZone(DashboardZone.primary);
    final secondaryTiles = layout.tilesForZone(DashboardZone.secondary);
    final tertiaryTiles = layout.tilesForZone(DashboardZone.tertiary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Command Bar (fixed)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _CommandBar(
            colors: colors,
            pulseController: pulseController,
            isEditing: isEditing,
            onToggleEdit: onToggleEdit,
            onManageWidgets: onManageWidgets,
            onResetLayout: onResetLayout,
          ),
        ),

        if (isEditing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _EditModeBanner(colors: colors),
          ),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary Zone
                _ZoneColumn(
                  zone: DashboardZone.primary,
                  tiles: primaryTiles,
                  registry: registry,
                  colors: colors,
                  pulseController: pulseController,
                  isEditing: isEditing,
                  cardVariant: CardVariant.elevated,
                  isHeroZone: true,
                  onReorder: onReorder,
                  onResize: onResize,
                  onToggleEnabled: onToggleEnabled,
                ),

                // Tertiary Zone immediately after primary (compact status cards)
                if (tertiaryTiles.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _TertiaryZoneRow(
                    tiles: tertiaryTiles,
                    registry: registry,
                    colors: colors,
                    pulseController: pulseController,
                    isEditing: isEditing,
                    onReorder: onReorder,
                    onResize: onResize,
                    onToggleEnabled: onToggleEnabled,
                  ),
                ],

                const SizedBox(height: 16),

                // Secondary Zone (last in stacked layout)
                _ZoneColumn(
                  zone: DashboardZone.secondary,
                  tiles: secondaryTiles,
                  registry: registry,
                  colors: colors,
                  pulseController: pulseController,
                  isEditing: isEditing,
                  cardVariant: CardVariant.standard,
                  isHeroZone: false,
                  onReorder: onReorder,
                  onResize: onResize,
                  onToggleEnabled: onToggleEnabled,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact layout for narrow screens (<768px)
  ///
  /// Mobile-optimized layout with:
  /// - Compact command bar at top
  /// - Weather widget full width (prioritized for field use)
  /// - Live preview full width
  /// - Quick actions as horizontal scrollable row
  /// - Device status cards in a wrap layout
  /// - Session and other cards stacked vertically
  Widget _buildCompactLayout(BuildContext context) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final allTiles = layout.tiles.where((t) => t.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Categorize tiles for mobile-optimized ordering
    final weatherTile = allTiles.where((t) => t.widgetId == DashboardWidgetId.weather).firstOrNull;
    final livePreviewTile = allTiles.where((t) => t.widgetId == DashboardWidgetId.livePreview).firstOrNull;
    final captureSettingsTile = allTiles.where((t) => t.widgetId == DashboardWidgetId.captureSettings).firstOrNull;
    final quickActionsTile = allTiles.where((t) => t.widgetId == DashboardWidgetId.quickActions).firstOrNull;
    final sessionTile = allTiles.where((t) => t.widgetId == DashboardWidgetId.sequenceStatus).firstOrNull;

    // Equipment-related tiles for wrap layout
    final equipmentTiles = allTiles.where((t) =>
      t.widgetId == DashboardWidgetId.equipmentStatus ||
      t.widgetId == DashboardWidgetId.mountControl ||
      t.widgetId == DashboardWidgetId.focus
    ).toList();

    // Other tiles (guiding, tonight, alerts, quick stats)
    final otherTiles = allTiles.where((t) =>
      t.widgetId != DashboardWidgetId.weather &&
      t.widgetId != DashboardWidgetId.livePreview &&
      t.widgetId != DashboardWidgetId.captureSettings &&
      t.widgetId != DashboardWidgetId.quickActions &&
      t.widgetId != DashboardWidgetId.sequenceStatus &&
      t.widgetId != DashboardWidgetId.equipmentStatus &&
      t.widgetId != DashboardWidgetId.mountControl &&
      t.widgetId != DashboardWidgetId.focus
    ).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact Command Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _CompactCommandBar(
            colors: colors,
            pulseController: pulseController,
            isEditing: isEditing,
            onToggleEdit: onToggleEdit,
          ),
        ),

        if (isEditing)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _EditModeBanner(colors: colors),
          ),

        // Mobile-optimized scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Weather - full width at top (important for field use)
                if (weatherTile != null) ...[
                  _buildTile(
                    tile: weatherTile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],

                // 2. Live Preview - full width hero
                if (livePreviewTile != null) ...[
                  _buildTile(
                    tile: livePreviewTile,
                    registry: registry,
                    cardVariant: CardVariant.elevated,
                    isHero: true,
                  ),
                  const SizedBox(height: 12),
                ],

                // 3. Capture Settings - full width
                if (captureSettingsTile != null) ...[
                  _buildTile(
                    tile: captureSettingsTile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],

                // 4. Quick Actions - full width (responsive wrap inside)
                if (quickActionsTile != null) ...[
                  _buildTile(
                    tile: quickActionsTile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. Session Status - full width
                if (sessionTile != null) ...[
                  _buildTile(
                    tile: sessionTile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],

                // 6. Equipment tiles in responsive wrap layout
                if (equipmentTiles.isNotEmpty) ...[
                  _MobileEquipmentSection(
                    tiles: equipmentTiles,
                    registry: registry,
                    colors: colors,
                    pulseController: pulseController,
                    isEditing: isEditing,
                    onReorder: onReorder,
                    onResize: onResize,
                    onToggleEnabled: onToggleEnabled,
                  ),
                  const SizedBox(height: 12),
                ],

                // 7. Other tiles stacked vertically
                for (final tile in otherTiles) ...[
                  _buildTile(
                    tile: tile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile({
    required DashboardTileConfig tile,
    required Map<DashboardWidgetId, DashboardWidgetDefinition> registry,
    required CardVariant cardVariant,
    required bool isHero,
  }) {
    final definition = registry[tile.widgetId];
    if (definition == null) return const SizedBox.shrink();

    final child = definition.builder(
      // Using a BuildContext is a bit awkward here - builders will get it from NightshadeCard
      WidgetsBinding.instance.rootElement!,
      colors,
      pulseController,
    );

    return _DashboardTile(
      tile: tile,
      width: double.infinity,
      colors: colors,
      child: child,
      isEditing: isEditing,
      cardVariant: cardVariant,
      isHero: isHero,
      onReorder: onReorder,
      onResize: onResize,
      onToggleEnabled: onToggleEnabled,
    );
  }
}

/// Command Bar: Fixed header with session status, quick stats, clock, and controls.
///
/// This is the central nervous system status display showing:
/// - Session status indicator (Idle/Capturing with target name)
/// - Quick stats strip: Temp | Focus | HFR | RMS
/// - Clock/LST widget
/// - Edit mode toggle and controls
class _CommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;

  const _CommandBar({
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing = sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Responsive thresholds for command bar elements
        final showClock = width >= 900;
        final showDividers = width >= 850;
        final showStats = width >= 800;
        final compactPadding = width < 900;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compactPadding ? 12 : 16,
            vertical: compactPadding ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusLg,
            border: Border.all(color: colors.border),
            boxShadow: NightshadeTokens.elevationLevel1,
          ),
          child: Row(
            children: [
              // Session Status - always show but constrain width
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width < 900 ? 120 : 180),
                  child: _SessionStatusIndicator(
                    colors: colors,
                    pulseController: pulseController,
                    isCapturing: isCapturing,
                    targetName: targetName,
                  ),
                ),
              ),

              if (showDividers) ...[
                SizedBox(width: compactPadding ? 12 : 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
                SizedBox(width: compactPadding ? 12 : 24),
              ] else
                SizedBox(width: compactPadding ? 8 : 16),

              // Quick Stats Strip - only show on wider layouts
              if (showStats)
                Expanded(
                  child: _QuickStatsStrip(colors: colors),
                )
              else
                const Spacer(),

              if (showDividers && showStats) ...[
                SizedBox(width: compactPadding ? 12 : 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
              ],

              SizedBox(width: compactPadding ? 8 : 16),

              // Clock/LST - hide on narrower layouts
              if (showClock) ...[
                _ClockWidget(colors: colors),
                SizedBox(width: compactPadding ? 8 : 16),
              ],

              // Edit Controls
              _DashboardHeaderActions(
                isEditing: isEditing,
                onToggleEdit: onToggleEdit,
                onManageWidgets: onManageWidgets,
                onResetLayout: onResetLayout,
                compact: !showClock,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Session status indicator showing capture state and current target.
class _SessionStatusIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isCapturing;
  final String targetName;

  const _SessionStatusIndicator({
    required this.colors,
    required this.pulseController,
    required this.isCapturing,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCapturing
                    ? colors.success.withValues(alpha: 0.4 + pulseController.value * 0.4)
                    : colors.textMuted.withValues(alpha: 0.4 + pulseController.value * 0.3),
                boxShadow: isCapturing
                    ? [
                        BoxShadow(
                          color: colors.success.withValues(alpha: 0.3),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isCapturing ? 'Capturing' : 'Idle',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCapturing ? colors.success : colors.textSecondary,
                ),
              ),
              Text(
                targetName,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick stats strip showing Temp | Focus | HFR | RMS in the command bar.
class _QuickStatsStrip extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsStrip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Camera temperature
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));

    // Focuser position
    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final focuserPosition = ref.watch(focuserStateProvider.select((s) => s.position));

    // HFR from last image
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));

    // Guiding RMS
    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    // Format values
    final tempValue = cameraConnected && cameraTemp != null
        ? '${cameraTemp.toStringAsFixed(1)}°C'
        : '---';
    final focusValue = focuserConnected && focuserPosition != null
        ? focuserPosition.toString()
        : '---';
    final hfrValue = hfr != null ? hfr.toStringAsFixed(2) : '---';
    final rmsValue = guiderConnected && guiderIsGuiding && guiderRms != null
        ? '${guiderRms.toStringAsFixed(2)}"'
        : '---';

    // Use FittedBox to scale down gracefully on narrower layouts
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CommandBarStat(
            icon: LucideIcons.thermometer,
            label: 'Temp',
            value: tempValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.focus,
            label: 'Focus',
            value: focusValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.target,
            label: 'HFR',
            value: hfrValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.activity,
            label: 'RMS',
            value: rmsValue,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _CommandBarStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CommandBarStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: colors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact command bar for narrow screens (<768px).
///
/// Mobile-optimized header showing:
/// - Row 1: Session status + Edit button
/// - Row 2 (optional): Compact quick stats (Temp | HFR | RMS) when capturing
class _CompactCommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;

  const _CompactCommandBar({
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing = sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    // Quick stats for mobile (only when capturing or has data)
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    final showStats = isCapturing || cameraConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Status + Edit
          Row(
            children: [
              // Status dot
              AnimatedBuilder(
                animation: pulseController,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCapturing
                          ? colors.success.withValues(alpha: 0.4 + pulseController.value * 0.4)
                          : colors.textMuted.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Status and target name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isCapturing ? 'Capturing' : 'Idle',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isCapturing ? colors.success : colors.textSecondary,
                      ),
                    ),
                    if (isCapturing)
                      Text(
                        targetName,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Edit button
              NightshadeButton(
                label: isEditing ? 'Done' : 'Edit',
                icon: isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
                variant: isEditing ? ButtonVariant.primary : ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: onToggleEdit,
              ),
            ],
          ),

          // Row 2: Compact quick stats (shown when capturing or has data)
          if (showStats) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              // Use FittedBox to scale down stats on very narrow screens
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _MobileStatChip(
                      label: 'Temp',
                      value: cameraConnected && cameraTemp != null
                          ? '${cameraTemp.toStringAsFixed(0)}°'
                          : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: 'HFR',
                      value: hfr != null ? hfr.toStringAsFixed(2) : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: 'RMS',
                      value: guiderIsGuiding && guiderRms != null
                          ? '${guiderRms.toStringAsFixed(1)}"'
                          : '---',
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact stat display for mobile command bar.
class _MobileStatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MobileStatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Column of widgets for a specific zone.
class _ZoneColumn extends StatelessWidget {
  final DashboardZone zone;
  final List<DashboardTileConfig> tiles;
  final Map<DashboardWidgetId, DashboardWidgetDefinition> registry;
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final CardVariant cardVariant;
  final bool isHeroZone;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target) onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;

  const _ZoneColumn({
    required this.zone,
    required this.tiles,
    required this.registry,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.cardVariant,
    required this.isHeroZone,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) {
      return _EmptyZonePlaceholder(zone: zone, colors: colors, isEditing: isEditing);
    }

    // Use tighter spacing for secondary zone (8px) vs primary (16px)
    final gapHeight = zone == DashboardZone.secondary ? 8.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          _buildZoneTile(tiles[i], i == 0 && isHeroZone),
          if (i < tiles.length - 1) SizedBox(height: gapHeight),
        ],
      ],
    );
  }

  Widget _buildZoneTile(DashboardTileConfig tile, bool isHero) {
    final definition = registry[tile.widgetId];
    if (definition == null) {
      return _DashboardLayoutError(
        title: 'Unknown widget',
        buttonLabel: 'Hide Tile',
        error: 'Missing widget definition for ${tile.widgetId.storageKey}.',
        onReset: () => onToggleEnabled(tile.widgetId, false),
      );
    }

    final child = Builder(
      builder: (context) => definition.builder(context, colors, pulseController),
    );

    return _DashboardTile(
      tile: tile,
      width: double.infinity,
      colors: colors,
      child: child,
      isEditing: isEditing,
      cardVariant: isHero ? CardVariant.elevated : cardVariant,
      isHero: isHero,
      onReorder: onReorder,
      onResize: onResize,
      onToggleEnabled: onToggleEnabled,
    );
  }
}

/// Placeholder for empty zones in edit mode.
class _EmptyZonePlaceholder extends StatelessWidget {
  final DashboardZone zone;
  final NightshadeColors colors;
  final bool isEditing;

  const _EmptyZonePlaceholder({
    required this.zone,
    required this.colors,
    required this.isEditing,
  });

  @override
  Widget build(BuildContext context) {
    if (!isEditing) return const SizedBox.shrink();

    final zoneName = switch (zone) {
      DashboardZone.primary => 'Primary',
      DashboardZone.secondary => 'Secondary',
      DashboardZone.tertiary => 'Tertiary',
    };

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(
          color: colors.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.layoutGrid, size: 32, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            '$zoneName Zone',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enable widgets to add them here',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Mobile equipment section with responsive wrap layout.
///
/// Displays equipment-related cards (Equipment Status, Mount Control, Focus) in a
/// flexible wrap layout that adapts to available width:
/// - On narrow screens: cards stack vertically (single column)
/// - On wider mobile screens: cards flow in a 2-column wrap
class _MobileEquipmentSection extends StatelessWidget {
  final List<DashboardTileConfig> tiles;
  final Map<DashboardWidgetId, DashboardWidgetDefinition> registry;
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target) onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;

  const _MobileEquipmentSection({
    required this.tiles,
    required this.registry,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Use wrap layout for cards - 2 columns if width >= 400, otherwise single column
        final useWrap = availableWidth >= 400;
        final cardWidth = useWrap ? (availableWidth - 12) / 2 : availableWidth;

        if (useWrap) {
          // Wrap layout for wider mobile screens
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: tiles.map((tile) {
              return SizedBox(
                width: cardWidth,
                child: _buildEquipmentTile(tile),
              );
            }).toList(),
          );
        } else {
          // Stack vertically for narrow screens
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                _buildEquipmentTile(tiles[i]),
                if (i < tiles.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildEquipmentTile(DashboardTileConfig tile) {
    final definition = registry[tile.widgetId];
    if (definition == null) return const SizedBox.shrink();

    final child = Builder(
      builder: (context) => definition.builder(context, colors, pulseController),
    );

    return _DashboardTile(
      tile: tile,
      width: double.infinity,
      colors: colors,
      child: child,
      isEditing: isEditing,
      cardVariant: CardVariant.standard,
      isHero: false,
      onReorder: onReorder,
      onResize: onResize,
      onToggleEnabled: onToggleEnabled,
    );
  }
}

/// Tertiary zone displayed as a horizontal row of compact cards.
/// Uses ConsumerWidget to conditionally hide the Alerts card when empty.
class _TertiaryZoneRow extends ConsumerWidget {
  final List<DashboardTileConfig> tiles;
  final Map<DashboardWidgetId, DashboardWidgetDefinition> registry;
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target) onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;

  /// Fixed minimum height for all tertiary zone cards to ensure consistent layout.
  static const double _tertiaryCardMinHeight = 150.0;

  /// Minimum width for tertiary cards.
  static const double _minCardWidth = 200.0;

  /// Maximum width for tertiary cards.
  static const double _maxCardWidth = 400.0;

  /// Spacing between cards.
  static const double _cardSpacing = 12.0;

  const _TertiaryZoneRow({
    required this.tiles,
    required this.registry,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check if alerts card should be hidden (no notifications and no active operation)
    final notifications = ref.watch(uiNotificationProvider);
    final hasOperation = ref.watch(hasActiveOperationProvider);
    final alertsHasContent = notifications.isNotEmpty || hasOperation;

    // Filter out Alerts card if it has no content (unless in edit mode where we show all)
    final filteredTiles = tiles.where((tile) {
      if (tile.widgetId == DashboardWidgetId.alerts && !alertsHasContent && !isEditing) {
        return false;
      }
      return true;
    }).toList();

    if (filteredTiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cardCount = filteredTiles.length;

        // Calculate optimal layout
        final layout = _calculateCardLayout(availableWidth, cardCount);

        // Build rows of cards
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildCardRows(filteredTiles, layout),
        );
      },
    );
  }

  /// Calculate the optimal card layout based on available width and card count.
  /// Returns a record with (cardWidth, cardsPerRow).
  ({double cardWidth, int cardsPerRow}) _calculateCardLayout(
    double availableWidth,
    int totalCards,
  ) {
    if (totalCards == 0) {
      return (cardWidth: _minCardWidth, cardsPerRow: 1);
    }

    // Try fitting all cards in one row first
    // Available width for cards = total width - spacing between cards
    // For N cards: spacing = (N - 1) * _cardSpacing
    double calculateCardWidth(int cardsInRow) {
      if (cardsInRow <= 0) return _maxCardWidth;
      final totalSpacing = (cardsInRow - 1) * _cardSpacing;
      return (availableWidth - totalSpacing) / cardsInRow;
    }

    // Start with trying to fit all cards in one row
    int cardsPerRow = totalCards;
    double cardWidth = calculateCardWidth(cardsPerRow);

    // If cards would be too narrow, reduce cards per row until they fit
    while (cardWidth < _minCardWidth && cardsPerRow > 1) {
      cardsPerRow--;
      cardWidth = calculateCardWidth(cardsPerRow);
    }

    // On very narrow screens (mobile), allow full width even if below min
    // This prevents horizontal overflow on small devices
    if (cardsPerRow == 1) {
      cardWidth = availableWidth; // Full width for single column
    } else {
      // Clamp to max width (cards won't exceed max even if there's extra space)
      cardWidth = cardWidth.clamp(_minCardWidth, _maxCardWidth);
    }

    // If we're using max width and have leftover space, we might fit more cards
    // but we already tried that above, so just use what we have

    return (cardWidth: cardWidth, cardsPerRow: cardsPerRow);
  }

  /// Build rows of cards with equal widths within each row.
  List<Widget> _buildCardRows(
    List<DashboardTileConfig> tiles,
    ({double cardWidth, int cardsPerRow}) layout,
  ) {
    final rows = <Widget>[];
    final totalCards = tiles.length;
    int startIndex = 0;

    while (startIndex < totalCards) {
      final remainingCards = totalCards - startIndex;
      final cardsInThisRow = remainingCards < layout.cardsPerRow
          ? remainingCards
          : layout.cardsPerRow;

      // Get tiles for this row
      final rowTiles = tiles.sublist(startIndex, startIndex + cardsInThisRow);

      // For the last row with fewer cards, we still want equal-width cards
      // but they should expand to fill the row (up to max width each)
      final rowWidget = _buildSingleRow(rowTiles, layout.cardWidth, layout.cardsPerRow);

      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: _cardSpacing));
      }
      rows.add(rowWidget);

      startIndex += cardsInThisRow;
    }

    return rows;
  }

  /// Build a single row of cards.
  Widget _buildSingleRow(
    List<DashboardTileConfig> rowTiles,
    double baseCardWidth,
    int standardCardsPerRow,
  ) {
    // Use Row with Expanded children to distribute space evenly
    // Cards have a fixed minHeight via _tertiaryCardMinHeight for consistent layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rowTiles.length; i++) ...[
          if (i > 0) const SizedBox(width: _cardSpacing),
          Expanded(
            child: _buildTertiaryTile(rowTiles[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildTertiaryTile(DashboardTileConfig tile) {
    final definition = registry[tile.widgetId];
    if (definition == null) return const SizedBox.shrink();

    final child = Builder(
      builder: (context) => definition.builder(context, colors, pulseController),
    );

    // Wrap in ConstrainedBox with minHeight for consistent card sizing
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _tertiaryCardMinHeight),
      child: _DashboardTile(
        tile: tile,
        width: double.infinity,
        colors: colors,
        child: child,
        isEditing: isEditing,
        cardVariant: CardVariant.standard,
        isHero: false,
        onReorder: onReorder,
        onResize: onResize,
        onToggleEnabled: onToggleEnabled,
      ),
    );
  }
}


class _ClockWidget extends ConsumerWidget {
  final NightshadeColors colors;

  const _ClockWidget({required this.colors});

  String _formatLST(double lstHours) {
    final h = lstHours.floor();
    final m = ((lstHours - h) * 60).floor();
    final s = (((lstHours - h) * 60 - m) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the observationTimeProvider for both local time and LST
    // This provider already updates every second, no need for a separate timer
    final timeState = ref.watch(observationTimeProvider);
    final now = timeState.time;
    final lst = ref.watch(localSiderealTimeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.15),
            colors.accent.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'LST ${_formatLST(lst)}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardHeaderActions extends StatelessWidget {
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;
  final bool compact;

  const _DashboardHeaderActions({
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttonSize = compact ? ButtonSize.small : ButtonSize.medium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NightshadeButton(
          key: DashboardTutorialKeys.editButton,
          label: isEditing ? 'Done' : (compact ? 'Edit' : 'Edit Dashboard'),
          icon: isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
          variant: isEditing ? ButtonVariant.primary : ButtonVariant.outline,
          size: buttonSize,
          onPressed: onToggleEdit,
        ),
        if (isEditing) ...[
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : 'Widgets',
            icon: LucideIcons.layoutGrid,
            variant: ButtonVariant.outline,
            size: buttonSize,
            onPressed: onManageWidgets,
          ),
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : 'Reset',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            size: buttonSize,
            onPressed: onResetLayout,
          ),
        ],
      ],
    );
  }
}

class _EditModeBanner extends StatelessWidget {
  final NightshadeColors colors;

  const _EditModeBanner({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.grip, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit mode: long-press the grip handle to drag and reorder tiles.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// _DashboardGrid removed - replaced by _ZoneBasedDashboard

class _DashboardTile extends StatelessWidget {
  final DashboardTileConfig tile;
  final double width;
  final NightshadeColors colors;
  final Widget child;
  final bool isEditing;
  final CardVariant cardVariant;
  final bool isHero;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target)
      onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;

  const _DashboardTile({
    required this.tile,
    required this.width,
    required this.colors,
    required this.child,
    required this.isEditing,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
    this.cardVariant = CardVariant.standard,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<DashboardWidgetId>(
      onWillAccept: (data) => isEditing && data != tile.widgetId,
      onAccept: (data) {
        if (isEditing) onReorder(data, tile.widgetId);
      },
      builder: (context, candidateData, _) {
        final isDropTarget = candidateData.isNotEmpty;
        final frame = _DashboardTileFrame(
          colors: colors,
          isEditing: isEditing,
          isDropTarget: isDropTarget,
          size: tile.size,
          child: child,
          cardVariant: cardVariant,
          isHero: isHero,
          onResize: () => onResize(tile.widgetId),
          onHide: () => onToggleEnabled(tile.widgetId, false),
        );

        if (!isEditing) {
          return frame;
        }

        return LongPressDraggable<DashboardWidgetId>(
          data: tile.widgetId,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: width,
              child: Opacity(
                opacity: 0.9,
                child: _DashboardTileFrame(
                  colors: colors,
                  isEditing: false,
                  isDropTarget: false,
                  size: tile.size,
                  child: child,
                  cardVariant: cardVariant,
                  isHero: isHero,
                  onResize: () {},
                  onHide: () {},
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.4,
            child: frame,
          ),
          child: frame,
        );
      },
    );
  }
}

class _DashboardTileFrame extends StatelessWidget {
  final NightshadeColors colors;
  final bool isEditing;
  final bool isDropTarget;
  final DashboardTileSize size;
  final Widget child;
  final CardVariant cardVariant;
  final bool isHero;
  final VoidCallback onResize;
  final VoidCallback onHide;

  const _DashboardTileFrame({
    required this.colors,
    required this.isEditing,
    required this.isDropTarget,
    required this.size,
    required this.child,
    required this.onResize,
    required this.onHide,
    this.cardVariant = CardVariant.standard,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    // Hero treatment: premium shadows and accent glow for live preview
    final List<BoxShadow> shadow;
    if (isHero) {
      shadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: colors.primary.withValues(alpha: 0.1),
          blurRadius: 16,
          spreadRadius: -2,
        ),
      ];
    } else if (cardVariant == CardVariant.elevated) {
      shadow = NightshadeTokens.elevationLevel1to2;
    } else if (cardVariant == CardVariant.subtle) {
      shadow = [];
    } else {
      shadow = NightshadeTokens.elevationLevel1;
    }

    // Border with hero accent and edit mode highlight
    final borderColor = isDropTarget
        ? colors.primary.withValues(alpha: 0.7)
        : isEditing
            ? colors.primary.withValues(alpha: 0.3)
            : isHero
                ? colors.primary.withValues(alpha: 0.2)
                : colors.border;

    return Stack(
      children: [
        // Card container with visual hierarchy
        AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusXl,
            border: Border.all(
              color: borderColor,
              width: isDropTarget ? 2 : (isHero ? 1.5 : 1),
            ),
            boxShadow: shadow,
          ),
          child: ClipRRect(
            borderRadius: NightshadeTokens.borderRadiusXl,
            child: IgnorePointer(
              ignoring: isEditing,
              child: child,
            ),
          ),
        ),

        // Hero glow effect (top edge accent)
        if (isHero)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.6),
                    colors.accent.withValues(alpha: 0.3),
                    colors.primary.withValues(alpha: 0.1),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
            ),
          ),

        // Edit mode drag handle (top-left)
        if (isEditing)
          Positioned(
            top: 8,
            left: 8,
            child: _DragHandleIndicator(colors: colors),
          ),

        // Edit mode controls (top-right) - adjusted for larger touch targets
        if (isEditing)
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EditIconButton(
                  icon: LucideIcons.maximize2,
                  tooltip: 'Resize (${size.label})',
                  onTap: onResize,
                ),
                // Touch areas now adjacent at 40px each
                _EditIconButton(
                  icon: LucideIcons.eyeOff,
                  tooltip: 'Hide tile',
                  onTap: onHide,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Edit mode icon button with expanded touch target (40x40px) for field use.
class _EditIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _EditIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Tooltip(
      message: tooltip,
      // Expanded touch target: 40x40px for easier tapping
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Center(
              // Visual element stays compact at 26x26px
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle indicator shown on tiles in edit mode.
///
/// Provides visual affordance that tiles can be long-pressed and dragged.
class _DragHandleIndicator extends StatelessWidget {
  final NightshadeColors colors;

  const _DragHandleIndicator({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        LucideIcons.gripVertical,
        size: 14,
        color: colors.primary.withValues(alpha: 0.8),
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _DashboardLayoutError extends StatelessWidget {
  final Object error;
  final VoidCallback onReset;
  final String title;
  final String buttonLabel;

  const _DashboardLayoutError({
    required this.error,
    required this.onReset,
    this.title = 'Dashboard Layout Error',
    this.buttonLabel = 'Reset Layout',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: colors.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: buttonLabel,
              icon: LucideIcons.refreshCw,
              variant: ButtonVariant.outline,
              size: ButtonSize.medium,
              onPressed: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetPickerDialog extends ConsumerWidget {
  const _WidgetPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final layoutAsync = ref.watch(dashboardLayoutProvider);
    final screenSize = MediaQuery.of(context).size;
    // Responsive dialog width: 90% of screen on small screens, max 420px on larger
    final dialogWidth = screenSize.width < 500
        ? screenSize.width * 0.9
        : 420.0;

    return AlertDialog(
      backgroundColor: colors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width < 400 ? 16 : 40,
        vertical: 24,
      ),
      title: Text(
        'Dashboard Widgets',
        style: TextStyle(color: colors.textPrimary, fontSize: screenSize.width < 400 ? 16 : 20),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          minWidth: 280,
          maxHeight: screenSize.height * 0.7,
        ),
        child: layoutAsync.when(
          data: (layout) {
            final tilesById = {
              for (final tile in layout.tiles) tile.widgetId: tile,
            };

            final children = <Widget>[];
            for (var i = 0; i < dashboardWidgetRegistry.length; i++) {
              final definition = dashboardWidgetRegistry[i];
              final tile = tilesById[definition.id];
              final enabled = tile?.enabled ?? false;

              if (i > 0) {
                children.add(Divider(color: colors.border));
              }

              children.add(
                CheckboxListTile(
                  value: enabled,
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(dashboardLayoutProvider.notifier)
                        .setTileEnabled(definition.id, value);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    definition.title,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    definition.subtitle,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            'Failed to load widgets: $error',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}

/// Live preview card - orchestrates smaller focused widgets
///
/// Uses a responsive aspect ratio for the image preview area that adapts
/// to the available width:
/// - Wide screens (>800px): 16:9 aspect ratio for cinematic preview
/// - Medium screens (400-800px): 4:3 aspect ratio for balanced view
/// - Narrow screens (<400px): 1:1 aspect ratio for compact display
///
/// The card fills the available width in its parent container.
class _LivePreviewCard extends StatelessWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;

  const _LivePreviewCard({
    super.key,
    required this.colors,
    required this.pulseController,
  });

  /// Calculate responsive aspect ratio based on available width.
  double _getAspectRatio(double width) {
    if (width > 800) {
      // Wide screens: 16:9 cinematic aspect ratio
      return 16 / 9;
    } else if (width > 400) {
      // Medium screens: 4:3 balanced aspect ratio
      return 4 / 3;
    } else {
      // Narrow screens: 1:1 square aspect ratio
      return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final aspectRatio = _getAspectRatio(availableWidth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row - compact
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(LucideIcons.image, size: 14, color: colors.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Live Preview',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                  ),
                  const Spacer(),
                  _CaptureStatusIndicator(colors: colors, pulseController: pulseController),
                ],
              ),

              const SizedBox(height: 10),

              // Image preview area - constrained height to prevent dominating screen
              // Max height of 400px ensures space for other content
              // On very narrow screens (<320px), use smaller min height
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 400,
                  minHeight: availableWidth < 320 ? 150 : 200,
                ),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _ImagePreviewArea(colors: colors),
                ),
              ),

              const SizedBox(height: 10),

              // Stats row
              _ImageStatsRow(colors: colors),
            ],
          );
        },
      ),
    );
  }
}

/// Capture status indicator - only rebuilds when capture state changes
class _CaptureStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;

  const _CaptureStatusIndicator({
    required this.colors,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));
    final isSessionCapturing = ref.watch(sessionStateProvider.select((s) => s.isCapturing));

    final isCapturing = isSessionCapturing || exposurePercent > 0 || isDownloading;

    return Row(
      children: [
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCapturing
                    ? colors.success.withValues(alpha: 0.3 + pulseController.value * 0.4)
                    : colors.textMuted.withValues(alpha: 0.3 + pulseController.value * 0.4),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          isCapturing ? 'Capturing' : 'Idle',
          style: TextStyle(
            fontSize: 12,
            color: isCapturing ? colors.success : colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Image preview area - only rebuilds when image or camera connection changes
class _ImagePreviewArea extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _ImagePreviewArea({required this.colors});

  @override
  ConsumerState<_ImagePreviewArea> createState() => _ImagePreviewAreaState();
}

class _ImagePreviewAreaState extends ConsumerState<_ImagePreviewArea> {
  double _currentZoom = 1.0;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final currentImage = ref.watch(currentImageProvider);
    final isConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            if (currentImage != null)
              Positioned.fill(
                child: AstroImageViewer(
                  imageData: currentImage.displayData,
                  width: currentImage.width,
                  height: currentImage.height,
                  isColor: currentImage.isColor,
                  minScale: 0.1,
                  maxScale: 10.0,
                  enableInteraction: true,
                  onTransformChanged: (controller) {
                    final scale = controller.value.getMaxScaleOnAxis();
                    if ((scale - _currentZoom).abs() > 0.01) {
                      setState(() => _currentZoom = scale);
                    }
                  },
                ),
              )
            else ...[
              CustomPaint(
                painter: _StarFieldPainter(colors: colors),
                size: Size.infinite,
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(LucideIcons.camera, size: 32, color: colors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isConnected ? 'No Image' : 'No Camera Connected',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected ? 'Take a snapshot or start a sequence' : 'Connect a camera in Equipment',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
            // Zoom indicator overlay in top-left
            if (currentImage != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${(_currentZoom * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            // Resolution overlay in top-right
            if (currentImage != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${currentImage.width} × ${currentImage.height}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Image stats row - only rebuilds when image stats change
class _ImageStatsRow extends ConsumerWidget {
  final NightshadeColors colors;

  const _ImageStatsRow({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastStats = ref.watch(lastImageStatsProvider);
    final currentImage = ref.watch(currentImageProvider);

    // Get image dimensions from current image
    final width = currentImage?.width;
    final height = currentImage?.height;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Top row - Image info
          Row(
            children: [
              _StatCell(label: 'Size', value: width != null && height != null ? '${width}x$height' : '---', colors: colors),
              _StatCell(label: 'Stars', value: lastStats?.starCount?.toString() ?? '---', colors: colors),
              _StatCell(label: 'HFR', value: lastStats?.hfr?.toStringAsFixed(2) ?? '---', colors: colors, highlight: true),
              _StatCell(label: 'FWHM', value: lastStats?.fwhm?.toStringAsFixed(2) ?? '---', colors: colors),
            ],
          ),
          const SizedBox(height: 4),
          // Bottom row - Pixel stats
          Row(
            children: [
              _StatCell(label: 'Mean', value: lastStats?.mean?.toStringAsFixed(0) ?? '---', colors: colors),
              _StatCell(label: 'Median', value: lastStats?.median?.toStringAsFixed(0) ?? '---', colors: colors),
              _StatCell(label: 'Min', value: lastStats?.min?.toStringAsFixed(0) ?? '---', colors: colors),
              _StatCell(label: 'Max', value: lastStats?.max?.toStringAsFixed(0) ?? '---', colors: colors),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact stat cell for the statistics grid
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const _StatCell({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  final NightshadeColors colors;

  _StarFieldPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint();

    for (var i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.3 + 0.1;
      final radius = random.nextDouble() * 1.5 + 0.5;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionProgressCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _SessionProgressCard({super.key, required this.colors});

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatIntegrationTime(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    return _formatDuration(duration);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final progress = ref.watch(sessionProgressProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);

    final isActive = sessionState.isActive;
    final progressValue = progress.clamp(0.0, 1.0);
    final targetName = sessionState.targetName ?? 'No target';

    // Format exposure count
    final exposureText = '${sessionState.completedExposures}/${sessionState.totalExposures}';

    // Format integration time
    final integrationText = sessionState.totalIntegrationSecs > 0
        ? _formatIntegrationTime(sessionState.totalIntegrationSecs)
        : '0m';

    // Format elapsed time
    final elapsedText = sessionState.startTime != null
        ? _formatDuration(DateTime.now().difference(sessionState.startTime!))
        : '---';

    // Calculate remaining time
    String remainingText = '---';
    if (isActive && progressValue > 0 && progressValue < 1.0 && sessionState.startTime != null) {
      final elapsed = DateTime.now().difference(sessionState.startTime!);
      final estimatedTotal = Duration(
        milliseconds: (elapsed.inMilliseconds / progressValue).round(),
      );
      final remaining = estimatedTotal - elapsed;
      if (remaining.inMilliseconds > 0) {
        remainingText = _formatDuration(remaining);
      }
    }

    // Current exposure info
    final currentExpText = '${exposureSettings.exposureTime}s ${exposureSettings.filter ?? "L"}';

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with target name
          Row(
            children: [
              Icon(
                LucideIcons.target,
                size: 14,
                color: isActive ? colors.success : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isActive ? targetName : 'Sequence',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  currentExpText,
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
                ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? colors.success.withValues(alpha: 0.15) : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? 'Running' : 'Idle',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isActive ? colors.success : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Progress bar with percentage
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: progressValue,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [colors.primary, colors.accent]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progressValue * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Current exposure progress row (only show when actively exposing)
          if (exposureProgress.percent > 0 || exposureProgress.isDownloading)
            _ExposureProgressRow(
              progress: exposureProgress,
              exposureTime: exposureSettings.exposureTime,
              colors: colors,
            ),

          if (exposureProgress.percent > 0 || exposureProgress.isDownloading)
            const SizedBox(height: 6),

          // Stats grid - compact layout
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                _CompactStat(label: 'Frm', value: exposureText, colors: colors),
                _CompactStat(label: 'Int', value: integrationText, colors: colors),
                _CompactStat(label: 'Elap', value: elapsedText, colors: colors),
                _CompactStat(label: 'Rem', value: remainingText, colors: colors, highlight: isActive),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows current exposure progress during active capture
class _ExposureProgressRow extends StatelessWidget {
  final ExposureProgress progress;
  final double exposureTime;
  final NightshadeColors colors;

  const _ExposureProgressRow({
    required this.progress,
    required this.exposureTime,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final elapsedText = progress.elapsed.toStringAsFixed(1);
    final totalText = exposureTime.toStringAsFixed(1);
    final progressPercent = (progress.percent / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            progress.isDownloading ? LucideIcons.download : LucideIcons.camera,
            size: 12,
            color: progress.isDownloading ? colors.info : colors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            progress.isDownloading
                ? 'Downloading...'
                : '$elapsedText s / $totalText s',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                widthFactor: progressPercent,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: progress.isDownloading ? colors.info : colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact stat for dense information display
class _CompactStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const _CompactStat({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SessionStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GuidingCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _GuidingCard({super.key, required this.colors});

  @override
  ConsumerState<_GuidingCard> createState() => _GuidingCardState();
}

class _GuidingCardState extends ConsumerState<_GuidingCard> {
  bool _isStartingOrStopping = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final guiderState = ref.watch(guiderStateProvider);
    final guideGraphData = ref.watch(guideGraphProvider);

    final isConnected = guiderState.connectionState == DeviceConnectionState.connected;
    final isGuiding = guiderState.isGuiding;
    final rmsTotal = guiderState.rmsTotal?.toStringAsFixed(2) ?? '---';
    final rmsRa = guiderState.rmsRa?.toStringAsFixed(2) ?? '---';
    final rmsDec = guiderState.rmsDec?.toStringAsFixed(2) ?? '---';

    // Guiding state text
    final stateText = !isConnected
        ? 'Disconnected'
        : _isStartingOrStopping
            ? (isGuiding ? 'Stopping...' : 'Starting...')
            : isGuiding
                ? 'Guiding'
                : 'Idle';

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with state and RMS inline
          Row(
            children: [
              Icon(
                LucideIcons.crosshair,
                size: 14,
                color: isGuiding ? colors.success : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Guiding',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
              ),
              const Spacer(),
              // Inline RMS values
              Text(
                '$rmsTotal"',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isGuiding ? colors.primary : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              // State badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isGuiding ? colors.success.withValues(alpha: 0.15) : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stateText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isGuiding ? colors.success : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Graph - compact height
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
            child: isConnected && guideGraphData.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CustomPaint(
                      painter: _DashboardGuidingGraphPainter(data: guideGraphData, colors: colors),
                      child: Container(),
                    ),
                  )
                : Center(
                    child: Text(
                      isConnected ? 'Click Start to begin' : 'Connect guider',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ),
          ),

          const SizedBox(height: 6),

          // Control button row
          Row(
            children: [
              // Stats row with legend
              Container(width: 10, height: 2, color: Colors.redAccent),
              const SizedBox(width: 3),
              Text('$rmsRa"', style: TextStyle(fontSize: 10, color: colors.textSecondary)),
              const SizedBox(width: 8),
              Container(width: 10, height: 2, color: Colors.blueAccent),
              const SizedBox(width: 3),
              Text('$rmsDec"', style: TextStyle(fontSize: 10, color: colors.textSecondary)),
              const Spacer(),
              // Start/Stop button
              SizedBox(
                height: 24,
                child: NightshadeButton(
                  label: isGuiding ? 'Stop' : 'Start',
                  icon: isGuiding ? LucideIcons.square : LucideIcons.play,
                  variant: isGuiding ? ButtonVariant.outline : ButtonVariant.primary,
                  size: ButtonSize.small,
                  onPressed: (!isConnected || _isStartingOrStopping)
                      ? null
                      : () => _toggleGuiding(isGuiding),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGuiding(bool isCurrentlyGuiding) async {
    setState(() => _isStartingOrStopping = true);
    try {
      final phd2Controller = ref.read(phd2ControllerProvider);
      if (isCurrentlyGuiding) {
        await phd2Controller.stopGuiding();
      } else {
        await phd2Controller.startGuiding();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${isCurrentlyGuiding ? 'stop' : 'start'} guiding: $e'),
            backgroundColor: widget.colors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingOrStopping = false);
      }
    }
  }
}

class _DashboardGuidingGraphPainter extends CustomPainter {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;

  _DashboardGuidingGraphPainter({required this.data, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paintRa = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintDec = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintZero = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    // Draw zero line
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paintZero);

    // Scale: +/- 4 arcsec range
    const range = 4.0;
    final scaleY = size.height / (range * 2);
    final stepX = size.width / 100; // Show last 100 points

    // Draw paths
    final pathRa = Path();
    final pathDec = Path();

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final x = size.width - ((data.length - 1 - i) * stepX);
      
      if (x < 0) continue;

      // Clamp values to range
      final raY = centerY - (point.ra.clamp(-range, range) * scaleY);
      final decY = centerY - (point.dec.clamp(-range, range) * scaleY);

      if (i == 0 || x < stepX) {
        pathRa.moveTo(x, raY);
        pathDec.moveTo(x, decY);
      } else {
        pathRa.lineTo(x, raY);
        pathDec.lineTo(x, decY);
      }
    }

    canvas.drawPath(pathRa, paintRa);
    canvas.drawPath(pathDec, paintDec);
  }

  @override
  bool shouldRepaint(covariant _DashboardGuidingGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class _CaptureSettingsCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _CaptureSettingsCard({super.key, required this.colors});

  @override
  ConsumerState<_CaptureSettingsCard> createState() =>
      _CaptureSettingsCardState();
}

class _CaptureSettingsCardState extends ConsumerState<_CaptureSettingsCard> {
  bool _isLooping = false;
  bool _isChangingFilter = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;
    final isFilterWheelConnected =
        filterWheelState.connectionState == DeviceConnectionState.connected;

    // Get actual filter names from connected filter wheel, or use defaults
    final filterNames = filterWheelState.filterNames.isNotEmpty
        ? filterWheelState.filterNames
        : const ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];

    // Current filter - use filter wheel position if connected, else from settings
    final currentFilterIndex = filterWheelState.currentPosition;
    final currentFilterName = isFilterWheelConnected &&
            currentFilterIndex != null &&
            currentFilterIndex >= 0 &&
            currentFilterIndex < filterNames.length
        ? filterNames[currentFilterIndex]
        : (exposureSettings.filter != null &&
                filterNames.contains(exposureSettings.filter)
            ? exposureSettings.filter!
            : filterNames.first);

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Settings - use Wrap for responsive layout
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Exposure
              _CompactSettingField(
                label: 'Exp',
                value: exposureSettings.exposureTime.toString(),
                suffix: 's',
                colors: colors,
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed > 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(exposureTime: parsed);
                  }
                },
              ),
              // Gain
              _CompactSettingField(
                label: 'Gain',
                value: exposureSettings.gain.toString(),
                colors: colors,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null && parsed >= 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(gain: parsed);
                  }
                },
              ),
              // Binning dropdown
              _CompactDropdown(
                label: 'Bin',
                value: exposureSettings.binning,
                items: const ['1x1', '2x2', '3x3', '4x4'],
                colors: colors,
                onChanged: (v) {
                  if (v != null) {
                    final parts = v.split('x');
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(
                      binningX: int.parse(parts[0]),
                      binningY: int.parse(parts[1]),
                    );
                  }
                },
              ),
              // Filter dropdown - uses actual filter names from connected filter wheel
              _CompactDropdown(
                label: 'Filter',
                value: currentFilterName,
                items: filterNames,
                colors: colors,
                highlight: true,
                onChanged: (_isChangingFilter || filterWheelState.isMoving)
                    ? null
                    : (v) => _onFilterChanged(v, filterNames),
              ),
              // Frame type dropdown
              _CompactDropdown(
                label: 'Frame',
                value: exposureSettings.frameType.displayName,
                items: FrameType.values.map((t) => t.displayName).toList(),
                colors: colors,
                onChanged: (v) {
                  if (v != null) {
                    final type = FrameType.values.firstWhere(
                      (t) => t.displayName == v,
                      orElse: () => FrameType.light,
                    );
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(frameType: type);
                  }
                },
              ),
              // Progress indicator when capturing
              if (isCapturing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: exposureProgress.percent,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(exposureProgress.percent * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                )
              else if (!isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'No Camera',
                    style: TextStyle(fontSize: 10, color: colors.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Capture buttons row - compact
          Row(
            children: [
              Expanded(
                flex: 2,
                child: NightshadeButton(
                  label: isCapturing
                      ? (exposureProgress.isDownloading ? 'Downloading...' : 'Capturing...')
                      : 'Capture',
                  icon: isCapturing ? LucideIcons.loader2 : LucideIcons.camera,
                  size: ButtonSize.small,
                  onPressed: (!isConnected || isCapturing) ? null : _captureImage,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NightshadeButton(
                  label: _isLooping ? 'Stop' : 'Loop',
                  icon: LucideIcons.repeat,
                  variant: _isLooping ? ButtonVariant.primary : ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: (!isConnected || isCapturing) ? null : _toggleLoop,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NightshadeButton(
                  label: 'Abort',
                  icon: LucideIcons.x,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: (isCapturing || _isLooping) ? _abortCapture : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _captureImage() async {
    try {
      final imagingService = ref.read(imagingServiceProvider);
      final settings = ref.read(exposureSettingsProvider);
      final result = await imagingService.captureImage(settings: settings);
      if (result != null && mounted) {
        ref.read(currentImageProvider.notifier).state = result;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  void _toggleLoop() async {
    if (_isLooping) {
      setState(() => _isLooping = false);
      return;
    }
    setState(() => _isLooping = true);
    while (_isLooping && mounted) {
      await _captureImage();
      if (_isLooping && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted) {
      setState(() => _isLooping = false);
    }
  }

  void _abortCapture() {
    setState(() => _isLooping = false);
    ref.read(imagingServiceProvider).cancelExposure();
  }

  /// Handle filter selection - updates settings AND moves the physical filter wheel
  Future<void> _onFilterChanged(String? filterName, List<String> filterNames) async {
    if (filterName == null) return;

    // Find the position index for this filter name
    final position = filterNames.indexOf(filterName);
    if (position < 0) return;

    // Always update exposure settings so filter is recorded in FITS headers
    final exposureSettings = ref.read(exposureSettingsProvider);
    ref.read(exposureSettingsProvider.notifier).state =
        exposureSettings.copyWith(filter: filterName);

    // If filter wheel is connected, actually move it
    final filterWheelState = ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      setState(() => _isChangingFilter = true);
      try {
        final deviceService = ref.read(deviceServiceProvider);
        await deviceService.setFilterWheelPosition(position);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to change filter: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isChangingFilter = false);
        }
      }
    }
  }
}

/// Compact text field for inline settings editing
class _CompactSettingField extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  const _CompactSettingField({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.suffix,
  });

  @override
  State<_CompactSettingField> createState() => _CompactSettingFieldState();
}

class _CompactSettingFieldState extends State<_CompactSettingField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CompactSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if the value changed externally (not from user input)
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.label}:',
          style: TextStyle(fontSize: 11, color: widget.colors.textMuted),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          height: 28,
          child: TextField(
            controller: _controller,
            style: TextStyle(fontSize: 12, color: widget.colors.textPrimary),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              filled: true,
              fillColor: widget.colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.colors.primary),
              ),
            ),
            onSubmitted: widget.onChanged,
          ),
        ),
        if (widget.suffix != null) ...[
          const SizedBox(width: 2),
          Text(widget.suffix!, style: TextStyle(fontSize: 10, color: widget.colors.textMuted)),
        ],
      ],
    );
  }
}

/// Compact dropdown for inline settings
class _CompactDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final NightshadeColors colors;
  final bool highlight;
  final ValueChanged<String?>? onChanged;

  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.colors,
    this.onChanged,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
        const SizedBox(width: 4),
        Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: highlight ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: highlight ? colors.primary.withValues(alpha: 0.3) : colors.border.withValues(alpha: 0.5),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: IgnorePointer(
                ignoring: !isEnabled,
                child: DropdownButton<String>(
                  value: value,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    color: highlight ? colors.primary : colors.textPrimary,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                  ),
                  dropdownColor: colors.surface,
                  icon: Icon(LucideIcons.chevronDown, size: 12, color: colors.textMuted),
                  items: items.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  )).toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MountControlCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _MountControlCard({super.key, required this.colors});

  static const double _expandedThreshold = 280.0;

  String _formatRa(double ra) {
    final hours = ra.floor();
    final minutes = ((ra - hours) * 60).floor();
    final seconds = (((ra - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDec(double dec) {
    final sign = dec >= 0 ? '+' : '-';
    final absDec = dec.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = (((absDec - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}°${minutes.toString().padLeft(2, '0')}\'${seconds.toString().padLeft(2, '0')}"';
  }

  String _trackingRateLabel(TrackingRate rate) {
    return switch (rate) {
      TrackingRate.sidereal => 'Sidereal',
      TrackingRate.lunar => 'Lunar',
      TrackingRate.solar => 'Solar',
      TrackingRate.king => 'King',
      TrackingRate.custom => 'Custom',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mountState = ref.watch(mountStateProvider);
    final isConnected = mountState.connectionState == DeviceConnectionState.connected;

    final raText = mountState.ra != null ? _formatRa(mountState.ra!) : '---';
    final decText = mountState.dec != null ? _formatDec(mountState.dec!) : '---';
    final pierText = isConnected ? (mountState.sideOfPier?.toUpperCase() ?? '---') : '---';

    // Status with color
    final (statusText, statusColor) = mountState.isSlewing
        ? ('Slewing', colors.warning)
        : mountState.isParked
            ? ('Parked', colors.textMuted)
            : mountState.isTracking
                ? ('Tracking', colors.success)
                : isConnected
                    ? ('Idle', colors.textSecondary)
                    : ('Off', colors.textMuted);

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isExpanded = constraints.maxWidth >= _expandedThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: mountState.isTracking ? colors.success.withValues(alpha: 0.1) : colors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      LucideIcons.move3d,
                      size: 14,
                      color: mountState.isTracking ? colors.success : colors.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Mount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Coordinates - NINA style
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RA', style: TextStyle(fontSize: 9, color: colors.textMuted)),
                          Text(raText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dec', style: TextStyle(fontSize: 9, color: colors.textMuted)),
                          Text(decText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Pier', style: TextStyle(fontSize: 9, color: colors.textMuted)),
                        Text(pierText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ),

              // Expanded mode: Directional controls and tracking rate
              if (isExpanded && isConnected) ...[
                const SizedBox(height: 10),

                // Directional jog controls (N/S/E/W)
                _MountDirectionalPad(
                  colors: colors,
                  isEnabled: isConnected && !mountState.isParked,
                  onDirection: (direction) {
                    ref.read(mountCommandServiceProvider).pulseGuide(context, direction);
                  },
                ),

                const SizedBox(height: 10),

                // Tracking rate selector
                Row(
                  children: [
                    Text('Rate:', style: TextStyle(fontSize: 10, color: colors.textMuted)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border.withValues(alpha: 0.5)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<TrackingRate>(
                            value: mountState.trackingRate,
                            isDense: true,
                            isExpanded: true,
                            style: TextStyle(fontSize: 11, color: colors.textPrimary),
                            dropdownColor: colors.surface,
                            icon: Icon(LucideIcons.chevronDown, size: 12, color: colors.textMuted),
                            items: TrackingRate.values.map((rate) => DropdownMenuItem(
                              value: rate,
                              child: Text(_trackingRateLabel(rate)),
                            )).toList(),
                            onChanged: mountState.canSetTrackingRate
                                ? (rate) {
                                    if (rate != null) {
                                      ref.read(deviceServiceProvider).setMountTrackingRate(rate.index);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: mountState.isParked ? 'Unpark' : 'Park',
                      icon: LucideIcons.parkingCircle,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).togglePark(context) : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: NightshadeButton(
                      label: mountState.isTracking ? 'Stop' : 'Track',
                      icon: LucideIcons.activity,
                      variant: mountState.isTracking ? ButtonVariant.primary : ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).toggleTracking(context) : null,
                    ),
                  ),
                ],
              ),
              if (mountState.isSlewing) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: NightshadeButton(
                    label: 'Abort Slew',
                    icon: LucideIcons.xCircle,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).abortSlew(context) : null,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Directional pad for mount jog controls (N/S/E/W).
class _MountDirectionalPad extends StatelessWidget {
  final NightshadeColors colors;
  final bool isEnabled;
  final void Function(String direction) onDirection;

  const _MountDirectionalPad({
    required this.colors,
    required this.isEnabled,
    required this.onDirection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // West button
          _DirectionalButton(
            icon: LucideIcons.chevronLeft,
            label: 'W',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onDirection('west'),
          ),
          const SizedBox(width: 2),
          // Column with North and South
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DirectionalButton(
                icon: LucideIcons.chevronUp,
                label: 'N',
                colors: colors,
                isEnabled: isEnabled,
                onPressed: () => onDirection('north'),
              ),
              const SizedBox(height: 2),
              _DirectionalButton(
                icon: LucideIcons.chevronDown,
                label: 'S',
                colors: colors,
                isEnabled: isEnabled,
                onPressed: () => onDirection('south'),
              ),
            ],
          ),
          const SizedBox(width: 2),
          // East button
          _DirectionalButton(
            icon: LucideIcons.chevronRight,
            label: 'E',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onDirection('east'),
          ),
        ],
      ),
    );
  }
}

/// Individual directional button for mount jog.
class _DirectionalButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _DirectionalButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: isEnabled ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _FocusCard({super.key, required this.colors});

  static const double _expandedThreshold = 280.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focuserState = ref.watch(focuserStateProvider);
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));
    final focusHistory = ref.watch(focusPositionHistoryProvider);
    final isConnected =
        focuserState.connectionState == DeviceConnectionState.connected;

    final positionText =
        focuserState.position != null ? '${focuserState.position}' : '---';
    final tempText = focuserState.temperature != null
        ? '${focuserState.temperature!.toStringAsFixed(1)}°C'
        : '---';
    final hfrText = hfr != null ? hfr.toStringAsFixed(2) : '---';

    return _GlassCard(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isExpanded = constraints.maxWidth >= _expandedThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.focus,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Focus',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    isConnected ? 'OK' : 'Off',
                    style: TextStyle(
                      fontSize: 11,
                      color: isConnected ? colors.success : colors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStat(
                    label: 'Pos',
                    value: positionText,
                    colors: colors,
                  ),
                  _MiniStat(
                    label: 'Temp',
                    value: tempText,
                    colors: colors,
                  ),
                  _MiniStat(
                    label: 'HFR',
                    value: hfrText,
                    colors: colors,
                  ),
                ],
              ),

              // Expanded mode: Show sparkline and fine focus controls
              if (isExpanded && isConnected) ...[
                const SizedBox(height: 10),

                // Focus position history sparkline
                if (focusHistory.length >= 2)
                  _FocusPositionSparkline(
                    positions: focusHistory,
                    colors: colors,
                  )
                else
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'Move focuser to see history',
                        style: TextStyle(fontSize: 10, color: colors.textMuted),
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                // Fine focus controls (+1/-1, +10/-10)
                _FineFocusControls(
                  colors: colors,
                  isEnabled: isConnected && !focuserState.isMoving,
                  onMove: (steps) async {
                    try {
                      await ref.read(deviceServiceProvider).moveFocuserRelative(steps);
                    } catch (e) {
                      if (context.mounted) {
                        context.showErrorSnackBar('Failed to move focuser: $e');
                      }
                    }
                  },
                ),
              ],

              const SizedBox(height: 12),

              // Autofocus button (always shown) or full controls in expanded
              if (!isExpanded)
                SizedBox(
                  width: double.infinity,
                  child: NightshadeButton(
                    label: 'Autofocus',
                    icon: LucideIcons.focus,
                    size: ButtonSize.small,
                    onPressed: isConnected ? () {
                      context.showInfoSnackBar('Use Focus tab for autofocus');
                    } : null,
                  ),
                )
              else
                const FocuserControls(
                  compact: true,
                  showAutofocus: true,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Sparkline widget showing focus position history with min/max labels.
class _FocusPositionSparkline extends StatelessWidget {
  final List<int> positions;
  final NightshadeColors colors;

  const _FocusPositionSparkline({
    required this.positions,
    required this.colors,
  });

  /// Format position value compactly (e.g., 12345 -> "12.3k")
  String _formatPosition(int position) {
    if (position >= 10000) {
      return '${(position / 1000).toStringAsFixed(1)}k';
    }
    return position.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          color: colors.surfaceAlt.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
        ),
      );
    }

    final minVal = positions.reduce(math.min);
    final maxVal = positions.reduce(math.max);
    final currentVal = positions.last;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Sparkline chart with left padding for labels
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: 28, right: 4, top: 4, bottom: 4),
              child: CustomPaint(
                size: const Size(double.infinity, 32),
                painter: _SparklinePainter(
                  values: positions.map((p) => p.toDouble()).toList(),
                  lineColor: colors.accent,
                  fillColor: colors.accent.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),

          // Max label (top-left)
          Positioned(
            left: 4,
            top: 2,
            child: Text(
              _formatPosition(maxVal),
              style: TextStyle(
                fontSize: 8,
                color: colors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),

          // Min label (bottom-left)
          Positioned(
            left: 4,
            bottom: 2,
            child: Text(
              _formatPosition(minVal),
              style: TextStyle(
                fontSize: 8,
                color: colors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),

          // Current value badge (right side)
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _formatPosition(currentVal),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: colors.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for sparkline chart.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color fillColor;

  _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final padding = 4.0;
    final chartWidth = size.width - (padding * 2);
    final chartHeight = size.height - (padding * 2);

    // Find min/max for scaling
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final range = maxVal - minVal;

    // If all values are the same, draw a flat line in the middle
    final normalizedValues = range == 0
        ? List.filled(values.length, 0.5)
        : values.map((v) => (v - minVal) / range).toList();

    // Build path
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < normalizedValues.length; i++) {
      final x = padding + (i / (normalizedValues.length - 1)) * chartWidth;
      final y = padding + (1 - normalizedValues[i]) * chartHeight;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - padding);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete fill path
    fillPath.lineTo(padding + chartWidth, size.height - padding);
    fillPath.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Draw current position dot (last point)
    if (normalizedValues.isNotEmpty) {
      final lastX = padding + chartWidth;
      final lastY = padding + (1 - normalizedValues.last) * chartHeight;
      final dotPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lastX, lastY), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}

/// Fine focus controls for step-by-step movement.
class _FineFocusControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool isEnabled;
  final void Function(int steps) onMove;

  const _FineFocusControls({
    required this.colors,
    required this.isEnabled,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FineStepButton(
            label: '-10',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onMove(-10),
          ),
          // Touch areas now adjacent - no spacer needed
          _FineStepButton(
            label: '-1',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onMove(-1),
          ),
          const SizedBox(width: 4),
          Text(
            'Fine',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(width: 4),
          _FineStepButton(
            label: '+1',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onMove(1),
          ),
          // Touch areas now adjacent - no spacer needed
          _FineStepButton(
            label: '+10',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onMove(10),
          ),
        ],
      ),
    );
  }
}

/// Individual button for fine focus steps.
///
/// Uses expanded touch target (48x40px) for field use with gloves while
/// maintaining compact visual appearance.
class _FineStepButton extends StatelessWidget {
  final String label;
  final NightshadeColors colors;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _FineStepButton({
    required this.label,
    required this.colors,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Expanded touch target: 48x40px for glove-friendly field use
    return SizedBox(
      width: 48,
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            // Visual element stays compact
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isEnabled ? colors.textPrimary : colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _AlertsCard({required this.colors});

  NightshadeAlertSeverity _mapSeverity(UiNotificationLevel level) {
    return switch (level) {
      UiNotificationLevel.info => NightshadeAlertSeverity.info,
      UiNotificationLevel.success => NightshadeAlertSeverity.success,
      UiNotificationLevel.warning => NightshadeAlertSeverity.warning,
      UiNotificationLevel.error => NightshadeAlertSeverity.error,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(uiNotificationProvider);
    final hasOperation = ref.watch(hasActiveOperationProvider);
    final recent = notifications.reversed.take(2).toList(); // Show fewer in compact

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.bell,
                  size: 16,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alerts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (notifications.isNotEmpty)
                NightshadeButton(
                  onPressed: () => ref
                      .read(uiNotificationProvider.notifier)
                      .clearAll(),
                  label: 'Clear',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasOperation) ...[
            const OperationStatusBar(),
            const SizedBox(height: 8),
          ],
          if (recent.isEmpty && !hasOperation)
            Text(
              'No active alerts.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            )
          else
            Column(
              children: recent
                  .map(
                    (notification) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: NightshadeAlert(
                        message: notification.message,
                        title: notification.title,
                        severity: _mapSeverity(notification.level),
                        compact: true,
                        onDismiss: () => ref
                            .read(uiNotificationProvider.notifier)
                            .dismiss(notification.id),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EquipmentStatusCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _EquipmentStatusCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only rebuild when connection state changes
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final mountConnected = ref.watch(mountStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final filterWheelConnected = ref.watch(filterWheelStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;

    final connectedCount = [cameraConnected, mountConnected, guiderConnected, focuserConnected, filterWheelConnected]
        .where((c) => c).length;

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                LucideIcons.plug,
                size: 14,
                color: connectedCount > 0 ? colors.success : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Equipment',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$connectedCount/5',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: connectedCount == 5 ? colors.success : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go('/equipment'),
                child: Text(
                  'Manage',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Compact horizontal icon row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CompactEquipmentIcon(
                  icon: LucideIcons.camera,
                  label: 'Cam',
                  isConnected: cameraConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.move3d,
                  label: 'Mnt',
                  isConnected: mountConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.crosshair,
                  label: 'Gdr',
                  isConnected: guiderConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.focus,
                  label: 'Foc',
                  isConnected: focuserConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.circle,
                  label: 'FW',
                  isConnected: filterWheelConnected,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact equipment status icon for horizontal display
class _CompactEquipmentIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isConnected;
  final NightshadeColors colors;

  const _CompactEquipmentIcon({
    required this.icon,
    required this.label,
    required this.isConnected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: ${isConnected ? "Connected" : "Disconnected"}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isConnected
                  ? colors.success.withValues(alpha: 0.15)
                  : colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isConnected ? colors.success.withValues(alpha: 0.3) : colors.border,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 14,
              color: isConnected ? colors.success : colors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: isConnected ? colors.textSecondary : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only rebuild when specific fields change
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));

    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));

    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final focuserPosition = ref.watch(focuserStateProvider.select((s) => s.position));

    // Format temperature (same logic as Imaging tab)
    String tempValue = '---';
    if (cameraConnected) {
      if (cameraTemp != null) {
        tempValue = '${cameraTemp.toStringAsFixed(1)}°C';
      } else {
        tempValue = 'N/A';
      }
    }

    // Format RMS (same logic as Imaging tab)
    String rmsValue = '---';
    if (guiderConnected && guiderIsGuiding && guiderRms != null) {
      rmsValue = '${guiderRms.toStringAsFixed(2)}"';
    }

    // Format HFR (same logic as Imaging tab)
    String hfrValue = '---';
    if (hfr != null) {
      hfrValue = hfr.toStringAsFixed(2);
    }

    // Format Focus position
    String focusValue = '---';
    if (focuserConnected) {
      if (focuserPosition != null) {
        focusValue = focuserPosition.toString();
      } else {
        focusValue = 'N/A';
      }
    }

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(0),
      child: Row(
        children: [
          _QuickStatItem(
            icon: LucideIcons.thermometer,
            label: 'Sensor',
            value: tempValue,
            colors: colors,
            isFirst: true,
          ),
          _QuickStatItem(
            icon: LucideIcons.focus,
            label: 'Focus',
            value: focusValue,
            colors: colors,
          ),
          _QuickStatItem(
            icon: LucideIcons.target,
            label: 'HFR',
            value: hfrValue,
            colors: colors,
          ),
          _QuickStatItem(
            icon: LucideIcons.activity,
            label: 'RMS',
            value: rmsValue,
            colors: colors,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _QuickStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isFirst;
  final bool isLast;

  const _QuickStatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  right: BorderSide(
                    color: colors.border.withValues(alpha: 0.5),
                  ),
                ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TonightCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _TonightCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moonInfo = ref.watch(moonInfoProvider);

    // Use select() to only watch the time field
    final now = ref.watch(observationTimeProvider.select((s) => s.time));

    // Format astro twilight time
    String astroTwilightTime = '--:--';
    if (twilight.astronomicalDusk != null) {
      final dusk = twilight.astronomicalDusk!;
      // If dusk is in the future (relative to simulation time), show it
      if (dusk.isAfter(now)) {
        astroTwilightTime = '${dusk.hour.toString().padLeft(2, '0')}:${dusk.minute.toString().padLeft(2, '0')}';
      } else {
        // Dusk already passed, show dawn
        if (twilight.astronomicalDawn != null) {
          final dawn = twilight.astronomicalDawn!;
          astroTwilightTime = '${dawn.hour.toString().padLeft(2, '0')}:${dawn.minute.toString().padLeft(2, '0')}';
        }
      }
    }

    // Format moon info - compact version without moonrise time
    final moonValue = '${moonInfo.illumination.toStringAsFixed(0)}%';

    // Calculate imaging window (darkness duration)
    String imagingWindow = '--:--';
    if (twilight.astronomicalDusk != null && twilight.astronomicalDawn != null) {
      final duration = twilight.astronomicalDawn!.difference(twilight.astronomicalDusk!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      imagingWindow = '${hours}h ${minutes}m';
    }

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.moon,
                  size: 16,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Tonight',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _TonightRow(
            icon: LucideIcons.sunset,
            label: 'Twilight',
            value: astroTwilightTime,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.moonStar,
            label: 'Moon',
            value: moonValue,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.timer,
            label: 'Window',
            value: imagingWindow,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _TonightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TonightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Quick Actions card with responsive layout.
///
/// Adapts to available width:
/// - Narrow (<280px): Single column stack
/// - Medium (280-400px): 2x2 grid
/// - Wide (>400px): Single row with all 4 buttons
class _QuickActionsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickActionsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mount capabilities to gate Park button
    final mountState = ref.watch(mountStateProvider);
    final mountCapabilitiesAsync = ref.watch(
        mountCapabilitiesProvider(mountState.deviceId ?? ''));
    final mountCapabilities = mountCapabilitiesAsync.valueOrNull;

    // Build action buttons with their callbacks
    final actionButtons = [
      _ActionButtonData(
        icon: LucideIcons.camera,
        label: 'Snapshot',
        onTap: () => _handleSnapshot(context, ref),
      ),
      _ActionButtonData(
        icon: LucideIcons.focus,
        label: 'Autofocus',
        onTap: () => _handleAutofocus(context, ref),
      ),
      _ActionButtonData(
        icon: LucideIcons.crosshair,
        label: 'Center',
        onTap: () => _handleCenter(context, ref),
      ),
      _ActionButtonData(
        icon: LucideIcons.parkingCircle,
        label: 'Park',
        onTap: (mountCapabilities?.canPark ?? true)
            ? () => ref.read(mountCommandServiceProvider).park(context)
            : null,
      ),
    ];

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          // Responsive button layout
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (width < 280) {
                // Narrow: Single column stack
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      _ActionButton(
                        icon: actionButtons[i].icon,
                        label: actionButtons[i].label,
                        colors: colors,
                        onTap: actionButtons[i].onTap,
                      ),
                      if (i < actionButtons.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              } else if (width < 400) {
                // Medium: 2x2 grid
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[0].icon,
                            label: actionButtons[0].label,
                            colors: colors,
                            onTap: actionButtons[0].onTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[1].icon,
                            label: actionButtons[1].label,
                            colors: colors,
                            onTap: actionButtons[1].onTap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[2].icon,
                            label: actionButtons[2].label,
                            colors: colors,
                            onTap: actionButtons[2].onTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: actionButtons[3].icon,
                            label: actionButtons[3].label,
                            colors: colors,
                            onTap: actionButtons[3].onTap,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              } else {
                // Wide: Single row with all buttons
                return Row(
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: actionButtons[i].icon,
                          label: actionButtons[i].label,
                          colors: colors,
                          onTap: actionButtons[i].onTap,
                        ),
                      ),
                      if (i < actionButtons.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleSnapshot(BuildContext context, WidgetRef ref) async {
    try {
      final settings = ref.read(exposureSettingsProvider);
      final imagingService = ref.read(imagingServiceProvider);
      final sessionNotifier = ref.read(sessionStateProvider.notifier);

      sessionNotifier.setCapturing(true);

      final result = await imagingService.captureImage(
        settings: settings,
        targetName: ref.read(sessionStateProvider).targetName,
      );

      if (result != null) {
        ref.read(currentImageProvider.notifier).state = result;
        ref.read(lastImageStatsProvider.notifier).state = result.stats;
        sessionNotifier.recordExposureComplete(
          exposureTime: settings.exposureTime,
          hfr: result.stats.hfr,
        );

        if (!context.mounted) return;
        context.showSuccessSnackBar('Snapshot captured');
      }
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Snapshot failed: $e');
    } finally {
      ref.read(sessionStateProvider.notifier).setCapturing(false);
    }
  }

  Future<void> _handleAutofocus(BuildContext context, WidgetRef ref) async {
    final cameraState = ref.read(cameraStateProvider);
    final focuserState = ref.read(focuserStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      context.showErrorSnackBar('Camera not connected');
      return;
    }

    if (focuserState.connectionState != DeviceConnectionState.connected) {
      context.showErrorSnackBar('Focuser not connected');
      return;
    }

    // Show progress notification - the device service will handle detailed progress
    // via activeOperationsProvider, but we show a quick snackbar for immediate feedback
    context.showInfoSnackBar(
      'Starting autofocus...',
      duration: const Duration(seconds: 2),
    );

    try {
      final deviceService = ref.read(deviceServiceProvider);
      final result = await deviceService.runAutofocus(
        exposureTime: 3.0,
        stepSize: 100,
        stepsOut: 7,
        method: 'VCurve',
        binning: 1,
      );

      if (!context.mounted) return;

      // Show success with key result metrics
      final hfrText = result.bestHfr.toStringAsFixed(2);
      final posText = result.bestPosition.toString();
      context.showSuccessSnackBar(
        'Autofocus complete: Position $posText, HFR $hfrText',
      );
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Autofocus failed: $e');
    }
  }

  void _handleCenter(BuildContext context, WidgetRef ref) {
    // Check if we have a target set
    final session = ref.read(sessionStateProvider);
    final targetRa = session.targetRa;
    final targetDec = session.targetDec;

    if (targetRa == null || targetDec == null) {
      context.showWarningSnackBar(
        'No target set. Please set a target first.',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    // Show centering dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CenteringDialog(
          ref: ref,
          targetRa: targetRa,
          targetDec: targetDec,
          targetName: session.targetName ?? 'Target',
          colors: colors,
        ),
      );
    }
  }
}

/// Data class for action button configuration.
class _ActionButtonData {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButtonData({
    required this.icon,
    required this.label,
    this.onTap,
  });
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.primary.withValues(alpha: 0.1)
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? widget.colors.primary : widget.colors.border,
            ),
          ),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 16,
              color: _isHovered
                  ? widget.colors.primary
                  : widget.colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _isHovered
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final EdgeInsets padding;

  const _GlassCard({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Centering dialog for plate solving and centering on target
class _CenteringDialog extends StatefulWidget {
  final WidgetRef ref;
  final double targetRa;
  final double targetDec;
  final String targetName;
  final NightshadeColors colors;

  const _CenteringDialog({
    required this.ref,
    required this.targetRa,
    required this.targetDec,
    required this.targetName,
    required this.colors,
  });

  @override
  State<_CenteringDialog> createState() => _CenteringDialogState();
}

class _CenteringDialogState extends State<_CenteringDialog> {
  String _status = 'Initializing...';
  bool _isRunning = true;
  int _iteration = 0;
  static const int _maxIterations = 3;
  double? _lastRaError;
  double? _lastDecError;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _runCentering();
  }

  Future<void> _runCentering() async {
    try {
      final imagingService = widget.ref.read(imagingServiceProvider);
      final mountService = widget.ref.read(mountCommandServiceProvider);
      final settings = widget.ref.read(appSettingsProvider).value;
      final astapPath = settings?.astapPath ?? '';

      // Use user-configured exposure settings for centering captures
      final userSettings = widget.ref.read(exposureSettingsProvider);
      final centeringSettings = ExposureSettings(
        exposureTime: userSettings.exposureTime > 0 ? userSettings.exposureTime : 5.0,
        gain: userSettings.gain,
        offset: userSettings.offset,
        binningX: userSettings.binningX > 0 ? userSettings.binningX : 2,
        binningY: userSettings.binningY > 0 ? userSettings.binningY : 2,
      );

      while (_iteration < _maxIterations && _isRunning) {
        _iteration++;

        // Step 1: Take an image
        setState(() => _status = 'Capturing image (attempt $_iteration/$_maxIterations)...');

        final image = await imagingService.captureImage(
          settings: centeringSettings,
          targetName: 'center_${widget.targetName}',
        );
        
        if (image == null || image.filePath == null) {
          setState(() => _status = 'Failed to capture image');
          return;
        }
        
        // Step 2: Plate solve
        setState(() => _status = 'Plate solving...');

        // PlateSolveService tries backend.plateSolve() first (works for both local and remote)
        // Only falls back to local solver if backend fails
        final executablePath = await PlateSolverUtils.findAstapExecutable(astapPath);

        final result = await widget.ref.read(plateSolveServiceProvider).solve(
          image.filePath!,
          PlateSolverConfig(
            type: PlateSolverType.astap,
            hintRa: widget.targetRa,
            hintDec: widget.targetDec,
            searchRadius: 15.0,
            // Provide path for local fallback - backend is tried first
            executablePath: executablePath ?? '',
          ),
        );
        
        if (!result.success || result.ra == null || result.dec == null) {
          setState(() => _status = 'Plate solve failed: ${result.errorMessage ?? "Unknown error"}');
          return;
        }
        
        // Step 3: Calculate error
        // RA is in hours, Dec is in degrees. Convert both to arcsec for display.
        // 1 hour RA = 15 degrees = 54000 arcsec
        final raErrorArcsec = (result.ra! - widget.targetRa) * 15.0 * 3600.0; // hours to arcsec
        final decErrorArcsec = (result.dec! - widget.targetDec) * 3600.0; // degrees to arcsec
        final totalErrorArcsec = math.sqrt(raErrorArcsec * raErrorArcsec + decErrorArcsec * decErrorArcsec);
        
        setState(() {
          _lastRaError = raErrorArcsec;
          _lastDecError = decErrorArcsec;
          _status = 'Error: ${totalErrorArcsec.toStringAsFixed(1)}" (RA: ${raErrorArcsec.toStringAsFixed(1)}", Dec: ${decErrorArcsec.toStringAsFixed(1)}")';
        });
        
        // Check if centered enough (within 30 arcseconds)
        if (totalErrorArcsec < 30.0) {
          setState(() {
            _success = true;
            _status = 'Centered! Error: ${totalErrorArcsec.toStringAsFixed(1)}"';
          });
          break;
        }
        
        // Step 4: Slew to corrected position
        setState(() => _status = 'Slewing to corrected position...');

        // Convert arcsec error back to coordinate units for correction
        // RA: arcsec / (15 * 3600) = hours, Dec: arcsec / 3600 = degrees
        final newRa = widget.targetRa - (raErrorArcsec / (15.0 * 3600.0)); // Correct for offset (hours)
        final newDec = widget.targetDec - (decErrorArcsec / 3600.0); // Correct for offset (degrees)

        // Use service without feedback - dialog shows its own status
        await mountService.slewTo(context, newRa, newDec, showFeedback: false);
        
        // Wait for slew to complete
        await Future.delayed(const Duration(seconds: 2));
        
        // Small delay before next iteration
        await Future.delayed(const Duration(seconds: 1));
      }
      
      if (!_success && _iteration >= _maxIterations) {
        setState(() {
          _status = 'Max iterations reached. Last error: RA ${_lastRaError?.toStringAsFixed(1)}", Dec ${_lastDecError?.toStringAsFixed(1)}"';
        });
      }
      
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 400;

    return AlertDialog(
      backgroundColor: widget.colors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.colors.border),
      ),
      title: Row(
        children: [
          Icon(
            _success ? LucideIcons.checkCircle : LucideIcons.crosshair,
            color: _success ? widget.colors.success : widget.colors.primary,
            size: isSmallScreen ? 20 : 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSmallScreen ? 'Centering' : 'Centering on ${widget.targetName}',
              style: TextStyle(
                color: widget.colors.textPrimary,
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isRunning)
            const LinearProgressIndicator()
          else if (_success)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle, color: widget.colors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target centered successfully!',
                      style: TextStyle(color: widget.colors.success, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(color: widget.colors.textSecondary, fontSize: 14),
          ),
          if (_lastRaError != null || _lastDecError != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('RA Error:', style: TextStyle(color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastRaError?.toStringAsFixed(1) ?? "---"}"', 
                     style: TextStyle(color: widget.colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dec Error:', style: TextStyle(color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastDecError?.toStringAsFixed(1) ?? "---"}"', 
                     style: TextStyle(color: widget.colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Iteration: $_iteration / $_maxIterations',
            style: TextStyle(color: widget.colors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (_isRunning)
          NightshadeButton(
            onPressed: () {
              setState(() => _isRunning = false);
            },
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          )
        else
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
      ],
    );
  }
}

