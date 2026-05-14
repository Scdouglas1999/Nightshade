import 'dart:math' as math;
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'mpc_export_panel.dart';
import 'period_analysis_panel.dart';
import 'photometric_calibration_wizard.dart';
import 'science_export_hub.dart';
import 'science_insights_panel.dart';
import 'science_kpi_strip.dart';
import 'science_overlay_composer.dart';
import 'science_surface_explorer.dart';
import 'science_timeline_scrubber.dart';

// Jump-nav anchor keys for the science tab. Declared at file scope so the
// build method's section bar and section bodies share the same key instances
// across rebuilds — Scrollable.ensureVisible needs a key whose context is in
// the live tree at the moment of the jump.
class _ScienceSectionKeys {
  final GlobalKey photometry = GlobalKey();
  final GlobalKey fieldQuality = GlobalKey();
  final GlobalKey anomalies = GlobalKey();
}

class ScienceAnalyticsTab extends ConsumerStatefulWidget {
  const ScienceAnalyticsTab({super.key});

  @override
  ConsumerState<ScienceAnalyticsTab> createState() =>
      _ScienceAnalyticsTabState();
}

class _ScienceAnalyticsTabState extends ConsumerState<ScienceAnalyticsTab> {
  final _ScienceSectionKeys _sectionKeys = _ScienceSectionKeys();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final activeSessionId = _resolveSessionId(ref);

    // When no session is available, render the full layout with empty data
    // so the user can see the card layout, info buttons, and structure.
    List<LightCurvePoint> lightCurve = const [];
    List<TransparencyTrendPoint> transparency = const [];
    List<TransparencySampleRow> transparencyRows = const [];
    List<FramePhotometricCalibrationRow> calibrations = const [];
    List<PsfFieldTileRow> psfTiles = const [];
    List<AstrometryResidualVectorRow> residuals = const [];
    List<MovingObjectCandidateRow> moving = const [];
    List<LineRatioProductRow> lineRatios = const [];
    List<ScienceFrameQualityMetricsRow> frameMetrics = const [];
    List<ScienceTileMetricRow> tileMetrics = const [];

    if (activeSessionId != null) {
      final targetObjectId = ref.watch(activePhotometryTargetObjectIdProvider);
      lightCurve = ref
          .watch(sessionLightCurveProvider((activeSessionId, targetObjectId)));
      transparency =
          ref.watch(sessionTransparencyTrendProvider(activeSessionId));
      transparencyRows = ref
              .watch(sessionTransparencySamplesProvider(activeSessionId))
              .valueOrNull ??
          const [];
      calibrations = ref
              .watch(sessionFrameCalibrationsProvider(activeSessionId))
              .valueOrNull ??
          const [];
      psfTiles =
          ref.watch(sessionPsfTilesProvider(activeSessionId)).valueOrNull ??
              const [];
      residuals = ref
              .watch(sessionResidualVectorsProvider(activeSessionId))
              .valueOrNull ??
          const [];
      moving = ref
              .watch(sessionMovingObjectCandidatesProvider(activeSessionId))
              .valueOrNull ??
          const [];
      lineRatios = ref
              .watch(sessionLineRatioProductsProvider(activeSessionId))
              .valueOrNull ??
          const [];
      frameMetrics = ref
              .watch(sessionFrameQualityMetricsProvider(activeSessionId))
              .valueOrNull ??
          const [];
      tileMetrics =
          ref.watch(sessionTileMetricsProvider(activeSessionId)).valueOrNull ??
              const [];
    } else {
      // No session available — show standalone/quick capture science data
      final targetObjectId = ref.watch(activePhotometryTargetObjectIdProvider);
      lightCurve = ref.watch(sessionlessLightCurveProvider(targetObjectId));
      transparency = ref.watch(sessionlessTransparencyTrendProvider);
      transparencyRows =
          ref.watch(sessionlessTransparencySamplesProvider).valueOrNull ??
              const [];
      calibrations =
          ref.watch(sessionlessCalibrationsProvider).valueOrNull ?? const [];
      psfTiles = ref.watch(sessionlessPsfTilesProvider).valueOrNull ?? const [];
      residuals =
          ref.watch(sessionlessResidualVectorsProvider).valueOrNull ?? const [];
      moving =
          ref.watch(sessionlessMovingObjectCandidatesProvider).valueOrNull ??
              const [];
      lineRatios =
          ref.watch(sessionlessLineRatioProductsProvider).valueOrNull ??
              const [];
      frameMetrics =
          ref.watch(sessionlessFrameQualityMetricsProvider).valueOrNull ??
              const [];
      tileMetrics =
          ref.watch(sessionlessTileMetricsProvider).valueOrNull ?? const [];
    }

    final latestPsfTiles = _latestPsfSnapshot(psfTiles);
    final latestResiduals = _latestResidualSnapshot(residuals);
    final latestTileMetrics = _latestTileMetricSnapshot(tileMetrics);
    // Memoized via Riverpod so a re-render that doesn't change the underlying
    // PSF/residual snapshots reuses the prior analysis instead of recomputing
    // it on every frame (audit §6.20).
    final diagnostics = ref.watch(
      latestSnapshotOpticalTrainDiagnosticsProvider(activeSessionId),
    );
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final allSessions = ref.watch(allSessionsProvider).valueOrNull ?? const [];
    final healthReport = const EquipmentHealthService().analyze(
      sessions: allSessions,
      deviceHealth: [
        if (cameraState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: cameraState.deviceId!,
            lastSuccessfulTimestampMs: cameraState
                    .lastSuccessfulCommunication?.millisecondsSinceEpoch ??
                DateTime.now().millisecondsSinceEpoch,
            isHealthy: cameraState.isHealthy,
          ),
        if (mountState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: mountState.deviceId!,
            lastSuccessfulTimestampMs: DateTime.now().millisecondsSinceEpoch,
            isHealthy:
                mountState.connectionState == DeviceConnectionState.connected,
          ),
        if (guiderState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: guiderState.deviceId!,
            lastSuccessfulTimestampMs: DateTime.now().millisecondsSinceEpoch,
            isHealthy:
                guiderState.connectionState == DeviceConnectionState.connected,
          ),
      ],
    );

    final latestCal = calibrations.isEmpty ? null : calibrations.last;
    final latestFrameQuality = frameMetrics.isEmpty ? null : frameMetrics.last;
    final latestTransparencyRow =
        transparencyRows.isEmpty ? null : transparencyRows.last;
    final isNarrow = MediaQuery.sizeOf(context).width < 1080;

    // Audit §4.12: when neither an active session nor any standalone capture
    // has produced science data, render a single shared placeholder instead
    // of stacking nine "no data" cards (one per panel).
    final bool allEmpty = lightCurve.isEmpty &&
        transparency.isEmpty &&
        transparencyRows.isEmpty &&
        calibrations.isEmpty &&
        psfTiles.isEmpty &&
        residuals.isEmpty &&
        moving.isEmpty &&
        lineRatios.isEmpty &&
        frameMetrics.isEmpty &&
        tileMetrics.isEmpty;
    if (allEmpty) {
      return EmptyState(
        icon: LucideIcons.flaskConical,
        title: 'No science data yet',
        body: activeSessionId == null
            ? 'Capture some plate-solved frames to populate the science tab. '
                'Photometry, PSF maps, and anomaly detections appear here once '
                'a session has produced calibrated data.'
            : 'This session has not produced calibrated science products yet. '
                'PSF tiles, residual maps, and photometry will populate as '
                'frames are processed.',
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Audit §4.13: jump nav for the three logical sections below. Sits
          // at the top of the scroll view; the IndexedStack containing this
          // tab keeps it pinned visually whenever the tab is active.
          _ScienceJumpNav(
            colors: colors,
            onPhotometry: () => _jumpTo(_sectionKeys.photometry),
            onFieldQuality: () => _jumpTo(_sectionKeys.fieldQuality),
            onAnomalies: () => _jumpTo(_sectionKeys.anomalies),
          ),
          const SizedBox(height: 12),
          ScienceKpiStrip(
            colors: colors,
            latestCalibration: latestCal,
            latestTransparency: latestTransparencyRow,
            latestFrameQuality: latestFrameQuality,
            movingCandidateCount: moving.length,
          ),
          const SizedBox(height: 16),
          if (isNarrow) ...[
            ScienceSurfaceExplorer(
              colors: colors,
              tiles: latestTileMetrics,
            ),
            const SizedBox(height: 12),
            ScienceOverlayComposer(colors: colors),
            const SizedBox(height: 12),
            ScienceTimelineScrubber(
              colors: colors,
              frameMetrics: frameMetrics,
            ),
            const SizedBox(height: 12),
            ScienceInsightsPanel(
              colors: colors,
              frameMetrics: latestFrameQuality,
              latestCalibration: latestCal,
              latestTransparency: latestTransparencyRow,
              diagnostics: diagnostics,
              healthReport: healthReport,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: ScienceSurfaceExplorer(
                    colors: colors,
                    tiles: latestTileMetrics,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      ScienceOverlayComposer(colors: colors),
                      const SizedBox(height: 12),
                      ScienceTimelineScrubber(
                        colors: colors,
                        frameMetrics: frameMetrics,
                      ),
                      const SizedBox(height: 12),
                      ScienceInsightsPanel(
                        colors: colors,
                        frameMetrics: latestFrameQuality,
                        latestCalibration: latestCal,
                        latestTransparency: latestTransparencyRow,
                        diagnostics: diagnostics,
                        healthReport: healthReport,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          // -------------------------------------------------------------
          // Section: Photometry
          // -------------------------------------------------------------
          KeyedSubtree(
            key: _sectionKeys.photometry,
            child: _SectionHeading(
              colors: colors,
              label: 'PHOTOMETRY',
              icon: LucideIcons.lineChart,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _LightCurveChartCard(
                  colors: colors,
                  lightCurve: lightCurve,
                  hubExportButton: lightCurve.isEmpty
                      ? null
                      : const _CardHubExportButton(
                          tooltip: 'Open export hub (Photometry)',
                          dataset: ScienceExportDataset.photometry,
                        ),
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
                  color: colors.info,
                  hubExportButton: transparencyRows.isEmpty
                      ? null
                      : const _CardHubExportButton(
                          tooltip: 'Open export hub (Transparency)',
                          dataset: ScienceExportDataset.transparency,
                        ),
                ),
              ),
            ],
          ),
          if (lightCurve.isNotEmpty && activeSessionId != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _AavsoExportButton(
                colors: colors,
                sessionId: activeSessionId,
              ),
            ),
          const SizedBox(height: 16),
          PeriodAnalysisPanel(
            colors: colors,
            lightCurve: lightCurve,
          ),
          const SizedBox(height: 24),
          // -------------------------------------------------------------
          // Section: Field Quality
          // -------------------------------------------------------------
          KeyedSubtree(
            key: _sectionKeys.fieldQuality,
            child: _SectionHeading(
              colors: colors,
              label: 'FIELD QUALITY',
              icon: LucideIcons.grid,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PsfHeatmapCard(
                  colors: colors,
                  tiles: latestPsfTiles,
                  hubExportButton: latestPsfTiles.isEmpty
                      ? null
                      : const _CardHubExportButton(
                          tooltip: 'Open export hub (PSF tiles)',
                          dataset: ScienceExportDataset.psfTiles,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ResidualCard(
                  colors: colors,
                  residuals: latestResiduals,
                  hubExportButton: latestResiduals.isEmpty
                      ? null
                      : const _CardHubExportButton(
                          tooltip: 'Open export hub (Astrometric residuals)',
                          dataset: ScienceExportDataset.residuals,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PhotometricTransformsCard(colors: colors),
          const SizedBox(height: 24),
          // -------------------------------------------------------------
          // Section: Anomalies
          // -------------------------------------------------------------
          KeyedSubtree(
            key: _sectionKeys.anomalies,
            child: _SectionHeading(
              colors: colors,
              label: 'ANOMALIES',
              icon: LucideIcons.orbit,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MovingObjectCard(
                  colors: colors,
                  moving: moving,
                  hubExportButton: moving.isEmpty
                      ? null
                      : _CardHubExportButton(
                          tooltip:
                              'Open export hub (Moving object candidates)',
                          dataset: ScienceExportDataset.movingObjects,
                          mpcCandidates: moving,
                        ),
                ),
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
          // MPC export panel -- only shown when moving object candidates exist
          if (moving.isNotEmpty) ...[
            const SizedBox(height: 16),
            MpcExportPanel(colors: colors, candidates: moving),
          ],
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

/// Inline export button that routes to the consolidated [ScienceExportHub]
/// pre-selected to a specific dataset. Replaces the per-card CSV writer so
/// there is one canonical export surface (audit §4.14).
class _CardHubExportButton extends StatelessWidget {
  final String tooltip;
  final ScienceExportDataset dataset;
  final List<MovingObjectCandidateRow> mpcCandidates;

  const _CardHubExportButton({
    required this.tooltip,
    required this.dataset,
    this.mpcCandidates = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => ScienceExportHub(
              initialDataset: dataset,
              mpcCandidates: mpcCandidates,
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            LucideIcons.download,
            size: 14,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Sticky jump-nav row pinning Photometry / Field Quality / Anomalies tabs at
/// the top of the science analytics scroll view. Implements audit §4.13 so
/// users do not have to scroll through several hundred pixels of dense panels
/// to reach the section they care about.
class _ScienceJumpNav extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onPhotometry;
  final VoidCallback onFieldQuality;
  final VoidCallback onAnomalies;

  const _ScienceJumpNav({
    required this.colors,
    required this.onPhotometry,
    required this.onFieldQuality,
    required this.onAnomalies,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _JumpChip(
            colors: colors,
            icon: LucideIcons.lineChart,
            label: 'Photometry',
            onTap: onPhotometry,
          ),
          const SizedBox(width: 8),
          _JumpChip(
            colors: colors,
            icon: LucideIcons.grid,
            label: 'Field Quality',
            onTap: onFieldQuality,
          ),
          const SizedBox(width: 8),
          _JumpChip(
            colors: colors,
            icon: LucideIcons.orbit,
            label: 'Anomalies',
            onTap: onAnomalies,
          ),
        ],
      ),
    );
  }
}

class _JumpChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _JumpChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final IconData icon;

  const _SectionHeading({
    required this.colors,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Per-card CSV row builders were removed once the science analytics tab
// stopped writing CSV inline. Exports now route exclusively through the
// consolidated [ScienceExportHub] (audit §4.14), which builds its rows from
// the DAO providers and therefore covers every session, not just the visible
// snapshot.

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

List<ScienceTileMetricRow> _latestTileMetricSnapshot(
  List<ScienceTileMetricRow> rows,
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

// =============================================================================
// Science Info Explanations
// =============================================================================

const _kCalibrationInfo = '''
Photometric calibration is the process of converting raw pixel values in your images into standardized astronomical magnitudes. This lets you make scientifically meaningful brightness measurements rather than working with arbitrary intensity numbers.

When Nightshade plate-solves a frame, it identifies known stars in the field and compares their measured brightness (in pixel counts) against their cataloged magnitudes. This comparison produces a zero-point (ZP) — a single number that anchors your instrumental magnitudes to the standard magnitude scale.

A "Calibrated" status means Nightshade successfully matched enough catalog stars to compute a reliable zero-point. "Uncalibrated" means either the plate solve failed, too few stars were matched, or the fit residuals were too large to trust.

The zero-point value itself tells you about your system's overall sensitivity for this session. A higher ZP means your system is detecting fainter stars per unit of exposure time. Changes in ZP between sessions can indicate differences in sky conditions, optical cleanliness, or camera performance.
''';

const _kLimMagInfo = '''
Limiting magnitude (5-sigma) tells you the faintest star your imaging system can reliably detect in the current conditions, at a 5-sigma confidence level. In other words, a star at this magnitude would produce a signal five times stronger than the background noise — the standard threshold astronomers use to distinguish real detections from noise.

This is one of the most important single numbers for evaluating your imaging setup's performance on a given night. It combines the effects of your telescope's aperture, camera sensitivity, sky brightness, atmospheric transparency, tracking accuracy, and focus quality into a single metric.

A higher limiting magnitude means you're reaching fainter objects. Typical values for amateur setups range from magnitude 16 to 22 depending on equipment and conditions. Comparing this number across sessions helps you identify your best nights and track equipment performance over time.

The "matched stars" count shows how many catalog stars were used to compute this value. More matched stars generally means a more reliable measurement. Fewer than ~20 matched stars may indicate the value is less trustworthy.
''';

const _kTransparencyInfo = '''
Atmospheric transparency measures how much starlight makes it through the atmosphere without being absorbed or scattered. It's expressed as a percentage, where 100% would mean perfectly clear skies with zero atmospheric extinction beyond the minimum.

Nightshade estimates transparency by comparing the measured brightness of known stars against their expected catalog magnitudes, after accounting for your system's calibrated zero-point. If stars appear dimmer than expected, the atmosphere is absorbing some of the light.

The quality bucket (Clear, Thin Cloud, etc.) provides a quick human-readable assessment based on the transparency percentage. This helps you decide whether conditions are suitable for photometry, narrowband imaging, or if you should wait for clearer skies.

Transparency is distinct from "seeing" (which measures atmospheric turbulence and affects star sharpness). You can have excellent transparency with poor seeing, or vice versa. Both matter for imaging, but transparency is especially critical for photometric accuracy and reaching faint targets.
''';

const _kMovingObjectsInfo = '''
The moving object detector searches for sources that shift position between consecutive frames in your imaging session. This can reveal asteroids, comets, near-Earth objects (NEOs), or even artificial satellites passing through your field of view.

Nightshade compares the positions of detected sources across multiple exposures. Objects that show consistent linear motion (within expected velocity ranges for solar system objects) are flagged as candidates. Each candidate is assigned a confidence score based on how well its apparent motion fits expected trajectories and how clearly it stands out from noise or image artifacts.

The count shown here represents the number of distinct candidate objects found. A high count doesn't necessarily mean many real asteroids — some candidates may be hot pixels, cosmic ray hits, or other artifacts that mimic motion. The confidence percentage of the top candidate helps you gauge how likely the best detection is to be a real object.

If you detect a high-confidence moving object that doesn't match known solar system bodies, it could be a previously undiscovered asteroid — a genuinely exciting find that you can report to the Minor Planet Center (MPC).
''';

const _kDifferentialPhotometryInfo = '''
Differential photometry measures how a target object's brightness changes over time relative to stable comparison stars in the same field of view. By measuring the target and comparison stars simultaneously in each frame, most atmospheric and instrumental effects cancel out, enabling very precise brightness measurements.

The Y-axis shows differential magnitude (dMag) — the difference between the target star's magnitude and the comparison ensemble. The axis is inverted so that brighter values appear higher on the chart, following the astronomical convention where lower magnitude numbers mean brighter objects.

The error bars on each data point show the measurement uncertainty. Smaller error bars indicate more precise measurements. Factors that reduce uncertainty include longer exposures, better focus, higher transparency, and more comparison stars.

This chart is essential for detecting variable stars, transiting exoplanets, eclipsing binaries, and other objects that change brightness. An exoplanet transit, for example, would appear as a subtle dip (typically 0.005-0.02 magnitudes) lasting a few hours. Eclipsing binaries show deeper, more regular dips.

For the most accurate results, ensure your comparison stars are non-variable, similar in color to your target, and well-exposed without saturation.
''';

const _kTransparencyTrendInfo = '''
The transparency trend chart tracks how atmospheric clarity changes throughout your imaging session. Each point represents a transparency measurement derived from comparing measured star brightnesses to their catalog values.

A flat, high line (near 90-100%) indicates stable, clear conditions — ideal for photometry and deep imaging. A downward trend suggests increasing cloud cover, rising humidity, or the target moving to lower altitude where atmospheric extinction is greater.

Sudden drops usually indicate thin clouds passing through the field. Gradual declines over the session may reflect changing atmospheric conditions, increasing dew formation on optics, or the target descending toward the horizon.

This chart helps you identify which portions of your session had the best conditions, so you can selectively stack only the frames captured during optimal transparency. It's also useful for explaining unexpected scatter in your photometry data — periods of poor transparency will naturally produce noisier magnitude measurements.

The X-axis shows elapsed time from the start of the session in minutes.
''';

const _kPsfFieldMapInfo = '''
The PSF (Point Spread Function) Field Map shows how star sharpness varies across your imaging sensor. Each tile in the grid represents a region of the field of view, color-coded by the median FWHM (Full Width at Half Maximum) of stars detected in that region.

FWHM measures how spread out a star's light profile is, in pixels. A perfectly focused star on a sensor with no atmospheric distortion would be as small as the diffraction limit allows. In practice, FWHM is typically 2-6 pixels for amateur setups and is affected by focus accuracy, atmospheric seeing, optical aberrations, and tracking errors.

Green tiles indicate regions with tight, well-focused stars (low FWHM). Red tiles indicate regions where stars appear bloated or elongated (high FWHM). A uniform green grid means your optics are well-corrected and evenly focused across the field.

Common patterns you might see:
- Corners redder than center: field curvature or coma from your optical train. Consider a field flattener or coma corrector.
- One side redder: tilt in your imaging train (camera not square to the optical axis). Check your adapters and spacers.
- Everything red: poor focus or poor seeing conditions.
- Uniform green: excellent optics and focus — the ideal result.

The color scale is normalized to the 5th and 95th percentiles of your data, so it automatically adapts to show the variation present in your specific setup.
''';

const _kAstrometricResidualsInfo = '''
Astrometric residuals measure the accuracy of the plate solution — how well the computed sky coordinates match the actual positions of known catalog stars in your image. After plate solving identifies stars and fits a coordinate model, the residual for each star is the angular distance between where the model says it should be and where it actually appears.

The RMS (Root Mean Square) value combines all individual residuals into a single accuracy metric, expressed in arcseconds. Lower RMS means a more accurate astrometric solution.

Typical values:
- Below 0.5": Excellent astrometry, suitable for scientific reporting.
- 0.5" to 1.5": Good astrometry, adequate for most purposes.
- 1.5" to 3.0": Acceptable, but may indicate optical distortion or a sparse star field.
- Above 3.0": Poor fit — may indicate tracking issues, severe distortion at the field edges, or an incorrect focal length in the solver configuration.

The "recommendation" code (when present) provides guidance from the astrometric solver about potential improvements, such as refining the distortion model, adjusting the focal length, or using a denser reference catalog.

High residuals can result from: poor tracking (field rotation or drift), optical distortion not accounted for in the plate model, incorrectly specified pixel scale or focal length, or very few reference stars in the field.
''';

const _kMovingObjectCandidatesInfo = '''
This panel lists the individual moving object candidates detected in your session, ranked by confidence. For each candidate, you can see:

- Name/ID: If the object matches a known asteroid or comet from the MPC (Minor Planet Center) database, its designation is shown. Otherwise, a temporary candidate ID is assigned.

- Confidence: A percentage score indicating how likely this detection is to be a real moving object versus an artifact. Scores above 80% are generally reliable. Lower scores may indicate hot pixels, cosmic rays, or satellite trails that partially mimic asteroid-like motion.

- Motion rate: The apparent angular velocity in arcseconds per minute. Main-belt asteroids typically move at 0.3-1.0"/min, while NEOs (Near-Earth Objects) can move much faster (up to several arcseconds per minute or more). Very fast motion (>10"/min) is usually an artificial satellite.

To confirm a candidate as a real discovery, you would need to image the same field on subsequent nights to verify the object is still present and moving along a consistent orbital arc. Confirmed new discoveries can be reported to the Minor Planet Center for official designation.

The list shows up to 6 candidates. If many low-confidence candidates appear, it may indicate noisy data or a crowded star field rather than actual moving objects.
''';

const _kNarrowbandRatiosInfo = '''
Narrowband emission line ratios compare the relative intensities of specific wavelengths of light emitted by ionized gas in nebulae. These ratios reveal the physical conditions — temperature, density, and ionization state — of the gas you're imaging.

The three ratios shown are:

SII/H-alpha: Compares sulfur-II emission (672nm) to hydrogen-alpha emission (656nm). Elevated SII/Ha ratios indicate shock-heated gas, such as supernova remnants (SNRs) or Herbig-Haro objects. Typical HII regions (star-forming nebulae) have SII/Ha < 0.4, while SNRs often exceed 0.4-0.5.

OIII/H-alpha: Compares doubly-ionized oxygen emission (496/501nm) to hydrogen-alpha. High OIII/Ha ratios indicate highly ionized gas, typically found near hot stars (planetary nebulae, Wolf-Rayet bubbles) or in the outer zones of large HII regions. This ratio is a proxy for the ionization parameter of the gas.

SII/OIII: Compares sulfur-II to oxygen-III directly. This ratio helps distinguish between different excitation mechanisms. Low SII/OIII values suggest photoionization by UV radiation from hot stars, while high values point toward collisional excitation from shocks.

To generate ratios, Nightshade needs at least one frame captured through each of the three narrowband filters (H-alpha, OIII, SII) in the current session. The frames are median-sampled and their integrated fluxes are compared to produce each ratio.

These ratios are widely used in professional astronomy for classifying nebulae, mapping shock fronts, and studying the interstellar medium. They form the basis of BPT (Baldwin-Phillips-Terlevich) diagnostic diagrams used to classify emission-line objects.
''';

const _kPhotometricTransformsInfo = '''
Photometric transformation coefficients convert your instrumental magnitudes into a standard photometric system (such as Johnson-Cousins UBVRI or Sloan ugriz). Without these coefficients, your brightness measurements are only relative — useful for differential photometry, but not directly comparable to catalog values or measurements from other observatories.

The transformation equation is: M_std = m_inst - k*X + T*(B-V) + ZP

Where:
- M_std: Standard magnitude (the calibrated result)
- m_inst: Instrumental magnitude (what your camera measures)
- k: Extinction coefficient (how much the atmosphere dims starlight per unit airmass)
- X: Airmass (how much atmosphere the light passes through; more at lower elevations)
- T: Color term (corrects for your filter+CCD combination's color response vs. the standard system)
- (B-V): Color index of the star (blue minus visual magnitude, a measure of stellar color)
- ZP: Zero point (the offset between your instrumental scale and the standard scale)

To compute these coefficients, Nightshade uses a least-squares fit of catalog star magnitudes against your measured instrumental magnitudes. The calibration wizard guides you through selecting a suitable frame with many catalog stars, matching them, and computing the fit.

The RMS residual indicates how well the transform fits the data. Values below 0.03 mag are excellent; 0.03-0.05 is good; 0.05-0.10 is acceptable for most work. Higher values may indicate color terms that vary across the field, poor focus, or thin clouds.

Once saved, these coefficients are automatically applied to new photometry measurements, converting differential magnitudes into absolute standard magnitudes suitable for AAVSO submission and cross-observatory comparison.
''';

/// Map of card titles to their info content for easy lookup.
const _kScienceInfoContent = <String, String>{
  'Calibration': _kCalibrationInfo,
  'Lim Mag (5-sigma)': _kLimMagInfo,
  'Transparency': _kTransparencyInfo,
  'Moving Objects': _kMovingObjectsInfo,
  'Differential Photometry': _kDifferentialPhotometryInfo,
  'Transparency Trend': _kTransparencyTrendInfo,
  'PSF Field Map': _kPsfFieldMapInfo,
  'Astrometric Residuals': _kAstrometricResidualsInfo,
  'Moving Object Candidates': _kMovingObjectCandidatesInfo,
  'Narrowband Ratios': _kNarrowbandRatiosInfo,
  'Photometric Transforms': _kPhotometricTransformsInfo,
};

/// Shows a themed info dialog explaining a science visualization.
void _showScienceInfoDialog(BuildContext context, String title, String body) {
  final colors = Theme.of(context).extension<NightshadeColors>()!;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.25)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.info,
              color: colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: SingleChildScrollView(
          child: Text(
            body.trim(),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context),
          label: 'Got it',
          variant: ButtonVariant.ghost,
        ),
      ],
    ),
  );
}

/// Small info icon button that opens the explanation dialog for a science card.
class _ScienceInfoButton extends StatelessWidget {
  final String title;

  const _ScienceInfoButton({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final body = _kScienceInfoContent[title];
    if (body == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'What is this?',
      child: InkWell(
        onTap: () => _showScienceInfoDialog(context, title, body),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            LucideIcons.info,
            size: 14,
            color: colors.textMuted,
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
  // Optional inline button that opens the consolidated export hub with the
  // matching dataset pre-selected. Replaces the old per-card CSV writer so
  // there is one canonical export surface (audit §4.14).
  final Widget? hubExportButton;

  const _SeriesChartCard({
    required this.colors,
    required this.title,
    required this.yLabel,
    required this.points,
    required this.color,
    this.hubExportButton,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (hubExportButton != null) hubExportButton!,
                _ScienceInfoButton(title: title),
              ],
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
          content: Column(
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
        child: SizedBox(
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
                        'dMag',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 10),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          (-value).toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 10,
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
                final labelColor = color.computeLuminance() > 0.45
                    ? const Color(0xFF000000)
                    : const Color(0xFFFFFFFF);

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
                        style: TextStyle(
                          color: labelColor,
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

// =============================================================================
// Photometric Transforms Card
// =============================================================================

class _PhotometricTransformsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _PhotometricTransformsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transformsAsync = ref.watch(activeProfileTransformsProvider);

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
                    'Photometric Transforms',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const _ScienceInfoButton(title: 'Photometric Transforms'),
              ],
            ),
            const SizedBox(height: 8),
            transformsAsync.when(
              data: (transforms) => _buildTransformContent(context, transforms),
              loading: () => SizedBox(
                height: 60,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              error: (error, _) => Text(
                'Failed to load transforms: $error',
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: () => _openCalibrationWizard(context),
                icon: LucideIcons.beaker,
                label: 'Calibrate',
                variant: ButtonVariant.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransformContent(
      BuildContext context, List<PhotometricTransformRow> transforms) {
    if (transforms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No transform coefficients computed yet. Use the Calibrate button '
          'to run the photometric calibration wizard on a standard star field.',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in transforms) ...[
          _TransformRow(colors: colors, transform: t),
          if (t != transforms.last) const SizedBox(height: 6),
        ],
      ],
    );
  }

  void _openCalibrationWizard(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PhotometricCalibrationWizard(),
    );
  }
}

class _TransformRow extends StatelessWidget {
  final NightshadeColors colors;
  final PhotometricTransformRow transform;

  const _TransformRow({
    required this.colors,
    required this.transform,
  });

  @override
  Widget build(BuildContext context) {
    final quality = _qualityLabel(transform.rmsResidual);
    final qualityColor = _qualityColor(transform.rmsResidual, colors);
    final age = DateTime.now().difference(transform.dateComputed);
    final ageLabel = age.inDays == 0
        ? 'Today'
        : age.inDays == 1
            ? '1 day ago'
            : '${age.inDays} days ago';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  transform.filterName,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: qualityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  quality,
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                ageLabel,
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _CoefficientChip(
                colors: colors,
                label: 'ZP',
                value: transform.zeroPoint.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'k',
                value: transform.extinctionCoefficient.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'T',
                value: transform.colorTerm.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'RMS',
                value: '${transform.rmsResidual.toStringAsFixed(3)} mag',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${transform.matchedStarCount} stars matched  |  '
            'Catalog: ${transform.catalogSource}',
            style: TextStyle(color: colors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(double rms) {
    if (rms <= 0.03) return 'Excellent';
    if (rms <= 0.05) return 'Good';
    if (rms <= 0.10) return 'Acceptable';
    return 'Poor';
  }

  Color _qualityColor(double rms, NightshadeColors colors) {
    if (rms <= 0.03) return colors.success;
    if (rms <= 0.05) return colors.info;
    if (rms <= 0.10) return colors.warning;
    return colors.error;
  }
}

class _CoefficientChip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _CoefficientChip({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
