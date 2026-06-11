import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The Night Briefing showpiece: a painted band spanning sunset → sunrise that
/// shows the twilight stages, the imaging (astronomical-dark) window, the live
/// "now" marker, and moonrise/moonset, with a large tabular countdown above it.
///
/// All time inputs come from providers that already tick at minute precision
/// (`observationTimeProvider`), so the strip repaints as the night advances
/// without this widget owning a `Timer`.
class NightTimeline extends ConsumerWidget {
  final NightshadeColors colors;

  const NightTimeline({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moon = ref.watch(moonInfoProvider);
    final now = ref.watch(observationTimeProvider.select((s) => s.time));

    // Without a location the calculator returns null twilight fields (or the
    // sun never sets at high latitude). Show a quiet prompt instead of an empty
    // painter rather than throwing.
    if (twilight.sunset == null || twilight.sunrise == null) {
      return _NoTwilight(colors: colors);
    }

    final countdown = computeNightCountdown(twilight: twilight, now: now);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CountdownHeader(colors: colors, countdown: countdown),
          const SizedBox(height: NightshadeTokens.spaceLg),
          // Band + axis labels. The painter draws ticks; labels are laid out
          // with the band in a LayoutBuilder so they sit under their ticks.
          SizedBox(
            height: 112,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, 112),
                  painter: _TimelinePainter(
                    colors: colors,
                    twilight: twilight,
                    moon: moon,
                    now: now,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line countdown header: the single most relevant fact plus the total
/// dark-window duration.
class _CountdownHeader extends StatelessWidget {
  final NightshadeColors colors;
  final NightCountdown countdown;

  const _CountdownHeader({required this.colors, required this.countdown});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                countdown.headlineLabel.toUpperCase(),
                style: NightshadeTypography.overline.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                countdown.headlineValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NightshadeTypography.telemetryLg.copyWith(
                  color: countdown.isDark ? colors.primary : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (countdown.windowLabel != null) ...[
          const SizedBox(width: NightshadeTokens.spaceMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'IMAGING WINDOW',
                style: NightshadeTypography.overline.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                countdown.windowLabel!,
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.telemetryMd.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NoTwilight extends StatelessWidget {
  final NightshadeColors colors;

  const _NoTwilight({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Row(
        children: [
          Icon(LucideIcons.mapPin, size: 16, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              'Set an observing location for twilight times.',
              style: NightshadeTypography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PURE COUNTDOWN LOGIC (testable without a widget tree)
// =============================================================================

/// The single relevant countdown fact for the night band header.
class NightCountdown {
  /// Quiet caps overline, e.g. "ASTRO DARK IN".
  final String headlineLabel;

  /// Large tabular value, e.g. "1h 24m" or "21:48".
  final String headlineValue;

  /// Total astronomical-darkness window, e.g. "6h 12m" — null when undefined.
  final String? windowLabel;

  /// True while `now` is inside the astronomical-dark window (drives the accent
  /// colour on the header).
  final bool isDark;

  const NightCountdown({
    required this.headlineLabel,
    required this.headlineValue,
    required this.windowLabel,
    required this.isDark,
  });
}

/// Resolve the most relevant single countdown for the night, mirroring the
/// astro-twilight phrasing in the spec:
///   * before astro dusk      → "Astro dark in Xh Ym"
///   * during darkness        → "Dark for another Xh Ym"
///   * after astro dawn        → "Sunrise in Xh Ym" (or, if the sun is already
///                               up, "Sunset at HH:MM")
/// Falls back to sunset/sunrise framing when astronomical twilight is undefined
/// (e.g. the sun stays above −18° all night at high latitude).
///
/// Pure: depends only on its arguments so it can be unit-tested directly.
NightCountdown computeNightCountdown({
  required TwilightTimes twilight,
  required DateTime now,
}) {
  final dusk = twilight.astronomicalDusk;
  final dawn = twilight.astronomicalDawn;
  final sunset = twilight.sunset;
  final sunrise = twilight.sunrise;

  final window = (dusk != null && dawn != null && dawn.isAfter(dusk))
      ? _hm(dawn.difference(dusk))
      : null;

  // Before astronomical dark: count down to dusk.
  if (dusk != null && now.isBefore(dusk)) {
    return NightCountdown(
      headlineLabel: 'Astro dark in',
      headlineValue: _hm(dusk.difference(now)),
      windowLabel: window,
      isDark: false,
    );
  }

  // Inside the dark window: count down how much dark remains.
  if (dusk != null &&
      dawn != null &&
      !now.isBefore(dusk) &&
      now.isBefore(dawn)) {
    return NightCountdown(
      headlineLabel: 'Dark for another',
      headlineValue: _hm(dawn.difference(now)),
      windowLabel: window,
      isDark: true,
    );
  }

  // After astronomical dawn but still before sunrise: count down to sunrise.
  if (sunrise != null && now.isBefore(sunrise)) {
    return NightCountdown(
      headlineLabel: 'Sunrise in',
      headlineValue: _hm(sunrise.difference(now)),
      windowLabel: window,
      isDark: false,
    );
  }

  // Daytime (sun already up): point at the next sunset.
  if (sunset != null) {
    return NightCountdown(
      headlineLabel: 'Sunset at',
      headlineValue: _clock(sunset),
      windowLabel: window,
      isDark: false,
    );
  }

  // No astronomical twilight at all but we still have a sunset/sunrise span.
  return NightCountdown(
    headlineLabel:
        sunrise != null && now.isBefore(sunrise) ? 'Sunrise in' : 'Tonight',
    headlineValue: sunrise != null && now.isBefore(sunrise)
        ? _hm(sunrise.difference(now))
        : '--',
    windowLabel: window,
    isDark: false,
  );
}

String _hm(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final h = clamped.inHours;
  final m = clamped.inMinutes % 60;
  return '${h}h ${m}m';
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// =============================================================================
// PAINTER
// =============================================================================

class _TimelinePainter extends CustomPainter {
  final NightshadeColors colors;
  final TwilightTimes twilight;
  final MoonTimes moon;
  final DateTime now;

  _TimelinePainter({
    required this.colors,
    required this.twilight,
    required this.moon,
    required this.now,
  });

  // The band occupies the top portion; labels sit in the strip below it.
  static const double _bandTop = 6;
  static const double _bandHeight = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final sunset = twilight.sunset!;
    final sunrise = twilight.sunrise!;
    final totalMs = sunrise.difference(sunset).inMilliseconds;
    if (totalMs <= 0) return;

    double x(DateTime t) {
      final f = (t.difference(sunset).inMilliseconds / totalMs).clamp(0.0, 1.0);
      return f * size.width;
    }

    final bandRect = Rect.fromLTWH(0, _bandTop, size.width, _bandHeight);
    final rrect = RRect.fromRectAndRadius(
      bandRect,
      const Radius.circular(NightshadeTokens.radiusMd),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    // Twilight gradient: lighter blue-grey at the sunset/sunrise edges fading
    // to near-black through astronomical darkness. Stops are placed at the
    // fraction each twilight boundary falls at, so the gradient tracks the real
    // ephemeris rather than a fixed shape.
    const edge = Color(0xFF2A3A4A); // blue-grey dusk glow
    const mid = Color(0xFF141B24);
    const dark = Color(0xFF06090D); // astronomical darkness
    final stops = <double>[];
    final cols = <Color>[];
    void stop(DateTime? t, Color c) {
      if (t == null) return;
      final f = (t.difference(sunset).inMilliseconds / totalMs).clamp(0.0, 1.0);
      stops.add(f);
      cols.add(c);
    }

    stop(sunset, edge);
    stop(twilight.civilDusk, mid);
    stop(twilight.astronomicalDusk, dark);
    stop(twilight.astronomicalDawn, dark);
    stop(twilight.civilDawn, mid);
    stop(sunrise, edge);
    // Guarantee a usable gradient even if intermediate stages are null.
    if (stops.length < 2) {
      stops
        ..clear()
        ..addAll([0.0, 0.5, 1.0]);
      cols
        ..clear()
        ..addAll([edge, dark, edge]);
    } else {
      // Gradient stops must be monotonically increasing.
      for (var i = 1; i < stops.length; i++) {
        if (stops[i] <= stops[i - 1]) stops[i] = stops[i - 1] + 0.0001;
      }
      if (stops.last > 1) stops[stops.length - 1] = 1.0;
    }

    final paint = Paint()
      ..shader = LinearGradient(
        colors: cols,
        stops: stops,
      ).createShader(bandRect);
    canvas.drawRect(bandRect, paint);

    // Highlight the astronomical-dark window with a faint top border so the
    // "imaging window" reads as the prize region of the band.
    final dusk = twilight.astronomicalDusk;
    final dawn = twilight.astronomicalDawn;
    if (dusk != null && dawn != null && dawn.isAfter(dusk)) {
      final markPaint = Paint()
        ..color = colors.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(x(dusk), _bandTop + 1),
        Offset(x(dawn), _bandTop + 1),
        markPaint,
      );
    }
    canvas.restore();

    // Band border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.border,
    );

    // Minor (unlabeled) ticks: civil + nautical boundaries.
    for (final t in [
      twilight.civilDusk,
      twilight.nauticalDusk,
      twilight.nauticalDawn,
      twilight.civilDawn,
    ]) {
      if (t == null) continue;
      _tick(canvas, x(t), colors.border, minor: true);
    }

    // Major labeled ticks.
    _labeledTick(canvas, size, x(sunset), 'Sunset', _clock(sunset));
    if (dusk != null) {
      _labeledTick(canvas, size, x(dusk), 'Astro dark', _clock(dusk));
    }
    if (dawn != null) {
      _labeledTick(canvas, size, x(dawn), 'Astro dawn', _clock(dawn));
    }
    _labeledTick(canvas, size, x(sunrise), 'Sunrise', _clock(sunrise),
        alignEnd: true);

    // Moon markers (small glyph ticks) when rise/set fall inside the window.
    _moonMarker(canvas, x, sunset, sunrise, moon.moonrise);
    _moonMarker(canvas, x, sunset, sunrise, moon.moonset);

    // "Now" marker: vivid primary line with a soft glow dot, only when now is
    // within the sunset→sunrise span.
    if (!now.isBefore(sunset) && !now.isAfter(sunrise)) {
      final nx = x(now);
      final glow = Paint()
        ..color = colors.primary.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(nx, _bandTop + _bandHeight / 2), 7, glow);
      canvas.drawLine(
        Offset(nx, _bandTop - 2),
        Offset(nx, _bandTop + _bandHeight + 2),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(nx, _bandTop + _bandHeight / 2),
        3.5,
        Paint()..color = colors.primary,
      );
    }
  }

  void _tick(Canvas canvas, double x, Color color, {bool minor = false}) {
    final top = minor ? _bandTop + _bandHeight - 8 : _bandTop;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, _bandTop + _bandHeight),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  void _labeledTick(
    Canvas canvas,
    Size size,
    double x,
    String label,
    String time, {
    bool alignEnd = false,
  }) {
    _tick(canvas, x, colors.textMuted);

    final labelPainter = _text(label, colors.textSecondary,
        NightshadeTypography.fontSize10, FontWeight.w600);
    final timePainter = _text(time, colors.textMuted,
        NightshadeTypography.fontSize9_5, FontWeight.w400,
        mono: true);

    // Keep labels inside the canvas: left-align at the start edge, right-align
    // at the end edge, centre otherwise.
    double lx;
    if (x < labelPainter.width / 2) {
      lx = 0;
    } else if (x > size.width - labelPainter.width / 2 || alignEnd) {
      lx = math.max(0, x - labelPainter.width);
      if (!alignEnd) lx = size.width - labelPainter.width;
    } else {
      lx = x - labelPainter.width / 2;
    }
    const labelY = _bandTop + _bandHeight + 8;
    labelPainter.paint(canvas, Offset(lx, labelY));

    double tx;
    if (x < timePainter.width / 2) {
      tx = 0;
    } else if (alignEnd || x > size.width - timePainter.width / 2) {
      tx = size.width - timePainter.width;
    } else {
      tx = x - timePainter.width / 2;
    }
    timePainter.paint(canvas, Offset(tx, labelY + 14));
  }

  void _moonMarker(
    Canvas canvas,
    double Function(DateTime) x,
    DateTime sunset,
    DateTime sunrise,
    DateTime? t,
  ) {
    if (t == null) return;
    if (t.isBefore(sunset) || t.isAfter(sunrise)) return;
    final mx = x(t);
    const cy = _bandTop + _bandHeight + 2;
    // Small crescent glyph above the labels strip.
    final paint = Paint()..color = colors.textSecondary;
    canvas.drawCircle(Offset(mx, cy + 3), 3, paint);
    canvas.drawCircle(
      Offset(mx + 1.3, cy + 3),
      3,
      Paint()..color = colors.surface,
    );
  }

  TextPainter _text(String s, Color color, double size, FontWeight weight,
      {bool mono = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: mono
              ? NightshadeTypography.fontFamilyMono
              : NightshadeTypography.fontFamily,
          fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  bool shouldRepaint(_TimelinePainter old) {
    return old.now != now ||
        old.twilight.sunset != twilight.sunset ||
        old.twilight.sunrise != twilight.sunrise ||
        old.twilight.astronomicalDusk != twilight.astronomicalDusk ||
        old.twilight.astronomicalDawn != twilight.astronomicalDawn ||
        old.twilight.civilDusk != twilight.civilDusk ||
        old.twilight.civilDawn != twilight.civilDawn ||
        old.twilight.nauticalDusk != twilight.nauticalDusk ||
        old.twilight.nauticalDawn != twilight.nauticalDawn ||
        old.moon.moonrise != moon.moonrise ||
        old.moon.moonset != moon.moonset ||
        old.colors.primary != colors.primary;
  }
}
