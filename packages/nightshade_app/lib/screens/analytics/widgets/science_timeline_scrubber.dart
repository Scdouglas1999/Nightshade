import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceTimelineScrubber extends StatefulWidget {
  final NightshadeColors colors;
  final List<ScienceFrameQualityMetricsRow> frameMetrics;
  final ValueChanged<int?>? onFrameSelected;

  const ScienceTimelineScrubber({
    super.key,
    required this.colors,
    required this.frameMetrics,
    this.onFrameSelected,
  });

  @override
  State<ScienceTimelineScrubber> createState() =>
      _ScienceTimelineScrubberState();
}

class _ScienceTimelineScrubberState extends State<ScienceTimelineScrubber> {
  double _slider = 0;

  @override
  Widget build(BuildContext context) {
    final metrics = widget.frameMetrics.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final hasData = metrics.isNotEmpty;
    final selectedIndex =
        hasData ? _slider.round().clamp(0, metrics.length - 1) : 0;
    final selected = hasData ? metrics[selectedIndex] : null;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline Scrubber',
              style: TextStyle(
                color: widget.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (!hasData)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    'No frame quality metrics yet.',
                    style: TextStyle(color: widget.colors.textMuted),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 54,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < metrics.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Container(
                            height: 8 + _normalized(metrics[i].snr) * 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i == selectedIndex
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF2563EB)
                                      .withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Slider(
                value: _slider.clamp(0, (metrics.length - 1).toDouble()),
                min: 0,
                max: (metrics.length - 1).toDouble(),
                onChanged: (value) {
                  setState(() => _slider = value);
                  final idx = value.round().clamp(0, metrics.length - 1);
                  widget.onFrameSelected?.call(metrics[idx].capturedImageId);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selected == null
                          ? 'Frame --'
                          : 'Frame ${selectedIndex + 1}/${metrics.length}',
                      style: TextStyle(
                        color: widget.colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (selected != null)
                    Text(
                      'SNR ${selected.snr.toStringAsFixed(1)} | Clip H ${selected.highClipPercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: widget.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _normalized(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return (math.log(value.clamp(0.01, 1e9)) / math.ln2 / 8.0).clamp(0.0, 1.0);
  }
}
