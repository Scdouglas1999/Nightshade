import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// One row of the Scheduler screen's target queue table.
///
/// Renders the target name, current score, status (eligible, below
/// horizon, wrong side of meridian, time-windowed, etc.), and a compact
/// summary of per-filter remaining frames. Tapping the row fires
/// [onTap] which the screen uses to open the per-target constraints
/// editor and integration goals editor.
class TargetScoreRow extends StatelessWidget {
  final TargetScore score;
  final List<IntegrationGoalProgress> progress;
  final bool isCurrent;
  final bool isWinner;
  final VoidCallback? onTap;

  const TargetScoreRow({
    super.key,
    required this.score,
    required this.progress,
    required this.isCurrent,
    required this.isWinner,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final eligible = !score.hardConstraintFailed;
    final statusLabel = _statusLabel();
    final statusColor = _statusColor(colors);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceLg,
            vertical: NightshadeTokens.spaceMd,
          ),
          decoration: BoxDecoration(
            color: isCurrent
                ? colors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent
                  ? colors.primary.withValues(alpha: 0.35)
                  : colors.border.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              // Trophy / current-target marker (38 px wide for alignment).
              SizedBox(
                width: 38,
                child: Center(
                  child: isWinner
                      ? Icon(
                          LucideIcons.trophy,
                          size: NightshadeTokens.iconSm,
                          color: colors.warning,
                          semanticLabel: 'Winning target',
                        )
                      : isCurrent
                          ? Icon(
                              LucideIcons.play,
                              size: NightshadeTokens.iconSm,
                              color: colors.primary,
                              semanticLabel: 'Currently active target',
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              // Target name and rejection reasons (if any).
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.targetName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: eligible ? colors.textPrimary : colors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (!eligible && score.rejectionReasons.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        score.rejectionReasons.first,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.error,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              // Score (right-aligned, monospace-ish for column scanning).
              SizedBox(
                width: 78,
                child: Text(
                  score.totalScore.toStringAsFixed(3),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: eligible ? colors.textPrimary : colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              // Status pill.
              SizedBox(
                width: 130,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(
                    label: statusLabel,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              // Per-filter remaining frames summary.
              Expanded(
                flex: 4,
                child: _GoalSummary(progress: progress, colors: colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel() {
    if (score.hardConstraintFailed) {
      final reason = score.rejectionReasons.isEmpty
          ? 'rejected'
          : score.rejectionReasons.first;
      if (reason.contains('altitude') && reason.contains('below')) {
        return 'Below horizon';
      }
      if (reason.contains('moon')) return 'Moon avoidance';
      if (reason.contains('time window')) return 'Outside window';
      if (reason.contains('filter')) return 'Filter missing';
      if (reason.contains('goals complete')) return 'Complete';
      if (reason.contains('horizon profile')) return 'Behind horizon';
      return 'Rejected';
    }
    if (isCurrent) return 'Active';
    if (isWinner) return 'Selected';
    return 'Eligible';
  }

  Color _statusColor(NightshadeColors colors) {
    if (score.hardConstraintFailed) return colors.error;
    if (isCurrent) return colors.primary;
    if (isWinner) return colors.success;
    return colors.textSecondary;
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _GoalSummary extends StatelessWidget {
  final List<IntegrationGoalProgress> progress;
  final NightshadeColors colors;

  const _GoalSummary({required this.progress, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (progress.isEmpty) {
      return Text(
        'No integration goals',
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final p in progress)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: p.isComplete
                  ? colors.success.withValues(alpha: 0.12)
                  : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: p.isComplete
                    ? colors.success.withValues(alpha: 0.4)
                    : colors.border,
              ),
            ),
            child: Text(
              '${p.goal.filter} ${p.capturedCount}/${p.goal.frameCount}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.isComplete ? colors.success : colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
