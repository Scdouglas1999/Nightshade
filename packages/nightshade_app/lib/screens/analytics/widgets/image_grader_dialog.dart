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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/authority_bound_dialog.dart';
import '../analytics_screen.dart' show dbSessionImagesProvider;

typedef ImageGraderPsfMetric = ({double? fwhm, double? eccentricity});

/// Load the PSF metrics used by the grader from the authoritative host.
///
/// A mobile companion has its own (normally empty) local database, so reading
/// [ScienceDao] there silently disables the FWHM and eccentricity rules. The
/// network backend already exposes the host's session science products; local
/// mode continues to read Drift directly.
Future<Map<int, ImageGraderPsfMetric>> loadImageGraderPsfMetrics({
  required NightshadeBackend backend,
  required ScienceDao? localScienceDao,
  required List<DbCapturedImage> frames,
  int? sessionId,
}) async {
  final frameIds = frames.map((frame) => frame.id).toSet();
  final tiles = <PsfFieldTileRow>[];

  if (backend is NetworkBackend) {
    if (sessionId != null) {
      tiles.addAll(await backend.getSessionPsfTiles(sessionId));
    } else {
      tiles.addAll((await backend.getSessionlessScienceBundle()).psfTiles);
    }
  } else {
    final dao = localScienceDao;
    if (dao == null) {
      throw StateError('A local science database is required in local mode');
    }
    if (sessionId != null) {
      tiles.addAll(await dao.getPsfTilesForSession(sessionId));
    } else {
      for (final frame in frames) {
        tiles.addAll(await dao.getPsfTilesForImage(frame.id));
      }
    }
  }

  final grouped = <int, List<PsfFieldTileRow>>{};
  for (final tile in tiles) {
    final imageId = tile.capturedImageId;
    if (imageId == null || !frameIds.contains(imageId)) continue;
    grouped.putIfAbsent(imageId, () => []).add(tile);
  }

  final result = <int, ImageGraderPsfMetric>{};
  for (final entry in grouped.entries) {
    final fwhms = <double>[];
    final eccentricities = <double>[];
    for (final tile in entry.value) {
      if (tile.starCount <= 0) continue;
      if (tile.medianFwhm.isFinite && tile.medianFwhm > 0) {
        fwhms.add(tile.medianFwhm);
      }
      if (tile.medianEccentricity.isFinite && tile.medianEccentricity > 0) {
        eccentricities.add(tile.medianEccentricity);
      }
    }
    final fwhm = _imageGraderMedian(fwhms);
    final eccentricity = _imageGraderMedian(eccentricities);
    if (fwhm != null || eccentricity != null) {
      result[entry.key] = (fwhm: fwhm, eccentricity: eccentricity);
    }
  }
  return result;
}

double? _imageGraderMedian(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = values.toList(growable: false)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2.0;
}

FrameGradeRules resolveImageGraderRules(
  ScienceSettings settings,
  List<DbCapturedImage> frames,
) {
  final persisted = settings.resolvedFrameGradeRules();
  return persisted.isEmpty ? FrameGradeRules.suggestFrom(frames) : persisted;
}

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
  FrameGradeRules _rules = const FrameGradeRules();
  bool _rulesLoading = true;
  String? _rulesError;
  bool _applying = false;
  String? _applyError;

  /// Per-frame field medians from the science PSF tiles. FWHM and
  /// eccentricity are not persisted on captured_images, so the grader
  /// sources them here — same data the capture-time auto-grader uses, so
  /// the preview and the automatic path can never disagree. Frames without
  /// PSF products simply have no entry and skip those rules.
  Map<int, ImageGraderPsfMetric> _psfMetricsByImage = const {};
  bool _psfMetricsLoading = true;
  String? _psfMetricsError;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _authorityGeneration = 0;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _authorityGeneration++;
        setState(() {
          _applying = false;
          _applyError = 'Connected rig changed; reopen the grader to continue.';
        });
        closeAuthorityBoundDialog(context);
      },
    );
    unawaited(_loadRules());
    unawaited(_loadPsfMetrics());
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  Future<void> _loadRules() async {
    if (_rulesError != null) {
      ref.invalidate(scienceSettingsProvider);
    }
    if (!_rulesLoading) {
      setState(() {
        _rulesLoading = true;
        _rulesError = null;
      });
    }
    try {
      final settings = await ref.read(scienceSettingsProvider.future);
      if (mounted) {
        setState(() {
          _rules = resolveImageGraderRules(settings, widget.frames);
          _rulesLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _rulesLoading = false;
          _rulesError = error.toString();
        });
      }
    }
  }

  Future<void> _loadPsfMetrics() async {
    if (!_psfMetricsLoading) {
      setState(() {
        _psfMetricsLoading = true;
        _psfMetricsError = null;
      });
    }
    final backend = ref.read(backendProvider);
    final generation = _authorityGeneration;
    try {
      final result = await loadImageGraderPsfMetrics(
        backend: backend,
        localScienceDao:
            backend is NetworkBackend ? null : ref.read(scienceDaoProvider),
        frames: widget.frames,
        sessionId: widget.sessionId,
      );
      if (_isCurrentAuthority(backend, generation)) {
        setState(() {
          _psfMetricsByImage = result;
          _psfMetricsLoading = false;
        });
      }
    } catch (error) {
      if (_isCurrentAuthority(backend, generation)) {
        setState(() {
          _psfMetricsLoading = false;
          _psfMetricsError = error.toString();
        });
      }
    }
  }

  bool _isCurrentAuthority(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _authorityGeneration &&
      identical(ref.read(backendProvider), backend);

  ({
    int rejected,
    int accepted,
    List<({DbCapturedImage frame, String reason})> rejections
  }) _preview() {
    final rejections = <({DbCapturedImage frame, String reason})>[];
    var rejected = 0;
    for (final f in widget.frames) {
      final metrics = _psfMetricsByImage[f.id];
      final reason = _rules.gradeFrame(
        f,
        fwhm: metrics?.fwhm,
        eccentricity: metrics?.eccentricity,
      );
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
    if (_applying) return;
    final backend = ref.read(backendProvider);
    final generation = _authorityGeneration;
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
      if (!_isCurrentAuthority(backend, generation)) return;
      final repo = ref.read(imagingRecordsRepositoryProvider);
      for (final r in preview.rejections) {
        if (!_isCurrentAuthority(backend, generation)) return;
        await repo.rejectImage(r.frame.id, r.reason);
        if (!_isCurrentAuthority(backend, generation)) return;
      }
      if (!mounted) return;
      ref.invalidate(dbSessionImagesProvider);
      Navigator.of(context).pop(preview.rejected);
    } catch (e) {
      if (!_isCurrentAuthority(backend, generation)) return;
      setState(() {
        _applying = false;
        _applyError = e.toString();
      });
    }
  }

  String _activeRuleSummary() {
    final parts = <String>[
      if (_rules.maxHfr != null) 'HFR ≤ ${_rules.maxHfr!.toStringAsFixed(2)}',
      if (_rules.maxFwhm != null)
        'FWHM ≤ ${_rules.maxFwhm!.toStringAsFixed(2)}',
      if (_rules.maxEccentricity != null)
        'ecc ≤ ${_rules.maxEccentricity!.toStringAsFixed(2)}',
      if (_rules.minStars != null) 'stars ≥ ${_rules.minStars}',
      if (_rules.maxGuidingRmsTotalArcsec != null)
        'RMS ≤ ${_rules.maxGuidingRmsTotalArcsec!.toStringAsFixed(2)}"',
    ];
    return parts.isEmpty ? 'No active rules' : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final preview = _preview();
    final frameCount = widget.frames.length;
    return NightshadeDialog(
      title: 'Image grader',
      icon: LucideIcons.sliders,
      width: 720,
      height: 640,
      closeEnabled: !_applying,
      actions: [
        NightshadeButton(
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
        ),
        NightshadeButton(
          onPressed:
              _rulesLoading || _rulesError != null || preview.rejected == 0
                  ? null
                  : _apply,
          isLoading: _applying,
          label: preview.rejected == 0
              ? 'Nothing to reject'
              : 'Reject ${preview.rejected} frame'
                  '${preview.rejected == 1 ? "" : "s"}',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mark frames as rejected when they exceed any threshold below. '
            'Nothing is deleted — rejection can be undone per frame.',
            style: NightshadeTypography.caption
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            '$frameCount frame${frameCount == 1 ? "" : "s"} loaded',
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
          ),
          if (_rulesLoading) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'Loading saved grading rules…',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ] else if (_rulesError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved grading rules could not be loaded. Applying is '
                    'disabled to protect the existing settings.',
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
                TextButton(onPressed: _loadRules, child: const Text('Retry')),
              ],
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceMd + 2),
          _ThresholdSliders(
            colors: colors,
            rules: _rules,
            frames: widget.frames,
            psfMetricsByImage: _psfMetricsByImage,
            onChanged: (next) => setState(() => _rules = next),
          ),
          if (_psfMetricsLoading) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'Loading FWHM and eccentricity measurements…',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ] else if (_psfMetricsError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'FWHM and eccentricity are unavailable. Those rules will '
                    'not be applied until the measurements load.',
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.warning,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loadPsfMetrics,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceMd),
          _PreviewSummary(
            colors: colors,
            rejected: preview.rejected,
            accepted: preview.accepted,
            activeRules: _activeRuleSummary(),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _RejectionList(
            colors: colors,
            rejections: preview.rejections,
          ),
          if (_applyError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              _applyError!,
              style: NightshadeTypography.caption.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThresholdSliders extends StatelessWidget {
  final NightshadeColors colors;
  final FrameGradeRules rules;
  final List<DbCapturedImage> frames;
  final Map<int, ({double? fwhm, double? eccentricity})> psfMetricsByImage;
  final ValueChanged<FrameGradeRules> onChanged;

  const _ThresholdSliders({
    required this.colors,
    required this.rules,
    required this.frames,
    required this.psfMetricsByImage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hfrs = frames
        .map((f) => f.hfr)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList(growable: false);
    final stars =
        frames.map((f) => f.starCount).whereType<int>().toList(growable: false);
    final guiding = frames
        .map((f) => f.guidingRmsTotal)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList(growable: false);
    final fwhms = psfMetricsByImage.values
        .map((m) => m.fwhm)
        .whereType<double>()
        .toList(growable: false);
    final eccs = psfMetricsByImage.values
        .map((m) => m.eccentricity)
        .whereType<double>()
        .toList(growable: false);

    return Column(
      children: [
        _DoubleRow(
          colors: colors,
          label: 'Max HFR',
          unit: 'px',
          metric: 'HFR',
          value: rules.maxHfr,
          available: hfrs,
          rangeMin: hfrs.isEmpty ? 0.0 : hfrs.reduce((a, b) => a < b ? a : b),
          rangeMax: hfrs.isEmpty ? 10.0 : hfrs.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(maxHfr: v)),
          onCleared: () => onChanged(rules.copyWith(clearHfr: true)),
        ),
        // FWHM / eccentricity come from each frame's PSF field map (science
        // pipeline product); frames without one skip these rules, and the
        // sliders disable entirely when no frame has PSF data.
        _DoubleRow(
          colors: colors,
          label: 'Max FWHM',
          unit: 'px',
          metric: 'FWHM',
          value: rules.maxFwhm,
          available: fwhms,
          rangeMin: fwhms.isEmpty ? 0.0 : fwhms.reduce((a, b) => a < b ? a : b),
          rangeMax:
              fwhms.isEmpty ? 12.0 : fwhms.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(maxFwhm: v)),
          onCleared: () => onChanged(rules.copyWith(clearFwhm: true)),
        ),
        _DoubleRow(
          colors: colors,
          label: 'Max eccentricity',
          unit: '',
          metric: 'eccentricity',
          value: rules.maxEccentricity,
          available: eccs,
          rangeMin: 0,
          rangeMax: eccs.isEmpty ? 1.0 : eccs.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(maxEccentricity: v)),
          onCleared: () => onChanged(rules.copyWith(clearEccentricity: true)),
        ),
        _IntRow(
          colors: colors,
          label: 'Min stars',
          metric: 'star count',
          value: rules.minStars,
          available: stars,
          rangeMin: stars.isEmpty ? 0 : stars.reduce((a, b) => a < b ? a : b),
          rangeMax: stars.isEmpty ? 200 : stars.reduce((a, b) => a > b ? a : b),
          onChanged: (v) => onChanged(rules.copyWith(minStars: v)),
          onCleared: () => onChanged(rules.copyWith(clearStars: true)),
        ),
        _DoubleRow(
          colors: colors,
          label: 'Max guiding RMS',
          unit: '"',
          metric: 'guiding',
          value: rules.maxGuidingRmsTotalArcsec,
          available: guiding,
          rangeMin: 0,
          rangeMax:
              guiding.isEmpty ? 3.0 : guiding.reduce((a, b) => a > b ? a : b),
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
  final String metric;
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
    required this.metric,
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
      padding:
          const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs + 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: NightshadeTypography.caption
                      .copyWith(color: colors.textSecondary),
                ),
                if (!enabled)
                  Text(
                    'no $metric data',
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            child: NightshadeSlider(
              min: rangeMin,
              max: rangeMax == rangeMin ? rangeMin + 1 : rangeMax,
              value: effectiveValue,
              divisions: span > 0 ? 40 : null,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              value == null ? 'off' : '${value!.toStringAsFixed(2)} $unit',
              style: NightshadeTypography.monoSm.copyWith(
                color: value == null ? colors.textMuted : colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: value == null ? 'Enable rule' : 'Disable rule',
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            onPressed: () {
              if (value == null) {
                onChanged((rangeMin + rangeMax) / 2);
              } else {
                onCleared();
              }
            },
            icon: Icon(
              value == null ? LucideIcons.plus : LucideIcons.minus,
              size: NightshadeTokens.iconXs,
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
  final String metric;
  final int? value;
  final List<int> available;
  final int rangeMin;
  final int rangeMax;
  final ValueChanged<int> onChanged;
  final VoidCallback onCleared;

  const _IntRow({
    required this.colors,
    required this.label,
    required this.metric,
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
      padding:
          const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs + 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: NightshadeTypography.caption
                      .copyWith(color: colors.textSecondary),
                ),
                if (!enabled)
                  Text(
                    'no $metric data',
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            child: NightshadeSlider(
              min: rangeMin.toDouble(),
              max: rangeMax == rangeMin
                  ? (rangeMin + 1).toDouble()
                  : rangeMax.toDouble(),
              value: effective.toDouble(),
              divisions:
                  (rangeMax - rangeMin) > 0 ? (rangeMax - rangeMin) : null,
              onChanged: enabled ? (v) => onChanged(v.round()) : null,
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              value == null ? 'off' : '$value',
              style: NightshadeTypography.monoSm.copyWith(
                color: value == null ? colors.textMuted : colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: value == null ? 'Enable rule' : 'Disable rule',
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            onPressed: () {
              if (value == null) {
                onChanged(((rangeMin + rangeMax) / 2).round());
              } else {
                onCleared();
              }
            },
            icon: Icon(
              value == null ? LucideIcons.plus : LucideIcons.minus,
              size: NightshadeTokens.iconXs,
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
  final String activeRules;

  const _PreviewSummary({
    required this.colors,
    required this.rejected,
    required this.accepted,
    required this.activeRules,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(
                colors: colors,
                label: 'Will reject',
                value: '$rejected',
                tone: rejected == 0 ? colors.textMuted : colors.warning,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              _Chip(
                colors: colors,
                label: 'Will keep',
                value: '$accepted',
                tone: colors.success,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            activeRules,
            style:
                NightshadeTypography.monoXs.copyWith(color: colors.textMuted),
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
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm + 2,
        vertical: NightshadeTokens.spaceXs + 1,
      ),
      decoration: NightshadeDecorations.statusChip(
        tone,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: NightshadeTokens.spaceXs + 2),
          Text(
            value,
            style: NightshadeTypography.withTabular(
              NightshadeTypography.labelStrong.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
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

  const _RejectionList({required this.colors, required this.rejections});

  @override
  Widget build(BuildContext context) {
    if (rejections.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceMd + 2),
        child: Text(
          'No frames currently fail any rule.',
          style: NightshadeTypography.caption.copyWith(color: colors.textMuted),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: NightshadeTokens.borderRadiusLg,
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
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: NightshadeTypography.label
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: NightshadeTokens.spaceXs - 2),
                Text(
                  r.reason,
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
