// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
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
          icon: Icon(LucideIcons.target, size: 14),
        ),
        ButtonSegment(
          value: PolarAlignmentMode.allSky,
          label: Text('All-Sky'),
          icon: Icon(LucideIcons.globe, size: 14),
        ),
      ],
      selected: {ui.mode},
      showSelectedIcon: false,
      onSelectionChanged:
          isRunning ? null : (selection) => uiNotifier.setMode(selection.first),
    );

    final historyButton = NightshadeButton(
      label: 'History',
      icon: LucideIcons.history,
      variant:
          ui.showHistoryPanel ? ButtonVariant.primary : ButtonVariant.ghost,
      size: ButtonSize.small,
      onPressed: () => uiNotifier.toggleHistoryPanel(),
    );

    final backButton = IconButton(
      icon: Icon(LucideIcons.arrowLeft, color: colors.textPrimary),
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
        Icon(LucideIcons.compass, color: colors.primary, size: 24),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Polar Alignment',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                ui.mode.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
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
          icon: LucideIcons.camera,
          label: 'Camera',
          isConnected:
              cameraState.connectionState == DeviceConnectionState.connected,
          colors: colors,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          icon: LucideIcons.move,
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
    final equipmentReady = cameraConnected && mountConnected;

    // Build tooltip message for disabled state
    String? disabledReason;
    if (!cameraConnected && !mountConnected) {
      disabledReason = 'Camera and mount not connected';
    } else if (!cameraConnected) {
      disabledReason = 'Camera not connected';
    } else if (!mountConnected) {
      disabledReason = 'Mount not connected';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Status
          Expanded(
            child: Row(
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
                Expanded(
                  child: Text(
                    state.statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Action buttons
          if (state.phase == PolarAlignPhase.idle)
            Tooltip(
              message: disabledReason ?? '',
              child: NightshadeButton(
                key: PolarAlignmentTutorialKeys.startBtn,
                label: 'Start Alignment',
                icon: LucideIcons.play,
                variant: ButtonVariant.primary,
                onPressed: equipmentReady ? _startAlignment : null,
              ),
            )
          else if (state.phase == PolarAlignPhase.measuring)
            NightshadeButton(
              label: 'Stop',
              icon: LucideIcons.square,
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: _stopAlignment,
            )
          else if (state.phase == PolarAlignPhase.adjusting)
            Row(
              children: [
                NightshadeButton(
                  label: 'Stop',
                  icon: LucideIcons.square,
                  variant: ButtonVariant.destructive,
                  size: ButtonSize.small,
                  onPressed: _stopAlignment,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Done',
                  icon: LucideIcons.check,
                  variant: ButtonVariant.primary,
                  onPressed: _completeAlignment,
                ),
              ],
            )
          else if (state.phase == PolarAlignPhase.complete ||
              state.phase == PolarAlignPhase.error)
            Row(
              children: [
                NightshadeButton(
                  label: 'Restart',
                  icon: LucideIcons.rotateCcw,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: _resetAlignment,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Done',
                  icon: LucideIcons.check,
                  variant: ButtonVariant.primary,
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/imaging');
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
