// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/flat_wizard_keys.dart';
import 'widgets/flat_wizard_split_view.dart';
import 'widgets/flat_preview_panel.dart';
import 'widgets/save_path_dialog.dart';

class FlatWizardScreen extends ConsumerStatefulWidget {
  const FlatWizardScreen({super.key});

  @override
  ConsumerState<FlatWizardScreen> createState() => _FlatWizardScreenState();
}

class _FlatWizardScreenState extends ConsumerState<FlatWizardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Load filters on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(flatWizardProvider.notifier).loadFiltersFromWheel();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final mode = switch (_tabController.index) {
      0 => FlatWizardMode.quick,
      1 => FlatWizardMode.batch,
      2 => FlatWizardMode.skyFlats,
      _ => FlatWizardMode.quick,
    };
    ref.read(flatWizardProvider.notifier).setMode(mode);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);

    return ContextualTourPrompt(
      screenId: 'flat_wizard',
      tourCategory: TutorialCategory.flatWizardTour,
      title: 'Flat Wizard Tour',
      description: 'Learn how to capture calibration frames for your images.',
      durationMinutes: 2,
      alignment: Alignment.bottomRight,
      child: Column(
        children: [
          // Screen header
          _buildHeader(colors, state),

          // Tab bar
          _buildTabBar(colors),

          // Split view content
          Expanded(
            child: FlatWizardSplitView(
              controlsPanel: TabBarView(
                controller: _tabController,
                children: const [
                  _QuickCaptureControls(),
                  _BatchCaptureControls(),
                  _SkyFlatsControls(),
                ],
              ),
              previewPanel:
                  FlatPreviewPanel(key: FlatWizardTutorialKeys.preview),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors, FlatWizardState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.sun, color: colors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flat Frame Wizard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Capture calibration frames with optimal exposure',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (state.isCapturing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: colors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Capturing',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(NightshadeColors colors) {
    return Container(
      color: colors.surface,
      child: TabBar(
        key: FlatWizardTutorialKeys.tabs,
        controller: _tabController,
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.primary,
        indicatorWeight: 2,
        tabs: const [
          Tab(text: 'Quick Capture'),
          Tab(text: 'Multi-Filter Batch'),
          Tab(text: 'Sky Flats'),
        ],
      ),
    );
  }
}

// --- Quick Capture Controls ---

class _QuickCaptureControls extends ConsumerWidget {
  const _QuickCaptureControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

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

          // Histogram target
          _SectionHeader(title: 'Histogram Target', colors: colors),
          const SizedBox(height: 8),
          _HistogramTargetSlider(
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
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

// --- Batch Capture Controls ---

class _BatchCaptureControls extends ConsumerWidget {
  const _BatchCaptureControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter checklist
          _SectionHeader(title: 'Filters', colors: colors),
          const SizedBox(height: 8),
          _FilterChecklist(key: FlatWizardTutorialKeys.filterSelect),
          const SizedBox(height: 24),

          // Global settings
          _SectionHeader(title: 'Global Settings', colors: colors),
          const SizedBox(height: 8),
          _HistogramTargetSlider(
            key: FlatWizardTutorialKeys.targetAdu,
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
          ),
          const SizedBox(height: 12),
          _ToleranceSlider(
            value: state.globalSettings.tolerancePercent,
            onChanged: notifier.setTolerance,
          ),
          const SizedBox(height: 12),
          _FrameCountInput(
            key: FlatWizardTutorialKeys.frameCount,
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

// --- Sky Flats Controls ---

class _SkyFlatsControls extends ConsumerWidget {
  const _SkyFlatsControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

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
                onPressed: notifier.autoOrderForTwilight,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _FilterChecklist(key: FlatWizardTutorialKeys.filterSelect),
          const SizedBox(height: 24),

          // Global settings
          _SectionHeader(title: 'Global Settings', colors: colors),
          const SizedBox(height: 8),
          _HistogramTargetSlider(
            key: FlatWizardTutorialKeys.targetAdu,
            value: state.globalSettings.histogramTarget,
            onChanged: notifier.setHistogramTarget,
          ),
          const SizedBox(height: 12),
          _ToleranceSlider(
            value: state.globalSettings.tolerancePercent,
            onChanged: notifier.setTolerance,
          ),
          const SizedBox(height: 12),
          _FrameCountInput(
            key: FlatWizardTutorialKeys.frameCount,
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

// --- Shared Widgets ---

class _SectionHeader extends StatelessWidget {
  final String title;
  final NightshadeColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
    );
  }
}

class _FilterSelector extends ConsumerWidget {
  const _FilterSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final fwState = ref.watch(filterWheelStateProvider);
    final state = ref.watch(flatWizardProvider);

    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.filter, size: 18, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentFilter?.filterName ??
                  fwState.currentFilterName ??
                  'No filter',
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChecklist extends ConsumerWidget {
  const _FilterChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    if (state.filterSettings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'No filters available. Connect a filter wheel.',
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < state.filterSettings.length; i++)
            _FilterChecklistItem(
              filter: state.filterSettings[i],
              isLast: i == state.filterSettings.length - 1,
              onToggle: (enabled) => notifier.toggleFilter(i, enabled),
            ),
        ],
      ),
    );
  }
}

class _FilterChecklistItem extends StatelessWidget {
  final FlatFilterSettings filter;
  final bool isLast;
  final ValueChanged<bool> onToggle;

  const _FilterChecklistItem({
    required this.filter,
    required this.isLast,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: filter.enabled,
            onChanged: (v) => onToggle(v ?? false),
            activeColor: colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filter.filterName,
              style: TextStyle(
                fontSize: 13,
                color: filter.enabled ? colors.textPrimary : colors.textMuted,
              ),
            ),
          ),
          if (filter.suggestedExposure != null)
            Text(
              '~${filter.suggestedExposure!.toStringAsFixed(1)}s',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

class _HistogramTargetSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _HistogramTargetSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        Row(
          children: [
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '~${FlatExposureCalculator.histogramPercentToAdu(value)} ADU',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
          ),
          child: Slider(
            value: value,
            min: 10,
            max: 90,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToleranceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ToleranceSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Text(
          '±${value.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.surfaceAlt,
              thumbColor: colors.primary,
            ),
            child: Slider(
              value: value,
              min: 1,
              max: 25,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _FrameCountInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _FrameCountInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Text(
          'Frames:',
          style: TextStyle(
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(LucideIcons.minus, size: 18),
          color: colors.textSecondary,
        ),
        Container(
          width: 60,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(LucideIcons.plus, size: 18),
          color: colors.textSecondary,
        ),
      ],
    );
  }
}

class _TwilightModeSelector extends StatelessWidget {
  final TwilightMode mode;
  final ValueChanged<TwilightMode> onChanged;

  const _TwilightModeSelector({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunrise,
            label: 'Dawn',
            description: 'Brightening sky',
            isSelected: mode == TwilightMode.dawn,
            onTap: () => onChanged(TwilightMode.dawn),
            colors: colors,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunset,
            label: 'Dusk',
            description: 'Darkening sky',
            isSelected: mode == TwilightMode.dusk,
            onTap: () => onChanged(TwilightMode.dusk),
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _TwilightOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _TwilightOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? colors.primary : colors.textPrimary,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  final FlatWizardMode mode;

  const _ActionButtons({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraState = ref.watch(cameraStateProvider);
    final isCameraConnected =
        cameraState.connectionState == DeviceConnectionState.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertCircle, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(fontSize: 13, color: colors.error),
                  ),
                ),
                IconButton(
                  onPressed: notifier.clearError,
                  icon: const Icon(LucideIcons.x, size: 16),
                  color: colors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (state.isCapturing)
          NightshadeButton(
            label: 'Stop Capture',
            onPressed: notifier.requestCancel,
            variant: ButtonVariant.destructive,
          )
        else
          NightshadeButton(
            key: FlatWizardTutorialKeys.startBtn,
            label:
                mode == FlatWizardMode.quick ? 'Start Capture' : 'Start Batch',
            onPressed:
                isCameraConnected ? () => _startCapture(context, ref) : null,
          ),
        if (!state.isCapturing && !isCameraConnected) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.cameraOff, size: 14, color: colors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Connect a camera before starting flat capture.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _startCapture(BuildContext context, WidgetRef ref) async {
    final state = ref.read(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraState = ref.read(cameraStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected ||
        cameraState.deviceId == null) {
      notifier.setErrorMessage('Camera not connected');
      return;
    }

    // Check if save path is set
    if (state.globalSettings.savePath == null ||
        state.globalSettings.savePath!.isEmpty) {
      final result = await SavePathDialog.show(
        context,
        currentPath: state.globalSettings.savePath,
        createDateSubfolder: state.globalSettings.createDateSubfolder,
        createFilterSubfolders: state.globalSettings.createFilterSubfolders,
      );

      if (result == null) return; // User cancelled

      notifier.updateGlobalSettings(
        state.globalSettings.copyWith(
          savePath: result.path,
          createDateSubfolder: result.createDateSubfolder,
          createFilterSubfolders: result.createFilterSubfolders,
        ),
      );
    }

    // Re-read state after potential save path update
    final currentState = ref.read(flatWizardProvider);

    // Start capture
    notifier.setCapturing(true);
    notifier.clearCancelRequest();
    notifier.clearAduHistory();
    notifier.setStatusMessage('Initializing...');

    try {
      await _runCaptureSequence(ref, currentState);
    } catch (e) {
      notifier.setErrorMessage('Capture failed: $e');
    } finally {
      notifier.setCapturing(false);
      notifier.setExposing(false);
      notifier.setStatusMessage(null);
    }
  }

  Future<void> _runCaptureSequence(WidgetRef ref, FlatWizardState state) async {
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraState = ref.read(cameraStateProvider);
    final backend = ref.read(backendProvider);
    final flatService = ref.read(flatWizardServiceProvider);
    final db = ref.read(databaseProvider);
    final profileId = ref.read(activeEquipmentProfileProvider)?.id;
    final brightnessTracker = ref.read(skyBrightnessTrackerProvider);

    // Validate camera is connected
    if (cameraState.connectionState != DeviceConnectionState.connected ||
        cameraState.deviceId == null) {
      notifier.setErrorMessage('Camera not connected');
      return;
    }

    final cameraId = cameraState.deviceId!;

    // Build save path with optional date subfolder
    String baseSavePath = state.globalSettings.savePath!;
    if (state.globalSettings.createDateSubfolder) {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      baseSavePath = p.join(baseSavePath, dateStr);
    }

    // Ensure base directory exists
    await Directory(baseSavePath).create(recursive: true);

    // Get list of filters to process
    final filtersToProcess = _getFiltersToProcess(state);
    if (filtersToProcess.isEmpty) {
      notifier.setErrorMessage('No filters selected');
      return;
    }

    // Process each filter
    for (int filterIdx = 0; filterIdx < filtersToProcess.length; filterIdx++) {
      if (notifier.cancelRequested) {
        notifier.setStatusMessage('Cancelled');
        break;
      }

      final filterSetting = filtersToProcess[filterIdx];
      notifier.setCurrentFilterIndex(filterIdx);
      notifier.updateFilterStatus(
          filterIdx, FilterCalibrationStatus.calibrating);
      notifier.setStatusMessage('Calibrating ${filterSetting.filterName}...');

      // Move filter wheel if needed
      await _moveFilterWheel(ref, filterSetting.filterPosition);

      // Calculate target ADU from histogram percentage
      final targetAdu = FlatExposureCalculator.histogramPercentToAdu(
        filterSetting.histogramTargetOverride ??
            state.globalSettings.histogramTarget,
      ).toDouble();

      final tolerance = filterSetting.toleranceOverride ??
          state.globalSettings.tolerancePercent;
      final minExp =
          filterSetting.minExposureOverride ?? state.globalSettings.minExposure;
      final maxExp =
          filterSetting.maxExposureOverride ?? state.globalSettings.maxExposure;

      // Calibrate exposure
      FlatResult calibrationResult;
      if (state.mode == FlatWizardMode.skyFlats) {
        // Use rate-tracking calibration for sky flats
        calibrationResult = await flatService.calibrateFilterWithRateTracking(
          deviceId: cameraId,
          filter: filterSetting.filterName,
          targetAdu: targetAdu,
          tolerance: tolerance,
          minExposure: minExp,
          maxExposure: maxExp,
          brightnessTracker: brightnessTracker,
          historicalExposure: filterSetting.suggestedExposure,
          onProgress: (iteration, exposure, adu, status) {
            notifier.addAduMeasurement(exposure, adu);
            notifier.updateFilterCalibration(filterIdx, exposure, adu);
            notifier.setStatusMessage(
              '${filterSetting.filterName}: $status (${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
            );
          },
        );
      } else {
        // Use standard calibration for flat panels
        calibrationResult = await flatService.calibrateFilter(
          deviceId: cameraId,
          filter: filterSetting.filterName,
          targetAdu: targetAdu,
          tolerance: tolerance,
          minExposure: minExp,
          maxExposure: maxExp,
          onProgress: (iteration, exposure, adu) {
            notifier.addAduMeasurement(exposure, adu);
            notifier.updateFilterCalibration(filterIdx, exposure, adu);
            notifier.setStatusMessage(
              '${filterSetting.filterName}: Iteration $iteration (${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
            );
          },
        );
      }

      if (!calibrationResult.success) {
        notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.failed);
        notifier.setWarningMessage(
          '${filterSetting.filterName}: ${calibrationResult.errorMessage ?? "Calibration failed"}',
        );
        // Continue to next filter instead of stopping
        continue;
      }

      // Update filter with calibrated exposure
      notifier.updateFilterCalibration(
        filterIdx,
        calibrationResult.exposure,
        calibrationResult.adu,
      );
      notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.capturing);

      // Build filter-specific save path
      String filterSavePath = baseSavePath;
      if (state.globalSettings.createFilterSubfolders) {
        filterSavePath = p.join(baseSavePath, filterSetting.filterName);
        await Directory(filterSavePath).create(recursive: true);
      }

      // Capture frames
      final frameCount =
          filterSetting.frameCountOverride ?? state.globalSettings.frameCount;

      for (int frameNum = 1; frameNum <= frameCount; frameNum++) {
        if (notifier.cancelRequested) {
          notifier.setStatusMessage('Cancelled');
          break;
        }

        notifier.setCurrentFrameIndex(frameNum);
        notifier.setStatusMessage(
          '${filterSetting.filterName}: Capturing frame $frameNum/$frameCount',
        );

        // Start exposure with countdown
        notifier.setExposing(
          true,
          startTime: DateTime.now(),
          duration: calibrationResult.exposure,
        );

        // Capture frame
        try {
          await backend.cameraStartExposure(
            deviceId: cameraId,
            exposureTime: calibrationResult.exposure,
            frameType: FrameType.flat,
            gain: cameraState.gain ?? 0,
            offset: cameraState.offset ?? 0,
            binX: 1,
            binY: 1,
          );

          // Wait for exposure to complete
          await Future.delayed(
            Duration(
                milliseconds:
                    (calibrationResult.exposure * 1000 + 500).toInt()),
          );

          notifier.setExposing(false);

          // Get the captured image for preview
          final image = await backend.cameraGetLastImage(cameraId);
          if (image != null) {
            // Update preview with full image result (includes pixels, histogram, stats)
            notifier.setLastImage(null, image);

            // Update ADU reading from actual capture
            notifier.addAduMeasurement(
                calibrationResult.exposure, image.stats.mean);
          }

          // Generate filename and save
          final captureTime = DateTime.now();
          final timestamp = DateFormat('yyyyMMdd_HHmmss').format(captureTime);
          final filename =
              'Flat_${filterSetting.filterName}_${timestamp}_$frameNum.fits';
          final filePath = p.join(filterSavePath, filename);

          await backend.saveFitsFromLastCapture(
            deviceId: cameraId,
            filePath: filePath,
            headerData: FitsWriteHeader(
              frameType: 'FLAT',
              filter: filterSetting.filterName,
              exposureTime: calibrationResult.exposure,
              captureTimestamp: captureTime.toIso8601String(),
              gain: cameraState.gain,
              offset: cameraState.offset,
              binX: 1,
              binY: 1,
            ),
          );

          notifier.incrementFilterCapturedCount(filterIdx);
          notifier.setLastImage(filePath, image);
        } catch (e) {
          notifier.setExposing(false);
          notifier.setWarningMessage('Frame $frameNum failed: $e');
          // Continue to next frame
        }
      }

      if (notifier.cancelRequested) break;

      // Mark filter complete
      notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.complete);

      // Record calibration to history database
      try {
        await db.flatHistoryDao.recordCalibration(
          filterName: filterSetting.filterName,
          exposureTime: calibrationResult.exposure,
          histogramTarget: state.globalSettings.histogramTarget,
          actualAdu: calibrationResult.adu.toInt(),
          equipmentProfileId: profileId,
          skyAduRate: state.mode == FlatWizardMode.skyFlats
              ? brightnessTracker.calculateRate()
              : null,
          twilightPhase: state.mode == FlatWizardMode.skyFlats
              ? (state.twilightMode == TwilightMode.dawn ? 'dawn' : 'dusk')
              : null,
        );
      } catch (e) {
        debugPrint('[FlatWizard] Failed to record calibration to history: $e');
      }
    }

    // Final status
    if (notifier.cancelRequested) {
      final completed = filtersToProcess
          .where((f) => f.status == FilterCalibrationStatus.complete)
          .length;
      notifier.setStatusMessage('Cancelled. Completed $completed filters.');
    } else {
      notifier.setStatusMessage('Complete!');
    }
  }

  List<FlatFilterSettings> _getFiltersToProcess(FlatWizardState state) {
    if (state.mode == FlatWizardMode.quick) {
      // Quick mode: just the current filter
      if (state.filterSettings.isNotEmpty &&
          state.currentFilterIndex < state.filterSettings.length) {
        return [state.filterSettings[state.currentFilterIndex]];
      }
      return [];
    } else {
      // Batch/Sky mode: all enabled filters
      return state.filterSettings.where((f) => f.enabled).toList();
    }
  }

  Future<void> _moveFilterWheel(WidgetRef ref, int position) async {
    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.connectionState != DeviceConnectionState.connected ||
        fwState.deviceId == null) {
      return; // No filter wheel connected, skip
    }

    if (fwState.currentPosition == position) {
      return; // Already at correct position
    }

    final backend = ref.read(backendProvider);
    await backend.filterWheelSetPosition(fwState.deviceId!, position);

    // Wait for filter wheel to settle
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
