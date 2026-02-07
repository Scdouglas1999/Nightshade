// ignore_for_file: unused_local_variable

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/astro_image_viewer.dart';
import '../../../widgets/capture_settings_panel.dart';

class CaptureTab extends ConsumerStatefulWidget {
  const CaptureTab({super.key});

  @override
  ConsumerState<CaptureTab> createState() => _CaptureTabState();
}

class _CaptureTabState extends ConsumerState<CaptureTab> {
  // UI-only local state (these don't need to persist across navigation)
  bool _autoStretch = true;
  bool _showCrosshair = true;
  bool _showGrid = false;

  // Zoom control state
  final GlobalKey<_ImageDisplayState> _imageDisplayKey =
      GlobalKey<_ImageDisplayState>();
  double _currentZoomLevel = 1.0;
  ZoomMode _currentZoomMode = ZoomMode.fit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMobile = Responsive.isMobile(context);

    // Watch the current image
    final currentImage = ref.watch(currentImageProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    // Derive capture state from exposureProgress (single source of truth)
    final isCapturing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;

    // Mobile layout: Stack vertically
    if (isMobile) {
      return _buildMobileLayout(
        context: context,
        colors: colors,
        currentImage: currentImage,
        exposureProgress: exposureProgress,
        lastStats: lastStats,
        isConnected: isConnected,
      );
    }

    // Desktop layout: Side-by-side
    return Row(
      children: [
        // Main image view (70%)
        Expanded(
          flex: 7,
          child: Column(
            children: [
              // Image canvas
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Stack(
                    children: [
                      // Image display
                      if (currentImage != null)
                        _ImageDisplay(
                          key: _imageDisplayKey,
                          imageData: currentImage,
                          colors: colors,
                          onZoomChanged: (scale, mode) {
                            setState(() {
                              _currentZoomLevel = scale;
                              _currentZoomMode = mode;
                            });
                          },
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.image,
                                size: 64,
                                color: colors.textMuted,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No image captured',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isConnected
                                    ? 'Take an exposure to see preview here'
                                    : 'Connect a camera first',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Crosshair overlay
                      if (_showCrosshair)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CrosshairPainter(
                                color: colors.primary.withValues(alpha: 0.3)),
                          ),
                        ),

                      // Exposure progress overlay
                      if (exposureProgress.percent > 0 ||
                          exposureProgress.isDownloading)
                        _ExposureProgressOverlay(
                          progress: exposureProgress,
                          colors: colors,
                        ),

                      // Zoom controls
                      if (currentImage != null)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              children: [
                                _IconButton(
                                  icon: LucideIcons.zoomIn,
                                  tooltip: 'Zoom In',
                                  onPressed: () =>
                                      _imageDisplayKey.currentState?.zoomIn(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.zoomOut,
                                  tooltip: 'Zoom Out',
                                  onPressed: () =>
                                      _imageDisplayKey.currentState?.zoomOut(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.maximize2,
                                  tooltip: 'Fit to Screen',
                                  isActive: _currentZoomMode == ZoomMode.fit,
                                  onPressed: () => _imageDisplayKey.currentState
                                      ?.fitToScreen(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.square,
                                  tooltip: '1:1 (100%)',
                                  isActive:
                                      _currentZoomMode == ZoomMode.oneToOne,
                                  onPressed: () =>
                                      _imageDisplayKey.currentState?.oneToOne(),
                                ),
                                if (_currentZoomLevel != 1.0) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${(_currentZoomLevel * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: colors.primary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                // Divider and plate solve button
                                const SizedBox(height: 8),
                                Container(
                                  height: 1,
                                  width: 24,
                                  color: colors.border,
                                ),
                                const SizedBox(height: 8),
                                _IconButton(
                                  icon: LucideIcons.sparkles,
                                  tooltip: 'Plate Solve Image',
                                  onPressed: currentImage.filePath != null
                                      ? () => _handlePlateSolve(currentImage)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom stats row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    // Image stats
                    Expanded(
                      child: NightshadeCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Image Stats',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: 'HFR',
                                    value: lastStats?.hfr?.toStringAsFixed(2) ??
                                        '---',
                                  ),
                                  _StatItem(
                                    label: 'Stars',
                                    value: lastStats?.starCount?.toString() ??
                                        '---',
                                  ),
                                  _StatItem(
                                    label: 'Mean',
                                    value:
                                        lastStats?.mean?.toStringAsFixed(0) ??
                                            '---',
                                  ),
                                  _StatItem(
                                    label: 'Median',
                                    value:
                                        lastStats?.median?.toStringAsFixed(0) ??
                                            '---',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Histogram
                    Expanded(
                      child: NightshadeCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Histogram',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: colors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: HistogramDisplay(
                                  histogram: currentImage?.histogram,
                                  height: 40,
                                  barColor: colors.primary,
                                  logarithmic: true,
                                  showGrid: false,
                                  showClipping: true,
                                  allowLogToggle: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Annotations
                    NightshadeCard(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Annotations',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Consumer(
                              builder: (context, ref, _) {
                                final annotationSettings =
                                    ref.watch(annotationSettingsProvider);
                                final settings =
                                    annotationSettings.valueOrNull ??
                                        const AnnotationSettings();
                                final showStars = settings.visibleTypes
                                    .contains(AnnotationObjectFilter.stars);

                                // Use Wrap to prevent overflow on narrow screens
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        ref
                                            .read(annotationSettingsProvider
                                                .notifier)
                                            .toggleObjectType(
                                                AnnotationObjectFilter.stars);
                                      },
                                      child: _ToggleChip(
                                          label: 'Stars', isActive: showStars),
                                    ),
                                    GestureDetector(
                                      onTap: () => setState(
                                          () => _showGrid = !_showGrid),
                                      child: _ToggleChip(
                                          label: 'Grid', isActive: _showGrid),
                                    ),
                                    GestureDetector(
                                      onTap: () => setState(() =>
                                          _showCrosshair = !_showCrosshair),
                                      child: _ToggleChip(
                                          label: 'Crosshair',
                                          isActive: _showCrosshair),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right sidebar - Capture controls
        SizedBox(
          width: Responsive.value(context,
              mobile: 280.0, tablet: 300.0, desktop: 320.0),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                left: BorderSide(color: colors.border, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildSidebarContent(colors, currentImage),
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile layout: Stacked vertically with scrollable content
  Widget _buildMobileLayout({
    required BuildContext context,
    required NightshadeColors colors,
    required CapturedImageData? currentImage,
    required ExposureProgress exposureProgress,
    required ImageStats? lastStats,
    required bool isConnected,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image display area (fixed height on mobile)
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Stack(
              children: [
                // Image display
                if (currentImage != null)
                  _ImageDisplay(
                    key: _imageDisplayKey,
                    imageData: currentImage,
                    colors: colors,
                    onZoomChanged: (scale, mode) {
                      setState(() {
                        _currentZoomLevel = scale;
                        _currentZoomMode = mode;
                      });
                    },
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.image,
                          size: 48,
                          color: colors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isConnected
                              ? 'No image captured'
                              : 'Connect a camera first',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Crosshair overlay
                if (_showCrosshair)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CrosshairPainter(
                          color: colors.primary.withValues(alpha: 0.3)),
                    ),
                  ),

                // Exposure progress overlay
                if (exposureProgress.percent > 0 ||
                    exposureProgress.isDownloading)
                  _ExposureProgressOverlay(
                    progress: exposureProgress,
                    colors: colors,
                  ),

                // Zoom controls (mobile-friendly position)
                if (currentImage != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _IconButton(
                          icon: LucideIcons.zoomOut,
                          tooltip: 'Zoom Out',
                          onPressed: () =>
                              _imageDisplayKey.currentState?.zoomOut(),
                        ),
                        const SizedBox(width: 4),
                        _IconButton(
                          icon: LucideIcons.zoomIn,
                          tooltip: 'Zoom In',
                          onPressed: () =>
                              _imageDisplayKey.currentState?.zoomIn(),
                        ),
                        const SizedBox(width: 4),
                        _IconButton(
                          icon: LucideIcons.maximize2,
                          tooltip: 'Fit to Screen',
                          isActive: _currentZoomMode == ZoomMode.fit,
                          onPressed: () =>
                              _imageDisplayKey.currentState?.fitToScreen(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Stats row (horizontal on mobile)
          Row(
            children: [
              Expanded(
                child: _CompactStatCard(
                  label: 'HFR',
                  value: lastStats?.hfr?.toStringAsFixed(2) ?? '---',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactStatCard(
                  label: 'Stars',
                  value: lastStats?.starCount?.toString() ?? '---',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactStatCard(
                  label: 'Median',
                  value: lastStats?.median?.toStringAsFixed(0) ?? '---',
                  colors: colors,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Histogram (full width on mobile)
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Histogram',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: HistogramDisplay(
                      histogram: currentImage?.histogram,
                      height: 50,
                      barColor: colors.primary,
                      logarithmic: true,
                      showGrid: false,
                      showClipping: true,
                      allowLogToggle: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Capture settings (full width on mobile)
          _buildSidebarContent(colors, currentImage),
        ],
      ),
    );
  }

  /// Shared sidebar content for both mobile and desktop
  Widget _buildSidebarContent(
      NightshadeColors colors, CapturedImageData? currentImage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CaptureSettingsPanel(
          showHeader: true,
          showConnectionBadge: true,
        ),

        const SizedBox(height: 24),

        // Options
        Row(
          children: [
            NightshadeCheckbox(
              value: _autoStretch,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _autoStretch = value);
                }
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Auto-stretch',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            NightshadeCheckbox(
              value: _showCrosshair,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _showCrosshair = value);
                }
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Show crosshair',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Session info
        if (currentImage != null) ...[
          Text(
            'Last Capture',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                    label: 'Size',
                    value: '${currentImage.width} × ${currentImage.height}'),
                const SizedBox(height: 4),
                _InfoRow(
                    label: 'Exposure',
                    value: '${currentImage.settings.exposureTime}s'),
                const SizedBox(height: 4),
                _InfoRow(
                    label: 'Frame',
                    value: currentImage.settings.frameType.displayName),
                const SizedBox(height: 4),
                _InfoRow(
                    label: 'Time', value: _formatTime(currentImage.capturedAt)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  Future<void> _handlePlateSolve(CapturedImageData image) async {
    if (image.filePath == null) {
      context.showErrorSnackBar('No image file to plate solve');
      return;
    }

    // Show solving indicator via snackbar
    context.showInfoSnackBar('Plate solving...');

    try {
      final plateSolveService = ref.read(plateSolveServiceProvider);
      final appSettings = ref.read(appSettingsProvider).valueOrNull;
      final mountState = ref.read(mountStateProvider);

      // Find ASTAP executable
      final executablePath =
          await PlateSolverUtils.findAstapExecutable(appSettings?.astapPath);

      final config = PlateSolverConfig(
        type: PlateSolverType.astap,
        executablePath: executablePath ?? '',
        timeoutSeconds: 60,
        searchRadius: 30.0,
        // Use mount position as hint if available
        hintRa: mountState.connectionState == DeviceConnectionState.connected
            ? mountState.ra
            : null,
        hintDec: mountState.connectionState == DeviceConnectionState.connected
            ? mountState.dec
            : null,
      );

      final result = await plateSolveService.solve(image.filePath!, config);

      if (!mounted) return;

      if (result.success) {
        final raText = result.ra?.toStringAsFixed(4) ?? '?';
        final decText = result.dec?.toStringAsFixed(4) ?? '?';
        final rotText = result.rotation?.toStringAsFixed(1) ?? '?';
        context.showSuccessSnackBar(
          'Solved: RA ${raText}h, Dec $decText°, Rotation $rotText°',
        );
      } else {
        context.showErrorSnackBar(
            'Plate solve failed: ${result.errorMessage ?? "Unknown error"}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Plate solve error: $e');
      }
    }
  }
}

/// Zoom mode enumeration
enum ZoomMode {
  fit, // Fit to screen
  oneToOne, // 1:1 pixel mapping
  custom, // User-controlled zoom
}

/// Image display with zoom/pan support for both color and mono images
class _ImageDisplay extends StatefulWidget {
  final CapturedImageData imageData;
  final NightshadeColors colors;
  final Function(double scale, ZoomMode mode)? onZoomChanged;

  const _ImageDisplay({
    super.key,
    required this.imageData,
    required this.colors,
    this.onZoomChanged,
  });

  @override
  State<_ImageDisplay> createState() => _ImageDisplayState();
}

class _ImageDisplayState extends State<_ImageDisplay> {
  late TransformationController _controller;
  ZoomMode _currentMode = ZoomMode.fit;
  double _currentScale = 1.0;

  // Store the container key for getting size
  final GlobalKey _containerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _controller.addListener(_onTransformChanged);

    // Initialize to fit mode after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fitToScreen();
    });
  }

  @override
  void didUpdateWidget(_ImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the image changed, reset to fit mode
    if (oldWidget.imageData != widget.imageData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentMode == ZoomMode.fit) {
          fitToScreen();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale != _currentScale) {
      setState(() {
        _currentScale = scale;
      });
      widget.onZoomChanged?.call(scale, _currentMode);
    }
  }

  Size? _getContainerSize() {
    final renderBox =
        _containerKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size;
  }

  /// Zoom in by 25%
  void zoomIn() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.25).clamp(0.1, 10.0);
    _setScale(newScale, ZoomMode.custom);
  }

  /// Zoom out by 25%
  void zoomOut() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.25).clamp(0.1, 10.0);
    _setScale(newScale, ZoomMode.custom);
  }

  /// Fit image to screen while maintaining aspect ratio
  void fitToScreen() {
    final containerSize = _getContainerSize();
    if (containerSize == null) return;

    final imageWidth = widget.imageData.width.toDouble();
    final imageHeight = widget.imageData.height.toDouble();

    // Calculate scale to fit
    final scaleX = containerSize.width / imageWidth;
    final scaleY = containerSize.height / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the image
    final scaledWidth = imageWidth * scale;
    final scaledHeight = imageHeight * scale;
    final offsetX = (containerSize.width - scaledWidth) / 2;
    final offsetY = (containerSize.height - scaledHeight) / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(offsetX, offsetY, 0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);

    _controller.value = matrix;
    setState(() {
      _currentMode = ZoomMode.fit;
      _currentScale = scale;
    });
    widget.onZoomChanged?.call(scale, ZoomMode.fit);
  }

  /// Display at 1:1 pixel ratio (100% zoom)
  void oneToOne() {
    final containerSize = _getContainerSize();
    if (containerSize == null) return;

    final imageWidth = widget.imageData.width.toDouble();
    final imageHeight = widget.imageData.height.toDouble();

    // Center the image at 1:1 scale
    final offsetX = (containerSize.width - imageWidth) / 2;
    final offsetY = (containerSize.height - imageHeight) / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(offsetX, offsetY, 0, 1.0)
      ..scaleByDouble(1.0, 1.0, 1.0, 1.0);

    _controller.value = matrix;
    setState(() {
      _currentMode = ZoomMode.oneToOne;
      _currentScale = 1.0;
    });
    widget.onZoomChanged?.call(1.0, ZoomMode.oneToOne);
  }

  /// Set a specific scale level
  void _setScale(double scale, ZoomMode mode) {
    final containerSize = _getContainerSize();
    if (containerSize == null) return;

    // Get current center point
    final currentMatrix = _controller.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    // Calculate current center in image coordinates
    final centerX =
        (containerSize.width / 2 - currentMatrix.getTranslation().x) /
            currentScale;
    final centerY =
        (containerSize.height / 2 - currentMatrix.getTranslation().y) /
            currentScale;

    // Calculate new offset to maintain center point
    final offsetX = containerSize.width / 2 - centerX * scale;
    final offsetY = containerSize.height / 2 - centerY * scale;

    final matrix = Matrix4.identity()
      ..translateByDouble(offsetX, offsetY, 0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);

    _controller.value = matrix;
    setState(() {
      _currentMode = mode;
      _currentScale = scale;
    });
    widget.onZoomChanged?.call(scale, mode);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: _containerKey,
      builder: (context, constraints) {
        // Use a custom InteractiveViewer with our controller
        return _ControllableImageViewer(
          controller: _controller,
          imageData: widget.imageData,
        );
      },
    );
  }
}

/// Image viewer with external zoom control via TransformationController
class _ControllableImageViewer extends StatelessWidget {
  final TransformationController controller;
  final CapturedImageData imageData;

  const _ControllableImageViewer({
    required this.controller,
    required this.imageData,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final currentScale = controller.value.getMaxScaleOnAxis();
          final delta = event.scrollDelta.dy;
          final scaleFactor = delta > 0 ? 0.9 : 1.1;
          final newScale = (currentScale * scaleFactor).clamp(0.1, 10.0);

          if (newScale != currentScale) {
            final focalPoint = event.localPosition;
            final scaleChange = newScale / currentScale;

            final matrix = Matrix4.identity()
              ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1.0)
              ..scaleByDouble(scaleChange, scaleChange, 1.0, 1.0)
              ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1.0);

            controller.value = matrix * controller.value;
          }
        }
      },
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 0.1,
        maxScale: 10.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        constrained: false,
        child: Center(
          child: AstroImageViewer(
            imageData: imageData.displayData,
            width: imageData.width,
            height: imageData.height,
            isColor: imageData.isColor,
            minScale:
                1.0, // Disable internal scaling (we handle it via outer InteractiveViewer)
            maxScale: 1.0,
            enableInteraction:
                false, // Disable internal interaction (we handle it via outer InteractiveViewer)
          ),
        ),
      ),
    );
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
    final progressValue = progress.percent / 100.0;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: progressValue,
                  strokeWidth: 4,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
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
                  '${progress.percent.toStringAsFixed(0)}% (${progress.remaining.toStringAsFixed(1)}s remaining)',
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
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;

  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  const _IconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Use 44x44 minimum touch target for accessibility compliance
    final button = Material(
      color: isActive ? colors.primary.withValues(alpha: 0.1) : colors.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive ? colors.primary : colors.border,
              width: isActive ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
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
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;

  const _ToggleChip({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? colors.primary : colors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isActive ? colors.primary : colors.textSecondary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Compact stat card for mobile layout
class _CompactStatCard extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CompactStatCard({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
