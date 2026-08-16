// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

extension _ScreenShell on _PolarAlignmentScreenState {
  Widget _buildHeader(NightshadeColors colors, bool isRunning) {
    final ui = ref.watch(polarAlignmentUiStateProvider);
    final uiNotifier = ref.read(polarAlignmentUiStateProvider.notifier);

    final modeSelector = PolarAlignmentSegmentedButton<PolarAlignmentMode>(
      segments: const [
        ButtonSegment(
          value: PolarAlignmentMode.threePoint,
          label: Text('TPPA'),
          icon: Icon(NightshadeIcons.target, size: 14),
        ),
        ButtonSegment(
          value: PolarAlignmentMode.allSky,
          label: Text('All-Sky'),
          icon: Icon(NightshadeIcons.globe, size: 14),
        ),
      ],
      selected: {ui.mode},
      showSelectedIcon: false,
      onSelectionChanged:
          isRunning ? null : (selection) => uiNotifier.setMode(selection.first),
    );

    final historyButton = Tooltip(
      message: ui.showHistoryPanel
          ? 'Hide past alignment runs'
          : 'Show past alignment runs below the settings',
      child: NightshadeButton(
        label: 'History',
        icon: NightshadeIcons.history,
        variant:
            ui.showHistoryPanel ? ButtonVariant.primary : ButtonVariant.ghost,
        size: ButtonSize.small,
        onPressed: () => uiNotifier.toggleHistoryPanel(),
      ),
    );

    final backButton = IconButton(
      icon: Icon(NightshadeIcons.arrowLeft, color: colors.textPrimary),
      onPressed: isRunning
          ? null
          : () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/imaging');
              }
            },
      tooltip: isRunning ? 'Stop alignment first' : 'Back',
    );

    final titleBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(NightshadeIcons.compass, color: colors.primary, size: 24),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Polar Alignment',
                overflow: TextOverflow.ellipsis,
                style:
                    NightshadeTypography.h4.copyWith(color: colors.textPrimary),
              ),
              Text(
                ui.mode.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useCompactHeader = constraints.maxWidth < 960;

          if (!useCompactHeader) {
            return SizedBox(
              height: 48,
              child: Row(
                children: [
                  backButton,
                  const SizedBox(width: 8),
                  titleBlock,
                  const SizedBox(width: 16),
                  modeSelector,
                  const Spacer(),
                  historyButton,
                  const SizedBox(width: 12),
                  _buildEquipmentIndicators(colors),
                ],
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    backButton,
                    Expanded(child: titleBlock),
                    historyButton,
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: modeSelector),
                  const SizedBox(width: 8),
                  _buildEquipmentIndicators(colors),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEquipmentIndicators(NightshadeColors colors) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);

    return Row(
      children: [
        _StatusChip(
          icon: NightshadeIcons.camera,
          label: 'Camera',
          isConnected:
              cameraState.connectionState == DeviceConnectionState.connected,
          colors: colors,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          icon: NightshadeIcons.move,
          label: 'Mount',
          isConnected:
              mountState.connectionState == DeviceConnectionState.connected,
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildFooter(
    NightshadeColors colors,
    PolarAlignmentState state,
    bool isRunning,
  ) {
    // Check equipment connection state for disabling Start button
    final cameraConnected = ref.watch(cameraStateProvider
        .select((s) => s.connectionState == DeviceConnectionState.connected));
    final mountConnected = ref.watch(mountStateProvider
        .select((s) => s.connectionState == DeviceConnectionState.connected));
    // A parked mount cannot slew between the three points and is not pointing
    // at sky, so the run is refused before it starts. Letting it run returns
    // "Plate solve timed out" — a solver error for a mount the app knew was
    // parked before the click.
    final mountParked = mountConnected &&
        ref.watch(mountStateProvider.select((s) => s.isParked));
    final equipmentReady = cameraConnected && mountConnected && !mountParked;
    final detectionAsync = ref.watch(plateSolverDetectionProvider);
    final preferenceAsync = ref.watch(plateSolverPreferenceProvider);
    final solverReady = detectionAsync.valueOrNull != null &&
        preferenceAsync.valueOrNull != null &&
        detectionAsync.valueOrNull!
            .supports(preferenceAsync.valueOrNull!.choice);
    final readinessResolved = !detectionAsync.isLoading &&
        !preferenceAsync.isLoading &&
        !detectionAsync.hasError &&
        !preferenceAsync.hasError;
    // The site is a prerequisite in exactly the same sense as the camera, the
    // mount and the solver: the az/alt decomposition of a polar-axis error is a
    // function of latitude, and the app installs a (0, 0) observer at startup,
    // so without this the wizard measures for an observer on the equator.
    // `_startAlignment` refuses too, but a disabled button with a reason is the
    // shape every other prerequisite already uses here.
    final settingsResolved = ref.watch(appSettingsProvider).hasValue;
    final siteReady =
        settingsResolved && ref.watch(appObserverLocationProvider) != null;
    final canStart = equipmentReady && solverReady && siteReady;

    // Report every unmet prerequisite together.
    final blockers = <String>[
      if (!cameraConnected && !mountConnected)
        'Camera and mount not connected'
      else if (!cameraConnected)
        'Camera not connected'
      else if (!mountConnected)
        'Mount not connected'
      else if (mountParked)
        'Mount is parked — unpark it before aligning',
      if (!siteReady)
        settingsResolved
            ? 'No observing location set'
            : 'Checking observing location…',
      if (!readinessResolved)
        detectionAsync.hasError || preferenceAsync.hasError
            ? 'Could not check plate solver configuration'
            : 'Checking plate solver configuration…'
      else if (!solverReady)
        'Selected plate solver is not ready',
    ];
    final String? disabledReason =
        blockers.isEmpty ? null : blockers.join(' · ');

    // A disabled Start button explains itself on HOVER, which is no
    // explanation to the operator who clicked it: a parked mount ate the
    // click, the footer went on reading "Ready to start polar alignment", and
    // nothing was written to the log. The blocker is stated where the operator
    // is already looking — the footer — for as long as it applies.
    final String? blockedNotice =
        state.phase == PolarAlignPhase.idle && !isRunning
            ? disabledReason
            : null;

    final status = Row(
      children: [
        if (isRunning)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          ),
        if (blockedNotice != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              NightshadeIcons.warning,
              size: 14,
              color: colors.warning,
            ),
          ),
        Expanded(
          child: Text(
            blockedNotice == null
                ? state.statusMessage
                : 'Cannot start: $blockedNotice',
            key: blockedNotice == null ? null : startBlockedNoticeKey,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color:
                  blockedNotice == null ? colors.textSecondary : colors.warning,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    // Action buttons for the current phase. When [stretch] is true they fill
    // the available width (phone, stacked under the status); otherwise they
    // size to content and sit beside the status on a wider viewport.
    //
    // NightshadeButton sizes to its content but expands to fill a bounded
    // parent. The stretched buttons are always laid out inside a Row, so
    // Expanded is what makes them full-width without touching the shared
    // component (SizedBox(width: infinity) would be an unbounded-width error
    // inside a Row).
    Widget wrapButton(Widget button, {required bool stretch}) {
      if (!stretch) return button;
      return Expanded(child: button);
    }

    /// Stopping a run means waiting for the exposure or plate solve in flight
    /// to reach a checkpoint. The button says so for those seconds instead of
    /// standing unchanged, which reads as a click that never landed.
    Widget stopButton() => NightshadeButton(
          label: _stopping ? 'Stopping…' : 'Stop',
          icon: NightshadeIcons.stop,
          variant: ButtonVariant.destructive,
          size: ButtonSize.small,
          onPressed: _stopping ? null : _stopAlignment,
        );

    List<Widget> actionButtons(bool stretch) {
      switch (state.phase) {
        case PolarAlignPhase.idle:
          return [
            wrapButton(
              Tooltip(
                message: disabledReason ?? '',
                child: NightshadeButton(
                  key: PolarAlignmentTutorialKeys.startBtn,
                  label: 'Start Alignment',
                  icon: NightshadeIcons.play,
                  variant: ButtonVariant.primary,
                  onPressed: canStart ? _startAlignment : null,
                ),
              ),
              stretch: stretch,
            ),
          ];
        case PolarAlignPhase.measuring:
          return [
            wrapButton(stopButton(), stretch: stretch),
          ];
        case PolarAlignPhase.adjusting:
          final hasMeasurement =
              state.initialError != null && state.currentError != null;
          return [
            wrapButton(stopButton(), stretch: stretch),
            const SizedBox(width: 8),
            wrapButton(
              Tooltip(
                message: hasMeasurement
                    ? 'Stop and save this alignment'
                    : 'Waiting for the first alignment measurement',
                child: NightshadeButton(
                  label: 'Done',
                  icon: NightshadeIcons.check,
                  variant: ButtonVariant.primary,
                  onPressed: hasMeasurement ? _completeAlignment : null,
                ),
              ),
              stretch: stretch,
            ),
          ];
        case PolarAlignPhase.complete:
        case PolarAlignPhase.error:
          return [
            wrapButton(
              NightshadeButton(
                label: 'Restart',
                icon: NightshadeIcons.undo,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: _resetAlignment,
              ),
              stretch: stretch,
            ),
            const SizedBox(width: 8),
            wrapButton(
              NightshadeButton(
                label: 'Done',
                icon: NightshadeIcons.check,
                variant: ButtonVariant.primary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/imaging');
                  }
                },
              ),
              stretch: stretch,
            ),
          ];
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below ~520px a status + label-bearing button row gets tight, so
            // stack the actions under the status and let them fill the width.
            final stack = constraints.maxWidth < 520;
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  status,
                  const SizedBox(height: 12),
                  Row(children: actionButtons(true)),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 16),
                ...actionButtons(false),
              ],
            );
          },
        ),
      ),
    );
  }
}
