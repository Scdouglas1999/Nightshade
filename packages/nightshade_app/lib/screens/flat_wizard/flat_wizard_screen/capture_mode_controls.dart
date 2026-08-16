part of '../flat_wizard_screen.dart';

// Quick capture controls

class _QuickCaptureControls extends ConsumerWidget {
  const _QuickCaptureControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraConfig = ref.watch(flatCameraConfigProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter selector
          _SectionHeader(title: 'Filter', colors: colors),
          const SizedBox(height: 8),
          const _FilterSelector(),
          const SizedBox(height: 24),

          // Camera settings the run will actually command
          _SectionHeader(title: 'Camera', colors: colors),
          const SizedBox(height: 8),
          const _CaptureConfigSummary(),
          const SizedBox(height: 24),

          // Histogram target
          _SectionHeader(title: 'Histogram Target', colors: colors),
          const SizedBox(height: 8),
          _HistogramTargetSlider(
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
            config: cameraConfig,
          ),
          const SizedBox(height: 24),

          // Tolerance
          _SectionHeader(title: 'Tolerance', colors: colors),
          const SizedBox(height: 8),
          _ToleranceSlider(
            value: state.globalSettings.tolerancePercent,
            onChanged: notifier.setTolerance,
          ),
          const SizedBox(height: 24),

          // Frame count
          _SectionHeader(title: 'Frame Count', colors: colors),
          const SizedBox(height: 8),
          _FrameCountInput(
            value: state.globalSettings.frameCount,
            onChanged: notifier.setFrameCount,
          ),
          const SizedBox(height: 32),

          // Action buttons
          const _ActionButtons(mode: FlatWizardMode.quick),
        ],
      ),
    );
  }
}

// Batch capture controls

class _BatchCaptureControls extends ConsumerWidget {
  const _BatchCaptureControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraConfig = ref.watch(flatCameraConfigProvider);
    final isSelected = state.mode == FlatWizardMode.batch;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter checklist
          _SectionHeader(title: 'Filters', colors: colors),
          const SizedBox(height: 8),
          // Only the SELECTED tab claims the shared tutorial GlobalKeys: the
          // TabBarView keeps the outgoing tab mounted across a switch, and a
          // GlobalKey attached twice throws "specified multiple times in the
          // widget tree".
          _FilterChecklist(
            key: isSelected ? FlatWizardTutorialKeys.filterSelect : null,
          ),
          const SizedBox(height: 24),

          // Global settings
          _SectionHeader(title: 'Global Settings', colors: colors),
          const SizedBox(height: 8),
          const _CaptureConfigSummary(),
          const SizedBox(height: 12),
          const _FieldLabel('Histogram Target'),
          _HistogramTargetSlider(
            key: isSelected ? FlatWizardTutorialKeys.targetAdu : null,
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
            config: cameraConfig,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Tolerance'),
          _ToleranceSlider(
            value: state.globalSettings.tolerancePercent,
            onChanged: notifier.setTolerance,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Frame Count'),
          _FrameCountInput(
            key: isSelected ? FlatWizardTutorialKeys.frameCount : null,
            value: state.globalSettings.frameCount,
            onChanged: notifier.setFrameCount,
          ),
          const SizedBox(height: 32),

          // Action buttons
          const _ActionButtons(mode: FlatWizardMode.batch),
        ],
      ),
    );
  }
}

// Sky flats controls

class _SkyFlatsControls extends ConsumerWidget {
  const _SkyFlatsControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraConfig = ref.watch(flatCameraConfigProvider);
    final isSelected = state.mode == FlatWizardMode.skyFlats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Twilight mode
          _SectionHeader(title: 'Twilight Mode', colors: colors),
          const SizedBox(height: 8),
          _TwilightModeSelector(
            mode: state.twilightMode,
            onChanged: notifier.setTwilightMode,
          ),
          const SizedBox(height: 24),

          // Filter checklist with auto-order button
          Row(
            children: [
              _SectionHeader(title: 'Filters', colors: colors),
              const Spacer(),
              NightshadeButton(
                label: 'Auto-Order',
                icon: LucideIcons.arrowUpDown,
                // Reordering mid-run would invalidate the run's stable filter
                // indices, so the control is disabled while capturing.
                onPressed:
                    state.isCapturing ? null : notifier.autoOrderForTwilight,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _FilterChecklist(
            key: isSelected ? FlatWizardTutorialKeys.filterSelect : null,
          ),
          const SizedBox(height: 24),

          // Global settings
          _SectionHeader(title: 'Global Settings', colors: colors),
          const SizedBox(height: 8),
          const _CaptureConfigSummary(),
          const SizedBox(height: 12),
          const _FieldLabel('Histogram Target'),
          _HistogramTargetSlider(
            key: isSelected ? FlatWizardTutorialKeys.targetAdu : null,
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
            config: cameraConfig,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Tolerance'),
          _ToleranceSlider(
            value: state.globalSettings.tolerancePercent,
            onChanged: notifier.setTolerance,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Frame Count'),
          _FrameCountInput(
            key: isSelected ? FlatWizardTutorialKeys.frameCount : null,
            value: state.globalSettings.frameCount,
            onChanged: notifier.setFrameCount,
          ),
          const SizedBox(height: 32),

          // Action buttons
          const _ActionButtons(mode: FlatWizardMode.skyFlats),
        ],
      ),
    );
  }
}
