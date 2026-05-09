import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'panel_widgets.dart';

class StackingPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const StackingPanel({super.key, required this.colors});

  @override
  ConsumerState<StackingPanel> createState() => _StackingPanelState();
}

class _StackingPanelState extends ConsumerState<StackingPanel> {
  bool _isStarting = false;
  bool _isStopping = false;

  Future<void> _startStacking() async {
    // Let user pick a reference image file
    const typeGroup = XTypeGroup(
      label: 'Image files',
      extensions: ['fits', 'fit', 'fts', 'xisf', 'tif', 'tiff', 'png'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _isStarting = true);

    try {
      final notifier = ref.read(liveStackingProvider.notifier);
      final config = ref.read(liveStackingProvider).config;
      await notifier.startFromFile(file.path, config: config);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopStacking() async {
    setState(() => _isStopping = true);
    try {
      await ref.read(liveStackingProvider.notifier).stop();
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _resetStack() async {
    await ref.read(liveStackingProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final stackState = ref.watch(liveStackingProvider);
    final isRunning = stackState.status == LiveStackingStatus.running;
    final isError = stackState.status == LiveStackingStatus.error;
    final stats = stackState.stats;
    final config = stackState.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error banner
          if (isError && stackState.errorMessage != null)
            _ErrorBanner(
              message: stackState.errorMessage!,
              colors: widget.colors,
            ),

          // Status and controls
          PanelSection(
            title: 'Live Stacking',
            colors: widget.colors,
            child: Column(
              children: [
                // Status indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Status',
                        style: TextStyle(
                            fontSize: 12,
                            color: widget.colors.textSecondary)),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isRunning
                                ? widget.colors.success
                                : isError
                                    ? widget.colors.error
                                    : widget.colors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRunning
                              ? 'Stacking'
                              : isError
                                  ? 'Error'
                                  : 'Idle',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isRunning
                                ? widget.colors.success
                                : isError
                                    ? widget.colors.error
                                    : widget.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Start/Stop buttons
                Row(
                  children: [
                    Expanded(
                      child: SmallButton(
                        label: _isStarting ? 'Starting...' : 'Start',
                        icon: _isStarting
                            ? LucideIcons.loader2
                            : LucideIcons.layers,
                        colors: widget.colors,
                        isEnabled: !isRunning && !_isStarting,
                        onTap: _startStacking,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: _isStopping ? 'Stopping...' : 'Stop',
                        icon: LucideIcons.square,
                        isOutline: true,
                        colors: widget.colors,
                        isEnabled: isRunning && !_isStopping,
                        onTap: _stopStacking,
                      ),
                    ),
                  ],
                ),
                if (isRunning) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SmallButton(
                      label: 'Reset Stack',
                      icon: LucideIcons.refreshCw,
                      isOutline: true,
                      colors: widget.colors,
                      onTap: _resetStack,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statistics
          PanelSection(
            title: 'Statistics',
            colors: widget.colors,
            child: Column(
              children: [
                _StatRow(
                  label: 'Stacked Frames',
                  value: '${stats.stackedFrameCount}',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Total Attempted',
                  value: '${stats.totalFramesAttempted}',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Rejected (Alignment)',
                  value: '${stats.rejectedAlignmentFailures}',
                  valueColor: stats.rejectedAlignmentFailures > 0
                      ? widget.colors.warning
                      : null,
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Matched Pairs',
                  value: stats.avgMatchedPairs.toStringAsFixed(1),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Alignment Residual',
                  value: '${stats.avgAlignmentResidual.toStringAsFixed(2)} px',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Sigma-Rejected Pixels',
                  value: _formatLargeNumber(stats.totalSigmaRejectedPixels),
                  colors: widget.colors,
                ),
                const SizedBox(height: 12),
                // Alignment quality indicator
                _AlignmentQualityBar(
                  stats: stats,
                  colors: widget.colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stacked preview
          if (stackState.previewData != null &&
              stackState.previewWidth > 0 &&
              stackState.previewHeight > 0)
            PanelSection(
              title: 'Stacked Preview',
              colors: widget.colors,
              child: _StackedPreview(
                previewData: stackState.previewData!,
                width: stackState.previewWidth,
                height: stackState.previewHeight,
                colors: widget.colors,
              ),
            ),

          if (stackState.previewData != null) const SizedBox(height: 20),

          // Sigma Clipping config
          PanelSection(
            title: 'Sigma Clipping',
            colors: widget.colors,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Enabled',
                        style: TextStyle(
                            fontSize: 12,
                            color: widget.colors.textSecondary)),
                    SizedBox(
                      height: 24,
                      child: Switch(
                        value: config.sigmaClipEnabled,
                        onChanged: (value) {
                          ref
                              .read(liveStackingProvider.notifier)
                              .updateConfig(
                                config.copyWith(sigmaClipEnabled: value),
                              );
                        },
                        activeColor: widget.colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Threshold',
                  value: config.sigmaClipThreshold,
                  min: 1.0,
                  max: 5.0,
                  suffix: '\u03c3',
                  colors: widget.colors,
                  onChanged: config.sigmaClipEnabled
                      ? (value) {
                          ref
                              .read(liveStackingProvider.notifier)
                              .updateConfig(
                                config.copyWith(sigmaClipThreshold: value),
                              );
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Star Matching config
          PanelSection(
            title: 'Star Matching',
            colors: widget.colors,
            child: Column(
              children: [
                InputRowEditable(
                  label: 'Max Stars',
                  value: config.maxMatchStars.toString(),
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(liveStackingProvider.notifier).updateConfig(
                            config.copyWith(maxMatchStars: parsed),
                          );
                    }
                  },
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Match Radius',
                  value: config.matchRadiusPx,
                  min: 5.0,
                  max: 200.0,
                  suffix: 'px',
                  colors: widget.colors,
                  onChanged: (value) {
                    ref.read(liveStackingProvider.notifier).updateConfig(
                          config.copyWith(matchRadiusPx: value),
                        );
                  },
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Flux Tolerance',
                  value: config.matchFluxTolerance,
                  min: 0.1,
                  max: 1.0,
                  suffix: '',
                  colors: widget.colors,
                  onChanged: (value) {
                    ref.read(liveStackingProvider.notifier).updateConfig(
                          config.copyWith(matchFluxTolerance: value),
                        );
                  },
                ),
                const SizedBox(height: 12),
                InputRowEditable(
                  label: 'Min Pairs',
                  value: config.minMatchedPairs.toString(),
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(liveStackingProvider.notifier).updateConfig(
                            config.copyWith(minMatchedPairs: parsed),
                          );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLargeNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String message;
  final NightshadeColors colors;

  const _ErrorBanner({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final NightshadeColors colors;

  const _StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Visual indicator of alignment quality based on stacking statistics.
class _AlignmentQualityBar extends StatelessWidget {
  final LiveStackingStats stats;
  final NightshadeColors colors;

  const _AlignmentQualityBar({
    required this.stats,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate quality from rejection ratio and alignment residual.
    // Quality = 1.0 means perfect, 0.0 means all frames rejected.
    double quality;
    String qualityLabel;
    Color qualityColor;

    if (stats.totalFramesAttempted == 0) {
      quality = 0.0;
      qualityLabel = 'No data';
      qualityColor = colors.textMuted;
    } else {
      final acceptanceRate = stats.stackedFrameCount / stats.totalFramesAttempted;
      // Residual penalty: >2px is poor, <0.5px is great
      final residualPenalty =
          (stats.avgAlignmentResidual / 2.0).clamp(0.0, 1.0);
      quality = (acceptanceRate * (1.0 - residualPenalty * 0.3)).clamp(0.0, 1.0);

      if (quality >= 0.8) {
        qualityLabel = 'Excellent';
        qualityColor = colors.success;
      } else if (quality >= 0.6) {
        qualityLabel = 'Good';
        qualityColor = colors.primary;
      } else if (quality >= 0.4) {
        qualityLabel = 'Fair';
        qualityColor = colors.warning;
      } else {
        qualityLabel = 'Poor';
        qualityColor = colors.error;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Alignment Quality',
                style:
                    TextStyle(fontSize: 11, color: colors.textSecondary)),
            Text(qualityLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: qualityColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: quality,
            minHeight: 6,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(qualityColor),
          ),
        ),
      ],
    );
  }
}

/// Displays the u16 stacked preview image, converting it to an 8-bit
/// displayable format on the fly.
class _StackedPreview extends StatefulWidget {
  final Uint16List previewData;
  final int width;
  final int height;
  final NightshadeColors colors;

  const _StackedPreview({
    required this.previewData,
    required this.width,
    required this.height,
    required this.colors,
  });

  @override
  State<_StackedPreview> createState() => _StackedPreviewState();
}

class _StackedPreviewState extends State<_StackedPreview> {
  ui.Image? _displayImage;
  bool _isDecoding = false;

  @override
  void initState() {
    super.initState();
    _buildDisplayImage();
  }

  @override
  void didUpdateWidget(_StackedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild when the data actually changes (identity check is fast)
    if (!identical(widget.previewData, oldWidget.previewData) ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height) {
      _buildDisplayImage();
    }
  }

  @override
  void dispose() {
    _displayImage?.dispose();
    super.dispose();
  }

  Future<void> _buildDisplayImage() async {
    if (_isDecoding) return;
    _isDecoding = true;

    final data = widget.previewData;
    final w = widget.width;
    final h = widget.height;
    final pixelCount = w * h;

    // Sanity check
    if (data.length < pixelCount) {
      _isDecoding = false;
      return;
    }

    // Find min/max for auto-stretch
    int minVal = 65535;
    int maxVal = 0;
    for (int i = 0; i < pixelCount; i++) {
      final v = data[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    final range = (maxVal - minVal).clamp(1, 65535);

    // Convert u16 mono to RGBA bytes with simple linear stretch
    final rgba = Uint8List(pixelCount * 4);
    for (int i = 0; i < pixelCount; i++) {
      final normalized = ((data[i] - minVal) * 255 ~/ range).clamp(0, 255);
      final offset = i * 4;
      rgba[offset] = normalized;
      rgba[offset + 1] = normalized;
      rgba[offset + 2] = normalized;
      rgba[offset + 3] = 255;
    }

    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _displayImage?.dispose();
          _displayImage = frame.image;
        });
      } else {
        frame.image.dispose();
      }

      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (e) {
      debugPrint('[StackingPanel] Error building preview image: $e');
    } finally {
      _isDecoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayImage == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('Rendering preview...',
                  style:
                      TextStyle(fontSize: 11, color: widget.colors.textMuted)),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: widget.width / widget.height,
        child: RawImage(
          image: _displayImage,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
