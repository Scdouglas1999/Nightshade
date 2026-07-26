// Part of ../guiding_screen.dart -- extracted for maintainability.
//
// Desktop layout, shared panels, value formatting, and guiding actions.
part of '../guiding_screen.dart';

mixin _GuidingDesktopSections
    on ConsumerState<GuidingScreen>, _GuidingStateFields {
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
                    bold: true, compact: true),
              ),
            ] else ...[
              // Desktop shows RMS in graph header, not here
              _buildRmsChip('RA', guideStats.rmsRa, guideStats.pixelScale,
                  colors.error, colors),
              const SizedBox(width: 10),
              _buildRmsChip('Dec', guideStats.rmsDec, guideStats.pixelScale,
                  colors.info, colors),
              const SizedBox(width: 10),
              _buildRmsChip('Total', guideStats.rmsTotal, guideStats.pixelScale,
                  colors.primary, colors,
                  bold: true),
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

  /// PHD2 reports guide residuals in pixels (RADistanceRaw/AvgDist). When a
  /// pixel scale (arcsec/px) is known we present arcseconds; otherwise we show
  /// the raw pixel value labelled "px" rather than mislabelling it as arcsec.
  ({double value, String unit}) _rmsReadout(double raw, double pixelScale) {
    if (pixelScale > 0) return (value: raw * pixelScale, unit: '"');
    return (value: raw, unit: ' px');
  }

  Widget _buildRmsChip(
    String label,
    double value,
    double pixelScale,
    Color color,
    NightshadeColors colors, {
    bool bold = false,
    bool compact = false,
  }) {
    final readout = _rmsReadout(value, pixelScale);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusInline4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: compact ? 10 : 12,
            ),
          ),
          Text(
            '${readout.value.toStringAsFixed(2)}${readout.unit}',
            style: NightshadeTypography.monoSm.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: compact ? 11 : null,
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
                loading: () => const GuideStarView(
                  statusMessage: 'Waiting for image...',
                ),
                error: (_, __) => const GuideStarView(
                  statusMessage: 'No star selected',
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
          const SizedBox(height: 12),
          // Star stats - fixed height card instead of Expanded to prevent overflow
          _buildGlassCard(
            colors,
            title: 'Star Statistics',
            icon: NightshadeIcons.activity,
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

  Widget _buildCenterPanel(NightshadeColors colors, Phd2GuideStats stats) {
    final graphData = ref.watch(guideGraphProvider);
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
                          _buildCompactRms('RA', stats.rmsRa, stats.pixelScale,
                              colors.error, colors),
                          const SizedBox(width: 12),
                          _buildCompactRms('Dec', stats.rmsDec,
                              stats.pixelScale, colors.info, colors),
                          const SizedBox(width: 12),
                          _buildCompactRms('Total', stats.rmsTotal,
                              stats.pixelScale, colors.primary, colors,
                              bold: true),
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
                          raError: p.ra,
                          decError: p.dec,
                        ))
                    .toList(),
                timeScale: _timeScale,
                yScale: _yScale,
                rmsRa: stats.rmsRa,
                rmsDec: stats.rmsDec,
                rmsTotal: stats.rmsTotal,
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
  }) {
    final readout = _rmsReadout(value, pixelScale);
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
          '${readout.value.toStringAsFixed(2)}${readout.unit}',
          style: NightshadeTypography.monoSm.copyWith(
            color: color,
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
      // doesn't visibly resize when PHD2 returns its parameter dump.
      loading: () => Padding(
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
      ),
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

  /// Pull a human-readable message out of whatever the brain-params fetch
  /// threw. `StateError` (our explicit empty-dump guard) carries a clean
  /// sentence; everything else falls back to its string form.
  String _brainErrorMessage(Object error) {
    if (error is StateError) return error.message;
    return error.toString();
  }

  Widget _buildStatRow(
      String label, String value, Color valueColor, NightshadeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 1,
          child: Text(
            label,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: NightshadeTypography.monoSm.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getSnrColor(double snr, NightshadeColors colors) {
    if (snr >= 10) return colors.success;
    if (snr >= 5) return colors.warning;
    return colors.error;
  }

  Color _getStateColor(Phd2State state) {
    final colors = NightshadeColors.of(context);
    switch (state) {
      case Phd2State.stopped:
        return colors.textMuted;
      case Phd2State.looping:
        return colors.warning;
      case Phd2State.calibrating:
        return colors.warning;
      case Phd2State.guiding:
        return colors.success;
      case Phd2State.paused:
        return colors.info;
      case Phd2State.settling:
        return colors.info;
      case Phd2State.lostLock:
        return colors.error;
      case Phd2State.unknown:
        return colors.warning;
      default:
        return colors.textMuted;
    }
  }

  String _getStateLabel(Phd2State state) {
    switch (state) {
      case Phd2State.stopped:
        return 'Stopped';
      case Phd2State.selected:
        return 'Star Selected';
      case Phd2State.looping:
        return 'Looping';
      case Phd2State.calibrating:
        return 'Calibrating';
      case Phd2State.guiding:
        return 'Guiding';
      case Phd2State.paused:
        return 'Paused';
      case Phd2State.settling:
        return 'Settling';
      case Phd2State.lostLock:
        return 'Lost Lock';
      case Phd2State.unknown:
        return 'Unknown';
    }
  }

  Phd2GuidingState _mapPhd2State(Phd2State state) {
    switch (state) {
      case Phd2State.stopped:
      // "Selected" is connected + a star chosen but not yet guiding — the same
      // idle-but-ready surface as Stopped (Start is legal), NOT disconnected.
      case Phd2State.selected:
        return Phd2GuidingState.stopped;
      case Phd2State.looping:
        return Phd2GuidingState.looping;
      case Phd2State.calibrating:
        return Phd2GuidingState.calibrating;
      case Phd2State.guiding:
        return Phd2GuidingState.guiding;
      case Phd2State.paused:
        return Phd2GuidingState.paused;
      case Phd2State.settling:
        return Phd2GuidingState.settling;
      case Phd2State.lostLock:
        return Phd2GuidingState.lostLock;
      case Phd2State.unknown:
        return Phd2GuidingState.unknown;
    }
  }

  void _showConnectionDialog() {
    Phd2ConnectionDialog.show(context, ref);
  }

  Future<void> _disconnectActiveGuider() async {
    final backend = ref.read(backendProvider);
    final guiderId = ref.read(guiderStateProvider).deviceId;
    try {
      await ref.read(deviceServiceProvider).disconnectGuider();
      if (!mounted) return;
      if (!identical(backend, ref.read(backendProvider))) {
        _showActionError(
          'The imaging host changed while disconnecting the guider. '
          'Check Equipment before continuing.',
        );
      }
    } catch (e) {
      _showActionError(
        'Failed to disconnect ${guiderId ?? 'the active guider'}: $e',
      );
    }
  }

  /// Select the guide star at a tapped image position. The star view invokes
  /// this fire-and-forget, so the RPC failure is surfaced here — a rejected
  /// lock-position command would otherwise leave the tap silently doing
  /// nothing.
  Future<void> _selectStar(double x, double y) async {
    try {
      await ref.read(lockPositionProvider.notifier).setLockPosition(x, y);
    } catch (e) {
      _showActionError('Could not select the guide star: $e');
    }
  }

  /// Deselect the guide star. Returns the controller Future so the awaiting
  /// caller (GuideControlsPanel's `_runAction`) surfaces a rejected RPC — e.g. a
  /// mid-flight host change — instead of the failure escaping as an unhandled
  /// Future. Discarding it here left a Deselect tap silently failing.
  Future<void> _deselectStar() =>
      ref.read(lockPositionProvider.notifier).deselectStar();

  /// Surface a guiding action failure inline instead of letting it escape as an
  /// unhandled Future (calibration ops issue real PHD2 RPCs that can fail).
  void _showActionError(String message) {
    if (!mounted) return;
    final colors = NightshadeColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: colors.error),
    );
  }

  Future<void> _clearCalibration() async {
    final backend = ref.read(backendProvider);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Clear Calibration?',
      message: 'This discards PHD2\'s current calibration. You will need to '
          'recalibrate before guiding is reliable again.',
      confirmLabel: 'Clear',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    if (!identical(backend, ref.read(backendProvider))) {
      _showActionError(
        'The connected imaging host changed. Calibration was not cleared.',
      );
      return;
    }
    try {
      await ref.read(calibrationStateProvider.notifier).clearCalibration();
    } catch (e) {
      _showActionError('Failed to clear calibration: $e');
    }
  }

  Future<void> _flipCalibration() async {
    try {
      await ref.read(calibrationStateProvider.notifier).flipCalibration();
    } catch (e) {
      _showActionError('Failed to flip calibration: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Settle / dither persistence — canonical AppSettings authority (defect 5)
  //
  // The screen owns no independent settle/dither store: it seeds its live cache
  // from the persisted settings once, then writes every edit straight back
  // through the AppSettings notifier so values persist across navigation AND
  // full reconstruction, and remote companions share the same canonical sync.
  // ---------------------------------------------------------------------------

  /// Seed the settle/dither controls from the persisted authority exactly once
  /// per screen instance. Values are clamped to the control ranges so a
  /// corrupt/out-of-range stored value can never push a slider off its track.
  void _hydrateGuidingSettings(AppSettingsState settings) {
    if (_guidingSettingsHydrated) return;
    _guidingSettingsHydrated = true;
    _settlePixels = settings.settleThreshold.clamp(0.5, 5.0).toDouble();
    _settleTimeout = settings.settleTimeout.toDouble().clamp(30.0, 180.0);
    _settleTime = settings.settleTime.toDouble().clamp(5.0, 60.0);
    _ditherAmount = _ditherScaleToPixels(settings.ditherScale).clamp(1.0, 20.0);
    _ditherRaOnly = settings.ditherRaOnly;
  }

  void _setSettlePixels(double value) {
    final clamped = value.clamp(0.5, 5.0).toDouble();
    final rollback = _settlePixels;
    setState(() => _settlePixels = clamped);
    unawaited(_persistSettlePixels(clamped, rollback));
  }

  Future<void> _persistSettlePixels(double value, double rollback) async {
    final clamped = value.clamp(0.5, 5.0).toDouble();
    final current = ref.read(appSettingsProvider).valueOrNull?.settleThreshold;
    if (current != null && (current - clamped).abs() < 0.0001) return;
    try {
      await ref.read(appSettingsProvider.notifier).setSettleThreshold(clamped);
    } catch (error) {
      if (!mounted) return;
      if ((_settlePixels - clamped).abs() < 0.0001) {
        final authoritative =
            ref.read(appSettingsProvider).valueOrNull?.settleThreshold;
        setState(
            () => _settlePixels = (authoritative ?? rollback).clamp(0.5, 5.0));
      }
      _showActionError('Could not save the settle threshold: $error');
    }
  }

  void _setSettleTimeout(double value) {
    final clamped = value.clamp(30.0, 180.0).toDouble();
    final rollback = _settleTimeout;
    setState(() => _settleTimeout = clamped);
    unawaited(_persistSettleTimeout(clamped, rollback));
  }

  Future<void> _persistSettleTimeout(double value, double rollback) async {
    final clamped = value.clamp(30.0, 180.0).round();
    final current = ref.read(appSettingsProvider).valueOrNull?.settleTimeout;
    if (current == clamped) return;
    try {
      await ref.read(appSettingsProvider.notifier).setSettleTimeout(clamped);
    } catch (error) {
      if (!mounted) return;
      if ((_settleTimeout - clamped).abs() < 0.0001) {
        final authoritative =
            ref.read(appSettingsProvider).valueOrNull?.settleTimeout;
        setState(
          () => _settleTimeout =
              (authoritative?.toDouble() ?? rollback).clamp(30.0, 180.0),
        );
      }
      _showActionError('Could not save the settle timeout: $error');
    }
  }

  void _setSettleTime(double value) {
    final clamped = value.clamp(5.0, 60.0).toDouble();
    final rollback = _settleTime;
    setState(() => _settleTime = clamped);
    unawaited(_persistSettleTime(clamped, rollback));
  }

  Future<void> _persistSettleTime(double value, double rollback) async {
    final clamped = value.clamp(5.0, 60.0).round();
    final current = ref.read(appSettingsProvider).valueOrNull?.settleTime;
    if (current == clamped) return;
    try {
      await ref.read(appSettingsProvider.notifier).setSettleTime(clamped);
    } catch (error) {
      if (!mounted) return;
      if ((_settleTime - clamped).abs() < 0.0001) {
        final authoritative =
            ref.read(appSettingsProvider).valueOrNull?.settleTime;
        setState(
          () => _settleTime =
              (authoritative?.toDouble() ?? rollback).clamp(5.0, 60.0),
        );
      }
      _showActionError('Could not save the settle time: $error');
    }
  }

  void _setDitherRaOnly(bool value) {
    final rollback = _ditherRaOnly;
    setState(() => _ditherRaOnly = value);
    unawaited(_persistDitherRaOnly(value, rollback));
  }

  Future<void> _persistDitherRaOnly(bool value, bool rollback) async {
    final current = ref.read(appSettingsProvider).valueOrNull?.ditherRaOnly;
    if (current == value) return;
    try {
      await ref.read(appSettingsProvider.notifier).setDitherRaOnly(value);
    } catch (error) {
      if (!mounted) return;
      if (_ditherRaOnly == value) {
        final authoritative =
            ref.read(appSettingsProvider).valueOrNull?.ditherRaOnly;
        setState(() => _ditherRaOnly = authoritative ?? rollback);
      }
      _showActionError('Could not save the dither RA-only setting: $error');
    }
  }

  void _setDitherAmount(double pixels) {
    final clamped = pixels.clamp(1.0, 20.0).toDouble();
    final rollback = _ditherAmount;
    setState(() => _ditherAmount = clamped);
    unawaited(_persistDitherScale(clamped, rollback));
  }

  Future<void> _persistDitherScale(double pixels, double rollback) async {
    final scale = _pixelsToDitherScale(pixels);
    final current = ref.read(appSettingsProvider).valueOrNull?.ditherScale;
    if (current == scale) return;
    try {
      await ref.read(appSettingsProvider.notifier).setDitherScale(scale);
    } catch (error) {
      if (!mounted) return;
      if ((_ditherAmount - pixels).abs() < 0.0001) {
        final authoritative =
            ref.read(appSettingsProvider).valueOrNull?.ditherScale;
        setState(
          () => _ditherAmount = authoritative == null
              ? rollback
              : _ditherScaleToPixels(authoritative),
        );
      }
      _showActionError('Could not save the dither amount: $error');
    }
  }

  /// Canonical AppSettings stores dither strength as a coarse Small/Medium/Large
  /// bucket; the slider works in pixels. These two helpers are the single,
  /// documented bridge between the two representations.
  static double _ditherScaleToPixels(String scale) {
    switch (scale) {
      case 'Small':
        return 2.0;
      case 'Large':
        return 10.0;
      case 'Medium':
      default:
        return 5.0;
    }
  }

  static String _pixelsToDitherScale(double pixels) {
    if (pixels < 3.5) return 'Small';
    if (pixels < 7.5) return 'Medium';
    return 'Large';
  }
}
