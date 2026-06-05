// Part of ../guiding_screen.dart -- extracted for maintainability.
//
// Mobile tab layout and compact guiding controls.
part of '../guiding_screen.dart';

mixin _GuidingMobileSections
    on
        ConsumerState<GuidingScreen>,
        _GuidingStateFields,
        _GuidingDesktopSections {
  /// Minimum height the live guide graph is given on a phone so it never
  /// collapses to an unreadable sliver — especially in landscape where the
  /// viewport height is small. The graph stays mounted (so it keeps streaming)
  /// in both orientations because the same [_buildCenterPanel] instance is the
  /// `start`/top pane in either branch.
  static const double _phoneGraphMinHeight = 200.0;

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
    final graph = Padding(
      padding: const EdgeInsets.all(12),
      child: _buildCenterPanel(colors, guideStats),
    );
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
          final isLandscape = constraints.maxWidth > constraints.maxHeight;

          // Landscape with enough width: graph beside controls. TwoPane keeps
          // both panes mounted so the graph keeps streaming.
          if (isLandscape && constraints.maxWidth >= 560) {
            return TwoPane(
              start: graph,
              end: tabs,
              startFlex: 3,
              endFlex: 2,
            );
          }

          // Portrait / narrow landscape: stack. Give the graph a fixed,
          // legible height (clamped to leave room for the tab section) and let
          // the tabbed controls take the remainder.
          final graphHeight = (constraints.maxHeight * 0.42)
              .clamp(_phoneGraphMinHeight, constraints.maxHeight * 0.6);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: graphHeight, child: graph),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: AdaptiveTabBar(
            horizontalPadding: 8,
            selectedIndex: _tabController.index,
            onSelected: (i) {
              _tabController.index = i;
              setState(() {});
            },
            tabs: const [
              AdaptiveTab(label: 'Star View', icon: LucideIcons.star),
              AdaptiveTab(label: 'Controls', icon: LucideIcons.sliders),
              AdaptiveTab(label: 'Settings', icon: LucideIcons.settings),
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
                        icon: LucideIcons.star,
                        trailing: isConnected
                            ? IconButton(
                                icon: Icon(LucideIcons.refreshCw,
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
                              statusMessage: 'Waiting for image...',
                            ),
                            error: (_, __) => GuideStarView(
                              key: GuidingTutorialKeys.starView,
                              statusMessage: 'No star selected',
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
                        icon: LucideIcons.target,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: GuideTargetDisplay(
                            key: GuidingTutorialKeys.targetDisplay,
                            errorHistory: errorHistory
                                .map((e) => GuideErrorPoint(
                                      raError: e.raError,
                                      decError: e.decError,
                                      timestamp: e.timestamp,
                                    ))
                                .toList(),
                            currentRaError: currentError?.raError ?? 0,
                            currentDecError: currentError?.decError ?? 0,
                            scaleArcsec: _yScale.arcsec / 2,
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
                    icon: LucideIcons.star,
                    trailing: isConnected
                        ? IconButton(
                            icon: Icon(LucideIcons.refreshCw,
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
                          statusMessage: 'Waiting for image...',
                        ),
                        error: (_, __) => GuideStarView(
                          key: GuidingTutorialKeys.starView,
                          statusMessage: 'No star selected',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildGlassCard(
                    colors,
                    title: 'Target Display',
                    icon: LucideIcons.target,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GuideTargetDisplay(
                        key: GuidingTutorialKeys.targetDisplay,
                        errorHistory: errorHistory
                            .map((e) => GuideErrorPoint(
                                  raError: e.raError,
                                  decError: e.decError,
                                  timestamp: e.timestamp,
                                ))
                            .toList(),
                        currentRaError: currentError?.raError ?? 0,
                        currentDecError: currentError?.decError ?? 0,
                        scaleArcsec: _yScale.arcsec / 2,
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
            icon: LucideIcons.activity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatRow('SNR', stats.snr.toStringAsFixed(1),
                    _getSnrColor(stats.snr, colors), colors),
                const SizedBox(height: 10),
                _buildStatRow('Star Mass', stats.starMass.toStringAsFixed(0),
                    colors.textPrimary, colors),
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
                  ref.read(phd2ControllerProvider).startGuiding(),
              onStopGuiding: () =>
                  ref.read(phd2ControllerProvider).stopGuiding(),
              onLoop: () => ref.read(phd2ControllerProvider).loop(),
              onFindStar: () =>
                  ref.read(lockPositionProvider.notifier).findStar(),
              onDeselectStar: () => _deselectStar(),
              onDither: () => ref.read(phd2ControllerProvider).dither(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: CalibrationPanel(
              state: calibrationData.isCalibrated
                  ? CalibrationState.calibrated
                  : CalibrationState.notCalibrated,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSettingsTab(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeButton(
            key: GuidingTutorialKeys.brainBtn,
            label:
                _showBrainPanel ? 'Hide Brain Settings' : 'Show Brain Settings',
            icon: LucideIcons.brain,
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: NightshadeTokens.borderRadiusInline8,
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.brain,
                        size: 48,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'PHD2 Brain Settings',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: NightshadeTypography.fontSize16,
                        ),
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
