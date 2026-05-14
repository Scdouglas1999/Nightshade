import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;

import 'package:nightshade_app/utils/snackbar_helper.dart';
import 'framing_altaz.dart';
import 'framing_search_provider.dart';
import '../../widgets/tutorial_keys/framing_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../suggestions/widgets/suggestion_filters.dart';
import 'widgets/optical_config_panel.dart';
import 'widgets/framing_canvas.dart';
import 'widgets/framing_controls.dart';
import 'widgets/framing_sidebar.dart';
import 'widgets/framing_suggestions_tab.dart';

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
    AppSettingsState? settings,
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
              FramingSuggestionsTab(
                onTargetSelected: (suggestion) =>
                    _navigateToFramingWithTarget(suggestion),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(NightshadeColors colors) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          FramingTabButton(
            icon: LucideIcons.frame,
            label: 'Framing',
            isSelected: _currentTabIndex == 0,
            colors: colors,
            onTap: () {
              _tabController.animateTo(0);
              setState(() => _currentTabIndex = 0);
            },
          ),
          FramingTabButton(
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
                Positioned.fill(
                  child: FramingCanvas(
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
                  FramingTargetSearch(
                    colors: colors,
                    searchState: searchState,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    raController: _raController,
                    decController: _decController,
                    onTargetSelected: _selectTarget,
                    onResolveByName: _resolveAndSelectTarget,
                    onGoToManualCoordinates: _goToManualCoordinates,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FramingEquipmentSection(
                            colors: colors,
                            equipmentAsync: equipmentResult,
                          ),
                          const SizedBox(height: 20),
                          FramingControlsSection(
                            colors: colors,
                            framingState: framingState,
                            equipmentAsync: equipmentResult,
                          ),
                          const SizedBox(height: 20),
                          FramingCoordinatesPanel(
                            colors: colors,
                            framingState: framingState,
                            currentAltAz: currentAltAz,
                          ),
                          const SizedBox(height: 20),
                          FramingAltitudePanel(
                            colors: colors,
                            framingState: framingState,
                          ),
                          const SizedBox(height: 20),
                          FramingMosaicSection(
                            colors: colors,
                            framingState: framingState,
                            equipmentAsync: equipmentResult,
                          ),
                          const SizedBox(height: 20),
                          FramingActionsPanel(
                            colors: colors,
                            framingState: framingState,
                            onAddToSequence: () =>
                                _addToSequence(framingState.target!),
                            onSaveTarget: _saveTarget,
                            onCacheImage: _cacheImage,
                          ),
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

  void _navigateToFramingWithTarget(TargetSuggestion suggestion) {
    ref.read(framingProvider.notifier).setTargetCoordinates(
          suggestion.raHours,
          suggestion.decDegrees,
          name: suggestion.targetName,
        );

    _tabController.animateTo(0);
    setState(() => _currentTabIndex = 0);

    _searchController.text = suggestion.targetName;
    _raController.text = CoordinateUtils.formatRA(suggestion.raHours);
    _decController.text = CoordinateUtils.formatDec(suggestion.decDegrees);
    // Alt/Az auto-refreshes on the next build via _computeCurrentAltAz.
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

  void _addToSequence(FramingTarget target) {
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
