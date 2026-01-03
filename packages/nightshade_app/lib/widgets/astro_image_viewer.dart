import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Data class for passing image conversion parameters to the isolate
class _ImageConversionParams {
  final Uint8List sourceData;
  final int width;
  final int height;
  final bool isColor;

  _ImageConversionParams({
    required this.sourceData,
    required this.width,
    required this.height,
    required this.isColor,
  });
}

/// Efficient astronomy image viewer that supports both color and mono images
/// with zoom/pan functionality including mousewheel support.
///
/// Features:
/// - GPU-accelerated rendering via ui.Image
/// - Background isolate conversion (doesn't block UI)
/// - Supports RGB color and grayscale mono images
/// - Interactive zoom/pan with mousewheel and gesture support
/// - Configurable min/max zoom levels
class AstroImageViewer extends StatefulWidget {
  /// The raw pixel data (RGB for color, grayscale for mono)
  final Uint8List imageData;

  /// Width of the image in pixels
  final int width;

  /// Height of the image in pixels
  final int height;

  /// Whether the image is color (RGB) or mono (grayscale)
  final bool isColor;

  /// Minimum zoom scale
  final double minScale;

  /// Maximum zoom scale
  final double maxScale;

  /// Whether to enable zoom/pan interaction
  final bool enableInteraction;

  /// Filter quality for image scaling
  final FilterQuality filterQuality;

  /// Callback when zoom/pan state changes
  final ValueChanged<TransformationController>? onTransformChanged;

  const AstroImageViewer({
    super.key,
    required this.imageData,
    required this.width,
    required this.height,
    this.isColor = false,
    this.minScale = 0.1,
    this.maxScale = 10.0,
    this.enableInteraction = true,
    this.filterQuality = FilterQuality.medium,
    this.onTransformChanged,
  });

  @override
  State<AstroImageViewer> createState() => _AstroImageViewerState();
}

class _AstroImageViewerState extends State<AstroImageViewer> {
  ui.Image? _decodedImage;
  bool _isLoading = true;
  Uint8List? _lastImageData;
  int? _lastWidth;
  int? _lastHeight;
  bool? _lastIsColor;
  bool _initialScaleSet = false;
  double? _effectiveMinScale;

  late TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _decodeImage();
  }

  /// Calculate the scale needed to fit the image within the container
  double _calculateFitScale(Size containerSize, int imageWidth, int imageHeight) {
    if (containerSize.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return 1.0;
    }
    final scaleX = containerSize.width / imageWidth;
    final scaleY = containerSize.height / imageHeight;
    return scaleX < scaleY ? scaleX : scaleY;
  }

  /// Set the initial transformation to fit the image in the container
  void _setInitialFitTransform(Size containerSize) {
    if (_decodedImage == null || _initialScaleSet) return;

    final fitScale = _calculateFitScale(
      containerSize,
      _decodedImage!.width,
      _decodedImage!.height,
    );

    // Calculate offset to center the scaled image
    final scaledWidth = _decodedImage!.width * fitScale;
    final scaledHeight = _decodedImage!.height * fitScale;
    final offsetX = (containerSize.width - scaledWidth) / 2;
    final offsetY = (containerSize.height - scaledHeight) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(fitScale);

    _initialScaleSet = true;
  }

  @override
  void didUpdateWidget(covariant AstroImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-decode if the image data actually changed
    if (!identical(widget.imageData, _lastImageData) ||
        widget.width != _lastWidth ||
        widget.height != _lastHeight ||
        widget.isColor != _lastIsColor) {
      // Reset initial scale flag so new image gets fit to container
      _initialScaleSet = false;
      _decodeImage();
    }
  }

  Future<void> _decodeImage() async {
    final sourceData = widget.imageData;
    final width = widget.width;
    final height = widget.height;
    final isColor = widget.isColor;

    if (sourceData.isEmpty || width <= 0 || height <= 0) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    // Cache current params
    _lastImageData = sourceData;
    _lastWidth = width;
    _lastHeight = height;
    _lastIsColor = isColor;

    // Show loading state
    if (mounted && !_isLoading) {
      setState(() => _isLoading = true);
    }

    // Convert to RGBA in a compute isolate to avoid blocking UI
    final params = _ImageConversionParams(
      sourceData: sourceData,
      width: width,
      height: height,
      isColor: isColor,
    );
    final rgbaData = await compute(_convertToRgba, params);

    // Decode pixels to ui.Image
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaData,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        completer.complete(img);
      },
    );

    final image = await completer.future;

    if (mounted) {
      // Dispose old image before replacing
      _decodedImage?.dispose();
      setState(() {
        _decodedImage = image;
        _isLoading = false;
      });
    } else {
      // Widget was disposed while loading
      image.dispose();
    }
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.enableInteraction) return;

    if (event is PointerScrollEvent) {
      // Get current scale
      final currentScale = _transformationController.value.getMaxScaleOnAxis();

      // Calculate new scale based on scroll direction
      final delta = event.scrollDelta.dy;
      final scaleFactor = delta > 0 ? 0.9 : 1.1; // Zoom out or in
      final minScale = _effectiveMinScale ?? widget.minScale;
      final newScale = (currentScale * scaleFactor).clamp(minScale, widget.maxScale);

      if (newScale != currentScale) {
        // Get the focal point in scene coordinates
        final focalPoint = event.localPosition;

        // Calculate the new transformation matrix
        final scaleChange = newScale / currentScale;

        // Create a new matrix that scales around the focal point
        final matrix = Matrix4.identity()
          ..translate(focalPoint.dx, focalPoint.dy)
          ..scale(scaleChange)
          ..translate(-focalPoint.dx, -focalPoint.dy);

        _transformationController.value = matrix * _transformationController.value;

        widget.onTransformChanged?.call(_transformationController);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_decodedImage == null) {
      return const Center(
        child: Text('No image data'),
      );
    }

    final imageWidget = CustomPaint(
      painter: _AstroImagePainter(
        image: _decodedImage!,
        filterQuality: widget.filterQuality,
      ),
      size: Size(
        _decodedImage!.width.toDouble(),
        _decodedImage!.height.toDouble(),
      ),
    );

    if (!widget.enableInteraction) {
      return Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: imageWidget,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Calculate fit scale for this container
        final fitScale = _calculateFitScale(
          containerSize,
          _decodedImage!.width,
          _decodedImage!.height,
        );

        // Ensure minScale doesn't exceed the fit scale, otherwise the image
        // would appear zoomed in rather than fitting the container
        final effectiveMinScale = fitScale < widget.minScale ? fitScale : widget.minScale;
        _effectiveMinScale = effectiveMinScale;

        // Set initial fit transform once we know the container size
        // This is safe to call during build since it only updates the
        // transformation controller (not widget state) and only runs once
        if (!_initialScaleSet && containerSize.width > 0 && containerSize.height > 0) {
          _setInitialFitTransform(containerSize);
        }

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: effectiveMinScale,
            maxScale: widget.maxScale,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Center(
              child: imageWidget,
            ),
          ),
        );
      },
    );
  }
}

/// Convert source image data to RGBA format for ui.decodeImageFromPixels.
/// This runs in a compute isolate to avoid blocking the UI thread.
Uint8List _convertToRgba(_ImageConversionParams params) {
  final src = params.sourceData;
  final numPixels = params.width * params.height;
  final rgba = Uint8List(numPixels * 4);

  if (params.isColor) {
    // RGB -> RGBA (add alpha channel)
    for (int i = 0; i < numPixels; i++) {
      final srcOffset = i * 3;
      final dstOffset = i * 4;
      rgba[dstOffset] = src[srcOffset];         // R
      rgba[dstOffset + 1] = src[srcOffset + 1]; // G
      rgba[dstOffset + 2] = src[srcOffset + 2]; // B
      rgba[dstOffset + 3] = 255;                // A (fully opaque)
    }
  } else {
    // Grayscale -> RGBA
    for (int i = 0; i < numPixels; i++) {
      final gray = src[i];
      final offset = i * 4;
      rgba[offset] = gray;     // R
      rgba[offset + 1] = gray; // G
      rgba[offset + 2] = gray; // B
      rgba[offset + 3] = 255;  // A (fully opaque)
    }
  }

  return rgba;
}

/// Efficient image painter that draws a pre-decoded ui.Image
class _AstroImagePainter extends CustomPainter {
  final ui.Image image;
  final FilterQuality filterQuality;

  _AstroImagePainter({
    required this.image,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = filterQuality;
    canvas.drawImage(image, Offset.zero, paint);
  }

  @override
  bool shouldRepaint(_AstroImagePainter oldDelegate) {
    return oldDelegate.image != image ||
           oldDelegate.filterQuality != filterQuality;
  }
}
