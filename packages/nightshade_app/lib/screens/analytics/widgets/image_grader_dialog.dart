// Image Grader: bulk frame rejection by per-frame quality thresholds.
//
// This is the "drag-the-bar to reject everything above HFR 2.8 / star count
// below 60" feature that SGP users love and that NINA's Auto-Focus After
// only approximates. We compute a live preview as the user moves sliders,
// then commit with one Apply press.
//
// Important: this never *deletes* image files — it only flips the database
// `isAccepted` flag (with a rejection reason). Acceptance restoration is
// a single tap on the rejected card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ImageGraderDialog extends ConsumerStatefulWidget {
  final List<DbCapturedImage> frames;
  final int? sessionId;

  const ImageGraderDialog({
    super.key,
    required this.frames,
    this.sessionId,
  });

  static Future<int?> show(
    BuildContext context, {
    required List<DbCapturedImage> frames,
    int? sessionId,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => ImageGraderDialog(frames: frames, sessionId: sessionId),
    );
  }

  @override
  ConsumerState<ImageGraderDialog> createState() => _ImageGraderDialogState();
}

class _ImageGraderDialogState extends ConsumerState<ImageGraderDialog> {
  late FrameGradeRules _rules = const FrameGradeRules();
  bool _rulesLoaded = false;
  bool _applying = false;
  String? _applyError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rulesLoaded) return;
    _rulesLoaded = true;
    final persisted = ref.read(scienceSettingsProvider).valueOrNull;
    _rules = persisted?.resolvedFrameGradeRules() ??
        FrameGradeRules.suggestFrom(widget.frames);
  }

  ({int rejected, int accepted, List<({DbCapturedImage frame, String reason})> rejections})
      _preview() {
    final rejections =
        <({DbCapturedImage frame, String reason})>[];
    var rejected = 0;
    for (final f in widget.frames) {
      final reason = _rules.gradeFrame(f);
      if (reason != null) {
        rejected++;
        rejections.add((frame: f, reason: reason));
      }
    }
    return (
      rejected: rejected,
      accepted: widget.frames.length - rejected,
      rejections: rejections,
    );
  }

  Future<void> _apply() async {
    final preview = _preview();
    if (preview.rejections.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      await ref
          .read(scienceSettingsProvider.notifier)
          .setFrameGradeRules(_rules);
      final dao = ref.read(imagesDaoProvider);
      for (final r in preview.rejections) {
        await dao.rejectImage(r.frame.id, r.reason);
      }
      if (!mounted) return;
      Navigator.of(context).pop(preview.rejected);
    } catch (e) {
      setState(() {
        _applying = false;
        _applyError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final preview = _preview();
    return Dialog(
      backgroundColor: colors.surface,
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 720,
          designMaxHeight: 640,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(colors: colors, frameCount: widget.frames.length),
              const SizedBox(height: 14),
              _ThresholdSliders(
                colors: colors,
                rules: _rules,
                frames: widget.frames,
                onChanged: (next) => setState(() => _rules = next),
              ),
              const SizedBox(height: 12),
              _PreviewSummary(
                colors: colors,
                rejected: preview.rejected,
                accepted: preview.accepted,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _RejectionList(
                  colors: colors,
                  rejections: preview.rejections,
                ),
              ),
              if (_applyError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _applyError!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed:
                        _applying ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  if (_applying)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    NightshadeButton(
                      onPressed: preview.rejected == 0 ? null : _apply,
                      label: preview.rejected == 0
                          ? 'Nothing to reject'
                          : 'Reject ${preview.rejected} frame'
                              '${preview.rejected == 1 ? "" : "s"}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final NightshadeColors colors;
  final int frameCount;

  const _Header({required this.colors, required this.frameCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.sliders, color: colors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Image grader',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Mark frames as rejected when they exceed any threshold below. '
                'Nothing is deleted — rejection can be undone per frame.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$frameCount frame${frameCount == 1 ? "" : "s"} loaded',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThresholdSliders extends StatelessWidget {
  final NightshadeColors colors;
  final FrameGradeRules rules;
  final List<DbCapturedImage> frames;
  final ValueChanged<FrameGradeRules> onChanged;

  const _ThresholdSliders({
    required this.colors,
    required this.rules,
    required this.frames,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hfrs = frames
        .map((f) => f.hfr)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList(growable: false);
    final stars = frames
        .map((f) => f.starCount)
        .whereType<int>()
        .toList(growable: false);
    final guiding = frames
        .map((f) => f.guidingRmsTotal)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList(growable: false);

    return Column(
      children: [
        _DoubleRow(
          colors: colors,
          label: 'Max HFR',
          unit: 'px',
          value: rules.maxHfr,
          available: hfrs,
          rangeMin: hfrs.isEmpty ? 0.0 : hfrs.reduce((a, b) => a < b ? a : b),
          rangeMax: hfrs.isEmpty ? 10.0 : hfrs.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(maxHfr: v)),
          onCleared: () => onChanged(rules.copyWith(clearHfr: true)),
        ),
        _IntRow(
          colors: colors,
          label: 'Min stars',
          value: rules.minStars,
          available: stars,
          rangeMin: stars.isEmpty ? 0 : stars.reduce((a, b) => a < b ? a : b),
          rangeMax:
              stars.isEmpty ? 200 : stars.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(minStars: v)),
          onCleared: () => onChanged(rules.copyWith(clearStars: true)),
        ),
        _DoubleRow(
          colors: colors,
          label: 'Max guiding RMS',
          unit: '"',
          value: rules.maxGuidingRmsTotalArcsec,
          available: guiding,
          rangeMin: 0,
          rangeMax: guiding.isEmpty
              ? 3.0
              : guiding.reduce((a, b) => a > b ? a : b),
          onChanged: (v) =>
              onChanged(rules.copyWith(maxGuidingRmsTotalArcsec: v)),
          onCleared: () => onChanged(rules.copyWith(clearGuiding: true)),
        ),
      ],
    );
  }
}

class _DoubleRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String unit;
  final double? value;
  final List<double> available;
  final double rangeMin;
  final double rangeMax;
  final ValueChanged<double> onChanged;
  final VoidCallback onCleared;

  const _DoubleRow({
    required this.colors,
    required this.label,
    required this.unit,
    required this.value,
    required this.available,
    required this.rangeMin,
    required this.rangeMax,
    required this.onChanged,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final span = rangeMax - rangeMin;
    final enabled = available.isNotEmpty;
    final effectiveValue = (value ?? rangeMax).clamp(rangeMin, rangeMax);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: Slider(
                min: rangeMin,
                max: rangeMax == rangeMin ? rangeMin + 1 : rangeMax,
                value: effectiveValue,
                divisions: span > 0 ? 40 : null,
                onChanged: enabled ? onChanged : null,
                activeColor: colors.primary,
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              value == null
                  ? 'off'
                  : '${value!.toStringAsFixed(2)} $unit',
              style: TextStyle(
                color: value == null ? colors.textMuted : colors.textPrimary,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: value == null ? 'Enable rule' : 'Disable rule',
            onPressed: () {
              if (value == null) {
                onChanged((rangeMin + rangeMax) / 2);
              } else {
                onCleared();
              }
            },
            icon: Icon(
              value == null ? LucideIcons.plus : LucideIcons.minus,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final int? value;
  final List<int> available;
  final int rangeMin;
  final int rangeMax;
  final ValueChanged<int> onChanged;
  final VoidCallback onCleared;

  const _IntRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.available,
    required this.rangeMin,
    required this.rangeMax,
    required this.onChanged,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = available.isNotEmpty;
    final effective = (value ?? rangeMin).clamp(rangeMin, rangeMax);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: Slider(
                min: rangeMin.toDouble(),
                max: rangeMax == rangeMin
                    ? (rangeMin + 1).toDouble()
                    : rangeMax.toDouble(),
                value: effective.toDouble(),
                divisions:
                    (rangeMax - rangeMin) > 0 ? (rangeMax - rangeMin) : null,
                onChanged: enabled
                    ? (v) => onChanged(v.round())
                    : null,
                activeColor: colors.primary,
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              value == null ? 'off' : '$value',
              style: TextStyle(
                color: value == null ? colors.textMuted : colors.textPrimary,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: value == null ? 'Enable rule' : 'Disable rule',
            onPressed: () {
              if (value == null) {
                onChanged(((rangeMin + rangeMax) / 2).round());
              } else {
                onCleared();
              }
            },
            icon: Icon(
              value == null ? LucideIcons.plus : LucideIcons.minus,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  final NightshadeColors colors;
  final int rejected;
  final int accepted;

  const _PreviewSummary({
    required this.colors,
    required this.rejected,
    required this.accepted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _Chip(
            colors: colors,
            label: 'Will reject',
            value: '$rejected',
            tone: rejected == 0 ? colors.textMuted : colors.warning,
          ),
          const SizedBox(width: 12),
          _Chip(
            colors: colors,
            label: 'Will keep',
            value: '$accepted',
            tone: colors.success,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final Color tone;

  const _Chip({
    required this.colors,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: NightshadeDecorations.statusChip(
        tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectionList extends StatelessWidget {
  final NightshadeColors colors;
  final List<({DbCapturedImage frame, String reason})> rejections;

  const _RejectionList(
      {required this.colors, required this.rejections});

  @override
  Widget build(BuildContext context) {
    if (rejections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'No frames currently fail any rule.',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: rejections.length,
        shrinkWrap: true,
        separatorBuilder: (_, __) =>
            Divider(color: colors.border, height: 1, thickness: 0.5),
        itemBuilder: (_, i) {
          final r = rejections[i];
          final filename = r.frame.filePath.split(RegExp(r'[\\/]')).last;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.reason,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
