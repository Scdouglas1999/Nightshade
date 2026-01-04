import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Factory that returns the appropriate progress panel widget for a node type
Widget? getProgressPanelForNode({
  required SequenceNode node,
  required NightshadeColors colors,
  required double progressPercent,
  required String? progressDetail,
}) {
  // Parse progress detail to extract relevant info
  final detail = progressDetail ?? '';

  if (node is CoolCameraNode || node is WarmCameraNode) {
    return _CoolingProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      isWarming: node is WarmCameraNode,
    );
  }

  if (node is AutofocusNode) {
    return _AutofocusProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
    );
  }

  if (node is ExposureNode) {
    return _ExposureProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      node: node,
    );
  }

  if (node is SlewNode || node is CenterNode) {
    return _SlewProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      isCentering: node is CenterNode,
    );
  }

  if (node is FilterChangeNode) {
    return _FilterProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
    );
  }

  // Default panel for other node types
  return _DefaultProgressPanel(
    colors: colors,
    progressPercent: progressPercent,
    detail: detail,
  );
}

/// Base container for progress panels with consistent styling
class _ProgressPanelContainer extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final Color? accentColor;

  const _ProgressPanelContainer({
    required this.colors,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? colors.info;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Progress panel for cooling/warming operations
class _CoolingProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final bool isWarming;

  const _CoolingProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    required this.isWarming,
  });

  @override
  Widget build(BuildContext context) {
    // Parse detail string: "Cooling: 15.2°C → -10.0°C (85% power)"
    // or "At target: -10.3°C (45% power)"
    final tempMatch = RegExp(r'(-?\d+\.?\d*)°C').allMatches(detail);
    final powerMatch = RegExp(r'(\d+\.?\d*)% power').firstMatch(detail);

    double? currentTemp;
    double? targetTemp;
    double? power;

    if (tempMatch.isNotEmpty) {
      final temps = tempMatch.map((m) => double.tryParse(m.group(1) ?? '')).whereType<double>().toList();
      if (temps.isNotEmpty) currentTemp = temps[0];
      if (temps.length > 1) targetTemp = temps[1];
    }
    if (powerMatch != null) {
      power = double.tryParse(powerMatch.group(1) ?? '');
    }

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: isWarming ? colors.warning : colors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                isWarming ? Icons.thermostat : Icons.ac_unit,
                size: 16,
                color: isWarming ? colors.warning : colors.info,
              ),
              const SizedBox(width: 8),
              Text(
                isWarming ? 'Warming Camera' : 'Cooling Camera',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Temperature display
          Row(
            children: [
              // Current temp
              _TempDisplay(
                colors: colors,
                label: 'Current',
                temp: currentTemp,
                isTarget: false,
              ),
              const SizedBox(width: 16),
              // Arrow
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: colors.textMuted,
              ),
              const SizedBox(width: 16),
              // Target temp
              _TempDisplay(
                colors: colors,
                label: 'Target',
                temp: targetTemp ?? currentTemp,
                isTarget: true,
              ),
              const Spacer(),
              // Power gauge
              if (power != null) _PowerGauge(colors: colors, power: power),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: isWarming ? colors.warning : colors.info,
          ),
        ],
      ),
    );
  }
}

class _TempDisplay extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double? temp;
  final bool isTarget;

  const _TempDisplay({
    required this.colors,
    required this.label,
    this.temp,
    required this.isTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
          ),
        ),
        Text(
          temp != null ? '${temp!.toStringAsFixed(1)}°C' : '--°C',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isTarget ? colors.info : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PowerGauge extends StatelessWidget {
  final NightshadeColors colors;
  final double power;

  const _PowerGauge({required this.colors, required this.power});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Power',
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 40,
              height: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: power / 100.0,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    power > 80 ? colors.error : power > 50 ? colors.warning : colors.success,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${power.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Progress panel for autofocus operations with V-curve and star zoom
class _AutofocusProgressPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;

  const _AutofocusProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
  });

  @override
  ConsumerState<_AutofocusProgressPanel> createState() => _AutofocusProgressPanelState();
}

class _AutofocusProgressPanelState extends ConsumerState<_AutofocusProgressPanel> {
  int _currentStarIndex = 0;
  bool _isRefreshing = false;
  List<StarCrop>? _refreshedCrops;

  @override
  Widget build(BuildContext context) {
    // Try to parse structured JSON progress data
    final afData = AutofocusProgressData.tryParse(widget.detail);

    // Fallback to legacy parsing if not structured data
    if (afData == null) {
      return _buildLegacyPanel();
    }

    return _buildEnhancedPanel(afData);
  }

  Widget _buildLegacyPanel() {
    // Parse detail: "Point 5/9: HFR=2.45, Stars=127"
    final pointMatch = RegExp(r'Point (\d+)/(\d+)').firstMatch(widget.detail);
    final hfrMatch = RegExp(r'HFR[=:]?\s*(\d+\.?\d*)').firstMatch(widget.detail);
    final starsMatch = RegExp(r'Stars[=:]?\s*(\d+)').firstMatch(widget.detail);

    final currentPoint = int.tryParse(pointMatch?.group(1) ?? '');
    final totalPoints = int.tryParse(pointMatch?.group(2) ?? '');
    final hfr = double.tryParse(hfrMatch?.group(1) ?? '');
    final stars = int.tryParse(starsMatch?.group(1) ?? '');

    return _ProgressPanelContainer(
      colors: widget.colors,
      accentColor: widget.colors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(currentPoint, totalPoints),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatBox(colors: widget.colors, label: 'HFR', value: hfr?.toStringAsFixed(2) ?? '--', unit: 'px', color: widget.colors.primary),
              const SizedBox(width: 16),
              _StatBox(colors: widget.colors, label: 'Stars', value: stars?.toString() ?? '--', unit: '', color: widget.colors.success),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: widget.colors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: widget.colors.border),
            ),
            child: Center(
              child: Text('Waiting for data...', style: TextStyle(fontSize: 10, color: widget.colors.textMuted)),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedProgressBar(colors: widget.colors, progress: widget.progressPercent / 100.0, color: widget.colors.primary),
        ],
      ),
    );
  }

  Future<void> _refreshStarCrops() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Get the camera device ID from the camera state
      final cameraState = ref.read(cameraStateProvider);
      final deviceId = cameraState.deviceId;

      if (deviceId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No camera connected'),
              backgroundColor: widget.colors.warning,
            ),
          );
        }
        return;
      }

      // Request fresh star crops from the backend
      final backend = ref.read(backendProvider);
      final crops = await backend.getStarCropsFromLastImage(deviceId, maxCrops: 5);

      if (mounted) {
        setState(() {
          _refreshedCrops = crops;
          _currentStarIndex = 0;
        });

        if (crops.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No stars detected in image'),
              backgroundColor: widget.colors.warning,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh star crops: $e'),
            backgroundColor: widget.colors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Widget _buildEnhancedPanel(AutofocusProgressData data) {
    // Use refreshed crops if available, otherwise use data from progress events
    final starCrops = _refreshedCrops ?? data.starCrops;

    // Ensure star index is valid
    if (_currentStarIndex >= starCrops.length) {
      _currentStarIndex = 0;
    }

    // Clear refreshed crops when new progress data arrives with different crops
    if (_refreshedCrops != null && data.starCrops.isNotEmpty &&
        data.starCrops.first.pixelsBase64 != _refreshedCrops!.first.pixelsBase64) {
      _refreshedCrops = null;
    }

    return _ProgressPanelContainer(
      colors: widget.colors,
      accentColor: widget.colors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(data.point, data.totalPoints),
          const SizedBox(height: 12),

          // V-curve with star zoom overlay
          SizedBox(
            height: 120,
            child: Stack(
              children: [
                // V-curve chart (fills the whole area)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.colors.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: widget.colors.border),
                    ),
                    child: CustomPaint(
                      painter: _VCurvePainter(
                        colors: widget.colors,
                        points: data.vcurvePoints,
                        focusRange: data.focusRange,
                      ),
                      size: const Size(double.infinity, 120),
                    ),
                  ),
                ),

                // Star zoom panel (top-left corner overlay)
                if (starCrops.isNotEmpty)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _StarZoomPanel(
                      colors: widget.colors,
                      starCrops: starCrops,
                      currentIndex: _currentStarIndex,
                      isRefreshing: _isRefreshing,
                      onPrevious: () => setState(() {
                        _currentStarIndex = (_currentStarIndex - 1 + starCrops.length) % starCrops.length;
                      }),
                      onNext: () => setState(() {
                        _currentStarIndex = (_currentStarIndex + 1) % starCrops.length;
                      }),
                      onRefresh: _refreshStarCrops,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Stats row
          Row(
            children: [
              _StatBox(colors: widget.colors, label: 'HFR', value: data.hfr.toStringAsFixed(2), unit: 'px', color: widget.colors.primary),
              const SizedBox(width: 16),
              _StatBox(colors: widget.colors, label: 'Stars', value: data.starCount.toString(), unit: '', color: widget.colors.success),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar
          _AnimatedProgressBar(colors: widget.colors, progress: widget.progressPercent / 100.0, color: widget.colors.primary),
        ],
      ),
    );
  }

  Widget _buildHeader(int? currentPoint, int? totalPoints) {
    return Row(
      children: [
        Icon(Icons.center_focus_strong, size: 16, color: widget.colors.primary),
        const SizedBox(width: 8),
        Text(
          'Autofocus',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.colors.textPrimary),
        ),
        const Spacer(),
        if (currentPoint != null && totalPoints != null)
          Text(
            'Point $currentPoint of $totalPoints',
            style: TextStyle(fontSize: 10, color: widget.colors.textMuted),
          ),
      ],
    );
  }
}

/// Star zoom panel with navigation arrows
class _StarZoomPanel extends StatelessWidget {
  final NightshadeColors colors;
  final List<StarCrop> starCrops;
  final int currentIndex;
  final bool isRefreshing;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRefresh;

  const _StarZoomPanel({
    required this.colors,
    required this.starCrops,
    required this.currentIndex,
    this.isRefreshing = false,
    required this.onPrevious,
    required this.onNext,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final crop = starCrops.isNotEmpty && currentIndex < starCrops.length
        ? starCrops[currentIndex]
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Star image
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: crop != null
                ? _buildStarImage(crop)
                : Center(
                    child: Icon(Icons.star_border, size: 24, color: colors.textMuted),
                  ),
          ),

          // Navigation row
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Previous arrow
                _buildNavButton(
                  icon: Icons.chevron_left,
                  onTap: starCrops.length > 1 ? onPrevious : null,
                ),
                // Counter
                Text(
                  '${currentIndex + 1}/${starCrops.length}',
                  style: TextStyle(fontSize: 9, color: colors.textMuted),
                ),
                // Next arrow
                _buildNavButton(
                  icon: Icons.chevron_right,
                  onTap: starCrops.length > 1 ? onNext : null,
                ),
                // Refresh button
                if (isRefreshing)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(colors.primary),
                    ),
                  )
                else
                  _buildNavButton(
                    icon: Icons.refresh,
                    onTap: onRefresh,
                    size: 12,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    VoidCallback? onTap,
    double size = 14,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: size,
        color: onTap != null ? colors.textSecondary : colors.textMuted.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildStarImage(StarCrop crop) {
    // Create a grayscale image from the pixel data
    try {
      final pixels = crop.pixels;
      if (pixels.isEmpty) {
        return Center(child: Icon(Icons.error_outline, size: 24, color: colors.textMuted));
      }

      // Build RGBA image from grayscale
      final rgbaPixels = <int>[];
      for (final pixel in pixels) {
        rgbaPixels.add(pixel); // R
        rgbaPixels.add(pixel); // G
        rgbaPixels.add(pixel); // B
        rgbaPixels.add(255);   // A
      }

      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        child: Image.memory(
          _createBmpFromRgba(rgbaPixels, crop.width, crop.height),
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    } catch (e) {
      return Center(child: Icon(Icons.error_outline, size: 24, color: colors.textMuted));
    }
  }

  /// Create a simple BMP image from RGBA pixel data
  static Uint8List _createBmpFromRgba(List<int> rgbaPixels, int width, int height) {
    // BMP header (54 bytes) + pixel data
    final rowSize = ((width * 3 + 3) ~/ 4) * 4; // Row size must be multiple of 4
    final imageSize = rowSize * height;
    final fileSize = 54 + imageSize;

    final bmp = Uint8List(fileSize);
    final data = ByteData.view(bmp.buffer);

    // BMP file header (14 bytes)
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    data.setUint32(2, fileSize, Endian.little);
    data.setUint32(10, 54, Endian.little); // Pixel data offset

    // DIB header (40 bytes)
    data.setUint32(14, 40, Endian.little); // Header size
    data.setInt32(18, width, Endian.little);
    data.setInt32(22, -height, Endian.little); // Negative for top-down
    data.setUint16(26, 1, Endian.little); // Planes
    data.setUint16(28, 24, Endian.little); // Bits per pixel
    data.setUint32(34, imageSize, Endian.little);

    // Pixel data (BGR format)
    int offset = 54;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        if (idx + 2 < rgbaPixels.length) {
          bmp[offset++] = rgbaPixels[idx + 2]; // B
          bmp[offset++] = rgbaPixels[idx + 1]; // G
          bmp[offset++] = rgbaPixels[idx];     // R
        } else {
          offset += 3;
        }
      }
      // Padding
      while (offset % 4 != 54 % 4 && offset < fileSize) {
        bmp[offset++] = 0;
      }
    }

    return bmp;
  }
}

/// V-curve painter with real data points and axis labels
class _VCurvePainter extends CustomPainter {
  final NightshadeColors colors;
  final List<VCurvePoint> points;
  final FocusRange focusRange;

  _VCurvePainter({
    required this.colors,
    required this.points,
    required this.focusRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    // Margins for axis labels
    const leftMargin = 35.0;
    const bottomMargin = 16.0;
    const topMargin = 8.0;
    const rightMargin = 8.0;

    final chartWidth = size.width - leftMargin - rightMargin;
    final chartHeight = size.height - topMargin - bottomMargin;

    // Calculate value ranges
    final minHfr = points.map((p) => p.hfr).reduce((a, b) => a < b ? a : b);
    final maxHfr = points.map((p) => p.hfr).reduce((a, b) => a > b ? a : b);
    final hfrRange = (maxHfr - minHfr).clamp(0.5, double.infinity);
    final hfrPadding = hfrRange * 0.1;

    final posRange = (focusRange.max - focusRange.min).toDouble();

    // Draw axis labels
    _drawAxisLabels(canvas, size, leftMargin, bottomMargin, topMargin,
        minHfr - hfrPadding, maxHfr + hfrPadding, focusRange);

    // Draw gridlines
    _drawGridlines(canvas, leftMargin, topMargin, chartWidth, chartHeight);

    // Draw curve and points
    final linePaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;

    final path = Path();
    bool first = true;

    for (final point in points) {
      final x = leftMargin + ((point.position - focusRange.min) / posRange) * chartWidth;
      final y = topMargin + chartHeight - ((point.hfr - (minHfr - hfrPadding)) / (hfrRange + 2 * hfrPadding)) * chartHeight;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 4, pointPaint);
    }

    canvas.drawPath(path, linePaint);

    // Mark the minimum HFR point
    final minPoint = points.reduce((a, b) => a.hfr < b.hfr ? a : b);
    final minX = leftMargin + ((minPoint.position - focusRange.min) / posRange) * chartWidth;
    final minY = topMargin + chartHeight - ((minPoint.hfr - (minHfr - hfrPadding)) / (hfrRange + 2 * hfrPadding)) * chartHeight;

    final starPaint = Paint()
      ..color = colors.success
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(minX, minY), 6, starPaint);
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Collecting data...',
        style: TextStyle(color: colors.textMuted, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2));
  }

  void _drawAxisLabels(Canvas canvas, Size size, double leftMargin, double bottomMargin,
      double topMargin, double minHfr, double maxHfr, FocusRange range) {
    final textStyle = TextStyle(color: colors.textMuted, fontSize: 8);

    // Y-axis label (HFR)
    final yLabel = TextPainter(
      text: TextSpan(text: 'HFR', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    yLabel.layout();
    yLabel.paint(canvas, const Offset(2, 4));

    // Min/max HFR values
    final minLabel = TextPainter(
      text: TextSpan(text: minHfr.toStringAsFixed(1), style: textStyle),
      textDirection: TextDirection.ltr,
    );
    minLabel.layout();
    minLabel.paint(canvas, Offset(2, size.height - bottomMargin - minLabel.height));

    final maxLabel = TextPainter(
      text: TextSpan(text: maxHfr.toStringAsFixed(1), style: textStyle),
      textDirection: TextDirection.ltr,
    );
    maxLabel.layout();
    maxLabel.paint(canvas, Offset(2, topMargin));

    // X-axis labels (focus range)
    final rangeLabel = TextPainter(
      text: TextSpan(text: '${range.min} → ${range.max}', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    rangeLabel.layout();
    rangeLabel.paint(canvas, Offset((size.width - rangeLabel.width) / 2, size.height - rangeLabel.height - 2));
  }

  void _drawGridlines(Canvas canvas, double left, double top, double width, double height) {
    final gridPaint = Paint()
      ..color = colors.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Horizontal gridlines
    for (int i = 0; i <= 4; i++) {
      final y = top + (height * i / 4);
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
    }

    // Vertical gridlines
    for (int i = 0; i <= 4; i++) {
      final x = left + (width * i / 4);
      canvas.drawLine(Offset(x, top), Offset(x, top + height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VCurvePainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      oldDelegate.focusRange.min != focusRange.min ||
      oldDelegate.focusRange.max != focusRange.max;
}

class _StatBox extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatBox({
    required this.colors,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress panel for exposure operations
class _ExposureProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final ExposureNode node;

  const _ExposureProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    // Parse detail: "Frame 3/10" or "Exposing: 45s remaining"
    final frameMatch = RegExp(r'Frame (\d+)/(\d+)').firstMatch(detail);
    final currentFrame = int.tryParse(frameMatch?.group(1) ?? '') ?? 0;
    final totalFrames = int.tryParse(frameMatch?.group(2) ?? '') ?? node.count;

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.camera, size: 16, color: colors.success),
              const SizedBox(width: 8),
              Text(
                'Exposure: ${node.filter ?? 'No Filter'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$currentFrame / $totalFrames frames',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Frame grid
          _FrameGrid(
            colors: colors,
            totalFrames: totalFrames,
            completedFrames: currentFrame - 1,
            currentFrame: currentFrame,
          ),
          const SizedBox(height: 12),

          // Duration info
          Row(
            children: [
              _StatBox(
                colors: colors,
                label: 'Duration',
                value: node.durationSecs.toStringAsFixed(0),
                unit: 's',
                color: colors.success,
              ),
              const SizedBox(width: 12),
              _StatBox(
                colors: colors,
                label: 'Total',
                value: (node.durationSecs * totalFrames / 60).toStringAsFixed(1),
                unit: 'min',
                color: colors.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FrameGrid extends StatelessWidget {
  final NightshadeColors colors;
  final int totalFrames;
  final int completedFrames;
  final int currentFrame;

  const _FrameGrid({
    required this.colors,
    required this.totalFrames,
    required this.completedFrames,
    required this.currentFrame,
  });

  @override
  Widget build(BuildContext context) {
    // Limit display to reasonable number
    final displayFrames = totalFrames > 20 ? 20 : totalFrames;
    final frameSize = totalFrames > 10 ? 14.0 : 18.0;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(displayFrames, (i) {
        final frameNum = i + 1;
        final isCompleted = frameNum <= completedFrames;
        final isCurrent = frameNum == currentFrame;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: frameSize,
          height: frameSize,
          decoration: BoxDecoration(
            color: isCompleted
                ? colors.success
                : isCurrent
                    ? colors.info
                    : colors.surface,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isCompleted
                  ? colors.success
                  : isCurrent
                      ? colors.info
                      : colors.border,
              width: isCurrent ? 2 : 1,
            ),
            boxShadow: isCurrent
                ? [BoxShadow(color: colors.info.withValues(alpha: 0.5), blurRadius: 4)]
                : null,
          ),
        );
      }),
    );
  }
}

/// Progress panel for slew/centering operations
class _SlewProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final bool isCentering;

  const _SlewProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    required this.isCentering,
  });

  @override
  Widget build(BuildContext context) {
    // Parse detail for separation info in centering
    final sepMatch = RegExp(r'(\d+\.?\d*)"?').firstMatch(detail);
    final separation = double.tryParse(sepMatch?.group(1) ?? '');

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCentering ? Icons.gps_fixed : Icons.navigation,
                size: 16,
                color: colors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCentering ? 'Centering Target' : 'Slewing to Target',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (separation != null && isCentering)
                Text(
                  '${separation.toStringAsFixed(1)}" remaining',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: colors.warning,
          ),
        ],
      ),
    );
  }
}

/// Progress panel for filter change operations
class _FilterProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;

  const _FilterProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt, size: 16, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail.isNotEmpty ? detail : 'Changing Filter',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: colors.accent,
          ),
        ],
      ),
    );
  }
}

/// Default progress panel for nodes without specific visualization
class _DefaultProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;

  const _DefaultProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isError = detail.toLowerCase().startsWith('error');
    final accentColor = isError ? colors.error : colors.info;

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (isError)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.error_outline,
                        size: 14,
                        color: colors.error,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        color: isError ? colors.error : colors.textPrimary,
                        fontWeight: isError ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isError)
            _AnimatedProgressBar(
              colors: colors,
              progress: progressPercent / 100.0,
              color: accentColor,
            ),
        ],
      ),
    );
  }
}

/// Animated progress bar with gradient
class _AnimatedProgressBar extends StatelessWidget {
  final NightshadeColors colors;
  final double progress;
  final Color color;

  const _AnimatedProgressBar({
    required this.colors,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: colors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
