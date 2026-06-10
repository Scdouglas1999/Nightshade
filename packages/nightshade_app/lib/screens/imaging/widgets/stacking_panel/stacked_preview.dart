part of '../stacking_panel.dart';

/// Displays the u16 stacked preview image, converting it to an 8-bit
/// displayable format on the fly.
///
/// [channels] selects how [previewData] is interpreted:
///   * `1` — a single luminance plane (`width * height` samples); rendered with
///     a min/max linear stretch into grayscale RGBA (the historic mono path,
///     byte-for-byte unchanged).
///   * `3` — an interleaved RGB16 buffer (`width * height * 3` samples, the
///     layout an OSC session produces); each channel is linearly stretched with
///     its own min/max so a colour stack previews in colour rather than as a
///     scrambled mono plane.
class _StackedPreview extends StatefulWidget {
  final Uint16List previewData;
  final int width;
  final int height;
  final int channels;
  final NightshadeColors colors;

  const _StackedPreview({
    required this.previewData,
    required this.width,
    required this.height,
    required this.channels,
    required this.colors,
  });

  @override
  State<_StackedPreview> createState() => _StackedPreviewState();
}

class _StackedPreviewState extends State<_StackedPreview> {
  ui.Image? _displayImage;
  bool _isDecoding = false;

  @override
  void initState() {
    super.initState();
    _buildDisplayImage();
  }

  @override
  void didUpdateWidget(_StackedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild when the data actually changes (identity check is fast)
    if (!identical(widget.previewData, oldWidget.previewData) ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.channels != oldWidget.channels) {
      _buildDisplayImage();
    }
  }

  @override
  void dispose() {
    _displayImage?.dispose();
    super.dispose();
  }

  Future<void> _buildDisplayImage() async {
    if (_isDecoding) return;
    _isDecoding = true;

    final data = widget.previewData;
    final w = widget.width;
    final h = widget.height;
    final pixelCount = w * h;

    if (pixelCount <= 0) {
      _isDecoding = false;
      return;
    }

    final Uint8List rgba;
    if (widget.channels == 3) {
      // Sanity check: an interleaved RGB16 buffer must carry 3 samples/pixel.
      if (data.length < pixelCount * 3) {
        _isDecoding = false;
        return;
      }
      rgba = stackedPreviewColorRgba(data, pixelCount);
    } else {
      // Sanity check.
      if (data.length < pixelCount) {
        _isDecoding = false;
        return;
      }
      rgba = stackedPreviewGrayRgba(data, pixelCount);
    }

    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _displayImage?.dispose();
          _displayImage = frame.image;
        });
      } else {
        frame.image.dispose();
      }

      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (e) {
      developer.log('[StackingPanel] Error building preview image: $e',
          name: 'StackingPanel', level: 900, error: e);
    } finally {
      _isDecoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayImage == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('Rendering preview...',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted)),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      child: AspectRatio(
        aspectRatio: widget.width / widget.height,
        child: RawImage(
          image: _displayImage,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview pixel conversion (channel-aware)
// ---------------------------------------------------------------------------

/// Linear min/max stretch of a single u16 luminance plane to grayscale RGBA.
/// Byte-for-byte identical to the historic mono preview path.
///
/// Exposed for testing the channel-branching contract of the stacked preview.
@visibleForTesting
Uint8List stackedPreviewGrayRgba(Uint16List data, int pixelCount) {
  int minVal = 65535;
  int maxVal = 0;
  for (int i = 0; i < pixelCount; i++) {
    final v = data[i];
    if (v < minVal) minVal = v;
    if (v > maxVal) maxVal = v;
  }
  final range = (maxVal - minVal).clamp(1, 65535);

  final rgba = Uint8List(pixelCount * 4);
  for (int i = 0; i < pixelCount; i++) {
    final normalized = ((data[i] - minVal) * 255 ~/ range).clamp(0, 255);
    final offset = i * 4;
    rgba[offset] = normalized;
    rgba[offset + 1] = normalized;
    rgba[offset + 2] = normalized;
    rgba[offset + 3] = 255;
  }
  return rgba;
}

/// Per-channel linear min/max stretch of an interleaved RGB16 buffer
/// (`R0,G0,B0,R1,...`) to RGBA.
///
/// Each channel is stretched against its own min/max so the colour balance is
/// preserved rather than being dominated by whichever channel happens to be
/// brightest. This is a genuine colour rendering (the live EAA preview is a
/// fast linear map; the quality-oriented STF colour stretch lives in the
/// Stack-and-Share result viewer), never a grayscale fallback.
///
/// Exposed for testing the channel-branching contract of the stacked preview.
@visibleForTesting
Uint8List stackedPreviewColorRgba(Uint16List data, int pixelCount) {
  var rMin = 65535, gMin = 65535, bMin = 65535;
  var rMax = 0, gMax = 0, bMax = 0;
  for (int i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final r = data[base];
    final g = data[base + 1];
    final b = data[base + 2];
    if (r < rMin) rMin = r;
    if (r > rMax) rMax = r;
    if (g < gMin) gMin = g;
    if (g > gMax) gMax = g;
    if (b < bMin) bMin = b;
    if (b > bMax) bMax = b;
  }
  final rRange = (rMax - rMin).clamp(1, 65535);
  final gRange = (gMax - gMin).clamp(1, 65535);
  final bRange = (bMax - bMin).clamp(1, 65535);

  final rgba = Uint8List(pixelCount * 4);
  for (int i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final offset = i * 4;
    rgba[offset] = ((data[base] - rMin) * 255 ~/ rRange).clamp(0, 255);
    rgba[offset + 1] = ((data[base + 1] - gMin) * 255 ~/ gRange).clamp(0, 255);
    rgba[offset + 2] = ((data[base + 2] - bMin) * 255 ~/ bRange).clamp(0, 255);
    rgba[offset + 3] = 255;
  }
  return rgba;
}
