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
import 'widgets/capture_panel.dart';
import 'widgets/camera_panel.dart';
import 'widgets/focus_panel.dart';
import 'widgets/guiding_panel.dart';
import 'widgets/live_preview_area.dart';
import 'widgets/panel_widgets.dart';
import 'widgets/rotator_panel.dart';
import 'widgets/stacking_panel.dart';
import '../../widgets/filter_wheel_selector.dart';
import '../../widgets/tutorial_keys/imaging_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

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
final _catalogDialogShownThisSessionProvider = StateProvider<bool>((ref) => false);

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

  /// Persist the catalog prompt dismissal to DB so it only shows once ever
  Future<void> _dismissCatalogPrompt() async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting('annotation_catalog_prompt_dismissed', 'true');
    ref.invalidate(annotationBannerDismissedProvider);
  }

  /// On first capture with annotations enabled but no catalogs, show a dialog.
  ///
  /// Driven by `ref.listen(annotationStateProvider, ...)` in `build`, which
  /// fires only on actual provider transitions instead of on every rebuild —
  /// this prevents duplicate dialogs from window-resize storms / hot-reload
  /// rebuilds (audit §4.3).
  void _maybeShowFirstUseCatalogPrompt(AnnotationState annotationState) {
    if (annotationState.status != AnnotationStatus.catalogsNotInstalled) return;

    // Only show once per session
    final shownThisSession = ref.read(_catalogDialogShownThisSessionProvider);
    if (shownThisSession) return;

    // Check if the prompt was permanently dismissed
    final dismissed =
        ref.read(annotationBannerDismissedProvider).valueOrNull ?? false;
    if (dismissed) return;

    // Mark as shown this session immediately to prevent re-triggering
    ref.read(_catalogDialogShownThisSessionProvider.notifier).state = true;

    // Defer the dialog so we don't open it inside the listener callback,
    // which can fire mid-frame when other providers transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showFirstUseCatalogDialog();
    });
  }

  void _showFirstUseCatalogDialog() {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(LucideIcons.sparkles, color: colors.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Annotation Catalogs Required',
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Annotations are enabled but no object catalogs are installed yet. '
          'Download the annotation catalog to automatically identify galaxies, '
          'nebulae, and other objects in your images.\n\n'
          'This only takes a moment and greatly enhances your imaging experience.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          NightshadeButton(
            label: 'Not Now',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () {
              _dismissCatalogPrompt();
              Navigator.of(dialogContext).pop();
            },
          ),
          NightshadeButton(
            label: 'Download Catalogs',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () {
              _dismissCatalogPrompt();
              Navigator.of(dialogContext).pop();
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
                ref.invalidate(annotationCatalogInstalledProvider);
              });
            },
          ),
        ],
      ),
    );
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
        _feedToLiveStacker(result);
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
              _feedToLiveStacker(image);
            }
          },
          onError: (error) {
            if (!mounted) return;
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

  /// Feed a newly captured frame to the live stacker if stacking is active.
  ///
  /// Uses the saved file path when available (preferred, avoids sending raw
  /// pixel data over FFI twice). Silently skips when stacking is not running.
  void _feedToLiveStacker(CapturedImageData image) {
    final isActive = ref.read(liveStackingIsActiveProvider);
    if (!isActive) return;

    final filePath = image.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      // Fire-and-forget: the notifier logs warnings on rejection
      ref.read(liveStackingProvider.notifier).addFrameFromFile(filePath);
    }
  }

  // =========================================================================
  // ZOOM/PAN CONTROLS — delegates to imagingViewerStateProvider so window
  // navigation and rebuilds don't reset the user's view (audit §4.10).
  // =========================================================================

  ImagingViewerStateNotifier get _viewer =>
      ref.read(imagingViewerStateProvider.notifier);

  void _zoomIn() => _viewer.zoomIn();
  void _zoomOut() => _viewer.zoomOut();
  void _fitToWindow() => _viewer.fitToWindow();
  void _zoom1to1() => _viewer.zoom1to1();
  void _panPreview(Offset delta) => _viewer.pan(delta);

  @override
  Widget build(BuildContext context) {
    // Sync snapshot exposure defaults from the active equipment profile
    ref.watch(syncExposureFromProfileProvider);

    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
        // Live preview area (compact on mobile)
        Expanded(
          flex: 4,
          child: LivePreviewArea(
            key: ImagingTutorialKeys.previewArea,
            colors: colors,
            zoomLevel: viewerState.zoomLevel,
            panOffset: viewerState.panOffset,
            showCrosshair: viewerState.showCrosshair,
            showGrid: viewerState.showGrid,
            showStarOverlay: viewerState.showStarOverlay,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onFitToWindow: _fitToWindow,
            onZoom1to1: _zoom1to1,
            onAbortCapture: _abortCapture,
            onPanUpdate: _panPreview,
            onToggleCrosshair: _viewer.toggleCrosshair,
            onToggleGrid: _viewer.toggleGrid,
            onToggleStarOverlay: _viewer.toggleStarOverlay,
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
                        CameraPanel(colors: colors),
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
          child: Column(
            children: [
              // Live preview area
              Expanded(
                flex: 6,
                child: LivePreviewArea(
                  key: ImagingTutorialKeys.previewArea,
                  colors: colors,
                  zoomLevel: viewerState.zoomLevel,
                  panOffset: viewerState.panOffset,
                  showCrosshair: viewerState.showCrosshair,
                  showGrid: viewerState.showGrid,
                  showStarOverlay: viewerState.showStarOverlay,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onFitToWindow: _fitToWindow,
                  onZoom1to1: _zoom1to1,
                  onAbortCapture: _abortCapture,
                  onPanUpdate: _panPreview,
                  onToggleCrosshair: _viewer.toggleCrosshair,
                  onToggleGrid: _viewer.toggleGrid,
                  onToggleStarOverlay: _viewer.toggleStarOverlay,
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
                        CameraPanel(colors: colors),
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
                ControlSection(
                  title: 'Capture',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: BigActionButton(
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
                  title: 'Exposure',
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: EditableCompactInput(
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

        // On larger screens, use a wrapping grid so Capture / Exposure /
        // Filter / Display / Stats flow onto a second line when horizontal
        // space is tight. Replaces the previous SingleChildScrollView, which
        // silently scrolled the Capture buttons offscreen on narrow desktop
        // windows (audit §4.9).
        final wrapSpacing = sectionSpacing;
        final sections = <Widget>[
          ControlSection(
            title: 'Capture',
            colors: colors,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BigActionButton(
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
          ),
          ControlSection(
            title: 'Exposure',
            colors: colors,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EditableCompactInput(
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
          ),
          ControlSection(
            title: 'Filter',
            colors: colors,
            child: FilterWheelSelector(
              key: ImagingTutorialKeys.filterSelector,
              style: FilterSelectorStyle.buttons,
              compact: isMobile,
            ),
          ),
          ControlSection(
            title: 'Display',
            colors: colors,
            child: const StretchControls(compact: true),
          ),
          if (!isMobile)
            // Quick stats with live data (hide on mobile to save space)
            QuickStatsPanel(colors: colors),
        ];

        return Padding(
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding, vertical: verticalPadding),
          child: Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapSpacing,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: sections,
          ),
        );
      },
    );
  }
}
