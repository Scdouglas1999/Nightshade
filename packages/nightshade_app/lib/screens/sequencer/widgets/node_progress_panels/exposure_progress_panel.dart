part of '../node_progress_panels.dart';

class _ExposureProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final InstructionProgressDetail? structuredDetail;
  final ExposureNode node;

  /// The node finished all its frames. The live per-frame detail is cleared on
  /// the success path, so without this the card fell back to frame 0 and read
  /// "0 / 4 frames" directly above the four thumbnails it had just captured.
  final bool isComplete;

  /// The filter the run is imaging through, when the node itself names none.
  ///
  /// A node with `filter == null` does not image unfiltered — it images
  /// through whatever is in the wheel, and every other surface said so: the
  /// telemetry strip read `Filter: R`, the thumbnails `Filter R`, the files on
  /// disk `M42-TEST_R_0001.fits`, the session report a single `R` row. Only
  /// this header called it "No Filter", two rows under a target rollup reading
  /// "R 180s" (Wave D, SEQ-19).
  final String? runFilter;

  const _ExposureProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    this.structuredDetail,
    required this.node,
    this.isComplete = false,
    this.runFilter,
  });

  /// What to call the filter on this card. The node's own choice wins; the
  /// run's filter is the fallback and is marked as inherited rather than
  /// presented as if the node had asked for it.
  String get _filterLabel {
    final own = node.filter;
    if (own != null && own.isNotEmpty) return own;
    final live = runFilter;
    if (live != null && live.isNotEmpty) return '$live (current)';
    return 'No filter set';
  }

  @override
  Widget build(BuildContext context) {
    final exposureDetail = structuredDetail is ExposureInstructionProgressDetail
        ? structuredDetail as ExposureInstructionProgressDetail
        : null;
    // Compatibility fallback: older / remote backends that have not been
    // upgraded to the typed ExposureInstructionProgressDetail still emit a
    // plain "Frame 3/10" string. The typed path above is preferred; this
    // regex only runs when it is absent. Kept (not deleted) until every
    // shipped backend is confirmed to populate the typed detail.
    final frameMatch = RegExp(r'Frame (\d+)/(\d+)').firstMatch(detail);
    final totalFrames = exposureDetail?.total ??
        int.tryParse(frameMatch?.group(2) ?? '') ??
        node.count;
    final liveFrame =
        exposureDetail?.frame ?? int.tryParse(frameMatch?.group(1) ?? '') ?? 0;
    // A finished node has no frame in flight; every planned frame is done.
    final currentFrame = isComplete ? 0 : liveFrame;
    final completedFrames = isComplete ? totalFrames : liveFrame - 1;
    final durationSecs =
        exposureDetail != null && exposureDetail.durationSecs > 0
            ? exposureDetail.durationSecs
            : node.durationSecs;

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(NightshadeIcons.camera, size: 16, color: colors.success),
              const SizedBox(width: 8),
              // The filter name is the elastic half of this header: the frame
              // counter is the number the operator is watching and must never
              // be the thing that gets pushed off the panel. Both were rigid,
              // so a long filter name or a scaled-up font size overflowed the
              // row instead of truncating the title.
              Expanded(
                child: Text(
                  'Exposure: $_filterLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: NightshadeTypography.labelStrongSm
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isComplete ? totalFrames : currentFrame} / $totalFrames '
                'frames',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Frame grid
          _FrameGrid(
            colors: colors,
            totalFrames: totalFrames,
            completedFrames: completedFrames,
            currentFrame: currentFrame,
          ),
          const SizedBox(height: 12),

          // Duration info
          Row(
            children: [
              _StatBox(
                colors: colors,
                label: 'Duration',
                value: durationSecs.toStringAsFixed(0),
                unit: 's',
                color: colors.success,
              ),
              const SizedBox(width: 12),
              _StatBox(
                colors: colors,
                label: 'Total',
                value: (durationSecs * totalFrames / 60).toStringAsFixed(1),
                unit: 'min',
                color: colors.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FrameGrid extends StatelessWidget {
  final NightshadeColors colors;
  final int totalFrames;
  final int completedFrames;
  final int currentFrame;

  const _FrameGrid({
    required this.colors,
    required this.totalFrames,
    required this.completedFrames,
    required this.currentFrame,
  });

  /// Cap on individually-rendered cells. Above this we render the first
  /// [_maxCells]-1 frames plus a single "+N" summary cell so a 200-frame
  /// exposure node doesn't paint 200 squares.
  static const int _maxCells = 20;

  @override
  Widget build(BuildContext context) {
    final frameSize = totalFrames > 10 ? 14.0 : 18.0;
    final overflow = totalFrames > _maxCells;
    // When overflowing, show the first 19 frames as real cells and reserve
    // the 20th slot for a "+N" tally of the remaining frames.
    final individualCells = overflow ? _maxCells - 1 : totalFrames;

    Widget cell(int frameNum) {
      final isCompleted = frameNum <= completedFrames;
      final isCurrent = frameNum == currentFrame;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: frameSize,
        height: frameSize,
        decoration: BoxDecoration(
          color: isCompleted
              ? colors.success
              : isCurrent
                  ? colors.info
                  : colors.surface,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
          border: Border.all(
            color: isCompleted
                ? colors.success
                : isCurrent
                    ? colors.info
                    : colors.border,
            width: isCurrent ? 2 : 1,
          ),
        ),
      );
    }

    final children = <Widget>[
      for (var i = 0; i < individualCells; i++) cell(i + 1),
    ];

    if (overflow) {
      final remaining = totalFrames - individualCells;
      // How many of the remaining (hidden) frames are already done — colours
      // the tally green once the run has advanced past the shown cells.
      final remainingCompleted =
          (completedFrames - individualCells).clamp(0, remaining);
      final allRemainingDone = remainingCompleted >= remaining;
      // Slightly wider than a single cell so the "+N" label fits.
      children.add(
        Container(
          height: frameSize,
          constraints: BoxConstraints(minWidth: frameSize * 1.6),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: allRemainingDone
                ? colors.success.withValues(alpha: 0.18)
                : colors.surface,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
            border: Border.all(
              color: allRemainingDone ? colors.success : colors.border,
            ),
          ),
          child: Text(
            '+$remaining',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize9,
              fontWeight: FontWeight.w700,
              color: allRemainingDone ? colors.success : colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    return Wrap(spacing: 4, runSpacing: 4, children: children);
  }
}
