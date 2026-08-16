import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

class OverlayChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const OverlayChip({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // absolute: HUD chip drawn over the live image canvas
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
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
              fontSize: NightshadeTypography.fontSize11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class OverlayIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final bool isActive;
  final VoidCallback? onTap;

  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.isActive = false,
    this.onTap,
  });

  @override
  State<OverlayIconButton> createState() => _OverlayIconButtonState();
}

class _OverlayIconButtonState extends State<OverlayIconButton> {
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
                // absolute: HUD button hover tint over the live image canvas
                color: widget.isActive
                    ? widget.colors.primary.withValues(alpha: 0.3)
                    : _isHovered
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                border: widget.isActive
                    ? Border.all(
                        color: widget.colors.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: 18,
                // absolute: HUD icon over the live image canvas
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

class HistogramWidget extends StatelessWidget {
  final NightshadeColors colors;
  final List<int>? histogram;

  const HistogramWidget({
    super.key,
    required this.colors,
    this.histogram,
  });

  @override
  Widget build(BuildContext context) {
    // Use responsive width - smaller on narrow screens
    final screenWidth = MediaQuery.sizeOf(context).width;
    final histogramWidth = screenWidth < 400 ? 140.0 : 200.0;

    return Container(
      width: histogramWidth,
      height: 80,
      padding: const EdgeInsets.all(12),
      // absolute: histogram HUD panel over the live image canvas
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Histogram',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: histogram != null && histogram!.isNotEmpty
                ? CustomPaint(
                    painter: HistogramPainter(
                      histogram: histogram!,
                      color: colors.primary,
                    ),
                    size: Size.infinite,
                  )
                : Container(
                    decoration: BoxDecoration(
                      // absolute: empty-state fill in the image-canvas HUD panel
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline4),
                    ),
                    child: Center(
                      child: Text(
                        'No data',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize9,
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

class HistogramPainter extends CustomPainter {
  final List<int> histogram;
  final Color color;

  HistogramPainter({required this.histogram, required this.color});

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
  bool shouldRepaint(covariant HistogramPainter oldDelegate) {
    return histogram != oldDelegate.histogram;
  }
}

class ImageStatsOverlay extends StatelessWidget {
  final NightshadeColors colors;
  final ImageStats? stats;

  const ImageStatsOverlay({
    super.key,
    required this.colors,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      // absolute: image-stats HUD panel over the live image canvas
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatLine(
            label: 'HFR',
            value: stats?.hfr?.toStringAsFixed(2) ?? '---',
            colors: colors,
          ),
          StatLine(
            label: 'Stars',
            value: stats?.starCount?.toString() ?? '---',
            colors: colors,
          ),
          StatLine(
            label: 'Median',
            value: stats?.median?.toStringAsFixed(0) ?? '---',
            colors: colors,
          ),
          StatLine(
            label: 'Mean',
            value: stats?.mean?.toStringAsFixed(0) ?? '---',
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class StatLine extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const StatLine({
    super.key,
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
              fontSize: NightshadeTypography.fontSize10,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w500,
              // absolute: stat value over the live image canvas HUD
              color: Colors.white70,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class ExposureProgressOverlay extends StatelessWidget {
  final ExposureProgress progress;
  final NightshadeColors colors;

  /// The operator has asked for this exposure to stop and the abort is in
  /// flight.
  ///
  /// The countdown MUST stop here. `ExposureProgress` keeps ticking after a
  /// cancel — the native waiter goes on publishing progress until the driver
  /// reports not-exposing or the duration deadline passes — so a running ring
  /// counts down to a frame that will never arrive. Nothing is known about how
  /// long the driver takes to honour an abort, so this state is indeterminate
  /// by construction.
  final bool isAborting;

  const ExposureProgressOverlay({
    super.key,
    required this.progress,
    required this.colors,
    this.isAborting = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = isAborting
        ? 'Stopping exposure...'
        : (progress.isDownloading ? 'Downloading...' : 'Exposing...');
    final progressValue = (progress.percent / 100.0).clamp(0.0, 1.0);

    return Container(
      // absolute: exposure progress scrim over the live image canvas
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
                    value: isAborting ? null : progressValue,
                    strokeWidth: 4,
                    backgroundColor: colors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                  if (!isAborting)
                    Center(
                      child: Text(
                        '${progress.percent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize16,
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
                fontSize: NightshadeTypography.fontSize14,
                fontWeight: FontWeight.w600,
                // absolute: status label over the live image canvas
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            if (!isAborting && !progress.isDownloading)
              Text(
                '${progress.remaining.toStringAsFixed(1)}s remaining',
                style: const TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  // absolute: remaining-time label over the live image canvas
                  color: Colors.white70,
                ),
              ),
            if (progress.totalFrames != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Frame ${progress.frameNumber} of ${progress.totalFrames}',
                  style: const TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    // absolute: frame-count label over the live image canvas
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
