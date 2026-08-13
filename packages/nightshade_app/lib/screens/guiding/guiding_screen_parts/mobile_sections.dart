// Part of ../guiding_screen.dart -- extracted for maintainability.
//
// Mobile tab layout and compact guiding controls.
part of '../guiding_screen.dart';

mixin _GuidingMobileSections
    on
        ConsumerState<GuidingScreen>,
        _GuidingStateFields,
        _GuidingDesktopSections {
  /// Preferred height the live guide graph is given on a phone so it never
  /// collapses to an unreadable sliver — especially in landscape where the
  /// viewport height is small. The graph stays mounted (so it keeps streaming)
  /// in both orientations because the same [_buildCenterPanel] instance is the
  /// `start`/top pane in either branch.
  ///
  /// This is a *preference*, not a hard floor: [_stackedGraphHeight] caps it
  /// against the ceiling so the two bounds can never invert.
  static const double _phoneGraphMinHeight = 200.0;

  /// Height below which the stacked layout trades chrome for content — the
  /// graph panel's outer gutter shrinks so the plot keeps a usable share of a
  /// short viewport instead of spending it on padding.
  static const double _phoneCompactHeight = 380.0;

  /// Height of the graph pane in the stacked (portrait / narrow landscape)
  /// phone layout.
  ///
  /// Total-order safe by construction: the preferred height is raised to
  /// [_phoneGraphMinHeight] and only then capped at 60% of what is available,
  /// so a short viewport (a persistent banner above this screen, a small
  /// device, a split-screen window) degrades to the cap instead of inverting a
  /// clamp's bounds and throwing.
  static double _stackedGraphHeight(double availableHeight) {
    final ceiling = availableHeight * 0.6;
    final preferred = math.max(availableHeight * 0.42, _phoneGraphMinHeight);
    return math.min(preferred, ceiling);
  }

  Widget _buildMobileLayout(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    // The graph is the dominant, always-mounted element. The tabbed controls
    // are the secondary region. In phone landscape we place them side-by-side
    // (graph left, controls right) via TwoPane; in portrait they stack with the
    // graph pinned to a sensible min height and the tabs filling the rest.
    final tabs = _buildMobileTabSection(
      colors,
      isConnected,
      phd2State,
      guideStats,
    );

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The shared app shell may already have consumed a modal keyboard's
          // inset before this backing route is laid out. At the resulting
          // near-zero height neither the graph nor the tab chrome is usable;
          // keep the covered background quiet instead of overflowing behind
          // the PHD2 dialog.
          if (constraints.maxHeight < 80) {
            return ColoredBox(color: colors.background);
          }
          final isLandscape = constraints.maxWidth > constraints.maxHeight;

          Widget graphPane(double gutter) => Padding(
                padding: EdgeInsets.all(gutter),
                child: _buildCenterPanel(colors, guideStats),
              );

          // Landscape with enough width: graph beside controls. TwoPane keeps
          // both panes mounted so the graph keeps streaming, and each pane
          // already has the full viewport height to work with.
          if (isLandscape && constraints.maxWidth >= 560) {
            return TwoPane(
              start: graphPane(NightshadeTokens.spaceMd),
              end: tabs,
              startFlex: 3,
              endFlex: 2,
            );
          }

          // Portrait / narrow landscape: stack. Give the graph its preferred
          // legible height, capped to leave room for the tab section, and let
          // the tabbed controls take the remainder. Here the graph only gets a
          // fraction of the viewport, so a short one spends its gutter on the
          // plot instead.
          final graphHeight = _stackedGraphHeight(constraints.maxHeight);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: graphHeight,
                child: graphPane(
                  constraints.maxHeight < _phoneCompactHeight
                      ? NightshadeTokens.spaceSm
                      : NightshadeTokens.spaceMd,
                ),
              ),
              Expanded(child: tabs),
            ],
          );
        },
      ),
    );
  }

  /// The Star / Controls / Settings tab section used in both phone
  /// orientations. Uses [AdaptiveTabBar] so the tab row never overflows at
  /// 360 px (it collapses to icons / scrolls), and a hand-driven body switch
  /// (instead of TabBarView) so it composes inside [TwoPane] without needing a
  /// bounded width from a Material TabBar.
  Widget _buildMobileTabSection(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    final Widget body;
    switch (_tabController.index) {
      case 1:
        body = _buildMobileControlsTab(colors, isConnected, phd2State);
        break;
      case 2:
        body = _buildMobileSettingsTab(colors);
        break;
      case 0:
      default:
        body = _buildMobileStarViewTab(colors, isConnected, guideStats);
        break;
    }

    // Title + sub-tabs share ONE row (this section had no title row of its own
    // above the tabs — the outer nav named the screen). Fold the title inline
    // to the left of the tab strip; this section is phone-only so the icon-only
    // form is what renders, but the label is gated on the same `!isPhone` check
    // the other screens use for consistency.
    final isPhone = Responsive.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: NightshadeTokens.spaceLg,
                  right: isPhone
                      ? NightshadeTokens.spaceSm
                      : NightshadeTokens.spaceMd,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      NightshadeIcons.guider,
                      size: 18,
                      color: colors.primary,
                    ),
                    if (!isPhone) ...[
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Text(
                        'Guiding',
                        style: NightshadeTypography.h5.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: AdaptiveTabBar(
                  horizontalPadding: 8,
                  selectedIndex: _tabController.index,
                  onSelected: (i) {
                    _tabController.index = i;
                    setState(() {});
                  },
                  tabs: const [
                    AdaptiveTab(label: 'Star View', icon: NightshadeIcons.star),
                    AdaptiveTab(
                        label: 'Controls', icon: NightshadeIcons.sliders),
                    AdaptiveTab(
                        label: 'Settings', icon: NightshadeIcons.settings),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildMobileStarViewTab(
    NightshadeColors colors,
    bool isConnected,
    Phd2GuideStats stats,
  ) {
    final starImage = ref.watch(starImageProvider);
    final errorHistory = ref.watch(targetDisplayHistoryProvider);
    final currentError = errorHistory.isNotEmpty ? errorHistory.last : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Guide Star and Target Display side by side on wider phones
          LayoutBuilder(
            builder: (context, constraints) {
              // If width allows, show side by side
              if (constraints.maxWidth > 400) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildGlassCard(
                        colors,
                        title: 'Guide Star',
                        icon: NightshadeIcons.star,
                        trailing: isConnected
                            ? IconButton(
                                icon: Icon(NightshadeIcons.refresh,
                                    size: 14, color: colors.textSecondary),
                                onPressed: () => ref
                                    .read(starImageProvider.notifier)
                                    .refresh(),
                                tooltip: 'Refresh',
                                constraints: const BoxConstraints(
                                    minWidth: 44, minHeight: 44),
                                padding: EdgeInsets.zero,
                              )
                            : null,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: starImage.when(
                            data: (image) => GuideStarView(
                              key: GuidingTutorialKeys.starView,
                              pixels: image.pixels,
                              width: image.width,
                              height: image.height,
                              starX: image.starX,
                              starY: image.starY,
                              snr: stats.snr,
                              showCrosshairs: true,
                              onStarSelected: isConnected
                                  ? (x, y) => _selectStar(x, y)
                                  : null,
                              statusMessage: 'No star selected',
                            ),
                            loading: () => GuideStarView(
                              key: GuidingTutorialKeys.starView,
                              statusMessage: _starViewIdleMessage(),
                            ),
                            error: (_, __) => GuideStarView(
                              key: GuidingTutorialKeys.starView,
                              statusMessage: 'Guide star image unavailable',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassCard(
                        colors,
                        title: 'Target Display',
                        icon: NightshadeIcons.target,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: GuideTargetDisplay(
                            key: GuidingTutorialKeys.targetDisplay,
                            errorHistory: errorHistory
                                .map((e) => GuideErrorPoint(
                                      raError: _errorForDisplay(
                                          e.raError, stats.pixelScale),
                                      decError: _errorForDisplay(
                                          e.decError, stats.pixelScale),
                                      timestamp: e.timestamp,
                                    ))
                                .toList(),
                            showCurrentError: currentError != null,
                            currentRaError: _errorForDisplay(
                                currentError?.raError ?? 0, stats.pixelScale),
                            currentDecError: _errorForDisplay(
                                currentError?.decError ?? 0, stats.pixelScale),
                            scaleArcsec: _yScale.arcsec / 2,
                            unitSuffix: _errorUnit(stats.pixelScale),
                            numRings: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              // Stack vertically on narrow phones
              return Column(
                children: [
                  _buildGlassCard(
                    colors,
                    title: 'Guide Star',
                    icon: NightshadeIcons.star,
                    trailing: isConnected
                        ? IconButton(
                            icon: Icon(NightshadeIcons.refresh,
                                size: 14, color: colors.textSecondary),
                            onPressed: () =>
                                ref.read(starImageProvider.notifier).refresh(),
                            tooltip: 'Refresh',
                            constraints: const BoxConstraints(
                                minWidth: 44, minHeight: 44),
                            padding: EdgeInsets.zero,
                          )
                        : null,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: starImage.when(
                        data: (image) => GuideStarView(
                          key: GuidingTutorialKeys.starView,
                          pixels: image.pixels,
                          width: image.width,
                          height: image.height,
                          starX: image.starX,
                          starY: image.starY,
                          snr: stats.snr,
                          showCrosshairs: true,
                          onStarSelected:
                              isConnected ? (x, y) => _selectStar(x, y) : null,
                          statusMessage: 'No star selected',
                        ),
                        loading: () => GuideStarView(
                          key: GuidingTutorialKeys.starView,
                          statusMessage: _starViewIdleMessage(),
                        ),
                        error: (_, __) => GuideStarView(
                          key: GuidingTutorialKeys.starView,
                          statusMessage: 'Guide star image unavailable',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildGlassCard(
                    colors,
                    title: 'Target Display',
                    icon: NightshadeIcons.target,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GuideTargetDisplay(
                        key: GuidingTutorialKeys.targetDisplay,
                        errorHistory: errorHistory
                            .map((e) => GuideErrorPoint(
                                  raError: _errorForDisplay(
                                      e.raError, stats.pixelScale),
                                  decError: _errorForDisplay(
                                      e.decError, stats.pixelScale),
                                  timestamp: e.timestamp,
                                ))
                            .toList(),
                        showCurrentError: currentError != null,
                        currentRaError: _errorForDisplay(
                            currentError?.raError ?? 0, stats.pixelScale),
                        currentDecError: _errorForDisplay(
                            currentError?.decError ?? 0, stats.pixelScale),
                        scaleArcsec: _yScale.arcsec / 2,
                        unitSuffix: _errorUnit(stats.pixelScale),
                        numRings: 3,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Star stats
          _buildGlassCard(
            colors,
            title: 'Star Statistics',
            icon: NightshadeIcons.activity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatRow('SNR', _starMetricText(stats.snr),
                    _getSnrColor(stats.snr, colors), colors),
                const SizedBox(height: 10),
                _buildStatRow(
                    'Star Mass',
                    _starMetricText(stats.starMass, decimals: 0),
                    stats.starMass > 0 ? colors.textPrimary : colors.textMuted,
                    colors),
                const SizedBox(height: 10),
                _buildStatRow('Frame Count', stats.frameCount.toString(),
                    colors.textPrimary, colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileControlsTab(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
  ) {
    final calibrationData = ref.watch(calibrationStateProvider);
    final guiderId = ref.watch(guiderStateProvider).deviceId;
    final isPhd2Guider = guiderId == null || isPhd2DeviceId(guiderId);
    final settingsAsync = ref.watch(appSettingsProvider);
    final canPersistGuidingSettings = settingsAsync.hasValue &&
        !settingsAsync.isLoading &&
        !settingsAsync.hasError;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: GuideControlsPanel(
              key: GuidingTutorialKeys.controls,
              state: _mapPhd2State(phd2State),
              isConnected: isConnected,
              onStartGuiding: () =>
                  ref.read(phd2ControllerProvider).startGuiding(
                        settlePixels: _settlePixels,
                        settleTime: _settleTime,
                        settleTimeout: _settleTimeout,
                      ),
              onStopGuiding: () =>
                  ref.read(phd2ControllerProvider).stopGuiding(),
              onPauseGuiding: isPhd2Guider
                  ? () => ref.read(phd2ControllerProvider).pauseGuiding()
                  : null,
              onResumeGuiding: isPhd2Guider
                  ? () => ref.read(phd2ControllerProvider).resumeGuiding()
                  : null,
              pauseUnavailableReason:
                  isPhd2Guider ? null : kBuiltinGuiderNoPauseReason,
              onLoop: () => ref.read(phd2ControllerProvider).loop(),
              onFindStar: () =>
                  ref.read(lockPositionProvider.notifier).findStar(),
              onDeselectStar: _deselectStar,
              ditherAmount: _ditherAmount,
              ditherRaOnly: _ditherRaOnly,
              onDitherAmountChanged:
                  canPersistGuidingSettings ? _setDitherAmount : null,
              onDitherRaOnlyChanged:
                  canPersistGuidingSettings ? _setDitherRaOnly : null,
              onDither: () => ref.read(phd2ControllerProvider).dither(
                    amount: _ditherAmount,
                    raOnly: _ditherRaOnly,
                    settlePixels: _settlePixels,
                    settleTime: _settleTime,
                    settleTimeout: _settleTimeout,
                  ),
              settlePixels: _settlePixels,
              settleTime: _settleTime,
              settleTimeout: _settleTimeout,
              onSettlePixelsChanged:
                  canPersistGuidingSettings ? _setSettlePixels : null,
              onSettleTimeChanged:
                  canPersistGuidingSettings ? _setSettleTime : null,
              onSettleTimeoutChanged:
                  canPersistGuidingSettings ? _setSettleTimeout : null,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: isPhd2Guider
                ? CalibrationPanel(
                    state: calibrationData.isCalibrated
                        ? CalibrationState.calibrated
                        : (phd2State == Phd2State.calibrating
                            ? CalibrationState.calibrating
                            : CalibrationState.notCalibrated),
                    data: CalibrationData(
                      hasCalibration: calibrationData.isCalibrated,
                      raAngle: calibrationData.rotationAngle,
                      decAngle: null,
                      raRate: calibrationData.raRate,
                      decRate: calibrationData.decRate,
                    ),
                    isConnected: isConnected,
                    onClearCalibration: () => _clearCalibration(),
                    onFlipCalibration: () => _flipCalibration(),
                  )
                : _buildNonPhd2GuiderInfo(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSettingsTab(NightshadeColors colors) {
    final guiderId = ref.watch(guiderStateProvider).deviceId;
    final isPhd2Guider = guiderId == null || isPhd2DeviceId(guiderId);

    if (!isPhd2Guider) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NightshadeButton(
              key: GuidingTutorialKeys.brainBtn,
              label: 'Open Guider Settings',
              icon: NightshadeIcons.settings,
              variant: ButtonVariant.outline,
              onPressed: () => context.go('/equipment'),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildNonPhd2GuiderInfo(colors)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeButton(
            key: GuidingTutorialKeys.brainBtn,
            label:
                _showBrainPanel ? 'Hide Brain Settings' : 'Show Brain Settings',
            icon: NightshadeIcons.brain,
            variant:
                _showBrainPanel ? ButtonVariant.primary : ButtonVariant.outline,
            onPressed: () => setState(() => _showBrainPanel = !_showBrainPanel),
          ),
          const SizedBox(height: 12),
          if (_showBrainPanel)
            Expanded(
              child: _buildBrainPanel(colors),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: NightshadeCard(
                  variant: CardVariant.subtle,
                  borderRadius: NightshadeTokens.radiusInline8,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        NightshadeIcons.brain,
                        size: 48,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'PHD2 Brain Settings',
                        style: NightshadeTypography.h4
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Configure RA and Dec guide algorithm parameters for fine-tuning guiding performance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: NightshadeTypography.fontSize13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
