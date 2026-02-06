import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceAnalyticsTab extends ConsumerWidget {
  const ScienceAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final activeSessionId = _resolveSessionId(ref);

    if (activeSessionId == null) {
      return Center(
        child: Text(
          'No active or recent session available for science analytics.',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }

    final targetObjectId = ref.watch(activePhotometryTargetObjectIdProvider);
    final lightCurve =
        ref.watch(sessionLightCurveProvider((activeSessionId, targetObjectId)));
    final transparency =
        ref.watch(sessionTransparencyTrendProvider(activeSessionId));
    final transparencyRows = ref
            .watch(sessionTransparencySamplesProvider(activeSessionId))
            .valueOrNull ??
        const [];
    final calibrations = ref
            .watch(sessionFrameCalibrationsProvider(activeSessionId))
            .valueOrNull ??
        const [];
    final psfTiles =
        ref.watch(sessionPsfTilesProvider(activeSessionId)).valueOrNull ??
            const [];
    final latestPsfTiles = _latestPsfSnapshot(psfTiles);
    final residuals = ref
            .watch(sessionResidualVectorsProvider(activeSessionId))
            .valueOrNull ??
        const [];
    final latestResiduals = _latestResidualSnapshot(residuals);
    final moving = ref
            .watch(sessionMovingObjectCandidatesProvider(activeSessionId))
            .valueOrNull ??
        const [];
    final lineRatios = ref
            .watch(sessionLineRatioProductsProvider(activeSessionId))
            .valueOrNull ??
        const [];

    final latestCal = calibrations.isEmpty ? null : calibrations.last;
    final latestTransparency = transparency.isEmpty ? null : transparency.last;
    final latestTransparencyRow =
        transparencyRows.isEmpty ? null : transparencyRows.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _KpiCard(
                colors: colors,
                title: 'Calibration',
                value: latestCal == null
                    ? 'N/A'
                    : latestCal.isCalibrated
                        ? 'Calibrated'
                        : 'Uncalibrated',
                subtitle: latestCal?.zeroPoint == null
                    ? 'ZP unavailable'
                    : 'ZP ${latestCal!.zeroPoint!.toStringAsFixed(2)}',
              ),
              _KpiCard(
                colors: colors,
                title: 'Lim Mag (5-sigma)',
                value:
                    latestCal?.limitingMag5Sigma?.toStringAsFixed(2) ?? 'N/A',
                subtitle: latestCal == null
                    ? 'No photometric fit yet'
                    : '${latestCal.matchedStarCount} matched stars',
              ),
              _KpiCard(
                colors: colors,
                title: 'Transparency',
                value: latestTransparency == null
                    ? 'N/A'
                    : '${latestTransparency.transparencyPercent.toStringAsFixed(1)}%',
                subtitle:
                    latestTransparencyRow?.qualityBucket ?? 'No trend yet',
              ),
              _KpiCard(
                colors: colors,
                title: 'Moving Objects',
                value: moving.length.toString(),
                subtitle: moving.isEmpty
                    ? 'No candidates'
                    : 'Top conf ${(moving.first.confidence * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SeriesChartCard(
                  colors: colors,
                  title: 'Differential Photometry',
                  yLabel: 'dMag',
                  points: lightCurve
                      .map((point) => _ChartPoint(
                          point.timestamp, point.differentialMagnitude))
                      .toList(growable: false),
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SeriesChartCard(
                  colors: colors,
                  title: 'Transparency Trend',
                  yLabel: '%',
                  points: transparency
                      .map((point) => _ChartPoint(
                          point.timestamp, point.transparencyPercent))
                      .toList(growable: false),
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PsfHeatmapCard(colors: colors, tiles: latestPsfTiles),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    _ResidualCard(colors: colors, residuals: latestResiduals),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MovingObjectCard(colors: colors, moving: moving),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LineRatioCard(
                  colors: colors,
                  sessionId: activeSessionId,
                  lineRatios: lineRatios,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int? _resolveSessionId(WidgetRef ref) {
    final activeSession = ref.watch(sessionStateProvider).dbSessionId;
    if (activeSession != null) {
      return activeSession;
    }

    final sessions = ref.watch(allSessionsProvider).valueOrNull;
    if (sessions == null || sessions.isEmpty) {
      return null;
    }

    return sessions.first.id;
  }
}

List<PsfFieldTileRow> _latestPsfSnapshot(List<PsfFieldTileRow> rows) {
  if (rows.isEmpty) {
    return const [];
  }
  int? latestId;
  DateTime latestTime = DateTime.fromMillisecondsSinceEpoch(0);
  for (final row in rows) {
    if (row.capturedImageId == null) {
      continue;
    }
    if (row.timestamp.isAfter(latestTime)) {
      latestTime = row.timestamp;
      latestId = row.capturedImageId;
    }
  }
  if (latestId == null) {
    return rows;
  }
  return rows
      .where((row) => row.capturedImageId == latestId)
      .toList(growable: false);
}

List<AstrometryResidualVectorRow> _latestResidualSnapshot(
  List<AstrometryResidualVectorRow> rows,
) {
  if (rows.isEmpty) {
    return const [];
  }
  int? latestId;
  DateTime latestTime = DateTime.fromMillisecondsSinceEpoch(0);
  for (final row in rows) {
    if (row.capturedImageId == null) {
      continue;
    }
    if (row.timestamp.isAfter(latestTime)) {
      latestTime = row.timestamp;
      latestId = row.capturedImageId;
    }
  }
  if (latestId == null) {
    return rows;
  }
  return rows
      .where((row) => row.capturedImageId == latestId)
      .toList(growable: false);
}

class _KpiCard extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String value;
  final String subtitle;

  const _KpiCard({
    required this.colors,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPoint {
  final DateTime time;
  final double value;

  const _ChartPoint(this.time, this.value);
}

class _SeriesChartCard extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String yLabel;
  final List<_ChartPoint> points;
  final Color color;

  const _SeriesChartCard({
    required this.colors,
    required this.title,
    required this.yLabel,
    required this.points,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return NightshadeCard(
        child: SizedBox(
          height: 240,
          child: Center(
            child: Text(
              '$title has no data yet',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        ),
      );
    }

    final sorted = points.toList(growable: false)
      ..sort((a, b) => a.time.compareTo(b.time));
    final start = sorted.first.time;
    final spots = sorted
        .map(
          (point) => FlSpot(
              point.time.difference(start).inSeconds.toDouble(), point.value),
        )
        .toList(growable: false);

    var minY = sorted.first.value;
    var maxY = sorted.first.value;
    for (final point in sorted) {
      if (point.value < minY) {
        minY = point.value;
      }
      if (point.value > maxY) {
        maxY = point.value;
      }
    }

    final yRange = math.max(0.5, maxY - minY);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: spots.last.x == 0 ? 1 : spots.last.x,
                  minY: minY - (yRange * 0.15),
                  maxY: maxY + (yRange * 0.15),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: colors.border),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: true,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.border.withValues(alpha: 0.35)),
                    getDrawingVerticalLine: (_) =>
                        FlLine(color: colors.border.withValues(alpha: 0.25)),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval:
                            math.max(1, (spots.last.x / 4).floorToDouble()),
                        getTitlesWidget: (value, meta) {
                          final mins =
                              Duration(seconds: value.round()).inMinutes;
                          return Text(
                            '${mins}m',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: Text(
                        yLabel,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 10),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: color,
                      barWidth: 2,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PsfHeatmapCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<PsfFieldTileRow> tiles;

  const _PsfHeatmapCard({required this.colors, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PSF Field Map',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (tiles.isEmpty)
              SizedBox(
                height: 170,
                child: Center(
                  child: Text(
                    'No PSF tiles computed yet',
                    style: TextStyle(color: colors.textMuted),
                  ),
                ),
              )
            else
              _PsfHeatmapGrid(colors: colors, tiles: tiles),
          ],
        ),
      ),
    );
  }
}

class _PsfHeatmapGrid extends StatelessWidget {
  final NightshadeColors colors;
  final List<PsfFieldTileRow> tiles;

  const _PsfHeatmapGrid({required this.colors, required this.tiles});

  @override
  Widget build(BuildContext context) {
    var maxRow = 0;
    var maxCol = 0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    final rowCount = maxRow + 1;
    final colCount = maxCol + 1;

    final valid = tiles
        .where((tile) => tile.starCount > 0 && tile.medianFwhm > 0)
        .map((tile) => tile.medianFwhm)
        .toList(growable: false)
      ..sort();
    final low = valid.isEmpty ? 0.0 : _percentile(valid, 0.05);
    final high = valid.isEmpty
        ? 1.0
        : _percentile(valid, 0.95).clamp(low + 1e-6, double.infinity);

    return SizedBox(
      height: 170,
      child: Column(
        children: List.generate(rowCount, (row) {
          return Expanded(
            child: Row(
              children: List.generate(colCount, (col) {
                PsfFieldTileRow? tile;
                for (final candidate in tiles) {
                  if (candidate.tileRow == row && candidate.tileCol == col) {
                    tile = candidate;
                    break;
                  }
                }
                final fwhm = tile?.medianFwhm ?? 0.0;
                final normalized = tile == null || tile.starCount <= 0
                    ? 0.0
                    : ((fwhm - low) / (high - low)).clamp(0.0, 1.0);
                final color = tile == null || tile.starCount <= 0
                    ? const Color(0xFF4A5568)
                    : Color.lerp(
                        const Color(0xFF0B6E4F),
                        const Color(0xFFC0392B),
                        normalized,
                      )!;

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        tile == null ? '-' : fwhm.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  double _percentile(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1.0 - t) + sortedValues[hi] * t;
  }
}

class _ResidualCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<AstrometryResidualVectorRow> residuals;

  const _ResidualCard({required this.colors, required this.residuals});

  @override
  Widget build(BuildContext context) {
    final rms = residuals.isEmpty
        ? 0.0
        : math.sqrt(
            residuals
                    .map((r) => r.magnitudeArcsec * r.magnitudeArcsec)
                    .fold<double>(0.0, (sum, value) => sum + value) /
                residuals.length,
          );

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Astrometric Residuals',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              residuals.isEmpty
                  ? 'No residual vectors available for this session'
                  : 'RMS: ${rms.toStringAsFixed(3)}" across ${residuals.length} samples',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            if (residuals.isNotEmpty)
              Text(
                'Latest recommendation: ${residuals.last.recommendationCode ?? 'none'}',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MovingObjectCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<MovingObjectCandidateRow> moving;

  const _MovingObjectCard({required this.colors, required this.moving});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Moving Object Candidates',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (moving.isEmpty)
              Text(
                'No candidates detected in current session window.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              )
            else
              ...moving.take(6).map(
                    (candidate) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              candidate.objectName ?? candidate.candidateId,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(candidate.confidence * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${candidate.motionArcsecPerMinute.toStringAsFixed(2)}"/min',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _LineRatioCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final int sessionId;
  final List<LineRatioProductRow> lineRatios;

  const _LineRatioCard({
    required this.colors,
    required this.sessionId,
    required this.lineRatios,
  });

  @override
  ConsumerState<_LineRatioCard> createState() => _LineRatioCardState();
}

class _LineRatioCardState extends ConsumerState<_LineRatioCard> {
  bool _isGenerating = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    final narrowbandEnabled = scienceSettings.narrowbandRatiosEnabled;
    final latest = widget.lineRatios.isEmpty ? null : widget.lineRatios.first;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Narrowband Ratios',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: _isGenerating || !narrowbandEnabled
                    ? null
                    : _generateLineRatios,
                label: !narrowbandEnabled
                    ? 'Enable Narrowband Ratios in Settings'
                    : _isGenerating
                        ? 'Generating...'
                        : 'Generate From Session Frames',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
              ),
            ),
            const SizedBox(height: 8),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: widget.colors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            if (!narrowbandEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Feature disabled globally. Turn on Narrowband line ratios in Settings > Science.',
                  style: TextStyle(
                    color: widget.colors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            if (latest == null)
              Text(
                'No line-ratio products generated yet.',
                style: TextStyle(color: widget.colors.textMuted, fontSize: 12),
              )
            else ...[
              _MetricLine(
                colors: widget.colors,
                label: 'SII/Ha',
                value: latest.ratioSiiHa,
              ),
              _MetricLine(
                colors: widget.colors,
                label: 'OIII/Ha',
                value: latest.ratioOiiiHa,
              ),
              _MetricLine(
                colors: widget.colors,
                label: 'SII/OIII',
                value: latest.ratioSiiOiii,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateLineRatios() async {
    final scienceSettings = ref.read(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    if (!scienceSettings.narrowbandRatiosEnabled) {
      setState(() {
        _statusMessage =
            'Narrowband ratios are disabled. Enable them in Settings > Science.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = null;
    });

    try {
      final images = await ref
          .read(imagesDaoProvider)
          .getImagesForSession(widget.sessionId);
      final ha =
          _findLatestByFilter(images, {'ha', 'halpha', 'h-alpha', 'h alpha'});
      final oiii = _findLatestByFilter(images, {'oiii', 'o3'});
      final sii = _findLatestByFilter(images, {'sii', 's2'});

      if (ha == null || oiii == null || sii == null) {
        setState(() {
          _statusMessage =
              'Need latest H-alpha, OIII, and SII frames in this session.';
          _isGenerating = false;
        });
        return;
      }

      await ref.read(scienceProcessingServiceProvider).generateLineRatios(
            sessionId: widget.sessionId,
            set: NarrowbandSet(
              hAlphaPath: ha.filePath,
              oiiiPath: oiii.filePath,
              siiPath: sii.filePath,
            ),
            hAlphaImageId: ha.id,
            oiiiImageId: oiii.id,
            siiImageId: sii.id,
          );

      setState(() {
        _statusMessage =
            'Generated using ${ha.fileName}, ${oiii.fileName}, ${sii.fileName}.';
        _isGenerating = false;
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Line-ratio generation failed: $error';
        _isGenerating = false;
      });
    }
  }

  CapturedImage? _findLatestByFilter(
      List<CapturedImage> images, Set<String> names) {
    final filtered = images.where((image) {
      final filter = (image.filter ?? '').toLowerCase();
      for (final name in names) {
        if (filter.contains(name)) {
          return true;
        }
      }
      return false;
    }).toList();

    if (filtered.isEmpty) {
      return null;
    }

    filtered.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return filtered.first;
  }
}

class _MetricLine extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double value;

  const _MetricLine({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
