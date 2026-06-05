import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Run Dashboard Quality Panel (Wave 3 Image Grading).
///
/// Subscribes to the active backend's event stream and reads the typed
/// `FrameAccepted` / `FrameRejected` payloads produced by the Pack H
/// bridge dispatch (`SequencerEvent::FrameAccepted` / `FrameRejected`).
///
/// Pre-Pack-H this code parsed `InstructionProgress.detail` strings with
/// regex. That parser has been deleted â€” every metric the panel needs
/// (HFR, eccentricity, star count, reject reason, consecutive-reject
/// counter) now arrives as typed data via [FrameGradeEvent.fromTypedData].
///
/// Hidden when grading is disabled in settings AND no events have arrived
/// (an idle dashboard stays clean).
///
/// Wave 5 Agent 2 â€” the panel also surfaces the most recent sky-brightness
/// adaptive-exposure decision so the user sees live sky brightness +
/// nominal/adapted exposure pair on the dashboard.
class RunDashboardQualityPanel extends ConsumerWidget {
  const RunDashboardQualityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final summary = ref.watch(runDashboardQualitySummaryProvider);
    final adaptive = ref.watch(runDashboardAdaptiveExposureProvider);

    // Hidden when no grading has happened yet AND no adaptive event has
    // landed â€” keeps an idle dashboard uncluttered. The panel auto-
    // appears the moment the Rust path emits its first event.
    if (summary.total == 0 && adaptive == null) {
      return const SizedBox.shrink();
    }
    // If only adaptive-exposure has fired (grading off / not yet
    // active), render a slim adaptive-only banner.
    if (summary.total == 0 && adaptive != null) {
      return _AdaptiveExposureBanner(event: adaptive, colors: colors);
    }

    final rejectPct = (summary.rejectRate * 100).clamp(0.0, 100.0);
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.filter, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'IMAGE QUALITY',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.total} graded',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelQuiet.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),

          // Headline: accept / reject counts + percentage.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${summary.rejected}',
                style: NightshadeTypography.telemetryLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: summary.rejected > 0
                      ? colors.warning
                      : colors.textPrimary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                '/ ${summary.total} rejected',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              if (summary.total > 0)
                Text(
                  '${rejectPct.toStringAsFixed(0)}%',
                  style: NightshadeTypography.withTabular(
                    NightshadeTypography.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: summary.rejectRate > 0.2
                          ? colors.warning
                          : colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),

          // Progress bar (filled = rejected fraction).
          NightshadeProgressBar(
            value: summary.rejectRate.clamp(0.0, 1.0),
            height: 4,
          ),

          if (summary.recent.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: NightshadeTokens.spaceMd),
            Text(
              'RECENT',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            // Up to the 6 most-recent decisions, newest at the top.
            for (final event in summary.recent.reversed.take(6))
              _GradeRow(event: event, colors: colors),
          ],

          if (summary.hfrSparkline.length >= 3) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _HfrSparklinePainter(
                  values: summary.hfrSparkline,
                  color: colors.primary,
                ),
                size: Size.infinite,
              ),
            ),
          ],
          // Wave 5 Agent 2 â€” adaptive-exposure status row. Embedded
          // inside the quality panel so the user has one place to look
          // for "is the rig adapting tonight?".
          if (adaptive != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _AdaptiveExposureInline(event: adaptive, colors: colors),
          ],
        ],
      ),
    );
  }
}

/// Wave 5 Agent 2 â€” slim banner used when adaptive-exposure has fired
/// but no image-grading events have arrived yet (e.g. grading disabled).
class _AdaptiveExposureBanner extends StatelessWidget {
  const _AdaptiveExposureBanner({required this.event, required this.colors});

  final AdaptiveExposureEvent event;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: _AdaptiveExposureInline(event: event, colors: colors),
    );
  }
}

/// Wave 5 Agent 2 â€” the inline body that renders the live adaptive-
/// exposure state for the quality panel.
class _AdaptiveExposureInline extends StatelessWidget {
  const _AdaptiveExposureInline({
    required this.event,
    required this.colors,
  });

  final AdaptiveExposureEvent event;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final isAdjusted = event.isNontrivialAdjustment;
    final tone = switch (event.reason) {
      AdaptiveExposureReason.clampedMin ||
      AdaptiveExposureReason.clampedMax ||
      AdaptiveExposureReason.outOfNominalBounds =>
        colors.warning,
      AdaptiveExposureReason.unavailable ||
      AdaptiveExposureReason.disabled =>
        colors.textMuted,
      AdaptiveExposureReason.adapted ||
      AdaptiveExposureReason.unknown =>
        isAdjusted ? colors.primary : colors.textPrimary,
    };
    final skyLabel = event.skyBrightnessMag != null
        ? '${event.skyBrightnessMag!.toStringAsFixed(2)} mag/arcsecÂ²'
        : 'sky brightness unavailable';
    final filterLabel =
        event.filter == null ? '' : '${event.filter} Â· ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(LucideIcons.lineChart, size: 14, color: tone),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'ADAPTIVE EXPOSURE',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colors.textMuted,
              ),
            ),
            const Spacer(),
            Text(
              event.reason.label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          '$filterLabel${event.adaptedSecs.toStringAsFixed(0)}s '
              '(nominal ${event.nominalSecs.toStringAsFixed(0)}s)',
          style: NightshadeTypography.withTabular(
            NightshadeTypography.label.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Sky brightness: $skyLabel',
          style: NightshadeTypography.withTabular(
            NightshadeTypography.labelQuiet.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.event, required this.colors});

  final FrameGradeEvent event;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final isReject = event.isReject;
    final icon = isReject ? LucideIcons.x : LucideIcons.check;
    final iconColor = isReject ? colors.warning : colors.primary;
    // Pack H: the typed payload carries HFR / star count directly, so the
    // dashboard surfaces them on every row instead of swallowing them into
    // a parsed reason string.
    final metricChips = <String>[];
    if (event.hfr != null) {
      metricChips.add('HFR ${event.hfr!.toStringAsFixed(2)}');
    }
    if (event.eccentricity != null) {
      metricChips.add('ecc ${event.eccentricity!.toStringAsFixed(2)}');
    }
    if (event.starCount != null) {
      metricChips.add('${event.starCount} stars');
    }
    final metricSuffix =
        metricChips.isEmpty ? '' : '  (${metricChips.join(', ')})';
    final label = isReject
        ? 'Frame ${event.frame}: ${event.reason}$metricSuffix'
        : 'Frame ${event.frame}: accepted$metricSuffix';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight HFR-over-time sparkline. Renders the last N accepted-frame
/// HFR values as a polyline. No axes â€” this is a sparkline, not a chart.
class _HfrSparklinePainter extends CustomPainter {
  _HfrSparklinePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    final span = range < 1e-3 ? 1.0 : range;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final normalized = (values[i] - min) / span;
      // Invert so smaller HFR draws at the top (better focus = up).
      final y = size.height * (1 - normalized);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HfrSparklinePainter old) =>
      old.values != values || old.color != color;
}

// ============================================================================
// Provider â€” accumulates grading events into a per-run summary.
// ============================================================================

/// Maximum recent events retained for the dashboard. Older events scroll
/// off the bottom of the list; the totals stay accurate.
const int _kQualityRecentLimit = 50;

class _QualityNotifier extends StateNotifier<FrameGradeRunSummary> {
  _QualityNotifier(this._ref) : super(FrameGradeRunSummary.empty) {
    _wireBackendEvents();
  }

  final Ref _ref;
  StreamSubscription<NightshadeEvent>? _subscription;
  ProviderSubscription<DiagnosticsBackend>? _backendSubscription;

  void _wireBackendEvents() {
    void resubscribe(DiagnosticsBackend backend) {
      _subscription?.cancel();
      _subscription = backend.eventStream.listen(_onEvent);
    }

    resubscribe(_ref.read(diagnosticsBackendProvider));
    _backendSubscription =
        _ref.listen<DiagnosticsBackend>(diagnosticsBackendProvider, (_, next) {
      resubscribe(next);
    });
  }

  void _onEvent(NightshadeEvent event) {
    if (event.category != EventCategory.sequencer) return;
    // 'Started' resets per-run counters.
    if (event.eventType == 'Started') {
      state = FrameGradeRunSummary.empty;
      return;
    }
    // Pack H: only the typed grading variants drive the panel. We no
    // longer parse `InstructionProgress.detail` strings â€” the regex
    // pipeline has been removed entirely.
    if (event.eventType != 'FrameAccepted' &&
        event.eventType != 'FrameRejected') {
      return;
    }
    final grade = FrameGradeEvent.fromTypedData(event.eventType, event.data);
    if (grade == null) return;

    final nextRecent = List<FrameGradeEvent>.from(state.recent)..add(grade);
    if (nextRecent.length > _kQualityRecentLimit) {
      nextRecent.removeRange(0, nextRecent.length - _kQualityRecentLimit);
    }

    // Sparkline only tracks accepted-frame HFRs because reject HFR may
    // be a known-bad outlier. The typed event carries the HFR directly
    // â€” no parsing â€” so we can populate the trend line honestly.
    final nextSparkline = List<double>.from(state.hfrSparkline);
    if (grade.decision == FrameGradeDecision.accepted && grade.hfr != null) {
      nextSparkline.add(grade.hfr!);
      // Cap the sparkline to a reasonable window so memory + paint cost
      // stay bounded across long sessions.
      if (nextSparkline.length > 200) {
        nextSparkline.removeRange(0, nextSparkline.length - 200);
      }
    }

    // The typed event always carries the authoritative running counts.
    // No fall-back-to-local-increment branch needed.
    state = FrameGradeRunSummary(
      accepted: grade.acceptedTotal,
      rejected: grade.rejectedTotal,
      recent: nextRecent,
      hfrSparkline: nextSparkline,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _backendSubscription?.close();
    super.dispose();
  }
}

/// Per-run quality summary fed by the backend event stream.
///
/// Pack H: removed the duplicate `ref.onDispose(notifier.dispose)` â€”
/// Riverpod's StateNotifierProvider already auto-disposes the notifier
/// when the container shuts down, so the manual hook was triggering
/// `Bad state: Tried to use _QualityNotifier after dispose was called`
/// under tests that dispose deterministically.
final runDashboardQualitySummaryProvider =
    StateNotifierProvider<_QualityNotifier, FrameGradeRunSummary>((ref) {
  return _QualityNotifier(ref);
});

// ============================================================================
// Wave 5 Agent 2 â€” Sky-brightness adaptive exposure surface
// ============================================================================
//
// Mirrors the `_QualityNotifier` pattern: subscribe to the active backend
// event stream, watch for `ExposureAdjusted`, and expose the most recent
// decision via a StateNotifierProvider so the dashboard panel can re-paint
// without holding the backend reference itself.

class _AdaptiveExposureNotifier
    extends StateNotifier<AdaptiveExposureEvent?> {
  _AdaptiveExposureNotifier(this._ref) : super(null) {
    _wireBackendEvents();
  }

  final Ref _ref;
  StreamSubscription<NightshadeEvent>? _subscription;
  ProviderSubscription<DiagnosticsBackend>? _backendSubscription;

  void _wireBackendEvents() {
    void resubscribe(DiagnosticsBackend backend) {
      _subscription?.cancel();
      _subscription = backend.eventStream.listen(_onEvent);
    }

    resubscribe(_ref.read(diagnosticsBackendProvider));
    _backendSubscription =
        _ref.listen<DiagnosticsBackend>(diagnosticsBackendProvider, (_, next) {
      resubscribe(next);
    });
  }

  void _onEvent(NightshadeEvent event) {
    if (event.category != EventCategory.sequencer) return;
    // 'Started' clears the last-seen value so a fresh run doesn't
    // surface a stale decision from the previous run.
    if (event.eventType == 'Started') {
      state = null;
      return;
    }
    if (event.eventType != 'ExposureAdjusted') return;
    final parsed = AdaptiveExposureEvent.fromTypedData(
      event.eventType,
      event.data,
    );
    if (parsed != null) {
      state = parsed;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _backendSubscription?.close();
    super.dispose();
  }
}

/// Most-recent sky-brightness adaptive exposure decision from the
/// executor, or `null` when none has been emitted in this run.
final runDashboardAdaptiveExposureProvider =
    StateNotifierProvider<_AdaptiveExposureNotifier, AdaptiveExposureEvent?>(
        (ref) {
  return _AdaptiveExposureNotifier(ref);
});
