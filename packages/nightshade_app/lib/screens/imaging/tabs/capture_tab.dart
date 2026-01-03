import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../widgets/astro_image_viewer.dart';

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
  bool _isLooping = false;

  // Zoom control state
  final GlobalKey<_ImageDisplayState> _imageDisplayKey = GlobalKey<_ImageDisplayState>();
  double _currentZoomLevel = 1.0;
  ZoomMode _currentZoomMode = ZoomMode.fit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch the current image
    final currentImage = ref.watch(currentImageProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);
    // Watch exposure settings from provider (persists across navigation)
    final exposureSettings = ref.watch(exposureSettingsProvider);

    final isConnected = cameraState.connectionState == DeviceConnectionState.connected;
    // Derive capture state from exposureProgress (single source of truth)
    final isCapturing = exposureProgress.percent > 0 || exposureProgress.isDownloading;

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
                            painter: _CrosshairPainter(color: colors.primary.withValues(alpha: 0.3)),
                          ),
                        ),

                      // Exposure progress overlay
                      if (exposureProgress.percent > 0 || exposureProgress.isDownloading)
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
                                  onPressed: () => _imageDisplayKey.currentState?.zoomIn(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.zoomOut,
                                  tooltip: 'Zoom Out',
                                  onPressed: () => _imageDisplayKey.currentState?.zoomOut(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.maximize2,
                                  tooltip: 'Fit to Screen',
                                  isActive: _currentZoomMode == ZoomMode.fit,
                                  onPressed: () => _imageDisplayKey.currentState?.fitToScreen(),
                                ),
                                const SizedBox(height: 4),
                                _IconButton(
                                  icon: LucideIcons.square,
                                  tooltip: '1:1 (100%)',
                                  isActive: _currentZoomMode == ZoomMode.oneToOne,
                                  onPressed: () => _imageDisplayKey.currentState?.oneToOne(),
                                ),
                                if (_currentZoomLevel != 1.0) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${(_currentZoomLevel * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: colors.primary,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                ],
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
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: 'HFR',
                                    value: lastStats?.hfr?.toStringAsFixed(2) ?? '---',
                                  ),
                                  _StatItem(
                                    label: 'Stars',
                                    value: lastStats?.starCount?.toString() ?? '---',
                                  ),
                                  _StatItem(
                                    label: 'Mean',
                                    value: lastStats?.mean?.toStringAsFixed(0) ?? '---',
                                  ),
                                  _StatItem(
                                    label: 'Median',
                                    value: lastStats?.median?.toStringAsFixed(0) ?? '---',
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
                                final annotationSettings = ref.watch(annotationSettingsProvider);
                                final settings = annotationSettings.valueOrNull ?? const AnnotationSettings();
                                final showStars = settings.visibleTypes.contains(AnnotationObjectFilter.stars);

                                return Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        ref.read(annotationSettingsProvider.notifier)
                                            .toggleObjectType(AnnotationObjectFilter.stars);
                                      },
                                      child: _ToggleChip(label: 'Stars', isActive: showStars),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(() => _showGrid = !_showGrid),
                                      child: _ToggleChip(label: 'Grid', isActive: _showGrid),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(() => _showCrosshair = !_showCrosshair),
                                      child: _ToggleChip(label: 'Crosshair', isActive: _showCrosshair),
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

        // Right sidebar - Capture controls (30%)
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              left: BorderSide(color: colors.border, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Capture Controls',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (!isConnected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.alertCircle, size: 12, color: colors.warning),
                            const SizedBox(width: 4),
                            Text(
                              'No camera',
                              style: TextStyle(fontSize: 10, color: colors.warning),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Exposure
                _ControlRow(
                  label: 'Exposure',
                  child: Row(
                    children: [
                      Expanded(
                        child: NightshadeTextField(
                          initialValue: exposureSettings.exposureTime.toString(),
                          onChanged: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null && parsed > 0) {
                              ref.read(exposureSettingsProvider.notifier).state =
                                  exposureSettings.copyWith(exposureTime: parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'sec',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Gain
                _ControlRow(
                  label: 'Gain',
                  child: NightshadeTextField(
                    initialValue: exposureSettings.gain.toString(),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed >= 0) {
                        ref.read(exposureSettingsProvider.notifier).state =
                            exposureSettings.copyWith(gain: parsed);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Offset
                _ControlRow(
                  label: 'Offset',
                  child: NightshadeTextField(
                    initialValue: exposureSettings.offset.toString(),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed >= 0) {
                        ref.read(exposureSettingsProvider.notifier).state =
                            exposureSettings.copyWith(offset: parsed);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Binning
                _ControlRow(
                  label: 'Binning',
                  child: NightshadeDropdown(
                    value: exposureSettings.binning,
                    items: const ['1x1', '2x2', '3x3', '4x4'],
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
                ),

                const SizedBox(height: 12),

                // Frame Type
                _ControlRow(
                  label: 'Frame',
                  child: NightshadeDropdown(
                    value: exposureSettings.frameType.displayName,
                    items: FrameType.values.map((t) => t.displayName).toList(),
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
                ),

                const SizedBox(height: 12),

                // Filter
                _ControlRow(
                  label: 'Filter',
                  child: NightshadeDropdown(
                    value: exposureSettings.filter ?? 'L',
                    items: const ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(exposureSettingsProvider.notifier).state =
                            exposureSettings.copyWith(filter: value);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Capture buttons
                Row(
                  children: [
                    Expanded(
                      child: NightshadeButton(
                        label: isCapturing ? (exposureProgress.isDownloading ? 'Downloading...' : 'Capturing...') : 'Capture',
                        icon: isCapturing ? LucideIcons.loader2 : LucideIcons.camera,
                        size: ButtonSize.large,
                        onPressed: (!isConnected || isCapturing) ? null : _captureImage,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: NightshadeButton(
                        label: _isLooping ? 'Looping...' : 'Loop',
                        icon: LucideIcons.repeat,
                        variant: _isLooping ? ButtonVariant.primary : ButtonVariant.outline,
                        onPressed: (!isConnected || isCapturing) ? null : _toggleLoop,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NightshadeButton(
                        label: 'Abort',
                        icon: LucideIcons.x,
                        variant: ButtonVariant.outline,
                        onPressed: (isCapturing || _isLooping) ? _abortCapture : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Options
                Row(
                  children: [
                    NightshadeCheckbox(
                      value: _autoStretch,
                      onChanged: (value) => setState(() => _autoStretch = value ?? true),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Auto-stretch',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    NightshadeCheckbox(
                      value: _showCrosshair,
                      onChanged: (value) => setState(() => _showCrosshair = value ?? true),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Show crosshair',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
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
                        _InfoRow(label: 'Size', value: '${currentImage.width} × ${currentImage.height}'),
                        const SizedBox(height: 4),
                        _InfoRow(label: 'Exposure', value: '${currentImage.settings.exposureTime}s'),
                        const SizedBox(height: 4),
                        _InfoRow(label: 'Frame', value: currentImage.settings.frameType.displayName),
                        const SizedBox(height: 4),
                        _InfoRow(label: 'Time', value: _formatTime(currentImage.capturedAt)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _captureImage() async {
    // Note: capture state is now tracked via exposureProgressProvider (single source of truth)
    // The imaging service updates exposureProgressProvider automatically
    try {
      final imagingService = ref.read(imagingServiceProvider);
      // Get settings from provider (persists across navigation)
      final settings = ref.read(exposureSettingsProvider);

      final result = await imagingService.captureImage(settings: settings);

      if (result != null && mounted) {
        ref.read(currentImageProvider.notifier).state = result;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: Theme.of(context).extension<NightshadeColors>()!.error,
          ),
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
    setState(() {
      _isLooping = false;
    });
    ref.read(imagingServiceProvider).cancelExposure();
    // exposureProgressProvider will be reset by the imaging service
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

/// Zoom mode enumeration
enum ZoomMode {
  fit,       // Fit to screen
  oneToOne,  // 1:1 pixel mapping
  custom,    // User-controlled zoom
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

  // Store the container size for calculations
  Size? _containerSize;
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
    final renderBox = _containerKey.currentContext?.findRenderObject() as RenderBox?;
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
      ..translate(offsetX, offsetY)
      ..scale(scale);

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
      ..translate(offsetX, offsetY)
      ..scale(1.0);

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

    final imageWidth = widget.imageData.width.toDouble();
    final imageHeight = widget.imageData.height.toDouble();

    // Get current center point
    final currentMatrix = _controller.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    // Calculate current center in image coordinates
    final centerX = (containerSize.width / 2 - currentMatrix.getTranslation().x) / currentScale;
    final centerY = (containerSize.height / 2 - currentMatrix.getTranslation().y) / currentScale;

    // Calculate new offset to maintain center point
    final offsetX = containerSize.width / 2 - centerX * scale;
    final offsetY = containerSize.height / 2 - centerY * scale;

    final matrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);

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
              ..translate(focalPoint.dx, focalPoint.dy)
              ..scale(scaleChange)
              ..translate(-focalPoint.dx, -focalPoint.dy);

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
            minScale: 1.0,  // Disable internal scaling (we handle it via outer InteractiveViewer)
            maxScale: 1.0,
            enableInteraction: false,  // Disable internal interaction (we handle it via outer InteractiveViewer)
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
    final statusText = progress.isDownloading ? 'Downloading...' : 'Exposing...';
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
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isActive;

  const _IconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final button = Material(
      color: isActive ? colors.primary.withValues(alpha: 0.1) : colors.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive ? colors.primary : colors.border,
              width: isActive ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 14,
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
        color: isActive ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
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

class _ControlRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _ControlRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(child: child),
      ],
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
