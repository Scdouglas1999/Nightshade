part of '../imaging_screen.dart';

extension _ImagingScreenActions on _ImagingScreenState {
  /// Initialize the annotation service so it starts listening for new images
  void _initializeAnnotationService() {
    // Reading the provider creates the AnnotationService instance
    // which sets up the listener for currentImageProvider
    ref.read(annotationServiceProvider);
    ref.read(loggingServiceProvider).info(
        '[Imaging] AnnotationService initialized',
        source: 'ImagingScreen');
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
    final colors = context.nightshadeColors;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(LucideIcons.sparkles, color: colors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Annotation Catalogs Required',
                style: TextStyle(color: colors.textPrimary, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Annotations are enabled but no object catalogs are installed yet. '
          'Download the annotation catalog to automatically identify galaxies, '
          'nebulae, and other objects in your images.\n\n'
          'This only takes a moment and greatly enhances your imaging experience.',
          style:
              TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
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
                    constraints: AdaptiveDialogConstraints.hybrid(
                      context,
                      designMaxWidth: 800,
                      designMaxHeight: 700,
                    ),
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

  // =========================================================================
  // CAPTURE ACTIONS
  // =========================================================================

  Future<void> _takeSnapshot() async {
    if (_isSingleCapture || _isLooping) return;

    _update(() => _isSingleCapture = true);

    final settings = ref.read(exposureSettingsProvider);
    final imagingService = ref.read(imagingServiceProvider);
    final sessionNotifier = ref.read(sessionStateProvider.notifier);

    sessionNotifier.setCapturing(true);

    // IMG-P1-5: flip the button label back to "Snapshot" as soon as the
    // imaging service publishes the preview image, even though FITS
    // save, auto-calibration, and science processing keep running in
    // the background after that. Without this listener the button
    // stayed on "Taking…" for the full save+calibration cycle — long
    // after the user could see and inspect the frame.
    //
    // We baseline against the `capturedAt` of whatever was on screen
    // when the snapshot started so an idle, never-changing image (or a
    // stale frame from a previous session) doesn't immediately trip
    // the reset.
    final baselineCapturedAt = ref.read(currentImageProvider)?.capturedAt;
    var previewSeen = false;
    final previewSubscription = ref.listenManual<CapturedImageData?>(
      currentImageProvider,
      (previous, next) {
        if (previewSeen) return;
        if (next == null) return;
        if (next.capturedAt == baselineCapturedAt) return;
        previewSeen = true;
        if (!mounted) return;
        // Pop the button out of "Taking…" the instant the preview
        // surfaces. The session-level `capturing` flag (used by other
        // UI like the global capture chip) stays on until the whole
        // pipeline finishes in the outer try/finally below — we don't
        // want to mislead other surfaces that the work is done.
        _update(() => _isSingleCapture = false);
      },
      // We don't care about the initial value, only future writes.
      fireImmediately: false,
    );

    try {
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
      previewSubscription.close();
      if (mounted) {
        // Safety net: if the capture failed before the preview was
        // ever published (e.g. camera throw, abort), flip the button
        // back here. When the listener already reset the flag this is
        // a no-op setState that just rebuilds with the same state.
        if (_isSingleCapture) {
          _update(() => _isSingleCapture = false);
        }
        ref.read(sessionStateProvider.notifier).setCapturing(false);
      }
    }
  }

  Future<void> _toggleLoop() async {
    if (_isSingleCapture) return;

    if (_isLooping) {
      // Stop looping
      _update(() => _isLooping = false);
      ref.read(imagingServiceProvider).cancelExposure();
      return;
    }

    _update(() => _isLooping = true);
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
        _update(() => _isLooping = false);
        ref.read(sessionStateProvider.notifier).setCapturing(false);
      }
    }
  }

  void _abortCapture() {
    ref.read(imagingServiceProvider).cancelExposure();
    _update(() {
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
}
