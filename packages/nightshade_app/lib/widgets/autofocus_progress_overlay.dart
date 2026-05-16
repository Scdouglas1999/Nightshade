import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Non-blocking autofocus progress overlay that sits at the bottom-right
/// of the screen and shows live V-curve data as autofocus runs.
///
/// This overlay does not block interaction with the rest of the app.
/// It can be minimized, dragged, and dismissed.
class AutofocusProgressOverlay extends ConsumerStatefulWidget {
  const AutofocusProgressOverlay({super.key});

  @override
  ConsumerState<AutofocusProgressOverlay> createState() =>
      _AutofocusProgressOverlayState();
}

class _AutofocusProgressOverlayState
    extends ConsumerState<AutofocusProgressOverlay>
    with SingleTickerProviderStateMixin {
  // Drag offset from bottom-right corner
  Offset _offset = const Offset(16, 16);
  late AnimationController _pulseController;

  static const double _expandedWidth = 360.0;
  static const double _expandedHeight = 320.0;
  static const double _minimizedWidth = 200.0;
  static const double _minimizedHeight = 40.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlayState = ref.watch(autofocusOverlayProvider);

    if (!overlayState.isVisible) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMinimized = overlayState.isMinimized;

    final width = isMinimized ? _minimizedWidth : _expandedWidth;
    final height = isMinimized ? _minimizedHeight : _expandedHeight;

    return Positioned(
      right: _offset.dx,
      bottom: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final screenSize = MediaQuery.sizeOf(context);
          setState(() {
            _offset = Offset(
              (_offset.dx - details.delta.dx).clamp(0, screenSize.width - width),
              (_offset.dy - details.delta.dy).clamp(0, screenSize.height - height),
            );
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: overlayState.isRunning
                  ? colors.primary.withValues(alpha: 0.6)
                  : colors.border,
              width: overlayState.isRunning ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: isMinimized
              ? _buildMinimized(colors, overlayState)
              : _buildExpanded(colors, overlayState),
        ),
      ),
    );
  }

  Widget _buildMinimized(
      NightshadeColors colors, AutofocusOverlayState overlayState) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            ref.read(autofocusOverlayProvider.notifier).toggleMinimized(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (overlayState.isRunning)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Icon(
                      LucideIcons.focus,
                      size: 16,
                      color: Color.lerp(
                        colors.primary,
                        colors.primary.withValues(alpha: 0.4),
                        _pulseController.value,
                      ),
                    );
                  },
                )
              else
                Icon(
                  LucideIcons.focus,
                  size: 16,
                  color: overlayState.result != null
                      ? colors.success
                      : colors.textMuted,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overlayState.isRunning
                      ? 'AF: ${overlayState.currentPoint}/${overlayState.totalPoints}'
                      : (overlayState.result != null
                          ? 'AF: HFR ${overlayState.result!.bestHfr.toStringAsFixed(2)}'
                          : 'AF: ${overlayState.status}'),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildCloseButton(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(
      NightshadeColors colors, AutofocusOverlayState overlayState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title bar
        _buildTitleBar(colors, overlayState),

        // V-curve chart area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: overlayState.vcurvePoints.isEmpty
                  ? Center(
                      child: overlayState.isRunning
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        colors.primary),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Waiting for data...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'No data',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textMuted,
                              ),
                            ),
                    )
                  : CustomPaint(
                      painter: _OverlayVCurvePainter(
                        vcurvePoints: overlayState.vcurvePoints,
                        bestPosition: overlayState.result?.bestPosition,
                        focusRange: overlayState.focusRange,
                        accentColor: colors.primary,
                        gridColor: colors.border,
                        textColor: colors.textMuted,
                        successColor: colors.success,
                        isRunning: overlayState.isRunning,
                        currentPoint: overlayState.currentPoint,
                      ),
                      size: Size.infinite,
                    ),
            ),
          ),
        ),

        // Stats row
        _buildStatsRow(colors, overlayState),

        // Progress bar (only while running)
        if (overlayState.isRunning && overlayState.totalPoints > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: LinearProgressIndicator(
              value: overlayState.currentPoint / overlayState.totalPoints,
              backgroundColor: colors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(colors.primary),
              minHeight: 3,
            ),
          ),

        // Status line
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            overlayState.status,
            style: TextStyle(
              fontSize: 10,
              color: overlayState.hasError
                  ? colors.error
                  : colors.textMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar(
      NightshadeColors colors, AutofocusOverlayState overlayState) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (overlayState.isRunning)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                LucideIcons.focus,
                size: 14,
                color: overlayState.result != null
                    ? colors.success
                    : colors.textMuted,
              ),
            ),
          Text(
            'Autofocus',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          // Minimize button
          _buildIconButton(
            icon: LucideIcons.minus,
            onPressed: () => ref
                .read(autofocusOverlayProvider.notifier)
                .toggleMinimized(),
            colors: colors,
          ),
          const SizedBox(width: 2),
          // Close button
          _buildCloseButton(colors),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
      NightshadeColors colors, AutofocusOverlayState overlayState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          _StatBadge(
            label: 'Point',
            value: overlayState.totalPoints > 0
                ? '${overlayState.currentPoint}/${overlayState.totalPoints}'
                : '--',
            colors: colors,
          ),
          const SizedBox(width: 8),
          _StatBadge(
            label: 'HFR',
            value: overlayState.currentHfr > 0
                ? overlayState.currentHfr.toStringAsFixed(2)
                : '--',
            colors: colors,
          ),
          const SizedBox(width: 8),
          _StatBadge(
            label: 'Best',
            value: overlayState.bestHfr > 0
                ? overlayState.bestHfr.toStringAsFixed(2)
                : '--',
            colors: colors,
            highlight: true,
          ),
          const SizedBox(width: 8),
          _StatBadge(
            label: 'Stars',
            value: overlayState.starCount > 0
                ? '${overlayState.starCount}'
                : '--',
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required NightshadeColors colors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 14, color: colors.textMuted),
        ),
      ),
    );
  }

  Widget _buildCloseButton(NightshadeColors colors) {
    return _buildIconButton(
      icon: LucideIcons.x,
      onPressed: () => ref.read(autofocusOverlayProvider.notifier).dismiss(),
      colors: colors,
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: highlight
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: highlight
              ? Border.all(color: colors.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: colors.textMuted,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlight ? colors.primary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter for the overlay V-curve chart
class _OverlayVCurvePainter extends CustomPainter {
  final List<VCurvePoint> vcurvePoints;
  final int? bestPosition;
  final FocusRange? focusRange;
  final Color accentColor;
  final Color gridColor;
  final Color textColor;
  final Color successColor;
  final bool isRunning;
  final int currentPoint;

  _OverlayVCurvePainter({
    required this.vcurvePoints,
    this.bestPosition,
    this.focusRange,
    required this.accentColor,
    required this.gridColor,
    required this.textColor,
    required this.successColor,
    required this.isRunning,
    required this.currentPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vcurvePoints.isEmpty) return;

    const padding = EdgeInsets.fromLTRB(36, 8, 8, 20);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    if (chartArea.width <= 0 || chartArea.height <= 0) return;

    // Extract data
    final positions = vcurvePoints.map((p) => p.position).toList();
    final hfrs = vcurvePoints.map((p) => p.hfr).toList();

    // Use focus range if available, otherwise compute from data
    final minPos = focusRange?.min ??
        positions.reduce((a, b) => a < b ? a : b);
    final maxPos = focusRange?.max ??
        positions.reduce((a, b) => a > b ? a : b);
    final minHfr = hfrs.reduce((a, b) => a < b ? a : b);
    final maxHfr = hfrs.reduce((a, b) => a > b ? a : b);

    final posRange = (maxPos - minPos).toDouble();
    final hfrPadding = (maxHfr - minHfr) * 0.15;
    final displayMinHfr = math.max(0.0, minHfr - hfrPadding);
    final displayMaxHfr = maxHfr + hfrPadding;
    final hfrRange = displayMaxHfr - displayMinHfr;

    if (posRange == 0 || hfrRange == 0) return;

    double toX(int position) =>
        chartArea.left + (position - minPos) / posRange * chartArea.width;
    double toY(double hfr) =>
        chartArea.bottom - (hfr - displayMinHfr) / hfrRange * chartArea.height;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = chartArea.top + (chartArea.height * i / 3);
      canvas.drawLine(
        Offset(chartArea.left, y),
        Offset(chartArea.right, y),
        gridPaint,
      );
    }

    // Draw the V-curve line (sorted by position so the line forms a clean V)
    if (vcurvePoints.length > 1) {
      final linePaint = Paint()
        ..color = accentColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final sortedPoints = List.of(vcurvePoints)
        ..sort((a, b) => a.position.compareTo(b.position));

      final path = Path();
      for (var i = 0; i < sortedPoints.length; i++) {
        final p = sortedPoints[i];
        final x = toX(p.position);
        final y = toY(p.hfr);
        if (x.isNaN || y.isNaN || x.isInfinite || y.isInfinite) continue;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Draw data points
    final pointPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < vcurvePoints.length; i++) {
      final p = vcurvePoints[i];
      final x = toX(p.position);
      final y = toY(p.hfr);
      if (x.isNaN || y.isNaN || x.isInfinite || y.isInfinite) continue;
      final isBest = bestPosition != null && p.position == bestPosition;
      final isLatest = i == vcurvePoints.length - 1 && isRunning;

      if (isBest) {
        // Draw best point with success color
        final bestPaint = Paint()
          ..color = successColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), 5, bestPaint);
        final ringPaint = Paint()
          ..color = successColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(x, y), 8, ringPaint);
      } else if (isLatest) {
        // Highlight latest point while running
        canvas.drawCircle(Offset(x, y), 4, pointPaint);
        final ringPaint = Paint()
          ..color = accentColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(x, y), 7, ringPaint);
      } else {
        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }

    // Draw axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Y-axis label
    textPainter.text = TextSpan(
      text: 'HFR',
      style: TextStyle(color: textColor, fontSize: 8),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(4, chartArea.top));

    // X-axis label
    textPainter.text = TextSpan(
      text: 'Position',
      style: TextStyle(color: textColor, fontSize: 8),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(chartArea.center.dx - textPainter.width / 2, size.height - 12),
    );

    // Min/max HFR labels
    textPainter.text = TextSpan(
      text: displayMaxHfr.toStringAsFixed(1),
      style: TextStyle(color: textColor, fontSize: 7),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(chartArea.left - textPainter.width - 2, chartArea.top - 4),
    );

    textPainter.text = TextSpan(
      text: displayMinHfr.toStringAsFixed(1),
      style: TextStyle(color: textColor, fontSize: 7),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(chartArea.left - textPainter.width - 2, chartArea.bottom - 6),
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayVCurvePainter oldDelegate) {
    return vcurvePoints.length != oldDelegate.vcurvePoints.length ||
        bestPosition != oldDelegate.bestPosition ||
        currentPoint != oldDelegate.currentPoint ||
        isRunning != oldDelegate.isRunning;
  }
}
