// Desktop layout, shared panels, value formatting, and guiding actions.
part of '../guiding_screen.dart';

mixin _GuidingDesktopSections
    on ConsumerState<GuidingScreen>, _GuidingStateFields, _GuidingActions {
  Widget _buildDesktopLayout(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate panel widths based on available space
        // Minimum space needed: 2 side panels + graph + gaps
        final availableWidth =
            constraints.maxWidth - 32; // Account for outer padding
        final isCompact = availableWidth < 900;

        // Below 900px use fractional widths so side panels scale with viewport.
        final leftPanelWidth = isCompact
            ? availableWidth * 0.26
            : Responsive.value(
                context,
                mobile: 240.0,
                tablet: 240.0,
                desktop: 280.0,
              );
        final rightPanelWidth = isCompact
            ? availableWidth * 0.30
            : Responsive.value(
                context,
                mobile: 260.0,
                tablet: 260.0,
                desktop: 300.0,
              );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Left panel - Star view, Target display, Star stats
              SizedBox(
                width: leftPanelWidth,
                child: _buildLeftPanel(colors, isConnected, guideStats),
              ),
              const SizedBox(width: 16),
              // Center panel - Graph
              Expanded(
                child: _buildCenterPanel(colors, guideStats),
              ),
              const SizedBox(width: 16),
              // Right panel - Controls
              SizedBox(
                width: rightPanelWidth,
                child: _buildRightPanel(colors, isConnected, phd2State),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    final stateColor = _getStateColor(phd2State);
    final hasRmsSamples = guideStats.frameCount > 0;
    final guiderState = ref.watch(guiderStateProvider);
    final guiderId = guiderState.deviceId;
    final isPhd2Guider = guiderId == null || isPhd2DeviceId(guiderId);
    final isBuiltinGuider = guiderId == builtinGuiderDeviceId;
    final connectedLabel = isBuiltinGuider
        ? 'Built-in Guider Connected'
        : isPhd2Guider
            ? 'PHD2 Connected'
            : '${guiderState.deviceName ?? 'Guider'} Connected';
    final disconnectedLabel = isPhd2Guider
        ? 'PHD2 Disconnected'
        : '${guiderState.deviceName ?? 'Guider'} Disconnected';
    // Track the same phone-viewport check as the layout swap in
    // guiding_screen.dart so a phone in landscape gets the compact status bar.
    final isMobile = _isPhoneViewport(context);

    return Container(
      key: GuidingTutorialKeys.statusBar,
      height: isMobile ? 52 : 56,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Leading status group (connection dot, label, state pill). Wrapped
          // in Expanded so it claims ALL horizontal slack and the trailing
          // action buttons (Connect/Disconnect + Settings) pin to the far
          // right of the bar. A bare Spacer here would split the slack with the
          // loose state pill, leaving the actions floating near the centre.
          Expanded(
            child: Row(
              children: [
                // Connection status indicator
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? colors.success : colors.error,
                  ),
                ),
                const SizedBox(width: 10),
                if (!isMobile)
                  Text(
                    isConnected ? connectedLabel : disconnectedLabel,
                    style: NightshadeTypography.label
                        .copyWith(color: colors.textPrimary),
                  ),
                SizedBox(width: isMobile ? 8 : 20),
                // State indicator pill — flexible so a long label (e.g.
                // "Calibrating") ellipsizes instead of overflowing on a narrow
                // phone.
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 8 : 12,
                      vertical: 5,
                    ),
                    decoration: NightshadeDecorations.statusChip(
                      stateColor,
                      borderRadius: NightshadeTokens.borderRadiusMd,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: stateColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _getStateLabel(phd2State),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: stateColor,
                              fontWeight: FontWeight.w600,
                              fontSize: isMobile ? 11 : 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // RMS display - compact on mobile (key only on mobile, desktop uses graph header)
          if (phd2State == Phd2State.guiding) ...[
            if (isMobile) ...[
              // Show only total RMS on mobile with key
              Container(
                key: GuidingTutorialKeys.rmsDisplay,
                child: _buildRmsChip('Total', guideStats.rmsTotal,
                    guideStats.pixelScale, colors.primary, colors,
                    bold: true, compact: true, hasSamples: hasRmsSamples),
              ),
            ] else ...[
              // Desktop shows RMS in graph header, not here
              _buildRmsChip('RA', guideStats.rmsRa, guideStats.pixelScale,
                  colors.error, colors,
                  hasSamples: hasRmsSamples),
              const SizedBox(width: 10),
              _buildRmsChip('Dec', guideStats.rmsDec, guideStats.pixelScale,
                  colors.info, colors,
                  hasSamples: hasRmsSamples),
              const SizedBox(width: 10),
              _buildRmsChip('Total', guideStats.rmsTotal, guideStats.pixelScale,
                  colors.primary, colors,
                  bold: true, hasSamples: hasRmsSamples),
            ],
            SizedBox(width: isMobile ? 8 : 20),
          ] else if (isMobile) ...[
            // Keep star panel mounted on mobile when not guiding
            Container(
              key: GuidingTutorialKeys.rmsDisplay,
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusInline4,
              ),
              child: Text(
                'RMS: --',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: NightshadeTypography.fontSize10,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Connect/Disconnect button. While a connect is in flight the guider
          // sits in the `connecting` state — show a disabled, spinning
          // "Connecting…" affordance so a second tap can't launch/socket PHD2
          // again (connect is not abortable mid-flight, so both actions wait).
          if (guiderState.connectionState == DeviceConnectionState.connecting)
            NightshadeButton(
              key: GuidingTutorialKeys.connectBtn,
              label: isMobile ? '' : 'Connecting…',
              icon: NightshadeIcons.connected,
              size: ButtonSize.small,
              isLoading: true,
              onPressed: null,
            )
          else if (!isConnected && isPhd2Guider)
            NightshadeButton(
              key: GuidingTutorialKeys.connectBtn,
              label: isMobile ? '' : 'Connect',
              icon: NightshadeIcons.connected,
              size: ButtonSize.small,
              onPressed: () => connectPhd2(ref, context: context),
            )
          else if (isConnected)
            NightshadeButton(
              key: GuidingTutorialKeys.connectBtn,
              label: isMobile ? '' : 'Disconnect',
              icon: LucideIcons.plugZap,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => isPhd2Guider
                  ? disconnectPhd2(ref, context: context)
                  : _disconnectActiveGuider(),
            )
          else
            NightshadeButton(
              key: GuidingTutorialKeys.connectBtn,
              label: isMobile ? '' : 'Equipment',
              icon: NightshadeIcons.guider,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => context.go('/equipment'),
            ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusInline8,
            ),
            child: IconButton(
              icon: Icon(NightshadeIcons.settings,
                  color: colors.textSecondary, size: 18),
              onPressed: () => isPhd2Guider
                  ? _showConnectionDialog()
                  : context.go('/equipment'),
              tooltip:
                  isPhd2Guider ? 'PHD2 Connection Settings' : 'Guider Settings',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(
      NightshadeColors colors, bool isConnected, Phd2GuideStats stats) {
    final starImage = ref.watch(starImageProvider);
    final errorHistory = ref.watch(targetDisplayHistoryProvider);
    final currentError = errorHistory.isNotEmpty ? errorHistory.last : null;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Star view
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
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
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
                  statusMessage: _starViewIdleMessage(),
                ),
                error: (_, __) => const GuideStarView(
                  statusMessage: 'Guide star image unavailable',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Target display
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
                          raError:
                              _errorForDisplay(e.raError, stats.pixelScale),
                          decError:
                              _errorForDisplay(e.decError, stats.pixelScale),
                          timestamp: e.timestamp,
                        ))
                    .toList(),
                // Absent error coalesced to 0 put the marker exactly on the
                // bullseye while the guider was stopped with nothing measured,
                // which reads as perfect guiding rather than as no reading.
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
          const SizedBox(height: 12),
          // Star stats - fixed height card instead of Expanded to prevent overflow
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
                _buildStatRow(
                    'Frame Count',
                    _frameCountText(stats, ref.watch(phd2StateProvider)),
                    colors.textPrimary,
                    colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard(
    NightshadeColors colors, {
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    // Use responsive padding - more compact on phone-tier screens
    final isMobile = _isPhoneViewport(context);
    final headerPadding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    final iconSize = isMobile ? 12.0 : 14.0;
    final iconPadding = isMobile ? 4.0 : 6.0;
    final titleFontSize = isMobile ? 12.0 : 13.0;
    final contentPadding = isMobile ? 8.0 : 12.0;

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: headerPadding,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Icon(icon, size: iconSize, color: colors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: titleFontSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing,
                ],
              ],
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.all(contentPadding),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Pane height below which the graph card drops its own title row on a
  /// phone. The title costs ~38 dp of a pane that a banner-squeezed viewport
  /// can cut to ~120 dp, and it is the least load-bearing thing in the card —
  /// the screen is already named Guiding, the scale selectors stay, and the
  /// plot is what the user came for.
  static const double _graphTitleMinPaneHeight = 220.0;

  Widget _buildCenterPanel(NightshadeColors colors, Phd2GuideStats stats) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildGraphCard(
        colors,
        stats,
        showTitle: !_isPhoneViewport(context) ||
            constraints.maxHeight >= _graphTitleMinPaneHeight,
      ),
    );
  }

  Widget _buildGraphCard(
    NightshadeColors colors,
    Phd2GuideStats stats, {
    required bool showTitle,
  }) {
    final graphData = ref.watch(guideGraphProvider);
    final hasRmsSamples = stats.frameCount > 0;
    final isMobile = _isPhoneViewport(context);
    final iconSize = isMobile ? 12.0 : 14.0;
    final iconPadding = isMobile ? 4.0 : 6.0;
    final titleFontSize = isMobile ? 12.0 : 13.0;

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          if (showTitle)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 16,
                vertical: isMobile ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: NightshadeTokens.borderRadiusMd,
                    ),
                    child: Icon(NightshadeIcons.chart,
                        size: iconSize, color: colors.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Guide Graph',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: titleFontSize,
                    ),
                  ),
                  const Spacer(),
                  // RMS display in header - hide on mobile (shown in status bar)
                  if (!isMobile)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          key: GuidingTutorialKeys.rmsDisplay,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCompactRms('RA', stats.rmsRa,
                                stats.pixelScale, colors.error, colors,
                                hasSamples: hasRmsSamples),
                            const SizedBox(width: 12),
                            _buildCompactRms('Dec', stats.rmsDec,
                                stats.pixelScale, colors.info, colors,
                                hasSamples: hasRmsSamples),
                            const SizedBox(width: 12),
                            _buildCompactRms('Total', stats.rmsTotal,
                                stats.pixelScale, colors.primary, colors,
                                bold: true, hasSamples: hasRmsSamples),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Graph content
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 8 : 12),
              child: GuideGraphAdvanced(
                key: GuidingTutorialKeys.graph,
                data: graphData
                    .map((p) => GuideDataPoint(
                          timestamp: p.time,
                          raError: _errorForDisplay(p.ra, stats.pixelScale),
                          decError: _errorForDisplay(p.dec, stats.pixelScale),
                        ))
                    .toList(),
                valueUnit: _errorUnit(stats.pixelScale),
                timeScale: _timeScale,
                yScale: _yScale,
                // Values are converted here (and nulled out when nothing has
                // been measured) so the graph's own stats row cannot label raw
                // pixels as arcseconds or print a fabricated 0.00.
                rmsRa: hasRmsSamples
                    ? _rmsReadout(stats.rmsRa, stats.pixelScale).value
                    : null,
                rmsDec: hasRmsSamples
                    ? _rmsReadout(stats.rmsDec, stats.pixelScale).value
                    : null,
                rmsTotal: hasRmsSamples
                    ? _rmsReadout(stats.rmsTotal, stats.pixelScale).value
                    : null,
                rmsUnit: _rmsReadout(0, stats.pixelScale).unit,
                onTimeScaleChanged: (scale) =>
                    setState(() => _timeScale = scale),
                onYScaleChanged: (scale) => setState(() => _yScale = scale),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRms(
    String label,
    double value,
    double pixelScale,
    Color color,
    NightshadeColors colors, {
    bool bold = false,
    bool hasSamples = true,
  }) {
    final text = _rmsText(value, pixelScale, hasSamples: hasSamples);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize11),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: NightshadeTypography.monoSm.copyWith(
            color: hasSamples ? color : colors.textMuted,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRightPanel(
      NightshadeColors colors, bool isConnected, Phd2State phd2State) {
    final calibrationData = ref.watch(calibrationStateProvider);
    final guiderId = ref.watch(guiderStateProvider).deviceId;
    final isPhd2Guider = guiderId == null || isPhd2DeviceId(guiderId);
    final settingsAsync = ref.watch(appSettingsProvider);
    final canPersistGuidingSettings = settingsAsync.hasValue &&
        !settingsAsync.isLoading &&
        !settingsAsync.hasError;

    return Column(
      children: [
        // Controls panel
        Expanded(
          flex: 3,
          child: GuideControlsPanel(
            key: GuidingTutorialKeys.controls,
            state: _mapPhd2State(phd2State),
            isConnected: isConnected,
            onStartGuiding: () => ref.read(phd2ControllerProvider).startGuiding(
                  settlePixels: _settlePixels,
                  settleTime: _settleTime,
                  settleTimeout: _settleTimeout,
                ),
            onStopGuiding: () => ref.read(phd2ControllerProvider).stopGuiding(),
            onPauseGuiding: isPhd2Guider
                ? () => ref.read(phd2ControllerProvider).pauseGuiding()
                : null,
            onResumeGuiding: isPhd2Guider
                ? () => ref.read(phd2ControllerProvider).resumeGuiding()
                : null,
            pauseUnavailableReason:
                isPhd2Guider ? null : kBuiltinGuiderNoPauseReason,
            onLoop: () => ref.read(phd2ControllerProvider).loop(),
            onFindStar: _autoSelectStar,
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
        // Calibration panel
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
                    decAngle: null, // Not separately available
                    raRate: calibrationData.raRate,
                    decRate: calibrationData.decRate,
                  ),
                  isConnected: isConnected,
                  onClearCalibration: () => _clearCalibration(),
                  onFlipCalibration: () => _flipCalibration(),
                )
              : _buildNonPhd2GuiderInfo(colors),
        ),
        const SizedBox(height: 12),
        // Brain settings toggle
        NightshadeButton(
          key: GuidingTutorialKeys.brainBtn,
          label: isPhd2Guider
              ? (_showBrainPanel ? 'Hide Brain Settings' : 'Brain Settings')
              : 'Guider Settings',
          icon: isPhd2Guider ? NightshadeIcons.brain : NightshadeIcons.settings,
          variant: ButtonVariant.outline,
          onPressed: isPhd2Guider
              ? () => setState(() => _showBrainPanel = !_showBrainPanel)
              : () => context.go('/equipment'),
        ),
        if (isPhd2Guider && _showBrainPanel) ...[
          const SizedBox(height: 12),
          Expanded(
            flex: 3,
            child: _buildBrainPanel(colors),
          ),
        ],
      ],
    );
  }

  Widget _buildNonPhd2GuiderInfo(NightshadeColors colors) {
    final isBuiltin = ref.watch(isBuiltinGuiderProvider);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isBuiltin ? NightshadeIcons.guider : NightshadeIcons.settings,
              size: 28,
              color: colors.primary,
            ),
            const SizedBox(height: 10),
            Text(
              isBuiltin ? 'Built-in Guider' : 'External Guider',
              textAlign: TextAlign.center,
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              isBuiltin
                  ? 'Calibration is managed automatically by Nightshade. '
                      'Pulse and multi-star settings are available under Equipment.'
                  : 'This guider does not expose PHD2 calibration or Brain controls. '
                      'Configure it from Equipment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
            const SizedBox(height: 12),
            NightshadeButton(
              label: 'Open Equipment',
              icon: NightshadeIcons.settings,
              size: ButtonSize.small,
              variant: ButtonVariant.outline,
              onPressed: () => context.go('/equipment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrainPanel(NightshadeColors colors) {
    final brainParams = ref.watch(brainParamsProvider);
    final guiderState = ref.watch(guiderStateProvider);

    // BrainParamsNotifier only ever calls fetch() while PHD2 itself is
    // connected (brain_and_calibration.dart: connected && deviceId ==
    // kPhd2CanonicalId), and it resets to `loading` on every disconnect. So
    // outside that window `loading` does NOT mean "values are on the way" — it
    // means no request will ever be made. Rendering the shimmer there left six
    // grey rows pulsing indefinitely with no values, no message and no error,
    // and the panel's real error branch (with its Retry button) is unreachable
    // because nothing ever throws. Say what is actually true instead.
    final canFetchBrainParams =
        guiderState.connectionState == DeviceConnectionState.connected &&
            guiderState.deviceId == kPhd2CanonicalId;

    return brainParams.when(
      data: (params) => BrainSettingsPanel(
        isEditing: true,
        raParams: params.raParams.entries
            .map((e) => BrainParam(name: e.key, value: e.value))
            .toList(),
        decParams: params.decParams.entries
            .map((e) => BrainParam(name: e.key, value: e.value))
            .toList(),
        onParamChanged: (axis, name, value) =>
            ref.read(brainParamsProvider.notifier).setParam(axis, name, value),
        onReset: () => ref.read(brainParamsProvider.notifier).fetch(),
      ),
      // Shimmer placeholders match the brain-params field rows so the dialog
      // doesn't visibly resize when PHD2 returns its parameter dump — but only
      // while a dump can actually arrive.
      loading: () => canFetchBrainParams
          // Scrollable: the six 36 px rows plus padding need ~320 px, more
          // than this flex-3 slot gets on a 900 px-tall window, and the
          // placeholder overflowed the column by 47 px there.
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  6,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ShimmerLoading(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: NightshadeTokens.borderRadiusMd,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : _buildBrainUnavailable(colors),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NightshadeIcons.warning, color: colors.error, size: 28),
              const SizedBox(height: 10),
              Text(
                'Failed to load brain settings',
                textAlign: TextAlign.center,
                style: NightshadeTypography.labelStrong
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              // Surface the real error so the user can act on it instead of
              // staring at a generic "failed" message (silent fallbacks hide
              // bugs). Common cause: PHD2 connected but no equipment profile.
              Text(
                _brainErrorMessage(e),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12),
              ),
              const SizedBox(height: 14),
              NightshadeButton(
                label: 'Retry',
                icon: NightshadeIcons.refresh,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                onPressed: () => ref.read(brainParamsProvider.notifier).fetch(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown in place of the shimmer when no brain-params fetch can run: PHD2
  /// holds these values, so with PHD2 down there is nothing to load and
  /// nothing to retry until it is connected.
  Widget _buildBrainUnavailable(NightshadeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(NightshadeIcons.brain, color: colors.textMuted, size: 28),
            const SizedBox(height: 10),
            Text(
              'Brain settings need PHD2',
              textAlign: TextAlign.center,
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'These are PHD2\'s own guiding parameters. Connect PHD2 to read '
              'and edit them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
