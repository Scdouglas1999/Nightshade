import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../../utils/snackbar_helper.dart';
import '../settings/catalog_settings_screen.dart';
import 'tabs/mount_tab.dart';
import 'widgets/annotation_widgets.dart';
import 'widgets/calibration_section.dart';
import 'widgets/capture_panel.dart';
import 'widgets/camera_panel.dart';
import 'widgets/focus_panel.dart';
import 'widgets/guiding_panel.dart';
import 'widgets/imaging_bottom_banner.dart';
import 'widgets/imaging_preview_toolbar.dart';
import 'widgets/live_preview_area.dart';
import 'widgets/meridian_flip_countdown_banner.dart';
import 'widgets/panel_widgets.dart';
import 'widgets/rotator_panel.dart';
import 'widgets/stacking_panel.dart';
import '../../widgets/tutorial_keys/imaging_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

part 'imaging_screen/imaging_screen_actions.dart';

/// Provider to check if annotation catalog is installed
final annotationCatalogInstalledProvider = FutureProvider<bool>((ref) async {
  final status = await CatalogManager.instance.getAnnotationCatalogStatus();
  return status.isInstalled;
});

/// Provider to track if the annotation catalog banner has been dismissed (persisted)
final annotationBannerDismissedProvider = FutureProvider<bool>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final value = await dao.getSetting('annotation_catalog_prompt_dismissed');
  return value == 'true';
});

/// Provider to track if the first-use catalog dialog has been shown this session
final _catalogDialogShownThisSessionProvider =
    StateProvider<bool>((ref) => false);

class ImagingScreen extends ConsumerStatefulWidget {
  const ImagingScreen({super.key});

  @override
  ConsumerState<ImagingScreen> createState() => _ImagingScreenState();
}

class _ImagingScreenState extends ConsumerState<ImagingScreen>
    with SingleTickerProviderStateMixin {
  // Panel selection is now stored in provider for persistence across navigation
  late AnimationController _fadeController;

  // Local capture state
  bool _isLooping = false;
  bool _isSingleCapture = false;

  void _update(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    // Initialize the annotation service to set up the image listener
    // This must happen on first frame to have access to ref
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAnnotationService();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _selectPanel(int index) {
    final currentPanel = ref.read(selectedImagingPanelProvider);
    if (index != currentPanel) {
      _fadeController.reset();
      ref.read(selectedImagingPanelProvider.notifier).state = index;
      _fadeController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sync snapshot exposure defaults from the active equipment profile
    ref.watch(syncExposureFromProfileProvider);

    final colors = context.nightshadeColors;
    final selectedPanel = ref.watch(selectedImagingPanelProvider);
    final annotationSettings = ref.watch(annotationSettingsProvider);
    final catalogInstalled = ref.watch(annotationCatalogInstalledProvider);
    final bannerDismissed = ref.watch(annotationBannerDismissedProvider);

    // Show banner if annotations are enabled but catalog is not installed
    final showBanner = (annotationSettings.valueOrNull?.enabled ?? false) &&
        catalogInstalled.valueOrNull == false &&
        !(bannerDismissed.valueOrNull ?? false);

    // Watch shared viewer state so rebuilds reflect zoom/pan/overlay changes.
    final viewerState = ref.watch(imagingViewerStateProvider);

    // Replace the previous build-time `_checkFirstUseCatalogPrompt()` call:
    // ref.listen fires only on actual provider transitions, so resize storms
    // and hot reloads no longer trigger duplicate dialogs (audit §4.3).
    ref.listen<AnnotationState>(annotationStateProvider, (prev, next) {
      _maybeShowFirstUseCatalogPrompt(next);
    });

    return ContextualTourPrompt(
      screenId: 'imaging',
      tourCategory: TutorialCategory.imagingTour,
      title: 'Imaging Tour',
      description: 'Learn how to capture, preview, and manage your images.',
      durationMinutes: 4,
      alignment: Alignment.bottomRight,
      child: Column(
        children: [
          // Annotation catalog banner
          if (showBanner)
            AnnotationCatalogBanner(
              colors: colors,
              onDismiss: () => _dismissCatalogPrompt(),
              onSetup: () {
                _dismissCatalogPrompt();
                // Show catalog settings dialog
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    child: ConstrainedBox(
                      constraints: AdaptiveDialogConstraints.hybrid(
                        context,
                        designMaxWidth: 800,
                        designMaxHeight: 700,
                      ),
                      child: const CatalogSettingsScreen(),
                    ),
                  ),
                ).then((_) {
                  // Refresh catalog status after dialog closes
                  ref.invalidate(annotationCatalogInstalledProvider);
                });
              },
            ),

          // Live meridian-flip countdown. Self-hides (SizedBox.shrink, zero
          // height) whenever a flip is not armed, so it adds no chrome on idle
          // nights and never pushes the live preview down. As a child of this
          // top-level Column it appears on both the desktop and mobile layouts.
          const MeridianFlipCountdownBanner(),

          // Main content. A single AdaptivePanelLayout replaces the former
          // desktop `ResizablePanel` split AND the bespoke mobile column:
          //
          //   * Desktop (w >= 768): resizable split — preview column on the
          //     left, the tab panel on the right with a draggable divider,
          //     reproducing the old `ResizablePanel(320/250/500, side left)`.
          //   * Tablet (600..768): fixed-ratio side-by-side split.
          //   * Phone portrait (w < 600): the tab panel collapses into a bottom
          //     sheet so the live preview keeps the whole screen; a persistent
          //     compact capture bar under the preview keeps Snapshot / Loop /
          //     duration reachable WITHOUT opening the sheet.
          //   * Phone landscape (enough width): automatic side-by-side split
          //     (preview left, controls right).
          //
          // We compute the phone tier on the screen's OWN constraints (not the
          // raw window) so an embedded/remote layout still reflows correctly.
          //
          // On phone the persistent capture bar is a SIBLING below the
          // AdaptivePanelLayout (not inside its primary): the bottom-sheet
          // strategy floats a "Controls" handle at the bottom edge of its
          // primary region, so anchoring the capture bar below the panel keeps
          // that handle from overlapping the Snapshot/Loop buttons.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isPhone =
                    constraints.maxWidth < BreakpointTokens.breakpointPhone;
                // A phone held in landscape reports a tablet-ish WIDTH (e.g.
                // 640) but a very SHORT height (~360). Stacking the desktop
                // bottom control panel under the preview there squeezes the
                // image and overflows, so we treat a short viewport the same as
                // a phone: the live preview keeps the column, the tabs sit
                // beside it (AdaptivePanelLayout's landscape/tablet split), and
                // the persistent capture bar carries Snapshot/Loop below.
                final isShort = constraints.maxHeight.isFinite &&
                    constraints.maxHeight < 500;
                final compact = isPhone || isShort;
                final panel = AdaptivePanelLayout(
                  phoneStrategy: PhonePanelStrategy.bottomSheet,
                  panelSide: PanelSide.end,
                  initialPanelWidth: 320,
                  minPanelWidth: 250,
                  maxPanelWidth: 500,
                  primarySegmentLabel: 'Image',
                  primarySegmentIcon: NightshadeIcons.image,
                  primary: _buildPreviewColumn(
                    colors,
                    viewerState,
                    phone: compact,
                  ),
                  secondary: [
                    AdaptivePanel(
                      title: 'Controls',
                      icon: NightshadeIcons.sliders,
                      child: _buildTabsPanel(
                        colors,
                        selectedPanel,
                        phone: compact,
                      ),
                    ),
                  ],
                );
                if (!compact) return panel;
                // When the controls sit in a landscape side-by-side SPLIT, the
                // Capture tab's Snapshot/Loop are already visible beside the
                // image — so a persistent bottom capture bar is both redundant
                // AND overflows the short (~430 px) landscape height, floating
                // over the preview. Only add the bar when the controls are
                // COLLAPSED (portrait, or a very narrow landscape that falls
                // back to the sheet), where the primary action would otherwise
                // be hidden behind the controls handle. This mirrors
                // AdaptivePanelLayout's own landscape-split condition
                // (landscape && width >= landscapeSplitMinWidth, default 560).
                final controlsInLandscapeSplit =
                    constraints.maxWidth > constraints.maxHeight &&
                        constraints.maxWidth >= 560;
                if (controlsInLandscapeSplit) return panel;
                return Column(
                  children: [
                    Expanded(child: panel),
                    _buildPhoneCaptureBar(colors),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The dominant region handed to [AdaptivePanelLayout] as `primary`: the
  /// off-canvas toolbar, the live preview (which absorbs all free height), and
  /// — on desktop / tablet — the capped bottom control panel beneath it.
  ///
  /// On phone the bottom control panel is NOT included here; the persistent
  /// capture bar is composed as a sibling of the whole panel (see [build]) so
  /// the live preview keeps the full primary region.
  Widget _buildPreviewColumn(
    NightshadeColors colors,
    ImagingViewerState viewerState, {
    required bool phone,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hide the inline Stats readout on narrow widths, matching the old
        // panel which dropped the whole Stats section below ~600px.
        final showStats =
            constraints.maxWidth >= BreakpointTokens.breakpointPhone;
        return Column(
          // Stretch so every child (toolbar, preview, control banner) gets a
          // TIGHT width equal to the column. Without this the column defaults
          // to CrossAxisAlignment.center, which hands children LOOSE width
          // constraints — and the live preview's inner Stack holds only
          // Positioned children, so under a loose width it collapses to zero
          // width (height stays correct via the Expanded). That zero-width
          // Stack is exactly why captured frames rendered blank here while the
          // dashboard's stretch-column copy of the same ImageDisplayWidget
          // showed them fine.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Slim off-canvas toolbar above the preview — status readouts,
            // Overlays menu, annotate toggle and view controls live here so the
            // image canvas itself stays unobstructed.
            ImagingPreviewToolbar(
              colors: colors,
              zoomLevel: viewerState.zoomLevel,
              showCrosshair: viewerState.showCrosshair,
              showStarOverlay: viewerState.showStarOverlay,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onFitToWindow: _fitToWindow,
              onZoom1to1: _zoom1to1,
              onAbortCapture: _abortCapture,
              onToggleCrosshair: _viewer.toggleCrosshair,
              onToggleStarOverlay: _viewer.toggleStarOverlay,
            ),
            // Live preview area — dominant, absorbs all free height.
            Expanded(
              child: LivePreviewArea(
                key: ImagingTutorialKeys.previewArea,
                colors: colors,
                zoomLevel: viewerState.zoomLevel,
                panOffset: viewerState.panOffset,
                showCrosshair: viewerState.showCrosshair,
                showStarOverlay: viewerState.showStarOverlay,
                onZoomIn: _zoomIn,
                onZoomOut: _zoomOut,
                onPanUpdate: _panPreview,
              ),
            ),
            // Desktop / tablet bottom control BANNER — a single thin toolbar
            // row (Snapshot/Loop, duration + an Exposure popover, the filter
            // strip, an inline stats readout, and the compact stretch/display
            // controls). It replaces the former three always-expanded
            // collapsible sections, so the live preview's Expanded above keeps
            // the vertical room. On phone this is omitted: the persistent
            // capture bar (composed as a sibling in [build]) carries
            // Duration + Snapshot + Loop.
            if (!phone)
              FadeTransition(
                opacity: _fadeController,
                child: ImagingBottomBanner(
                  colors: colors,
                  isLooping: _isLooping,
                  isSingleCapture: _isSingleCapture,
                  showStats: showStats,
                  onSnapshot: _takeSnapshot,
                  onToggleLoop: _toggleLoop,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The tab strip + IndexedStack panel handed to [AdaptivePanelLayout] as the
  /// secondary panel.
  ///
  /// On desktop/tablet (`phone == false`) it fills the side column, so the
  /// IndexedStack lives in an [Expanded] and each tab's own scroll view handles
  /// overflow. On phone (`phone == true`) it is hosted inside the bottom sheet,
  /// whose body is itself a [SingleChildScrollView] — an [Expanded] there would
  /// be unbounded and throw — so we give the IndexedStack a bounded height
  /// (capped to the sheet's working area) and let each tab scroll internally.
  Widget _buildTabsPanel(
    NightshadeColors colors,
    int selectedPanel, {
    required bool phone,
  }) {
    final stack = FadeTransition(
      opacity: _fadeController,
      child: IndexedStack(
        index: selectedPanel,
        children: [
          CapturePanel(colors: colors),
          _CameraTabContent(colors: colors),
          FocusPanel(key: ImagingTutorialKeys.focusTab, colors: colors),
          GuidingPanel(colors: colors),
          MountTab(key: ImagingTutorialKeys.mountTab),
          RotatorPanel(colors: colors),
          StackingPanel(colors: colors),
          AnnotationTabPanel(colors: colors),
        ],
      ),
    );

    if (phone) {
      // The phone/compact variant is hosted in two different containers:
      //   * the bottom SHEET, whose body is a SingleChildScrollView (unbounded
      //     height) — there an Expanded would throw, so we size the body to a
      //     fraction of the screen and let each tab scroll internally; and
      //   * the landscape/tablet side-by-side SPLIT, where the panel sits in a
      //     bounded Expanded column.
      //
      // A LayoutBuilder distinguishes the two: when the incoming height is
      // bounded (the split) we let the IndexedStack fill it via Expanded; when
      // it is unbounded (the sheet) we fall back to the screen-fraction
      // SizedBox. This avoids any fixed height ever exceeding a bounded parent
      // by a sub-pixel during fade frames.
      return Container(
        decoration: BoxDecoration(color: colors.surface),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabs = PanelTabs(
              key: ImagingTutorialKeys.tabBar,
              selectedIndex: selectedPanel,
              onSelected: _selectPanel,
              colors: colors,
              compact: phone,
            );
            if (constraints.maxHeight.isFinite) {
              return Column(
                children: [tabs, Expanded(child: stack)],
              );
            }
            final bodyHeight = MediaQuery.sizeOf(context).height * 0.52;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [tabs, SizedBox(height: bodyHeight, child: stack)],
            );
          },
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: colors.surface),
      child: Column(
        children: [
          PanelTabs(
            key: ImagingTutorialKeys.tabBar,
            selectedIndex: selectedPanel,
            onSelected: _selectPanel,
            colors: colors,
          ),
          Expanded(child: stack),
        ],
      ),
    );
  }

  /// Persistent compact capture bar shown under the live preview on phones.
  ///
  /// Keeps the primary capture action reachable WITHOUT scrolling or opening
  /// the controls sheet (mobile-responsive standard rule 5). It reflows via a
  /// [Wrap] so the Duration field + Snapshot + Loop never overflow at the
  /// narrowest supported width (360 px), and exposes the same snapshot/loop
  /// handlers and `isEnabled` gating as the desktop control panel.
  Widget _buildPhoneCaptureBar(NightshadeColors colors) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing = _isSingleCapture || _isLooping;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final hostSuffix = isRemoteMode ? ' (host)' : '';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Duration field.
              SizedBox(
                width: 110,
                child: EditableCompactInput(
                  key: ImagingTutorialKeys.exposureSlider,
                  label: 'Duration$hostSuffix',
                  value: exposureSettings.exposureTime.toStringAsFixed(0),
                  suffix: 's',
                  colors: colors,
                  isMobile: true,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(exposureTime: parsed);
                    }
                  },
                ),
              ),
              // Snapshot — the primary capture action.
              SizedBox(
                width: 150,
                child: BigActionButton(
                  key: ImagingTutorialKeys.snapshotBtn,
                  icon: _isSingleCapture
                      ? NightshadeIcons.loading
                      : NightshadeIcons.camera,
                  label: _isSingleCapture ? 'Taking...' : 'Snapshot$hostSuffix',
                  color: colors.primary,
                  isLoading: _isSingleCapture,
                  isEnabled: isConnected && !isCapturing,
                  onPressed: _takeSnapshot,
                  isMobile: true,
                ),
              ),
              // Loop / Stop.
              SizedBox(
                width: 120,
                child: BigActionButton(
                  key: ImagingTutorialKeys.loopBtn,
                  icon: _isLooping ? NightshadeIcons.stop : LucideIcons.video,
                  label: _isLooping ? 'Stop' : 'Loop',
                  color: _isLooping ? colors.error : colors.accent,
                  isEnabled: isConnected && !_isSingleCapture,
                  onPressed: _toggleLoop,
                  isMobile: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Composes the Camera tab from its existing controls and the new
/// [CalibrationSection]. Kept in this file (rather than mutating
/// [CameraPanel] directly) so the tab/panel layout stays the single
/// integration point for the W6-DEFECT UI.
///
/// The Camera tab and the [CalibrationSection] share ONE scroll view so the
/// Cooling controls keep their natural height. Previously [CameraPanel] was an
/// [Expanded] scroll region with the calibration card pinned below it, which
/// let the full-height calibration card squeeze Cooling into a cramped,
/// separately-scrolling strip. [CameraPanel] now renders non-scrolling
/// ([CameraPanel.scrollable] = false) and the single outer
/// [SingleChildScrollView] scrolls the whole tab — no nested scroll regions.
class _CameraTabContent extends StatelessWidget {
  final NightshadeColors colors;

  const _CameraTabContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CameraPanel(colors: colors, scrollable: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: CalibrationSection(colors: colors),
          ),
        ],
      ),
    );
  }
}
