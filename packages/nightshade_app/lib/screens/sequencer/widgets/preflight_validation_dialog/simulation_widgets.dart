part of '../preflight_validation_dialog.dart';

class _SimulationMetric extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final Color? tone;

  const _SimulationMetric({
    required this.colors,
    required this.label,
    required this.value,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = tone ?? colors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulationTimeline extends StatelessWidget {
  final NightshadeColors colors;
  final PreSessionSimulationResult simulation;

  const _SimulationTimeline({
    required this.colors,
    required this.simulation,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = simulation.duration.inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            for (final segment in simulation.segments)
              Expanded(
                flex: segment.duration.inMilliseconds.clamp(1, totalMs),
                child: Tooltip(
                  message:
                      '${segment.nodeName}: ${DurationFormat.of(segment.duration, style: DurationStyle.compact)}',
                  child: Container(
                    margin: const EdgeInsets.only(right: 1),
                    color: _colorFor(segment),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(PreSessionSimulationSegment segment) {
    switch (segment.nodeType) {
      case 'TakeExposure':
        return colors.primary;
      case 'SmartExposure':
        return colors.info;
      case 'Autofocus':
        return colors.warning;
      case 'SlewToTarget':
      case 'CenterTarget':
        return colors.success;
      default:
        return colors.textMuted;
    }
  }
}

class _SimulationIssueRow extends StatelessWidget {
  final NightshadeColors colors;
  final PreSessionSimulationIssue issue;

  const _SimulationIssueRow({
    required this.colors,
    required this.issue,
  });

  @override
  Widget build(BuildContext context) {
    final tone = switch (issue.severity) {
      PreSessionSimulationSeverity.error => colors.error,
      PreSessionSimulationSeverity.warning => colors.warning,
      PreSessionSimulationSeverity.info => colors.info,
    };
    final icon = switch (issue.severity) {
      PreSessionSimulationSeverity.error => LucideIcons.xCircle,
      PreSessionSimulationSeverity.warning => LucideIcons.alertTriangle,
      PreSessionSimulationSeverity.info => LucideIcons.info,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              issue.message,
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small count badge widget
