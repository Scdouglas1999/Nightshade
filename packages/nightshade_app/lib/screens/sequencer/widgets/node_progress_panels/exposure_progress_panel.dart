part of '../node_progress_panels.dart';

class _ExposureProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final InstructionProgressDetail? structuredDetail;
  final ExposureNode node;

  const _ExposureProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    this.structuredDetail,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    final exposureDetail = structuredDetail is ExposureInstructionProgressDetail
        ? structuredDetail as ExposureInstructionProgressDetail
        : null;
    // Parse legacy detail: "Frame 3/10" or "Exposing: 45s remaining".
    final frameMatch = RegExp(r'Frame (\d+)/(\d+)').firstMatch(detail);
    final currentFrame =
        exposureDetail?.frame ?? int.tryParse(frameMatch?.group(1) ?? '') ?? 0;
    final totalFrames = exposureDetail?.total ??
        int.tryParse(frameMatch?.group(2) ?? '') ??
        node.count;
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
              Icon(Icons.camera, size: 16, color: colors.success),
              const SizedBox(width: 8),
              Text(
                'Exposure: ${node.filter ?? 'No Filter'}',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$currentFrame / $totalFrames frames',
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
            completedFrames: currentFrame - 1,
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

  @override
  Widget build(BuildContext context) {
    // Limit display to reasonable number
    final displayFrames = totalFrames > 20 ? 20 : totalFrames;
    final frameSize = totalFrames > 10 ? 14.0 : 18.0;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(displayFrames, (i) {
        final frameNum = i + 1;
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
            boxShadow: null,
          ),
        );
      }),
    );
  }
}
