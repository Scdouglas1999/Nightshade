// Stats bar, status indicator, exposure countdown and visualization toggles.
part of '../flat_preview_panel.dart';

class _StatsBar extends StatelessWidget {
  final FlatWizardState state;

  const _StatsBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Get current filter info
    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;

    // A dense readout row that must not overflow on a phone: the labelled
    // stats wrap, and the status indicator drops onto its own line when the
    // viewport is too narrow to keep it inline.
    final stats = [
      ResponsiveStat(
        label: 'Filter',
        value: currentFilter?.filterName ?? '-',
      ),
      ResponsiveStat(
        label: 'Exposure',
        value: currentFilter?.calibratedExposure != null
            ? '${currentFilter!.calibratedExposure!.toStringAsFixed(2)}s'
            : '-',
      ),
      ResponsiveStat(
        label: 'ADU',
        value: currentFilter?.currentAdu != null
            ? currentFilter!.currentAdu!.toStringAsFixed(0)
            : '-',
      ),
      ResponsiveStat(
        label: 'Frame',
        value: currentFilter != null
            ? '${currentFilter.capturedCount}/${currentFilter.frameCountOverride ?? state.globalSettings.frameCount}'
            : '-/-',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: NightshadeCard(
        variant: CardVariant.subtle,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep stats + status on one line only when there is comfortable
            // room; otherwise stack the status under the wrapped stats.
            final inline = constraints.maxWidth >= 460;
            final statStrip =
                ResponsiveStatStrip(stats: stats, minCellWidth: 96);
            final status = _StatusIndicator(
              status: currentFilter?.status ?? FilterCalibrationStatus.pending,
              colors: colors,
            );

            if (inline) {
              return Row(
                children: [
                  Expanded(child: statStrip),
                  const SizedBox(width: 16),
                  status,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                statStrip,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: status),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final FilterCalibrationStatus status;
  final NightshadeColors colors;

  const _StatusIndicator({
    required this.status,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      FilterCalibrationStatus.pending => (
          LucideIcons.clock,
          'Pending',
          colors.textMuted
        ),
      FilterCalibrationStatus.calibrating => (
          LucideIcons.settings,
          'Calibrating',
          colors.warning
        ),
      FilterCalibrationStatus.calibrated => (
          LucideIcons.check,
          'On Target',
          colors.success
        ),
      FilterCalibrationStatus.capturing => (
          LucideIcons.camera,
          'Capturing',
          colors.primary
        ),
      FilterCalibrationStatus.complete => (
          LucideIcons.checkCircle,
          'Complete',
          colors.success
        ),
      FilterCalibrationStatus.partial => (
          LucideIcons.alertTriangle,
          'Partial',
          colors.warning
        ),
      FilterCalibrationStatus.failed => (
          LucideIcons.alertCircle,
          'Failed',
          colors.error
        ),
      FilterCalibrationStatus.skipped => (
          LucideIcons.skipForward,
          'Skipped',
          colors.textMuted
        ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: NightshadeTypography.label.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ExposureCountdown extends StatefulWidget {
  final FlatWizardState state;

  const _ExposureCountdown({required this.state});

  @override
  State<_ExposureCountdown> createState() => _ExposureCountdownState();
}

class _ExposureCountdownState extends State<_ExposureCountdown> {
  // Owned so we can cancel on dispose — without an explicit Timer field this
  // recursive Future.delayed schedules a fresh timer every 100 ms whose
  // closure would outlive the widget tree on teardown (hot reload, widget
  // test, fast navigation).
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Trigger rebuilds for countdown animation
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !widget.state.isExposing) return;
      setState(() {});
      _scheduleNextTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    if (widget.state.exposureStartTime == null ||
        widget.state.currentExposureDuration == null) {
      return const SizedBox.shrink();
    }

    final elapsed = DateTime.now()
            .difference(widget.state.exposureStartTime!)
            .inMilliseconds /
        1000.0;
    final remaining = (widget.state.currentExposureDuration! - elapsed)
        .clamp(0.0, widget.state.currentExposureDuration!);
    final progress = elapsed / widget.state.currentExposureDuration!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.primary,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Text(
            'CAPTURING: ${remaining.toStringAsFixed(1)}s remaining',
            style: NightshadeTypography.labelStrong
                .copyWith(color: colors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: NightshadeProgressBar(
              value: progress.clamp(0.0, 1.0),
              height: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualizationsSection extends ConsumerWidget {
  final FlatWizardState state;

  const _VisualizationsSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    // Count visible visualizations
    final visibleCount = [
      state.showAduGraph,
      state.showFilterCards,
    ].where((v) => v).length;

    if (visibleCount == 0) {
      return const SizedBox.shrink();
    }

    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;
    final histogramTarget = currentFilter?.histogramTargetOverride ??
        state.globalSettings.histogramTarget;
    final tolerancePercent = currentFilter?.toleranceOverride ??
        state.globalSettings.tolerancePercent;
    // Target ADU against the DETECTED full scale so the convergence graph's
    // target/tolerance bands match what a 12/14/16-bit camera can actually
    // reach (not a hardcoded 16-bit range).
    final cameraConfig = ref.watch(flatCameraConfigProvider);
    final targetAdu = cameraConfig.targetAduFor(histogramTarget);
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggles
          Row(
            children: [
              Text(
                'Visualizations',
                style: NightshadeTypography.h6
                    .copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              _ToggleButton(
                icon: LucideIcons.lineChart,
                isActive: state.showAduGraph,
                onTap: () => ref
                    .read(flatWizardProvider.notifier)
                    .toggleAduGraph(!state.showAduGraph),
                tooltip: 'ADU Graph',
              ),
              _ToggleButton(
                icon: LucideIcons.layoutGrid,
                isActive: state.showFilterCards,
                onTap: () => ref
                    .read(flatWizardProvider.notifier)
                    .toggleFilterCards(!state.showFilterCards),
                tooltip: 'Filter Cards',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Visualization content
          Expanded(
            child: Row(
              children: [
                if (state.showAduGraph)
                  Expanded(
                    child: _AduConvergenceGraph(
                      history: state.aduHistory,
                      targetAdu: targetAdu,
                      toleranceAdu: toleranceAdu,
                    ),
                  ),
                if (state.showFilterCards)
                  Expanded(child: _FilterProgressCards(state: state)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;

  const _ToggleButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return NightshadeTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 4),
          decoration: isActive
              ? NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                )
              : const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? colors.primary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}
