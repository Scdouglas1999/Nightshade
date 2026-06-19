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
///
/// `SequenceNode` is sealed: the switch is exhaustive, so adding a new node
/// type forces a decision here at compile time rather than silently
/// defaulting to "no duration".
bool hasMeaningfulDuration(SequenceNode node) {
  return switch (node) {
    ExposureNode _ ||
    AutofocusNode _ ||
    DelayNode _ ||
    WaitTimeNode _ ||
    SlewNode _ ||
    CenterNode _ ||
    MeridianFlipNode _ ||
    DitherNode _ ||
    FilterChangeNode _ ||
    RotatorNode _ ||
    ParkNode _ ||
    UnparkNode _ ||
    CoolCameraNode _ ||
    WarmCameraNode _ ||
    StartGuidingNode _ ||
    StopGuidingNode _ ||
    OpenDomeNode _ ||
    CloseDomeNode _ ||
    ParkDomeNode _ ||
    PolarAlignmentNode _ ||
    ScriptNode _ ||
    // SmartExposure has a meaningful (and often very
    // large) duration — display the time estimate inline like ExposureNode.
    SmartExposureNode _ ||
    // Audit §11 — plugin nodes carry an OPTIONAL per-node timeout that
    // bounds wall-clock cost; treat the duration as meaningful when the
    // operator supplied one, so the editor's timing section shows the
    // worst-case budget and the user can immediately tell which plugin
    // nodes might overrun the night.
    PluginInstructionNode _ ||
    // SciencePhotometry captures `count` frames at
    // `exposureSecs` apiece — total wall-clock is the count × exposure
    // sum (plus per-frame overhead), which is meaningful in the same
    // way ExposureNode's is. Surfacing the estimate in the editor warns
    // the user when a 600-frame burst would overrun the night.
    SciencePhotometryNode _ =>
      true,
    // Container/notification/cover/calibrator nodes have no intrinsic duration
    TargetHeaderNode _ ||
    InstructionSetNode _ ||
    LoopNode _ ||
    ParallelNode _ ||
    ConditionalNode _ ||
    RecoveryNode _ ||
    NotificationNode _ ||
    OpenCoverNode _ ||
    CloseCoverNode _ ||
    CalibratorOnNode _ ||
    CalibratorOffNode _ ||
    // TargetScheduler is a container — its duration is the
    // sum/max of its children's durations, which the timing estimator
    // computes by walking the subtree. The container itself has no
    // intrinsic per-node duration to display in the section header.
    TargetSchedulerNode _ ||
    // LiveStacking arms the broadcast and returns
    // immediately. The wall-clock cost is paid by sibling exposure
    // nodes, so this node itself has no displayable duration.
    LiveStackingNode _ =>
      false,
  };
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

    // Calculate timing for this node using the SHARED overhead model so the
    // node chip, the timeline, and the run-dashboard total all agree
    // (findings 5/9/16). The autofocus settings feed the runtime-injected AF
    // term in the total, which has no node in the tree.
    final overhead = ref.watch(sequencerOverheadConfigProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final estimator = SequenceTimeEstimator(overhead: overhead);
    final now = DateTime.now();
    final timings = estimator.estimateSequenceTiming(sequence, now);
    final nodeTiming = timings.where((t) => t.nodeId == node.id).firstOrNull;

    // Calculate total sequence duration for percentage, including the
    // runtime-injected autofocus runs the executor splices in (filter-change
    // AF + AF-interval cadence) so "Contributes X%" is measured against the
    // same total the run dashboard shows.
    final totalDuration = estimator.estimateTotalDuration(
      sequence,
      now,
      autoFocusOnFilterChange: appSettings?.autoFocusOnFilterChange ?? false,
      autoFocusEveryMinutes: appSettings?.autoFocusEveryMinutes ?? 0,
    );

    // Get node-specific duration details. The per-frame download overhead is
    // drawn from the shared config so the "Total" line here matches the chip
    // and the timeline rather than a divergent hard-coded 2 s literal.
    final durationDetails = _getDurationDetails(ref, overhead);

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
              padding: EdgeInsets.symmetric(
                  horizontal: Responsive.spacing(context, 8)),
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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final detail in durationDetails)
                  Padding(
                    padding:
                        EdgeInsets.only(bottom: Responsive.spacing(context, 4)),
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
          decoration: NightshadeDecorations.iconChip(
            colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            borderAlpha: 0.2,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clock,
                      size: sectionIconSize, color: colors.primary),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    'Duration:',
                    style: TextStyle(
                      fontSize: summaryFontSize,
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Flexible(
                    child: Text(
                      formatDurationNice(duration),
                      style: TextStyle(
                        fontSize: summaryFontSize,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
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
                    Flexible(
                      child: Text(
                        '${percentage.toStringAsFixed(1)}% of total',
                        style: TextStyle(
                          fontSize: contributeFontSize,
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
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
  ///
  /// [overhead] is the shared [SequenceOverheadConfig] (from
  /// [sequencerOverheadConfigProvider]) so the per-frame download cost shown in
  /// the breakdown matches the estimator, the chip, and the run dashboard.
  List<_DurationDetail>? _getDurationDetails(
    WidgetRef ref,
    SequenceOverheadConfig overhead,
  ) {
    if (node is ExposureNode) {
      final exposure = node as ExposureNode;
      final exposureTotal = exposure.durationSecs * exposure.count;
      final downloadOverhead =
          exposure.count * overhead.downloadOverheadPerExposureSecs;
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
          value: '$exposuresPerPoint x ${exposureDuration}s',
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
      final mins =
          (warm.targetTemp - (-10.0)).clamp(0.0, 60.0) / warm.ratePerMin;
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

    // SciencePhotometry — count × exposure plus the
    // standard per-frame download overhead, surfaced so the user sees
    // upfront that a 600-frame V0376 Per burst is a 10-hour
    // commitment.
    if (node is SciencePhotometryNode) {
      final phot = node as SciencePhotometryNode;
      final exposureTotal = phot.exposureSecs * phot.count;
      final downloadOverhead =
          phot.count * overhead.downloadOverheadPerExposureSecs;
      final total = exposureTotal + downloadOverhead;
      return [
        _DurationDetail(
          label: 'Frames',
          value:
              '${phot.count} x ${phot.exposureSecs.toStringAsFixed(phot.exposureSecs == phot.exposureSecs.truncate() ? 0 : 1)}s',
        ),
        _DurationDetail(
          label: 'Filter',
          value: phot.filter,
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
