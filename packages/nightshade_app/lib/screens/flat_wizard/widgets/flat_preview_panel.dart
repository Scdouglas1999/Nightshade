import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/astro_image_viewer.dart';

class FlatPreviewPanel extends ConsumerWidget {
  const FlatPreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(flatWizardProvider);

    return Column(
      children: [
        // Image preview area
        Expanded(
          flex: 3,
          child: _ImagePreview(
            imageData: state.lastImageData,
            showHistogram: state.showHistogramOverlay,
          ),
        ),

        // Stats bar
        _StatsBar(state: state),

        // Live countdown (when exposing)
        if (state.isExposing) _ExposureCountdown(state: state),

        // Toggleable visualizations
        Expanded(
          flex: 2,
          child: _VisualizationsSection(state: state),
        ),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final dynamic imageData;
  final bool showHistogram;

  const _ImagePreview({
    required this.imageData,
    required this.showHistogram,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Attempt to extract CapturedImageResult from the dynamic imageData field.
    // The flat wizard screen stores either a CapturedImageResult or raw Uint8List
    // depending on how setLastImage was called. We handle both for robustness.
    final CapturedImageResult? imageResult = _extractImageResult();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            // Image or empty state
            Positioned.fill(
              child: imageResult != null
                  ? _buildImage(imageResult, colors)
                  : _buildEmptyState(colors),
            ),

            // Histogram overlay (top right)
            if (showHistogram && imageResult != null)
              Positioned(
                top: 12,
                right: 12,
                child: _buildHistogramOverlay(imageResult, colors),
              ),
          ],
        ),
      ),
    );
  }

  /// Extract CapturedImageResult from the dynamic imageData field.
  /// Returns null if no valid image data is available.
  CapturedImageResult? _extractImageResult() {
    if (imageData == null) return null;
    if (imageData is CapturedImageResult) {
      return imageData as CapturedImageResult;
    }
    // If someone passed raw Uint8List (legacy path), we cannot render it
    // without width/height/isColor info, so treat as unavailable.
    return null;
  }

  Widget _buildImage(CapturedImageResult result, NightshadeColors colors) {
    final Uint8List displayBytes;
    if (result.displayData is Uint8List) {
      displayBytes = result.displayData as Uint8List;
    } else {
      displayBytes = Uint8List.fromList(result.displayData);
    }

    if (displayBytes.isEmpty || result.width <= 0 || result.height <= 0) {
      return _buildEmptyState(colors);
    }

    return AstroImageViewer(
      imageData: displayBytes,
      width: result.width,
      height: result.height,
      isColor: result.isColor,
      enableInteraction: true,
      minScale: 0.1,
      maxScale: 10.0,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _buildEmptyState(NightshadeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.image,
          size: 64,
          color: colors.textMuted,
        ),
        const SizedBox(height: 16),
        Text(
          'No flat captured yet',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start capture or test exposure to see preview',
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildHistogramOverlay(
      CapturedImageResult result, NightshadeColors colors) {
    return Container(
      width: 200,
      height: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Histogram',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
              Text(
                'Mean: ${result.stats.mean.toStringAsFixed(0)} ADU',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _HistogramChart(
              histogram: result.histogram,
              colors: colors,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0',
                style: TextStyle(
                  fontSize: 8,
                  color: colors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '255',
                style: TextStyle(
                  fontSize: 8,
                  color: colors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom painter that renders a histogram from 256-bin data.
/// Uses logarithmic scaling to handle the wide dynamic range typical of
/// flat frame ADU distributions (dominant mid-range peak with low tails).
class _HistogramChart extends StatelessWidget {
  final List<int> histogram;
  final NightshadeColors colors;

  const _HistogramChart({
    required this.histogram,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (histogram.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CustomPaint(
        painter: _HistogramPainter(
          histogram: histogram,
          barColor: colors.primary.withValues(alpha: 0.7),
          backgroundColor: colors.surfaceAlt,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> histogram;
  final Color barColor;
  final Color backgroundColor;

  _HistogramPainter({
    required this.histogram,
    required this.barColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    if (histogram.isEmpty) return;

    // Use logarithmic scaling to visualize the histogram.
    // Flat frames typically have a very dominant peak in the mid-range,
    // and log scaling makes the full distribution visible.
    final binCount = histogram.length;
    final barWidth = size.width / binCount;

    // Find the maximum log value for normalization, skipping the first and
    // last bins which can contain clipped pixel counts that skew the scale.
    double maxLogVal = 0;
    for (int i = 1; i < binCount - 1; i++) {
      if (histogram[i] > 0) {
        final logVal = math.log(histogram[i] + 1);
        if (logVal > maxLogVal) {
          maxLogVal = logVal;
        }
      }
    }
    // Also check first/last bins but cap them at the interior max so they
    // don't dominate the chart if they contain clipped pixels.
    if (maxLogVal == 0) {
      // All bins (excluding edges) are zero; fall back to using edges
      for (int i = 0; i < binCount; i++) {
        if (histogram[i] > 0) {
          final logVal = math.log(histogram[i] + 1);
          if (logVal > maxLogVal) {
            maxLogVal = logVal;
          }
        }
      }
    }
    if (maxLogVal == 0) return; // No data at all

    final barPaint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < binCount; i++) {
      if (histogram[i] <= 0) continue;

      final logVal = math.log(histogram[i] + 1);
      final normalizedHeight = (logVal / maxLogVal).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * size.height;

      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter oldDelegate) {
    return !identical(oldDelegate.histogram, histogram) ||
        oldDelegate.barColor != barColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _StatsBar extends StatelessWidget {
  final FlatWizardState state;

  const _StatsBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Get current filter info
    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Filter
          _StatItem(
            label: 'Filter',
            value: currentFilter?.filterName ?? '-',
            colors: colors,
          ),
          _divider(colors),

          // Exposure
          _StatItem(
            label: 'Exposure',
            value: currentFilter?.calibratedExposure != null
                ? '${currentFilter!.calibratedExposure!.toStringAsFixed(2)}s'
                : '-',
            colors: colors,
          ),
          _divider(colors),

          // ADU
          _StatItem(
            label: 'ADU',
            value: currentFilter?.currentAdu != null
                ? currentFilter!.currentAdu!.toStringAsFixed(0)
                : '-',
            colors: colors,
          ),
          _divider(colors),

          // Frame progress
          _StatItem(
            label: 'Frame',
            value: currentFilter != null
                ? '${currentFilter.capturedCount}/${currentFilter.frameCountOverride ?? state.globalSettings.frameCount}'
                : '-/-',
            colors: colors,
          ),
          _divider(colors),

          // Status
          Expanded(
            child: _StatusIndicator(
              status: currentFilter?.status ?? FilterCalibrationStatus.pending,
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(NightshadeColors colors) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: colors.border,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatItem({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
      ],
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
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
  @override
  void initState() {
    super.initState();
    // Trigger rebuilds for countdown animation
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && widget.state.isExposing) {
        setState(() {});
        _startCountdownTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

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
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Text(
            'CAPTURING: ${remaining.toStringAsFixed(1)}s remaining',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Count visible visualizations
    final visibleCount = [
      state.showAduGraph,
      state.showExposureTimeline,
      state.showSkyBrightness && state.mode == FlatWizardMode.skyFlats,
      state.showFilterCards,
    ].where((v) => v).length;

    if (visibleCount == 0) {
      return const SizedBox.shrink();
    }

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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
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
                icon: LucideIcons.barChart3,
                isActive: state.showExposureTimeline,
                onTap: () => ref
                    .read(flatWizardProvider.notifier)
                    .toggleExposureTimeline(!state.showExposureTimeline),
                tooltip: 'Exposure Timeline',
              ),
              if (state.mode == FlatWizardMode.skyFlats)
                _ToggleButton(
                  icon: LucideIcons.sunrise,
                  isActive: state.showSkyBrightness,
                  onTap: () => ref
                      .read(flatWizardProvider.notifier)
                      .toggleSkyBrightness(!state.showSkyBrightness),
                  tooltip: 'Sky Brightness',
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
                      child: _AduConvergenceGraph(history: state.aduHistory)),
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return NightshadeTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
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

class _AduConvergenceGraph extends StatelessWidget {
  final List<AduMeasurement> history;

  const _AduConvergenceGraph({required this.history});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ADU Convergence',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              history.isEmpty ? 'No data' : '${history.length} measurements',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _FilterProgressCards extends StatelessWidget {
  final FlatWizardState state;

  const _FilterProgressCards({required this.state});

  @override
  Widget build(BuildContext context) {
    final enabledFilters =
        state.filterSettings.where((f) => f.enabled).toList();

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: enabledFilters.length,
        itemBuilder: (context, index) {
          final filter = enabledFilters[index];
          return _FilterCard(
            filter: filter,
            globalFrameCount: state.globalSettings.frameCount,
          );
        },
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final FlatFilterSettings filter;
  final int globalFrameCount;

  const _FilterCard({
    required this.filter,
    required this.globalFrameCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final frameCount = filter.frameCountOverride ?? globalFrameCount;
    final progress = frameCount > 0 ? filter.capturedCount / frameCount : 0.0;

    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filter.status == FilterCalibrationStatus.capturing
              ? colors.primary
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filter.filterName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            filter.calibratedExposure != null
                ? '${filter.calibratedExposure!.toStringAsFixed(2)}s'
                : 'Not calibrated',
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          NightshadeProgressBar(
            value: progress,
            height: 4,
          ),
          const SizedBox(height: 2),
          Text(
            '${filter.capturedCount}/$frameCount',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
