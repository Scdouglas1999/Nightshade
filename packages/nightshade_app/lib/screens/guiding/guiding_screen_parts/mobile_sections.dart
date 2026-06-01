// Part of ../guiding_screen.dart -- extracted for maintainability.
//
// Mobile tab layout and compact guiding controls.
part of '../guiding_screen.dart';

mixin _GuidingMobileSections
    on
        ConsumerState<GuidingScreen>,
        _GuidingStateFields,
        _GuidingDesktopSections {
  Widget _buildMobileLayout(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    return Column(
      children: [
        // Guide graph — shares vertical space like desktop (Expanded, not fixed 220).
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _buildCenterPanel(colors, guideStats),
          ),
        ),
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.border),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Use smaller text and icon-only tabs on very narrow screens
              final isVeryNarrow = constraints.maxWidth < 340;
              final isNarrow = constraints.maxWidth < 400;
              return TabBar(
                controller: _tabController,
                labelColor: colors.primary,
                unselectedLabelColor: colors.textSecondary,
                indicatorColor: colors.primary,
                indicatorWeight: 2,
                // Make tabs scrollable on very narrow screens to prevent overflow
                isScrollable: isVeryNarrow,
                tabAlignment: isVeryNarrow ? TabAlignment.start : null,
                labelPadding: isVeryNarrow
                    ? const EdgeInsets.symmetric(horizontal: 12)
                    : null,
                labelStyle: TextStyle(
                  fontSize: isNarrow ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: isNarrow ? 11 : 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(
                    icon: Icon(LucideIcons.star, size: isNarrow ? 16 : 18),
                    text: isVeryNarrow ? null : 'Star View',
                    iconMargin: isVeryNarrow
                        ? EdgeInsets.zero
                        : const EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    icon: Icon(LucideIcons.sliders, size: isNarrow ? 16 : 18),
                    text: isVeryNarrow ? null : 'Controls',
                    iconMargin: isVeryNarrow
                        ? EdgeInsets.zero
                        : const EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    icon: Icon(LucideIcons.settings, size: isNarrow ? 16 : 18),
                    text: isVeryNarrow ? null : 'Settings',
                    iconMargin: isVeryNarrow
                        ? EdgeInsets.zero
                        : const EdgeInsets.only(bottom: 4),
                  ),
                ],
              );
            },
          ),
        ),
        // Tab content
        Expanded(
          flex: 3,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Star View tab - Guide Star, Target Display, Star Statistics
              _buildMobileStarViewTab(colors, isConnected, guideStats),
              // Controls tab - Guiding controls and calibration
              _buildMobileControlsTab(colors, isConnected, phd2State),
              // Settings tab - Brain settings
              _buildMobileSettingsTab(colors),
            ],
          ),
        ),
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
                    borderRadius: BorderRadius.circular(8),
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
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Configure RA and Dec guide algorithm parameters for fine-tuning guiding performance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
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
