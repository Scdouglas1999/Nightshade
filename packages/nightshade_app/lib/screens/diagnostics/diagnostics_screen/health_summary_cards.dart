part of '../diagnostics_screen.dart';

class _HealthGradeCard extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final NightshadeColors colors;

  const _HealthGradeCard({
    required this.diagnostics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // §4.25: a duplicate inline A..F mapping used to live here. The
    // shared `OpticalHealthScore` model owns the bands now so any other
    // surface (analytics, exports) renders the same letter for the same
    // raw scores.
    final health = diagnostics.healthScore;
    final gradeColor = _gradeColor(health.grade, colors);

    return _DiagCard(
      colors: colors,
      child: Column(
        children: [
          Text(
            'Optical Health',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 16),
          Container(
            width: 44,
            height: 44,
            decoration: NightshadeDecorations.kpiBadge(gradeColor),
            child: Center(
              child: Text(
                health.letterGrade,
                style: NightshadeTypography.telemetryLg.copyWith(
                  fontWeight: FontWeight.w800,
                  color: gradeColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            health.qualityLabel,
            style: NightshadeTypography.label.copyWith(color: gradeColor),
          ),
          const SizedBox(height: 6),
          Text(
            'Lower bars are better. Use this grade as a quick summary before diving into the field map and findings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          // Score breakdown
          _ScoreBar(
            label: context.l10n.text('diagnosticsTilt'),
            value: diagnostics.tiltScore,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _ScoreBar(
            label: context.l10n.text('diagnosticsCollimation'),
            value: diagnostics.collimationScore,
            colors: colors,
          ),
        ],
      ),
    );
  }

  // Maps the shared `OpticalHealthGrade` enum to the theme palette. The
  // model deliberately stays UI-agnostic; only the diagnostics widgets need
  // to know which colour ramp matches the letter.
  Color _gradeColor(OpticalHealthGrade grade, NightshadeColors colors) {
    switch (grade) {
      case OpticalHealthGrade.a:
      case OpticalHealthGrade.b:
        return colors.success;
      case OpticalHealthGrade.c:
        return colors.warning;
      case OpticalHealthGrade.d:
      case OpticalHealthGrade.f:
        return colors.error;
    }
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final NightshadeColors colors;

  const _ScoreBar({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 100.0);
    final barColor = clampedValue < 18
        ? colors.success
        : clampedValue < 30
            ? colors.warning
            : colors.error;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clampedValue / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            clampedValue.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: NightshadeTypography.labelStrongSm.copyWith(color: barColor),
          ),
        ),
      ],
    );
  }
}

// --- Tilt Assessment Card ---

class _TiltAssessmentCard extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final NightshadeColors colors;

  const _TiltAssessmentCard({
    required this.diagnostics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final direction = diagnostics.dominantTiltDirection;
    final score = diagnostics.tiltScore;
    final severity = score >= 30
        ? 'Strong tilt'
        : score >= 18
            ? 'Watch tilt'
            : 'Within range';
    final severityColor = score >= 30
        ? colors.error
        : score >= 18
            ? colors.warning
            : colors.success;

    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.move, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Tilt',
                style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                ),
                child: Text(
                  severity,
                  style: NightshadeTypography.labelStrongSm.copyWith(color: severityColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Tilt direction visualizer
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _TiltDirectionPainter(
                  direction: direction,
                  magnitude: score,
                  arrowColor: severityColor,
                  ringColor: colors.border,
                  textColor: colors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              direction == 'unknown'
                  ? 'Need more solved frames to determine tilt direction'
                  : 'Strongest tilt points toward $direction',
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              score >= 30
                  ? 'Score ${score.toStringAsFixed(1)}: check tilt adjusters, focuser sag, or adapter seating.'
                  : score >= 18
                      ? 'Score ${score.toStringAsFixed(1)}: compare corners before making a mechanical change.'
                      : 'Score ${score.toStringAsFixed(1)}: tilt looks controlled for this session.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
