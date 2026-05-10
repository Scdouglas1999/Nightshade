import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../localization/nightshade_localizations.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  int? _selectedSessionId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMobile = Responsive.isMobile(context);
    final sessionsAsync = ref.watch(allSessionsProvider);
    final l10n = context.l10n;

    // Auto-select current session if none selected
    final sessionState = ref.watch(sessionStateProvider);
    if (_selectedSessionId == null && sessionState.dbSessionId != null) {
      _selectedSessionId = sessionState.dbSessionId;
    }

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.microscope, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                l10n.text('diagnosticsTitle'),
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              // Session selector
              sessionsAsync.when(
                data: (sessions) => _SessionSelector(
                  sessions: sessions,
                  selectedSessionId: _selectedSessionId,
                  onChanged: (id) => setState(() => _selectedSessionId = id),
                  colors: colors,
                ),
                loading: () => const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => Text(
                  l10n.text('diagnosticsLoadSessionsFailed'),
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Lower tilt and collimation scores are better. Use this screen to judge field shape and spacing before changing hardware.',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Main content
          Expanded(
            child: _selectedSessionId == null
                ? EmptyState(
                    icon: LucideIcons.star,
                    title: l10n.text('diagnosticsNoSessionTitle'),
                    body: l10n.text('diagnosticsNoSessionBody'),
                  )
                : _DiagnosticsContent(
                    sessionId: _selectedSessionId!,
                    isMobile: isMobile,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionSelector extends StatelessWidget {
  final List<ImagingSession> sessions;
  final int? selectedSessionId;
  final ValueChanged<int?> onChanged;
  final NightshadeColors colors;

  const _SessionSelector({
    required this.sessions,
    required this.selectedSessionId,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Text(
        context.l10n.text('diagnosticsNoSessions'),
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      );
    }

    final dateFormat = DateFormat('MMM d, HH:mm');
    final sessionsByRecency = sessions.reversed.toList();
    final recentSessions = sessionsByRecency.take(50).toList();
    final selectedSession = selectedSessionId == null
        ? null
        : sessions.cast<ImagingSession?>().firstWhere(
              (session) => session?.id == selectedSessionId,
              orElse: () => null,
            );
    final visibleSessions = [...recentSessions];

    if (selectedSession != null &&
        !visibleSessions.any((session) => session.id == selectedSession.id)) {
      visibleSessions.insert(0, selectedSession);
    }

    final dropdownValue = selectedSessionId != null &&
            visibleSessions.any((session) => session.id == selectedSessionId)
        ? selectedSessionId
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: dropdownValue,
          hint: Text(
            context.l10n.text('diagnosticsSelectSession'),
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          dropdownColor: colors.surfaceElevated,
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          items: visibleSessions.map((session) {
            final label = session.name != null && session.name!.isNotEmpty
                ? '${session.name} (${dateFormat.format(session.startTime)})'
                : dateFormat.format(session.startTime);
            return DropdownMenuItem(
              value: session.id,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _NoSessionSelected extends StatelessWidget {
  final NightshadeColors colors;

  const _NoSessionSelected({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.star, size: 48, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            context.l10n.text('diagnosticsNoSessionTitle'),
            style: TextStyle(
              fontSize: 15,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('diagnosticsNoSessionBody'),
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsContent extends ConsumerWidget {
  final int sessionId;
  final bool isMobile;

  const _DiagnosticsContent({
    required this.sessionId,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final diagnosticsAsync =
        ref.watch(opticalTrainDiagnosticsProvider(sessionId));
    final psfAsync = ref.watch(psfTilesForSessionProvider(sessionId));
    final residualsAsync =
        ref.watch(residualVectorsForSessionProvider(sessionId));

    return diagnosticsAsync.when(
      data: (diagnostics) {
        final psfTiles = psfAsync.valueOrNull ?? const [];
        final residuals = residualsAsync.valueOrNull ?? const [];

        if (isMobile) {
          return _MobileLayout(
            diagnostics: diagnostics,
            psfTiles: psfTiles,
            residuals: residuals,
            colors: colors,
          );
        }

        return _DesktopLayout(
          diagnostics: diagnostics,
          psfTiles: psfTiles,
          residuals: residuals,
          colors: colors,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 32, color: colors.error),
            const SizedBox(height: 12),
            Text(
              context.l10n.text('diagnosticsFailedTitle'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text('diagnosticsFailedBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            NightshadeButton(
              label: context.l10n.text('diagnosticsRetry'),
              icon: LucideIcons.refreshCw,
              size: ButtonSize.small,
              onPressed: () {
                ref.invalidate(opticalTrainDiagnosticsProvider(sessionId));
                ref.invalidate(psfTilesForSessionProvider(sessionId));
                ref.invalidate(residualVectorsForSessionProvider(sessionId));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final List<PsfFieldTileRow> psfTiles;
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;

  const _DesktopLayout({
    required this.diagnostics,
    required this.psfTiles,
    required this.residuals,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: health grade + issues
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _HealthGradeCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _TiltAssessmentCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _CollimationCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _IssuesCard(diagnostics: diagnostics, colors: colors),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right column: field map + residual overlay
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _PsfFieldMapCard(
                  psfTiles: psfTiles,
                  colors: colors,
                ),
                const SizedBox(height: 12),
                _ResidualVectorCard(
                  residuals: residuals,
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final List<PsfFieldTileRow> psfTiles;
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;

  const _MobileLayout({
    required this.diagnostics,
    required this.psfTiles,
    required this.residuals,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _HealthGradeCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _TiltAssessmentCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _CollimationCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _PsfFieldMapCard(psfTiles: psfTiles, colors: colors),
          const SizedBox(height: 12),
          _ResidualVectorCard(residuals: residuals, colors: colors),
          const SizedBox(height: 12),
          _IssuesCard(diagnostics: diagnostics, colors: colors),
        ],
      ),
    );
  }
}

// --- Health Grade Card ---

class _HealthGradeCard extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final NightshadeColors colors;

  const _HealthGradeCard({
    required this.diagnostics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final overallScore = _computeOverallScore(diagnostics);
    final grade = _gradeForScore(overallScore);
    final gradeColor = _colorForScore(overallScore, colors);

    return _DiagCard(
      colors: colors,
      child: Column(
        children: [
          Text(
            'Optical Health',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Large grade letter
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gradeColor.withValues(alpha: 0.15),
              border: Border.all(color: gradeColor, width: 3),
            ),
            child: Center(
              child: Text(
                grade,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: gradeColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _labelForScore(overallScore),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: gradeColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lower bars are better. Use this grade as a quick summary before diving into the field map and findings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
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

  double _computeOverallScore(OpticalTrainDiagnostics d) {
    // Invert: lower tilt/collimation = better health.
    // Score 0-100 where 100 is perfect.
    final tiltPenalty = d.tiltScore.clamp(0, 100);
    final collPenalty = d.collimationScore.clamp(0, 100);
    return (100.0 - (tiltPenalty * 0.5 + collPenalty * 0.5)).clamp(0.0, 100.0);
  }

  String _gradeForScore(double score) {
    if (score >= 90) return 'A';
    if (score >= 75) return 'B';
    if (score >= 55) return 'C';
    if (score >= 35) return 'D';
    return 'F';
  }

  String _labelForScore(double score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 55) return 'Fair';
    if (score >= 35) return 'Poor';
    return 'Critical';
  }

  Color _colorForScore(double score, NightshadeColors colors) {
    if (score >= 75) return colors.success;
    if (score >= 55) return colors.warning;
    return colors.error;
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
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clampedValue / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(3),
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: barColor,
            ),
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  severity,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: severityColor,
                  ),
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
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TiltDirectionPainter extends CustomPainter {
  final String direction;
  final double magnitude;
  final Color arrowColor;
  final Color ringColor;
  final Color textColor;

  _TiltDirectionPainter({
    required this.direction,
    required this.magnitude,
    required this.arrowColor,
    required this.ringColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Draw outer ring
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ringPaint);

    // Draw inner dot (center reference)
    final dotPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, dotPaint);

    // Draw cardinal labels
    final textStyle = TextStyle(fontSize: 9, color: textColor);
    _drawLabel(
        canvas, 'T', Offset(center.dx, center.dy - radius - 2), textStyle);
    _drawLabel(
        canvas, 'B', Offset(center.dx, center.dy + radius + 2), textStyle);
    _drawLabel(
        canvas, 'L', Offset(center.dx - radius - 2, center.dy), textStyle);
    _drawLabel(
        canvas, 'R', Offset(center.dx + radius + 2, center.dy), textStyle);

    // Draw arrow toward dominant direction
    if (direction == 'unknown') return;

    final angle = _directionToAngle(direction);
    final arrowLength = (magnitude / 100.0).clamp(0.1, 0.9) * radius;
    final arrowEnd = Offset(
      center.dx + arrowLength * math.cos(angle),
      center.dy + arrowLength * math.sin(angle),
    );

    final arrowPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, arrowEnd, arrowPaint);

    // Arrowhead
    const headLength = 8.0;
    final headAngle1 = angle + math.pi * 0.8;
    final headAngle2 = angle - math.pi * 0.8;
    canvas.drawLine(
      arrowEnd,
      Offset(
        arrowEnd.dx + headLength * math.cos(headAngle1),
        arrowEnd.dy + headLength * math.sin(headAngle1),
      ),
      arrowPaint,
    );
    canvas.drawLine(
      arrowEnd,
      Offset(
        arrowEnd.dx + headLength * math.cos(headAngle2),
        arrowEnd.dy + headLength * math.sin(headAngle2),
      ),
      arrowPaint,
    );
  }

  double _directionToAngle(String dir) {
    switch (dir) {
      case 'top edge':
        return -math.pi / 2; // Up
      case 'bottom edge':
        return math.pi / 2; // Down
      case 'left edge':
        return math.pi; // Left
      case 'right edge':
        return 0; // Right
      default:
        return 0;
    }
  }

  void _drawLabel(
      Canvas canvas, String text, Offset position, TextStyle style) {
    final span = TextSpan(text: text, style: style);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(position.dx - painter.width / 2, position.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TiltDirectionPainter old) =>
      direction != old.direction ||
      magnitude != old.magnitude ||
      arrowColor != old.arrowColor;
}

// --- Collimation Card ---

class _CollimationCard extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final NightshadeColors colors;

  const _CollimationCard({
    required this.diagnostics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final score = diagnostics.collimationScore;
    final severity = score >= 25
        ? 'Off-center'
        : score >= 15
            ? 'Slight offset'
            : 'Centered';
    final severityColor = score >= 25
        ? colors.error
        : score >= 15
            ? colors.warning
            : colors.success;

    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Collimation',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  severity,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: severityColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Collimation visualizer: concentric rings with off-center indicator
          Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: CustomPaint(
                painter: _CollimationPainter(
                  score: score,
                  statusColor: severityColor,
                  ringColor: colors.border,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Lower is better. Edge/center residual ratio: ${score.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              score >= 25
                  ? 'A strong offset usually points to spacing or alignment that needs attention.'
                  : score >= 15
                      ? 'A mild offset is present. Recheck spacing before making larger adjustments.'
                      : 'Center and edge behavior look balanced for this session.',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollimationPainter extends CustomPainter {
  final double score;
  final Color statusColor;
  final Color ringColor;

  _CollimationPainter({
    required this.score,
    required this.statusColor,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 4;

    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric rings
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * i / 4, ringPaint);
    }

    // Draw crosshair
    final crossPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      crossPaint,
    );

    // Draw offset indicator dot — the further off-center, the worse the collimation
    final offsetFraction = (score / 100.0).clamp(0.0, 0.8);
    final offsetDot = Offset(
      center.dx + offsetFraction * maxRadius * 0.5,
      center.dy - offsetFraction * maxRadius * 0.3,
    );
    final dotPaint = Paint()
      ..color = statusColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offsetDot, 5, dotPaint);

    // Draw glow around dot
    final glowPaint = Paint()
      ..color = statusColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offsetDot, 10, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _CollimationPainter old) =>
      score != old.score || statusColor != old.statusColor;
}

// --- PSF Field Map Card ---

class _PsfFieldMapCard extends StatelessWidget {
  final List<PsfFieldTileRow> psfTiles;
  final NightshadeColors colors;

  const _PsfFieldMapCard({
    required this.psfTiles,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.grid, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'PSF Field Map',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${psfTiles.length} tiles',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (psfTiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No PSF field tile data for this session.\nCapture plate-solved frames to generate PSF maps.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1.5,
              child: CustomPaint(
                painter: _PsfFieldMapPainter(
                  tiles: psfTiles,
                  goodColor: colors.success,
                  warnColor: colors.warning,
                  badColor: colors.error,
                  borderColor: colors.border,
                  textColor: colors.textPrimary,
                  bgColor: colors.surfaceAlt,
                ),
              ),
            ),
          if (psfTiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Color legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(
                  color: colors.success,
                  label: context.l10n.text('diagnosticsLowHfr'),
                ),
                const SizedBox(width: 16),
                _LegendDot(
                  color: colors.warning,
                  label: context.l10n.text('diagnosticsMedium'),
                ),
                const SizedBox(width: 16),
                _LegendDot(
                  color: colors.error,
                  label: context.l10n.text('diagnosticsHighHfr'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _PsfFieldMapPainter extends CustomPainter {
  final List<PsfFieldTileRow> tiles;
  final Color goodColor;
  final Color warnColor;
  final Color badColor;
  final Color borderColor;
  final Color textColor;
  final Color bgColor;

  _PsfFieldMapPainter({
    required this.tiles,
    required this.goodColor,
    required this.warnColor,
    required this.badColor,
    required this.borderColor,
    required this.textColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;

    final maxRow =
        tiles.map((t) => t.tileRow).fold<int>(0, (a, b) => a > b ? a : b);
    final maxCol =
        tiles.map((t) => t.tileCol).fold<int>(0, (a, b) => a > b ? a : b);
    final numRows = maxRow + 1;
    final numCols = maxCol + 1;

    if (numRows == 0 || numCols == 0) return;

    final cellWidth = size.width / numCols;
    final cellHeight = size.height / numRows;

    // Compute HFR range across all tiles for normalization
    final hfrValues =
        tiles.map((t) => t.medianHfr).where((v) => v > 0).toList();
    if (hfrValues.isEmpty) return;

    final minHfr = hfrValues.reduce(math.min);
    final maxHfr = hfrValues.reduce(math.max);
    final hfrRange = (maxHfr - minHfr).clamp(0.01, double.infinity);

    // Build lookup
    final lookup = <(int, int), PsfFieldTileRow>{};
    for (final tile in tiles) {
      lookup[(tile.tileRow, tile.tileCol)] = tile;
    }

    for (int row = 0; row < numRows; row++) {
      for (int col = 0; col < numCols; col++) {
        final rect = Rect.fromLTWH(
          col * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );

        final tile = lookup[(row, col)];
        if (tile == null || tile.medianHfr <= 0) {
          // Empty tile
          final emptyPaint = Paint()..color = bgColor;
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
            emptyPaint,
          );
          continue;
        }

        // Normalize HFR to 0-1 (0 = best, 1 = worst)
        final normalized = (tile.medianHfr - minHfr) / hfrRange;

        // Interpolate color: green -> yellow -> red
        final color = Color.lerp(
          Color.lerp(goodColor, warnColor, (normalized * 2).clamp(0.0, 1.0)),
          badColor,
          ((normalized - 0.5) * 2).clamp(0.0, 1.0),
        )!;

        final cellPaint = Paint()..color = color.withValues(alpha: 0.7);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
          cellPaint,
        );

        // Draw border
        final borderPaint = Paint()
          ..color = borderColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
          borderPaint,
        );

        // Draw HFR value text if cell is big enough
        if (cellWidth > 40 && cellHeight > 25) {
          final span = TextSpan(
            text: tile.medianHfr.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          );
          final painter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(
            canvas,
            Offset(
              rect.center.dx - painter.width / 2,
              rect.center.dy - painter.height / 2,
            ),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PsfFieldMapPainter old) => tiles != old.tiles;
}

// --- Residual Vector Card ---

class _ResidualVectorCard extends StatelessWidget {
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;

  const _ResidualVectorCard({
    required this.residuals,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.wind, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Astrometric Residuals',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${residuals.length} vectors',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (residuals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No astrometric residual data for this session.\nCapture plate-solved frames to generate residual vectors.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1.5,
              child: CustomPaint(
                painter: _ResidualVectorPainter(
                  residuals: residuals,
                  vectorColor: colors.primary,
                  gridColor: colors.border,
                  bgColor: colors.surfaceAlt,
                ),
              ),
            ),
          if (residuals.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResidualStats(residuals: residuals, colors: colors),
          ],
        ],
      ),
    );
  }
}

class _ResidualStats extends StatelessWidget {
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;

  const _ResidualStats({
    required this.residuals,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final magnitudes = residuals.map((r) => r.magnitudeArcsec).toList();
    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final maxMag = magnitudes.reduce(math.max);
    final minMag = magnitudes.reduce(math.min);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatChip(
            label: context.l10n.text('diagnosticsMean'),
            value: '${mean.toStringAsFixed(2)}"',
            colors: colors),
        _StatChip(
            label: context.l10n.text('diagnosticsMin'),
            value: '${minMag.toStringAsFixed(2)}"',
            colors: colors),
        _StatChip(
            label: context.l10n.text('diagnosticsMax'),
            value: '${maxMag.toStringAsFixed(2)}"',
            colors: colors),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: colors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ResidualVectorPainter extends CustomPainter {
  final List<AstrometryResidualVectorRow> residuals;
  final Color vectorColor;
  final Color gridColor;
  final Color bgColor;

  _ResidualVectorPainter({
    required this.residuals,
    required this.vectorColor,
    required this.gridColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (residuals.isEmpty) return;

    // Background
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    // Grid lines
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Find max magnitude for scaling vectors
    final maxMag = residuals
        .map((r) => r.magnitudeArcsec)
        .reduce(math.max)
        .clamp(0.1, double.infinity);
    final scaleFactor = math.min(size.width, size.height) * 0.08 / maxMag;

    final vectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (final r in residuals) {
      // x, y are 0-1 normalized field positions
      final px = r.x * size.width;
      final py = r.y * size.height;
      final dx = r.dxArcsec * scaleFactor;
      final dy = r.dyArcsec * scaleFactor;

      // Color by magnitude: green for small, red for large
      final normalizedMag = (r.magnitudeArcsec / maxMag).clamp(0.0, 1.0);
      final color = Color.lerp(vectorColor, vectorColor.withValues(alpha: 0.3),
          1.0 - normalizedMag)!;
      vectorPaint.color = color;

      // Draw dot at position
      final dotPaint = Paint()
        ..color = vectorColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 2, dotPaint);

      // Draw vector arrow
      canvas.drawLine(
        Offset(px, py),
        Offset(px + dx, py + dy),
        vectorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResidualVectorPainter old) =>
      residuals != old.residuals;
}

// --- Issues Card ---

class _IssuesCard extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final NightshadeColors colors;

  const _IssuesCard({
    required this.diagnostics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.clipboardList, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Findings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${diagnostics.issues.length} item${diagnostics.issues.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (diagnostics.issues.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No issues detected',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            )
          else
            ...diagnostics.issues.map(
              (issue) => _IssueRow(issue: issue, colors: colors),
            ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final OpticalDiagnosticIssue issue;
  final NightshadeColors colors;

  const _IssueRow({
    required this.issue,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (issue.severity) {
      OpticalIssueSeverity.critical => (LucideIcons.alertOctagon, colors.error),
      OpticalIssueSeverity.warning => (
          LucideIcons.alertTriangle,
          colors.warning
        ),
      OpticalIssueSeverity.info => (LucideIcons.info, colors.info),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  issue.detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Shared Card Container ---

class _DiagCard extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _DiagCard({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}
