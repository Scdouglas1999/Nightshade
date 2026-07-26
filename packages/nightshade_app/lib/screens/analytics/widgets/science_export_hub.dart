import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../services/observation_report_service.dart';
import '../../../utils/authority_bound_dialog.dart';
import '../../../utils/exported_file_reveal.dart';
import '../../../utils/snackbar_helper.dart';
import 'mpc_export_panel.dart';
import 'transient_report_panel.dart';

part 'science_export_hub/export_controls.dart';

/// Identifier for a science dataset that the hub can export. Exposed so that
/// per-card export buttons in the science analytics tab can route into the
/// hub with the relevant card pre-highlighted (audit §4.14 consolidation).
enum ScienceExportDataset {
  photometry,
  frameQuality,
  transparency,
  psfTiles,
  residuals,
  calibration,
  movingObjects,
  mpcReport,
  transientReport,
}

/// Resolves and creates the shared science-export directory. Keeping the
/// platform lookup behind a provider lets export workflows be tested without
/// depending on path_provider plugin initialization and avoids repeating the
/// directory setup for every row type in one hub session.
final scienceExportDirectoryProvider = FutureProvider<Directory>((ref) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
  if (!await exportDir.exists()) {
    await exportDir.create(recursive: true);
  }
  return exportDir;
});

typedef ScienceExportFileWriter = Future<void> Function(
  File file,
  String contents,
);

final scienceExportFileWriterProvider = Provider<ScienceExportFileWriter>(
  (ref) => (file, contents) async {
    await file.writeAsString(contents);
  },
);

/// Dialog listing all exportable science data types with CSV export and filters.
class ScienceExportHub extends ConsumerStatefulWidget {
  /// When set, the dialog scrolls to and visually highlights the matching
  /// dataset row so that opening the hub from a card's export button feels
  /// like a continuation of the user's intent, not a context switch.
  final ScienceExportDataset? initialDataset;

  /// Optional moving-object candidates list used by the MPC report row.
  /// The science analytics tab passes the in-memory snapshot it is already
  /// rendering, so the hub does not need to re-query the database.
  final List<MovingObjectCandidateRow> mpcCandidates;

  /// Optional First Light transient detections used by the transient-report row
  /// (AAVSO / MPC / TNS discovery export). Defaults to the global detection
  /// snapshot watched inside the hub when not supplied.
  final List<TransientDetectionRow> transientDetections;

  const ScienceExportHub({
    super.key,
    this.initialDataset,
    this.mpcCandidates = const [],
    this.transientDetections = const [],
  });

  @override
  ConsumerState<ScienceExportHub> createState() => _ScienceExportHubState();
}

class _ScienceExportHubState extends ConsumerState<ScienceExportHub> {
  static const _allDataFilter = 'All Sessions & Standalone';
  static const _standaloneFilter = 'Standalone Captures';

  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedSessionId;
  bool _standaloneOnly = false;
  bool _isExporting = false;
  String? _lastExportResult;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _authorityGeneration = 0;

  // Keys per dataset row so we can scroll a deep-linked row into view and
  // pulse a highlight ring around it on first frame.
  final Map<ScienceExportDataset, GlobalKey> _rowKeys = {
    for (final d in ScienceExportDataset.values) d: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _authorityGeneration++;
        setState(() {
          _isExporting = false;
          _lastExportResult = null;
          _selectedSessionId = null;
          _standaloneOnly = false;
        });
        closeAuthorityBoundDialog(context);
      },
    );
    final initial = widget.initialDataset;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _rowKeys[initial]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  bool _isCurrentAuthority(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _authorityGeneration &&
      identical(ref.read(backendProvider), backend);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final sessionsAsync = ref.watch(allSessionsProvider);
    final sessions = sessionsAsync.valueOrNull ?? const [];
    final sessionsReady = sessionsAsync.hasValue &&
        !sessionsAsync.isLoading &&
        !sessionsAsync.hasError;
    final dateFormat = DateFormat('yyyy-MM-dd');

    // First Light transient detections: prefer the caller's snapshot, else the
    // global newest-first feed.
    final AsyncValue<List<TransientDetectionRow>> transientDetectionsAsync =
        widget.transientDetections.isNotEmpty
            ? AsyncValue.data(widget.transientDetections)
            : ref.watch(allTransientDetectionsProvider);
    final transientDetections =
        transientDetectionsAsync.valueOrNull ?? const <TransientDetectionRow>[];
    final transientDetectionsReady = transientDetectionsAsync.hasValue &&
        !transientDetectionsAsync.isLoading &&
        !transientDetectionsAsync.hasError;

    return Dialog(
      backgroundColor: colors.surface,
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 700,
          designMaxHeight: 750,
        ),
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
                      style: NightshadeTypography.h4.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(LucideIcons.x, size: 18, color: colors.textMuted),
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
                    style: NightshadeTypography.h6.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sessionFilter = _buildSessionFilter(
                        colors,
                        sessionsAsync,
                        sessions,
                      );
                      final dates = _buildDateFilters(colors, dateFormat);
                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sessionFilter,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: dates,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: sessionFilter),
                          const SizedBox(width: 12),
                          dates,
                        ],
                      );
                    },
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
                      key: _rowKeys[ScienceExportDataset.photometry],
                      colors: colors,
                      title: 'Photometry Measurements',
                      description:
                          'Differential photometry: object ID, flux, magnitude, SNR, uncertainty, timestamp',
                      icon: LucideIcons.lineChart,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.photometry,
                      onExport: () =>
                          _exportData(ScienceExportDataset.photometry),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.frameQuality],
                      colors: colors,
                      title: 'Frame Quality Metrics',
                      description:
                          'Per-frame statistics: SNR, background, noise, clipping, uniformity, gradients',
                      icon: LucideIcons.barChart2,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.frameQuality,
                      onExport: () =>
                          _exportData(ScienceExportDataset.frameQuality),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.transparency],
                      colors: colors,
                      title: 'Transparency Samples',
                      description:
                          'Sky transparency %, extinction coefficient, quality bucket per frame',
                      icon: LucideIcons.cloud,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.transparency,
                      onExport: () =>
                          _exportData(ScienceExportDataset.transparency),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.psfTiles],
                      colors: colors,
                      title: 'PSF Field Tiles',
                      description:
                          'Per-tile FWHM, HFR, eccentricity, roundness, star count across field',
                      icon: LucideIcons.grid,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.psfTiles,
                      onExport: () =>
                          _exportData(ScienceExportDataset.psfTiles),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.residuals],
                      colors: colors,
                      title: 'Astrometric Residuals',
                      description:
                          'Plate solve residual vectors: position, magnitude (arcsec), recommendation',
                      icon: LucideIcons.crosshair,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.residuals,
                      onExport: () =>
                          _exportData(ScienceExportDataset.residuals),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.calibration],
                      colors: colors,
                      title: 'Photometric Calibration',
                      description:
                          'Zero-point, limiting magnitude, matched star count, RMS per frame',
                      icon: LucideIcons.gauge,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.calibration,
                      onExport: () =>
                          _exportData(ScienceExportDataset.calibration),
                    ),
                    const SizedBox(height: 8),
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.movingObjects],
                      colors: colors,
                      title: 'Moving Object Candidates',
                      description:
                          'Detected movers: RA/Dec, motion rate, confidence, known object matches',
                      icon: LucideIcons.orbit,
                      isExporting: _isExporting,
                      enabled: sessionsReady,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.movingObjects,
                      onExport: () =>
                          _exportData(ScienceExportDataset.movingObjects),
                    ),
                    const SizedBox(height: 8),
                    // MPC astrometry uses a separate selection UI (per-observation
                    // checkbox list + 80-column format), so the hub launches that
                    // panel as a sub-dialog rather than producing CSV inline.
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.mpcReport],
                      colors: colors,
                      title: 'MPC Astrometry Report',
                      description: widget.mpcCandidates.isEmpty
                          ? 'No moving object candidates available to report yet.'
                          : 'Submit selected moving-object detections in MPC 80-column format',
                      icon: LucideIcons.send,
                      isExporting: _isExporting,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.mpcReport,
                      enabled: widget.mpcCandidates.isNotEmpty,
                      actionLabel: 'Open',
                      actionIcon: LucideIcons.externalLink,
                      onExport: _openMpcPanel,
                    ),
                    const SizedBox(height: 8),
                    // First Light transient discovery report (AAVSO / MPC / TNS).
                    _ExportTypeCard(
                      key: _rowKeys[ScienceExportDataset.transientReport],
                      colors: colors,
                      title: 'Transient Discovery Report',
                      description: transientDetections.isEmpty
                          ? transientDetectionsAsync.isLoading
                              ? 'Loading First Light transient detections...'
                              : transientDetectionsAsync.hasError
                                  ? 'Could not load First Light detections: '
                                      '${transientDetectionsAsync.error}'
                                  : 'No First Light transient detections available yet.'
                          : 'Submit a confirmed difference-image detection to '
                              'AAVSO, the MPC, or the TNS',
                      icon: LucideIcons.sparkles,
                      isExporting: _isExporting,
                      highlight: widget.initialDataset ==
                          ScienceExportDataset.transientReport,
                      enabled: transientDetectionsAsync.hasError ||
                          (transientDetectionsReady &&
                              transientDetections.isNotEmpty),
                      actionLabel:
                          transientDetectionsAsync.hasError ? 'Retry' : 'Open',
                      actionIcon: transientDetectionsAsync.hasError
                          ? LucideIcons.refreshCw
                          : LucideIcons.externalLink,
                      onExport: transientDetectionsAsync.hasError
                          ? () => ref.invalidate(allTransientDetectionsProvider)
                          : () => _openTransientPanel(transientDetections),
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
                            : _standaloneOnly
                                ? 'Select a Session to Generate a PDF Report'
                                : 'Generate Observation Report (PDF)',
                        icon: LucideIcons.fileText,
                        onPressed: _isExporting ||
                                !sessionsReady ||
                                sessions.isEmpty ||
                                _standaloneOnly
                            ? null
                            : _generateReport,
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
                    fontSize: NightshadeTypography.fontSize11,
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

  Widget _buildDateFilters(
    NightshadeColors colors,
    DateFormat dateFormat,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DateButton(
          colors: colors,
          label: _startDate != null
              ? dateFormat.format(_startDate!)
              : 'Start Date',
          onTap: () => _pickDate(isStart: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('-', style: TextStyle(color: colors.textMuted)),
        ),
        _DateButton(
          colors: colors,
          label: _endDate != null ? dateFormat.format(_endDate!) : 'End Date',
          onTap: () => _pickDate(isStart: false),
        ),
        if (_startDate != null || _endDate != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
            onPressed: () => setState(() {
              _startDate = null;
              _endDate = null;
            }),
            tooltip: 'Clear date filter',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ],
    );
  }

  Widget _buildSessionFilter(
    NightshadeColors colors,
    AsyncValue<List<ImagingSession>> sessionsAsync,
    List<ImagingSession> sessions,
  ) {
    if (sessionsAsync.isLoading || !sessionsAsync.hasValue) {
      if (!sessionsAsync.hasError) {
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Loading sessions...',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12,
                ),
              ),
            ],
          ),
        );
      }
    }

    if (sessionsAsync.hasError) {
      return Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
          border: Border.all(color: colors.error.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Could not load sessions: ${sessionsAsync.error}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.error,
                  fontSize: NightshadeTypography.fontSize11,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(allSessionsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final selectedSession = sessions
        .where((session) => session.id == _selectedSessionId)
        .firstOrNull;
    final value = _standaloneOnly
        ? _standaloneFilter
        : selectedSession == null
            ? _allDataFilter
            : _sessionLabel(sessions, selectedSession.id);
    return NightshadeDropdown(
      value: value,
      isExpanded: true,
      items: [
        _allDataFilter,
        _standaloneFilter,
        ...sessions.map((session) => _sessionLabel(sessions, session.id)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          if (value == _allDataFilter) {
            _selectedSessionId = null;
            _standaloneOnly = false;
          } else if (value == _standaloneFilter) {
            _selectedSessionId = null;
            _standaloneOnly = true;
          } else {
            final match = sessions.firstWhere(
              (session) => _sessionLabel(sessions, session.id) == value,
            );
            _selectedSessionId = match.id;
            _standaloneOnly = false;
          }
        });
      },
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

  Future<void> _openMpcPanel() async {
    if (widget.mpcCandidates.isEmpty) {
      context.showInfoSnackBar(
        'No moving object candidates available to report yet.',
      );
      return;
    }
    final colors = NightshadeColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: colors.surface,
          child: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 720,
              designMaxHeight: 720,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MpcExportPanel(
                colors: colors,
                candidates: widget.mpcCandidates,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openTransientPanel(
    List<TransientDetectionRow> detections,
  ) async {
    if (detections.isEmpty) {
      context.showInfoSnackBar(
        'No First Light transient detections available yet.',
      );
      return;
    }
    final colors = NightshadeColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: colors.surface,
          child: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 720,
              designMaxHeight: 720,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TransientReportPanel(
                colors: colors,
                detections: detections,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportData(ScienceExportDataset dataType) async {
    final backend = ref.read(backendProvider);
    final generation = ++_authorityGeneration;
    setState(() {
      _isExporting = true;
      _lastExportResult = null;
    });

    try {
      final sessions = await ref.read(allSessionsProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return;
      final selectedSession = sessions
          .where((session) => session.id == _selectedSessionId)
          .firstOrNull;
      final includeStandalone = _standaloneOnly || selectedSession == null;

      // "All" includes standalone quick captures as well as saved sessions.
      // A specific session excludes standalone data, while the explicit
      // standalone filter excludes every saved session.
      final List<int> sessionIds;
      if (_standaloneOnly) {
        sessionIds = const [];
      } else if (selectedSession != null) {
        sessionIds = [selectedSession.id];
      } else {
        sessionIds = sessions.map((s) => s.id).toList();
      }

      final List<List<dynamic>> rows;
      final String filePrefix;

      switch (dataType) {
        case ScienceExportDataset.photometry:
          rows = await _buildPhotometryRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'photometry';
        case ScienceExportDataset.frameQuality:
          rows = await _buildFrameQualityRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'frame_quality';
        case ScienceExportDataset.transparency:
          rows = await _buildTransparencyRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'transparency';
        case ScienceExportDataset.psfTiles:
          rows = await _buildPsfTileRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'psf_tiles';
        case ScienceExportDataset.residuals:
          rows = await _buildResidualRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'astrometric_residuals';
        case ScienceExportDataset.calibration:
          rows = await _buildCalibrationRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'photometric_calibration';
        case ScienceExportDataset.movingObjects:
          rows = await _buildMovingObjectRows(
            sessionIds,
            includeStandalone: includeStandalone,
          );
          filePrefix = 'moving_objects';
        case ScienceExportDataset.mpcReport:
          // MPC report has its own dialog/flow; should not land here, but
          // surfacing an error keeps the contract honest if a future caller
          // routes a "Download CSV" intent to the wrong dataset.
          throw StateError(
              'MPC report uses the dedicated panel, not CSV export.');
        case ScienceExportDataset.transientReport:
          // Transient discovery reports use the dedicated panel (per-network
          // format), not inline CSV export.
          throw StateError(
              'Transient report uses the dedicated panel, not CSV export.');
      }

      if (!_isCurrentAuthority(backend, generation)) return;

      if (rows.length <= 1) {
        // Only header row, no data
        if (mounted) {
          setState(() {
            _isExporting = false;
            _lastExportResult = 'No data found for the selected filters.';
          });
        }
        return;
      }

      final csv = const ListToCsvConverter().convert(rows);
      final directory = await ref.read(scienceExportDirectoryProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return;
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = '${filePrefix}_$timestamp.csv';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      await ref.read(scienceExportFileWriterProvider)(file, csv);

      if (!_isCurrentAuthority(backend, generation) || !mounted) return;
      setState(() {
        _isExporting = false;
        _lastExportResult = 'Exported ${rows.length - 1} rows to $filePath';
      });
      // On mobile the export lives in the app sandbox; share it so it's
      // actually retrievable instead of naming an unreachable path.
      await revealExportedFile(
        context,
        filePath,
        subject: 'Nightshade science export',
      );
    } catch (e) {
      if (!_isCurrentAuthority(backend, generation) || !mounted) return;
      setState(() {
        _isExporting = false;
        _lastExportResult = 'Export failed: $e';
      });
      context.showErrorSnackBar('Export failed: $e');
    }
  }

  Future<void> _generateReport() async {
    final backend = ref.read(backendProvider);
    final generation = ++_authorityGeneration;
    setState(() {
      _isExporting = true;
      _lastExportResult = null;
    });

    try {
      final sessions = await ref.read(allSessionsProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return;
      final selectedSession = sessions
          .where((session) => session.id == _selectedSessionId)
          .firstOrNull;
      final reportSessionId = selectedSession?.id ?? sessions.firstOrNull?.id;
      if (_standaloneOnly || reportSessionId == null) {
        setState(() {
          _isExporting = false;
          _lastExportResult = _standaloneOnly
              ? 'Observation reports require a saved imaging session.'
              : 'No saved sessions are available for a report.';
        });
        if (!mounted) return;
        context.showWarningSnackBar(_lastExportResult!);
        return;
      }
      if (_selectedSessionId != reportSessionId) {
        setState(() => _selectedSessionId = reportSessionId);
      }

      late final String filePath;
      if (backend is NetworkBackend) {
        final bytes = await backend.generateObservationReport(reportSessionId);
        if (!_isCurrentAuthority(backend, generation)) return;
        final directory = await ref.read(scienceExportDirectoryProvider.future);
        if (!_isCurrentAuthority(backend, generation)) return;
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
          sessionId: reportSessionId,
        );
      }

      if (!_isCurrentAuthority(backend, generation) || !mounted) return;
      setState(() {
        _isExporting = false;
        _lastExportResult = 'Report generated: $filePath';
      });
      await revealExportedFile(
        context,
        filePath,
        subject: 'Nightshade observation report',
      );
    } catch (e) {
      if (!_isCurrentAuthority(backend, generation) || !mounted) return;
      setState(() {
        _isExporting = false;
        _lastExportResult = 'Report generation failed: $e';
      });
      context.showErrorSnackBar('Report generation failed: $e');
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<PhotometryMeasurementRow>>[];
    if (includeStandalone) {
      datasets.add(await ref.read(sessionlessPhotometryProvider.future));
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionPhotometryProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<ScienceFrameQualityMetricsRow>>[];
    if (includeStandalone) {
      datasets.add(
        await ref.read(sessionlessFrameQualityMetricsProvider.future),
      );
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionFrameQualityMetricsProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<TransparencySampleRow>>[];
    if (includeStandalone) {
      datasets.add(
        await ref.read(sessionlessTransparencySamplesProvider.future),
      );
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionTransparencySamplesProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<PsfFieldTileRow>>[];
    if (includeStandalone) {
      datasets.add(await ref.read(sessionlessPsfTilesProvider.future));
    }
    for (final sessionId in sessionIds) {
      datasets.add(await ref.read(sessionPsfTilesProvider(sessionId).future));
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<AstrometryResidualVectorRow>>[];
    if (includeStandalone) {
      datasets.add(await ref.read(sessionlessResidualVectorsProvider.future));
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionResidualVectorsProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<FramePhotometricCalibrationRow>>[];
    if (includeStandalone) {
      datasets.add(await ref.read(sessionlessCalibrationsProvider.future));
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionFrameCalibrationsProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
    List<int> sessionIds, {
    required bool includeStandalone,
  }) async {
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

    final datasets = <List<MovingObjectCandidateRow>>[];
    if (includeStandalone) {
      datasets.add(
        await ref.read(sessionlessMovingObjectCandidatesProvider.future),
      );
    }
    for (final sessionId in sessionIds) {
      datasets.add(
        await ref.read(sessionMovingObjectCandidatesProvider(sessionId).future),
      );
    }
    for (final data in datasets) {
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
}
