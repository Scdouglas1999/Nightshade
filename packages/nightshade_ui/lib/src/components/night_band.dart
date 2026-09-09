import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import 'nightshade_panel.dart';

/// One labelled moment on the [NightBand] legend.
@immutable
class NightBandEvent {
  const NightBandEvent({required this.time, required this.label});

  /// When it happens.
  final DateTime time;

  /// Its label, e.g. "19:12 sunset".
  final String label;
}

/// The imageable span of a target, as two instants.
@immutable
class NightBandWindow {
  const NightBandWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// The signature timeline of tonight: sunset → astro dark → astro dawn →
/// sunrise, with the current time, the target's altitude arc and its imageable
/// window.
///
/// Every colour is a token, so the light and red-night bands follow with no
/// second code path (the red-night bands sit on the red axis by construction).
class NightBand extends StatelessWidget {
  const NightBand({
    super.key,
    required this.sunset,
    required this.astroDark,
    required this.astroDawn,
    required this.sunrise,
    required this.now,
    this.moonSet,
    this.targetAltitudeCurve,
    this.imageableWindow,
    this.events = const <NightBandEvent>[],
  });

  /// The night's start — the left edge of the canvas.
  final DateTime sunset;

  /// When astronomical darkness begins.
  final DateTime astroDark;

  /// When it ends.
  final DateTime astroDawn;

  /// The night's end — the right edge of the canvas.
  final DateTime sunrise;

  /// The current time. Drives the "now" marker.
  final DateTime now;

  /// When the moon sets, if it does tonight.
  final DateTime? moonSet;

  /// The target's altitude, sampled left to right, each value 0–1 where 1 is
  /// the top of the canvas. Null hides the arc.
  final List<double>? targetAltitudeCurve;

  /// The span in which the target is worth imaging.
  final NightBandWindow? imageableWindow;

  /// Labels for the legend, positioned at their times.
  final List<NightBandEvent> events;

  /// The gradient canvas's height.
  static const double canvasHeight = 52;

  /// The legend's height (two rows: the event labels and the "now" line).
  static const double legendHeight = 30;

  /// The second legend row, which carries "▲ now hh:mm" so it can never
  /// collide with an event label.
  static const double nowRowHeight = 15;

  /// The imageable-window bar's thickness.
  static const double windowBarHeight = 4;

  /// The "now" line's thickness and its cap's diameter.
  static const double nowLineWidth = 1.5;
  static const double nowDotSize = 6;

  /// The altitude path's stroke width.
  static const double altitudeStrokeWidth = 1.5;

  /// Fill opacity under the altitude path.
  static const double altitudeFillOpacity = 0.16;

  /// The panel's padding: 12 top and bottom, 16 either side.
  static const EdgeInsets panelPadding = EdgeInsets.symmetric(
    horizontal: NightshadeTokens.spaceLg,
    vertical: NightshadeTokens.spaceMd,
  );

  /// Where [instant] falls between [sunset] and [sunrise], clamped to 0–1.
  ///
  /// Public so a caller — and the widget test — can check the marker without
  /// re-deriving the arithmetic.
  double fractionOf(DateTime instant) {
    final span = sunrise.difference(sunset).inMilliseconds;
    if (span <= 0) return 0;
    final offset = instant.difference(sunset).inMilliseconds;
    return (offset / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadePanel(
      padding: panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: NightshadeTokens.borderRadiusSm,
            child: SizedBox(
              height: canvasHeight,
              child: CustomPaint(
                painter: _NightBandPainter(
                  colors: colors,
                  astroDark: fractionOf(astroDark),
                  astroDawn: fractionOf(astroDawn),
                  moonSet: moonSet == null ? null : fractionOf(moonSet!),
                  now: fractionOf(now),
                  altitude: targetAltitudeCurve,
                  windowStart: imageableWindow == null
                      ? null
                      : fractionOf(imageableWindow!.start),
                  windowEnd: imageableWindow == null
                      ? null
                      : fractionOf(imageableWindow!.end),
                ),
              ),
            ),
          ),
          SizedBox(
            height: legendHeight,
            child: _NightBandLegend(
              colors: colors,
              labels: <(double, String)>[
                for (final event in events)
                  (fractionOf(event.time), event.label),
              ],
              nowFraction: fractionOf(now),
              nowLabel: _formatNow(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNow() {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '▲ now $hh:$mm';
  }
}

class _NightBandPainter extends CustomPainter {
  _NightBandPainter({
    required this.colors,
    required this.astroDark,
    required this.astroDawn,
    required this.moonSet,
    required this.now,
    required this.altitude,
    required this.windowStart,
    required this.windowEnd,
  });

  final NightshadeColors colors;
  final double astroDark;
  final double astroDawn;
  final double? moonSet;
  final double now;
  final List<double>? altitude;
  final double? windowStart;
  final double? windowEnd;

  /// Dash length and gap for the astro-dark / astro-dawn verticals.
  static const double dashLength = 3;
  static const double dashGap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // The sky. Five stops: dusk, twilight, the dark middle, twilight again,
    // dawn — the same shape the night has.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            colors.bandDusk,
            colors.bandTwilight,
            colors.bandDark,
            colors.bandTwilight,
            colors.bandDawn,
          ],
          stops: const <double>[0, 0.14, 0.5, 0.86, 1],
        ).createShader(rect),
    );

    final hairline = Paint()
      ..color = colors.textPrimary.withValues(
        alpha: NightshadeTokens.opacityHairlineStrong,
      )
      ..strokeWidth = 1;
    _dashedVertical(canvas, size, astroDark, hairline);
    _dashedVertical(canvas, size, astroDawn, hairline);
    if (moonSet != null) _dashedVertical(canvas, size, moonSet!, hairline);

    _paintAltitude(canvas, size);
    _paintWindow(canvas, size);
    _paintNow(canvas, size);
  }

  void _dashedVertical(Canvas canvas, Size size, double x, Paint paint) {
    final dx = x * size.width;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(dx, y),
        Offset(dx, (y + dashLength).clamp(0.0, size.height)),
        paint,
      );
      y += dashLength + dashGap;
    }
  }

  void _paintAltitude(Canvas canvas, Size size) {
    final samples = altitude;
    if (samples == null || samples.length < 2) return;

    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * (i / (samples.length - 1));
      final y = size.height * (1 - samples[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = colors.primary.withValues(
          alpha: NightBand.altitudeFillOpacity,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = NightBand.altitudeStrokeWidth,
    );
  }

  void _paintWindow(Canvas canvas, Size size) {
    final start = windowStart;
    final end = windowEnd;
    if (start == null || end == null || end <= start) return;
    canvas.drawRect(
      Rect.fromLTRB(
        start * size.width,
        size.height - NightBand.windowBarHeight,
        end * size.width,
        size.height,
      ),
      Paint()..color = colors.primary,
    );
  }

  void _paintNow(Canvas canvas, Size size) {
    final dx = now * size.width;
    canvas.drawLine(
      Offset(dx, 0),
      Offset(dx, size.height),
      Paint()
        ..color = colors.textPrimary
        ..strokeWidth = NightBand.nowLineWidth,
    );
    canvas.drawCircle(
      Offset(dx, NightBand.nowDotSize / 2),
      NightBand.nowDotSize / 2,
      Paint()..color = colors.textPrimary,
    );
  }

  @override
  bool shouldRepaint(_NightBandPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.astroDark != astroDark ||
      oldDelegate.astroDawn != astroDawn ||
      oldDelegate.moonSet != moonSet ||
      oldDelegate.now != now ||
      oldDelegate.altitude != altitude ||
      oldDelegate.windowStart != windowStart ||
      oldDelegate.windowEnd != windowEnd;
}

/// The legend: event labels on the first row at their own times, and the "now"
/// label on a second row so the two can never collide.
class _NightBandLegend extends StatelessWidget {
  const _NightBandLegend({
    required this.colors,
    required this.labels,
    required this.nowFraction,
    required this.nowLabel,
  });

  final NightshadeColors colors;
  final List<(double fraction, String label)> labels;
  final double nowFraction;
  final String nowLabel;

  /// Rough width a legend label is allowed, so a centred one does not run off
  /// the canvas.
  static const double labelSlot = 96;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: <Widget>[
            for (var i = 0; i < labels.length; i++)
              _positioned(
                width: width,
                fraction: labels[i].$1,
                // The first label is left-aligned and the last right-aligned,
                // so neither hangs off the end of the band; the rest are
                // centred on their own time.
                alignment: i == 0
                    ? Alignment.centerLeft
                    : (i == labels.length - 1
                          ? Alignment.centerRight
                          : Alignment.center),
                child: Text(
                  labels[i].$2,
                  style: NightshadeTypography.monoCaption.copyWith(
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                ),
              ),
            _positioned(
              width: width,
              fraction: nowFraction,
              alignment: Alignment.center,
              top: NightBand.legendHeight - NightBand.nowRowHeight,
              child: Text(
                nowLabel,
                style: NightshadeTypography.monoCaption.copyWith(
                  color: colors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _positioned({
    required double width,
    required double fraction,
    required Alignment alignment,
    required Widget child,
    double top = 0,
  }) {
    final centre = fraction.clamp(0.0, 1.0) * width;
    double left;
    if (alignment == Alignment.centerLeft) {
      left = 0;
    } else if (alignment == Alignment.centerRight) {
      left = (width - labelSlot).clamp(0.0, width);
    } else {
      left = (centre - labelSlot / 2).clamp(
        0.0,
        (width - labelSlot).clamp(0.0, width),
      );
    }
    return Positioned(
      left: left,
      top: top,
      width: labelSlot,
      height: NightBand.nowRowHeight,
      child: Align(alignment: alignment, child: child),
    );
  }
}
