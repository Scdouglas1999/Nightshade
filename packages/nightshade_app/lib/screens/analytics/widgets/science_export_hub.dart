import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../services/observation_report_service.dart';
import '../../../utils/snackbar_helper.dart';

/// Dialog listing all exportable science data types with CSV export and filters.
class ScienceExportHub extends ConsumerStatefulWidget {
  const ScienceExportHub({super.key});

  @override
  ConsumerState<ScienceExportHub> createState() => _ScienceExportHubState();
}

class _ScienceExportHubState extends ConsumerState<ScienceExportHub> {
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedSessionId;
  bool _isExporting = false;
  String? _lastExportResult;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sessions = ref.watch(allSessionsProvider).valueOrNull ?? const [];
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Dialog(
      backgroundColor: colors.surface,
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 750),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.database, size: 20, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Science Data Export',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 18, color: colors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Filters
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Session filter
                      Expanded(
                        child: NightshadeDropdown(
                          value: _selectedSessionId == null
                              ? 'All Sessions'
                              : _sessionLabel(sessions, _selectedSessionId!),
                          items: [
                            'All Sessions',
                            ...sessions.map((s) => _sessionLabel(sessions, s.id)),
                          ],
                          onChanged: (value) {
                            setState(() {
                              if (value == 'All Sessions' || value == null) {
                                _selectedSessionId = null;
                              } else {
                                final match = sessions.firstWhere(
                                  (s) => _sessionLabel(sessions, s.id) == value,
                                );
                                _selectedSessionId = match.id;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Date range
                      _DateButton(
                        colors: colors,
                        label: _startDate != null
                            ? dateFormat.format(_startDate!)
                            : 'Start Date',
                        onTap: () => _pickDate(isStart: true),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '-',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ),
                      _DateButton(
                        colors: colors,
                        label: _endDate != null
                            ? dateFormat.format(_endDate!)
                            : 'End Date',
                        onTap: () => _pickDate(isStart: false),
                      ),
                      if (_startDate != null || _endDate != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: colors.textMuted),
                          onPressed: () => setState(() {
                            _startDate = null;
                            _endDate = null;
                          }),
                          tooltip: 'Clear date filter',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Data type list
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Photometry Measurements',
                      description:
                          'Differential photometry: object ID, flux, magnitude, SNR, uncertainty, timestamp',
                      icon: LucideIcons.lineChart,
                      isExporting: _isExporting,
                      onExport: () => _exportData(_ScienceDataType.photometry),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Frame Quality Metrics',
                      description:
                          'Per-frame statistics: SNR, background, noise, clipping, uniformity, gradients',
                      icon: LucideIcons.barChart2,
                      isExporting: _isExporting,
                      onExport: () =>
                          _exportData(_ScienceDataType.frameQuality),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Transparency Samples',
                      description:
                          'Sky transparency %, extinction coefficient, quality bucket per frame',
                      icon: LucideIcons.cloud,
                      isExporting: _isExporting,
                      onExport: () =>
                          _exportData(_ScienceDataType.transparency),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'PSF Field Tiles',
                      description:
                          'Per-tile FWHM, HFR, eccentricity, roundness, star count across field',
                      icon: LucideIcons.grid,
                      isExporting: _isExporting,
                      onExport: () => _exportData(_ScienceDataType.psfTiles),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Astrometric Residuals',
                      description:
                          'Plate solve residual vectors: position, magnitude (arcsec), recommendation',
                      icon: LucideIcons.crosshair,
                      isExporting: _isExporting,
                      onExport: () => _exportData(_ScienceDataType.residuals),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Photometric Calibration',
                      description:
                          'Zero-point, limiting magnitude, matched star count, RMS per frame',
                      icon: LucideIcons.gauge,
                      isExporting: _isExporting,
                      onExport: () =>
                          _exportData(_ScienceDataType.calibration),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      colors: colors,
                      title: 'Moving Object Candidates',
                      description:
                          'Detected movers: RA/Dec, motion rate, confidence, known object matches',
                      icon: LucideIcons.orbit,
                      isExporting: _isExporting,
                      onExport: () =>
                          _exportData(_ScienceDataType.movingObjects),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: colors.border),
                    const SizedBox(height: 12),
                    // Generate Report button
                    SizedBox(
                      width: double.infinity,
                      child: NightshadeButton(
                        label: _isExporting
                            ? 'Generating...'
                            : 'Generate Observation Report (PDF)',
                        icon: LucideIcons.fileText,
                        onPressed: _isExporting ? null : _generateReport,
                        variant: ButtonVariant.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Status bar
            if (_lastExportResult != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Text(
                  _lastExportResult!,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _sessionLabel(List<ImagingSession> sessions, int id) {
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return 'Session $id';
    final name = session.name ?? 'Session $id';
    final date = DateFormat('MMM d').format(session.startTime);
    return '$name ($date)';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          // Set end date to end of day
          _endDate =
              DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Future<void> _exportData(_ScienceDataType dataType) async {
    setState(() {
      _isExporting = true;
      _lastExportResult = null;
    });

    try {
      final sessions = ref.read(allSessionsProvider).valueOrNull ?? const [];

      // Determine which sessions to export
      final List<int> sessionIds;
      if (_selectedSessionId != null) {
        sessionIds = [_selectedSessionId!];
      } else {
        sessionIds = sessions.map((s) => s.id).toList();
      }

      final List<List<dynamic>> rows;
      final String filePrefix;

      switch (dataType) {
        case _ScienceDataType.photometry:
          rows = await _buildPhotometryRows(sessionIds);
          filePrefix = 'photometry';
        case _ScienceDataType.frameQuality:
          rows = await _buildFrameQualityRows(sessionIds);
          filePrefix = 'frame_quality';
        case _ScienceDataType.transparency:
          rows = await _buildTransparencyRows(sessionIds);
          filePrefix = 'transparency';
        case _ScienceDataType.psfTiles:
          rows = await _buildPsfTileRows(sessionIds);
          filePrefix = 'psf_tiles';
        case _ScienceDataType.residuals:
          rows = await _buildResidualRows(sessionIds);
          filePrefix = 'astrometric_residuals';
        case _ScienceDataType.calibration:
          rows = await _buildCalibrationRows(sessionIds);
          filePrefix = 'photometric_calibration';
        case _ScienceDataType.movingObjects:
          rows = await _buildMovingObjectRows(sessionIds);
          filePrefix = 'moving_objects';
      }

      if (rows.length <= 1) {
        // Only header row, no data
        if (mounted) {
          setState(() {
            _isExporting = false;
            _lastExportResult =
                'No data found for the selected filters.';
          });
        }
        return;
      }

      final csv = const ListToCsvConverter().convert(rows);
      final directory = await _getExportDirectory();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = '${filePrefix}_$timestamp.csv';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      await file.writeAsString(csv);

      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportResult = 'Exported ${rows.length - 1} rows to $filePath';
        });
        context.showSuccessSnackBar('Exported to: $filePath');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportResult = 'Export failed: $e';
        });
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _generateReport() async {
    // Need a specific session for the report
    if (_selectedSessionId == null) {
      final sessions = ref.read(allSessionsProvider).valueOrNull ?? const [];
      if (sessions.isEmpty) {
        if (mounted) {
          context.showWarningSnackBar(
              'No sessions available. Select a session to generate a report.');
        }
        return;
      }
      // Use the most recent session if none selected
      _selectedSessionId = sessions.first.id;
    }

    setState(() {
      _isExporting = true;
      _lastExportResult = null;
    });

    try {
      late final String filePath;
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final bytes = await backend.generateObservationReport(_selectedSessionId!);
        final directory = await _getExportDirectory();
        final timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
        filePath =
            path.join(directory.path, 'observation_report_$timestamp.pdf');
        await File(filePath).writeAsBytes(bytes, flush: true);
      } else {
        final reportService = ObservationReportService(
          sessionsDao: ref.read(sessionsDaoProvider),
          imagesDao: ref.read(imagesDaoProvider),
          scienceDao: ref.read(scienceDaoProvider),
        );
        filePath = await reportService.generateReport(
          sessionId: _selectedSessionId!,
        );
      }

      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportResult = 'Report generated: $filePath';
        });
        context.showSuccessSnackBar('Report saved to: $filePath');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportResult = 'Report generation failed: $e';
        });
        context.showErrorSnackBar('Report generation failed: $e');
      }
    }
  }

  // =========================================================================
  // CSV row builders
  // =========================================================================

  bool _withinDateRange(DateTime timestamp) {
    if (_startDate != null && timestamp.isBefore(_startDate!)) return false;
    if (_endDate != null && timestamp.isAfter(_endDate!)) return false;
    return true;
  }

  Future<List<List<dynamic>>> _buildPhotometryRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Object ID',
        'Role',
        'X',
        'Y',
        'Flux',
        'Differential Magnitude',
        'SNR',
        'Uncertainty',
        'Is Outlier',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data = await ref.read(sessionPhotometryProvider(sessionId).future);
      for (final m in data) {
        if (!_withinDateRange(m.timestamp)) continue;
        rows.add([
          m.sessionId ?? '',
          m.capturedImageId ?? '',
          m.objectId,
          m.role,
          m.x,
          m.y,
          m.flux,
          m.differentialMagnitude ?? '',
          m.snr ?? '',
          m.uncertainty ?? '',
          m.isOutlier,
          m.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildFrameQualityRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Timestamp',
        'Median',
        'Mean',
        'StdDev',
        'MAD',
        'Background',
        'Noise',
        'SNR',
        'Dynamic Range (P1-P99)',
        'Low Clip %',
        'High Clip %',
        'Uniformity CV',
        'Gradient X',
        'Gradient Y',
        'Processing Tier',
        'Processing Ms',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data =
          await ref.read(sessionFrameQualityMetricsProvider(sessionId).future);
      for (final m in data) {
        if (!_withinDateRange(m.timestamp)) continue;
        rows.add([
          m.sessionId ?? '',
          m.capturedImageId ?? '',
          m.timestamp.toIso8601String(),
          m.median,
          m.mean,
          m.stdDev,
          m.mad,
          m.background,
          m.noise,
          m.snr,
          m.dynamicRangeP1P99,
          m.lowClipPercent,
          m.highClipPercent,
          m.uniformityCv,
          m.gradientX,
          m.gradientY,
          m.processingTier,
          m.processingMs,
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildTransparencyRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Transparency %',
        'Extinction Coefficient',
        'Quality Bucket',
        'Confidence',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data =
          await ref.read(sessionTransparencySamplesProvider(sessionId).future);
      for (final s in data) {
        if (!_withinDateRange(s.timestamp)) continue;
        rows.add([
          s.sessionId ?? '',
          s.capturedImageId ?? '',
          s.transparencyPercent,
          s.extinctionCoefficient,
          s.qualityBucket,
          s.confidence,
          s.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildPsfTileRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Tile Row',
        'Tile Col',
        'Star Count',
        'Median FWHM',
        'Median HFR',
        'Median Eccentricity',
        'Roundness',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data = await ref.read(sessionPsfTilesProvider(sessionId).future);
      for (final t in data) {
        if (!_withinDateRange(t.timestamp)) continue;
        rows.add([
          t.sessionId ?? '',
          t.capturedImageId ?? '',
          t.tileRow,
          t.tileCol,
          t.starCount,
          t.medianFwhm,
          t.medianHfr,
          t.medianEccentricity,
          t.roundness,
          t.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildResidualRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'X',
        'Y',
        'dX (arcsec)',
        'dY (arcsec)',
        'Magnitude (arcsec)',
        'Recommendation',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data =
          await ref.read(sessionResidualVectorsProvider(sessionId).future);
      for (final r in data) {
        if (!_withinDateRange(r.timestamp)) continue;
        rows.add([
          r.sessionId ?? '',
          r.capturedImageId ?? '',
          r.x,
          r.y,
          r.dxArcsec,
          r.dyArcsec,
          r.magnitudeArcsec,
          r.recommendationCode ?? '',
          r.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildCalibrationRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Is Calibrated',
        'Zero Point',
        'Lim Mag 3-sigma',
        'Lim Mag 5-sigma',
        'Matched Stars',
        'Calibration RMS',
        'Catalog Source',
        'Solver ID',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data =
          await ref.read(sessionFrameCalibrationsProvider(sessionId).future);
      for (final c in data) {
        if (!_withinDateRange(c.timestamp)) continue;
        rows.add([
          c.sessionId ?? '',
          c.capturedImageId ?? '',
          c.isCalibrated,
          c.zeroPoint ?? '',
          c.limitingMag3Sigma ?? '',
          c.limitingMag5Sigma ?? '',
          c.matchedStarCount,
          c.calibrationRms,
          c.catalogSource,
          c.solverId,
          c.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<List<List<dynamic>>> _buildMovingObjectRows(
      List<int> sessionIds) async {
    final rows = <List<dynamic>>[
      [
        'Session ID',
        'Image ID',
        'Candidate ID',
        'RA (deg)',
        'Dec (deg)',
        'Motion (arcsec/min)',
        'Position Angle (deg)',
        'Confidence',
        'Is Known Object',
        'Object Name',
        'Source',
        'Timestamp',
      ]
    ];

    for (final sessionId in sessionIds) {
      final data = await ref
          .read(sessionMovingObjectCandidatesProvider(sessionId).future);
      for (final m in data) {
        if (!_withinDateRange(m.timestamp)) continue;
        rows.add([
          m.sessionId ?? '',
          m.capturedImageId ?? '',
          m.candidateId,
          m.raDegrees,
          m.decDegrees,
          m.motionArcsecPerMinute,
          m.positionAngleDegrees,
          m.confidence,
          m.isKnownObject,
          m.objectName ?? '',
          m.source,
          m.timestamp.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  Future<Directory> _getExportDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir =
        Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }
}

enum _ScienceDataType {
  photometry,
  frameQuality,
  transparency,
  psfTiles,
  residuals,
  calibration,
  movingObjects,
}

class _ExportTypeCard extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String description;
  final IconData icon;
  final bool isExporting;
  final VoidCallback onExport;

  const _ExportTypeCard({
    required this.colors,
    required this.title,
    required this.description,
    required this.icon,
    required this.isExporting,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            label: 'CSV',
            icon: LucideIcons.download,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: isExporting ? null : onExport,
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final VoidCallback onTap;

  const _DateButton({
    required this.colors,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendar, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
