import 'dart:math' as math;
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../analytics_screen.dart'
    show dbSessionImagesProvider, standaloneImagesProvider;
import 'mpc_export_panel.dart';
import 'period_analysis_panel.dart';
import 'photometric_calibration_wizard.dart';
import 'science_export_hub.dart';
import 'science_insights_panel.dart';
import 'science_kpi_strip.dart';
import 'science_overlay_composer.dart';
import 'science_solve_rate_card.dart';
import 'image_grader_dialog.dart';
import 'science_status_banner.dart';
import 'science_surface_explorer.dart';
import 'night_story_timeline.dart';
import 'science_timeline_scrubber.dart';
import 'science_campaign_strip.dart';
import 'science_trend_cards.dart';
import 'adaptive_chart_container.dart';
import 'science_onboarding/science_ladder_card.dart';
import 'science_onboarding/science_empty_onramp.dart';
import 'science_onboarding/science_nav_row_card.dart';

part 'science_analytics_tab/navigation_and_snapshots.dart';
part 'science_analytics_tab/science_info_and_series_chart.dart';
part 'science_analytics_tab/science_cards.dart';
part 'science_analytics_tab/transforms_and_welcome.dart';

// Jump-nav anchor keys for the science tab. Declared at file scope so the
// build method's section bar and section bodies share the same key instances
// across rebuilds — Scrollable.ensureVisible needs a key whose context is in
// the live tree at the moment of the jump.
class _ScienceSectionKeys {
  final GlobalKey ladder = GlobalKey();
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

  void _openExportHub(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ScienceExportHub(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
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

    // Pull the underlying captured-image list so the solve-rate card and the
    // insights engine can report on plate-solve health. Same provider the
    // Session tab uses, so Drift only runs the query once.
    final imageList = activeSessionId == null
        ? (ref.watch(standaloneImagesProvider).valueOrNull ?? const [])
        : (ref.watch(dbSessionImagesProvider(activeSessionId)).valueOrNull ??
            const []);
    final lightFrames = imageList
        .where((image) => image.frameType.toLowerCase() == 'light')
        .toList(growable: false);
    final solvedFrames =
        lightFrames.where((image) => image.isPlateSolved).length;
    final calibratedRowCount = calibrations.where((c) => c.isCalibrated).length;

    final hasTarget =
        ref.watch(sciencePhotometrySelectionProvider).valueOrNull?.target !=
            null;
    final photometryLive =
        ref.watch(scienceModeStateProvider).differentialPhotometryActive;
    final hasPeriodResult = ref.watch(periodAnalysisProvider).result != null;
    final hasExportableData = lightCurve.isNotEmpty ||
        moving.isNotEmpty ||
        calibrations.isNotEmpty;

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
      // P0.2 + P0.3: even when no science products exist yet, show the live
      // pipeline status and the solve-rate card so users can see *why*
      // products are missing (queue idle, plate solver not configured, etc.)
      // and take action.
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScienceStatusBanner(),
            const SizedBox(height: NightshadeTokens.spaceLg),
            ScienceSolveRateCard(
              colors: colors,
              lightFrames: lightFrames,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            KeyedSubtree(
              key: _sectionKeys.ladder,
              child: ScienceLadderCard(
                hasCalibration: calibratedRowCount > 0,
                hasTarget: hasTarget,
                photometryLive: photometryLive,
                lightCurvePoints: lightCurve.length,
                hasPeriodResult: hasPeriodResult,
                hasExportableData: hasExportableData,
                onJumpToPhotometry: () => _jumpTo(_sectionKeys.ladder),
                onJumpToFieldQuality: () => _jumpTo(_sectionKeys.ladder),
                onOpenExport: () => _openExportHub(context),
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            ScienceEmptyOnramp(
              onShowSteps: () => _jumpTo(_sectionKeys.ladder),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // P0.2: always-on pipeline status. Tells the user whether science
          // is currently running, idle, or failing — instead of inferring
          // from empty cards.
          const ScienceStatusBanner(),
          const SizedBox(height: 12),
          ScienceLadderCard(
            hasCalibration: calibratedRowCount > 0,
            hasTarget: hasTarget,
            photometryLive: photometryLive,
            lightCurvePoints: lightCurve.length,
            hasPeriodResult: hasPeriodResult,
            hasExportableData: hasExportableData,
            onJumpToPhotometry: () => _jumpTo(_sectionKeys.photometry),
            onJumpToFieldQuality: () => _jumpTo(_sectionKeys.fieldQuality),
            onOpenExport: () => _openExportHub(context),
          ),
          const SizedBox(height: 12),
          ScienceNavRowCard(
            icon: LucideIcons.satellite,
            iconColor: colors.info,
            label: 'Observing alerts (Transients)',
            labelColor: colors.textPrimary,
            onTap: () => context.go('/transients'),
          ),
          const SizedBox(height: 12),
          // Audit §4.13: jump nav for the three logical sections below. Sits
          // at the top of the scroll view; the IndexedStack containing this
          // tab keeps it pinned visually whenever the tab is active.
          _ScienceJumpNav(
            colors: colors,
            onPhotometry: () => _jumpTo(_sectionKeys.photometry),
            onFieldQuality: () => _jumpTo(_sectionKeys.fieldQuality),
            onAnomalies: () => _jumpTo(_sectionKeys.anomalies),
            sessionId: activeSessionId,
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
          // P0.3: solve-rate health card. Always visible — turns a soft
          // "no data" failure mode into an actionable diagnosis.
          ScienceSolveRateCard(
            colors: colors,
            lightFrames: lightFrames,
          ),
          const SizedBox(height: 12),
          const ScienceCampaignStrip(),
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
              calibratedFrameCount: calibratedRowCount,
              processedFrameCount: lightFrames.length,
              solvedFrameCount: solvedFrames,
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
                        calibratedFrameCount: calibratedRowCount,
                        processedFrameCount: lightFrames.length,
                        solvedFrameCount: solvedFrames,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          // -------------------------------------------------------------
          // Section: Night Story (Night Narrator surface #3)
          // -------------------------------------------------------------
          // The session's narrative timeline — sits right after the insights
          // panel (which reports what's true *now*) so the user reads the
          // stateless snapshot and then the temporal story of the night
          // before diving into the raw photometry/quality charts below.
          _SectionHeading(
            colors: colors,
            label: 'NIGHT STORY',
            icon: LucideIcons.bookOpen,
          ),
          const SizedBox(height: 12),
          NightStoryTimeline(sessionId: activeSessionId),
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
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ZeroPointTrendCard(
                  colors: colors,
                  calibrations: calibrations,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SolveRateTrendCard(
                  colors: colors,
                  lightFrames: lightFrames,
                ),
              ),
            ],
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
              trailing: lightFrames.isEmpty
                  ? null
                  : NightshadeButton(
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () async {
                        final rejected = await ImageGraderDialog.show(
                          context,
                          frames: lightFrames,
                          sessionId: activeSessionId,
                        );
                        if (rejected != null &&
                            rejected > 0 &&
                            context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Rejected $rejected frame'
                                '${rejected == 1 ? "" : "s"} '
                                'using the threshold rules.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      label:
                          'Grade ${lightFrames.length} frame${lightFrames.length == 1 ? "" : "s"}',
                      icon: LucideIcons.sliders,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: HfrTrendCard(
                  colors: colors,
                  lightFrames: lightFrames,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UniformityTrendCard(
                  colors: colors,
                  frameMetrics: frameMetrics,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                          tooltip: 'Open export hub (Moving object candidates)',
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
