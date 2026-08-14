// ignore_for_file: invalid_use_of_protected_member
// Part of ../science_analytics_tab.dart -- extracted for maintainability.
//
// Navigation helpers, session bar, paired cards and science-data state sections.
part of '../science_analytics_tab.dart';

extension _ScienceAnalyticsTabSections on _ScienceAnalyticsTabState {
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
    bool offerQuickCaptures = false,
  }) {
    if (sessions.isEmpty && !offerQuickCaptures) return const SizedBox.shrink();
    final quickCapturesPinned =
        offerQuickCaptures && activeSessionId == kQuickCaptureSessionSelection;
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
                value: quickCapturesPinned
                    ? kQuickCaptureSessionSelection
                    : active?.id,
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
                  // Same entry, same wording as Diagnostics and Session: the
                  // sessionless photometry / field-quality products are a real
                  // night's work and must stay reachable once a run exists.
                  if (offerQuickCaptures)
                    DropdownMenuItem<int>(
                      value: kQuickCaptureSessionSelection,
                      child: Text(
                        kQuickCaptureSessionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
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
    List<ImagingSession> sessions = const [],
    bool offerQuickCaptures = false,
    bool isLive = false,
  }) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The picker belongs here too: this branch is exactly when the
          // operator most wants to point the tab at a different night, and
          // dropping it meant a science query that was slow or failing took
          // the only way out of that session with it.
          _sessionBar(
            colors: colors,
            sessions: sessions,
            activeSessionId: activeSessionId,
            offerQuickCaptures: offerQuickCaptures,
            isLive: isLive,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
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
