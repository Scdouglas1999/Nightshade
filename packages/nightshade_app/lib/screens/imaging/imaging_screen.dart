import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../services/mount_command_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/preview_transform.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../../widgets/annotation_overlay.dart';
import '../settings/catalog_settings_screen.dart';
import 'imaging_science_state.dart';
import 'tabs/mount_tab.dart';
import 'widgets/stretch_controls.dart';
import 'widgets/science_hud.dart';
import '../../widgets/focuser_controls.dart';
import '../../widgets/filter_wheel_selector.dart';
import '../../widgets/tutorial_keys/imaging_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

/// Provider to check if annotation catalog is installed
final annotationCatalogInstalledProvider = FutureProvider<bool>((ref) async {
  final status = await CatalogManager.instance.getAnnotationCatalogStatus();
  return status.isInstalled;
});

/// Provider to track if the annotation catalog banner has been dismissed
final annotationBannerDismissedProvider = StateProvider<bool>((ref) => false);

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

  // Image view state
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;
  bool _showCrosshair = true;
  bool _showGrid = false;
  bool _showStarOverlay = false;

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

  /// Initialize the annotation service so it starts listening for new images
  void _initializeAnnotationService() {
    // Reading the provider creates the AnnotationService instance
    // which sets up the listener for currentImageProvider
    ref.read(annotationServiceProvider);
    debugPrint('[Imaging] AnnotationService initialized');
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

  // =========================================================================
  // CAPTURE ACTIONS
  // =========================================================================

  Future<void> _takeSnapshot() async {
    if (_isSingleCapture || _isLooping) return;

    setState(() => _isSingleCapture = true);

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
      }
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Capture failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isSingleCapture = false);
        ref.read(sessionStateProvider.notifier).setCapturing(false);
      }
    }
  }

  Future<void> _toggleLoop() async {
    if (_isSingleCapture) return;

    if (_isLooping) {
      // Stop looping
      setState(() => _isLooping = false);
      ref.read(imagingServiceProvider).cancelExposure();
      return;
    }

    setState(() => _isLooping = true);
    ref.read(sessionStateProvider.notifier).setCapturing(true);

    final settings = ref.read(exposureSettingsProvider);
    final imagingService = ref.read(imagingServiceProvider);

    try {
      await imagingService.startLoopCapture(
          settings: settings,
          targetName: ref.read(sessionStateProvider).targetName,
          onImageCaptured: (image) {
            if (mounted) {
              ref.read(currentImageProvider.notifier).state = image;
              ref.read(lastImageStatsProvider.notifier).state = image.stats;
              ref.read(sessionStateProvider.notifier).recordExposureComplete(
                    exposureTime: settings.exposureTime,
                    hfr: image.stats.hfr,
                  );
            }
          },
          onError: (error) {
            context.showErrorSnackBar('Capture error: $error');
          });
    } finally {
      if (mounted) {
        setState(() => _isLooping = false);
        ref.read(sessionStateProvider.notifier).setCapturing(false);
      }
    }
  }

  void _abortCapture() {
    ref.read(imagingServiceProvider).cancelExposure();
    setState(() {
      _isLooping = false;
      _isSingleCapture = false;
    });
    ref.read(sessionStateProvider.notifier).setCapturing(false);
  }

  // =========================================================================
  // ZOOM/PAN CONTROLS
  // =========================================================================

  void _zoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel * 1.25).clamp(0.25, 8.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel / 1.25).clamp(0.25, 8.0);
    });
  }

  void _fitToWindow() {
    setState(() {
      _zoomLevel = 1.0;
      _panOffset = Offset.zero;
    });
  }

  void _zoom1to1() {
    setState(() {
      _zoomLevel = 1.0;
      _panOffset = Offset.zero;
    });
  }

  void _panPreview(Offset delta) {
    setState(() {
      _panOffset += delta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final selectedPanel = ref.watch(selectedImagingPanelProvider);
    final annotationSettings = ref.watch(annotationSettingsProvider);
    final catalogInstalled = ref.watch(annotationCatalogInstalledProvider);
    final bannerDismissed = ref.watch(annotationBannerDismissedProvider);

    // Show banner if annotations are enabled but catalog is not installed
    final showBanner = (annotationSettings.valueOrNull?.enabled ?? false) &&
        catalogInstalled.valueOrNull == false &&
        !bannerDismissed;

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
            _AnnotationCatalogBanner(
              colors: colors,
              onDismiss: () => ref
                  .read(annotationBannerDismissedProvider.notifier)
                  .state = true,
              onSetup: () {
                // Show catalog settings dialog
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 800, maxHeight: 700),
                      child: const CatalogSettingsScreen(),
                    ),
                  ),
                ).then((_) {
                  // Refresh catalog status after dialog closes
                  ref.invalidate(annotationCatalogInstalledProvider);
                });
              },
            ),

          // Main content
          Expanded(
            child: Responsive.isMobile(context)
                ? _buildMobileLayout(colors, selectedPanel)
                : _buildDesktopLayout(colors, selectedPanel),
          ),
        ],
      ),
    );
  }

  /// Mobile layout: Tabs at bottom, full-width content
  Widget _buildMobileLayout(NightshadeColors colors, int selectedPanel) {
    return Column(
      children: [
        // Live preview area (compact on mobile)
        Expanded(
          flex: 4,
          child: _LivePreviewArea(
            key: ImagingTutorialKeys.previewArea,
            colors: colors,
            zoomLevel: _zoomLevel,
            panOffset: _panOffset,
            showCrosshair: _showCrosshair,
            showGrid: _showGrid,
            showStarOverlay: _showStarOverlay,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onFitToWindow: _fitToWindow,
            onZoom1to1: _zoom1to1,
            onAbortCapture: _abortCapture,
            onPanUpdate: _panPreview,
            onToggleCrosshair: () =>
                setState(() => _showCrosshair = !_showCrosshair),
            onToggleGrid: () => setState(() => _showGrid = !_showGrid),
            onToggleStarOverlay: () =>
                setState(() => _showStarOverlay = !_showStarOverlay),
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
                _PanelTabs(
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
                        _CapturePanel(colors: colors),
                        _CameraPanel(colors: colors),
                        _FocusPanel(
                            key: ImagingTutorialKeys.focusTab, colors: colors),
                        _GuidingPanel(colors: colors),
                        MountTab(key: ImagingTutorialKeys.mountTab),
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
  Widget _buildDesktopLayout(NightshadeColors colors, int selectedPanel) {
    return Row(
      children: [
        // Main content area (image + controls)
        Expanded(
          flex: 7,
          child: Column(
            children: [
              // Live preview area
              Expanded(
                flex: 6,
                child: _LivePreviewArea(
                  key: ImagingTutorialKeys.previewArea,
                  colors: colors,
                  zoomLevel: _zoomLevel,
                  panOffset: _panOffset,
                  showCrosshair: _showCrosshair,
                  showGrid: _showGrid,
                  showStarOverlay: _showStarOverlay,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onFitToWindow: _fitToWindow,
                  onZoom1to1: _zoom1to1,
                  onAbortCapture: _abortCapture,
                  onPanUpdate: _panPreview,
                  onToggleCrosshair: () =>
                      setState(() => _showCrosshair = !_showCrosshair),
                  onToggleGrid: () => setState(() => _showGrid = !_showGrid),
                  onToggleStarOverlay: () =>
                      setState(() => _showStarOverlay = !_showStarOverlay),
                ),
              ),

              // Bottom control panel
              Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    top: BorderSide(color: colors.border),
                  ),
                ),
                child: FadeTransition(
                  opacity: _fadeController,
                  child: _buildControlPanel(colors),
                ),
              ),
            ],
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
                _PanelTabs(
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
                        _CapturePanel(colors: colors),
                        _CameraPanel(colors: colors),
                        _FocusPanel(
                            key: ImagingTutorialKeys.focusTab, colors: colors),
                        _GuidingPanel(colors: colors),
                        MountTab(key: ImagingTutorialKeys.mountTab),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
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
                _ControlSection(
                  title: 'Capture',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: _BigActionButton(
                          key: ImagingTutorialKeys.snapshotBtn,
                          icon: _isSingleCapture
                              ? LucideIcons.loader2
                              : LucideIcons.camera,
                          label: _isSingleCapture ? 'Taking...' : 'Snapshot',
                          color: colors.primary,
                          isLoading: _isSingleCapture,
                          isEnabled: isConnected && !isCapturing,
                          onPressed: _takeSnapshot,
                          isMobile: true,
                        ),
                      ),
                      SizedBox(width: sectionSpacing),
                      Expanded(
                        child: _BigActionButton(
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
                _ControlSection(
                  title: 'Exposure',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: _EditableCompactInput(
                          key: ImagingTutorialKeys.exposureSlider,
                          label: 'Duration',
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
                        child: _EditableCompactInput(
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
                        child: _EditableCompactInput(
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
                _ControlSection(
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
                _ControlSection(
                  title: 'Display',
                  colors: colors,
                  child: const StretchControls(compact: true),
                ),
              ],
            ),
          );
        }

        // On larger screens, use horizontal layout
        return Padding(
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding, vertical: verticalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Capture controls
                _ControlSection(
                  title: 'Capture',
                  colors: colors,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BigActionButton(
                        key: ImagingTutorialKeys.snapshotBtn,
                        icon: _isSingleCapture
                            ? LucideIcons.loader2
                            : LucideIcons.camera,
                        label: _isSingleCapture ? 'Taking...' : 'Snapshot',
                        color: colors.primary,
                        isLoading: _isSingleCapture,
                        isEnabled: isConnected && !isCapturing,
                        onPressed: _takeSnapshot,
                      ),
                      const SizedBox(width: 12),
                      _BigActionButton(
                        key: ImagingTutorialKeys.loopBtn,
                        icon:
                            _isLooping ? LucideIcons.square : LucideIcons.video,
                        label: _isLooping ? 'Stop' : 'Loop',
                        color: _isLooping ? colors.error : colors.accent,
                        isEnabled: isConnected && !_isSingleCapture,
                        onPressed: _toggleLoop,
                      ),
                    ],
                  ),
                ),

                SizedBox(width: sectionSpacing),

                // Exposure settings
                _ControlSection(
                  title: 'Exposure',
                  colors: colors,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EditableCompactInput(
                        key: ImagingTutorialKeys.exposureSlider,
                        label: 'Duration',
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
                      _EditableCompactInput(
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
                      _EditableCompactInput(
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
                ),

                SizedBox(width: sectionSpacing),

                // Filter selection
                _ControlSection(
                  title: 'Filter',
                  colors: colors,
                  child: FilterWheelSelector(
                    key: ImagingTutorialKeys.filterSelector,
                    style: FilterSelectorStyle.buttons,
                    compact: isMobile,
                  ),
                ),

                SizedBox(width: sectionSpacing),

                // Stretch controls
                _ControlSection(
                  title: 'Display',
                  colors: colors,
                  child: const StretchControls(compact: true),
                ),

                if (!isMobile) ...[
                  SizedBox(width: sectionSpacing),
                  // Quick stats with live data (hide on mobile to save space)
                  _QuickStatsPanel(colors: colors),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LivePreviewArea extends ConsumerWidget {
  final NightshadeColors colors;
  final double zoomLevel;
  final Offset panOffset;
  final bool showCrosshair;
  final bool showGrid;
  final bool showStarOverlay;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToWindow;
  final VoidCallback onZoom1to1;
  final VoidCallback onAbortCapture;
  final void Function(Offset delta) onPanUpdate;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleStarOverlay;

  const _LivePreviewArea({
    super.key,
    required this.colors,
    required this.zoomLevel,
    required this.panOffset,
    required this.showCrosshair,
    required this.showGrid,
    required this.showStarOverlay,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToWindow,
    required this.onZoom1to1,
    required this.onAbortCapture,
    required this.onPanUpdate,
    required this.onToggleCrosshair,
    required this.onToggleGrid,
    required this.onToggleStarOverlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentImage = ref.watch(currentImageProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final lastStats = ref.watch(lastImageStatsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final starDetectionResult = ref.watch(starDetectionResultProvider);
    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    final scienceVizPrefs =
        ref.watch(scienceVisualizationPrefsProvider).valueOrNull ??
            const ScienceVisualizationPrefs();
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceOverlay = ref.watch(scienceOverlayStateProvider);
    final scienceSnapshot = ref.watch(currentScienceSnapshotProvider);
    final latestCalibration = scienceSnapshot.$1;
    final latestTransparency = scienceSnapshot.$2;
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    final sessionImages = ref.watch(sessionImagesProvider);
    final currentFrameImageId = _resolveCurrentFrameImageId(
      sessionImages: sessionImages,
      currentImage: currentImage,
    );

    final sessionPsfTiles = sessionId == null
        ? const <PsfFieldTileRow>[]
        : ref.watch(sessionPsfTilesProvider(sessionId)).valueOrNull ??
            const <PsfFieldTileRow>[];
    final psfTiles = _selectCurrentFramePsfTiles(
      sessionTiles: sessionPsfTiles,
      capturedImageId: currentFrameImageId,
    );
    final sessionResidualVectors = sessionId == null
        ? const <AstrometryResidualVectorRow>[]
        : ref.watch(sessionResidualVectorsProvider(sessionId)).valueOrNull ??
            const <AstrometryResidualVectorRow>[];
    final residualVectors = _selectCurrentFrameResidualVectors(
      sessionVectors: sessionResidualVectors,
      capturedImageId: currentFrameImageId,
    );
    final sessionTileMetrics = sessionId == null
        ? const <ScienceTileMetricRow>[]
        : ref.watch(sessionTileMetricsProvider(sessionId)).valueOrNull ??
            const <ScienceTileMetricRow>[];
    final currentFrameTileMetrics = _selectCurrentFrameTileMetrics(
      sessionTiles: sessionTileMetrics,
      capturedImageId: currentFrameImageId,
    );
    final uniformityTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.uniformity.dbValue,
        )
        .toList(growable: false);
    final clipHighTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.clipHigh.dbValue,
        )
        .toList(growable: false);
    final clipLowTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.clipLow.dbValue,
        )
        .toList(growable: false);
    final sessionMovingCandidates = sessionId == null
        ? const <MovingObjectCandidateRow>[]
        : ref
                .watch(sessionMovingObjectCandidatesProvider(sessionId))
                .valueOrNull ??
            const <MovingObjectCandidateRow>[];
    final movingCandidates = _selectCurrentFrameMovingCandidates(
      sessionCandidates: sessionMovingCandidates,
      capturedImageId: currentFrameImageId,
    );
    final currentFrameWcs = currentFrameImageId == null
        ? null
        : ref.watch(capturedImageWcsProvider(currentFrameImageId)).valueOrNull;

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isExposing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageOffset = currentImage != null
            ? computeImageOffset(
                viewportSize: viewportSize,
                imageSize: Size(currentImage.width.toDouble(),
                    currentImage.height.toDouble()),
                zoomLevel: zoomLevel,
                panOffset: panOffset,
              )
            : Offset.zero;
        final projectedMovingTracks = currentImage == null
            ? const <_ProjectedMovingTrack>[]
            : _projectMovingTracks(
                candidates: movingCandidates,
                wcs: currentFrameWcs,
                imageWidth: currentImage.width.toDouble(),
                imageHeight: currentImage.height.toDouble(),
              );

        return Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              if (signal.scrollDelta.dy > 0) {
                onZoomOut();
              } else if (signal.scrollDelta.dy < 0) {
                onZoomIn();
              }
            }
          },
          child: GestureDetector(
            onPanUpdate: (details) => onPanUpdate(details.delta),
            child: Container(
              color: const Color(0xFF08080C),
              child: Stack(
                children: [
                  // Image display or empty state
                  if (currentImage != null)
                    Positioned.fill(
                      child: _ImageDisplayWidget(
                        imageData: currentImage,
                        zoomLevel: zoomLevel,
                        panOffset: panOffset,
                      ),
                    )
                  else
                    // Star field background with empty-state message
                    Positioned.fill(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _StarFieldPainter(colors: colors),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.surface.withValues(alpha: 0.8),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.border),
                                  ),
                                  child: Icon(
                                    LucideIcons.camera,
                                    size: 48,
                                    color: colors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  isConnected
                                      ? 'No Image'
                                      : 'No Camera Connected',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isConnected
                                      ? 'Take a snapshot or start a capture loop'
                                      : 'Connect a camera in Equipment settings',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Crosshair overlay
                  if (showCrosshair && currentImage != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CrosshairOverlayPainter(
                          color: colors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                    ),

                  // Grid overlay
                  if (showGrid && currentImage != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GridOverlayPainter(
                          color: colors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),

                  // Star overlay
                  if (showStarOverlay &&
                      currentImage != null &&
                      starDetectionResult != null &&
                      starDetectionResult.stars.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StarOverlayPainter(
                          stars: starDetectionResult.stars,
                          color: colors.accent.withValues(alpha: 0.8),
                          zoomLevel: zoomLevel,
                          imageOffset: imageOffset,
                        ),
                      ),
                    ),

                  // Annotation overlay with fade effects
                  if (currentImage != null)
                    Positioned.fill(
                      child: _AnnotationOverlayWrapper(
                        zoomLevel: zoomLevel,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                        colors: colors,
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showPsfHeatmap &&
                      psfTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SciencePsfOverlayPainter(
                            tiles: psfTiles,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showResidualVectors &&
                      residualVectors.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ScienceResidualOverlayPainter(
                            vectors: residualVectors,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showUniformityMap &&
                      uniformityTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ScienceUniformityOverlayPainter(
                            tiles: uniformityTiles,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      (scienceOverlay.showClipHighMap ||
                          scienceOverlay.showClipLowMap))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ScienceClipOverlayPainter(
                            highTiles: scienceOverlay.showClipHighMap
                                ? clipHighTiles
                                : const <ScienceTileMetricRow>[],
                            lowTiles: scienceOverlay.showClipLowMap
                                ? clipLowTiles
                                : const <ScienceTileMetricRow>[],
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showMovingObjectTracks &&
                      projectedMovingTracks.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _ScienceMovingTrackOverlayPainter(
                              tracks: projectedMovingTracks,
                              imageOffset: imageOffset,
                              zoomLevel: zoomLevel,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Exposure progress overlay
                  if (isExposing)
                    Positioned.fill(
                      child: _ExposureProgressOverlay(
                        progress: exposureProgress,
                        colors: colors,
                      ),
                    ),

                  // Top overlay bar - responsive layout
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Use compact layout on narrow screens
                        final isNarrow = constraints.maxWidth < 500;
                        final horizontalPadding = isNarrow ? 8.0 : 16.0;

                        return Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: isNarrow
                              // Compact mobile layout - stack chips on top, controls below
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Info chips - wrap to prevent overflow
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _OverlayChip(
                                          icon: LucideIcons.maximize2,
                                          label: currentImage != null
                                              ? '${currentImage.width}×${currentImage.height}'
                                              : '--×--',
                                          colors: colors,
                                        ),
                                        _OverlayChip(
                                          icon: LucideIcons.search,
                                          label:
                                              '${(zoomLevel * 100).round()}%',
                                          colors: colors,
                                        ),
                                        if (scienceSettings.advancedModeEnabled)
                                          _OverlayChip(
                                            icon: LucideIcons.gauge,
                                            label: latestCalibration
                                                        ?.zeroPoint ==
                                                    null
                                                ? 'ZP --'
                                                : 'ZP ${latestCalibration!.zeroPoint!.toStringAsFixed(2)}',
                                            colors: colors,
                                          ),
                                        if (scienceSettings.advancedModeEnabled)
                                          _OverlayChip(
                                            icon: LucideIcons.cloud,
                                            label: latestTransparency == null
                                                ? 'Sky --'
                                                : 'Sky ${latestTransparency.qualityBucket}',
                                            colors: colors,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Control buttons - wrap to prevent overflow
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 2,
                                            runSpacing: 2,
                                            children: [
                                              _OverlayIconButton(
                                                icon: LucideIcons.crosshair,
                                                tooltip: 'Crosshair',
                                                colors: colors,
                                                isActive: showCrosshair,
                                                onTap: onToggleCrosshair,
                                              ),
                                              _OverlayIconButton(
                                                icon: LucideIcons.grid,
                                                tooltip: 'Grid',
                                                colors: colors,
                                                isActive: showGrid,
                                                onTap: onToggleGrid,
                                              ),
                                              _OverlayIconButton(
                                                icon: LucideIcons.sparkles,
                                                tooltip: 'Stars',
                                                colors: colors,
                                                isActive: showStarOverlay,
                                                onTap: onToggleStarOverlay,
                                              ),
                                              Consumer(
                                                builder: (context, ref, _) {
                                                  final isPanelVisible = ref.watch(
                                                      annotationPanelVisibleProvider);
                                                  return _OverlayIconButton(
                                                    icon: LucideIcons.list,
                                                    tooltip: 'Objects',
                                                    colors: colors,
                                                    isActive: isPanelVisible,
                                                    onTap: () => ref
                                                        .read(
                                                            annotationPanelVisibleProvider
                                                                .notifier)
                                                        .state = !isPanelVisible,
                                                  );
                                                },
                                              ),
                                              if (scienceSettings
                                                  .advancedModeEnabled)
                                                _OverlayIconButton(
                                                  icon:
                                                      LucideIcons.flaskConical,
                                                  tooltip: scienceMode
                                                          .scienceHudVisible
                                                      ? 'Hide science HUD'
                                                      : 'Show science HUD',
                                                  colors: colors,
                                                  isActive: scienceMode
                                                      .scienceHudVisible,
                                                  onTap: () => ref
                                                      .read(
                                                          scienceModeStateProvider
                                                              .notifier)
                                                      .state = scienceMode.copyWith(
                                                    scienceHudVisible:
                                                        !scienceMode
                                                            .scienceHudVisible,
                                                  ),
                                                ),
                                              Row(
                                                key: ImagingTutorialKeys
                                                    .zoomControls,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _OverlayIconButton(
                                                    icon: LucideIcons.zoomIn,
                                                    tooltip: 'Zoom in',
                                                    colors: colors,
                                                    onTap: onZoomIn,
                                                  ),
                                                  _OverlayIconButton(
                                                    icon: LucideIcons.zoomOut,
                                                    tooltip: 'Zoom out',
                                                    colors: colors,
                                                    onTap: onZoomOut,
                                                  ),
                                                  _OverlayIconButton(
                                                    icon: LucideIcons.maximize,
                                                    tooltip: 'Fit',
                                                    colors: colors,
                                                    onTap: onFitToWindow,
                                                  ),
                                                ],
                                              ),
                                              if (exposureProgress.percent >
                                                      0 &&
                                                  exposureProgress.percent <
                                                      1.0)
                                                _OverlayIconButton(
                                                  key: ImagingTutorialKeys
                                                      .abortBtn,
                                                  icon: LucideIcons.x,
                                                  tooltip: 'Abort',
                                                  colors: colors,
                                                  onTap: onAbortCapture,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              // Standard desktop layout
                              : Row(
                                  children: [
                                    _OverlayChip(
                                      icon: LucideIcons.maximize2,
                                      label: currentImage != null
                                          ? '${currentImage.width} × ${currentImage.height}'
                                          : '--- × ---',
                                      colors: colors,
                                    ),
                                    const SizedBox(width: 8),
                                    _OverlayChip(
                                      icon: LucideIcons.grid,
                                      label:
                                          'Binning ${exposureSettings.binning}',
                                      colors: colors,
                                    ),
                                    const SizedBox(width: 8),
                                    _OverlayChip(
                                      icon: LucideIcons.search,
                                      label: '${(zoomLevel * 100).round()}%',
                                      colors: colors,
                                    ),
                                    if (scienceSettings
                                        .advancedModeEnabled) ...[
                                      const SizedBox(width: 8),
                                      _OverlayChip(
                                        icon: LucideIcons.gauge,
                                        label: latestCalibration?.zeroPoint ==
                                                null
                                            ? 'ZP --'
                                            : 'ZP ${latestCalibration!.zeroPoint!.toStringAsFixed(2)}',
                                        colors: colors,
                                      ),
                                      const SizedBox(width: 8),
                                      _OverlayChip(
                                        icon: LucideIcons.cloud,
                                        label: latestTransparency == null
                                            ? 'Sky --'
                                            : 'Sky ${latestTransparency.qualityBucket}',
                                        colors: colors,
                                      ),
                                    ],
                                    const Spacer(),
                                    _OverlayIconButton(
                                      icon: LucideIcons.crosshair,
                                      tooltip: 'Toggle crosshair',
                                      colors: colors,
                                      isActive: showCrosshair,
                                      onTap: onToggleCrosshair,
                                    ),
                                    _OverlayIconButton(
                                      icon: LucideIcons.grid,
                                      tooltip: 'Toggle grid',
                                      colors: colors,
                                      isActive: showGrid,
                                      onTap: onToggleGrid,
                                    ),
                                    _OverlayIconButton(
                                      icon: LucideIcons.sparkles,
                                      tooltip: 'Toggle star overlay',
                                      colors: colors,
                                      isActive: showStarOverlay,
                                      onTap: onToggleStarOverlay,
                                    ),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final isPanelVisible = ref.watch(
                                            annotationPanelVisibleProvider);
                                        final annotation = ref
                                            .watch(currentAnnotationProvider);
                                        final objectCount =
                                            annotation?.objects.length ?? 0;
                                        return _OverlayIconButton(
                                          icon: LucideIcons.list,
                                          tooltip:
                                              'Objects panel${objectCount > 0 ? ' ($objectCount)' : ''}',
                                          colors: colors,
                                          isActive: isPanelVisible,
                                          onTap: () => ref
                                              .read(
                                                  annotationPanelVisibleProvider
                                                      .notifier)
                                              .state = !isPanelVisible,
                                        );
                                      },
                                    ),
                                    if (scienceSettings.advancedModeEnabled)
                                      _OverlayIconButton(
                                        icon: LucideIcons.flaskConical,
                                        tooltip: scienceMode.scienceHudVisible
                                            ? 'Hide science HUD'
                                            : 'Show science HUD',
                                        colors: colors,
                                        isActive: scienceMode.scienceHudVisible,
                                        onTap: () => ref
                                            .read(scienceModeStateProvider
                                                .notifier)
                                            .state = scienceMode.copyWith(
                                          scienceHudVisible:
                                              !scienceMode.scienceHudVisible,
                                        ),
                                      ),
                                    Row(
                                      key: ImagingTutorialKeys.zoomControls,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _OverlayIconButton(
                                          icon: LucideIcons.zoomIn,
                                          tooltip: 'Zoom in',
                                          colors: colors,
                                          onTap: onZoomIn,
                                        ),
                                        _OverlayIconButton(
                                          icon: LucideIcons.zoomOut,
                                          tooltip: 'Zoom out',
                                          colors: colors,
                                          onTap: onZoomOut,
                                        ),
                                        _OverlayIconButton(
                                          icon: LucideIcons.minimize2,
                                          tooltip: '1:1 zoom',
                                          colors: colors,
                                          onTap: onZoom1to1,
                                        ),
                                        _OverlayIconButton(
                                          icon: LucideIcons.maximize,
                                          tooltip: 'Fit to window',
                                          colors: colors,
                                          onTap: onFitToWindow,
                                        ),
                                      ],
                                    ),
                                    if (exposureProgress.percent > 0 &&
                                        exposureProgress.percent < 1.0)
                                      _OverlayIconButton(
                                        key: ImagingTutorialKeys.abortBtn,
                                        icon: LucideIcons.x,
                                        tooltip: 'Abort capture',
                                        colors: colors,
                                        onTap: onAbortCapture,
                                      ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),

                  // Bottom histogram overlay
                  if (scienceSettings.advancedModeEnabled &&
                      scienceMode.scienceHudVisible)
                    Positioned(
                      top: 56,
                      right: 16,
                      child: ScienceHudPanel(colors: colors),
                    ),

                  // Bottom histogram overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: _HistogramWidget(
                      key: ImagingTutorialKeys.histogram,
                      colors: colors,
                      histogram: currentImage?.histogram,
                    ),
                  ),

                  // Right side stats
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _ImageStatsOverlay(
                      key: ImagingTutorialKeys.statsPanel,
                      colors: colors,
                      stats: lastStats,
                    ),
                  ),

                  // Annotation status indicator (top left, below the overlay bar)
                  if (currentImage != null)
                    Positioned(
                      top: 48,
                      left: 16,
                      child: _AnnotationStatusIndicator(colors: colors),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<PsfFieldTileRow> _selectCurrentFramePsfTiles({
    required List<PsfFieldTileRow> sessionTiles,
    required int? capturedImageId,
  }) {
    if (sessionTiles.isEmpty) {
      return const <PsfFieldTileRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionTiles
          .where((tile) => tile.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionTiles
        .where((tile) => tile.capturedImageId != null)
        .map((tile) => tile.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == latest)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == id)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionTiles;
    }
    return sessionTiles
        .where((tile) => tile.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  int? _resolveCurrentFrameImageId({
    required List<CapturedImage> sessionImages,
    required CapturedImageData? currentImage,
  }) {
    final filePath = currentImage?.filePath;
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    for (final image in sessionImages) {
      if (image.filePath == filePath) {
        final parsed = int.tryParse(image.id);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  List<AstrometryResidualVectorRow> _selectCurrentFrameResidualVectors({
    required List<AstrometryResidualVectorRow> sessionVectors,
    required int? capturedImageId,
  }) {
    if (sessionVectors.isEmpty) {
      return const <AstrometryResidualVectorRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionVectors
          .where((vector) => vector.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionVectors
        .where((vector) => vector.capturedImageId != null)
        .map((vector) => vector.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionVectors
          .where((vector) => vector.capturedImageId == latest)
          .map((vector) => vector.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionVectors
          .where((vector) => vector.capturedImageId == id)
          .map((vector) => vector.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionVectors;
    }
    return sessionVectors
        .where((vector) => vector.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  List<ScienceTileMetricRow> _selectCurrentFrameTileMetrics({
    required List<ScienceTileMetricRow> sessionTiles,
    required int? capturedImageId,
  }) {
    if (sessionTiles.isEmpty) {
      return const <ScienceTileMetricRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionTiles
          .where((tile) => tile.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionTiles
        .where((tile) => tile.capturedImageId != null)
        .map((tile) => tile.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == latest)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == id)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionTiles;
    }
    return sessionTiles
        .where((tile) => tile.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  List<MovingObjectCandidateRow> _selectCurrentFrameMovingCandidates({
    required List<MovingObjectCandidateRow> sessionCandidates,
    required int? capturedImageId,
  }) {
    if (sessionCandidates.isEmpty) {
      return const <MovingObjectCandidateRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionCandidates
          .where((candidate) => candidate.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionCandidates
        .where((candidate) => candidate.capturedImageId != null)
        .map((candidate) => candidate.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionCandidates
          .where((candidate) => candidate.capturedImageId == latest)
          .map((candidate) => candidate.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionCandidates
          .where((candidate) => candidate.capturedImageId == id)
          .map((candidate) => candidate.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionCandidates;
    }
    return sessionCandidates
        .where((candidate) => candidate.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  List<_ProjectedMovingTrack> _projectMovingTracks({
    required List<MovingObjectCandidateRow> candidates,
    required CapturedImageWcsData? wcs,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (candidates.isEmpty || wcs == null) {
      return const <_ProjectedMovingTrack>[];
    }
    final solvedRaHours = wcs.solvedRaHours;
    final solvedDecDegrees = wcs.solvedDecDegrees;
    final solvedRotation = wcs.solvedRotationDegrees;
    final solvedScale = wcs.solvedPixelScaleArcsecPerPixel;
    if (!wcs.isPlateSolved ||
        solvedRaHours == null ||
        solvedDecDegrees == null ||
        solvedRotation == null ||
        solvedScale == null ||
        solvedScale <= 0) {
      return const <_ProjectedMovingTrack>[];
    }

    final tracks = <_ProjectedMovingTrack>[];
    final centerRaDeg = solvedRaHours * 15.0;
    for (final candidate in candidates.take(200)) {
      final projected = _skyToPixel(
        raDegrees: candidate.raDegrees,
        decDegrees: candidate.decDegrees,
        centerRaDegrees: centerRaDeg,
        centerDecDegrees: solvedDecDegrees,
        rotationDegrees: solvedRotation,
        pixelScaleArcsecPerPixel: solvedScale,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (projected == null) {
        continue;
      }
      tracks.add(
        _ProjectedMovingTrack(
          imageX: projected.dx,
          imageY: projected.dy,
          positionAngleDegrees: candidate.positionAngleDegrees,
          motionArcsecPerMinute: candidate.motionArcsecPerMinute,
          confidence: candidate.confidence,
        ),
      );
    }
    return tracks;
  }

  Offset? _skyToPixel({
    required double raDegrees,
    required double decDegrees,
    required double centerRaDegrees,
    required double centerDecDegrees,
    required double rotationDegrees,
    required double pixelScaleArcsecPerPixel,
    required double imageWidth,
    required double imageHeight,
  }) {
    final raRad = raDegrees * math.pi / 180.0;
    final decRad = decDegrees * math.pi / 180.0;
    final centerRaRad = centerRaDegrees * math.pi / 180.0;
    final centerDecRad = centerDecDegrees * math.pi / 180.0;

    var dRa = raRad - centerRaRad;
    while (dRa > math.pi) {
      dRa -= 2 * math.pi;
    }
    while (dRa < -math.pi) {
      dRa += 2 * math.pi;
    }

    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCenterDec = math.cos(centerDecRad);
    final sinCenterDec = math.sin(centerDecRad);
    final denom = sinCenterDec * sinDec + cosCenterDec * cosDec * math.cos(dRa);
    if (denom <= 0) {
      return null;
    }

    final xi = cosDec * math.sin(dRa) / denom;
    final eta =
        (cosCenterDec * sinDec - sinCenterDec * cosDec * math.cos(dRa)) / denom;
    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;
    final rot = rotationDegrees * math.pi / 180.0;
    final xr = xiDeg * math.cos(rot) - etaDeg * math.sin(rot);
    final yr = xiDeg * math.sin(rot) + etaDeg * math.cos(rot);
    final x = xr * 3600.0 / pixelScaleArcsecPerPixel + imageWidth / 2.0;
    final y = imageHeight / 2.0 - yr * 3600.0 / pixelScaleArcsecPerPixel;
    if (!x.isFinite || !y.isFinite) {
      return null;
    }
    return Offset(x, y);
  }
}

class _StarFieldPainter extends CustomPainter {
  final NightshadeColors colors;

  _StarFieldPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint();

    for (var i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.25 + 0.05;
      final radius = random.nextDouble() * 1.2 + 0.3;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _OverlayChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final bool isActive;
  final VoidCallback? onTap;

  const _OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.isActive = false,
    this.onTap,
  });

  @override
  State<_OverlayIconButton> createState() => _OverlayIconButtonState();
}

class _OverlayIconButtonState extends State<_OverlayIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return NightshadeTooltip(
      message: widget.tooltip,
      position: NightshadeTooltipPosition.bottom,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          // Ensure minimum touch target of 44x44 for accessibility
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? widget.colors.primary.withValues(alpha: 0.3)
                    : _isHovered
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: widget.isActive
                    ? Border.all(
                        color: widget.colors.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: widget.isActive
                    ? widget.colors.primary
                    : _isHovered
                        ? Colors.white
                        : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistogramWidget extends StatelessWidget {
  final NightshadeColors colors;
  final List<int>? histogram;

  const _HistogramWidget({
    super.key,
    required this.colors,
    this.histogram,
  });

  @override
  Widget build(BuildContext context) {
    // Use responsive width - smaller on narrow screens
    final screenWidth = MediaQuery.of(context).size.width;
    final histogramWidth = screenWidth < 400 ? 140.0 : 200.0;

    return Container(
      width: histogramWidth,
      height: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Histogram',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: histogram != null && histogram!.isNotEmpty
                ? CustomPaint(
                    painter: _HistogramPainter(
                      histogram: histogram!,
                      color: colors.primary,
                    ),
                    size: Size.infinite,
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'No data',
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.textMuted,
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

class _HistogramPainter extends CustomPainter {
  final List<int> histogram;
  final Color color;

  _HistogramPainter({required this.histogram, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (histogram.isEmpty) return;

    final maxVal = histogram.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final barWidth = size.width / histogram.length;

    for (int i = 0; i < histogram.length; i++) {
      final barHeight = (histogram[i] / maxVal) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) {
    return histogram != oldDelegate.histogram;
  }
}

class _ImageStatsOverlay extends StatelessWidget {
  final NightshadeColors colors;
  final ImageStats? stats;

  const _ImageStatsOverlay({
    super.key,
    required this.colors,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _StatLine(
            label: 'HFR',
            value: stats?.hfr?.toStringAsFixed(2) ?? '---',
            colors: colors,
          ),
          _StatLine(
            label: 'Stars',
            value: stats?.starCount?.toString() ?? '---',
            colors: colors,
          ),
          _StatLine(
            label: 'Median',
            value: stats?.median?.toStringAsFixed(0) ?? '---',
            colors: colors,
          ),
          _StatLine(
            label: 'Mean',
            value: stats?.mean?.toStringAsFixed(0) ?? '---',
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatLine({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NightshadeColors colors;

  const _PanelTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.colors,
  });

  static const _tabs = [
    (LucideIcons.camera, 'Capture'),
    (LucideIcons.aperture, 'Camera'),
    (LucideIcons.focus, 'Focus'),
    (LucideIcons.crosshair, 'Guiding'),
    (LucideIcons.compass, 'Mount'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final (icon, label) = entry.value;
          final isSelected = index == selectedIndex;

          return Expanded(
            child: _PanelTab(
              icon: icon,
              label: label,
              isSelected: isSelected,
              onTap: () => onSelected(index),
              colors: colors,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PanelTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _PanelTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<_PanelTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.surface
                : _isHovered
                    ? widget.colors.surface.withValues(alpha: 0.5)
                    : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.isSelected
                    ? widget.colors.primary
                    : Colors.transparent,
                width: widget.isSelected ? 2.5 : 0,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
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

class _ControlSection extends StatelessWidget {
  final String title;
  final Widget child;
  final NightshadeColors colors;

  const _ControlSection({
    required this.title,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _BigActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isEnabled;
  final bool isLoading;
  final bool isMobile;

  const _BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.isEnabled = true,
    this.isLoading = false,
    this.isMobile = false,
  });

  @override
  State<_BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<_BigActionButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.isEnabled ? widget.color : widget.color.withValues(alpha: 0.4);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:
            widget.isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp:
            widget.isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            widget.isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: () {
            final scale = _isPressed && widget.isEnabled ? 0.95 : 1.0;
            return Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0);
          }(),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isMobile ? 12 : 20,
            vertical: widget.isMobile ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isHovered && widget.isEnabled
                ? [
                    BoxShadow(
                      color: effectiveColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.isLoading
                  ? AnimatedBuilder(
                      animation: _loadingController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _loadingController.value * 2 * math.pi,
                          child: Icon(
                            LucideIcons.loader2,
                            size: 24,
                            color: Colors.white.withValues(
                                alpha: widget.isEnabled ? 1.0 : 0.5),
                          ),
                        );
                      },
                    )
                  : Icon(
                      widget.icon,
                      size: widget.isMobile ? 20 : 24,
                      color: Colors.white
                          .withValues(alpha: widget.isEnabled ? 1.0 : 0.5),
                    ),
              SizedBox(height: widget.isMobile ? 4 : 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white
                        .withValues(alpha: widget.isEnabled ? 1.0 : 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableCompactInput extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;
  final bool isMobile;

  const _EditableCompactInput({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
    this.isMobile = false,
  });

  @override
  State<_EditableCompactInput> createState() => _EditableCompactInputState();
}

class _EditableCompactInputState extends State<_EditableCompactInput> {
  late TextEditingController _controller;
  bool _isEditing = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _commitValue();
      }
    });
  }

  @override
  void didUpdateWidget(_EditableCompactInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitValue() {
    setState(() => _isEditing = false);
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            color: widget.colors.textMuted,
          ),
        ),
        SizedBox(height: widget.isMobile ? 3 : 4),
        GestureDetector(
          onTap: () {
            setState(() => _isEditing = true);
            _focusNode.requestFocus();
            _controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controller.text.length,
            );
          },
          child: Container(
            width: widget.isMobile ? 70 : 90,
            constraints: BoxConstraints(
              minHeight: widget.isMobile ? 32 : 34,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isMobile ? 8 : 10,
              vertical: widget.isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    _isEditing ? widget.colors.primary : widget.colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _isEditing
                      ? TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: TextStyle(
                            fontSize: widget.isMobile ? 12 : 13,
                            fontWeight: FontWeight.w500,
                            color: widget.colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _commitValue(),
                        )
                      : Text(
                          widget.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                ),
                if (widget.suffix != null)
                  Text(
                    widget.suffix!,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// IMAGE DISPLAY AND OVERLAYS
// =============================================================================

class _ImageDisplayWidget extends ConsumerStatefulWidget {
  final CapturedImageData imageData;
  final double zoomLevel;
  final Offset panOffset;

  const _ImageDisplayWidget({
    required this.imageData,
    required this.zoomLevel,
    required this.panOffset,
  });

  @override
  ConsumerState<_ImageDisplayWidget> createState() =>
      _ImageDisplayWidgetState();
}

class _ImageDisplayWidgetState extends ConsumerState<_ImageDisplayWidget> {
  ui.Image? _decodedImage;
  bool _isDecoding = false;
  Uint8List? _lastDecodedPixels;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(_ImageDisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageData != oldWidget.imageData) {
      _decodeImage();
    }
  }

  Future<void> _decodeImage({Uint8List? stretchedData}) async {
    if (_isDecoding) return;
    _isDecoding = true;

    try {
      final width = widget.imageData.width;
      final height = widget.imageData.height;
      // Use stretched data if available, otherwise fall back to display data.
      // Both are always RGBA (4 bytes per pixel, alpha=255) — the conversion
      // is done in Rust (for display_data) or at the provider boundary (for
      // stretched data), so no per-pixel loop is needed here.
      final Uint8List rgbaBytes = stretchedData ?? widget.imageData.displayData;

      // Skip re-decoding if pixels haven't changed
      if (_lastDecodedPixels != null && _lastDecodedPixels == rgbaBytes) {
        _isDecoding = false;
        return;
      }
      _lastDecodedPixels = rgbaBytes;

      ui.decodeImageFromPixels(
        rgbaBytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (image) {
          if (mounted) {
            setState(() {
              _decodedImage = image;
              _isDecoding = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[Imaging] Error decoding image: $e');
      _isDecoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the stretched image provider for auto-stretch updates
    final stretchedImageAsync = ref.watch(stretchedImageProvider);

    // When stretched data changes, trigger re-decode
    stretchedImageAsync.whenData((stretchedData) {
      if (stretchedData != null && stretchedData != _lastDecodedPixels) {
        // Defer the decode to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _decodeImage(stretchedData: stretchedData);
          }
        });
      }
    });

    if (_decodedImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRect(
      child: Center(
        child: Transform.translate(
          offset: widget.panOffset,
          child: Transform.scale(
            scale: widget.zoomLevel,
            alignment: Alignment.center,
            child: CustomPaint(
              painter: _DecodedImagePainter(
                image: _decodedImage!,
              ),
              size: Size(
                _decodedImage!.width.toDouble(),
                _decodedImage!.height.toDouble(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DecodedImagePainter extends CustomPainter {
  final ui.Image image;

  _DecodedImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_DecodedImagePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}

class _ExposureProgressOverlay extends StatelessWidget {
  final ExposureProgress progress;
  final NightshadeColors colors;

  const _ExposureProgressOverlay({
    required this.progress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final statusText =
        progress.isDownloading ? 'Downloading...' : 'Exposing...';
    final progressValue = (progress.percent / 100.0).clamp(0.0, 1.0);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                children: [
                  CircularProgressIndicator(
                    value: progressValue,
                    strokeWidth: 4,
                    backgroundColor: colors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                  Center(
                    child: Text(
                      '${progress.percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              statusText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            if (!progress.isDownloading)
              Text(
                '${progress.remaining.toStringAsFixed(1)}s remaining',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            if (progress.totalFrames != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Frame ${progress.frameNumber} of ${progress.totalFrames}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CrosshairOverlayPainter extends CustomPainter {
  final Color color;

  _CrosshairOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Horizontal line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      paint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      paint,
    );

    // Center circle
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(centerX, centerY), 20, paint);
    canvas.drawCircle(Offset(centerX, centerY), 40, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GridOverlayPainter extends CustomPainter {
  final Color color;

  _GridOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const gridSize = 50.0;

    // Vertical lines
    for (double x = gridSize; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = gridSize; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarOverlayPainter extends CustomPainter {
  final List<DetectedStar> stars;
  final Color color;
  final double zoomLevel;
  final Offset imageOffset;

  _StarOverlayPainter({
    required this.stars,
    required this.color,
    required this.zoomLevel,
    required this.imageOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    for (final star in stars) {
      final x = star.x * zoomLevel + imageOffset.dx;
      final y = star.y * zoomLevel + imageOffset.dy;

      // Skip stars outside the visible area
      if (x < -50 || x > size.width + 50 || y < -50 || y > size.height + 50) {
        continue;
      }

      final position = Offset(x, y);

      // Draw circle around star (radius based on HFR)
      final radius = (star.hfr * zoomLevel).clamp(3.0, 30.0);
      canvas.drawCircle(position, radius, fillPaint);
      canvas.drawCircle(position, radius, paint);

      // Draw crosshair
      const crosshairSize = 3.0;
      canvas.drawLine(
        Offset(x - crosshairSize, y),
        Offset(x + crosshairSize, y),
        paint,
      );
      canvas.drawLine(
        Offset(x, y - crosshairSize),
        Offset(x, y + crosshairSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarOverlayPainter oldDelegate) {
    return stars != oldDelegate.stars ||
        color != oldDelegate.color ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageOffset != oldDelegate.imageOffset;
  }
}

class _SciencePsfOverlayPainter extends CustomPainter {
  final List<PsfFieldTileRow> tiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;

  _SciencePsfOverlayPainter({
    required this.tiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) {
      return;
    }

    var maxRow = 0;
    var maxCol = 0;
    var maxFwhm = 0.0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
      if (tile.starCount > 0 && tile.medianFwhm > maxFwhm) {
        maxFwhm = tile.medianFwhm;
      }
    }

    final validFwhm = tiles
        .where((tile) => tile.starCount > 0 && tile.medianFwhm > 0)
        .map((tile) => tile.medianFwhm)
        .toList(growable: false)
      ..sort();
    final low = validFwhm.isEmpty ? 0.0 : _percentile(validFwhm, 0.05);
    final high = validFwhm.isEmpty
        ? maxFwhm
        : _percentile(validFwhm, 0.95).clamp(low + 1e-6, double.infinity);

    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final tile in tiles) {
      final norm = tile.starCount <= 0 || high <= low
          ? 0.0
          : ((tile.medianFwhm - low) / (high - low)).clamp(0.0, 1.0);
      final fill = Paint()
        ..color = (tile.starCount <= 0
                ? const Color(0xFF4A5568)
                : Color.lerp(
                    const Color(0xFF0B6E4F),
                    const Color(0xFFC0392B),
                    norm,
                  )!)
            .withValues(alpha: tile.starCount > 0 ? 0.28 : 0.12)
        ..style = PaintingStyle.fill;

      final left = (tile.tileCol * tileW) * zoomLevel + imageOffset.dx;
      final top = (tile.tileRow * tileH) * zoomLevel + imageOffset.dy;
      final rect = Rect.fromLTWH(
        left,
        top,
        tileW * zoomLevel,
        tileH * zoomLevel,
      );

      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SciencePsfOverlayPainter oldDelegate) {
    return tiles != oldDelegate.tiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight;
  }

  double _percentile(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1.0 - t) + sortedValues[hi] * t;
  }
}

class _ScienceResidualOverlayPainter extends CustomPainter {
  final List<AstrometryResidualVectorRow> vectors;
  final Offset imageOffset;
  final double zoomLevel;

  _ScienceResidualOverlayPainter({
    required this.vectors,
    required this.imageOffset,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vectors.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..color = const Color(0xFFF1C40F).withValues(alpha: 0.75)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final headPaint = Paint()
      ..color = const Color(0xFFF39C12).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final magnitudes = vectors
        .map((vector) => vector.magnitudeArcsec)
        .where((value) => value.isFinite && value > 0)
        .toList(growable: false)
      ..sort();
    final p95Magnitude = magnitudes.isEmpty
        ? 1.0
        : magnitudes[((magnitudes.length - 1) * 0.95).floor()];
    final scaleArcsecToPixels = p95Magnitude <= 0
        ? 6.0
        : (22.0 / p95Magnitude).clamp(2.0, 40.0).toDouble();

    final maxVectors = math.min(350, vectors.length);
    for (var i = 0; i < maxVectors; i++) {
      final vector = vectors[i];
      final x1 = vector.x * zoomLevel + imageOffset.dx;
      final y1 = vector.y * zoomLevel + imageOffset.dy;
      final dx = vector.dxArcsec * zoomLevel * scaleArcsecToPixels;
      final dy = vector.dyArcsec * zoomLevel * scaleArcsecToPixels;
      final x2 = x1 + dx;
      final y2 = y1 + dy;

      if (x1 < -100 ||
          x1 > size.width + 100 ||
          y1 < -100 ||
          y1 > size.height + 100) {
        continue;
      }

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      canvas.drawCircle(Offset(x2, y2), 1.6, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScienceResidualOverlayPainter oldDelegate) {
    return vectors != oldDelegate.vectors ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel;
  }
}

class _ScienceUniformityOverlayPainter extends CustomPainter {
  final List<ScienceTileMetricRow> tiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;
  final double opacity;

  _ScienceUniformityOverlayPainter({
    required this.tiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) {
      return;
    }

    var maxRow = 0;
    var maxCol = 0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }

    final values = tiles
        .map((tile) => tile.value)
        .where((value) => value.isFinite && value >= 0.0)
        .toList(growable: false)
      ..sort();
    final low = values.isEmpty ? 0.0 : _percentile(values, 0.05);
    final high = values.isEmpty
        ? 1.0
        : _percentile(values, 0.95).clamp(low + 1e-6, double.infinity);

    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final tile in tiles) {
      final norm = high <= low
          ? 0.0
          : ((tile.value - low) / (high - low)).clamp(0.0, 1.0);
      final fill = Paint()
        ..color = Color.lerp(
          const Color(0xFF0B3D91),
          const Color(0xFFFF8C42),
          norm,
        )!
            .withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final left = (tile.tileCol * tileW) * zoomLevel + imageOffset.dx;
      final top = (tile.tileRow * tileH) * zoomLevel + imageOffset.dy;
      final rect = Rect.fromLTWH(
        left,
        top,
        tileW * zoomLevel,
        tileH * zoomLevel,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScienceUniformityOverlayPainter oldDelegate) {
    return tiles != oldDelegate.tiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        opacity != oldDelegate.opacity;
  }

  double _percentile(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1.0 - t) + sortedValues[hi] * t;
  }
}

class _ScienceClipOverlayPainter extends CustomPainter {
  final List<ScienceTileMetricRow> highTiles;
  final List<ScienceTileMetricRow> lowTiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;
  final double opacity;

  _ScienceClipOverlayPainter({
    required this.highTiles,
    required this.lowTiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (highTiles.isEmpty && lowTiles.isEmpty) {
      return;
    }
    var maxRow = 0;
    var maxCol = 0;
    for (final tile in highTiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    for (final tile in lowTiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final highMap = <(int, int), double>{};
    final lowMap = <(int, int), double>{};
    for (final tile in highTiles) {
      highMap[(tile.tileRow, tile.tileCol)] = tile.value;
    }
    for (final tile in lowTiles) {
      lowMap[(tile.tileRow, tile.tileCol)] = tile.value;
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final high = (highMap[(row, col)] ?? 0.0).clamp(0.0, 100.0);
        final low = (lowMap[(row, col)] ?? 0.0).clamp(0.0, 100.0);
        if (high <= 0 && low <= 0) {
          continue;
        }
        final alpha = (math.max(high, low) / 100.0).clamp(0.08, 1.0) * opacity;
        final fillColor = Color.lerp(
          const Color(0xFF3B82F6), // low clipping: blue
          const Color(0xFFEF4444), // high clipping: red
          high / math.max(1.0, high + low),
        )!
            .withValues(alpha: alpha);
        final fill = Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill;

        final left = (col * tileW) * zoomLevel + imageOffset.dx;
        final top = (row * tileH) * zoomLevel + imageOffset.dy;
        final rect = Rect.fromLTWH(
          left,
          top,
          tileW * zoomLevel,
          tileH * zoomLevel,
        );
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScienceClipOverlayPainter oldDelegate) {
    return highTiles != oldDelegate.highTiles ||
        lowTiles != oldDelegate.lowTiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        opacity != oldDelegate.opacity;
  }
}

class _ScienceMovingTrackOverlayPainter extends CustomPainter {
  final List<_ProjectedMovingTrack> tracks;
  final Offset imageOffset;
  final double zoomLevel;

  _ScienceMovingTrackOverlayPainter({
    required this.tracks,
    required this.imageOffset,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tracks.isEmpty) {
      return;
    }

    for (final track in tracks) {
      final x = track.imageX * zoomLevel + imageOffset.dx;
      final y = track.imageY * zoomLevel + imageOffset.dy;
      if (x < -120 ||
          x > size.width + 120 ||
          y < -120 ||
          y > size.height + 120) {
        continue;
      }

      final confidenceColor = Color.lerp(
        const Color(0xFFF59E0B),
        const Color(0xFF22C55E),
        track.confidence.clamp(0.0, 1.0),
      )!;

      final trailLength =
          (8.0 + track.motionArcsecPerMinute * 1.8).clamp(8.0, 44.0).toDouble();
      final paRad = track.positionAngleDegrees * math.pi / 180.0;
      final dx = math.sin(paRad) * trailLength;
      final dy = -math.cos(paRad) * trailLength;
      final start = Offset(x - dx * 0.45, y - dy * 0.45);
      final end = Offset(x + dx * 0.55, y + dy * 0.55);

      final linePaint = Paint()
        ..color = confidenceColor.withValues(alpha: 0.86)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final pointPaint = Paint()
        ..color = confidenceColor.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;

      canvas.drawLine(start, end, linePaint);
      canvas.drawCircle(end, 2.2, pointPaint);
      canvas.drawCircle(
        Offset(x, y),
        3.6,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(x, y),
        2.0,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScienceMovingTrackOverlayPainter oldDelegate) {
    return tracks != oldDelegate.tracks ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel;
  }
}

class _ProjectedMovingTrack {
  final double imageX;
  final double imageY;
  final double positionAngleDegrees;
  final double motionArcsecPerMinute;
  final double confidence;

  const _ProjectedMovingTrack({
    required this.imageX,
    required this.imageY,
    required this.positionAngleDegrees,
    required this.motionArcsecPerMinute,
    required this.confidence,
  });
}

class _QuickStatsPanel extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsPanel({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);

    // Format temperature
    String tempValue = '---';
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      if (cameraState.temperature != null) {
        tempValue = '${cameraState.temperature!.toStringAsFixed(1)}°C';
      } else {
        tempValue = 'N/A';
      }
    }

    // Format RMS
    String rmsValue = '---';
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.isGuiding &&
        guiderState.rmsTotal != null) {
      rmsValue = '${guiderState.rmsTotal!.toStringAsFixed(2)}"';
    }

    // Format HFR
    String hfrValue = '---';
    if (lastStats?.hfr != null) {
      hfrValue = lastStats!.hfr!.toStringAsFixed(2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _QuickStat(
            icon: LucideIcons.thermometer,
            label: 'Sensor',
            value: tempValue,
            colors: colors,
          ),
          const SizedBox(width: 24),
          _QuickStat(
            icon: LucideIcons.activity,
            label: 'RMS',
            value: rmsValue,
            colors: colors,
          ),
          const SizedBox(width: 24),
          _QuickStat(
            icon: LucideIcons.target,
            label: 'HFR',
            value: hfrValue,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textMuted),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
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

// Panel content widgets
class _CapturePanel extends ConsumerWidget {
  final NightshadeColors colors;

  const _CapturePanel({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final namingPattern = ref.watch(namingPatternProvider);
    final sessionState = ref.watch(sessionStateProvider);
    final sessionImages = ref.watch(sessionImagesProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final cameraState = ref.watch(cameraStateProvider);

    // Get binning options based on connected camera's capabilities
    final binningOptions = ref.watch(
      cameraBinningOptionsProvider(cameraState.deviceId ?? ''),
    );

    // Ensure current binning value is valid for available options
    final currentBinning = binningOptions.contains(exposureSettings.binning)
        ? exposureSettings.binning
        : binningOptions.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exposure Settings
          _PanelSection(
            title: 'Exposure Settings',
            colors: colors,
            child: Column(
              children: [
                _InputRowEditable(
                  label: 'Exposure',
                  value: exposureSettings.exposureTime.toStringAsFixed(1),
                  suffix: 'sec',
                  colors: colors,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(exposureTime: parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _DropdownRow(
                  label: 'Frame Type',
                  value: exposureSettings.frameType.displayName,
                  items: FrameType.values.map((t) => t.displayName).toList(),
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final type = FrameType.values.firstWhere(
                        (t) => t.displayName == value,
                        orElse: () => FrameType.light,
                      );
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(frameType: type);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _DropdownRow(
                  label: 'Binning',
                  value: currentBinning,
                  items: binningOptions,
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final parts = value.split('x');
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(
                        binningX: int.parse(parts[0]),
                        binningY: int.parse(parts[1]),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // File Settings
          _PanelSection(
            title: 'File Settings',
            colors: colors,
            child: Column(
              children: [
                _DropdownRow(
                  label: 'Format',
                  value: namingPattern.format.displayName,
                  items:
                      ImageFileFormat.values.map((f) => f.displayName).toList(),
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final format = ImageFileFormat.values.firstWhere(
                        (f) => f.displayName == value,
                        orElse: () => ImageFileFormat.fits,
                      );
                      ref
                          .read(appSettingsProvider.notifier)
                          .setImageFormat(format.settingsValue);
                    }
                  },
                ),
                const SizedBox(height: 12),
                // In remote mode, show text input for server path
                // In local mode, show directory picker
                if (isRemoteMode)
                  _InputRowEditable(
                    label: 'Save Path (Server)',
                    value: namingPattern.baseDir,
                    colors: colors,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setImageOutputPath(value);
                    },
                  )
                else
                  _InputRow(
                    label: 'Save Path',
                    value: namingPattern.baseDir,
                    colors: colors,
                    trailing: GestureDetector(
                      onTap: () async {
                        final result = await getDirectoryPath(
                          confirmButtonText: 'Select',
                          initialDirectory: namingPattern.baseDir.isNotEmpty
                              ? namingPattern.baseDir
                              : null,
                        );
                        if (result != null) {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setImageOutputPath(result);
                        }
                      },
                      child: Icon(LucideIcons.folderOpen,
                          size: 14, color: colors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Session Statistics
          _PanelSection(
            title: 'Session',
            colors: colors,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Captured',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    Text(
                      '${sessionImages.length} frames',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Integration',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    Text(
                      _formatDuration(sessionState.totalIntegrationSecs),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Session status and duration
                if (sessionState.isActive) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary)),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Active',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.success),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Duration',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary)),
                      Text(
                        sessionState.duration != null
                            ? _formatSessionDuration(sessionState.duration!)
                            : '--:--:--',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        label: 'View Gallery',
                        icon: LucideIcons.galleryHorizontal,
                        colors: colors,
                        onTap: () {
                          // Would open gallery view
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        label: 'Clear Session',
                        icon: LucideIcons.trash2,
                        isOutline: true,
                        colors: colors,
                        onTap: () {
                          ref
                              .read(sessionImagesProvider.notifier)
                              .clearSession();
                        },
                      ),
                    ),
                  ],
                ),
                if (sessionState.isActive) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _SmallButton(
                      label: 'End Session',
                      icon: LucideIcons.stopCircle,
                      colors: colors,
                      onTap: () => _showEndSessionDialog(context, ref, colors),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).round();

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatSessionDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _showEndSessionDialog(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    final sessionState = ref.read(sessionStateProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.stopCircle, color: colors.warning),
            const SizedBox(width: 12),
            const Text('End Session'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to end the current imaging session?',
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Images Captured:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text('${sessionState.completedExposures}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Integration:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text(_formatDuration(sessionState.totalIntegrationSecs),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Duration:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text(
                          sessionState.duration != null
                              ? _formatSessionDuration(sessionState.duration!)
                              : '--:--:--',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, child) {
                final parkOnEnd = ref.watch(_parkMountOnEndProvider);
                final mountState = ref.watch(mountStateProvider);
                final mountConnected = mountState.connectionState ==
                    DeviceConnectionState.connected;

                return CheckboxListTile(
                  value: parkOnEnd,
                  onChanged: mountConnected
                      ? (value) {
                          ref.read(_parkMountOnEndProvider.notifier).state =
                              value ?? false;
                        }
                      : null,
                  title: Text(
                    'Park mount after ending session',
                    style: TextStyle(
                      fontSize: 14,
                      color: mountConnected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  enabled: mountConnected,
                );
              },
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          _GradientDialogButton(
            onPressed: () async {
              // Capture context before closing dialog
              final dialogContext = context;
              Navigator.of(context).pop();
              await _endSession(ref, dialogContext);
            },
            color: colors.warning,
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  Future<void> _endSession(WidgetRef ref, BuildContext context) async {
    try {
      final parkOnEnd = ref.read(_parkMountOnEndProvider);

      // End the session
      await ref.read(sessionStateProvider.notifier).endSession();

      // Park mount if requested (service handles connection check)
      if (parkOnEnd) {
        debugPrint('[Imaging] Parking mount after session end...');
        final result = await ref.read(mountCommandServiceProvider).park();
        if (context.mounted) {
          context.showCommandActionResult(result);
        }
        debugPrint(result.isSuccess
            ? '[Imaging] Mount parked successfully'
            : '[Imaging] Mount park failed: ${result.message}');
      }
    } catch (e) {
      debugPrint('[Imaging] Error ending session: $e');
    }
  }
}

// Provider for park mount on end setting
final _parkMountOnEndProvider = StateProvider<bool>((ref) => false);

class _CameraPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _CameraPanel({required this.colors});

  @override
  ConsumerState<_CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends ConsumerState<_CameraPanel> {
  bool _isCooling = false; // Only for UI loading state

  @override
  Widget build(BuildContext context) {
    final cameraState = ref.watch(cameraStateProvider);
    final coolingSettings = ref.watch(coolingSettingsProvider);
    final coolingStatus = ref.watch(coolingStatusProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    // Use target temp from provider (persists across navigation)
    final targetTemp = cameraState.targetTemp;

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;

    // Watch camera capabilities to gate UI features
    final capabilitiesAsync =
        ref.watch(cameraCapabilitiesProvider(cameraState.deviceId ?? ''));
    final capabilities = capabilitiesAsync.valueOrNull;
    final capabilitiesLoading = capabilitiesAsync.isLoading;
    final hasCoolingTelemetry = cameraState.temperature != null ||
        cameraState.coolerPower != null ||
        cameraState.isCooling;
    // Show cooling controls when support is known, still loading, or live
    // telemetry confirms cooling is active.
    final showCoolingSection = isConnected &&
        (capabilitiesLoading ||
            (capabilities?.canSetCcdTemperature == true) ||
            hasCoolingTelemetry);
    // If capabilities are unavailable, infer controls from live camera telemetry
    // to avoid blocking devices that omit explicit capability reporting.
    final canSetGain = capabilities?.canSetGain ?? (cameraState.gain != null);
    final canSetOffset =
        capabilities?.canSetOffset ?? (cameraState.offset != null);

    // Get binning options based on camera capabilities
    final binningOptions = ref.watch(
      cameraBinningOptionsProvider(cameraState.deviceId ?? ''),
    );

    // Ensure current binning value is valid for available options
    final currentBinning = binningOptions.contains(exposureSettings.binning)
        ? exposureSettings.binning
        : binningOptions.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No camera connected',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Cooling Section - show if camera supports cooling or while loading capabilities
          if (showCoolingSection)
            _PanelSection(
              title: 'Cooling',
              colors: widget.colors,
              child: Column(
                children: [
                  // Current temperature display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current',
                          style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary)),
                      Row(
                        children: [
                          Text(
                            isConnected && cameraState.temperature != null
                                ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
                                : '---',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                            ),
                          ),
                          if (isConnected && coolingStatus.isCooling)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                coolingStatus.isAtTarget
                                    ? LucideIcons.checkCircle2
                                    : LucideIcons.arrowDown,
                                size: 14,
                                color: coolingStatus.isAtTarget
                                    ? widget.colors.success
                                    : widget.colors.primary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Power',
                          style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary)),
                      Text(
                        isConnected && cameraState.coolerPower != null
                            ? '${cameraState.coolerPower!.toStringAsFixed(0)}%'
                            : '---',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (isConnected && coolingStatus.isCooling)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Target',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: widget.colors.textSecondary)),
                          Text(
                            '${coolingStatus.targetTemp.toStringAsFixed(1)}°C',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Target temperature slider
                  _SliderRowInteractive(
                    label: 'Target Temperature',
                    value: targetTemp,
                    min: -30,
                    max: 20,
                    suffix: '°C',
                    colors: widget.colors,
                    onChanged: isConnected
                        ? (value) {
                            // Update provider so value persists across navigation
                            ref
                                .read(cameraStateProvider.notifier)
                                .setTargetTemp(value);
                            // Also update settings provider for consistency
                            ref.read(coolingSettingsProvider.notifier).state =
                                coolingSettings.copyWith(targetTemp: value);
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallButton(
                          label: _isCooling ? 'Setting...' : 'Cool Down',
                          icon: LucideIcons.snowflake,
                          colors: widget.colors,
                          isEnabled: isConnected && !_isCooling,
                          onTap: () async {
                            setState(() => _isCooling = true);
                            try {
                              await ref
                                  .read(deviceServiceProvider)
                                  .setCameraCooling(
                                    enabled: true,
                                    targetTemp: targetTemp,
                                  );

                              // Update settings state
                              ref.read(coolingSettingsProvider.notifier).state =
                                  coolingSettings.copyWith(
                                      enabled: true, targetTemp: targetTemp);
                              // Update camera state
                              ref
                                  .read(cameraStateProvider.notifier)
                                  .setCooling(true);
                            } catch (e) {
                              if (!context.mounted) return;
                              context.showErrorSnackBar(
                                  'Failed to set cooling: $e');
                            } finally {
                              if (mounted) setState(() => _isCooling = false);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SmallButton(
                          label: 'Warm Up',
                          icon: LucideIcons.flame,
                          isOutline: true,
                          colors: widget.colors,
                          isEnabled: isConnected,
                          onTap: () async {
                            try {
                              await ref
                                  .read(deviceServiceProvider)
                                  .setCameraCooling(
                                    enabled: false,
                                  );

                              ref.read(coolingSettingsProvider.notifier).state =
                                  coolingSettings.copyWith(enabled: false);
                              ref
                                  .read(cameraStateProvider.notifier)
                                  .setCooling(false);
                            } catch (e) {
                              if (!context.mounted) return;
                              context.showErrorSnackBar(
                                  'Failed to turn off cooler: $e');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // Show "not supported" message when camera is connected and capabilities confirm no cooling support
          if (isConnected &&
              !capabilitiesLoading &&
              !capabilitiesAsync.hasError &&
              capabilities != null &&
              !capabilities.canSetCcdTemperature)
            _PanelSection(
              title: 'Cooling',
              colors: widget.colors,
              child: Text(
                'Cooling not supported by this camera',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 20),

          // Sensor Settings
          _PanelSection(
            title: 'Sensor',
            colors: widget.colors,
            child: Column(
              children: [
                _DropdownRow(
                  label: 'Binning',
                  value: currentBinning,
                  items: binningOptions,
                  colors: widget.colors,
                  onChanged: isConnected
                      ? (value) {
                          if (value != null) {
                            final parts = value.split('x');
                            ref.read(exposureSettingsProvider.notifier).state =
                                exposureSettings.copyWith(
                              binningX: int.parse(parts[0]),
                              binningY: int.parse(parts[1]),
                            );
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _DropdownRow(
                  label: 'Read Mode',
                  value: exposureSettings.fastReadout ? 'Fast' : 'High Quality',
                  items: const ['High Quality', 'Fast'],
                  colors: widget.colors,
                  onChanged: isConnected
                      ? (value) {
                          ref.read(exposureSettingsProvider.notifier).state =
                              exposureSettings.copyWith(
                                  fastReadout: value == 'Fast');
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Gain/Offset - only show if camera supports these features
          if (canSetGain || canSetOffset)
            _PanelSection(
              title: 'Gain / Offset',
              colors: widget.colors,
              child: Column(
                children: [
                  // Only show gain control if camera supports it
                  if (canSetGain)
                    _InputRowEditable(
                      label:
                          'Gain${capabilities?.gainMin != null ? ' (${capabilities!.gainMin}-${capabilities.gainMax})' : ''}',
                      value: exposureSettings.gain.toString(),
                      colors: widget.colors,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 0) {
                          // Clamp to valid range if capabilities available
                          final clamped = capabilities?.gainMin != null
                              ? parsed.clamp(
                                  capabilities!.gainMin!, capabilities.gainMax!)
                              : parsed;
                          ref.read(exposureSettingsProvider.notifier).state =
                              exposureSettings.copyWith(gain: clamped);
                        }
                      },
                    ),
                  if (canSetGain && canSetOffset) const SizedBox(height: 12),
                  // Only show offset control if camera supports it
                  if (canSetOffset)
                    _InputRowEditable(
                      label:
                          'Offset${capabilities?.offsetMin != null ? ' (${capabilities!.offsetMin}-${capabilities.offsetMax})' : ''}',
                      value: exposureSettings.offset.toString(),
                      colors: widget.colors,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 0) {
                          // Clamp to valid range if capabilities available
                          final clamped = capabilities?.offsetMin != null
                              ? parsed.clamp(capabilities!.offsetMin!,
                                  capabilities.offsetMax!)
                              : parsed;
                          ref.read(exposureSettingsProvider.notifier).state =
                              exposureSettings.copyWith(offset: clamped);
                        }
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const _DebayeringCard(),
        ],
      ),
    );
  }
}

class _FocusPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _FocusPanel({super.key, required this.colors});

  @override
  ConsumerState<_FocusPanel> createState() => _FocusPanelState();
}

class _FocusPanelState extends ConsumerState<_FocusPanel> {
  // UI-only transient state (doesn't need to persist)
  bool _isRunningAutofocus = false;

  Future<void> _goToPosition(int position) async {
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.moveFocuserTo(position);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Focuser error: $e');
    }
  }

  void _showGoToPositionDialog() {
    final focuserState = ref.read(focuserStateProvider);
    final maxPosition = focuserState.maxPosition ?? 50000;
    final currentPosition = focuserState.position ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        final controller =
            TextEditingController(text: currentPosition.toString());
        return AlertDialog(
          title: const Text('Go To Position'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter position (0 - $maxPosition):'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Position',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            _GradientDialogButton(
              onPressed: () {
                final position = int.tryParse(controller.text);
                if (position != null &&
                    position >= 0 &&
                    position <= maxPosition) {
                  Navigator.of(context).pop();
                  _goToPosition(position);
                } else {
                  context.showWarningSnackBar(
                      'Invalid position. Must be between 0 and $maxPosition');
                }
              },
              color: Theme.of(context).extension<NightshadeColors>()!.primary,
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runAutofocus() async {
    setState(() => _isRunningAutofocus = true);
    ref.read(sessionStateProvider.notifier).setAutofocusing(true);

    try {
      final settings = ref.read(focusSettingsProvider);
      final result = await ref.read(deviceServiceProvider).runAutofocus(
            exposureTime: settings.exposureTime,
            stepSize: settings.afStepSize,
            stepsOut: settings.stepsOut,
            method: settings.method,
            binning: 1,
          );

      ref.read(autofocusResultProvider.notifier).state = result;

      if (mounted) {
        context.showSuccessSnackBar(
            'Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Autofocus failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRunningAutofocus = false);
        ref.read(sessionStateProvider.notifier).setAutofocusing(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final focuserState = ref.watch(focuserStateProvider);
    final focusSettings = ref.watch(focusSettingsProvider);
    final isConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final currentPosition = focuserState.position ?? 0;
    final maxPosition = focuserState.maxPosition ?? 50000;
    final temperature = focuserState.temperature;
    final isMoving = focuserState.isMoving;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No focuser connected',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Manual Focus Section
          _PanelSection(
            title: 'Manual Focus',
            colors: widget.colors,
            child: Column(
              children: [
                // Position display
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Position',
                        style: TextStyle(
                            fontSize: 12, color: widget.colors.textSecondary)),
                    Row(
                      children: [
                        Text(
                          isConnected ? '$currentPosition' : '---',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          isConnected ? ' / $maxPosition' : '',
                          style: TextStyle(
                              fontSize: 12, color: widget.colors.textMuted),
                        ),
                        if (isMoving)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.colors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (temperature != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Temperature',
                            style: TextStyle(
                                fontSize: 12,
                                color: widget.colors.textSecondary)),
                        Text(
                          '${temperature.toStringAsFixed(1)}°C',
                          style: TextStyle(
                              fontSize: 12, color: widget.colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Movement buttons - using shared FocuserControls widget
                const FocuserControls(
                  compact: true,
                  showAutofocus: false,
                ),
                const SizedBox(height: 12),

                // Step size selector
                Row(
                  children: [
                    Text('Step Size:',
                        style: TextStyle(
                            fontSize: 11, color: widget.colors.textSecondary)),
                    const SizedBox(width: 8),
                    ...[10, 50, 100, 500].map((step) {
                      final isSelected = focusSettings.stepSize == step;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => ref
                              .read(focusSettingsProvider.notifier)
                              .state = focusSettings.copyWith(stepSize: step),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.colors.primary.withValues(alpha: 0.2)
                                  : widget.colors.background,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? widget.colors.primary
                                    : widget.colors.border,
                              ),
                            ),
                            child: Text(
                              '$step',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? widget.colors.primary
                                    : widget.colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),

                // Go to position button
                SizedBox(
                  width: double.infinity,
                  child: _SmallButton(
                    label: 'Go To Position...',
                    icon: LucideIcons.move,
                    colors: widget.colors,
                    isEnabled: isConnected && !isMoving,
                    onTap: _showGoToPositionDialog,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Autofocus Section
          _PanelSection(
            title: 'Autofocus',
            colors: widget.colors,
            child: Column(
              children: [
                _DropdownRow(
                  label: 'Method',
                  value: focusSettings.method,
                  items: const ['V-Curve', 'Hyperbolic', 'Parabolic'],
                  colors: widget.colors,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(focusSettingsProvider.notifier).state =
                          focusSettings.copyWith(method: value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _InputRowEditable(
                  label: 'Step Size',
                  value: '${focusSettings.afStepSize}',
                  suffix: 'steps',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(focusSettingsProvider.notifier).state =
                          focusSettings.copyWith(afStepSize: parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _InputRowEditable(
                  label: 'Steps Out',
                  value: '${focusSettings.stepsOut}',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(focusSettingsProvider.notifier).state =
                          focusSettings.copyWith(stepsOut: parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _InputRowEditable(
                  label: 'Exposure',
                  value: focusSettings.exposureTime.toStringAsFixed(1),
                  suffix: 'sec',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(focusSettingsProvider.notifier).state =
                          focusSettings.copyWith(exposureTime: parsed);
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _SmallButton(
                    label: _isRunningAutofocus ? 'Running...' : 'Run Autofocus',
                    icon: _isRunningAutofocus
                        ? LucideIcons.loader2
                        : LucideIcons.focus,
                    colors: widget.colors,
                    isEnabled: isConnected && !_isRunningAutofocus,
                    onTap: _runAutofocus,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidingPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _GuidingPanel({required this.colors});

  @override
  ConsumerState<_GuidingPanel> createState() => _GuidingPanelState();
}

class _GuidingPanelState extends ConsumerState<_GuidingPanel> {
  // UI-only transient state (doesn't need to persist)
  bool _isStartingGuiding = false;
  bool _isDithering = false;

  Future<void> _startGuiding() async {
    setState(() => _isStartingGuiding = true);
    final ditherSettings = ref.read(ditherSettingsProvider);
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.startGuiding(
        settlePixels: ditherSettings.settlePixels,
        settleTime: ditherSettings.settleTime,
      );
      ref.read(sessionStateProvider.notifier).setGuiding(true);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to start guiding: $e');
    } finally {
      if (mounted) setState(() => _isStartingGuiding = false);
    }
  }

  Future<void> _stopGuiding() async {
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.stopGuiding();
      ref.read(sessionStateProvider.notifier).setGuiding(false);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to stop guiding: $e');
    }
  }

  Future<void> _dither() async {
    setState(() => _isDithering = true);
    ref.read(sessionStateProvider.notifier).setDithering(true);
    final ditherSettings = ref.read(ditherSettingsProvider);
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.dither(
        amount: ditherSettings.ditherAmount,
        settlePixels: ditherSettings.settlePixels,
        settleTime: ditherSettings.settleTime,
      );
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Dither failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isDithering = false);
        ref.read(sessionStateProvider.notifier).setDithering(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guiderState = ref.watch(guiderStateProvider);
    final ditherSettings = ref.watch(ditherSettingsProvider);
    final isConnected =
        guiderState.connectionState == DeviceConnectionState.connected;
    final isGuiding = guiderState.isGuiding;

    final rmsRa = guiderState.rmsRa?.toStringAsFixed(2) ?? '---';
    final rmsDec = guiderState.rmsDec?.toStringAsFixed(2) ?? '---';
    final rmsTotal = guiderState.rmsTotal?.toStringAsFixed(2) ?? '---';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No guider connected (PHD2)',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Guiding graph with real data
          _CompactGuidingGraph(
            colors: widget.colors,
            data: ref.watch(guideGraphProvider),
            isGuiding: isGuiding,
            isConnected: isConnected,
          ),
          const SizedBox(height: 16),

          // RMS Stats
          Row(
            children: [
              _GuideStat(
                  label: 'RA RMS', value: '$rmsRa"', colors: widget.colors),
              _GuideStat(
                  label: 'Dec RMS', value: '$rmsDec"', colors: widget.colors),
              _GuideStat(
                  label: 'Total', value: '$rmsTotal"', colors: widget.colors),
            ],
          ),
          const SizedBox(height: 20),

          // Control Section
          _PanelSection(
            title: 'Control',
            colors: widget.colors,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        label: _isStartingGuiding
                            ? 'Starting...'
                            : isGuiding
                                ? 'Guiding'
                                : 'Start',
                        icon:
                            isGuiding ? LucideIcons.activity : LucideIcons.play,
                        colors: widget.colors,
                        isEnabled:
                            isConnected && !isGuiding && !_isStartingGuiding,
                        onTap: _startGuiding,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        label: 'Stop',
                        icon: LucideIcons.square,
                        isOutline: true,
                        colors: widget.colors,
                        isEnabled: isConnected && isGuiding,
                        onTap: _stopGuiding,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _SmallButton(
                    label: _isDithering ? 'Dithering...' : 'Dither',
                    icon: _isDithering
                        ? LucideIcons.loader2
                        : LucideIcons.shuffle,
                    isOutline: true,
                    colors: widget.colors,
                    isEnabled: isConnected && isGuiding && !_isDithering,
                    onTap: _dither,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Dithering Settings
          _PanelSection(
            title: 'Dither Settings',
            colors: widget.colors,
            child: Column(
              children: [
                _SliderRowInteractive(
                  label: 'Amount',
                  value: ditherSettings.ditherAmount,
                  min: 1,
                  max: 20,
                  suffix: 'px',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(ditherAmount: value),
                ),
                const SizedBox(height: 12),
                _SliderRowInteractive(
                  label: 'Settle Threshold',
                  value: ditherSettings.settlePixels,
                  min: 0.3,
                  max: 3.0,
                  suffix: '"',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(settlePixels: value),
                ),
                const SizedBox(height: 12),
                _SliderRowInteractive(
                  label: 'Settle Time',
                  value: ditherSettings.settleTime,
                  min: 5,
                  max: 30,
                  suffix: 's',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(settleTime: value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact guiding graph widget for the imaging screen overview panel.
/// Displays real RA/Dec error data from guideGraphProvider, or a
/// empty-state message when no guide data is available.
class _CompactGuidingGraph extends StatelessWidget {
  final NightshadeColors colors;
  final List<GuideGraphPoint> data;
  final bool isGuiding;
  final bool isConnected;

  const _CompactGuidingGraph({
    required this.colors,
    required this.data,
    required this.isGuiding,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = data.isNotEmpty;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          // Draw the real graph when we have data
          if (hasData)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: CustomPaint(
                  painter: _CompactGuidingGraphPainter(
                    data: data,
                    colors: colors,
                  ),
                ),
              ),
            ),
          // Show empty state when no data
          if (!hasData)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGuiding ? LucideIcons.activity : LucideIcons.crosshair,
                    size: 24,
                    color: isGuiding ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isGuiding
                        ? 'Waiting for guide data...'
                        : isConnected
                            ? 'Ready to guide'
                            : 'No guide data',
                    style: TextStyle(
                      fontSize: 11,
                      color: isGuiding ? colors.success : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          // Legend (always visible)
          Positioned(
            bottom: 8,
            left: 8,
            child: Row(
              children: [
                Container(width: 12, height: 2, color: Colors.redAccent),
                const SizedBox(width: 4),
                Text('RA',
                    style: TextStyle(fontSize: 9, color: colors.textMuted)),
                const SizedBox(width: 12),
                Container(width: 12, height: 2, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text('Dec',
                    style: TextStyle(fontSize: 9, color: colors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders real RA/Dec guide error data.
/// Matches the rendering approach from the guiding_tab.dart _GraphPainter
/// but is simplified for the compact 120px overview panel.
class _CompactGuidingGraphPainter extends CustomPainter {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;

  _CompactGuidingGraphPainter({
    required this.data,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // Draw center zero-line
    final zeroPaint = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), zeroPaint);

    if (data.isEmpty) return;

    final raPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final decPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Scale: +/- 4 arcsec range (same as the full guiding graph)
    const range = 4.0;
    final scaleY = size.height / (range * 2);
    // Show last 100 points spread across the width
    final stepX = size.width / 100;

    final raPath = Path();
    final decPath = Path();

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final x = size.width - ((data.length - 1 - i) * stepX);

      if (x < 0) continue;

      final raY = centerY - (point.ra.clamp(-range, range) * scaleY);
      final decY = centerY - (point.dec.clamp(-range, range) * scaleY);

      if (i == 0 || x < stepX) {
        raPath.moveTo(x, raY);
        decPath.moveTo(x, decY);
      } else {
        raPath.lineTo(x, raY);
        decPath.lineTo(x, decY);
      }
    }

    canvas.drawPath(raPath, raPaint);
    canvas.drawPath(decPath, decPaint);
  }

  @override
  bool shouldRepaint(covariant _CompactGuidingGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class _GuideStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _GuideStat({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
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
    );
  }
}

class _PanelSection extends StatelessWidget {
  final String title;
  final Widget child;
  final NightshadeColors colors;

  const _PanelSection({
    required this.title,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InputRow extends StatelessWidget {
  final String label;
  final String? value;
  final NightshadeColors colors;
  final Widget? trailing;

  const _InputRow({
    required this.label,
    this.value,
    required this.colors,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InputRowEditable extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  const _InputRowEditable({
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: TextEditingController(text: value),
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
              onSubmitted: onChanged,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final NightshadeColors colors;
  final ValueChanged<String?>? onChanged;

  const _DropdownRow({
    required this.label,
    this.value,
    required this.items,
    required this.colors,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isEnabled ? colors.textSecondary : colors.textMuted,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isEnabled ? colors.background : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : null,
                isExpanded: true,
                isDense: true,
                icon: Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: colors.textMuted,
                ),
                dropdownColor: colors.surface,
                style: TextStyle(
                  fontSize: 12,
                  color: isEnabled ? colors.textPrimary : colors.textMuted,
                ),
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderRowInteractive extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final NightshadeColors colors;
  final ValueChanged<double>? onChanged;

  const _SliderRowInteractive({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.colors,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isEnabled ? colors.textSecondary : colors.textMuted,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: isEnabled ? colors.primary : colors.textMuted,
              inactiveTrackColor: colors.border,
              thumbColor: isEnabled ? colors.primary : colors.textMuted,
              overlayColor: colors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${value.toStringAsFixed(1)}$suffix',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isEnabled ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isOutline;
  final bool isEnabled;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _SmallButton({
    required this.label,
    required this.icon,
    this.isOutline = false,
    this.isEnabled = true,
    required this.colors,
    this.onTap,
  });

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.isEnabled;
    final primaryColor =
        isEnabled ? widget.colors.primary : widget.colors.textMuted;

    // Build gradient for filled (non-outline) buttons
    final useGradient = !widget.isOutline && isEnabled;
    final fillColor = widget.isOutline
        ? _isHovered && isEnabled
            ? primaryColor.withValues(alpha: 0.1)
            : Colors.transparent
        : isEnabled
            ? null // Use gradient instead
            : widget.colors.surfaceAlt;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color:
                useGradient ? primaryColor.withValues(alpha: 0.65) : fillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primaryColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isOutline
                    ? primaryColor
                    : isEnabled
                        ? Colors.white
                        : widget.colors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isOutline
                        ? primaryColor
                        : isEnabled
                            ? Colors.white
                            : widget.colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
// GRADIENT DIALOG BUTTON
// =============================================================================

/// A dialog action button with gradient styling to match NightshadeButton
class _GradientDialogButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Color color;
  final Widget child;

  const _GradientDialogButton({
    required this.onPressed,
    required this.color,
    required this.child,
  });

  @override
  State<_GradientDialogButton> createState() => _GradientDialogButtonState();
}

class _GradientDialogButtonState extends State<_GradientDialogButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  /// Creates a slightly darker shade of the given color
  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;
    final effectiveColor = isDisabled
        ? widget.color.withValues(alpha: 0.4)
        : _isPressed
            ? _darkenColor(widget.color, 0.1)
            : widget.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _isPressed = false;
        });
      },
      cursor:
          isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: isDisabled ? null : (_) => setState(() => _isPressed = true),
        onTapUp: isDisabled ? null : (_) => setState(() => _isPressed = false),
        onTapCancel:
            isDisabled ? null : () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isHovered && !isDisabled && !_isPressed
                ? [
                    BoxShadow(
                      color: effectiveColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DEBAYERING CARD
// =============================================================================

class _DebayeringCard extends ConsumerWidget {
  const _DebayeringCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final debayerEnabled = ref.watch(debayerEnabledProvider);
    final bayerPattern = ref.watch(bayerPatternProvider);
    final debayerAlgorithm = ref.watch(debayerAlgorithmProvider);

    return _PanelSection(
      title: 'Debayering',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enable Debayering',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              Switch(
                value: debayerEnabled,
                onChanged: (value) {
                  ref.read(debayerEnabledProvider.notifier).state = value;
                },
                activeThumbColor: colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enable for color cameras to convert raw Bayer data to RGB',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(height: 16),

          // Algorithm selection
          _DropdownRow(
            label: 'Algorithm',
            value: debayerAlgorithm.displayName,
            items: DebayerAlgorithm.values.map((a) => a.displayName).toList(),
            colors: colors,
            onChanged: debayerEnabled
                ? (value) {
                    if (value != null) {
                      final algorithm = DebayerAlgorithm.values.firstWhere(
                        (a) => a.displayName == value,
                        orElse: () => DebayerAlgorithm.bilinear,
                      );
                      ref.read(debayerAlgorithmProvider.notifier).state =
                          algorithm;
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),

          // Bayer pattern selection
          _DropdownRow(
            label: 'Pattern',
            value: bayerPattern.displayName,
            items: BayerPattern.values.map((p) => p.displayName).toList(),
            colors: colors,
            onChanged: debayerEnabled
                ? (value) {
                    if (value != null) {
                      final pattern = BayerPattern.values.firstWhere(
                        (p) => p.displayName == value,
                        orElse: () => BayerPattern.rggb,
                      );
                      ref.read(bayerPatternProvider.notifier).state = pattern;
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),

          // Auto-detect option
          Consumer(
            builder: (context, ref, _) {
              final autoDetect = ref.watch(autoDetectBayerPatternProvider);
              return Row(
                children: [
                  Checkbox(
                    value: autoDetect,
                    onChanged: debayerEnabled
                        ? (v) {
                            ref
                                .read(autoDetectBayerPatternProvider.notifier)
                                .state = v ?? false;
                          }
                        : null,
                    fillColor: WidgetStateProperty.all(colors.primary),
                    side: BorderSide(color: colors.border),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Auto-detect from FITS header',
                      style: TextStyle(
                        fontSize: 12,
                        color: debayerEnabled
                            ? colors.textSecondary
                            : colors.textMuted,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Wrapper widget for annotation overlay with object info popup
class _AnnotationOverlayWrapper extends ConsumerStatefulWidget {
  final double zoomLevel;
  final Offset imageOffset;
  final Size imageSize;
  final NightshadeColors colors;

  const _AnnotationOverlayWrapper({
    required this.zoomLevel,
    required this.imageOffset,
    required this.imageSize,
    required this.colors,
  });

  @override
  ConsumerState<_AnnotationOverlayWrapper> createState() =>
      _AnnotationOverlayWrapperState();
}

class _AnnotationOverlayWrapperState
    extends ConsumerState<_AnnotationOverlayWrapper> {
  CelestialObjectAnnotation? _selectedObject;
  Offset? _tooltipPosition;
  bool _isHoverTooltip = false; // Tracks if tooltip is from hover
  static const double _tooltipWidth = 300;
  static const double _tooltipHeight = 220;
  static const double _tooltipMargin = 12;
  static const double _objectsPanelWidth = 280;

  Offset _computeTooltipPosition(Offset anchor, {bool preferRight = true}) {
    final screenSize = MediaQuery.of(context).size;
    final isPanelVisible = ref.read(annotationPanelVisibleProvider);
    final reservedRight = isPanelVisible ? _objectsPanelWidth : 0.0;
    final availableRight =
        (screenSize.width - reservedRight).clamp(0.0, screenSize.width);

    final preferX =
        preferRight ? anchor.dx + 20 : anchor.dx - _tooltipWidth - 20;
    final fallbackX =
        preferRight ? anchor.dx - _tooltipWidth - 20 : anchor.dx + 20;
    final x = (preferX + _tooltipWidth + _tooltipMargin <= availableRight)
        ? preferX
        : fallbackX;

    final preferredY = anchor.dy - (_tooltipHeight / 2);
    final y = preferredY.clamp(
      _tooltipMargin,
      screenSize.height - _tooltipHeight - _tooltipMargin,
    );
    final maxX = math.max(
      _tooltipMargin,
      availableRight - _tooltipWidth - _tooltipMargin,
    );

    return Offset(
      x.clamp(_tooltipMargin, maxX),
      y,
    );
  }

  void _onObjectTapped(CelestialObjectAnnotation object) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
    final screenPosition = imageToViewport(
      imagePoint: Offset(object.x, object.y),
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = false; // This is a click, not hover
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: true);
    });
  }

  void _onObjectHovered(
      CelestialObjectAnnotation object, Offset screenPosition) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
    // Don't override a click-selected tooltip with hover
    if (_selectedObject != null && !_isHoverTooltip) return;

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = true;
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: true);
    });
  }

  void _onObjectUnhovered() {
    // Only clear if this was a hover tooltip, not a click
    if (!_isHoverTooltip) return;

    ref.read(selectedAnnotationObjectProvider.notifier).state = null;
    setState(() {
      _selectedObject = null;
      _tooltipPosition = null;
      _isHoverTooltip = false;
    });
  }

  void _onIdentifyAt(double x, double y) async {
    // Use annotation service to identify object at position
    final annotationService = ref.read(annotationServiceProvider);
    final annotation = ref.read(currentAnnotationProvider);
    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();

    if (annotation?.plateSolve == null) return;

    final result = await annotationService.identifyAtPixel(
      plateSolve: annotation!.plateSolve,
      x: x,
      y: y,
      searchRadiusArcsec: settings.clickSearchRadiusArcsec,
    );

    if (result != null && mounted) {
      final screenPosition = imageToViewport(
        imagePoint: Offset(x, y),
        imageOffset: widget.imageOffset,
        zoomLevel: widget.zoomLevel,
      );

      setState(() {
        _selectedObject = result;
        _isHoverTooltip = false;
        _tooltipPosition =
            _computeTooltipPosition(screenPosition, preferRight: true);
      });
    }
  }

  void _closeTooltip() {
    ref.read(selectedAnnotationObjectProvider.notifier).state = null;
    setState(() {
      _selectedObject = null;
      _tooltipPosition = null;
      _isHoverTooltip = false;
    });
  }

  void _showMoreInfo() {
    if (_selectedObject == null) return;
    final obj = _selectedObject!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(obj.commonName ?? obj.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (obj.commonName != null) ...[
                Text('Common Name: ${obj.commonName}',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
              ],
              Text('Type: ${obj.type.toString().split('.').last}',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('RA: ${obj.ra.toStringAsFixed(6)}°',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('Dec: ${obj.dec.toStringAsFixed(6)}°',
                  style: const TextStyle(fontSize: 14)),
              if (obj.magnitude != null) ...[
                const SizedBox(height: 8),
                Text('Magnitude: ${obj.magnitude!.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14)),
              ],
              if (obj.size != null) ...[
                const SizedBox(height: 8),
                Text('Size: ${obj.size!.toStringAsFixed(2)}\'',
                    style: const TextStyle(fontSize: 14)),
              ],
            ],
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
      ),
    );

    _closeTooltip();
  }

  void _onObjectSelectedFromPanel(CelestialObjectAnnotation object) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
    // When an object is selected from the sidebar panel, show its tooltip
    final screenPosition = imageToViewport(
      imagePoint: Offset(object.x, object.y),
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = false; // Panel selection is like a click
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(currentAnnotationProvider);
    final isPanelVisible = ref.watch(annotationPanelVisibleProvider);

    return Stack(
      children: [
        AnnotationOverlay(
          annotation: annotation,
          zoomLevel: widget.zoomLevel,
          imageOffset: widget.imageOffset,
          imageSize: widget.imageSize,
          onObjectTapped: _onObjectTapped,
          onIdentifyAt: _onIdentifyAt,
          onObjectHovered: _onObjectHovered,
          onObjectUnhovered: _onObjectUnhovered,
        ),
        // Object info tooltip
        if (_selectedObject != null && _tooltipPosition != null)
          Positioned(
            left: _tooltipPosition!.dx,
            top: _tooltipPosition!.dy,
            child: ObjectInfoTooltip(
              object: _selectedObject!,
              onClose: _closeTooltip,
              onMoreInfo: _isHoverTooltip ? null : _showMoreInfo,
            ),
          ),
        // Objects sidebar panel
        if (isPanelVisible)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: _AnnotationObjectsPanel(
              colors: widget.colors,
              onObjectSelected: _onObjectSelectedFromPanel,
              selectedObjectId: _selectedObject?.id,
            ),
          ),
      ],
    );
  }
}

/// Banner shown when annotation catalog is not installed
class _AnnotationCatalogBanner extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback onSetup;

  const _AnnotationCatalogBanner({
    required this.colors,
    required this.onDismiss,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Annotations are enabled but no catalog is installed. Download the annotation catalog to identify objects in your images.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          NightshadeButton(
            onPressed: onSetup,
            label: 'Setup',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Status indicator for the live annotation pipeline
class _AnnotationStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;

  const _AnnotationStatusIndicator({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationState = ref.watch(annotationStateProvider);
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull;
    final secondaryMessage =
        annotationState.errorDetails ?? _getActionHint(annotationState.status);

    // Don't show anything if annotations are disabled
    if (annotationSettings != null && !annotationSettings.enabled) {
      return const SizedBox.shrink();
    }

    // Don't show idle state (reduces visual clutter)
    if (annotationState.status == AnnotationStatus.idle) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _getBackgroundColor(annotationState.status),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _getBorderColor(annotationState.status),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _getStatusIcon(annotationState.status),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  annotationState.message ??
                      _getStatusText(annotationState.status),
                  style: TextStyle(
                    color: _getTextColor(annotationState.status),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (secondaryMessage != null)
                  Text(
                    secondaryMessage,
                    style: TextStyle(
                      color: _getTextColor(annotationState.status)
                          .withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF1E3A5F)
            .withValues(alpha: 0.9); // Blue for processing
      case AnnotationStatus.complete:
        return const Color(0xFF1E4620)
            .withValues(alpha: 0.9); // Green for success
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFF5F1E1E).withValues(alpha: 0.9); // Red for error
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFF5F4D1E)
            .withValues(alpha: 0.9); // Orange for warning
      case AnnotationStatus.idle:
        return Colors.transparent;
    }
  }

  Color _getBorderColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF3B82F6).withValues(alpha: 0.5);
      case AnnotationStatus.complete:
        return const Color(0xFF22C55E).withValues(alpha: 0.5);
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFFEF4444).withValues(alpha: 0.5);
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFFF59E0B).withValues(alpha: 0.5);
      case AnnotationStatus.idle:
        return Colors.transparent;
    }
  }

  Color _getTextColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF93C5FD);
      case AnnotationStatus.complete:
        return const Color(0xFF86EFAC);
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFFFCA5A5);
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFFFCD34D);
      case AnnotationStatus.idle:
        return Colors.white70;
    }
  }

  Widget _getStatusIcon(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_getTextColor(status)),
          ),
        );
      case AnnotationStatus.complete:
        return Icon(LucideIcons.checkCircle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return Icon(LucideIcons.alertCircle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.catalogsNotInstalled:
        return Icon(LucideIcons.alertTriangle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.idle:
        return const SizedBox.shrink();
    }
  }

  String _getStatusText(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
        return 'Checking catalogs...';
      case AnnotationStatus.plateSolving:
        return 'Plate solving...';
      case AnnotationStatus.searchingCatalogs:
        return 'Searching catalogs...';
      case AnnotationStatus.complete:
        return 'Annotation complete';
      case AnnotationStatus.error:
        return 'Annotation error';
      case AnnotationStatus.plateSolveFailed:
        return 'Plate solve failed';
      case AnnotationStatus.catalogsNotInstalled:
        return 'No catalogs installed';
      case AnnotationStatus.idle:
        return '';
    }
  }

  String? _getActionHint(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.catalogsNotInstalled:
        return 'Install catalogs in Settings > Catalogs';
      case AnnotationStatus.plateSolveFailed:
        return 'Check solver config, focus, and star signal';
      case AnnotationStatus.error:
        return 'Capture a fresh frame to retry';
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
      case AnnotationStatus.complete:
      case AnnotationStatus.idle:
        return null;
    }
  }
}

/// Provider for the annotation sidebar panel visibility state
final annotationPanelVisibleProvider = StateProvider<bool>((ref) => false);

enum _AnnotationPanelSortMode { brightness, name, type }

final annotationPanelSortModeProvider =
    StateProvider<_AnnotationPanelSortMode>((ref) {
  return _AnnotationPanelSortMode.brightness;
});

Set<AnnotationObjectFilter> _filtersForObjectType(ObjectType type) {
  switch (type) {
    case ObjectType.galaxy:
      return {AnnotationObjectFilter.galaxies};
    case ObjectType.nebula:
      return {AnnotationObjectFilter.nebulae};
    case ObjectType.planetaryNebula:
      return {AnnotationObjectFilter.planetaryNebulae};
    case ObjectType.starCluster:
      return {AnnotationObjectFilter.starClusters};
    case ObjectType.star:
    case ObjectType.doubleStar:
      return {AnnotationObjectFilter.stars};
    case ObjectType.asterism:
    case ObjectType.unknown:
      return {AnnotationObjectFilter.other};
  }
}

bool _isTypeVisibleFromSettings(
  ObjectType type,
  Set<AnnotationObjectFilter> filters,
) {
  return _filtersForObjectType(type).any(filters.contains);
}

/// Sidebar panel showing list of detected celestial objects
class _AnnotationObjectsPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final void Function(CelestialObjectAnnotation object) onObjectSelected;
  final String? selectedObjectId;

  const _AnnotationObjectsPanel({
    required this.colors,
    required this.onObjectSelected,
    this.selectedObjectId,
  });

  @override
  ConsumerState<_AnnotationObjectsPanel> createState() =>
      _AnnotationObjectsPanelState();
}

class _AnnotationObjectsPanelState
    extends ConsumerState<_AnnotationObjectsPanel> {
  static const List<ObjectType> _filterTypes = [
    ObjectType.galaxy,
    ObjectType.nebula,
    ObjectType.planetaryNebula,
    ObjectType.starCluster,
    ObjectType.star,
    ObjectType.unknown,
  ];

  bool _filtersExpanded = false;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(currentAnnotationProvider);
    final settings = ref.watch(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    final sortMode = ref.watch(annotationPanelSortModeProvider);
    final objects = annotation?.objects ?? [];

    final typeCounts = <ObjectType, int>{};
    for (final obj in objects) {
      typeCounts[obj.type] = (typeCounts[obj.type] ?? 0) + 1;
    }

    // Apply visibility rules consistent with overlay rendering.
    final displayableObjects = objects.where((obj) {
      if (!obj.visible) return false;
      if (!_isTypeVisibleFromSettings(obj.type, settings.visibleTypes)) {
        return false;
      }
      if (obj.magnitude != null) {
        if (obj.magnitude! > settings.magnitudeCutoff) return false;
        if (obj.magnitude! < settings.minMagnitude) return false;
      }
      return true;
    }).toList();

    // Apply search filter on top of display filters.
    final filteredObjects = displayableObjects.where((obj) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatch = obj.name.toLowerCase().contains(query);
        final commonNameMatch =
            obj.commonName?.toLowerCase().contains(query) ?? false;
        final catalogMatch =
            obj.catalogId?.toLowerCase().contains(query) ?? false;
        if (!nameMatch && !commonNameMatch && !catalogMatch) return false;
      }
      return true;
    }).toList();

    switch (sortMode) {
      case _AnnotationPanelSortMode.brightness:
        filteredObjects.sort((a, b) {
          final aMag = a.magnitude ?? 99.0;
          final bMag = b.magnitude ?? 99.0;
          final magCompare = aMag.compareTo(bMag);
          if (magCompare != 0) return magCompare;
          return a.name.compareTo(b.name);
        });
      case _AnnotationPanelSortMode.name:
        filteredObjects.sort((a, b) => a.name.compareTo(b.name));
      case _AnnotationPanelSortMode.type:
        filteredObjects.sort((a, b) {
          final typeCompare = _getObjectTypeLabel(a.type)
              .compareTo(_getObjectTypeLabel(b.type));
          if (typeCompare != 0) return typeCompare;
          return (a.magnitude ?? 99.0).compareTo(b.magnitude ?? 99.0);
        });
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: widget.colors.surface.withValues(alpha: 0.95),
        border: Border(
          left: BorderSide(color: widget.colors.border),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              border: Border(
                bottom: BorderSide(color: widget.colors.border),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.sparkle,
                  size: 16,
                  color: widget.colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Detected Objects',
                  style: TextStyle(
                    color: widget.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Object count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${filteredObjects.length}/${displayableObjects.length}',
                    style: TextStyle(
                      color: widget.colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<_AnnotationPanelSortMode>(
                  tooltip: 'Sort objects',
                  color: widget.colors.surfaceAlt,
                  onSelected: (value) => ref
                      .read(annotationPanelSortModeProvider.notifier)
                      .state = value,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _AnnotationPanelSortMode.brightness,
                      child: Text(
                        'Sort: Brightness',
                        style: TextStyle(
                            color: widget.colors.textPrimary, fontSize: 12),
                      ),
                    ),
                    PopupMenuItem(
                      value: _AnnotationPanelSortMode.name,
                      child: Text(
                        'Sort: Name',
                        style: TextStyle(
                            color: widget.colors.textPrimary, fontSize: 12),
                      ),
                    ),
                    PopupMenuItem(
                      value: _AnnotationPanelSortMode.type,
                      child: Text(
                        'Sort: Type',
                        style: TextStyle(
                            color: widget.colors.textPrimary, fontSize: 12),
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.arrowUpDown,
                      size: 14,
                      color: widget.colors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Close button
                InkWell(
                  onTap: () => ref
                      .read(annotationPanelVisibleProvider.notifier)
                      .state = false,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              style: TextStyle(color: widget.colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search objects...',
                hintStyle:
                    TextStyle(color: widget.colors.textMuted, fontSize: 13),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 16,
                  color: widget.colors.textMuted,
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: widget.colors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.colors.primary),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Filters section
          ExpansionTile(
            initiallyExpanded: _filtersExpanded,
            onExpansionChanged: (expanded) =>
                setState(() => _filtersExpanded = expanded),
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            dense: true,
            title: Text(
              'Filters',
              style: TextStyle(
                color: widget.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Icon(
              _filtersExpanded
                  ? LucideIcons.chevronUp
                  : LucideIcons.chevronDown,
              size: 16,
              color: widget.colors.textMuted,
            ),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _QuickSettingChip(
                    label: settings.visibleTypes
                            .contains(AnnotationObjectFilter.stars)
                        ? 'Stars On'
                        : 'Stars Off',
                    isSelected: settings.visibleTypes
                        .contains(AnnotationObjectFilter.stars),
                    colors: widget.colors,
                    onTap: () {
                      unawaited(
                        ref
                            .read(annotationSettingsProvider.notifier)
                            .toggleObjectType(AnnotationObjectFilter.stars),
                      );
                    },
                  ),
                  _QuickSettingChip(
                    label: settings.showLabels ? 'Labels On' : 'Labels Off',
                    isSelected: settings.showLabels,
                    colors: widget.colors,
                    onTap: () {
                      unawaited(
                        ref
                            .read(annotationSettingsProvider.notifier)
                            .setShowLabels(!settings.showLabels),
                      );
                    },
                  ),
                  _QuickSettingChip(
                    label: settings.showMagnitudes ? 'Mag On' : 'Mag Off',
                    isSelected: settings.showMagnitudes,
                    colors: widget.colors,
                    onTap: () {
                      unawaited(
                        ref
                            .read(annotationSettingsProvider.notifier)
                            .setShowMagnitudes(!settings.showMagnitudes),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _filterTypes.map((type) {
                  final isSelected =
                      _isTypeVisibleFromSettings(type, settings.visibleTypes);
                  final count = _countForFilterType(type, typeCounts);
                  return _FilterChip(
                    label: _getObjectTypeLabel(type),
                    count: count,
                    isSelected: isSelected,
                    colors: widget.colors,
                    onTap: () {
                      final notifier =
                          ref.read(annotationSettingsProvider.notifier);
                      final updated = Set<AnnotationObjectFilter>.from(
                          settings.visibleTypes);
                      final typeFilters = _filtersForObjectType(type);
                      if (isSelected) {
                        updated.removeAll(typeFilters);
                      } else {
                        updated.addAll(typeFilters);
                      }
                      unawaited(notifier.setObjectTypes(updated));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    unawaited(
                      ref
                          .read(annotationSettingsProvider.notifier)
                          .setObjectTypes(
                        {
                          AnnotationObjectFilter.galaxies,
                          AnnotationObjectFilter.nebulae,
                          AnnotationObjectFilter.starClusters,
                          AnnotationObjectFilter.planetaryNebulae,
                        },
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset to defaults',
                    style: TextStyle(
                      color: widget.colors.primary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),

          Divider(height: 1, color: widget.colors.border),

          // Objects list
          Expanded(
            child: filteredObjects.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          annotation == null
                              ? LucideIcons.sparkle
                              : LucideIcons.searchX,
                          size: 32,
                          color: widget.colors.textMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          annotation == null
                              ? 'No image annotated'
                              : _searchQuery.isNotEmpty
                                  ? 'No matching objects'
                                  : 'No objects match filters',
                          style: TextStyle(
                            color: widget.colors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filteredObjects.length,
                    itemBuilder: (context, index) {
                      final object = filteredObjects[index];
                      return _ObjectListItem(
                        object: object,
                        colors: widget.colors,
                        onTap: () => widget.onObjectSelected(object),
                        isSelected: widget.selectedObjectId == object.id,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getObjectTypeLabel(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return 'Galaxies';
      case ObjectType.nebula:
        return 'Nebulae';
      case ObjectType.starCluster:
        return 'Clusters';
      case ObjectType.planetaryNebula:
        return 'PN';
      case ObjectType.star:
        return 'Stars';
      case ObjectType.doubleStar:
        return 'Stars';
      case ObjectType.asterism:
        return 'Asterisms';
      case ObjectType.unknown:
        return 'Other';
    }
  }

  int _countForFilterType(ObjectType type, Map<ObjectType, int> typeCounts) {
    if (type == ObjectType.star) {
      return (typeCounts[ObjectType.star] ?? 0) +
          (typeCounts[ObjectType.doubleStar] ?? 0);
    }
    if (type == ObjectType.unknown) {
      return (typeCounts[ObjectType.unknown] ?? 0) +
          (typeCounts[ObjectType.asterism] ?? 0);
    }
    return typeCounts[type] ?? 0;
  }
}

/// Filter chip for object type filtering
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.7)
                      : colors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickSettingChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _QuickSettingChip({
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.18)
              : colors.surfaceAlt.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.55)
                : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? colors.primary : colors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// List item for a celestial object
class _ObjectListItem extends StatelessWidget {
  final CelestialObjectAnnotation object;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final bool isSelected;

  const _ObjectListItem({
    required this.object,
    required this.colors,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colors.border.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Object type icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getTypeColor(object.type).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  _getTypeIcon(object.type),
                  size: 14,
                  color: _getTypeColor(object.type),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Object info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    object.commonName ?? object.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (object.commonName != null) ...[
                        Text(
                          object.name,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _getTypeShortLabel(object.type),
                        style: TextStyle(
                          color:
                              _getTypeColor(object.type).withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Magnitude
            if (object.magnitude != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'm${object.magnitude!.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return LucideIcons.disc3;
      case ObjectType.nebula:
        return LucideIcons.cloud;
      case ObjectType.starCluster:
        return LucideIcons.sparkles;
      case ObjectType.planetaryNebula:
        return LucideIcons.circle;
      case ObjectType.star:
        return LucideIcons.star;
      case ObjectType.doubleStar:
        return LucideIcons.gitMerge;
      case ObjectType.asterism:
        return LucideIcons.shapes;
      case ObjectType.unknown:
        return LucideIcons.helpCircle;
    }
  }

  Color _getTypeColor(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return const Color(0xFFE879F9); // Purple/Pink for galaxies
      case ObjectType.nebula:
        return const Color(0xFF60A5FA); // Blue for nebulae
      case ObjectType.starCluster:
        return const Color(0xFFFBBF24); // Yellow for clusters
      case ObjectType.planetaryNebula:
        return const Color(0xFF34D399); // Green for planetary nebulae
      case ObjectType.star:
        return const Color(0xFFFFF7ED); // Warm white for stars
      case ObjectType.doubleStar:
        return const Color(0xFFF472B6); // Pink for double stars
      case ObjectType.asterism:
        return const Color(0xFFA78BFA); // Violet for asterisms
      case ObjectType.unknown:
        return const Color(0xFF9CA3AF); // Gray for unknown
    }
  }

  String _getTypeShortLabel(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return 'Galaxy';
      case ObjectType.nebula:
        return 'Nebula';
      case ObjectType.starCluster:
        return 'Cluster';
      case ObjectType.planetaryNebula:
        return 'PN';
      case ObjectType.star:
        return 'Star';
      case ObjectType.doubleStar:
        return 'Double';
      case ObjectType.asterism:
        return 'Asterism';
      case ObjectType.unknown:
        return 'Unknown';
    }
  }
}
