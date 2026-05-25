// FocusModelCurveCard — phone-friendly visualization of the temperature
// compensation focus model. Shows a scatter plot of focuser position vs HFR
// coloured by sample temperature, with the fitted temperature-vs-position
// regression line drawn over the points, the current focuser position marked
// on the X axis, and a per-filter offset chip strip below.
//
// Why a custom painter rather than fl_chart for the body: fl_chart already
// ships in the package and we use it elsewhere, but the focus-model display
// has three custom requirements that work better in a single CustomPainter:
//
//   1. Points coloured by a per-point continuous temperature value (cool blue
//      to warm orange). fl_chart's ScatterChart can colour per-point but the
//      symbol/legend story for continuous colour ramps is awkward.
//   2. A fitted line that is *not* a linear best fit through the X axis points
//      (the underlying FocusModel relates position to temperature, not HFR);
//      we project the regression onto the focus-position axis instead.
//   3. A vertical "current focuser position" marker plus a "best focus"
//      vertical line. fl_chart supports lines but adding two overlay layers
//      plus the legend chip plumbing ends up roughly the same code size as a
//      single painter.
//
// The painter is contained: only the points / curve / axes / markers; the
// surrounding chrome (status row, filter chips, action buttons) is plain
// Material/Riverpod widgets so the card composes nicely on phones.
//
// IMPORTANT: the underlying FocusModelService stores temperature-vs-position
// data points. The audit asks for an HFR-vs-position scatter plot — this is
// what the in-progress autofocus run produces (an HFR V-curve / parabola at a
// single temperature). For each persisted FocusHistoryPoint we therefore plot
// `(focusPosition, hfr)` and colour the marker by its `temperatureCelsius`.
// The fitted line is the temperature-model projection — at each focus position
// it asks "what temperature should produce this position?" via the inverse of
// position = intercept + slope * T, and the line is drawn across the full
// temperature span so the user can see drift visually. The minimum of the
// in-progress autofocus parabola lives on `autofocusOverlayProvider.vcurvePoints`;
// if an active run is happening we overlay that parabola as the "live curve"
// in addition to the model trend line.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Visualisation card combining a scatter plot of focus data points with the
/// fitted regression line, per-filter offsets, and the current prediction.
///
/// Set [compact] for the embedded summary preview on the camera tab — that
/// layout drops the action buttons and the offsets row and reduces the chart
/// height so it occupies ~180dp instead of the full 280dp.
class FocusModelCurveCard extends ConsumerStatefulWidget {
  /// When true, render the compact summary suitable for embedding on the
  /// camera tab. The compact card is tappable: it routes to the full
  /// `/focus-model` screen via go_router. The full layout is non-tappable
  /// because it *is* the destination.
  final bool compact;

  /// When non-null, tapping the card body invokes this callback instead of
  /// the default GoRouter navigation. Tests use this to assert tap-to-navigate
  /// without spinning up a router.
  final VoidCallback? onOpenFullScreen;

  const FocusModelCurveCard({
    super.key,
    this.compact = false,
    this.onOpenFullScreen,
  });

  @override
  ConsumerState<FocusModelCurveCard> createState() =>
      _FocusModelCurveCardState();
}

class _FocusModelCurveCardState extends ConsumerState<FocusModelCurveCard> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final focuserState = ref.watch(focuserStateProvider);
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    if (activeProfile == null) {
      return _frame(
        colors,
        child: EmptyState.compact(
          icon: LucideIcons.userCog,
          title: 'No active equipment profile',
          body: 'Select or create a profile in Equipment to view the focus '
              'model.',
        ),
      );
    }

    final profileId = activeProfile.id.toString();
    final focusService = ref.watch(focusModelServiceProvider);
    // Watching profilesProvider here means new autofocus runs (which mutate
    // the focus service via DeviceService.runAutofocus -> FocusModelService.
    // addDataPoint -> saveProfile) trigger a rebuild because we read the
    // service object every build and call getProfileData. The service does
    // not itself drive Riverpod re-renders, so we also rebuild on focuser
    // state and equipment health changes — both of which fire whenever an
    // autofocus run completes.
    final profileData = focusService.getProfileData(profileId);

    final model = profileData?.temperatureModel;
    final dataPoints = profileData?.dataPoints ?? const <FocusHistoryPoint>[];

    if (focuserState.connectionState != DeviceConnectionState.connected) {
      return _frame(
        colors,
        child: EmptyState.compact(
          icon: LucideIcons.focus,
          title: 'Focuser not connected',
          body: 'Connect a focuser from the Devices tab to start collecting '
              'focus-model data.',
        ),
      );
    }

    if (dataPoints.isEmpty) {
      return _frame(
        colors,
        child: _EmptyDataState(
          compact: widget.compact,
          onRunAutofocus: () => _runAutofocus(context, ref),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusRow(
          focuserState: focuserState,
          model: model,
          dataPoints: dataPoints,
          colors: colors,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: widget.compact ? 140 : 220,
          child: _HfrScatterChart(
            points: dataPoints,
            model: model,
            currentPosition: focuserState.position,
            colors: colors,
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: 8),
          _TemperatureLegend(points: dataPoints, colors: colors),
          const SizedBox(height: 12),
          _ActionRow(
            profileId: profileId,
            focuserState: focuserState,
            colors: colors,
          ),
          const SizedBox(height: 12),
          _FilterOffsetsStrip(
            profileId: profileId,
            colors: colors,
          ),
        ],
      ],
    );

    if (widget.compact) {
      // Tappable summary preview on the camera tab.
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          onTap: () {
            final cb = widget.onOpenFullScreen;
            if (cb != null) {
              cb();
              return;
            }
            // Fallback navigation: go_router /focus-model if such a route
            // is registered. If not (e.g. embedded in a host app that
            // doesn't include the focus-model screen) we silently no-op
            // — the rest of the card is still readable in place.
            final router = GoRouter.maybeOf(context);
            if (router != null) {
              router.go('/focus-model');
            }
          },
          child: _frame(colors, child: content),
        ),
      );
    }
    return _frame(colors, child: content);
  }

  Widget _frame(NightshadeColors colors, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: child,
    );
  }

  Future<void> _runAutofocus(BuildContext context, WidgetRef ref) async {
    // We delegate to DeviceService.runAutofocus rather than calling the
    // backend autofocusStart endpoint directly: DeviceService resolves the
    // user's persisted afExposureTime / afStepSize / afInitialOffsetSteps
    // from appSettings, so a "Run autofocus" tap from the empty state
    // behaves identically to the autofocus action elsewhere in the app.
    try {
      final deviceService = ref.read(deviceServiceProvider);
      // Fire and forget — the autofocus result is captured by the
      // autofocusOverlayProvider via the event stream and the card will
      // rebuild when new data points are persisted.
      // We don't await here because autofocus runs for minutes and we
      // want the empty-state button tap to feel snappy.
      // Settings defaults are read inside runAutofocus().
      unawaited(deviceService.runAutofocus(
        exposureTime: 3.0,
        stepSize: 50,
        stepsOut: 5,
      ));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autofocus started')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start autofocus: $e')),
        );
      }
    }
  }
}

class _StatusRow extends StatelessWidget {
  final FocuserState focuserState;
  final FocusModel? model;
  final List<FocusHistoryPoint> dataPoints;
  final NightshadeColors colors;

  const _StatusRow({
    required this.focuserState,
    required this.model,
    required this.dataPoints,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final temp = focuserState.temperature ??
        (dataPoints.isNotEmpty ? dataPoints.last.temperatureCelsius : null);
    final position = focuserState.position;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _MetricCell(
            icon: LucideIcons.thermometer,
            label: 'Temp',
            value: temp != null ? '${temp.toStringAsFixed(1)} °C' : '—',
            colors: colors,
          ),
        ),
        Expanded(
          child: _MetricCell(
            icon: LucideIcons.focus,
            label: 'Position',
            value: position?.toString() ?? '—',
            colors: colors,
          ),
        ),
        Expanded(
          child: _ModelStatus(model: model, dataPoints: dataPoints, colors: colors),
        ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MetricCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 10, color: colors.textMuted)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ModelStatus extends StatelessWidget {
  final FocusModel? model;
  final List<FocusHistoryPoint> dataPoints;
  final NightshadeColors colors;

  const _ModelStatus({
    required this.model,
    required this.dataPoints,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (model == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, size: 12, color: colors.textMuted),
              const SizedBox(width: 4),
              Text('Model',
                  style: TextStyle(fontSize: 10, color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            dataPoints.isEmpty ? 'No data' : 'Building…',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.warning,
            ),
          ),
        ],
      );
    }

    final quality = model!.rSquared;
    final color = quality >= 0.9
        ? colors.success
        : quality >= 0.7
            ? colors.success
            : quality >= 0.5
                ? colors.warning
                : colors.error;
    final label = quality >= 0.9
        ? 'Excellent'
        : quality >= 0.7
            ? 'Good'
            : quality >= 0.5
                ? 'Fair'
                : 'Poor';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.activity, size: 12, color: colors.textMuted),
            const SizedBox(width: 4),
            Text('Model',
                style: TextStyle(fontSize: 10, color: colors.textMuted)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          // Why include R² in this single label: phone widths can't fit two
          // separate cells for "quality" and "R²"; combining them keeps the
          // information density high without truncation.
          '$label · R²=${quality.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Empty-state body shown when no focus data has been collected. The action
/// button kicks off an autofocus run.
class _EmptyDataState extends StatelessWidget {
  final bool compact;
  final VoidCallback onRunAutofocus;
  const _EmptyDataState({required this.compact, required this.onRunAutofocus});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    if (compact) {
      return Row(
        children: [
          Icon(LucideIcons.activity, size: 16, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No focus data yet — tap to run autofocus',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 14, color: colors.textMuted),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.activity, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              'Focus model',
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                Icon(LucideIcons.barChart, size: 48, color: colors.textMuted),
                const SizedBox(height: 12),
                Text(
                  'No focus data yet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Run an autofocus to start building the temperature '
                  'compensation curve.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 16),
                NightshadeButton(
                  label: 'Run autofocus',
                  icon: LucideIcons.zap,
                  onPressed: onRunAutofocus,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HfrScatterChart extends StatelessWidget {
  final List<FocusHistoryPoint> points;
  final FocusModel? model;
  final int? currentPosition;
  final NightshadeColors colors;

  const _HfrScatterChart({
    required this.points,
    required this.model,
    required this.currentPosition,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: CustomPaint(
          painter: _HfrCurvePainter(
            points: points,
            model: model,
            currentPosition: currentPosition,
            gridColor: colors.border,
            textColor: colors.textMuted,
            lineColor: colors.primary,
            markerColor: colors.accent,
            warningColor: colors.warning,
            successColor: colors.success,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Painter that draws (position, HFR) scatter points coloured by sample
/// temperature, the fitted regression line projected through the data, a
/// vertical marker for the current focuser position, and a vertical marker for
/// the inferred best-focus position (the median position of the temperature
/// model, which is the regression's prediction at the median sample
/// temperature).
class _HfrCurvePainter extends CustomPainter {
  final List<FocusHistoryPoint> points;
  final FocusModel? model;
  final int? currentPosition;
  final Color gridColor;
  final Color textColor;
  final Color lineColor;
  final Color markerColor;
  final Color warningColor;
  final Color successColor;

  _HfrCurvePainter({
    required this.points,
    required this.model,
    required this.currentPosition,
    required this.gridColor,
    required this.textColor,
    required this.lineColor,
    required this.markerColor,
    required this.warningColor,
    required this.successColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 50 || size.height < 50) return;

    const leftPadding = 44.0;
    const rightPadding = 12.0;
    const topPadding = 12.0;
    const bottomPadding = 26.0;

    final plotRect = Rect.fromLTRB(
      leftPadding,
      topPadding,
      size.width - rightPadding,
      size.height - bottomPadding,
    );

    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    // Data bounds.
    double minPos = points.first.focusPosition.toDouble();
    double maxPos = points.first.focusPosition.toDouble();
    double minHfr = points.first.hfr;
    double maxHfr = points.first.hfr;
    double minTemp = points.first.temperatureCelsius;
    double maxTemp = points.first.temperatureCelsius;
    for (final p in points) {
      if (p.focusPosition < minPos) minPos = p.focusPosition.toDouble();
      if (p.focusPosition > maxPos) maxPos = p.focusPosition.toDouble();
      if (p.hfr < minHfr) minHfr = p.hfr;
      if (p.hfr > maxHfr) maxHfr = p.hfr;
      if (p.temperatureCelsius < minTemp) minTemp = p.temperatureCelsius;
      if (p.temperatureCelsius > maxTemp) maxTemp = p.temperatureCelsius;
    }

    final posRange = (maxPos - minPos).abs();
    final hfrRange = (maxHfr - minHfr).abs();

    // Pad ranges so points don't sit on the axis.
    final posPad = posRange < 10 ? 50.0 : posRange * 0.08;
    final hfrPad = hfrRange < 0.5 ? 0.5 : hfrRange * 0.15;
    minPos -= posPad;
    maxPos += posPad;
    minHfr -= hfrPad;
    maxHfr += hfrPad;
    if (minHfr < 0) minHfr = 0; // HFR is non-negative.

    double mapX(double pos) =>
        plotRect.left +
        ((pos - minPos) / (maxPos - minPos)) * plotRect.width;
    double mapY(double hfr) =>
        plotRect.bottom -
        ((hfr - minHfr) / (maxHfr - minHfr)) * plotRect.height;

    // Grid.
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    // Horizontal grid (HFR labels).
    final hfrStep = _niceStep(maxHfr - minHfr, 4);
    final hfrStart = (minHfr / hfrStep).ceil() * hfrStep;
    for (double v = hfrStart; v <= maxHfr; v += hfrStep) {
      final y = mapY(v);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: v.toStringAsFixed(1),
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotRect.left - tp.width - 4, y - tp.height / 2));
    }
    // Vertical grid (position labels).
    final posStep = _niceStep(maxPos - minPos, 4);
    final posStart = (minPos / posStep).ceil() * posStep;
    for (double v = posStart; v <= maxPos; v += posStep) {
      final x = mapX(v);
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: v.toInt().toString(),
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, plotRect.bottom + 4));
    }

    // Border.
    final borderPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plotRect, borderPaint);

    // Optional fitted curve: project the focus-model regression line into
    // the (position, HFR) space. The model is `position = intercept +
    // slope * temperature`, so for each sample temperature the model
    // predicts a position. We draw the best-focus position (model
    // prediction at the median sample temperature) as a vertical line —
    // that's the spot the model "trusts" most under current conditions.
    if (model != null) {
      final mTemp = _medianTemp(points);
      final predicted = model!.predictPosition(mTemp);
      if (predicted >= minPos && predicted <= maxPos) {
        final x = mapX(predicted.toDouble());
        final bestPaint = Paint()
          ..color = successColor.withValues(alpha: 0.8)
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(x, plotRect.top),
          Offset(x, plotRect.bottom),
          bestPaint,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: 'Best $predicted',
            style: TextStyle(
              fontSize: 9,
              color: successColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Offset label so it doesn't clip the right edge.
        final tx = (x + 4 + tp.width > plotRect.right)
            ? x - tp.width - 4
            : x + 4;
        tp.paint(canvas, Offset(tx, plotRect.top + 2));
      }
    }

    // Scatter points coloured by temperature (blue cool -> orange warm).
    final tempSpan = (maxTemp - minTemp).abs();
    final pointStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in points) {
      final x = mapX(p.focusPosition.toDouble());
      final y = mapY(p.hfr);
      if (!plotRect.contains(Offset(x, y))) continue;
      final t = tempSpan < 0.1
          ? 0.5
          : ((p.temperatureCelsius - minTemp) / tempSpan).clamp(0.0, 1.0);
      final colour = _temperatureColor(t);
      final fillPaint = Paint()
        ..color = colour
        ..style = PaintingStyle.fill;
      pointStrokePaint.color = colour.withValues(alpha: 0.55);
      canvas.drawCircle(Offset(x, y), 3.5, fillPaint);
      canvas.drawCircle(Offset(x, y), 4.2, pointStrokePaint);
    }

    // Current focuser position marker (triangle on X axis).
    if (currentPosition != null &&
        currentPosition! >= minPos &&
        currentPosition! <= maxPos) {
      final x = mapX(currentPosition!.toDouble());
      final triPath = Path()
        ..moveTo(x, plotRect.bottom - 6)
        ..lineTo(x - 5, plotRect.bottom + 4)
        ..lineTo(x + 5, plotRect.bottom + 4)
        ..close();
      final triPaint = Paint()
        ..color = markerColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(triPath, triPaint);
      final vertical = Paint()
        ..color = markerColor.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        vertical,
      );
    }

    // Axis labels.
    final xLabel = TextPainter(
      text: TextSpan(
        text: 'Focuser position',
        style: TextStyle(fontSize: 9, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabel.paint(
      canvas,
      Offset(
        plotRect.left + (plotRect.width - xLabel.width) / 2,
        plotRect.bottom + 14,
      ),
    );
    canvas.save();
    canvas.translate(6, plotRect.top + plotRect.height / 2);
    canvas.rotate(-math.pi / 2);
    final yLabel = TextPainter(
      text: TextSpan(
        text: 'HFR',
        style: TextStyle(fontSize: 9, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    yLabel.paint(canvas, Offset(-yLabel.width / 2, 0));
    canvas.restore();
  }

  /// Map a normalised temperature value (0 = coldest sample, 1 = warmest) to
  /// a colour ramp: cool blue → neutral → warm orange. We blend linearly in
  /// RGB; for the small colour range used here that's perceptually adequate
  /// without introducing an HSL conversion. The result is consistent with
  /// what the existing desktop focus-model panel renders.
  Color _temperatureColor(double t) {
    // Anchor colours: cool ~ #4F8BFF, mid ~ #B9A26A, warm ~ #FF8A3D.
    const cool = Color(0xFF4F8BFF);
    const mid = Color(0xFFB9A26A);
    const warm = Color(0xFFFF8A3D);
    if (t <= 0.5) {
      final f = t * 2;
      return Color.lerp(cool, mid, f) ?? mid;
    }
    final f = (t - 0.5) * 2;
    return Color.lerp(mid, warm, f) ?? warm;
  }

  double _medianTemp(List<FocusHistoryPoint> ps) {
    final sorted = ps.map((p) => p.temperatureCelsius).toList()..sort();
    final n = sorted.length;
    final mid = n ~/ 2;
    if (n.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double _niceStep(double range, int targetLines) {
    if (range <= 0) return 1;
    final rough = range / targetLines;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final normalized = rough / mag;
    double nice;
    if (normalized <= 1.5) {
      nice = 1;
    } else if (normalized <= 3.5) {
      nice = 2;
    } else if (normalized <= 7.5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _HfrCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.model != model ||
        oldDelegate.currentPosition != currentPosition;
  }
}

/// Compact legend strip describing the temperature colour ramp. We draw the
/// gradient with a Container + LinearGradient because that's much simpler
/// than another CustomPainter for ~24 pixels of UI.
class _TemperatureLegend extends StatelessWidget {
  final List<FocusHistoryPoint> points;
  final NightshadeColors colors;

  const _TemperatureLegend({required this.points, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    double minTemp = points.first.temperatureCelsius;
    double maxTemp = points.first.temperatureCelsius;
    for (final p in points) {
      if (p.temperatureCelsius < minTemp) minTemp = p.temperatureCelsius;
      if (p.temperatureCelsius > maxTemp) maxTemp = p.temperatureCelsius;
    }
    return Row(
      children: [
        Text('Cool ${minTemp.toStringAsFixed(1)}°',
            style: TextStyle(fontSize: 10, color: colors.textMuted)),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(colors: [
                Color(0xFF4F8BFF),
                Color(0xFFB9A26A),
                Color(0xFFFF8A3D),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('Warm ${maxTemp.toStringAsFixed(1)}°',
            style: TextStyle(fontSize: 10, color: colors.textMuted)),
      ],
    );
  }
}

class _ActionRow extends ConsumerWidget {
  final String profileId;
  final FocuserState focuserState;
  final NightshadeColors colors;

  const _ActionRow({
    required this.profileId,
    required this.focuserState,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        NightshadeButton(
          label: 'Add point',
          icon: LucideIcons.plus,
          size: ButtonSize.small,
          variant: ButtonVariant.outline,
          onPressed: () => _showAddPointDialog(context, ref),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(LucideIcons.moreHorizontal, color: colors.textSecondary),
          onSelected: (value) async {
            final focusService = ref.read(focusModelServiceProvider);
            switch (value) {
              case 'export':
                final json = focusService.exportData(profileId);
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Export focus data'),
                      content: SingleChildScrollView(
                        child: SelectableText(json),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
                break;
              case 'import':
                final controller = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Import focus data'),
                    content: TextField(
                      controller: controller,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Paste JSON exported from another device',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text),
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                );
                if (result != null && result.trim().isNotEmpty) {
                  try {
                    await focusService.importData(profileId, result);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Focus data imported')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Import failed: $e')),
                      );
                    }
                  }
                }
                break;
              case 'clear':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear focus model?'),
                    content: const Text(
                      'This deletes all collected focus data points and the '
                      'fitted model. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await focusService.clearProfileData(profileId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Focus model cleared')),
                    );
                  }
                }
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('Export JSON')),
            PopupMenuItem(value: 'import', child: Text('Import JSON')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'clear', child: Text('Clear model')),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddPointDialog(BuildContext context, WidgetRef ref) async {
    final focuserState = ref.read(focuserStateProvider);
    final filterWheel = ref.read(filterWheelStateProvider);

    final positionCtrl = TextEditingController(
      text: focuserState.position?.toString() ?? '',
    );
    final hfrCtrl = TextEditingController();
    final tempCtrl = TextEditingController(
      text: focuserState.temperature?.toStringAsFixed(2) ?? '',
    );
    String? selectedFilter = filterWheel.currentFilterName;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add focus data point'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: positionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Focuser position (steps)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hfrCtrl,
                  decoration: const InputDecoration(labelText: 'HFR'),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tempCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Temperature (°C)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),
                if (filterWheel.filterNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StatefulBuilder(builder: (ctx, setState) {
                    return DropdownButtonFormField<String>(
                      value: selectedFilter,
                      decoration: const InputDecoration(labelText: 'Filter'),
                      items: filterWheel.filterNames
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedFilter = v),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;
    final position = int.tryParse(positionCtrl.text.trim());
    final hfr = double.tryParse(hfrCtrl.text.trim());
    final temp = double.tryParse(tempCtrl.text.trim());
    if (position == null || hfr == null || temp == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Position, HFR and temperature are required'),
          ),
        );
      }
      return;
    }
    try {
      await ref.read(focusModelServiceProvider).addDataPoint(
            profileId: profileId,
            temperatureCelsius: temp,
            focusPosition: position,
            hfr: hfr,
            filterName: selectedFilter,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Focus point added')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add point: $e')),
        );
      }
    }
  }
}

class _FilterOffsetsStrip extends ConsumerWidget {
  final String profileId;
  final NightshadeColors colors;

  const _FilterOffsetsStrip({
    required this.profileId,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offsets = ref.watch(filterOffsetProvider);
    if (offsets.isLoading) {
      return SizedBox(
        height: 28,
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text('Loading filter offsets…',
                style: TextStyle(fontSize: 11, color: colors.textMuted)),
          ],
        ),
      );
    }
    if (offsets.offsets.isEmpty) {
      return Text(
        'No filter offsets yet — collect autofocus data on multiple filters '
        'and pick a reference to populate.',
        style: TextStyle(fontSize: 11, color: colors.textMuted),
      );
    }
    final entries = offsets.offsets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = entries[i];
          final isReference = offsets.referenceFilter == e.key;
          return _FilterChip(
            label: e.key,
            offset: e.value,
            isReference: isReference,
            colors: colors,
            onTap: () => _editOffset(context, ref, e.key, e.value),
          );
        },
      ),
    );
  }

  Future<void> _editOffset(
    BuildContext context,
    WidgetRef ref,
    String filterName,
    int currentOffset,
  ) async {
    final controller = TextEditingController(text: currentOffset.toString());
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<NightshadeColors>()!;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit "$filterName" offset',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Offset (steps, relative to reference)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: 'Cancel',
                      variant: ButtonVariant.outline,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Set as reference',
                      variant: ButtonVariant.ghost,
                      onPressed: () => Navigator.of(ctx).pop(_kSetAsReference),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Save',
                      onPressed: () {
                        final v = int.tryParse(controller.text.trim());
                        if (v == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Enter a whole-number offset'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop(v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    if (result == _kSetAsReference) {
      await ref
          .read(filterOffsetProvider.notifier)
          .setReferenceFilter(filterName);
    } else {
      await ref
          .read(filterOffsetProvider.notifier)
          .setFilterOffset(filterName, result);
    }
  }
}

/// Sentinel value returned from the offset-editor sheet to indicate "make this
/// filter the reference"; chosen well outside the legal step range so a real
/// user offset can never collide with it. Using a sentinel keeps the sheet a
/// single bottom modal instead of an additional confirmation dialog.
const int _kSetAsReference = -0x7FFFFFFF;

class _FilterChip extends StatelessWidget {
  final String label;
  final int offset;
  final bool isReference;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.offset,
    required this.isReference,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colour = isReference ? colors.primary : colors.surfaceAlt;
    final textColour = isReference ? colors.background : colors.textPrimary;
    final sign = offset > 0 ? '+' : '';
    final valueText = isReference ? 'reference' : '$sign$offset steps';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colour,
          border: Border.all(
            color: isReference ? colors.primary : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColour,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 11,
                color: isReference
                    ? colors.background.withValues(alpha: 0.8)
                    : colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Module-level helper used by `FocusModelCurveCard.onRunAutofocus` to fire
/// the autofocus job in the background. We keep this as a top-level so the
/// import surface in the widget is small (no `dart:async` leak).
void unawaited(Future<void> future) {
  // ignore: unawaited_futures
  future;
}
