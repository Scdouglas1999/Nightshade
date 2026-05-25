// Wave 7.5 — Run-dashboard live light-curve panel for the
// SciencePhotometryNode (Wave 7 Agent 4).
//
// Data flow:
//   Rust executor emits ProgressDetail::PhotometryFrame for each frame
//     -> Dart science_processing_service writes a row to
//        photometry_measurements (one per (object, timestamp))
//     -> Drift stream in sessionPhotometryProvider fires
//     -> sessionLightCurveProvider rebuilds a per-target LightCurvePoint
//        list, which this panel renders as a magnitude-vs-time chart.
//
// The panel mounts only when a SciencePhotometryNode has executed at
// least one frame in the current run. Visibility is driven by a small
// notifier (`lightCurveActivityProvider`) that listens to the executor's
// InstructionProgress stream and remembers the last Science Photometry
// target / filter / cadence-break counter.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class LightCurvePanel extends ConsumerWidget {
  const LightCurvePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final session = ref.watch(sessionStateProvider);
    final activity = ref.watch(lightCurveActivityProvider);

    // Visibility rule: hide until we've seen a Science Photometry event
    // in this run. After the first frame the panel sticks around for
    // the rest of the run so the operator can still review the curve
    // once the burst has finished.
    if (!activity.hasSeenPhotometry) {
      return const SizedBox.shrink();
    }

    final sessionId = session.dbSessionId;
    if (sessionId == null) {
      return _buildShell(
        colors,
        child: _emptyState(
          colors,
          'No active session yet — waiting for the executor to '
          'announce a Photometry burst.',
        ),
      );
    }

    final targetDesignation = activity.lastTargetDesignation;
    if (targetDesignation == null || targetDesignation.isEmpty) {
      return _buildShell(
        colors,
        child: _emptyState(colors, 'Awaiting first photometry frame…'),
      );
    }

    final points = ref.watch(
      sessionLightCurveProvider((sessionId, targetDesignation)),
    );

    return _buildShell(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            colors: colors,
            target: targetDesignation,
            filter: activity.lastFilter,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (points.isEmpty)
            _emptyState(
              colors,
              'Frames captured but the science pipeline has not yet '
              'written photometry rows.',
            )
          else ...[
            _SummaryRow(
              colors: colors,
              points: points,
              cadenceBreaks: activity.cadenceBreaks,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _LightCurvePainter(
                  points: points,
                  primary: colors.primary,
                  axis: colors.border,
                  text: colors.textMuted,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShell(NightshadeColors colors, {required Widget child}) {
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: child,
    );
  }

  Widget _emptyState(NightshadeColors colors, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(LucideIcons.lineChart, size: 14, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Header / summary widgets
// ============================================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.target,
    required this.filter,
  });

  final NightshadeColors colors;
  final String target;
  final String? filter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.lineChart, size: 14, color: colors.primary),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'LIGHT CURVE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textMuted,
          ),
        ),
        const Spacer(),
        Text(
          filter == null ? target : '$target · $filter',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.colors,
    required this.points,
    required this.cadenceBreaks,
  });

  final NightshadeColors colors;
  final List<LightCurvePoint> points;
  final int cadenceBreaks;

  @override
  Widget build(BuildContext context) {
    final latest = points.last;
    final mag = latest.differentialMagnitude;
    final snr = latest.snr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _Metric(label: 'frames', value: '${points.length}', colors: colors),
        const SizedBox(width: NightshadeTokens.spaceLg),
        _Metric(
          label: 'Δmag',
          value: mag == 0 ? '—' : mag.toStringAsFixed(3),
          colors: colors,
        ),
        const SizedBox(width: NightshadeTokens.spaceLg),
        _Metric(
          label: 'snr',
          value: snr == 0 ? '—' : snr.toStringAsFixed(0),
          colors: colors,
        ),
        const Spacer(),
        if (cadenceBreaks > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: NightshadeDecorations.statusChip(
              colors.warning,
              borderRadius: BorderRadius.circular(4),
              bordered: false,
            ),
            child: Text(
              '$cadenceBreaks cadence break${cadenceBreaks == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.warning,
              ),
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.h4.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Painter — magnitude (Δmag) vs time
// ============================================================================

class _LightCurvePainter extends CustomPainter {
  _LightCurvePainter({
    required this.points,
    required this.primary,
    required this.axis,
    required this.text,
  });

  final List<LightCurvePoint> points;
  final Color primary;
  final Color axis;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final sorted = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final tStart = sorted.first.timestamp.millisecondsSinceEpoch.toDouble();
    final tEnd = sorted.last.timestamp.millisecondsSinceEpoch.toDouble();
    final tSpan = (tEnd - tStart).abs() < 1 ? 1.0 : tEnd - tStart;

    // Magnitude axis: plot diff-mag when present, else instrumental
    // magnitude derived from flux (Pogson: -2.5 log10(flux)). If flux
    // is zero we plot the raw value so the chart still shows something
    // rather than silently dropping the frame.
    final values = <double>[];
    for (final p in sorted) {
      if (p.differentialMagnitude != 0) {
        values.add(p.differentialMagnitude);
      } else if (p.flux > 0) {
        values.add(-2.5 * (math.log(p.flux) / math.ln10));
      } else {
        values.add(p.flux);
      }
    }
    final yMin = values.reduce((a, b) => a < b ? a : b);
    final yMax = values.reduce((a, b) => a > b ? a : b);
    final ySpan = (yMax - yMin).abs() < 1e-6 ? 1.0 : (yMax - yMin);

    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // Y-axis (left), X-axis (bottom).
    canvas.drawLine(Offset.zero, Offset(0, size.height), axisPaint);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    // Min/max magnitude labels. Magnitudes are conventionally plotted
    // with smaller (brighter) values at the top; the painter inverts y
    // accordingly so the chart reads like a published light curve.
    _paintText(canvas, yMin.toStringAsFixed(2), const Offset(4, 2), text);
    _paintText(
      canvas,
      yMax.toStringAsFixed(2),
      Offset(4, size.height - 14),
      text,
    );

    if (sorted.length == 1) {
      // Single point → draw a dot centered horizontally.
      final v = values.first;
      final yNorm = (v - yMin) / ySpan;
      final y = (1.0 - yNorm) * size.height;
      canvas.drawCircle(
        Offset(size.width / 2, y),
        3.0,
        Paint()..color = primary,
      );
      return;
    }

    final linePaint = Paint()
      ..color = primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = primary;

    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      final tNorm = (p.timestamp.millisecondsSinceEpoch - tStart) / tSpan;
      // Inverted axis (1 - yNorm): brighter mags higher on the canvas.
      final yNorm = (values[i] - yMin) / ySpan;
      final x = tNorm * size.width;
      final y = (1.0 - yNorm) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: NightshadeTypography.withTabular(
          TextStyle(fontSize: 9, color: color),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LightCurvePainter old) {
    if (old.points.length != points.length) return true;
    if (identical(old.points, points)) return false;
    if (old.points.isEmpty || points.isEmpty) return true;
    return old.points.last.timestamp != points.last.timestamp;
  }
}

// ============================================================================
// Activity provider — listens for Science Photometry executor events
// ============================================================================

/// Snapshot of what the light-curve panel knows about the currently-
/// executing (or most recently executed) photometry node in this run.
class LightCurveActivity {
  final bool hasSeenPhotometry;
  final String? lastTargetDesignation;
  final String? lastFilter;
  final int framesCaptured;
  final int cadenceBreaks;
  final DateTime? lastFrameAt;

  const LightCurveActivity({
    this.hasSeenPhotometry = false,
    this.lastTargetDesignation,
    this.lastFilter,
    this.framesCaptured = 0,
    this.cadenceBreaks = 0,
    this.lastFrameAt,
  });

  LightCurveActivity copyWith({
    bool? hasSeenPhotometry,
    String? lastTargetDesignation,
    String? lastFilter,
    int? framesCaptured,
    int? cadenceBreaks,
    DateTime? lastFrameAt,
  }) {
    return LightCurveActivity(
      hasSeenPhotometry: hasSeenPhotometry ?? this.hasSeenPhotometry,
      lastTargetDesignation:
          lastTargetDesignation ?? this.lastTargetDesignation,
      lastFilter: lastFilter ?? this.lastFilter,
      framesCaptured: framesCaptured ?? this.framesCaptured,
      cadenceBreaks: cadenceBreaks ?? this.cadenceBreaks,
      lastFrameAt: lastFrameAt ?? this.lastFrameAt,
    );
  }

  static const empty = LightCurveActivity();
}

/// Subscribes to the executor event stream and observes the
/// `InstructionProgress` payload from the Science Photometry node. The
/// Rust side stringifies `ProgressDetail::PhotometryFrame` /
/// `PhotometryCadenceBroken` / `PhotometrySummary` via
/// `ProgressDetail::detail_text()`; we only need the target name +
/// filter + cadence-break counter (the chart proper subscribes to the
/// Drift-backed `sessionPhotometryProvider`).
class _LightCurveActivityNotifier extends StateNotifier<LightCurveActivity> {
  _LightCurveActivityNotifier(this._ref) : super(LightCurveActivity.empty) {
    _wire();
  }

  final Ref _ref;
  StreamSubscription<NightshadeEvent>? _subscription;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  void _wire() {
    void resubscribe(NightshadeBackend backend) {
      _subscription?.cancel();
      _subscription = backend.eventStream.listen(_onEvent);
    }

    resubscribe(_ref.read(backendProvider));
    _backendSubscription =
        _ref.listen<NightshadeBackend>(backendProvider, (_, next) {
      resubscribe(next);
    });
  }

  void _onEvent(NightshadeEvent event) {
    if (event.category != EventCategory.sequencer) return;
    if (event.eventType == 'Started') {
      // New run — reset state so a fresh sequence doesn't render the
      // previous run's curve.
      state = LightCurveActivity.empty;
      return;
    }
    if (event.eventType != 'InstructionProgress') return;

    final instruction =
        event.data['instruction'] is String ? event.data['instruction'] as String : null;
    if (instruction != 'Science Photometry') return;
    final detail = event.data['detail'];
    if (detail is! String) return;

    // The detail string formats are emitted by
    // `ProgressDetail::detail_text()` (Rust). We parse just the bits we
    // need; the Drift-backed light curve provider is the authoritative
    // source for actual measurements.
    //   PhotometryFrame: "<target> frame <n>/<total> <filter> | snr=... fwhm=...\" airmass=... PASS"
    //   PhotometryCadenceBroken: "Cadence broken at frame <n>/<total>: <gap>s gap (max <max>s); break #<count>"
    //   PhotometrySummary:        "<target> <filter> burst complete: <n> frames, <breaks> cadence breaks..."

    if (detail.startsWith('Cadence broken')) {
      // Extract `break #N` so the visible counter stays in sync with
      // the executor's authoritative break count.
      final breakIdx = detail.lastIndexOf('break #');
      int? newCount;
      if (breakIdx >= 0) {
        final tail = detail.substring(breakIdx + 'break #'.length);
        newCount = int.tryParse(tail.trim());
      }
      state = state.copyWith(
        cadenceBreaks: newCount ?? state.cadenceBreaks + 1,
        lastFrameAt: DateTime.now(),
      );
      return;
    }

    if (detail.contains('burst complete')) {
      // Summary line — keep the activity surface live (panel still
      // visible) but bump the frame count if it parses cleanly.
      state = state.copyWith(
        hasSeenPhotometry: true,
        lastFrameAt: DateTime.now(),
      );
      return;
    }

    // PhotometryFrame fast path: split on " frame " to recover the
    // target designation, then the trailing token before " | " is the
    // filter. We deliberately do not parse SNR / FWHM / airmass — the
    // chart's authoritative values come from the DB row.
    final frameIdx = detail.indexOf(' frame ');
    if (frameIdx <= 0) return;
    final target = detail.substring(0, frameIdx).trim();

    // Filter token: between the "<n>/<total> " counter and " | ".
    String? filter;
    final pipeIdx = detail.indexOf(' | ');
    if (pipeIdx > frameIdx) {
      // e.g. "M31 frame 12/60 V | snr=..."
      // Slice between the counter end (last space before " | ") and " | "
      final beforePipe = detail.substring(0, pipeIdx);
      final lastSpace = beforePipe.lastIndexOf(' ');
      if (lastSpace > frameIdx) {
        filter = beforePipe.substring(lastSpace + 1).trim();
        if (filter.isEmpty) filter = null;
      }
    }

    state = state.copyWith(
      hasSeenPhotometry: true,
      lastTargetDesignation: target.isEmpty
          ? state.lastTargetDesignation
          : target,
      lastFilter: filter ?? state.lastFilter,
      framesCaptured: state.framesCaptured + 1,
      lastFrameAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _backendSubscription?.close();
    super.dispose();
  }
}

/// Most-recent Science Photometry executor activity for the current run.
///
/// The light-curve panel watches this provider to decide whether to
/// render itself, and uses the target / filter values to look up the
/// authoritative DB-backed light-curve point list.
final lightCurveActivityProvider =
    StateNotifierProvider<_LightCurveActivityNotifier, LightCurveActivity>(
        (ref) {
  return _LightCurveActivityNotifier(ref);
});
