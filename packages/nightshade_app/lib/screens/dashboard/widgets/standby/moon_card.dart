import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../glass_card.dart';

/// Moon briefing card: a painted phase disc plus illumination, phase name, and
/// moonrise/moonset times. Degrades to "--" rows when rise/set are undefined
/// (circumpolar moon, or no location).
///
/// Phase and illumination are the same everywhere on Earth, so they stay
/// truthful without a site; only rise/set depend on where the observer is.
class MoonCard extends ConsumerWidget {
  final NightshadeColors colors;

  const MoonCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moon = ref.watch(moonInfoProvider);
    final waxing = _isWaxing(moon.phaseName);
    // lat/lon both 0.0 is the "no site on record" sentinel. The moon does rise
    // and set at Null Island, so the provider returns real times for a place the
    // user has never been; blank them rather than pass them off as tonight's.
    final observer = ref.watch(observerLocationProvider);
    final hasSite = observer.latitude != 0.0 || observer.longitude != 0.0;

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.moon,
            title: 'Moon',
            accent: colors.info,
          ),
          const SizedBox(height: DashboardCardStyle.headerGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(72, 72),
                painter: _MoonPainter(
                  illumination: moon.illumination,
                  waxing: waxing,
                  litColor: const Color(0xFFD6DCE2),
                  darkColor: colors.surfaceAlt,
                  borderColor: colors.border,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      moon.phaseName,
                      style: NightshadeTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${moon.illumination.toStringAsFixed(0)}% illuminated',
                      style: NightshadeTypography.withTabular(
                        NightshadeTypography.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _TimeRow(
            colors: colors,
            icon: LucideIcons.arrowUp,
            label: 'Moonrise',
            value: _clock(hasSite ? moon.moonrise : null),
          ),
          const SizedBox(height: 6),
          _TimeRow(
            colors: colors,
            icon: LucideIcons.arrowDown,
            label: 'Moonset',
            value: _clock(hasSite ? moon.moonset : null),
          ),
        ],
      ),
    );
  }

  /// Derive waxing/waning from the phase name (MoonTimes exposes no flag). Any
  /// "waning"/"last"/"third" phrase → waning; otherwise default to waxing so a
  /// new/full disc still renders sensibly.
  static bool _isWaxing(String phaseName) {
    final p = phaseName.toLowerCase();
    if (p.contains('waning') || p.contains('last') || p.contains('third')) {
      return false;
    }
    return true;
  }

  static String _clock(DateTime? t) {
    if (t == null) return '--:--';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

class _TimeRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;

  const _TimeRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            label,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.labelStrongSm.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints a moon disc lit from one side. The terminator is an ellipse whose
/// width tracks the illuminated fraction; `waxing` flips which limb is lit.
class _MoonPainter extends CustomPainter {
  final double illumination; // 0..100
  final bool waxing;
  final Color litColor;
  final Color darkColor;
  final Color borderColor;

  _MoonPainter({
    required this.illumination,
    required this.waxing,
    required this.litColor,
    required this.darkColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final frac = (illumination / 100).clamp(0.0, 1.0);

    // Start fully dark.
    canvas.drawCircle(center, r, Paint()..color = darkColor);

    final lit = Paint()..color = litColor;
    canvas.save();
    canvas
        .clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    if (frac >= 0.999) {
      canvas.drawCircle(center, r, lit);
    } else if (frac > 0.001) {
      // Half the disc (the lit limb) is a solid semicircle; the terminator is
      // an ellipse interpolating between the two limbs. cos(pi*frac) gives the
      // signed terminator offset: <0.5 illum → terminator on the lit side
      // (crescent), >0.5 → on the dark side (gibbous).
      final litRight = waxing; // waxing moon is lit on the right limb
      final rect = Rect.fromCircle(center: center, radius: r);

      // Solid half on the lit side.
      final half = Path()
        ..addArc(
          rect,
          litRight ? -1.5708 : 1.5708, // start at top, sweep toward lit side
          3.14159,
        )
        ..close();
      canvas.drawPath(half, lit);

      // Terminator ellipse: positive offset adds to the lit half (gibbous),
      // negative carves into it (crescent).
      final term = (frac - 0.5) * 2; // -1..1
      final ellipseW = (r * term).abs();
      final ellipseRect = Rect.fromCenter(
        center: center,
        width: ellipseW * 2,
        height: r * 2,
      );
      final gibbous = frac > 0.5;
      canvas.drawOval(
        ellipseRect,
        Paint()..color = gibbous ? lit.color : darkColor,
      );
    }
    canvas.restore();

    // Rim.
    canvas.drawCircle(
      center,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) =>
      old.illumination != illumination ||
      old.waxing != waxing ||
      old.litColor != litColor ||
      old.darkColor != darkColor;
}
