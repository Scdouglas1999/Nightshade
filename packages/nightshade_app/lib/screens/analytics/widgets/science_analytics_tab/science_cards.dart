part of '../science_analytics_tab.dart';

class _AavsoExportButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final int sessionId;

  const _AavsoExportButton({
    required this.colors,
    required this.sessionId,
  });

  @override
  ConsumerState<_AavsoExportButton> createState() => _AavsoExportButtonState();
}

class _AavsoExportButtonState extends ConsumerState<_AavsoExportButton> {
  bool _exporting = false;

  Future<void> _doExport() async {
    final targetName = await _showTargetNameDialog();
    if (targetName == null || targetName.trim().isEmpty) {
      return;
    }

    setState(() => _exporting = true);
    try {
      final backend = ref.read(backendProvider);
      late final String filePath;
      if (backend is NetworkBackend) {
        final bytes = await backend.exportSessionAavso(
          widget.sessionId,
          targetStarName: targetName.trim(),
        );
        final docsDir = await getApplicationDocumentsDirectory();
        final exportDir =
            Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        filePath = path.join(
          exportDir.path,
          'AAVSO_${targetName.trim().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.txt',
        );
        await File(filePath).writeAsBytes(bytes, flush: true);
      } else {
        final scienceDao = ref.read(scienceDaoProvider);
        final settingsDao = ref.read(settingsDaoProvider);
        final imagesDao = ref.read(imagesDaoProvider);

        final service = AavsoExportService(
          scienceDao: scienceDao,
          settingsDao: settingsDao,
          imagesDao: imagesDao,
        );

        filePath = await service.exportSession(
          sessionId: widget.sessionId,
          targetStarName: targetName.trim(),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AAVSO export saved to: $filePath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } on AavsoExportError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: widget.colors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: widget.colors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<String?> _showTargetNameDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Export to AAVSO'),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              ctx,
              designMaxWidth: 480,
              designMaxHeight: 320,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the AAVSO star designation for this target '
                  '(e.g., "SS CYG", "R LEO"):',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Star name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) => Navigator.of(ctx).pop(value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Export'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: NightshadeButton(
        onPressed: _doExport,
        icon: LucideIcons.fileOutput,
        label: _exporting ? 'Exporting...' : 'Export to AAVSO',
        variant: ButtonVariant.outline,
        isLoading: _exporting,
      ),
    );
  }
}

class _LightCurveChartCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<LightCurvePoint> lightCurve;
  final Widget? hubExportButton;

  const _LightCurveChartCard({
    required this.colors,
    required this.lightCurve,
    this.hubExportButton,
  });

  @override
  Widget build(BuildContext context) {
    if (lightCurve.isEmpty) {
      return NightshadeCard(
        child: AdaptiveChartContainer.fixed(
          height: 240,
          child: Center(
            child: Text(
              'Differential Photometry has no data yet',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        ),
      );
    }

    final sorted = lightCurve.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final start = sorted.first.timestamp;
    // Negate values for inverted Y-axis (brighter = up = more negative mag).
    final spots = sorted
        .map(
          (point) => FlSpot(
            point.timestamp.difference(start).inSeconds.toDouble(),
            -point.differentialMagnitude,
          ),
        )
        .toList(growable: false);

    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    // Extend range to include error bar extents so they aren't clipped.
    for (final point in sorted) {
      if (point.uncertainty <= 0) continue;
      final yLow = -(point.differentialMagnitude - point.uncertainty);
      final yHigh = -(point.differentialMagnitude + point.uncertainty);
      if (yLow < minY) minY = yLow;
      if (yLow > maxY) maxY = yLow;
      if (yHigh < minY) minY = yHigh;
      if (yHigh > maxY) maxY = yHigh;
    }
    final yRange = math.max(0.5, maxY - minY);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Differential Photometry',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (hubExportButton != null) hubExportButton!,
                const _ScienceInfoButton(title: 'Differential Photometry'),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveChartContainer(
              preferredHeight: 190,
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
                              fontSize: NightshadeTypography.fontSize10,
                              color: colors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: Text(
                        'dMag',
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize10),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          (-value).toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    // Main data line with dot markers.
                    LineChartBarData(
                      spots: spots,
                      color: colors.primary,
                      barWidth: 2,
                      isCurved: false,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                          radius: 2.2,
                          color: colors.primary,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Error bars: each is a vertical line segment in chart
                    // coordinates (2 spots per bar), so alignment with data
                    // points is exact regardless of axis padding or layout.
                    for (final point in sorted)
                      if (point.uncertainty > 0)
                        LineChartBarData(
                          spots: [
                            FlSpot(
                              point.timestamp
                                  .difference(start)
                                  .inSeconds
                                  .toDouble(),
                              -(point.differentialMagnitude -
                                  point.uncertainty),
                            ),
                            FlSpot(
                              point.timestamp
                                  .difference(start)
                                  .inSeconds
                                  .toDouble(),
                              -(point.differentialMagnitude +
                                  point.uncertainty),
                            ),
                          ],
                          color: colors.primary.withValues(alpha: 0.4),
                          barWidth: 1.0,
                          isCurved: false,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(
                              radius: 1.5,
                              color: colors.primary.withValues(alpha: 0.4),
                              strokeWidth: 0,
                            ),
                          ),
                          belowBarData: BarAreaData(show: false),
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
  final Widget? hubExportButton;

  const _PsfHeatmapCard({
    required this.colors,
    required this.tiles,
    this.hubExportButton,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PSF Field Map',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (hubExportButton != null) hubExportButton!,
                const _ScienceInfoButton(title: 'PSF Field Map'),
              ],
            ),
            const SizedBox(height: 10),
            if (tiles.isEmpty)
              AdaptiveChartContainer.fixed(
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

    return AdaptiveChartContainer(
      preferredHeight: 170,
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
                final labelColor = color.computeLuminance() > 0.45
                    ? const Color(0xFF000000)
                    : const Color(0xFFFFFFFF);

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.85),
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline4),
                    ),
                    child: Center(
                      child: Text(
                        tile == null ? '-' : fwhm.toStringAsFixed(2),
                        style: TextStyle(
                          color: labelColor,
                          fontSize: NightshadeTypography.fontSize10,
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
  final Widget? hubExportButton;

  const _ResidualCard({
    required this.colors,
    required this.residuals,
    this.hubExportButton,
  });

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Astrometric Residuals',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (hubExportButton != null) hubExportButton!,
                const _ScienceInfoButton(title: 'Astrometric Residuals'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              residuals.isEmpty
                  ? 'No residual vectors available for this session'
                  : 'RMS: ${rms.toStringAsFixed(3)}" across ${residuals.length} samples',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
            const SizedBox(height: 8),
            if (residuals.isNotEmpty)
              Text(
                'Latest recommendation: ${residuals.last.recommendationCode ?? 'none'}',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: NightshadeTypography.fontSize11,
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
  final Widget? hubExportButton;

  const _MovingObjectCard({
    required this.colors,
    required this.moving,
    this.hubExportButton,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Moving Object Candidates',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (hubExportButton != null) hubExportButton!,
                const _ScienceInfoButton(title: 'Moving Object Candidates'),
              ],
            ),
            const SizedBox(height: 8),
            if (moving.isEmpty)
              Text(
                'No candidates detected in current session window.',
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12),
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
                              style: NightshadeTypography.labelSm.copyWith(
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(candidate.confidence * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: NightshadeTypography.fontSize11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${candidate.motionArcsecPerMinute.toStringAsFixed(2)}"/min',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize11,
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
  final int? sessionId;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Narrowband Ratios',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ),
                const _ScienceInfoButton(title: 'Narrowband Ratios'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: _isGenerating ||
                        !narrowbandEnabled ||
                        widget.sessionId == null
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
                    fontSize: NightshadeTypography.fontSize11,
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
                    fontSize: NightshadeTypography.fontSize11,
                  ),
                ),
              ),
            if (latest == null)
              Text(
                'No line-ratio products generated yet.',
                style: TextStyle(
                    color: widget.colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12),
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
    final sessionId = widget.sessionId;
    if (sessionId == null) return;

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
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final result = await backend.generateSessionLineRatios(sessionId);
        ref.invalidate(sessionLineRatioProductsProvider(sessionId));
        setState(() {
          final files = (result['files'] as List?)?.join(', ') ?? 'host frames';
          _statusMessage = 'Generated using $files.';
          _isGenerating = false;
        });
        return;
      }

      final images =
          await ref.read(imagesDaoProvider).getImagesForSession(sessionId);
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
            sessionId: sessionId,
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

  DbCapturedImage? _findLatestByFilter(
      List<DbCapturedImage> images, Set<String> names) {
    final filtered = images.where((image) {
      final filter = (image.filter ?? '').toLowerCase().trim();
      for (final name in names) {
        // Match on exact filter name or as a whole-word within the filter
        // string.  Prevents false positives like "Shah" matching "ha".
        if (filter == name) return true;
        final pattern =
            RegExp('(?:^|[\\s_-])${RegExp.escape(name)}(?:[\\s_-]|\$)');
        if (pattern.hasMatch(filter)) return true;
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
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
          Text(
            value.toStringAsFixed(3),
            style: NightshadeTypography.h6.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
