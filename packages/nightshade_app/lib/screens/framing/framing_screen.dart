import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;
import 'framing_search_provider.dart';
import 'altitude_chart.dart';
import 'package:nightshade_app/utils/snackbar_helper.dart';
import 'package:nightshade_app/widgets/slew_dropdown_button.dart';
import 'framing_altaz.dart';
import '../../widgets/tutorial_keys/framing_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../suggestions/widgets/suggestion_card.dart';
import '../suggestions/widgets/suggestion_filters.dart';
import 'widgets/optical_config_panel.dart';

/// The main framing screen that contains two tabs:
/// 1. Framing - For composing and framing astrophotography targets
/// 2. Suggestions - For viewing tonight's target suggestions
class FramingScreen extends ConsumerStatefulWidget {
  const FramingScreen({super.key});

  @override
  ConsumerState<FramingScreen> createState() => _FramingScreenState();
}

class _FramingScreenState extends ConsumerState<FramingScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _raController = TextEditingController();
  final _decController = TextEditingController();

  late TabController _tabController;

  /// Currently selected tab index (0 = Framing, 1 = Suggestions)
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    // Alt/Az is recomputed lazily in build() from target + settings; no need
    // for a periodic poll that fires while the screen is off-tab/off-focus.
    // Load the most recent target if no target is currently set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPersistedTarget();
    });
  }

  Future<void> _loadPersistedTarget() async {
    // Honor inbound query params first: /framing?ra=<hours>&dec=<deg>&name=<n>.
    // The planning workspace uses this to hand off a chosen target to framing.
    final applied = _applyQueryParamsTarget();

    final framingState = ref.read(framingProvider);
    if (!applied && framingState.target == null) {
      // No target in provider, try to load from database
      await ref.read(framingProvider.notifier).loadMostRecentTarget();
    }
    // Always sync controllers with provider state (handles navigation back to tab)
    final currentState = ref.read(framingProvider);
    if (currentState.target != null) {
      _searchController.text = currentState.target!.name;
      _raController.text = currentState.target!.raFormatted;
      _decController.text = currentState.target!.decFormatted;
    }
  }

  /// Parses `?ra=&dec=&name=` from the current GoRouter location and, when
  /// valid, hands the target to the framing provider. Returns true if a
  /// target was applied. RA is in decimal hours, Dec is in decimal degrees.
  bool _applyQueryParamsTarget() {
    if (!mounted) return false;
    final Uri uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {
      // Why: framing screen is reachable outside the GoRouter tree in tests.
      return false;
    }
    final params = uri.queryParameters;
    final raStr = params['ra'];
    final decStr = params['dec'];
    if (raStr == null || decStr == null) return false;

    final raHours = double.tryParse(raStr);
    final decDegrees = double.tryParse(decStr);
    if (raHours == null || decDegrees == null) return false;
    if (raHours < 0 || raHours >= 24) return false;
    if (decDegrees < -90 || decDegrees > 90) return false;

    final name = params['name']?.trim();
    ref.read(framingProvider.notifier).setTargetCoordinates(
          raHours,
          decDegrees,
          name: (name == null || name.isEmpty) ? null : name,
        );
    return true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _raController.dispose();
    _decController.dispose();
    super.dispose();
  }

  /// Compute current alt/az from target + location lazily during build.
  /// Returns null when no target or no usable location is available.
  (double, double)? _computeCurrentAltAz(
    FramingTarget? target,
    AppSettings? settings,
  ) {
    if (target == null || settings == null) return null;
    final lat = settings.latitude;
    final lon = settings.longitude;
    // (0,0) is the sentinel for "no location set"; avoid reporting nonsense.
    if (lat == 0.0 && lon == 0.0) return null;
    return calculateCurrentAltAz(
      raHours: target.raHours,
      decDegrees: target.decDegrees,
      latitudeDeg: lat,
      longitudeDeg: lon,
      time: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final framingState = ref.watch(framingProvider);
    final searchState = ref.watch(targetSearchProvider);
    final equipmentResult = ref.watch(framingFOVProvider);
    // Recompute alt/az lazily on each build (cheap trig, no IO). This naturally
    // refreshes whenever the framing target or location settings change; the
    // previous 10-second periodic timer fired even when off-tab/off-focus.
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final currentAltAz = _computeCurrentAltAz(framingState.target, settings);

    return Column(
      children: [
        // Tab bar header
        _buildTabBar(colors),

        // Tab content
        Expanded(
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              // Tab 0: Framing
              _buildFramingContent(colors, framingState, searchState,
                  equipmentResult, currentAltAz),
              // Tab 1: Suggestions
              _SuggestionsTab(
                onTargetSelected: (suggestion) =>
                    _navigateToFramingWithTarget(suggestion),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the tab bar header
  Widget _buildTabBar(NightshadeColors colors) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Framing tab
          _TabButton(
            icon: LucideIcons.frame,
            label: 'Framing',
            isSelected: _currentTabIndex == 0,
            colors: colors,
            onTap: () {
              _tabController.animateTo(0);
              setState(() => _currentTabIndex = 0);
            },
          ),
          // Suggestions tab
          _TabButton(
            icon: LucideIcons.lightbulb,
            label: 'Suggestions',
            isSelected: _currentTabIndex == 1,
            colors: colors,
            onTap: () {
              _tabController.animateTo(1);
              setState(() => _currentTabIndex = 1);
            },
          ),
          const Spacer(),
          // Quick actions based on current tab
          if (_currentTabIndex == 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    onPressed: () {
                      ref.read(refreshSuggestionsProvider.notifier).state++;
                    },
                    tooltip: 'Refresh suggestions',
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.slidersHorizontal, size: 18),
                    onPressed: () =>
                        _showSuggestionFilterSheet(context, colors),
                    tooltip: 'Filter options',
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the main framing content (original framing UI)
  Widget _buildFramingContent(
    NightshadeColors colors,
    FramingState framingState,
    TargetSearchState searchState,
    AsyncValue<FramingEquipmentResult> equipmentResult,
    (double, double)? currentAltAz,
  ) {
    return ContextualTourPrompt(
      screenId: 'framing',
      tourCategory: TutorialCategory.framingTour,
      title: 'Framing Tour',
      description:
          'Learn how to frame and compose your astrophotography targets.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Row(
        children: [
          // Main framing canvas with optical config overlay
          Expanded(
            child: Stack(
              children: [
                // The framing canvas fills the entire area
                Positioned.fill(
                  child: _FramingCanvas(
                    key: FramingTutorialKeys.canvas,
                    colors: colors,
                    framingState: framingState,
                    equipmentResult: equipmentResult.valueOrNull,
                    onPan: (dx, dy) {
                      ref.read(framingProvider.notifier).pan(dx, dy);
                    },
                    onRotate: (angle) {
                      ref.read(framingProvider.notifier).setRotation(angle);
                    },
                  ),
                ),
                // Optical config panel overlaid in top-left corner (dismissable)
                if (framingState.showOpticalConfigPanel)
                  const Positioned(
                    top: 16,
                    left: 16,
                    child: OpticalConfigPanel(),
                  )
                else
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Tooltip(
                      message: 'Show optical config panel',
                      child: Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            ref
                                .read(framingProvider.notifier)
                                .setOpticalConfigPanelVisible(true);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              LucideIcons.aperture,
                              size: 16,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Right sidebar
          ResizablePanel(
            initialWidth: 320,
            minWidth: 250,
            maxWidth: 500,
            side: ResizeSide.left,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: Column(
                children: [
                  // Target search
                  _buildTargetSearch(colors, searchState),

                  // Controls
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEquipmentSection(colors, equipmentResult),
                          const SizedBox(height: 20),
                          _buildFramingControls(
                              colors, framingState, equipmentResult),
                          const SizedBox(height: 20),
                          _buildCoordinatesPanel(
                              colors, framingState, currentAltAz),
                          const SizedBox(height: 20),
                          _buildAltitudePanel(colors, framingState),
                          const SizedBox(height: 20),
                          _buildMosaicPanel(
                              colors, framingState, equipmentResult),
                          const SizedBox(height: 20),
                          _buildActionsPanel(
                              colors, framingState, equipmentResult),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the suggestion filter sheet
  void _showSuggestionFilterSheet(
      BuildContext context, NightshadeColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NightshadeTokens.radiusLg),
        ),
      ),
      builder: (context) {
        return const SuggestionFilters(showAsSheet: true);
      },
    );
  }

  /// Navigates to the framing tab with a selected target from suggestions
  void _navigateToFramingWithTarget(TargetSuggestion suggestion) {
    // Set the target in the framing provider
    ref.read(framingProvider.notifier).setTargetCoordinates(
          suggestion.raHours,
          suggestion.decDegrees,
          name: suggestion.targetName,
        );

    // Switch to framing tab
    _tabController.animateTo(0);
    setState(() => _currentTabIndex = 0);

    // Update the search field and controllers
    _searchController.text = suggestion.targetName;
    _raController.text = CoordinateUtils.formatRA(suggestion.raHours);
    _decController.text = CoordinateUtils.formatDec(suggestion.decDegrees);
    // Alt/Az auto-refreshes on the next build via _computeCurrentAltAz.
  }

  Widget _buildTargetSearch(
      NightshadeColors colors, TargetSearchState searchState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: FramingTutorialKeys.targetSearch,
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name (M42, NGC7000, Orion)',
              hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: colors.textMuted),
              suffixIcon: searchState.isSearching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: colors.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(targetSearchProvider.notifier).clear();
                          },
                        )
                      : null,
              filled: true,
              fillColor: colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) {
              ref.read(targetSearchProvider.notifier).search(value);
            },
            onSubmitted: (value) {
              if (searchState.results.isNotEmpty) {
                _selectTarget(searchState.results.first);
              } else if (value.isNotEmpty) {
                // Try to resolve via SIMBAD
                _resolveAndSelectTarget(value);
              }
            },
          ),

          // Search results dropdown
          if (searchState.results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  final target = searchState.results[index];
                  return InkWell(
                    onTap: () => _selectTarget(target),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _getTargetIcon(target.type),
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (target.catalogId != null &&
                                    target.catalogId != target.name)
                                  Text(
                                    target.catalogId!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (target.magnitude != null)
                            Text(
                              'mag ${target.magnitude!.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Manual coordinate entry
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _raController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'RA',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '05h 35m 17s',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _decController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Dec',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '-05° 23\' 28"',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: LucideIcons.arrowRight,
                tooltip: 'Go to coordinates',
                colors: colors,
                onTap: _goToManualCoordinates,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectTarget(FramingTarget target) {
    final notifier = ref.read(framingProvider.notifier);
    notifier.setTarget(target);
    // Persist the target to database so it's available when returning to this tab
    notifier.saveTarget();
    ref.read(targetSearchProvider.notifier).clear();
    _searchController.text = target.name;
    _raController.text = target.raFormatted;
    _decController.text = target.decFormatted;
    _searchFocusNode.unfocus();
    // Alt/Az auto-refreshes on the next build (framingProvider watch triggers it).
  }

  Future<void> _resolveAndSelectTarget(String name) async {
    final result = await SimbadResolver.resolve(name);
    if (result != null && mounted) {
      final target = FramingTarget(
        name: result.mainId,
        catalogId: result.mainId,
        raHours: result.raHours,
        decDegrees: result.decDegrees,
        magnitude: result.magnitude,
      );
      _selectTarget(target);
    }
  }

  void _goToManualCoordinates() {
    final ra = CoordinateUtils.parseRA(_raController.text);
    final dec = CoordinateUtils.parseDec(_decController.text);

    if (ra != null && dec != null) {
      ref
          .read(framingProvider.notifier)
          .setTargetCoordinates(ra, dec, name: 'Custom Location');
      // Alt/Az auto-refreshes on the next build (framingProvider watch triggers it).
    } else {
      context.showInfoSnackBar('Invalid coordinates');
    }
  }

  IconData _getTargetIcon(TargetType? type) {
    switch (type) {
      case TargetType.galaxy:
        return LucideIcons.circle;
      case TargetType.nebula:
        return LucideIcons.cloud;
      case TargetType.cluster:
        return LucideIcons.sparkles;
      case TargetType.star:
        return LucideIcons.star;
      case TargetType.planet:
        return LucideIcons.globe;
      default:
        return LucideIcons.target;
    }
  }

  Widget _buildEquipmentSection(NightshadeColors colors,
      AsyncValue<FramingEquipmentResult> equipmentAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Equipment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            equipmentAsync.when(
              data: (result) {
                if (result.isReady) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.checkCircle,
                          size: 12, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        result.profileName ?? 'Ready',
                        style: TextStyle(fontSize: 10, color: colors.success),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 12, color: colors.warning),
                    const SizedBox(width: 4),
                    Text(
                      'Not Configured',
                      style: TextStyle(fontSize: 10, color: colors.warning),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(),
              error: (error, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 12, color: colors.error),
                  const SizedBox(width: 4),
                  Text(
                    'Error',
                    style: TextStyle(fontSize: 10, color: colors.error),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        equipmentAsync.when(
          data: (result) {
            // Show appropriate content based on equipment status
            switch (result.status) {
              case EquipmentStatus.noProfile:
                return _EquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.settings,
                  title: 'No Equipment Profile',
                  message:
                      'Create and activate an equipment profile in Settings → Equipment to enable framing preview.',
                  actionLabel: 'Open Settings',
                  onAction: () {
                    // Navigate to settings
                  },
                );

              case EquipmentStatus.noFocalLength:
                return _EquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.focus,
                  title: 'Optical Specs Missing',
                  message:
                      'Set the focal length in profile "${result.profileName}" to enable FOV preview.',
                  actionLabel: 'Edit Profile',
                  onAction: () {
                    // Navigate to profile editor
                  },
                );

              case EquipmentStatus.noCameraSpecs:
                return _EquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.camera,
                  title: 'Camera Not Configured',
                  message:
                      'Connect a camera or configure camera specs to enable accurate FOV preview.',
                  actionLabel: null,
                  onAction: null,
                );

              case EquipmentStatus.ready:
                final equipment = result.equipment!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: 'Camera',
                      value: equipment.cameraName,
                      colors: colors,
                    ),
                    const SizedBox(height: 6),
                    _InfoRow(
                      label: 'Telescope',
                      value:
                          '${equipment.effectiveFocalLength.round()}mm f/${equipment.focalRatio.toStringAsFixed(1)}',
                      colors: colors,
                    ),
                    // Show warning if using default sensor specs
                    if (result.message != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: colors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.info,
                                size: 12, color: colors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                result.message!,
                                style: TextStyle(
                                    fontSize: 10, color: colors.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
            }
          },
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => _EquipmentWarningCard(
            colors: colors,
            icon: LucideIcons.alertTriangle,
            title: 'Error Loading Equipment',
            message: e.toString(),
            actionLabel: null,
            onAction: null,
          ),
        ),
      ],
    );
  }

  Widget _buildFramingControls(
    NightshadeColors colors,
    FramingState framingState,
    AsyncValue<FramingEquipmentResult> equipmentAsync,
  ) {
    final result = equipmentAsync.valueOrNull;
    final equipment = result?.equipment;
    final hasEquipment = result?.isReady ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frame',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // Rotation slider (only useful with equipment)
        _SliderField(
          key: FramingTutorialKeys.rotation,
          label: 'Rotation',
          value: framingState.rotation,
          min: -180,
          max: 180,
          suffix: '°',
          colors: colors,
          onChanged: hasEquipment
              ? (value) => ref.read(framingProvider.notifier).setRotation(value)
              : (_) {},
        ),
        const SizedBox(height: 12),

        // FOV display (only show when equipment is ready)
        if (hasEquipment && equipment != null) ...[
          _InfoRow(
            label: 'FOV',
            value:
                '${equipment.fovWidthDeg.toStringAsFixed(2)}° × ${equipment.fovHeightDeg.toStringAsFixed(2)}°',
            colors: colors,
            highlight: true,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Resolution',
            value: '${equipment.imageScale.toStringAsFixed(2)} arcsec/px',
            colors: colors,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Sensor',
            value: '${equipment.pixelsX} × ${equipment.pixelsY}',
            colors: colors,
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.frame, size: 16, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure equipment to see FOV overlay',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Preview FOV control (always available for browsing)
        Text(
          'Preview Field of View',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        _PreviewFovSlider(
          colors: colors,
          value: framingState.previewFovDegrees,
          hasEquipment: hasEquipment,
          equipmentFov: equipment?.fovWidthDeg,
          onChanged: (value) {
            ref.read(framingProvider.notifier).setPreviewFov(value);
          },
        ),

        // Equipment FOV overlay controls (only when equipment is configured and preview FOV > equipment FOV)
        if (hasEquipment &&
            equipment != null &&
            framingState.previewFovDegrees > equipment.fovWidthDeg) ...[
          const SizedBox(height: 16),
          _EquipmentFovOverlayControls(
            colors: colors,
            showOverlay: framingState.showEquipmentFovOverlay,
            opacity: framingState.equipmentFovOverlayOpacity,
            onToggle: () {
              ref.read(framingProvider.notifier).toggleEquipmentFovOverlay();
            },
            onOpacityChanged: (value) {
              ref
                  .read(framingProvider.notifier)
                  .setEquipmentFovOverlayOpacity(value);
            },
          ),
        ],

        const SizedBox(height: 16),

        // Survey source dropdown (always available - can browse sky without FOV)
        Text(
          'Survey Source',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButton<SurveySource>(
            value: framingState.surveySource,
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 11, color: colors.textPrimary),
            dropdownColor: colors.surfaceAlt,
            items: SurveySource.values.map((source) {
              return DropdownMenuItem(
                value: source,
                child: Text(source.displayName),
              );
            }).toList(),
            onChanged: (source) {
              if (source != null) {
                ref.read(framingProvider.notifier).setSurveySource(source);
              }
            },
          ),
        ),

        const SizedBox(height: 16),

        // Display toggles
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ToggleChip(
              label: 'Grid',
              isActive: framingState.showGrid,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
            ),
            _ToggleChip(
              label: 'Labels',
              isActive: framingState.showLabels,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleLabels(),
            ),
            if (hasEquipment)
              _ToggleChip(
                label: 'Directions',
                isActive: framingState.showCardinalDirections,
                colors: colors,
                onTap: () => ref
                    .read(framingProvider.notifier)
                    .toggleCardinalDirections(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoordinatesPanel(
    NightshadeColors colors,
    FramingState framingState,
    (double, double)? currentAltAz,
  ) {
    final target = framingState.target;

    return Container(
      key: FramingTutorialKeys.coordinates,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Coordinates',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (target != null)
                IconButton(
                  icon:
                      Icon(LucideIcons.copy, size: 12, color: colors.textMuted),
                  tooltip: 'Copy coordinates',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: '${target.raFormatted}, ${target.decFormatted}',
                    ));
                    context.showInfoSnackBar('Coordinates copied');
                  },
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _CoordRow(
            label: 'RA',
            value: target?.raFormatted ?? '--',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _CoordRow(
            label: 'Dec',
            value: target?.decFormatted ?? '--',
            colors: colors,
          ),
          const Divider(height: 20),
          _CoordRow(
            label: 'Alt',
            value: currentAltAz != null
                ? '${currentAltAz.$1.toStringAsFixed(1)}°'
                : '--',
            colors: colors,
            isGood: currentAltAz != null && currentAltAz.$1 > 30,
            isBad: currentAltAz != null && currentAltAz.$1 < 15,
          ),
          const SizedBox(height: 6),
          _CoordRow(
            label: 'Az',
            value: currentAltAz != null
                ? '${currentAltAz.$2.toStringAsFixed(1)}°'
                : '--',
            colors: colors,
          ),
          if (currentAltAz != null && currentAltAz.$1 < 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 12, color: colors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Target below horizon',
                    style: TextStyle(fontSize: 10, color: colors.warning),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAltitudePanel(
      NightshadeColors colors, FramingState framingState) {
    final target = framingState.target;

    if (target == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.trendingUp, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Altitude',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Select a target to view altitude chart',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: AltitudeChart(
        key: FramingTutorialKeys.altitudeChart,
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        targetName: target.name,
      ),
    );
  }

  Widget _buildMosaicPanel(
    NightshadeColors colors,
    FramingState framingState,
    AsyncValue<FramingEquipmentResult> equipmentAsync,
  ) {
    final result = equipmentAsync.valueOrNull;
    final hasEquipment = result?.isReady ?? false;
    final config = framingState.mosaicConfig;
    final notifier = ref.read(framingProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        Row(
          key: FramingTutorialKeys.mosaicBtn,
          children: [
            Expanded(
              child: Text(
                'Mosaic',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: framingState.mosaicEnabled,
              onChanged:
                  hasEquipment ? (v) => notifier.setMosaicEnabled(v) : null,
              activeTrackColor: colors.primary,
              thumbColor: WidgetStateProperty.all(Colors.white),
            ),
          ],
        ),

        if (!hasEquipment)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure equipment to enable mosaic planning',
                    style: TextStyle(fontSize: 10, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),

        if (framingState.mosaicEnabled && hasEquipment) ...[
          const SizedBox(height: 12),

          // Grid configuration
          Row(
            children: [
              Expanded(
                child: _MosaicSpinner(
                  label: 'Columns',
                  value: config.columns,
                  min: 1,
                  max: 10,
                  onChanged: notifier.setMosaicColumns,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MosaicSpinner(
                  label: 'Rows',
                  value: config.rows,
                  min: 1,
                  max: 10,
                  onChanged: notifier.setMosaicRows,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Overlap slider
          _SliderField(
            label: 'Overlap',
            value: config.overlapPercent,
            min: 0,
            max: 50,
            suffix: '%',
            colors: colors,
            onChanged: notifier.setMosaicOverlap,
          ),
          const SizedBox(height: 12),

          // Capture pattern options
          Row(
            children: [
              Expanded(
                child: _OptionButton(
                  icon: LucideIcons.moveHorizontal,
                  label: 'Serpentine',
                  isSelected: config.serpentine,
                  onTap: notifier.toggleSerpentine,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionButton(
                  icon: LucideIcons.hash,
                  label: 'Numbers',
                  isSelected: framingState.showPanelNumbers,
                  onTap: notifier.togglePanelNumbers,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Start corner dropdown
          Text(
            'Start Corner',
            style: TextStyle(fontSize: 10, color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          _StartCornerSelector(
            selected: config.startCorner,
            onChanged: notifier.setMosaicStartCorner,
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Panel summary
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.layoutGrid,
                        size: 14, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${config.totalPanels} Panels',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (framingState.mosaicPanels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      itemCount: framingState.mosaicPanels.length,
                      itemBuilder: (context, index) {
                        final panel = framingState.mosaicPanels[index];
                        final isSelected =
                            index == framingState.selectedPanelIndex;
                        return InkWell(
                          onTap: () => notifier.selectPanel(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primary.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colors.primary
                                        : colors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? colors.primary
                                          : colors.border,
                                    ),
                                  ),
                                  child: Text(
                                    '${panel.index + 1}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    panel.raFormatted,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  panel.decFormatted,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Export button
          if (framingState.mosaicPanels.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ExportMosaicButton(
              colors: colors,
              panels: framingState.mosaicPanels,
              targetName: framingState.target?.name ?? 'Mosaic',
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildActionsPanel(
    NightshadeColors colors,
    FramingState framingState,
    AsyncValue<FramingEquipmentResult> equipmentAsync,
  ) {
    final hasTarget = framingState.target != null;
    final mountState = ref.watch(mountStateProvider);
    final hasMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;

    // Slew requires a target and a connected mount (FOV/equipment profile is optional)
    final canSlew = hasTarget && hasMountConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: hasTarget
              ? SlewDropdownButton(
                  key: FramingTutorialKeys.slewBtn,
                  ra: framingState.target!.raHours,
                  dec: framingState.target!.decDegrees,
                  targetName: framingState.target!.name,
                  // Use the rotation angle from framing state
                  targetRotation:
                      framingState.rotation != 0 ? framingState.rotation : null,
                  isEnabled: canSlew,
                  icon: LucideIcons.compass,
                  label: 'Slew to Target',
                )
              : _ActionButton(
                  key: FramingTutorialKeys.slewBtn,
                  icon: LucideIcons.compass,
                  label: 'Slew to Target',
                  isPrimary: true,
                  colors: colors,
                  isEnabled: false,
                  onTap: null,
                ),
        ),

        // Show hint if slew is disabled
        if (hasTarget && !hasMountConnected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Connect a mount to enable slewing',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: LucideIcons.plus,
                label: 'Add to Sequence',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget
                    ? () => _addToSequence(framingState.target!)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: LucideIcons.bookmark,
                label: 'Save Target',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget ? _saveTarget : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: LucideIcons.download,
                label: 'Cache Image',
                colors: colors,
                isEnabled: framingState.surveyImageBytes != null,
                onTap:
                    framingState.surveyImageBytes != null ? _cacheImage : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: LucideIcons.refreshCw,
                label: 'Reload',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget
                    ? () => ref.read(framingProvider.notifier).loadSurveyImage()
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _addToSequence(FramingTarget target) {
    // Add target to current sequence, adopting any orphan instructions
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    final targetNode = TargetHeaderNode(
      targetName: target.name,
      raHours: target.raHours,
      decDegrees: target.decDegrees,
    );

    // Use addTargetHeader to properly wrap existing orphan instructions
    sequenceNotifier.addTargetHeader(targetNode);

    context.showInfoSnackBar('Added ${target.name} to sequence');
  }

  Future<void> _saveTarget() async {
    try {
      await ref.read(framingProvider.notifier).saveTarget();
      if (!mounted) return;
      context.showSuccessSnackBar('Target saved');
    } catch (e) {
      context.showErrorSnackBar('Failed to save: $e');
      if (!mounted) return;
    }
  }

  void _cacheImage() {
    // Would save image to local cache
    context.showInfoSnackBar('Image cached locally');
  }
}

// =============================================================================
// FRAMING CANVAS
// =============================================================================

class _FramingCanvas extends StatefulWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final FramingEquipmentResult? equipmentResult;
  final void Function(double dx, double dy) onPan;
  final void Function(double angle) onRotate;

  const _FramingCanvas({
    super.key,
    required this.colors,
    required this.framingState,
    required this.equipmentResult,
    required this.onPan,
    required this.onRotate,
  });

  @override
  State<_FramingCanvas> createState() => _FramingCanvasState();
}

class _FramingCanvasState extends State<_FramingCanvas> {
  bool _isDragging = false;
  bool _isRotating = false;
  Offset _lastPosition = Offset.zero;

  FramingEquipment? get _equipment => widget.equipmentResult?.equipment;
  bool get _hasEquipment => widget.equipmentResult?.isReady ?? false;

  /// Whether to show the equipment FOV overlay (preview FOV > equipment FOV)
  bool get _showEquipmentOverlay {
    if (!_hasEquipment || _equipment == null) return false;
    return widget.framingState.previewFovDegrees > _equipment!.fovWidthDeg &&
        widget.framingState.showEquipmentFovOverlay;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        _lastPosition = details.localPosition;
        final center = Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
        final distance = (details.localPosition - center).distance;

        // If clicking near the rotation handle, rotate instead of pan
        if (_hasEquipment && _equipment != null) {
          final fovHeight =
              _equipment!.fovHeightDeg * 60 * widget.framingState.zoom;
          if (distance > fovHeight / 2 + 10 && distance < fovHeight / 2 + 40) {
            _isRotating = true;
          } else {
            _isDragging = true;
          }
        } else {
          _isDragging = true;
        }
      },
      onPanUpdate: (details) {
        if (_isRotating) {
          final center = Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          );
          final angle = math.atan2(
            details.localPosition.dx - center.dx,
            -(details.localPosition.dy - center.dy),
          );
          widget.onRotate(angle * 180 / math.pi);
        } else if (_isDragging) {
          final delta = details.localPosition - _lastPosition;
          widget.onPan(delta.dx, delta.dy);
          _lastPosition = details.localPosition;
        }
      },
      onPanEnd: (_) {
        _isDragging = false;
        _isRotating = false;
      },
      child: Container(
        color: const Color(0xFF0A0A12),
        child: Stack(
          children: [
            // Survey image background
            if (widget.framingState.surveyImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SurveyImagePainter(
                    image: widget.framingState.surveyImage!,
                    zoom: widget.framingState.zoom,
                    panX: widget.framingState.panX,
                    panY: widget.framingState.panY,
                  ),
                ),
              )
            else if (widget.framingState.isLoadingImage)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: widget.colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading sky survey...',
                      style: TextStyle(color: widget.colors.textMuted),
                    ),
                  ],
                ),
              )
            else
              // Static star field backdrop
              CustomPaint(
                painter: _StarBackgroundPainter(colors: widget.colors),
                size: Size.infinite,
              ),

            // Grid overlay
            if (widget.framingState.showGrid)
              CustomPaint(
                painter: _GridPainter(
                  zoom: widget.framingState.zoom,
                  panX: widget.framingState.panX,
                  panY: widget.framingState.panY,
                  color: widget.colors.primary.withValues(alpha: 0.2),
                ),
                size: Size.infinite,
              ),

            // Equipment FOV overlay - Show when preview FOV > equipment FOV
            if (_showEquipmentOverlay && _equipment != null)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      painter: _EquipmentFOVOverlayPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        previewFov: widget.framingState.previewFovDegrees,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        opacity: widget.framingState.equipmentFovOverlayOpacity,
                        showDirections:
                            widget.framingState.showCardinalDirections,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // FOV overlay - Show when equipment is configured and preview FOV <= equipment FOV
            if (_hasEquipment && _equipment != null && !_showEquipmentOverlay)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      key: FramingTutorialKeys.fovRect,
                      painter: _FOVPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        showDirections:
                            widget.framingState.showCardinalDirections,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // Mosaic grid overlay
            if (widget.framingState.mosaicEnabled &&
                _hasEquipment &&
                _equipment != null)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      painter: _MosaicGridPainter(
                        config: widget.framingState.mosaicConfig,
                        panels: widget.framingState.mosaicPanels,
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        showPanelNumbers: widget.framingState.showPanelNumbers,
                        showSequencePath: widget.framingState.showSequencePath,
                        selectedPanelIndex:
                            widget.framingState.selectedPanelIndex,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // Crosshairs
            Center(
              child: CustomPaint(
                painter: _CrosshairPainter(colors: widget.colors),
                size: const Size(100, 100),
              ),
            ),

            // Top controls
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _CanvasControls(
                colors: widget.colors,
                framingState: widget.framingState,
              ),
            ),

            // Equipment status overlay (when not configured)
            if (!_hasEquipment && widget.framingState.target != null)
              Positioned(
                top: 60,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.colors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: widget.colors.info.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.eye,
                          size: 14, color: widget.colors.info),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preview: ${widget.framingState.previewFovDegrees.toStringAsFixed(1)}° FOV',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: widget.colors.info,
                            ),
                          ),
                          Text(
                            'Configure equipment for accurate framing',
                            style: TextStyle(
                              fontSize: 9,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Zoom controls
            Positioned(
              bottom: 16,
              right: 16,
              child: Consumer(
                builder: (context, ref, child) => _ZoomControls(
                  colors: widget.colors,
                  zoom: widget.framingState.zoom,
                  onZoomIn: () => ref.read(framingProvider.notifier).zoomIn(),
                  onZoomOut: () => ref.read(framingProvider.notifier).zoomOut(),
                  onReset: () => ref.read(framingProvider.notifier).resetView(),
                ),
              ),
            ),

            // Scale indicator
            Positioned(
              bottom: 16,
              left: 16,
              child: _ScaleIndicator(
                colors: widget.colors,
                zoom: widget.framingState.zoom,
              ),
            ),

            // Target info overlay
            if (widget.framingState.target != null &&
                widget.framingState.showLabels)
              Positioned(
                top: 60,
                left: 16,
                child: _TargetInfoOverlay(
                  colors: widget.colors,
                  target: widget.framingState.target!,
                ),
              ),

            // Error overlay
            if (widget.framingState.imageError != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: widget.colors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.error),
                  ),
                  child: Text(
                    widget.framingState.imageError!,
                    style: TextStyle(color: widget.colors.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PAINTERS
// =============================================================================

class _SurveyImagePainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final double panX;
  final double panY;

  _SurveyImagePainter({
    required this.image,
    required this.zoom,
    required this.panX,
    required this.panY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;

    // Calculate scaling to fit image to canvas
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;

    double drawWidth, drawHeight;
    if (imageAspect > canvasAspect) {
      drawWidth = size.width * zoom;
      drawHeight = drawWidth / imageAspect;
    } else {
      drawHeight = size.height * zoom;
      drawWidth = drawHeight * imageAspect;
    }

    final center = Offset(size.width / 2 + panX, size.height / 2 + panY);
    final destRect = Rect.fromCenter(
      center: center,
      width: drawWidth,
      height: drawHeight,
    );

    final srcRect =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

    canvas.drawImageRect(image, srcRect, destRect, paint);
  }

  @override
  bool shouldRepaint(covariant _SurveyImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        zoom != oldDelegate.zoom ||
        panX != oldDelegate.panX ||
        panY != oldDelegate.panY;
  }
}

class _StarBackgroundPainter extends CustomPainter {
  final NightshadeColors colors;

  _StarBackgroundPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final random = _SeededRandom(42);

    // Background gradient
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Color(0xFF12121A),
          Color(0xFF08080C),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw stars
    for (var i = 0; i < 300; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.5 + 0.2;
      final radius = random.nextDouble() * 1.5 + 0.3;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Draw faint nebula hint in center
    final center = Offset(size.width / 2, size.height / 2);
    final gradient = RadialGradient(
      colors: [
        colors.primary.withValues(alpha: 0.1),
        colors.accent.withValues(alpha: 0.05),
        Colors.transparent,
      ],
    );
    final rect = Rect.fromCircle(center: center, radius: 150);
    paint.shader = gradient.createShader(rect);
    canvas.drawCircle(center, 150, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SeededRandom {
  int _seed;

  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}

class _GridPainter extends CustomPainter {
  final double zoom;
  final double panX;
  final double panY;
  final Color color;

  _GridPainter({
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    final center = Offset(size.width / 2 + panX, size.height / 2 + panY);
    final spacing = 60.0 * zoom;

    // Draw vertical lines
    for (var x = center.dx % spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (var y = center.dy % spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw center lines (brighter)
    paint.color = color.withValues(alpha: 0.5);
    paint.strokeWidth = 1;
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        panX != oldDelegate.panX ||
        panY != oldDelegate.panY;
  }
}

class _FOVPainter extends CustomPainter {
  final double fovWidth;
  final double fovHeight;
  final double zoom;
  final NightshadeColors colors;
  final bool showDirections;

  _FOVPainter({
    required this.fovWidth,
    required this.fovHeight,
    required this.zoom,
    required this.colors,
    required this.showDirections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale: roughly 60 pixels per degree at zoom 1.0
    final pixelsPerDegree = 60.0 * zoom;
    final rectWidth = fovWidth * pixelsPerDegree;
    final rectHeight = fovHeight * pixelsPerDegree;

    final center = Offset(size.width / 2, size.height / 2);

    // Semi-transparent fill
    final fillPaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Border
    final borderPaint = Paint()
      ..color = colors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: center,
      width: rectWidth,
      height: rectHeight,
    );

    // Draw frame
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw corner markers
    _drawCorners(canvas, rect, borderPaint);

    // Draw rotation handle
    final handlePaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;
    final handleY = center.dy - rectHeight / 2 - 18;
    canvas.drawCircle(Offset(center.dx, handleY), 10, handlePaint);
    canvas.drawLine(
      Offset(center.dx, center.dy - rectHeight / 2),
      Offset(center.dx, handleY + 10),
      borderPaint,
    );

    // Draw rotation icon
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '↻',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, Offset(center.dx - 6, handleY - 7));

    // Draw cardinal directions
    if (showDirections) {
      _drawCardinalDirections(canvas, center, rectWidth, rectHeight);
    }

    // Draw FOV dimensions
    final fovText =
        '${fovWidth.toStringAsFixed(2)}° × ${fovHeight.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: TextStyle(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Draw text background
    final textBg = Rect.fromCenter(
      center: Offset(center.dx, center.dy + rectHeight / 2 + 18),
      width: textPainter.width + 12,
      height: textPainter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );
    textPainter.paint(
      canvas,
      Offset(
          center.dx - textPainter.width / 2, center.dy + rectHeight / 2 + 15),
    );
  }

  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    final cornerLength = math.min(rect.width, rect.height) * 0.1;
    paint.strokeWidth = 3;

    // Top-left
    canvas.drawLine(
        Offset(rect.left, rect.top + cornerLength), rect.topLeft, paint);
    canvas.drawLine(
        rect.topLeft, Offset(rect.left + cornerLength, rect.top), paint);

    // Top-right
    canvas.drawLine(
        Offset(rect.right - cornerLength, rect.top), rect.topRight, paint);
    canvas.drawLine(
        rect.topRight, Offset(rect.right, rect.top + cornerLength), paint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right, rect.bottom - cornerLength),
        rect.bottomRight, paint);
    canvas.drawLine(rect.bottomRight,
        Offset(rect.right - cornerLength, rect.bottom), paint);

    // Bottom-left
    canvas.drawLine(
        Offset(rect.left + cornerLength, rect.bottom), rect.bottomLeft, paint);
    canvas.drawLine(
        rect.bottomLeft, Offset(rect.left, rect.bottom - cornerLength), paint);
  }

  void _drawCardinalDirections(
      Canvas canvas, Offset center, double width, double height) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final positions = [
      Offset(center.dx, center.dy - height / 2 + 12),
      Offset(center.dx + width / 2 - 12, center.dy),
      Offset(center.dx, center.dy + height / 2 - 12),
      Offset(center.dx - width / 2 + 8, center.dy),
    ];

    for (var i = 0; i < 4; i++) {
      final textPainter = TextPainter(
        text: TextSpan(text: directions[i], style: style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        positions[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FOVPainter oldDelegate) {
    return fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        zoom != oldDelegate.zoom ||
        showDirections != oldDelegate.showDirections;
  }
}

/// Draws the equipment FOV overlay when preview FOV is larger than equipment FOV
/// This shows the user what their actual capture area will be
class _EquipmentFOVOverlayPainter extends CustomPainter {
  final double fovWidth;
  final double fovHeight;
  final double previewFov;
  final double zoom;
  final NightshadeColors colors;
  final double opacity;
  final bool showDirections;

  _EquipmentFOVOverlayPainter({
    required this.fovWidth,
    required this.fovHeight,
    required this.previewFov,
    required this.zoom,
    required this.colors,
    required this.opacity,
    required this.showDirections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale: the preview FOV fills the canvas
    final pixelsPerDegree = size.width / previewFov * zoom;
    final rectWidth = fovWidth * pixelsPerDegree;
    final rectHeight = fovHeight * pixelsPerDegree;

    final center = Offset(size.width / 2, size.height / 2);

    // Semi-transparent fill for the equipment FOV area
    final fillPaint = Paint()
      ..color = colors.info.withValues(alpha: opacity * 0.3)
      ..style = PaintingStyle.fill;

    // Border for the equipment FOV
    final borderPaint = Paint()
      ..color = colors.info.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: center,
      width: rectWidth,
      height: rectHeight,
    );

    // Draw dark overlay outside the equipment FOV
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );

    // Draw equipment FOV frame
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw corner brackets
    _drawCornerBrackets(canvas, rect, borderPaint);

    // Draw equipment FOV label
    final fovText =
        'Equipment FOV: ${fovWidth.toStringAsFixed(2)}° × ${fovHeight.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: TextStyle(
          color: colors.info,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Draw text background
    final textBg = Rect.fromCenter(
      center: Offset(center.dx, rect.top - 16),
      width: textPainter.width + 16,
      height: textPainter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()..color = colors.info.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()
        ..color = colors.info.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          rect.top - textPainter.height / 2 - 16),
    );

    // Draw cardinal directions inside the equipment FOV
    if (showDirections) {
      _drawCardinalDirections(canvas, center, rectWidth, rectHeight);
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final bracketLength = math.min(rect.width, rect.height) * 0.12;
    paint.strokeWidth = 3;

    // Top-left bracket
    canvas.drawLine(Offset(rect.left - 2, rect.top + bracketLength),
        Offset(rect.left - 2, rect.top - 2), paint);
    canvas.drawLine(Offset(rect.left - 2, rect.top - 2),
        Offset(rect.left + bracketLength, rect.top - 2), paint);

    // Top-right bracket
    canvas.drawLine(Offset(rect.right - bracketLength, rect.top - 2),
        Offset(rect.right + 2, rect.top - 2), paint);
    canvas.drawLine(Offset(rect.right + 2, rect.top - 2),
        Offset(rect.right + 2, rect.top + bracketLength), paint);

    // Bottom-right bracket
    canvas.drawLine(Offset(rect.right + 2, rect.bottom - bracketLength),
        Offset(rect.right + 2, rect.bottom + 2), paint);
    canvas.drawLine(Offset(rect.right + 2, rect.bottom + 2),
        Offset(rect.right - bracketLength, rect.bottom + 2), paint);

    // Bottom-left bracket
    canvas.drawLine(Offset(rect.left + bracketLength, rect.bottom + 2),
        Offset(rect.left - 2, rect.bottom + 2), paint);
    canvas.drawLine(Offset(rect.left - 2, rect.bottom + 2),
        Offset(rect.left - 2, rect.bottom - bracketLength), paint);
  }

  void _drawCardinalDirections(
      Canvas canvas, Offset center, double width, double height) {
    final style = TextStyle(
      color: colors.info.withValues(alpha: 0.7),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final positions = [
      Offset(center.dx, center.dy - height / 2 + 14),
      Offset(center.dx + width / 2 - 14, center.dy),
      Offset(center.dx, center.dy + height / 2 - 14),
      Offset(center.dx - width / 2 + 10, center.dy),
    ];

    for (var i = 0; i < 4; i++) {
      final textPainter = TextPainter(
        text: TextSpan(text: directions[i], style: style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        positions[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EquipmentFOVOverlayPainter oldDelegate) {
    return fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        previewFov != oldDelegate.previewFov ||
        zoom != oldDelegate.zoom ||
        opacity != oldDelegate.opacity ||
        showDirections != oldDelegate.showDirections;
  }
}

class _CrosshairPainter extends CustomPainter {
  final NightshadeColors colors;

  _CrosshairPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.error.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);

    // Horizontal line
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);

    // Vertical line
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Center circle
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(center, 6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MosaicGridPainter extends CustomPainter {
  final MosaicConfig config;
  final List<MosaicPanel> panels;
  final double fovWidth;
  final double fovHeight;
  final double zoom;
  final NightshadeColors colors;
  final bool showPanelNumbers;
  final bool showSequencePath;
  final int selectedPanelIndex;

  _MosaicGridPainter({
    required this.config,
    required this.panels,
    required this.fovWidth,
    required this.fovHeight,
    required this.zoom,
    required this.colors,
    required this.showPanelNumbers,
    required this.showSequencePath,
    required this.selectedPanelIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Scale: convert degrees to pixels (60 pixels per degree at zoom 1)
    final scale = 60 * zoom;
    final panelWidth = fovWidth * scale;
    final panelHeight = fovHeight * scale;

    // Calculate step size accounting for overlap
    final overlapFactor = 1 - (config.overlapPercent / 100);
    final stepX = panelWidth * overlapFactor;
    final stepY = panelHeight * overlapFactor;

    // Calculate total mosaic extent
    final totalWidth = panelWidth + (config.columns - 1) * stepX;
    final totalHeight = panelHeight + (config.rows - 1) * stepY;

    // Starting offset (top-left corner of mosaic relative to center)
    final startX = center.dx - totalWidth / 2 + panelWidth / 2;
    final startY = center.dy - totalHeight / 2 + panelHeight / 2;

    // Draw mosaic outline
    final outlinePaint = Paint()
      ..color = colors.warning.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: totalWidth,
        height: totalHeight,
      ),
      outlinePaint,
    );

    // Draw sequence path if enabled
    if (showSequencePath && panels.length > 1) {
      final pathPaint = Paint()
        ..color = colors.warning.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final path = Path();
      bool first = true;

      for (final panel in panels) {
        final panelX = startX + panel.column * stepX;
        final panelY = startY + panel.row * stepY;

        if (first) {
          path.moveTo(panelX, panelY);
          first = false;
        } else {
          path.lineTo(panelX, panelY);
        }
      }

      canvas.drawPath(path, pathPaint);
    }

    // Draw individual panels
    for (int i = 0; i < panels.length; i++) {
      final panel = panels[i];
      final panelX = startX + panel.column * stepX;
      final panelY = startY + panel.row * stepY;
      final isSelected = i == selectedPanelIndex;

      // Panel rect
      final panelRect = Rect.fromCenter(
        center: Offset(panelX, panelY),
        width: panelWidth,
        height: panelHeight,
      );

      // Draw panel fill
      final fillPaint = Paint()
        ..color = isSelected
            ? colors.primary.withValues(alpha: 0.2)
            : colors.warning.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill;
      canvas.drawRect(panelRect, fillPaint);

      // Draw panel border
      final borderPaint = Paint()
        ..color = isSelected
            ? colors.primary.withValues(alpha: 0.8)
            : colors.warning.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2 : 1;
      canvas.drawRect(panelRect, borderPaint);

      // Draw panel number
      if (showPanelNumbers) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${panel.index + 1}',
            style: TextStyle(
              color: isSelected ? colors.primary : colors.warning,
              fontSize: 14 * zoom.clamp(0.5, 2.0),
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(
            panelX - textPainter.width / 2,
            panelY - textPainter.height / 2,
          ),
        );
      }

      // Draw crosshair on selected panel
      if (isSelected) {
        final crosshairPaint = Paint()
          ..color = colors.primary.withValues(alpha: 0.6)
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(panelX - 10, panelY),
          Offset(panelX + 10, panelY),
          crosshairPaint,
        );
        canvas.drawLine(
          Offset(panelX, panelY - 10),
          Offset(panelX, panelY + 10),
          crosshairPaint,
        );
      }
    }

    // Draw start indicator
    if (panels.isNotEmpty) {
      final firstPanel = panels.first;
      final startX2 = startX + firstPanel.column * stepX;
      final startY2 = startY + firstPanel.row * stepY;

      final startPaint = Paint()
        ..color = colors.success.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(startX2, startY2),
        6 * zoom.clamp(0.5, 1.5),
        startPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'START',
          style: TextStyle(
            color: colors.success,
            fontSize: 8 * zoom.clamp(0.7, 1.3),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          startX2 - textPainter.width / 2,
          startY2 + 10 * zoom.clamp(0.5, 1.5),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MosaicGridPainter oldDelegate) {
    return config.columns != oldDelegate.config.columns ||
        config.rows != oldDelegate.config.rows ||
        config.overlapPercent != oldDelegate.config.overlapPercent ||
        fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        zoom != oldDelegate.zoom ||
        showPanelNumbers != oldDelegate.showPanelNumbers ||
        showSequencePath != oldDelegate.showSequencePath ||
        selectedPanelIndex != oldDelegate.selectedPanelIndex ||
        panels.length != oldDelegate.panels.length;
  }
}

// =============================================================================
// UI COMPONENTS
// =============================================================================

class _CanvasControls extends StatelessWidget {
  final NightshadeColors colors;
  final FramingState framingState;

  const _CanvasControls({
    required this.colors,
    required this.framingState,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return Row(
          children: [
            // Survey source chip
            _ControlChip(
              icon: LucideIcons.layers,
              label: framingState.surveySource.displayName,
              colors: colors,
              onTap: () {
                // Show survey source picker
              },
            ),
            const SizedBox(width: 8),
            _ControlChip(
              icon: LucideIcons.grid,
              label: 'Grid',
              isActive: framingState.showGrid,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
            ),
            const SizedBox(width: 8),
            _ControlChip(
              icon: LucideIcons.tag,
              label: 'Labels',
              isActive: framingState.showLabels,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleLabels(),
            ),
            const Spacer(),
            if (framingState.isLoadingImage)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ControlChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ControlChip({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ControlChip> createState() => _ControlChipState();
}

class _ControlChipState extends State<_ControlChip> {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.colors.primary.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: _isHovered ? 0.7 : 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isActive ? widget.colors.primary : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      widget.isActive ? widget.colors.primary : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.colors,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: LucideIcons.plus, colors: colors, onTap: onZoomIn),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${(zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _ZoomButton(
              icon: LucideIcons.minus, colors: colors, onTap: onZoomOut),
          const SizedBox(height: 4),
          Container(height: 1, width: 20, color: colors.border),
          const SizedBox(height: 4),
          _ZoomButton(
              icon: LucideIcons.maximize2, colors: colors, onTap: onReset),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatefulWidget {
  final IconData icon;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ScaleIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;

  const _ScaleIndicator({required this.colors, required this.zoom});

  @override
  Widget build(BuildContext context) {
    // Scale bar represents ~10 arcminutes at zoom level
    final barLength = (10.0 / 60.0) * 60 * zoom;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scale',
            style: TextStyle(
              fontSize: 9,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: barLength.clamp(30.0, 100.0),
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "10'",
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetInfoOverlay extends StatelessWidget {
  final NightshadeColors colors;
  final FramingTarget target;

  const _TargetInfoOverlay({
    required this.colors,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            target.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (target.catalogId != null && target.catalogId != target.name)
            Text(
              target.catalogId!,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${target.raFormatted}  ${target.decFormatted}',
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (target.magnitude != null || target.sizeArcmin != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (target.magnitude != null)
                    'Mag ${target.magnitude!.toStringAsFixed(1)}',
                  if (target.sizeArcmin != null)
                    "${target.sizeArcmin!.toStringAsFixed(0)}'",
                ].join('  '),
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EquipmentWarningCard extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EquipmentWarningCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: colors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.warning,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.arrowRight,
                        size: 12, color: colors.warning),
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<double> onChanged;

  const _SliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${value.toInt()}${suffix ?? ''}',
            style: TextStyle(
              fontSize: 11,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _CoordRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isGood;
  final bool isBad;

  const _CoordRow({
    required this.label,
    required this.value,
    required this.colors,
    this.isGood = false,
    this.isBad = false,
  });

  @override
  Widget build(BuildContext context) {
    Color valueColor = colors.textPrimary;
    if (isGood) valueColor = colors.success;
    if (isBad) valueColor = colors.error;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isActive,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.2)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? colors.primary : colors.textSecondary,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isEnabled;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.isEnabled = true,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isEnabled && widget.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isPrimary && enabled
                ? LinearGradient(
                    colors: [
                      widget.colors.primary,
                      _darkenColor(widget.colors.primary, 0.08),
                    ],
                  )
                : null,
            color: widget.isPrimary
                ? null
                : enabled
                    ? (_isHovered
                        ? widget.colors.surfaceAlt
                        : widget.colors.background)
                    : widget.colors.surfaceAlt.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: enabled
                        ? widget.colors.border
                        : widget.colors.border.withValues(alpha: 0.5),
                  ),
            boxShadow: widget.isPrimary && _isHovered && enabled
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isPrimary
                    ? (enabled ? Colors.white : Colors.white60)
                    : (enabled
                        ? widget.colors.textSecondary
                        : widget.colors.textMuted),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? (enabled ? Colors.white : Colors.white60)
                      : (enabled
                          ? widget.colors.textSecondary
                          : widget.colors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  _isHovered ? widget.colors.primary : widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.colors.border),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? Colors.white : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PREVIEW FOV CONTROLS
// =============================================================================

class _PreviewFovSlider extends StatelessWidget {
  final NightshadeColors colors;
  final double value;
  final bool hasEquipment;
  final double? equipmentFov;
  final ValueChanged<double> onChanged;

  const _PreviewFovSlider({
    required this.colors,
    required this.value,
    required this.hasEquipment,
    this.equipmentFov,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${value.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (hasEquipment && equipmentFov != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: colors.info.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Equipment: ${equipmentFov!.toStringAsFixed(2)}°',
                    style: TextStyle(
                      fontSize: 9,
                      color: colors.info,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: 0.1,
              max: 10.0,
              divisions: 99,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.1°',
                  style: TextStyle(fontSize: 9, color: colors.textMuted)),
              Text('10°',
                  style: TextStyle(fontSize: 9, color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          // Quick presets
          Row(
            children: [
              _FovPresetButton(
                  label: '0.5°',
                  value: 0.5,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(0.5)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '1°',
                  value: 1.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(1.0)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '2°',
                  value: 2.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(2.0)),
              const SizedBox(width: 6),
              _FovPresetButton(
                  label: '5°',
                  value: 5.0,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(5.0)),
              if (hasEquipment && equipmentFov != null) ...[
                const SizedBox(width: 6),
                _FovPresetButton(
                  label: 'Equip',
                  value: equipmentFov!,
                  currentValue: value,
                  colors: colors,
                  onTap: () => onChanged(equipmentFov!),
                  isEquipment: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FovPresetButton extends StatelessWidget {
  final String label;
  final double value;
  final double currentValue;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final bool isEquipment;

  const _FovPresetButton({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.colors,
    required this.onTap,
    this.isEquipment = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = (currentValue - value).abs() < 0.05;
    final color = isEquipment ? colors.info : colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? color : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EquipmentFovOverlayControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool showOverlay;
  final double opacity;
  final VoidCallback onToggle;
  final ValueChanged<double> onOpacityChanged;

  const _EquipmentFovOverlayControls({
    required this.colors,
    required this.showOverlay,
    required this.opacity,
    required this.onToggle,
    required this.onOpacityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.frame, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Equipment FOV Overlay',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.info,
                  ),
                ),
              ),
              Switch(
                value: showOverlay,
                onChanged: (_) => onToggle(),
                activeThumbColor: colors.info,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          if (showOverlay) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Opacity',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: colors.info,
                      inactiveTrackColor: colors.border,
                      thumbColor: colors.info,
                      overlayColor: colors.info.withValues(alpha: 0.1),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: opacity,
                      min: 0.1,
                      max: 0.8,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 35,
                  child: Text(
                    '${(opacity * 100).round()}%',
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Shows your actual equipment field of view as an overlay',
              style: TextStyle(fontSize: 9, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Mosaic Helper Widgets
// =============================================================================

class _MosaicSpinner extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final NightshadeColors colors;

  const _MosaicSpinner({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _SpinnerButton(
                icon: LucideIcons.minus,
                onTap: value > min ? () => onChanged(value - 1) : null,
                colors: colors,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _SpinnerButton(
                icon: LucideIcons.plus,
                onTap: value < max ? () => onChanged(value + 1) : null,
                colors: colors,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpinnerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final NightshadeColors colors;

  const _SpinnerButton({
    required this.icon,
    this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null ? colors.textPrimary : colors.textMuted,
        ),
      ),
    );
  }
}

class _OptionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_OptionButton> createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.15)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : widget.colors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: widget.isSelected
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

class _StartCornerSelector extends StatelessWidget {
  final MosaicStartCorner selected;
  final ValueChanged<MosaicStartCorner> onChanged;
  final NightshadeColors colors;

  const _StartCornerSelector({
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _CornerOption(
            corner: MosaicStartCorner.topLeft,
            label: 'TL',
            icon: LucideIcons.arrowUpLeft,
            isSelected: selected == MosaicStartCorner.topLeft,
            onTap: () => onChanged(MosaicStartCorner.topLeft),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.topRight,
            label: 'TR',
            icon: LucideIcons.arrowUpRight,
            isSelected: selected == MosaicStartCorner.topRight,
            onTap: () => onChanged(MosaicStartCorner.topRight),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.bottomLeft,
            label: 'BL',
            icon: LucideIcons.arrowDownLeft,
            isSelected: selected == MosaicStartCorner.bottomLeft,
            onTap: () => onChanged(MosaicStartCorner.bottomLeft),
            colors: colors,
          ),
          _CornerOption(
            corner: MosaicStartCorner.bottomRight,
            label: 'BR',
            icon: LucideIcons.arrowDownRight,
            isSelected: selected == MosaicStartCorner.bottomRight,
            onTap: () => onChanged(MosaicStartCorner.bottomRight),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _CornerOption extends StatelessWidget {
  final MosaicStartCorner corner;
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _CornerOption({
    required this.corner,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? colors.primary : colors.textMuted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportMosaicButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final List<MosaicPanel> panels;
  final String targetName;

  const _ExportMosaicButton({
    required this.colors,
    required this.panels,
    required this.targetName,
  });

  @override
  ConsumerState<_ExportMosaicButton> createState() =>
      _ExportMosaicButtonState();
}

class _ExportMosaicButtonState extends ConsumerState<_ExportMosaicButton> {
  bool _isHovered = false;
  bool _isExporting = false;

  Future<void> _exportToTargets() async {
    if (_isExporting || widget.panels.isEmpty) return;

    setState(() => _isExporting = true);

    try {
      final targetsDao = ref.read(targetsDaoProvider);

      // Save each panel as a target
      for (final panel in widget.panels) {
        await targetsDao.createTarget(TargetsCompanion.insert(
          name: '${widget.targetName} - Panel ${panel.index + 1}',
          ra: panel.centerRaHours,
          dec: panel.centerDecDegrees,
          objectType: const Value('mosaic'),
        ));
      }

      if (!mounted) return;
      context.showSuccessSnackBar(
          'Exported ${widget.panels.length} panels to targets');
    } catch (e) {
      context.showErrorSnackBar('Error exporting: $e');
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _exportToTargets,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.colors.primary,
                widget.colors.primary.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isExporting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  LucideIcons.download,
                  size: 14,
                  color: Colors.white,
                ),
              const SizedBox(width: 8),
              Text(
                _isExporting
                    ? 'Exporting...'
                    : 'Export ${widget.panels.length} Panels to Targets',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TAB BAR BUTTON
// =============================================================================

/// A styled tab button for the framing screen tabs
class _TabButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.isSelected
                    ? widget.colors.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            color: _isHovered && !widget.isSelected
                ? widget.colors.surfaceHover
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isSelected
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

// =============================================================================
// SUGGESTIONS TAB
// =============================================================================

/// The suggestions tab content, integrated into the framing screen
class _SuggestionsTab extends ConsumerWidget {
  final void Function(TargetSuggestion suggestion) onTargetSelected;

  const _SuggestionsTab({
    required this.onTargetSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final suggestionsAsync = ref.watch(filteredSuggestionsProvider);

    return suggestionsAsync.when(
      data: (suggestions) => _buildDataState(context, ref, colors, suggestions),
      loading: () => _buildLoadingState(colors),
      error: (error, stackTrace) =>
          _buildErrorState(context, ref, colors, error),
    );
  }

  Widget _buildDataState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    List<TargetSuggestion> suggestions,
  ) {
    if (suggestions.isEmpty) {
      return _buildEmptyState(context, ref, colors);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Determine column count based on width
        // Mobile (< 600): single column
        // Tablet (600-900): 2 columns
        // Desktop (> 900): 2-3 columns
        final int crossAxisCount;
        if (width < NightshadeTokens.breakpointTablet) {
          crossAxisCount = 1;
        } else if (width < 1200) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 3;
        }

        final isMobile = width < NightshadeTokens.breakpointTablet;

        // On mobile, use RefreshIndicator for pull-to-refresh
        Widget content;
        if (crossAxisCount == 1) {
          // Single column ListView for mobile
          content = ListView.builder(
            padding: isMobile
                ? NightshadeTokens.screenPaddingCompact
                : NightshadeTokens.screenPadding,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                child: SuggestionCard(
                  suggestion: suggestions[index],
                  onViewInFraming: () => onTargetSelected(suggestions[index]),
                  onAddToSequence: () {
                    _addToSequence(context, ref, suggestions[index]);
                  },
                ),
              );
            },
          );
        } else {
          // Grid layout for tablet/desktop
          // Calculate card height for ~1.5 rows visible (matching mobile feel)
          final availableHeight = constraints.maxHeight;
          final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
          const hPad = NightshadeTokens.space2xl * 2;
          const gap = NightshadeTokens.spaceLg;
          final cardWidth =
              (width - hPad - (crossAxisCount - 1) * gap) / crossAxisCount;
          final aspectRatio = cardWidth / cardHeight;

          content = GridView.builder(
            padding: NightshadeTokens.screenPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: NightshadeTokens.spaceLg,
              mainAxisSpacing: NightshadeTokens.spaceLg,
              childAspectRatio: aspectRatio,
            ),
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              return SuggestionCard(
                suggestion: suggestions[index],
                onViewInFraming: () => onTargetSelected(suggestions[index]),
                onAddToSequence: () {
                  _addToSequence(context, ref, suggestions[index]);
                },
              );
            },
          );
        }

        // Wrap mobile layout with RefreshIndicator
        if (isMobile) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.read(refreshSuggestionsProvider.notifier).state++;
              await ref.read(tonightSuggestionsProvider.future);
            },
            color: colors.primary,
            backgroundColor: colors.surface,
            child: content,
          );
        }

        return content;
      },
    );
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < NightshadeTokens.breakpointTablet;
        final crossAxisCount = isMobile ? 1 : 2;

        // Match data-state card sizing
        final availableHeight = constraints.maxHeight;
        final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
        const hPad = NightshadeTokens.space2xl * 2;
        const gap = NightshadeTokens.spaceLg;
        final cardWidth =
            (width - hPad - (crossAxisCount - 1) * gap) / crossAxisCount;
        final aspectRatio = cardWidth / cardHeight;

        // Show shimmer loading states
        return ShimmerLoading(
          child: crossAxisCount == 1
              ? ListView.builder(
                  padding: isMobile
                      ? NightshadeTokens.screenPaddingCompact
                      : NightshadeTokens.screenPadding,
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: NightshadeTokens.spaceMd),
                      child: _SuggestionCardSkeleton(colors: colors),
                    );
                  },
                )
              : GridView.builder(
                  padding: NightshadeTokens.screenPadding,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: NightshadeTokens.spaceLg,
                    mainAxisSpacing: NightshadeTokens.spaceLg,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return _SuggestionCardSkeleton(colors: colors);
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmptyState(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    // Check if location is configured
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final hasLocation = settings != null &&
        !(settings.latitude == 0.0 && settings.longitude == 0.0);

    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLocation ? LucideIcons.moonStar : LucideIcons.mapPin,
              size: NightshadeTokens.icon2xl,
              color: colors.textMuted,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              hasLocation
                  ? 'No targets visible tonight'
                  : 'Location not configured',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              hasLocation
                  ? 'All targets in your database are below the minimum altitude or have low scores for tonight\'s conditions.'
                  : 'Set your observer location in Settings to see target suggestions for your area.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            if (!hasLocation)
              NightshadeButton(
                label: 'Open Settings',
                icon: LucideIcons.settings,
                onPressed: () {
                  // Use GoRouter to navigate
                  GoRouter.of(context).go('/settings');
                },
              )
            else
              NightshadeButton(
                label: 'Adjust Filters',
                icon: LucideIcons.slidersHorizontal,
                variant: ButtonVariant.outline,
                onPressed: () => _showFilterSheet(context, ref, colors),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    Object error,
  ) {
    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: NightshadeTokens.icon2xl,
              color: colors.error,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              'Failed to load suggestions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            NightshadeButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              onPressed: () {
                ref.read(refreshSuggestionsProvider.notifier).state++;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NightshadeTokens.radiusLg),
        ),
      ),
      builder: (context) {
        return const SuggestionFilters(showAsSheet: true);
      },
    );
  }

  void _addToSequence(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion suggestion,
  ) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Add to Sequence',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Add "${suggestion.targetName}" to the current sequence?',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              label: 'Add',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () {
                // Create a TargetHeaderNode for the suggestion
                final targetNode = TargetHeaderNode(
                  targetName: suggestion.targetName,
                  raHours: suggestion.raHours,
                  decDegrees: suggestion.decDegrees,
                );

                // Add target to sequence via provider
                ref
                    .read(currentSequenceProvider.notifier)
                    .addTargetHeader(targetNode);

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${suggestion.targetName} to sequence'),
                    backgroundColor: colors.success,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Skeleton loading cards for suggestions
class _SuggestionCardSkeleton extends StatelessWidget {
  final NightshadeColors colors;

  const _SuggestionCardSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 150, height: 18),
              Spacer(),
              SkeletonBox(
                  width: 60,
                  height: 24,
                  borderRadius: NightshadeTokens.radiusFull),
            ],
          ),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonText(width: 200, height: 14),
          SizedBox(height: NightshadeTokens.spaceSm),
          SkeletonText(width: double.infinity, height: 12, lines: 2),
          Spacer(),
          Row(
            children: [
              SkeletonBox(width: 80, height: 20),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 80, height: 20),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 80, height: 20),
            ],
          ),
        ],
      ),
    );
  }
}
