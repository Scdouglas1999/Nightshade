import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

class ImageDisplayWidget extends ConsumerStatefulWidget {
  final CapturedImageData imageData;
  final double zoomLevel;
  final Offset panOffset;

  const ImageDisplayWidget({
    super.key,
    required this.imageData,
    required this.zoomLevel,
    required this.panOffset,
  });

  @override
  ConsumerState<ImageDisplayWidget> createState() => _ImageDisplayWidgetState();
}

class _ImageDisplayWidgetState extends ConsumerState<ImageDisplayWidget> {
  ui.Image? _decodedImage;
  bool _isDecoding = false;
  Uint8List? _lastDecodedPixels;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(ImageDisplayWidget oldWidget) {
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
