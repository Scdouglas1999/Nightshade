import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Formats a Duration into a human-readable string like "5m 30s", "1h 20m", etc.
String formatDurationNice(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s';
  }
  if (duration.inMinutes < 60) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (secs == 0) {
      return '${mins}m';
    }
    return '${mins}m ${secs}s';
  }
  final hours = duration.inHours;
  final mins = duration.inMinutes % 60;
  if (mins == 0) {
    return '${hours}h';
  }
  return '${hours}h ${mins}m';
}

/// Checks if a node type has a meaningful duration that should be displayed.
bool hasMeaningfulDuration(SequenceNode node) {
  return node is ExposureNode ||
      node is AutofocusNode ||
      node is DelayNode ||
      node is WaitTimeNode ||
      node is SlewNode ||
      node is CenterNode ||
      node is MeridianFlipNode ||
      node is DitherNode ||
      node is FilterChangeNode ||
      node is RotatorNode ||
      node is ParkNode ||
      node is UnparkNode ||
      node is CoolCameraNode ||
      node is WarmCameraNode ||
      node is StartGuidingNode ||
      node is StopGuidingNode ||
      node is OpenDomeNode ||
      node is CloseDomeNode ||
      node is ParkDomeNode ||
      node is PolarAlignmentNode ||
      node is ScriptNode;
}

/// Widget that displays timing information for a sequence node.
class NodeTimingSection extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const NodeTimingSection({
    super.key,
    required this.colors,
    required this.node,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    if (sequence == null) return const SizedBox.shrink();

    // Calculate timing for this node
    final estimator = SequenceTimeEstimator();
    final timings = estimator.estimateSequenceTiming(sequence, DateTime.now());
    final nodeTiming = timings.where((t) => t.nodeId == node.id).firstOrNull;

    // Calculate total sequence duration for percentage
    final totalDuration =
        estimator.estimateTotalDuration(sequence, DateTime.now());

    // Get node-specific duration details
    final durationDetails = _getDurationDetails(ref);

    // If we have no timing info and no details, don't show the section
    if (nodeTiming == null && durationDetails == null) {
      return const SizedBox.shrink();
    }

    final duration = nodeTiming?.duration ?? Duration.zero;
    final percentage = totalDuration.inSeconds > 0
        ? (duration.inSeconds / totalDuration.inSeconds * 100)
        : 0.0;

    final sectionHeaderFontSize = Responsive.fontSize(context, 11);
    final detailFontSize = Responsive.fontSize(context, 12);
    final summaryFontSize = Responsive.fontSize(context, 13);
    final contributeFontSize = Responsive.fontSize(context, 12);
    final sectionIconSize = Responsive.iconSize(context, 15);
    final sectionPadding = Responsive.spacing(context, 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with divider line
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: colors.border,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Responsive.spacing(context, 8)),
              child: Text(
                'Timing',
                style: TextStyle(
                  fontSize: sectionHeaderFontSize,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: colors.border,
              ),
            ),
          ],
        ),
        SizedBox(height: sectionPadding),

        // Node-specific duration details (if any)
        if (durationDetails != null) ...[
          Container(
            padding: EdgeInsets.all(sectionPadding),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final detail in durationDetails)
                  Padding(
                    padding: EdgeInsets.only(bottom: Responsive.spacing(context, 4)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          detail.label,
                          style: TextStyle(
                            fontSize: detailFontSize,
                            color: colors.textSecondary,
                          ),
                        ),
                        Text(
                          detail.value,
                          style: TextStyle(
                            fontSize: detailFontSize,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: sectionPadding),
        ],

        // Summary timing info
        Container(
          padding: EdgeInsets.all(sectionPadding),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clock, size: sectionIconSize, color: colors.primary),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    'Duration:',
                    style: TextStyle(
                      fontSize: summaryFontSize,
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    formatDurationNice(duration),
                    style: TextStyle(
                      fontSize: summaryFontSize,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              if (totalDuration.inSeconds > 0 && percentage > 0.1) ...[
                SizedBox(height: Responsive.spacing(context, 8)),
                Row(
                  children: [
                    Icon(LucideIcons.pieChart,
                        size: sectionIconSize, color: colors.textMuted),
                    SizedBox(width: Responsive.spacing(context, 8)),
                    Text(
                      'Contributes:',
                      style: TextStyle(
                        fontSize: contributeFontSize,
                        color: colors.textSecondary,
                      ),
                    ),
                    SizedBox(width: Responsive.spacing(context, 8)),
                    Text(
                      '${percentage.toStringAsFixed(1)}% of total',
                      style: TextStyle(
                        fontSize: contributeFontSize,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        SizedBox(height: Responsive.spacing(context, 16)),
      ],
    );
  }

  /// Returns node-specific duration breakdown details, or null if not applicable.
  List<_DurationDetail>? _getDurationDetails(WidgetRef ref) {
    if (node is ExposureNode) {
      final exposure = node as ExposureNode;
      final exposureTotal = exposure.durationSecs * exposure.count;
      // Estimate download overhead at ~2 seconds per frame
      final downloadOverhead = exposure.count * 2.0;
      final total = exposureTotal + downloadOverhead;

      return [
        _DurationDetail(
          label: 'Exposures',
          value:
              '${exposure.count} x ${exposure.durationSecs.toStringAsFixed(exposure.durationSecs == exposure.durationSecs.truncate() ? 0 : 1)}s',
        ),
        _DurationDetail(
          label: 'Download overhead',
          value: '~${downloadOverhead.toStringAsFixed(0)}s',
        ),
        _DurationDetail(
          label: 'Total',
          value: formatDurationNice(Duration(seconds: total.round())),
        ),
      ];
    }

    if (node is AutofocusNode) {
      final autofocus = node as AutofocusNode;

      // Use global settings values when useSettingsDefaults is ON
      final int stepsOut;
      final int exposuresPerPoint;
      final double exposureDuration;

      if (autofocus.useSettingsDefaults) {
        final afSettings = ref.read(autofocusSettingsProvider);
        stepsOut = afSettings.initialOffsetSteps;
        exposuresPerPoint = afSettings.exposuresPerPoint;
        exposureDuration = afSettings.exposureTime;
      } else {
        stepsOut = autofocus.stepsOut;
        exposuresPerPoint = autofocus.exposuresPerPoint;
        exposureDuration = autofocus.exposureDuration;
      }

      // Calculate: (stepsOut * 2 + 1) data points, each with exposuresPerPoint exposures
      final dataPoints = stepsOut * 2 + 1;
      final totalExposures = dataPoints * exposuresPerPoint;
      final totalSecs = totalExposures * exposureDuration;

      return [
        _DurationDetail(
          label: 'Data points',
          value: '$dataPoints',
        ),
        _DurationDetail(
          label: 'Exposures/point',
          value:
              '$exposuresPerPoint x ${exposureDuration}s',
        ),
        _DurationDetail(
          label: 'Est. duration',
          value: formatDurationNice(Duration(seconds: totalSecs.round())),
        ),
        if (autofocus.useSettingsDefaults)
          const _DurationDetail(
            label: 'Source',
            value: 'Global settings',
          ),
      ];
    }

    if (node is DelayNode) {
      final delay = node as DelayNode;
      return [
        _DurationDetail(
          label: 'Delay',
          value: formatDurationNice(
              Duration(milliseconds: (delay.seconds * 1000).round())),
        ),
      ];
    }

    if (node is WaitTimeNode) {
      final wait = node as WaitTimeNode;
      if (wait.waitUntil != null) {
        return [
          _DurationDetail(
            label: 'Wait until',
            value:
                '${wait.waitUntil!.hour.toString().padLeft(2, '0')}:${wait.waitUntil!.minute.toString().padLeft(2, '0')}',
          ),
        ];
      } else if (wait.waitForTwilight != null) {
        final twilightName = switch (wait.waitForTwilight!) {
          TwilightType.civil => 'Civil twilight',
          TwilightType.nautical => 'Nautical twilight',
          TwilightType.astronomical => 'Astronomical twilight',
        };
        return [
          _DurationDetail(
            label: 'Wait for',
            value: twilightName,
          ),
        ];
      }
    }

    if (node is SlewNode) {
      return const [
        _DurationDetail(
          label: 'Est. slew time',
          value: '~30s',
        ),
      ];
    }

    if (node is CenterNode) {
      final center = node as CenterNode;
      return [
        const _DurationDetail(
          label: 'Est. centering time',
          value: '~30s',
        ),
        _DurationDetail(
          label: 'Max attempts',
          value: '${center.maxAttempts}',
        ),
      ];
    }

    if (node is MeridianFlipNode) {
      final flip = node as MeridianFlipNode;
      var totalSecs = 120.0; // Base flip time
      if (flip.autoCenter) {
        totalSecs += 30; // Add centering time
      }
      totalSecs += flip.settleTime;

      return [
        const _DurationDetail(
          label: 'Flip duration',
          value: '~2m',
        ),
        if (flip.autoCenter)
          const _DurationDetail(
            label: 'Auto-center',
            value: '~30s',
          ),
        _DurationDetail(
          label: 'Settle time',
          value: '${flip.settleTime.toStringAsFixed(0)}s',
        ),
        _DurationDetail(
          label: 'Est. total',
          value: formatDurationNice(Duration(seconds: totalSecs.round())),
        ),
      ];
    }

    if (node is CoolCameraNode) {
      final cool = node as CoolCameraNode;
      return [
        _DurationDetail(
          label: 'Max cooling time',
          value: '${(cool.durationMins ?? 10).toStringAsFixed(0)}m',
        ),
      ];
    }

    if (node is WarmCameraNode) {
      final warm = node as WarmCameraNode;
      final mins = (warm.targetTemp - (-10.0)).clamp(0.0, 60.0) / warm.ratePerMin;
      return [
        _DurationDetail(
          label: 'Warming rate',
          value: '${warm.ratePerMin}C/min',
        ),
        _DurationDetail(
          label: 'Target temp',
          value: '${warm.targetTemp.toStringAsFixed(1)}C',
        ),
        _DurationDetail(
          label: 'Est. duration',
          value: '~${mins.round()}m',
        ),
      ];
    }

    if (node is DitherNode) {
      final dither = node as DitherNode;
      return [
        _DurationDetail(
          label: 'Settle time',
          value: '${dither.settleTime.toStringAsFixed(0)}s',
        ),
      ];
    }

    if (node is FilterChangeNode) {
      return const [
        _DurationDetail(
          label: 'Est. change time',
          value: '~10s',
        ),
      ];
    }

    if (node is RotatorNode) {
      return const [
        _DurationDetail(
          label: 'Est. rotation time',
          value: '~15s',
        ),
      ];
    }

    if (node is ParkNode || node is UnparkNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~30s',
        ),
      ];
    }

    if (node is StartGuidingNode) {
      final guiding = node as StartGuidingNode;
      return [
        _DurationDetail(
          label: 'Settle timeout',
          value: '${guiding.settleTimeout.toStringAsFixed(0)}s',
        ),
      ];
    }

    if (node is StopGuidingNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~2s',
        ),
      ];
    }

    if (node is OpenDomeNode || node is CloseDomeNode || node is ParkDomeNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~1m',
        ),
      ];
    }

    if (node is PolarAlignmentNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~5m',
        ),
        _DurationDetail(
          label: 'Note',
          value: '3 plate solves + adjustment',
        ),
      ];
    }

    if (node is ScriptNode) {
      final script = node as ScriptNode;
      return [
        _DurationDetail(
          label: 'Timeout',
          value: '${script.timeoutSecs ?? 30}s',
        ),
      ];
    }

    return null;
  }
}

/// Helper class for duration detail display.
class _DurationDetail {
  final String label;
  final String value;

  const _DurationDetail({
    required this.label,
    required this.value,
  });
}
