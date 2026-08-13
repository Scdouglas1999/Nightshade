import 'dart:math' as math;
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../utils/exported_file_reveal.dart';
import '../../accessible_dropdown.dart';
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
import 'chart_axis.dart';
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

/// The session this tab falls back to when nothing is live and the user has
/// not chosen one: the most recent session that actually contains light frames.
///
/// Defaulting to `allSessions.first` (simply the newest row) meant a session
/// that only recorded darks or aborted before its first light left the whole
/// tab reading "Science idle — waiting for the first captured frame" while
/// nights of photometry sat one row below it.
final latestScienceSessionProvider = FutureProvider<int?>((ref) async {
  final backend = ref.watch(backendProvider);
  // Remote rigs answer through the network backend, which has no equivalent
  // query; the caller falls back to the newest session there.
  if (backend is NetworkBackend) return null;
  return ref.read(imagesDaoProvider).getLatestSessionIdWithLightFrames();
});

/// The most recent session that carries an actual science PRODUCT — a
/// photometry measurement or a plate-solved frame.
///
/// The Science tab used to open on the newest session holding light frames,
/// which is not the same question: two test frames shot after a 120-frame
/// photometry night are lights, so the tab opened on them and reported
/// "0 of 2 solved", "Warming up" and the never-started empty state, with the
/// night of real measurements two clicks away in a dropdown. Ordering comes
/// from [allSessionsProvider] (newest first) rather than from the product
/// timestamps, so "most recent" means the same thing here as in the session
/// picker beside it.
final latestScienceProductSessionProvider = FutureProvider<int?>((ref) async {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) return null;
  final sessions = await ref.watch(allSessionsProvider.future);
  if (sessions.isEmpty) return null;
  final withProducts = <int>{
    ...await ref.read(scienceDaoProvider).getSessionIdsWithPhotometry(),
    ...await ref.read(imagesDaoProvider).getSessionIdsWithSolvedFrames(),
  };
  if (withProducts.isEmpty) return null;
  for (final session in sessions) {
    if (withProducts.contains(session.id)) return session.id;
  }
  return null;
});

class ScienceAnalyticsTab extends ConsumerStatefulWidget {
  const ScienceAnalyticsTab({super.key});

  @override
  ConsumerState<ScienceAnalyticsTab> createState() =>
      _ScienceAnalyticsTabState();
}

class _ScienceAnalyticsTabState extends ConsumerState<ScienceAnalyticsTab> {
  final _ScienceSectionKeys _sectionKeys = _ScienceSectionKeys();
  final ScrollController _scrollController = ScrollController();

  // Captured-image id chosen in the Timeline Scrubber. When null the surface
  // explorer and insights panels track the latest frame.
  int? _selectedFrameImageId;

  // Session chosen in the session bar. Null means "follow the live session, or
  // the most recent one with light frames".
  int? _selectedSessionId;

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

  void _openExportHub(
    BuildContext context,
    List<MovingObjectCandidateRow> mpcCandidates,
  ) {
    showDialog(
      context: context,
      builder: (_) => ScienceExportHub(mpcCandidates: mpcCandidates),
    );
  }

  void _openCalibrationWizard(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const PhotometricCalibrationWizard(),
    );
  }

  /// Rung 2's 'Pick a target', and the photometry destination on the empty
  /// branch.
  ///
  /// Analytics has nowhere to pick a photometry target: the only control that
  /// sets one is the science HUD over the live frame. Rung 2 used to be
  /// answered with a scroll to the PHOTOMETRY charts (populated branch) or with
  /// the photometric calibration wizard (empty branch) — a button reading 'Pick
  /// a target' that opened a star-field calibration dialog. Send the operator
  /// to the control instead, with the HUD already open so it is on screen when
  /// they arrive.
  void _goPickPhotometryTarget(BuildContext context) {
    final mode = ref.read(scienceModeStateProvider);
    if (!mode.scienceHudVisible) {
      ref.read(scienceModeStateProvider.notifier).state =
          mode.copyWith(scienceHudVisible: true);
    }
    GoRouter.maybeOf(context)?.go('/imaging');
  }

  /// Which session the panels below are reporting on, and a way to change it.
  /// Without this the tab analysed one implicitly-chosen session and gave no
  /// hint that a different night could be selected.
  Widget _sessionBar({
    required NightshadeColors colors,
    required List<ImagingSession> sessions,
    required int? activeSessionId,
    required bool isLive,
  }) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final active = sessions
        .cast<ImagingSession?>()
        .firstWhere((s) => s?.id == activeSessionId, orElse: () => null);
    final format = DateFormat('MMM d, yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(isLive ? LucideIcons.radio : LucideIcons.history,
              size: NightshadeTokens.iconXs,
              color: isLive ? colors.success : colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            isLive ? 'Live session' : 'Analysing',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: AccessibleDropdown<int>(
                value: active?.id,
                isExpanded: true,
                isDense: true,
                dropdownColor: colors.surfaceElevated,
                borderRadius: NightshadeTokens.borderRadiusLg,
                hint: Text(
                  'Select a session',
                  style: NightshadeTypography.labelSm
                      .copyWith(color: colors.textMuted),
                ),
                style: NightshadeTypography.labelSm
                    .copyWith(color: colors.textPrimary),
                onChanged: (id) {
                  // periodAnalysisProvider is a single global result with no
                  // session key, so a period searched on the previous night
                  // stayed on screen for this one — and fed hasPeriodResult,
                  // marking the guide's "Analyse the period" rung done for a
                  // session that had never been searched.
                  ref.read(periodAnalysisProvider.notifier).clear();
                  setState(() {
                    _selectedSessionId = id;
                    // The frame picked in the old session means nothing here.
                    _selectedFrameImageId = null;
                  });
                },
                items: [
                  for (final session in sessions.take(60))
                    DropdownMenuItem<int>(
                      value: session.id,
                      child: Text(
                        '${session.name ?? 'Session ${session.id}'}'
                        '  ·  ${format.format(session.startTime)}'
                        '  ·  ${session.successfulExposures} frames',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_selectedSessionId != null) ...[
            const SizedBox(width: NightshadeTokens.spaceSm),
            TextButton(
              onPressed: () {
                ref.read(periodAnalysisProvider.notifier).clear();
                setState(() {
                  _selectedSessionId = null;
                  _selectedFrameImageId = null;
                });
              },
              child: Text(
                'Most recent',
                style:
                    NightshadeTypography.caption.copyWith(color: colors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pairedCards(bool isNarrow, Widget first, Widget second) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: 12),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final liveSessionId = ref.watch(sessionStateProvider).dbSessionId;
    final sessionsAsync = ref.watch(allSessionsProvider);
    if (liveSessionId == null &&
        (sessionsAsync.isLoading ||
            sessionsAsync.hasError ||
            !sessionsAsync.hasValue)) {
      return _buildSessionIndexState(colors, sessionsAsync);
    }
    final allSessions = sessionsAsync.valueOrNull ?? const <ImagingSession>[];
    // A manual pick wins, then the live session, then the newest session that
    // carries a science product, then the newest holding light frames, and only
    // then the newest session at all.
    final pickedSessionId =
        allSessions.any((session) => session.id == _selectedSessionId)
            ? _selectedSessionId
            : null;
    final activeSessionId = pickedSessionId ??
        liveSessionId ??
        ref.watch(latestScienceProductSessionProvider).valueOrNull ??
        ref.watch(latestScienceSessionProvider).valueOrNull ??
        allSessions.firstOrNull?.id;

    final scienceErrors = <Object>[];
    var scienceLoading = false;
    void track<T>(AsyncValue<T> source) {
      if (source.hasError && source.error != null) {
        scienceErrors.add(source.error!);
      }
      if (source.isLoading || (!source.hasValue && !source.hasError)) {
        scienceLoading = true;
      }
    }

    List<T> resolvedRows<T>(AsyncValue<List<T>> source) {
      track(source);
      return source.valueOrNull ?? const [];
    }

    track(sessionsAsync);

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

    // The object whose light curve this tab plots. Every photometry query below
    // is keyed on it.
    var photometryObjectId = ref.watch(activePhotometryTargetObjectIdProvider);

    if (activeSessionId != null) {
      final sessionPhotometry =
          ref.watch(sessionPhotometryProvider(activeSessionId));
      track(sessionPhotometry);
      // Reviewing is not capturing: a stored night's rows are keyed on the
      // object that WAS being tracked then, and filtering them by whatever the
      // live selection happens to name today hid a complete 120-point curve
      // behind "Differential Photometry has no data yet" (and with it the AAVSO
      // export and the period search).
      photometryObjectId = _reviewedPhotometryObjectId(
        rows: sessionPhotometry.valueOrNull ?? const [],
        liveSelection: photometryObjectId,
      );
      lightCurve = ref.watch(
        sessionLightCurveProvider((activeSessionId, photometryObjectId)),
      );
      transparency =
          ref.watch(sessionTransparencyTrendProvider(activeSessionId));
      transparencyRows = resolvedRows(
        ref.watch(sessionTransparencySamplesProvider(activeSessionId)),
      );
      calibrations = resolvedRows(
        ref.watch(sessionFrameCalibrationsProvider(activeSessionId)),
      );
      psfTiles = resolvedRows(
        ref.watch(sessionPsfTilesProvider(activeSessionId)),
      );
      residuals = resolvedRows(
        ref.watch(sessionResidualVectorsProvider(activeSessionId)),
      );
      moving = resolvedRows(
        ref.watch(sessionMovingObjectCandidatesProvider(activeSessionId)),
      );
      lineRatios = resolvedRows(
        ref.watch(sessionLineRatioProductsProvider(activeSessionId)),
      );
      frameMetrics = resolvedRows(
        ref.watch(sessionFrameQualityMetricsProvider(activeSessionId)),
      );
      tileMetrics = resolvedRows(
        ref.watch(sessionTileMetricsProvider(activeSessionId)),
      );
    } else {
      // No session available — show standalone/quick capture science data
      final sessionlessPhotometry = ref.watch(sessionlessPhotometryProvider);
      track(sessionlessPhotometry);
      photometryObjectId = _reviewedPhotometryObjectId(
        rows: sessionlessPhotometry.valueOrNull ?? const [],
        liveSelection: photometryObjectId,
      );
      lightCurve = ref.watch(sessionlessLightCurveProvider(photometryObjectId));
      transparency = ref.watch(sessionlessTransparencyTrendProvider);
      transparencyRows = resolvedRows(
        ref.watch(sessionlessTransparencySamplesProvider),
      );
      calibrations = resolvedRows(
        ref.watch(sessionlessCalibrationsProvider),
      );
      psfTiles = resolvedRows(ref.watch(sessionlessPsfTilesProvider));
      residuals = resolvedRows(
        ref.watch(sessionlessResidualVectorsProvider),
      );
      moving = resolvedRows(
        ref.watch(sessionlessMovingObjectCandidatesProvider),
      );
      lineRatios = resolvedRows(
        ref.watch(sessionlessLineRatioProductsProvider),
      );
      frameMetrics = resolvedRows(
        ref.watch(sessionlessFrameQualityMetricsProvider),
      );
      tileMetrics = resolvedRows(
        ref.watch(sessionlessTileMetricsProvider),
      );
    }

    // Photometry for the same object across every night that imaged this
    // target — the series a period search actually needs.
    final activeSession = allSessions
        .cast<ImagingSession?>()
        .firstWhere((s) => s?.id == activeSessionId, orElse: () => null);
    final campaignTargetId = activeSession?.targetId;
    var campaignLightCurve = const <LightCurvePoint>[];
    var campaignSessionCount = 0;
    if (campaignTargetId != null) {
      // Same object as the single-night curve above, or the campaign strip
      // would report "no data" for the very star the night below it plots.
      campaignLightCurve = ref
              .watch(targetLightCurveProvider(
                  (campaignTargetId, photometryObjectId)))
              .valueOrNull ??
          const [];
      campaignSessionCount = allSessions
          .where((session) => session.targetId == campaignTargetId)
          .length;
    }

    final latestPsfTiles = _latestPsfSnapshot(psfTiles);
    final latestResiduals = _latestResidualSnapshot(residuals);
    final latestTileMetrics =
        _tileMetricSnapshotForImage(tileMetrics, _selectedFrameImageId);
    // Memoized via Riverpod so a re-render that doesn't change the underlying
    // PSF/residual snapshots reuses the prior analysis instead of recomputing
    // it on every frame (audit §6.20).
    final diagnostics = ref.watch(
      latestSnapshotOpticalTrainDiagnosticsProvider(activeSessionId),
    );
    final latestCal = calibrations.isEmpty ? null : calibrations.last;
    final latestFrameQuality = frameMetrics.isEmpty ? null : frameMetrics.last;
    final selectedFrameQuality =
        _frameQualityForImage(frameMetrics, _selectedFrameImageId);
    final latestTransparencyRow =
        transparencyRows.isEmpty ? null : transparencyRows.last;
    final isNarrow = MediaQuery.sizeOf(context).width < 1080;

    // Pull the underlying captured-image list so the solve-rate card and the
    // insights engine can report on plate-solve health. Same provider the
    // Session tab uses, so Drift only runs the query once.
    final imagesAsync = activeSessionId == null
        ? ref.watch(standaloneImagesProvider)
        : ref.watch(dbSessionImagesProvider(activeSessionId));
    track(imagesAsync);
    final imageList = imagesAsync.valueOrNull ?? const [];
    final lightFrames = imageList
        .where((image) => image.frameType.toLowerCase() == 'light')
        .toList(growable: false);
    final solvedFrames =
        lightFrames.where((image) => image.isPlateSolved).length;
    final calibratedRowCount = calibrations.where((c) => c.isCalibrated).length;

    final photometrySelectionAsync =
        ref.watch(sciencePhotometrySelectionProvider);
    track(photometrySelectionAsync);
    final hasTarget = photometrySelectionAsync.valueOrNull?.target != null;
    final photometryLive =
        photometrySelectionAsync.valueOrNull?.differentialEnabled ?? false;
    final hasPeriodResult = ref.watch(periodAnalysisProvider).result != null;
    final hasExportableData =
        lightCurve.isNotEmpty || moving.isNotEmpty || calibrations.isNotEmpty;

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
    if (allEmpty && (scienceLoading || scienceErrors.isNotEmpty)) {
      return _buildScienceDataState(
        colors,
        activeSessionId: activeSessionId,
        isLoading: scienceLoading,
        errors: scienceErrors,
        storedFrameCount: lightFrames.length,
      );
    }
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
            _sessionBar(
              colors: colors,
              sessions: allSessions,
              activeSessionId: activeSessionId,
              isLive: liveSessionId != null && liveSessionId == activeSessionId,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            // The tab is reporting on a stored session; the banner's other
            // states come from the live pipeline, which is empty after a
            // restart.
            ScienceStatusBanner(storedFrameCount: lightFrames.length),
            const SizedBox(height: NightshadeTokens.spaceLg),
            ScienceSolveRateCard(
              colors: colors,
              lightFrames: lightFrames,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            // The night's narrative is not a science product, so `allEmpty`
            // must not hide it. The operator this branch exists for — imaged
            // all night, no plate solver, therefore no photometry, no PSF
            // tiles, no calibrations — was exactly the operator whose narrator
            // feed was suppressed, along with every detail sheet reachable from
            // it. It renders its own empty state when there is nothing to tell.
            _SectionHeading(
              colors: colors,
              label: 'NIGHT STORY',
              icon: LucideIcons.bookOpen,
            ),
            const SizedBox(height: 12),
            NightStoryTimeline(sessionId: activeSessionId),
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
                // Nothing on this branch to scroll to — there are no charts
                // yet — so "go to photometry" means the live science HUD, not
                // the calibration wizard it used to open.
                onJumpToPhotometry: () => _goPickPhotometryTarget(context),
                onRunCalibration: () => _openCalibrationWizard(context),
                onPickTarget: () => _goPickPhotometryTarget(context),
                onOpenExport: () => _openExportHub(context, const []),
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
          _sessionBar(
            colors: colors,
            sessions: allSessions,
            activeSessionId: activeSessionId,
            isLive: liveSessionId != null && liveSessionId == activeSessionId,
          ),
          const SizedBox(height: 12),
          // P0.2: always-on pipeline status. Tells the user whether science
          // is currently running, idle, or failing — instead of inferring
          // from empty cards.
          ScienceStatusBanner(storedFrameCount: lightFrames.length),
          if (scienceLoading || scienceErrors.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildScienceDataNotice(
              colors,
              activeSessionId: activeSessionId,
              isLoading: scienceLoading,
              errors: scienceErrors,
            ),
          ],
          const SizedBox(height: 12),
          ScienceLadderCard(
            hasCalibration: calibratedRowCount > 0,
            hasTarget: hasTarget,
            photometryLive: photometryLive,
            lightCurvePoints: lightCurve.length,
            hasPeriodResult: hasPeriodResult,
            hasExportableData: hasExportableData,
            onJumpToPhotometry: () => _jumpTo(_sectionKeys.photometry),
            // Rung 1's button says 'Run calibration', so it opens the
            // photometric calibration wizard. It used to scroll to FIELD
            // QUALITY, a section whose only control grades frames — which left
            // the wizard reachable ONLY from the empty-state ladder above, i.e.
            // unreachable the moment the user had any science data at all.
            onRunCalibration: () => _openCalibrationWizard(context),
            // Rung 2 says 'Pick a target'; the PHOTOMETRY section it used to
            // scroll to plots curves and exports them, it does not choose the
            // star.
            onPickTarget: () => _goPickPhotometryTarget(context),
            onOpenExport: () => _openExportHub(context, moving),
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
              onFrameSelected: (imageId) =>
                  setState(() => _selectedFrameImageId = imageId),
            ),
            const SizedBox(height: 12),
            _EquipmentHealthSection(
              colors: colors,
              sessions: allSessions,
              frameMetrics: selectedFrameQuality,
              latestCalibration: latestCal,
              latestTransparency: latestTransparencyRow,
              diagnostics: diagnostics,
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
                        onFrameSelected: (imageId) =>
                            setState(() => _selectedFrameImageId = imageId),
                      ),
                      const SizedBox(height: 12),
                      _EquipmentHealthSection(
                        colors: colors,
                        sessions: allSessions,
                        frameMetrics: selectedFrameQuality,
                        latestCalibration: latestCal,
                        latestTransparency: latestTransparencyRow,
                        diagnostics: diagnostics,
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
          _pairedCards(
            isNarrow,
            _LightCurveChartCard(
              colors: colors,
              lightCurve: lightCurve,
              hubExportButton: lightCurve.isEmpty
                  ? null
                  : const _CardHubExportButton(
                      tooltip: 'Open export hub (Photometry)',
                      dataset: ScienceExportDataset.photometry,
                    ),
            ),
            _SeriesChartCard(
              colors: colors,
              title: 'Transparency Trend',
              yLabel: '%',
              points: transparency
                  .map((point) =>
                      _ChartPoint(point.timestamp, point.transparencyPercent))
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
          if (lightCurve.isNotEmpty && activeSessionId != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _AavsoExportButton(
                colors: colors,
                sessionId: activeSessionId,
              ),
            ),
          const SizedBox(height: 12),
          _pairedCards(
            isNarrow,
            ZeroPointTrendCard(
              colors: colors,
              calibrations: calibrations,
            ),
            SolveRateTrendCard(
              colors: colors,
              lightFrames: lightFrames,
            ),
          ),
          const SizedBox(height: 16),
          PeriodAnalysisPanel(
            colors: colors,
            lightCurve: lightCurve,
            campaignLightCurve: campaignLightCurve,
            campaignSessionCount: campaignSessionCount,
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
          _pairedCards(
            isNarrow,
            HfrTrendCard(
              colors: colors,
              lightFrames: lightFrames,
            ),
            UniformityTrendCard(
              colors: colors,
              frameMetrics: frameMetrics,
              // Same frames as the HFR card beside it.
              rejectedImageIds: {
                for (final frame in lightFrames)
                  if (!frame.isAccepted) frame.id,
              },
            ),
          ),
          const SizedBox(height: 12),
          _pairedCards(
            isNarrow,
            _PsfHeatmapCard(
              colors: colors,
              tiles: latestPsfTiles,
              hubExportButton: latestPsfTiles.isEmpty
                  ? null
                  : const _CardHubExportButton(
                      tooltip: 'Open export hub (PSF tiles)',
                      dataset: ScienceExportDataset.psfTiles,
                    ),
            ),
            _ResidualCard(
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
          _pairedCards(
            isNarrow,
            _MovingObjectCard(
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
            _LineRatioCard(
              colors: colors,
              sessionId: activeSessionId,
              lineRatios: lineRatios,
            ),
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

  Widget _buildSessionIndexState(
    NightshadeColors colors,
    AsyncValue<List<ImagingSession>> sessionsAsync,
  ) {
    final error = sessionsAsync.error;
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          border: Border.all(
            color: error == null
                ? colors.border
                : colors.error.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error == null)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            else
              Icon(LucideIcons.alertTriangle, color: colors.error, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error == null
                        ? 'Loading imaging sessions...'
                        : 'Could not load imaging sessions',
                    style: NightshadeTypography.labelStrong.copyWith(
                      color: error == null ? colors.textPrimary : colors.error,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$error',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(width: 12),
              NightshadeButton(
                label: 'Retry',
                icon: LucideIcons.refreshCw,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                onPressed: () => ref.invalidate(allSessionsProvider),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScienceDataState(
    NightshadeColors colors, {
    required int? activeSessionId,
    required bool isLoading,
    required List<Object> errors,
    required int storedFrameCount,
  }) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScienceStatusBanner(storedFrameCount: storedFrameCount),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _buildScienceDataNotice(
            colors,
            activeSessionId: activeSessionId,
            isLoading: isLoading,
            errors: errors,
          ),
        ],
      ),
    );
  }

  Widget _buildScienceDataNotice(
    NightshadeColors colors, {
    required int? activeSessionId,
    required bool isLoading,
    required List<Object> errors,
  }) {
    final hasError = errors.isNotEmpty;
    final extraErrorCount = errors.length - 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            hasError ? colors.error.withValues(alpha: 0.08) : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(
          color:
              hasError ? colors.error.withValues(alpha: 0.55) : colors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasError)
            Icon(LucideIcons.alertTriangle, color: colors.error, size: 20)
          else
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasError
                      ? 'Some science data could not be loaded'
                      : 'Loading science data...',
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: hasError ? colors.error : colors.textPrimary,
                  ),
                ),
                if (hasError) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${errors.first}'
                    '${extraErrorCount > 0 ? ' (+$extraErrorCount more)' : ''}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                ] else if (isLoading) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Waiting for the current session and frame products.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasError) ...[
            const SizedBox(width: 12),
            NightshadeButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              size: ButtonSize.small,
              variant: ButtonVariant.outline,
              onPressed: () => _retryScienceData(activeSessionId),
            ),
          ],
        ],
      ),
    );
  }

  void _retryScienceData(int? sessionId) {
    ref.invalidate(allSessionsProvider);
    ref.invalidate(sciencePhotometrySelectionProvider);
    if (sessionId == null) {
      ref.invalidate(sessionlessPhotometryProvider);
      ref.invalidate(sessionlessTransparencySamplesProvider);
      ref.invalidate(sessionlessCalibrationsProvider);
      ref.invalidate(sessionlessPsfTilesProvider);
      ref.invalidate(sessionlessResidualVectorsProvider);
      ref.invalidate(sessionlessMovingObjectCandidatesProvider);
      ref.invalidate(sessionlessLineRatioProductsProvider);
      ref.invalidate(sessionlessFrameQualityMetricsProvider);
      ref.invalidate(sessionlessTileMetricsProvider);
      ref.invalidate(standaloneImagesProvider);
      return;
    }
    ref.invalidate(sessionPhotometryProvider(sessionId));
    ref.invalidate(sessionTransparencySamplesProvider(sessionId));
    ref.invalidate(sessionFrameCalibrationsProvider(sessionId));
    ref.invalidate(sessionPsfTilesProvider(sessionId));
    ref.invalidate(sessionResidualVectorsProvider(sessionId));
    ref.invalidate(sessionMovingObjectCandidatesProvider(sessionId));
    ref.invalidate(sessionLineRatioProductsProvider(sessionId));
    ref.invalidate(sessionFrameQualityMetricsProvider(sessionId));
    ref.invalidate(sessionTileMetricsProvider(sessionId));
    ref.invalidate(dbSessionImagesProvider(sessionId));
  }
}

/// The insights panel plus the equipment-health analysis that feeds it.
///
/// Its own [ConsumerWidget] because the three device-state providers below tick
/// roughly once a second while a camera, mount or guider is connected. Watched
/// from the tab's `build`, that heartbeat rebuilt all nine science sections —
/// every chart, the PSF heatmap, the residual painter — on the screen most
/// likely to be open during a run.
class _EquipmentHealthSection extends ConsumerWidget {
  const _EquipmentHealthSection({
    required this.colors,
    required this.sessions,
    required this.frameMetrics,
    required this.latestCalibration,
    required this.latestTransparency,
    required this.diagnostics,
    required this.calibratedFrameCount,
    required this.processedFrameCount,
    required this.solvedFrameCount,
  });

  final NightshadeColors colors;
  final List<ImagingSession> sessions;
  final ScienceFrameQualityMetricsRow? frameMetrics;
  final FramePhotometricCalibrationRow? latestCalibration;
  final TransparencySampleRow? latestTransparency;
  final OpticalTrainDiagnostics? diagnostics;
  final int calibratedFrameCount;
  final int processedFrameCount;
  final int solvedFrameCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final mountState = ref.watch(mountStateProvider);
    // `lastSuccessfulTimestampMs` is 0 — not `DateTime.now()` — where the
    // notifier tracks no heartbeat. Stamping the clock made the analysis input
    // differ on every rebuild by construction, so nothing upstream could ever
    // memoize it, for a field `analyze` does not read.
    final healthReport = const EquipmentHealthService().analyze(
      sessions: sessions,
      deviceHealth: [
        if (cameraState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: cameraState.deviceId!,
            lastSuccessfulTimestampMs: cameraState
                    .lastSuccessfulCommunication?.millisecondsSinceEpoch ??
                0,
            isHealthy: cameraState.isHealthy,
          ),
        if (mountState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: mountState.deviceId!,
            lastSuccessfulTimestampMs: 0,
            isHealthy:
                mountState.connectionState == DeviceConnectionState.connected,
          ),
        if (guiderState.deviceId != null)
          DeviceHealthSnapshot(
            deviceId: guiderState.deviceId!,
            lastSuccessfulTimestampMs: 0,
            isHealthy:
                guiderState.connectionState == DeviceConnectionState.connected,
          ),
      ],
    );

    return ScienceInsightsPanel(
      colors: colors,
      frameMetrics: frameMetrics,
      latestCalibration: latestCalibration,
      latestTransparency: latestTransparency,
      diagnostics: diagnostics,
      healthReport: healthReport,
      calibratedFrameCount: calibratedFrameCount,
      processedFrameCount: processedFrameCount,
      solvedFrameCount: solvedFrameCount,
    );
  }
}
