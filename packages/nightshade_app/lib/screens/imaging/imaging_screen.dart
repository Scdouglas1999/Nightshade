import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../../utils/snackbar_helper.dart';
import '../settings/catalog_settings_screen.dart';
import 'tabs/mount_tab.dart';
import 'widgets/stretch_controls.dart';
import 'widgets/annotation_widgets.dart';
import 'widgets/calibration_section.dart';
import 'widgets/capture_panel.dart';
import 'widgets/collapsible_control_panel.dart';
import 'widgets/camera_panel.dart';
import 'widgets/focus_panel.dart';
import 'widgets/guiding_panel.dart';
import 'widgets/imaging_preview_toolbar.dart';
import 'widgets/live_preview_area.dart';
import 'widgets/meridian_flip_countdown_banner.dart';
import 'widgets/panel_widgets.dart';
import 'widgets/rotator_panel.dart';
import 'widgets/stacking_panel.dart';
import '../../widgets/filter_wheel_selector.dart';
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

          // Main content
          Expanded(
            child: Responsive.isMobile(context)
                ? _buildMobileLayout(colors, selectedPanel, viewerState)
                : _buildDesktopLayout(colors, selectedPanel, viewerState),
          ),
        ],
      ),
    );
  }

  /// Mobile layout: Tabs at bottom, full-width content
  Widget _buildMobileLayout(
    NightshadeColors colors,
    int selectedPanel,
    ImagingViewerState viewerState,
  ) {
    return Column(
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
        // Live preview area (compact on mobile)
        Expanded(
          flex: 4,
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

        // Tab content area (scrollable)
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                top: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              children: [
                // Panel tabs (full width on mobile)
                PanelTabs(
                  key: ImagingTutorialKeys.tabBar,
                  selectedIndex: selectedPanel,
                  onSelected: _selectPanel,
                  colors: colors,
                ),

                // Panel content
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: IndexedStack(
                      index: selectedPanel,
                      children: [
                        CapturePanel(colors: colors),
                        _CameraTabContent(colors: colors),
                        FocusPanel(
                            key: ImagingTutorialKeys.focusTab, colors: colors),
                        GuidingPanel(colors: colors),
                        MountTab(key: ImagingTutorialKeys.mountTab),
                        RotatorPanel(colors: colors),
                        StackingPanel(colors: colors),
                        AnnotationTabPanel(colors: colors),
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

  /// Desktop layout: Side panel with tabs, image viewer takes most space
  Widget _buildDesktopLayout(
    NightshadeColors colors,
    int selectedPanel,
    ImagingViewerState viewerState,
  ) {
    return Row(
      children: [
        // Main content area (image + controls)
        Expanded(
          flex: 7,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Cap the bottom control panel at ~45% of the available column
              // height so the fully-expanded panel can never squeeze the live
              // preview to nothing. The panel itself sizes to its content
              // (it is NOT an Expanded), so as its sections collapse it shrinks
              // and the preview's Expanded above absorbs the reclaimed height —
              // which is the whole point of the collapsible layout. If the
              // expanded controls exceed the cap they scroll internally.
              final maxPanelHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight * 0.45
                  : double.infinity;
              return Column(
                children: [
                  // Slim off-canvas toolbar above the preview — status
                  // readouts, Overlays menu, annotate toggle and view controls
                  // live here so the image canvas itself stays unobstructed.
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
                  // Live preview area
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

                  // Bottom control panel — content-sized, capped + scrollable.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxPanelHeight),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          top: BorderSide(color: colors.border),
                        ),
                      ),
                      child: FadeTransition(
                        opacity: _fadeController,
                        child: SingleChildScrollView(
                          child: _buildControlPanel(colors),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Right panel with tabs
        ResizablePanel(
          initialWidth: 320,
          minWidth: 250,
          maxWidth: 500,
          side: ResizeSide.left,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                left: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              children: [
                // Panel tabs
                PanelTabs(
                  key: ImagingTutorialKeys.tabBar,
                  selectedIndex: selectedPanel,
                  onSelected: _selectPanel,
                  colors: colors,
                ),

                // Panel content
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: IndexedStack(
                      index: selectedPanel,
                      children: [
                        CapturePanel(colors: colors),
                        _CameraTabContent(colors: colors),
                        FocusPanel(
                            key: ImagingTutorialKeys.focusTab, colors: colors),
                        GuidingPanel(colors: colors),
                        MountTab(key: ImagingTutorialKeys.mountTab),
                        RotatorPanel(colors: colors),
                        StackingPanel(colors: colors),
                        AnnotationTabPanel(colors: colors),
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

  Widget _buildControlPanel(NightshadeColors colors) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing = _isSingleCapture || _isLooping;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final hostSuffix = isRemoteMode ? ' (host)' : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < BreakpointTokens.breakpointPhone;
        final isSmallMobile = constraints.maxWidth < 400;
        final horizontalPadding = isMobile ? 12.0 : 16.0;
        final verticalPadding = isMobile ? 12.0 : 16.0;
        final sectionSpacing = isSmallMobile ? 12.0 : (isMobile ? 16.0 : 24.0);

        // On very small screens, stack vertically
        if (isSmallMobile) {
          return Padding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, vertical: verticalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Capture controls
                ControlSection(
                  title: 'Capture$hostSuffix',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: BigActionButton(
                          key: ImagingTutorialKeys.snapshotBtn,
                          icon: _isSingleCapture
                              ? LucideIcons.loader2
                              : LucideIcons.camera,
                          label: _isSingleCapture
                              ? 'Taking...'
                              : 'Snapshot$hostSuffix',
                          color: colors.primary,
                          isLoading: _isSingleCapture,
                          isEnabled: isConnected && !isCapturing,
                          onPressed: _takeSnapshot,
                          isMobile: true,
                        ),
                      ),
                      SizedBox(width: sectionSpacing),
                      Expanded(
                        child: BigActionButton(
                          key: ImagingTutorialKeys.loopBtn,
                          icon: _isLooping
                              ? LucideIcons.square
                              : LucideIcons.video,
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
                SizedBox(height: sectionSpacing),
                // Exposure settings
                ControlSection(
                  title: 'Exposure$hostSuffix',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: EditableCompactInput(
                          key: ImagingTutorialKeys.exposureSlider,
                          label: 'Duration$hostSuffix',
                          value:
                              exposureSettings.exposureTime.toStringAsFixed(0),
                          suffix: 's',
                          colors: colors,
                          isMobile: true,
                          onChanged: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null && parsed > 0) {
                              ref
                                      .read(exposureSettingsProvider.notifier)
                                      .state =
                                  exposureSettings.copyWith(
                                      exposureTime: parsed);
                            }
                          },
                        ),
                      ),
                      SizedBox(width: sectionSpacing),
                      Expanded(
                        child: EditableCompactInput(
                          key: ImagingTutorialKeys.gainControl,
                          label: 'Gain',
                          value: exposureSettings.gain.toString(),
                          colors: colors,
                          isMobile: true,
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null && parsed >= 0) {
                              ref
                                      .read(exposureSettingsProvider.notifier)
                                      .state =
                                  exposureSettings.copyWith(gain: parsed);
                            }
                          },
                        ),
                      ),
                      SizedBox(width: sectionSpacing),
                      Expanded(
                        child: EditableCompactInput(
                          label: 'Offset',
                          value: exposureSettings.offset.toString(),
                          colors: colors,
                          isMobile: true,
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null && parsed >= 0) {
                              ref
                                      .read(exposureSettingsProvider.notifier)
                                      .state =
                                  exposureSettings.copyWith(offset: parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: sectionSpacing),
                // Filter selection
                ControlSection(
                  title: 'Filter',
                  colors: colors,
                  child: FilterWheelSelector(
                    key: ImagingTutorialKeys.filterSelector,
                    style: FilterSelectorStyle.buttons,
                    compact: true,
                  ),
                ),
                SizedBox(height: sectionSpacing),
                // Stretch controls
                ControlSection(
                  title: 'Display',
                  colors: colors,
                  child: const StretchControls(compact: true),
                ),
              ],
            ),
          );
        }

        // On larger screens the bottom control panel is split into three
        // independently collapsible sections so the live preview's Expanded
        // can grow to fill the freed space when the operator wants the image
        // to dominate the screen for review (IMG layout work):
        //
        //   1. Quick Capture — Capture / Exposure / Filter. When collapsed it
        //      shrinks to a thin "quick capture" bar that keeps filter
        //      switching + the duration field + the snapshot button reachable
        //      inline, so the most-used controls never vanish.
        //   2. Stats — temp / RMS / HFR. Collapses to a thin header that shows
        //      the same three readouts inline as a summary.
        //   3. Display — stretch controls. Collapses away entirely.
        //
        // Each section persists its expanded state for the session via the
        // providers in collapsible_control_panel.dart, matching the equipment
        // screen's rail/section collapse providers.
        //
        // The expanded Capture / Exposure / Filter bodies still flow through a
        // Wrap so they reflow onto a second line when horizontal space is
        // tight — preserving the audit §4.9 fix that stopped the Capture
        // buttons from scrolling offscreen on narrow desktop windows.
        final wrapSpacing = sectionSpacing;

        final captureSection = ControlSection(
          title: 'Capture$hostSuffix',
          colors: colors,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BigActionButton(
                key: ImagingTutorialKeys.snapshotBtn,
                icon:
                    _isSingleCapture ? LucideIcons.loader2 : LucideIcons.camera,
                label: _isSingleCapture ? 'Taking...' : 'Snapshot$hostSuffix',
                color: colors.primary,
                isLoading: _isSingleCapture,
                isEnabled: isConnected && !isCapturing,
                onPressed: _takeSnapshot,
              ),
              const SizedBox(width: 12),
              BigActionButton(
                key: ImagingTutorialKeys.loopBtn,
                icon: _isLooping ? LucideIcons.square : LucideIcons.video,
                label: _isLooping ? 'Stop' : 'Loop',
                color: _isLooping ? colors.error : colors.accent,
                isEnabled: isConnected && !_isSingleCapture,
                onPressed: _toggleLoop,
              ),
            ],
          ),
        );

        final exposureSection = ControlSection(
          title: 'Exposure$hostSuffix',
          colors: colors,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EditableCompactInput(
                key: ImagingTutorialKeys.exposureSlider,
                label: 'Duration$hostSuffix',
                value: exposureSettings.exposureTime.toStringAsFixed(0),
                suffix: 's',
                colors: colors,
                isMobile: isMobile,
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(exposureTime: parsed);
                  }
                },
              ),
              SizedBox(width: isMobile ? 8.0 : 12.0),
              EditableCompactInput(
                key: ImagingTutorialKeys.gainControl,
                label: 'Gain',
                value: exposureSettings.gain.toString(),
                colors: colors,
                isMobile: isMobile,
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed >= 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(gain: parsed);
                  }
                },
              ),
              SizedBox(width: isMobile ? 8.0 : 12.0),
              EditableCompactInput(
                label: 'Offset',
                value: exposureSettings.offset.toString(),
                colors: colors,
                isMobile: isMobile,
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed >= 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(offset: parsed);
                  }
                },
              ),
            ],
          ),
        );

        // Filter selector. In the wide single-row layout it scrolls
        // horizontally (with a trailing fade) so a profile with many filters
        // sits to the RIGHT of the capture controls instead of wrapping onto
        // its own row; in the narrow fallback it renders at natural width and
        // the Wrap reflows it below.
        ControlSection buildFilterSection({required bool scrollable}) {
          final selector = FilterWheelSelector(
            key: ImagingTutorialKeys.filterSelector,
            style: FilterSelectorStyle.buttons,
            compact: isMobile,
          );
          return ControlSection(
            title: 'Filter',
            colors: colors,
            child: scrollable
                ? ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFFFFFFF),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.92, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: selector,
                    ),
                  )
                : selector,
          );
        }

        // Cap + centre the panel so it doesn't stretch edge-to-edge on wide
        // monitors. A full-width panel spreads the Capture / Exposure / Filter
        // groups far apart and wastes horizontal room the image canvas could
        // use; centring at kImagingControlPanelMaxWidth keeps the controls in
        // one comfortable cluster anchored under the preview. The inner Wrap
        // still reflows when the available width is below the cap.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kImagingControlPanelMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: verticalPadding / 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Quick-capture section. Expanded: full Capture / Exposure /
                  // Filter controls. Collapsed: a thin bar with inline filter
                  // switching + duration + snapshot.
                  CollapsibleControlSection(
                    icon: LucideIcons.camera,
                    title: 'Quick Capture$hostSuffix',
                    expandedProvider: imagingCaptureSectionExpandedProvider,
                    colors: colors,
                    collapsedTrailing: QuickCaptureBar(
                      colors: colors,
                      exposureSettings: exposureSettings,
                      isConnected: isConnected,
                      isCapturing: isCapturing,
                      isSingleCapture: _isSingleCapture,
                      hostSuffix: hostSuffix,
                      onDurationChanged: (parsed) {
                        ref.read(exposureSettingsProvider.notifier).state =
                            exposureSettings.copyWith(exposureTime: parsed);
                      },
                      onSnapshot: _takeSnapshot,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Wide enough to seat Capture + Exposure + a scrolling
                        // Filter strip on a single row (filters to the right of
                        // the capture controls), saving the vertical run the
                        // wrapped layout cost. Narrow widths fall back to the
                        // reflowing Wrap so cramped/mobile panels still fit.
                        const oneRowMinWidth = 720.0;
                        if (constraints.maxWidth >= oneRowMinWidth) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              captureSection,
                              SizedBox(width: wrapSpacing),
                              exposureSection,
                              SizedBox(width: wrapSpacing),
                              Flexible(
                                child: buildFilterSection(scrollable: true),
                              ),
                            ],
                          );
                        }
                        return Wrap(
                          spacing: wrapSpacing,
                          runSpacing: wrapSpacing,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            captureSection,
                            exposureSection,
                            buildFilterSection(scrollable: false),
                          ],
                        );
                      },
                    ),
                  ),
                  // Stats section (temp / RMS / HFR). Hidden entirely on mobile
                  // widths to save space, mirroring the previous behaviour.
                  if (!isMobile)
                    CollapsibleControlSection(
                      icon: LucideIcons.activity,
                      title: 'Stats',
                      expandedProvider: imagingStatsSectionExpandedProvider,
                      colors: colors,
                      collapsedSummary: QuickStatsSummary(colors: colors),
                      child: QuickStatsPanel(colors: colors),
                    ),
                  // Display / stretch controls.
                  CollapsibleControlSection(
                    icon: LucideIcons.sliders,
                    title: 'Display',
                    expandedProvider: imagingDisplaySectionExpandedProvider,
                    colors: colors,
                    child: const StretchControls(compact: true),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
