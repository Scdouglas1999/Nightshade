import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/contextual_tour_prompt.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_provider.dart';
import 'widgets/command_bar.dart';
import 'widgets/dashboard_header_actions.dart';
import 'widgets/dashboard_tile.dart';
import 'widgets/dashboard_widget_registry.dart';
import 'widgets/widget_picker_dialog.dart';
import 'widgets/zone_layout.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    // Pulse is created stopped; build() drives it based on device activity so
    // it doesn't burn frames on an idle dashboard.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Ensure PHD2 controller is active and listening to events
    ref.watch(phd2ControllerProvider);
    final layoutAsync = ref.watch(dashboardLayoutProvider);

    // Drive the pulse only while there is something to indicate. Watching the
    // session + connection states here keeps the gating reactive without
    // leaking listeners into every consumer of pulseController.
    final sessionCapturing =
        ref.watch(sessionStateProvider.select((s) => s.isCapturing));
    final cameraConnected = ref.watch(cameraStateProvider
            .select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final mountConnected = ref.watch(mountStateProvider
            .select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final guiderConnected = ref.watch(guiderStateProvider
            .select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final focuserConnected = ref.watch(focuserStateProvider
            .select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final shouldPulse = sessionCapturing ||
        cameraConnected ||
        mountConnected ||
        guiderConnected ||
        focuserConnected;
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
    }

    return ContextualTourPrompt(
      screenId: 'dashboard',
      tourCategory: TutorialCategory.dashboardTour,
      title: context.l10n.text('dashboardTourTitle'),
      description: context.l10n.text('dashboardTourDescription'),
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
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
              ref
                  .read(dashboardLayoutProvider.notifier)
                  .reorder(dragged, target);
            },
            onResize: (id) {
              final tile = layout.tiles.firstWhere((t) => t.widgetId == id);
              ref
                  .read(dashboardLayoutProvider.notifier)
                  .setTileSize(id, tile.size.next());
            },
            onToggleEnabled: (id, enabled) {
              ref
                  .read(dashboardLayoutProvider.notifier)
                  .setTileEnabled(id, enabled);
            },
            onSetZone: (id, zone) {
              ref.read(dashboardLayoutProvider.notifier).setTileZone(id, zone);
            },
          ),
          loading: () => const DashboardLoading(),
          error: (error, _) => DashboardLayoutError(
            error: error,
            onReset: _resetLayout,
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
      builder: (context) => const WidgetPickerDialog(),
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
/// - >=1280px: Full three-zone layout
/// - 1024-1280px: Two-column compact (primary + secondary, no inline tertiary split)
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
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target)
      onReorder;
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

        // Responsive layout selection based on breakpoints. The 1280 cutoff
        // covers most laptops where the full three-column split would crush
        // the secondary column under its 280 px clamp.
        if (screenWidth < NightshadeTokens.breakpointTablet) {
          return _buildCompactLayout(context);
        } else if (screenWidth < NightshadeTokens.breakpointDesktop) {
          return _buildStackedLayout(context);
        } else if (screenWidth < _twoColumnFullThreshold) {
          return _buildTwoColumnCompactLayout(context, constraints);
        } else {
          return _buildFullLayout(context, constraints);
        }
      },
    );
  }

  // Width at which the full three-column split has enough room for both the
  // hero zone and a usable secondary column without starving either.
  static const double _twoColumnFullThreshold = 1280.0;

  /// Full three-zone layout for wide screens (>1024px)
  Widget _buildFullLayout(BuildContext context, BoxConstraints constraints) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final primaryTiles = layout.tilesForZone(DashboardZone.primary);
    final secondaryTiles = layout.tilesForZone(DashboardZone.secondary);
    final tertiaryTiles = layout.tilesForZone(DashboardZone.tertiary);

    // Calculate zone widths
    final availableWidth = constraints.maxWidth - 48; // padding
    final secondaryWidth =
        (availableWidth * layout.secondaryZoneWidth).clamp(280.0, 360.0);
    final primaryWidth = availableWidth - secondaryWidth - 16; // gap

    // On wide screens, split tertiary cards between primary and secondary zones
    final tertiaryForPrimary = <DashboardTileConfig>[];
    final tertiaryForSecondary = <DashboardTileConfig>[];

    for (final tile in tertiaryTiles) {
      if (tile.widgetId == DashboardWidgetId.mountControl ||
          tile.widgetId == DashboardWidgetId.focus) {
        tertiaryForPrimary.add(tile);
      } else {
        tertiaryForSecondary.add(tile);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Command Bar (fixed)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: DashboardCommandBar(
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
            child: EditModeBanner(colors: colors),
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
                        DashboardZoneColumn(
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
                          TertiaryZoneRow(
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
                        DashboardZoneColumn(
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
                            if (definition == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DashboardTile(
                                tile: tile,
                                width: double.infinity,
                                colors: colors,
                                isEditing: isEditing,
                                cardVariant: CardVariant.standard,
                                isHero: false,
                                onReorder: onReorder,
                                onResize: onResize,
                                onToggleEnabled: onToggleEnabled,
                                child: Builder(
                                  builder: (context) => definition.builder(
                                      context, colors, pulseController),
                                ),
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

  /// Intermediate two-column layout for 1024-1280 px (most laptops).
  ///
  /// At this width the full layout's 280-360 px secondary column clamp leaves
  /// the primary too narrow for the hero preview. Drop the inline tertiary
  /// split and let tertiary cards run as a single wrap below the two columns.
  Widget _buildTwoColumnCompactLayout(
      BuildContext context, BoxConstraints constraints) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final primaryTiles = layout.tilesForZone(DashboardZone.primary);
    final secondaryTiles = layout.tilesForZone(DashboardZone.secondary);
    final tertiaryTiles = layout.tilesForZone(DashboardZone.tertiary);

    // Reserve more room for the hero zone than the full layout does, since
    // the secondary tiles can be skimmed via scroll without losing context.
    const horizontalPadding = 32.0;
    const columnGap = 16.0;
    final availableWidth = constraints.maxWidth - horizontalPadding;
    final secondaryWidth =
        ((availableWidth - columnGap) * 0.36).clamp(300.0, 380.0);
    final primaryWidth = availableWidth - secondaryWidth - columnGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DashboardCommandBar(
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
            child: EditModeBanner(colors: colors),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: primaryWidth,
                      child: DashboardZoneColumn(
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
                    ),
                    const SizedBox(width: columnGap),
                    SizedBox(
                      width: secondaryWidth,
                      child: DashboardZoneColumn(
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
                    ),
                  ],
                ),
                if (tertiaryTiles.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TertiaryZoneRow(
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Stacked layout for medium screens (768-1024px)
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
          child: DashboardCommandBar(
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
            child: EditModeBanner(colors: colors),
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
                DashboardZoneColumn(
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
                  TertiaryZoneRow(
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
                DashboardZoneColumn(
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
  Widget _buildCompactLayout(BuildContext context) {
    final registry = {for (final def in dashboardWidgetRegistry) def.id: def};
    final allTiles = layout.tiles.where((t) => t.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Categorize tiles for mobile-optimized ordering
    final weatherTile = allTiles
        .where((t) => t.widgetId == DashboardWidgetId.weather)
        .firstOrNull;
    final livePreviewTile = allTiles
        .where((t) => t.widgetId == DashboardWidgetId.livePreview)
        .firstOrNull;
    final captureSettingsTile = allTiles
        .where((t) => t.widgetId == DashboardWidgetId.captureSettings)
        .firstOrNull;
    final quickActionsTile = allTiles
        .where((t) => t.widgetId == DashboardWidgetId.quickActions)
        .firstOrNull;
    final sessionTile = allTiles
        .where((t) => t.widgetId == DashboardWidgetId.sequenceStatus)
        .firstOrNull;

    // Equipment-related tiles for wrap layout
    final equipmentTiles = allTiles
        .where((t) =>
            t.widgetId == DashboardWidgetId.equipmentStatus ||
            t.widgetId == DashboardWidgetId.mountControl ||
            t.widgetId == DashboardWidgetId.focus)
        .toList();

    // Other tiles (guiding, tonight, alerts, quick stats)
    final otherTiles = allTiles
        .where((t) =>
            t.widgetId != DashboardWidgetId.weather &&
            t.widgetId != DashboardWidgetId.livePreview &&
            t.widgetId != DashboardWidgetId.captureSettings &&
            t.widgetId != DashboardWidgetId.quickActions &&
            t.widgetId != DashboardWidgetId.sequenceStatus &&
            t.widgetId != DashboardWidgetId.equipmentStatus &&
            t.widgetId != DashboardWidgetId.mountControl &&
            t.widgetId != DashboardWidgetId.focus)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact Command Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: CompactDashboardCommandBar(
            colors: colors,
            pulseController: pulseController,
            isEditing: isEditing,
            onToggleEdit: onToggleEdit,
          ),
        ),

        if (isEditing)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: EditModeBanner(colors: colors),
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
                    context: context,
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
                    context: context,
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
                    context: context,
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
                    context: context,
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
                    context: context,
                    tile: sessionTile,
                    registry: registry,
                    cardVariant: CardVariant.standard,
                    isHero: false,
                  ),
                  const SizedBox(height: 12),
                ],

                // 6. Equipment tiles in responsive wrap layout
                if (equipmentTiles.isNotEmpty) ...[
                  MobileEquipmentSection(
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
                    context: context,
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
    required BuildContext context,
    required DashboardTileConfig tile,
    required Map<DashboardWidgetId, DashboardWidgetDefinition> registry,
    required CardVariant cardVariant,
    required bool isHero,
  }) {
    final definition = registry[tile.widgetId];
    if (definition == null) return const SizedBox.shrink();

    final child = definition.builder(
      context,
      colors,
      pulseController,
    );

    return DashboardTile(
      tile: tile,
      width: double.infinity,
      colors: colors,
      isEditing: isEditing,
      cardVariant: cardVariant,
      isHero: isHero,
      onReorder: onReorder,
      onResize: onResize,
      onToggleEnabled: onToggleEnabled,
      child: child,
    );
  }
}
