import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/nightshade_colors.dart';

/// Widget that displays the PHD2 guide star subframe image
///
/// Renders a small grayscale image (typically 50x50 to 100x100 pixels)
/// centered on the guide star with crosshairs overlay showing star position.
class GuideStarView extends StatefulWidget {
  /// The star image pixel data (16-bit grayscale, little-endian)
  final Uint8List? pixels;

  /// Width of the star image in pixels
  final int width;

  /// Height of the star image in pixels
  final int height;

  /// X position of the star centroid (0 to width)
  final double starX;

  /// Y position of the star centroid (0 to height)
  final double starY;

  /// Signal-to-noise ratio for quality indicator
  final double snr;

  /// Whether to show the crosshairs overlay
  final bool showCrosshairs;

  /// Callback when user clicks on the image (for star selection)
  final void Function(double x, double y)? onStarSelected;

  /// Message to show when no star image is available
  final String statusMessage;

  const GuideStarView({
    super.key,
    this.pixels,
    this.width = 0,
    this.height = 0,
    this.starX = 0,
    this.starY = 0,
    this.snr = 0,
    this.showCrosshairs = true,
    this.onStarSelected,
    this.statusMessage = 'No star selected',
  });

  /// Check if this widget has valid image data to display
  bool get hasValidImage {
    if (pixels == null || pixels!.isEmpty) return false;
    if (width <= 0 || height <= 0) return false;
    // PHD2 sends 16-bit data (2 bytes per pixel)
    final expectedBytes = width * height * 2;
    return pixels!.length >= expectedBytes;
  }

  @override
  State<GuideStarView> createState() => _GuideStarViewState();
}

class _GuideStarViewState extends State<GuideStarView> {
  ui.Image? _cachedImage;
  Uint8List? _lastPixels;

  @override
  void didUpdateWidget(GuideStarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild image if pixels changed
    if (widget.pixels != _lastPixels) {
      _cachedImage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: widget.onStarSelected != null
              ? (details) => _handleTap(details, constraints)
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A12),
              border: Border.all(
                color: _getSnrColor(colors).withValues(alpha: 0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _getSnrColor(colors).withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  // Star image or empty state
                  if (widget.hasValidImage)
                    _buildStarImage(constraints, colors)
                  else
                    _buildEmptyState(constraints, colors),

                  // Crosshairs overlay (only if we have valid image)
                  if (widget.showCrosshairs && widget.hasValidImage)
                    CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _CrosshairsPainter(
                        starX: widget.starX,
                        starY: widget.starY,
                        imageWidth: widget.width,
                        imageHeight: widget.height,
                        color: Colors.red.withValues(alpha: 0.7),
                      ),
                    ),

                  // SNR indicator (only show when we have a valid image)
                  if (widget.hasValidImage)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _getSnrColor(colors).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.activity,
                              size: 10,
                              color: _getSnrColor(colors),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'SNR: ${widget.snr.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: _getSnrColor(colors),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStarImage(BoxConstraints constraints, NightshadeColors colors) {
    return FutureBuilder<ui.Image>(
      future: _createImage(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ImagePainter(
              image: snapshot.data!,
            ),
          );
        }
        return _buildEmptyState(constraints, colors);
      },
    );
  }

  Widget _buildEmptyState(BoxConstraints constraints, NightshadeColors colors) {
    return Container(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      color: const Color(0xFF0A0A12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceAlt.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.starOff,
                size: 20,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.statusMessage,
              style: TextStyle(color: colors.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<ui.Image> _createImage() async {
    if (_cachedImage != null && widget.pixels == _lastPixels) {
      return _cachedImage!;
    }

    _lastPixels = widget.pixels;

    // PHD2 sends 16-bit grayscale data (little-endian, 2 bytes per pixel)
    final pixels = widget.pixels!;
    final numPixels = widget.width * widget.height;

    // Convert 16-bit grayscale to RGBA
    final rgbaPixels = Uint8List(numPixels * 4);

    // First pass: find min/max for auto-stretch
    int minVal = 65535;
    int maxVal = 0;

    for (int i = 0; i < numPixels && (i * 2 + 1) < pixels.length; i++) {
      // Read 16-bit little-endian value
      final value16 = pixels[i * 2] | (pixels[i * 2 + 1] << 8);
      if (value16 < minVal) minVal = value16;
      if (value16 > maxVal) maxVal = value16;
    }

    // Avoid division by zero
    final range = (maxVal - minVal).clamp(1, 65535);

    // Second pass: convert to 8-bit RGBA with auto-stretch
    for (int i = 0; i < numPixels && (i * 2 + 1) < pixels.length; i++) {
      // Read 16-bit little-endian value
      final value16 = pixels[i * 2] | (pixels[i * 2 + 1] << 8);

      // Auto-stretch to 0-255 range
      final normalized = (value16 - minVal) / range;
      final stretched = (255 * normalized).round().clamp(0, 255);

      rgbaPixels[i * 4] = stretched; // R
      rgbaPixels[i * 4 + 1] = stretched; // G
      rgbaPixels[i * 4 + 2] = stretched; // B
      rgbaPixels[i * 4 + 3] = 255; // A
    }

    final codec = await ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(rgbaPixels),
      width: widget.width,
      height: widget.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    ).instantiateCodec();

    final frame = await codec.getNextFrame();
    _cachedImage = frame.image;
    return _cachedImage!;
  }

  Color _getSnrColor(NightshadeColors colors) {
    if (widget.snr >= 10) return colors.success;
    if (widget.snr >= 5) return colors.warning;
    return colors.error;
  }

  void _handleTap(TapDownDetails details, BoxConstraints constraints) {
    // Convert tap position to image coordinates
    final scaleX = widget.width / constraints.maxWidth;
    final scaleY = widget.height / constraints.maxHeight;
    final imageX = details.localPosition.dx * scaleX;
    final imageY = details.localPosition.dy * scaleY;
    widget.onStarSelected?.call(imageX, imageY);
  }
}

/// Painter for rendering crosshairs at the star position
class _CrosshairsPainter extends CustomPainter {
  final double starX;
  final double starY;
  final int imageWidth;
  final int imageHeight;
  final Color color;

  _CrosshairsPainter({
    required this.starX,
    required this.starY,
    required this.imageWidth,
    required this.imageHeight,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    // Scale star position to widget size
    final x = (starX / imageWidth) * size.width;
    final y = (starY / imageHeight) * size.height;

    // Draw crosshairs
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      paint,
    );

    // Draw small circle at intersection
    canvas.drawCircle(
      Offset(x, y),
      4,
      paint..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CrosshairsPainter oldDelegate) {
    return starX != oldDelegate.starX ||
        starY != oldDelegate.starY ||
        color != oldDelegate.color;
  }
}

/// Painter for rendering the star image
class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(
        image, srcRect, dstRect, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
