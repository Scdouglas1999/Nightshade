import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Side-by-side template / frame / residual cutout strip for one transient
/// candidate.
///
/// The raw per-detection postage stamps are not archived in the detection log
/// (the difference pipeline writes optional residual PNGs to a scratch dir, not
/// the DB), so this strip renders a faithful *schematic* of the measured
/// residual from the candidate's persisted shape statistics — the same numbers
/// the cross-match and the Narrator read:
///
///   * **Template** — the deep stack at the source position. A
///     `pointBrightening` had flux here already (a star present in the
///     template); a `newSource` did not (empty template), which is exactly what
///     makes it the headline case.
///   * **Frame** — the fresh light frame: template plus the source as it
///     appeared, an elliptical Gaussian sized by [TransientDetectionRow.fwhm]
///     and elongated by [TransientDetectionRow.eccentricity].
///   * **Residual** — frame minus template, the difference the pipeline
///     detected. A `dipole` shows the tell-tale +/- lobe pair; everything else
///     a single signed blob whose sign follows [TransientDetectionRow.deltaMag]
///     (or the residual flux).
///
/// Drawing the measured ellipse (not a generic icon) means the strip reads
/// honestly: a fat low-SNR smudge looks like one, a crisp high-SNR point looks
/// like one. The labels make the schematic nature explicit so it is never
/// mistaken for the raw pixels.
class CutoutStrip extends StatelessWidget {
  const CutoutStrip({super.key, required this.detection});

  final TransientDetectionRow detection;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final kind = TransientKind.fromWire(detection.kind);
    // A point brightening (and a known-star match) already had template flux;
    // a clean newcomer did not.
    final templateHasSource = kind == TransientKind.pointBrightening ||
        detection.catalogMatch != null;
    // Residual sign: deltaMag<0 means brighter (positive residual); fall back
    // to the signed residual flux when no magnitude was measurable.
    final brighter = detection.deltaMag != null
        ? detection.deltaMag! <= 0
        : detection.residualFlux >= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three equal panels with two gaps; keep them square-ish but never let a
        // narrow phone column overflow.
        const gap = NightshadeTokens.spaceSm;
        final panel = ((constraints.maxWidth - gap * 2) / 3).clamp(48.0, 132.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CutoutPanel(
              label: 'Template',
              size: panel,
              colors: colors,
              painter: _CutoutPainter(
                colors: colors,
                kind: kind,
                fwhm: detection.fwhm,
                eccentricity: detection.eccentricity,
                snr: detection.snr,
                positionAngleDeg: detection.positionAngleDeg,
                stage: _CutoutStage.template,
                templateHasSource: templateHasSource,
                brighter: brighter,
              ),
            ),
            const SizedBox(width: gap),
            _CutoutPanel(
              label: 'This frame',
              size: panel,
              colors: colors,
              painter: _CutoutPainter(
                colors: colors,
                kind: kind,
                fwhm: detection.fwhm,
                eccentricity: detection.eccentricity,
                snr: detection.snr,
                positionAngleDeg: detection.positionAngleDeg,
                stage: _CutoutStage.frame,
                templateHasSource: templateHasSource,
                brighter: brighter,
              ),
            ),
            const SizedBox(width: gap),
            _CutoutPanel(
              label: 'Residual',
              size: panel,
              colors: colors,
              accent: true,
              painter: _CutoutPainter(
                colors: colors,
                kind: kind,
                fwhm: detection.fwhm,
                eccentricity: detection.eccentricity,
                snr: detection.snr,
                positionAngleDeg: detection.positionAngleDeg,
                stage: _CutoutStage.residual,
                templateHasSource: templateHasSource,
                brighter: brighter,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CutoutPanel extends StatelessWidget {
  const _CutoutPanel({
    required this.label,
    required this.size,
    required this.colors,
    required this.painter,
    this.accent = false,
  });

  final String label;
  final double size;
  final NightshadeColors colors;
  final CustomPainter painter;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(
              color:
                  accent ? colors.accent.withValues(alpha: 0.6) : colors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(painter: painter, size: Size.square(size)),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          label,
          style: NightshadeTypography.labelQuiet.copyWith(
            color: accent ? colors.accent : colors.textMuted,
            fontSize: NightshadeTypography.fontSize10,
          ),
        ),
      ],
    );
  }
}

enum _CutoutStage { template, frame, residual }

/// Paints one schematic cutout panel: a faint star-field background plus the
/// measured source ellipse, drawn differently per [stage].
class _CutoutPainter extends CustomPainter {
  _CutoutPainter({
    required this.colors,
    required this.kind,
    required this.fwhm,
    required this.eccentricity,
    required this.snr,
    required this.positionAngleDeg,
    required this.stage,
    required this.templateHasSource,
    required this.brighter,
  });

  final NightshadeColors colors;
  final TransientKind kind;
  final double fwhm;
  final double eccentricity;
  final double snr;
  final double positionAngleDeg;
  final _CutoutStage stage;
  final bool templateHasSource;
  final bool brighter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Faint, deterministic field of background stars so the panels read as sky,
    // not blank tiles. Seeded by the panel size so it is stable across rebuilds.
    final rng = math.Random(((fwhm + eccentricity) * 1000).round() + 7);
    final star = Paint()..color = colors.textMuted.withValues(alpha: 0.35);
    for (var i = 0; i < 9; i++) {
      final p = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      // Skip stars too near the centre so they don't fight the source.
      if ((p - center).distance < size.width * 0.18) continue;
      canvas.drawCircle(p, 0.6 + rng.nextDouble() * 0.8, star);
    }

    // Source ellipse geometry from the measured PSF. FWHM is in pixels on the
    // tile grid; map a typical few-pixel PSF onto ~22% of the panel, clamped so
    // an extreme value can't fill or vanish.
    final base = size.width * (0.10 + 0.012 * fwhm).clamp(0.10, 0.30);
    final ecc = eccentricity.clamp(0.0, 0.95);
    final semiMajor = base / math.sqrt(1 - ecc * ecc).clamp(0.4, 1.0);
    final semiMinor = base * math.sqrt(1 - ecc * ecc);
    // Orient the ellipse along the residual's measured major axis (the native
    // second-moment position angle). The tile +y axis points down in canvas
    // space, but a position angle is direction-less (mod 180°) so the sign does
    // not matter for an ellipse. A round source's angle is immaterial.
    final angle = positionAngleDeg * math.pi / 180.0;
    // Brightness intensity ramps with SNR but stays visible at the floor.
    final intensity = (0.35 + snr / 30.0).clamp(0.35, 1.0);

    switch (stage) {
      case _CutoutStage.template:
        if (templateHasSource) {
          _drawBlob(
            canvas,
            center,
            semiMajor,
            semiMinor,
            angle,
            colors.textSecondary,
            // Template flux for a known source is steady, not the full bright
            // intensity — the *change* is what shows up in the residual.
            0.55,
          );
        }
        // newSource → empty template (nothing drawn): the headline absence.
        break;
      case _CutoutStage.frame:
        // Frame = template flux (if any) plus the source as imaged this night.
        if (templateHasSource) {
          _drawBlob(
            canvas,
            center,
            semiMajor,
            semiMinor,
            angle,
            colors.textSecondary,
            0.55,
          );
        }
        _drawBlob(
          canvas,
          center,
          semiMajor,
          semiMinor,
          angle,
          colors.textPrimary,
          intensity,
        );
        break;
      case _CutoutStage.residual:
        final pos = brighter ? colors.accent : colors.info;
        if (kind == TransientKind.dipole) {
          // The dipole signature: a positive lobe beside a negative one.
          final off = Offset(semiMajor * 0.8, 0);
          _drawBlob(
            canvas,
            center - off,
            semiMinor,
            semiMinor,
            0,
            colors.accent,
            intensity,
          );
          _drawBlob(
            canvas,
            center + off,
            semiMinor,
            semiMinor,
            0,
            colors.error,
            intensity,
          );
        } else {
          _drawBlob(
            canvas,
            center,
            semiMajor,
            semiMinor,
            angle,
            pos,
            intensity,
          );
        }
        break;
    }
  }

  /// Draw a soft elliptical Gaussian-like blob via a radial gradient.
  void _drawBlob(
    Canvas canvas,
    Offset center,
    double semiMajor,
    double semiMinor,
    double angle,
    Color color,
    double intensity,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    // Map the unit circle to the ellipse so the radial gradient becomes
    // elliptical.
    canvas.scale(semiMajor, semiMinor);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: intensity.clamp(0.0, 1.0)),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1.0));
    canvas.drawCircle(Offset.zero, 1.0, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter old) =>
      old.kind != kind ||
      old.fwhm != fwhm ||
      old.eccentricity != eccentricity ||
      old.snr != snr ||
      old.positionAngleDeg != positionAngleDeg ||
      old.stage != stage ||
      old.templateHasSource != templateHasSource ||
      old.brighter != brighter ||
      old.colors != colors;
}
