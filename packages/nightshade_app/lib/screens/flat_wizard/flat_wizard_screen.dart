import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// Flat wizard state providers
final flatWizardStateProvider =
    StateNotifierProvider<FlatWizardStateNotifier, FlatWizardState>((ref) {
  return FlatWizardStateNotifier(ref);
});

final skyBrightnessProvider = StateProvider<double?>((ref) => null);
final currentAduProvider = StateProvider<double?>((ref) => null);

/// State for the flat wizard
class FlatWizardState {
  final bool isCapturing;
  final FlatWizardMode mode;
  final List<FlatFilterPlan> filterPlans;
  final int currentFilterIndex;
  final int currentFrameIndex;
  final double targetAdu;
  final double aduTolerance;
  final double? panelBrightness;
  final bool usePanelControl;
  final String? errorMessage;

  const FlatWizardState({
    this.isCapturing = false,
    this.mode = FlatWizardMode.single,
    this.filterPlans = const [],
    this.currentFilterIndex = 0,
    this.currentFrameIndex = 0,
    this.targetAdu = 30000,
    this.aduTolerance = 10,
    this.panelBrightness,
    this.usePanelControl = false,
    this.errorMessage,
  });

  FlatWizardState copyWith({
    bool? isCapturing,
    FlatWizardMode? mode,
    List<FlatFilterPlan>? filterPlans,
    int? currentFilterIndex,
    int? currentFrameIndex,
    double? targetAdu,
    double? aduTolerance,
    double? panelBrightness,
    bool? usePanelControl,
    String? errorMessage,
  }) {
    return FlatWizardState(
      isCapturing: isCapturing ?? this.isCapturing,
      mode: mode ?? this.mode,
      filterPlans: filterPlans ?? this.filterPlans,
      currentFilterIndex: currentFilterIndex ?? this.currentFilterIndex,
      currentFrameIndex: currentFrameIndex ?? this.currentFrameIndex,
      targetAdu: targetAdu ?? this.targetAdu,
      aduTolerance: aduTolerance ?? this.aduTolerance,
      panelBrightness: panelBrightness ?? this.panelBrightness,
      usePanelControl: usePanelControl ?? this.usePanelControl,
      errorMessage: errorMessage,
    );
  }
}

enum FlatWizardMode { single, batch, skyFlats }

/// Plan for capturing flats with a specific filter
class FlatFilterPlan {
  final String filterName;
  final int frameCount;
  final double targetAdu;
  final double exposureTime;
  final int capturedCount;
  final bool isComplete;

  const FlatFilterPlan({
    required this.filterName,
    required this.frameCount,
    required this.targetAdu,
    required this.exposureTime,
    this.capturedCount = 0,
    this.isComplete = false,
  });

  FlatFilterPlan copyWith({
    String? filterName,
    int? frameCount,
    double? targetAdu,
    double? exposureTime,
    int? capturedCount,
    bool? isComplete,
  }) {
    return FlatFilterPlan(
      filterName: filterName ?? this.filterName,
      frameCount: frameCount ?? this.frameCount,
      targetAdu: targetAdu ?? this.targetAdu,
      exposureTime: exposureTime ?? this.exposureTime,
      capturedCount: capturedCount ?? this.capturedCount,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

class FlatWizardStateNotifier extends StateNotifier<FlatWizardState> {
  final Ref ref;
  bool _cancelRequested = false;

  FlatWizardStateNotifier(this.ref) : super(const FlatWizardState());

  void setMode(FlatWizardMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setTargetAdu(double adu) {
    state = state.copyWith(targetAdu: adu.clamp(5000, 60000));
  }

  void setAduTolerance(double tolerance) {
    state = state.copyWith(aduTolerance: tolerance.clamp(1, 30));
  }

  void setPanelBrightness(double? brightness) {
    state = state.copyWith(panelBrightness: brightness?.clamp(0, 100));
  }

  void setUsePanelControl(bool use) {
    state = state.copyWith(usePanelControl: use);
  }

  void addFilterPlan(FlatFilterPlan plan) {
    state = state.copyWith(filterPlans: [...state.filterPlans, plan]);
  }

  void removeFilterPlan(int index) {
    final plans = [...state.filterPlans];
    if (index >= 0 && index < plans.length) {
      plans.removeAt(index);
      state = state.copyWith(filterPlans: plans);
    }
  }

  void updateFilterPlan(int index, FlatFilterPlan plan) {
    final plans = [...state.filterPlans];
    if (index >= 0 && index < plans.length) {
      plans[index] = plan;
      state = state.copyWith(filterPlans: plans);
    }
  }

  /// Capture a single test frame and return the mean ADU
  Future<double?> captureTestFrame({
    required double exposureTime,
    String? filterName,
  }) async {
    try {
      final backend = ref.read(backendProvider);
      final cameraState = ref.read(cameraStateProvider);
      final deviceId = cameraState.deviceId;

      if (deviceId == null) {
        state = state.copyWith(errorMessage: 'Camera not connected');
        return null;
      }

      // Change filter if specified
      if (filterName != null) {
        final fwState = ref.read(filterWheelStateProvider);
        if (fwState.deviceName != null) {
          final filterIndex = fwState.filterNames.indexOf(filterName);
          if (filterIndex >= 0) {
            await backend.filterWheelSetPosition(fwState.deviceName!, filterIndex);
            // Wait for filter change
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      // Start exposure
      await backend.cameraStartExposure(
        deviceId: deviceId,
        exposureTime: exposureTime,
        frameType: FrameType.flat,
        gain: 0,
        offset: 0,
        binX: 1,
        binY: 1,
      );

      // Wait for exposure
      await Future.delayed(Duration(milliseconds: (exposureTime * 1000 + 500).toInt()));

      // Get the captured image
      final image = await backend.cameraGetLastImage(deviceId);
      if (image == null) {
        state = state.copyWith(errorMessage: 'Failed to retrieve test image');
        return null;
      }

      // Return the mean ADU value
      return image.stats.mean;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Test capture failed: $e');
      debugPrint('FlatWizard: Test capture error: $e');
      return null;
    }
  }

  /// Auto-tune exposure to reach target ADU using binary search
  Future<double?> autoTuneExposure({
    required double minExposure,
    required double maxExposure,
    required double targetAdu,
    required double tolerancePercent,
    String? filterName,
    int maxIterations = 8,
  }) async {
    double lowExp = minExposure;
    double highExp = maxExposure;
    double? lastGoodExposure;
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;

    for (int i = 0; i < maxIterations && !_cancelRequested; i++) {
      final testExposure = (lowExp + highExp) / 2.0;

      debugPrint('FlatWizard: Iteration ${i + 1}, testing exposure: ${testExposure.toStringAsFixed(3)}s');

      final measuredAdu = await captureTestFrame(
        exposureTime: testExposure,
        filterName: filterName,
      );

      if (measuredAdu == null) return null;

      debugPrint('FlatWizard: Measured ADU: ${measuredAdu.toStringAsFixed(0)} (target: ${targetAdu.toStringAsFixed(0)})');

      // Check if within tolerance
      if ((measuredAdu - targetAdu).abs() <= toleranceAdu) {
        debugPrint('FlatWizard: Found optimal exposure: ${testExposure.toStringAsFixed(3)}s');
        return testExposure;
      }

      // Adjust search range
      if (measuredAdu < targetAdu) {
        // Need more light, increase exposure
        lowExp = testExposure;
        lastGoodExposure = testExposure;
      } else {
        // Too bright, decrease exposure
        highExp = testExposure;
        lastGoodExposure = testExposure;
      }

      // Check if range is too narrow
      if ((highExp - lowExp) < 0.001) {
        debugPrint('FlatWizard: Search converged at ${testExposure.toStringAsFixed(3)}s');
        return testExposure;
      }
    }

    // Return the last attempted exposure
    return lastGoodExposure ?? ((minExposure + maxExposure) / 2.0);
  }

  /// Start capturing flat frames
  Future<void> startCapture() async {
    state = state.copyWith(isCapturing: true, errorMessage: null);
    _cancelRequested = false;

    try {
      final backend = ref.read(backendProvider);
      final cameraState = ref.read(cameraStateProvider);
      final deviceId = cameraState.deviceId;

      if (deviceId == null) {
        state = state.copyWith(errorMessage: 'Camera not connected', isCapturing: false);
        return;
      }

      if (state.mode == FlatWizardMode.batch) {
        // Batch mode: capture for each filter plan
        for (int filterIdx = 0; filterIdx < state.filterPlans.length && !_cancelRequested; filterIdx++) {
          state = state.copyWith(currentFilterIndex: filterIdx);
          final plan = state.filterPlans[filterIdx];

          // Change filter if filter wheel is connected
          final fwState = ref.read(filterWheelStateProvider);
          if (fwState.deviceName != null) {
            final filterIndex = fwState.filterNames.indexOf(plan.filterName);
            if (filterIndex >= 0) {
              await backend.filterWheelSetPosition(fwState.deviceName!, filterIndex);
              await Future.delayed(const Duration(seconds: 2));
            }
          }

          // Capture frames for this filter
          for (int frame = 0; frame < plan.frameCount && !_cancelRequested; frame++) {
            state = state.copyWith(currentFrameIndex: frame);

            await backend.cameraStartExposure(
              deviceId: deviceId,
              exposureTime: plan.exposureTime,
              frameType: FrameType.flat,
              gain: 0,
              offset: 0,
              binX: 1,
              binY: 1,
            );

            // Wait for exposure
            await Future.delayed(Duration(milliseconds: (plan.exposureTime * 1000 + 500).toInt()));

            // Update progress
            final updatedPlans = [...state.filterPlans];
            updatedPlans[filterIdx] = plan.copyWith(capturedCount: frame + 1);
            state = state.copyWith(filterPlans: updatedPlans);
          }

          // Mark filter plan complete
          final updatedPlans = [...state.filterPlans];
          updatedPlans[filterIdx] = state.filterPlans[filterIdx].copyWith(isComplete: true);
          state = state.copyWith(filterPlans: updatedPlans);
        }
      } else {
        // Single mode: capture using current settings
        final exposureTime = state.filterPlans.isNotEmpty
            ? state.filterPlans.first.exposureTime
            : 1.0;

        await backend.cameraStartExposure(
          deviceId: deviceId,
          exposureTime: exposureTime,
          frameType: FrameType.flat,
          gain: 0,
          offset: 0,
          binX: 1,
          binY: 1,
        );

        // Wait for exposure
        await Future.delayed(Duration(milliseconds: (exposureTime * 1000 + 500).toInt()));
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Capture failed: $e');
      debugPrint('FlatWizard: Capture error: $e');
    } finally {
      state = state.copyWith(isCapturing: false);
    }
  }

  void stopCapture() {
    _cancelRequested = true;
    state = state.copyWith(isCapturing: false);
  }

  void reset() {
    _cancelRequested = false;
    state = const FlatWizardState();
  }
}

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final wizardState = ref.watch(flatWizardStateProvider);

    return Column(
      children: [
        // Header
        Container(
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
              if (wizardState.isCapturing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(colors.success),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Capturing...',
                        style: TextStyle(
                          color: colors.success,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Tab bar
        Container(
          color: colors.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Quick Capture'),
              Tab(text: 'Multi-Filter Batch'),
              Tab(text: 'Sky Flats'),
            ],
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: colors.border,
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _QuickCaptureTab(colors: colors),
              _BatchCaptureTab(colors: colors),
              _SkyFlatsTab(colors: colors),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick capture tab for simple flat frame capture
class _QuickCaptureTab extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickCaptureTab({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizardState = ref.watch(flatWizardStateProvider);
    final notifier = ref.read(flatWizardStateProvider.notifier);
    final currentAdu = ref.watch(currentAduProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final filterState = ref.watch(filterWheelStateProvider);

    final isConnected = cameraState.connectionState == DeviceConnectionState.connected;

    return Row(
      children: [
        // Left panel - Settings
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(title: 'Target ADU', colors: colors),
                const SizedBox(height: 12),
                _AduSlider(
                  value: wizardState.targetAdu,
                  onChanged: notifier.setTargetAdu,
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _AduToleranceSlider(
                  value: wizardState.aduTolerance,
                  onChanged: notifier.setAduTolerance,
                  colors: colors,
                ),
                const SizedBox(height: 24),

                _SectionHeader(title: 'Current Filter', colors: colors),
                const SizedBox(height: 12),
                _FilterDisplay(
                  filterName: filterState.currentFilterName ?? 'No Filter',
                  colors: colors,
                ),
                const SizedBox(height: 24),

                _SectionHeader(title: 'Panel Control', colors: colors),
                const SizedBox(height: 12),
                _PanelControlSection(
                  isEnabled: wizardState.usePanelControl,
                  brightness: wizardState.panelBrightness,
                  onEnabledChanged: notifier.setUsePanelControl,
                  onBrightnessChanged: notifier.setPanelBrightness,
                  colors: colors,
                ),
                const SizedBox(height: 24),

                _SectionHeader(title: 'Frame Settings', colors: colors),
                const SizedBox(height: 12),
                _FrameCountInput(colors: colors),
              ],
            ),
          ),
        ),

        // Divider
        Container(width: 1, color: colors.border),

        // Right panel - Preview and controls
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Live preview area
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      // Preview header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.image, size: 16, color: colors.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              'Live Preview',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (currentAdu != null) ...[
                              _AduIndicator(
                                currentAdu: currentAdu,
                                targetAdu: wizardState.targetAdu,
                                tolerance: wizardState.aduTolerance,
                                colors: colors,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Preview image area
                      Expanded(
                        child: Center(
                          child: isConnected
                              ? _LivePreviewWidget(colors: colors)
                              : _NoConnectionPlaceholder(colors: colors),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom controls
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Test exposure button
                    OutlinedButton.icon(
                      onPressed: isConnected && !wizardState.isCapturing
                          ? () => _captureTestFrame(ref)
                          : null,
                      icon: const Icon(LucideIcons.testTube, size: 18),
                      label: const Text('Test Exposure'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Auto-tune button
                    OutlinedButton.icon(
                      onPressed: isConnected && !wizardState.isCapturing
                          ? () => _autoTuneExposure(ref)
                          : null,
                      icon: const Icon(LucideIcons.sparkles, size: 18),
                      label: const Text('Auto-Tune'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Capture button
                    ElevatedButton.icon(
                      onPressed: isConnected
                          ? () {
                              if (wizardState.isCapturing) {
                                notifier.stopCapture();
                              } else {
                                notifier.startCapture();
                              }
                            }
                          : null,
                      icon: Icon(
                        wizardState.isCapturing ? LucideIcons.square : LucideIcons.play,
                        size: 18,
                      ),
                      label: Text(wizardState.isCapturing ? 'Stop' : 'Start Capture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            wizardState.isCapturing ? colors.error : colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _captureTestFrame(WidgetRef ref) async {
    final notifier = ref.read(flatWizardStateProvider.notifier);

    // Capture a test frame at 1 second exposure
    final adu = await notifier.captureTestFrame(
      exposureTime: 1.0,
    );

    if (adu != null) {
      ref.read(currentAduProvider.notifier).state = adu;
    }
  }

  Future<void> _autoTuneExposure(WidgetRef ref) async {
    final notifier = ref.read(flatWizardStateProvider.notifier);
    final wizardState = ref.read(flatWizardStateProvider);

    // Auto-tune to find optimal exposure
    final optimalExposure = await notifier.autoTuneExposure(
      minExposure: 0.001,
      maxExposure: 30.0,
      targetAdu: wizardState.targetAdu,
      tolerancePercent: wizardState.aduTolerance,
    );

    if (optimalExposure != null && wizardState.filterPlans.isEmpty) {
      // Add a default plan with the calculated exposure
      notifier.addFilterPlan(FlatFilterPlan(
        filterName: 'L',
        frameCount: 25,
        targetAdu: wizardState.targetAdu,
        exposureTime: optimalExposure,
      ));
    }
  }
}

/// Multi-filter batch capture tab
class _BatchCaptureTab extends ConsumerWidget {
  final NightshadeColors colors;

  const _BatchCaptureTab({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizardState = ref.watch(flatWizardStateProvider);
    final notifier = ref.read(flatWizardStateProvider.notifier);

    return Row(
      children: [
        // Filter plans list
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.list, size: 18, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Filter Plans',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _showAddFilterDialog(context, ref),
                      icon: Icon(LucideIcons.plus, size: 18, color: colors.primary),
                      tooltip: 'Add Filter',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: wizardState.filterPlans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.filter, size: 48, color: colors.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              'No filter plans',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add filters to create a batch plan',
                              style: TextStyle(color: colors.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _showAddFilterDialog(context, ref),
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Add Filter'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: wizardState.filterPlans.length,
                        itemBuilder: (context, index) {
                          final plan = wizardState.filterPlans[index];
                          return _FilterPlanCard(
                            plan: plan,
                            index: index,
                            isActive: index == wizardState.currentFilterIndex &&
                                wizardState.isCapturing,
                            onRemove: () => notifier.removeFilterPlan(index),
                            colors: colors,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        // Divider
        Container(width: 1, color: colors.border),

        // Progress and controls
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Progress overview
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: 'Batch Progress', colors: colors),
                      const SizedBox(height: 16),
                      _BatchProgressWidget(
                        filterPlans: wizardState.filterPlans,
                        currentFilterIndex: wizardState.currentFilterIndex,
                        colors: colors,
                      ),
                      const SizedBox(height: 24),

                      _SectionHeader(title: 'Global Settings', colors: colors),
                      const SizedBox(height: 16),
                      _GlobalSettingsCard(
                        targetAdu: wizardState.targetAdu,
                        aduTolerance: wizardState.aduTolerance,
                        onTargetAduChanged: notifier.setTargetAdu,
                        onToleranceChanged: notifier.setAduTolerance,
                        colors: colors,
                      ),
                    ],
                  ),
                ),
              ),

              // Controls
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: wizardState.filterPlans.isEmpty
                          ? null
                          : () => notifier.reset(),
                      icon: const Icon(LucideIcons.rotateCcw, size: 18),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        side: BorderSide(color: colors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: wizardState.filterPlans.isEmpty
                          ? null
                          : () {
                              if (wizardState.isCapturing) {
                                notifier.stopCapture();
                              } else {
                                notifier.startCapture();
                              }
                            },
                      icon: Icon(
                        wizardState.isCapturing ? LucideIcons.square : LucideIcons.play,
                        size: 18,
                      ),
                      label: Text(wizardState.isCapturing ? 'Stop Batch' : 'Start Batch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            wizardState.isCapturing ? colors.error : colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddFilterDialog(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final filterState = ref.read(filterWheelStateProvider);
    final wizardState = ref.read(flatWizardStateProvider);
    final notifier = ref.read(flatWizardStateProvider.notifier);

    // Get available filters from filter wheel or use defaults
    final availableFilters = filterState.filterNames.isNotEmpty
        ? filterState.filterNames
        : ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];

    String? selectedFilter = availableFilters.isNotEmpty ? availableFilters.first : null;
    double targetAdu = wizardState.targetAdu;
    int frameCount = 25;
    TextEditingController frameController = TextEditingController(text: '25');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Row(
            children: [
              Icon(LucideIcons.plus, color: colors.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                'Add Filter Plan',
                style: TextStyle(color: colors.textPrimary, fontSize: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a filter to add to the batch capture queue',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 20),

                // Filter selection
                Text(
                  'Filter',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButton<String>(
                    value: selectedFilter,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: colors.surface,
                    style: TextStyle(color: colors.textPrimary),
                    items: availableFilters.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedFilter = value);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Target ADU
                Text(
                  'Target ADU',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: colors.primary,
                          inactiveTrackColor: colors.border,
                          thumbColor: colors.primary,
                          overlayColor: colors.primary.withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: targetAdu,
                          min: 10000,
                          max: 55000,
                          divisions: 45,
                          onChanged: (value) {
                            setState(() => targetAdu = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 70,
                      child: Text(
                        targetAdu.toInt().toString(),
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Frame count
                Text(
                  'Frame Count',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: frameController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '25',
                    hintStyle: TextStyle(color: colors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (value) {
                    frameCount = int.tryParse(value) ?? 25;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
            ),
            FilledButton(
              onPressed: selectedFilter != null
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                disabledBackgroundColor: colors.surfaceAlt,
              ),
              child: const Text('Add Filter'),
            ),
          ],
        ),
      ),
    );

    frameController.dispose();

    if (result == true && selectedFilter != null) {
      // Auto-tune exposure for this filter
      final optimalExposure = await notifier.autoTuneExposure(
        minExposure: 0.001,
        maxExposure: 30.0,
        targetAdu: targetAdu,
        tolerancePercent: wizardState.aduTolerance,
        filterName: selectedFilter,
      );

      if (optimalExposure != null) {
        // Add the filter plan with calculated exposure
        notifier.addFilterPlan(FlatFilterPlan(
          filterName: selectedFilter!,
          frameCount: frameCount,
          targetAdu: targetAdu,
          exposureTime: optimalExposure,
        ));

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added $selectedFilter filter: ${optimalExposure.toStringAsFixed(3)}s exposure, $frameCount frames',
              ),
              backgroundColor: colors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to calculate exposure for $selectedFilter'),
              backgroundColor: colors.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Generate sequence from calibration results
  Future<void> _generateSequence(WidgetRef ref) async {
    final wizardState = ref.read(flatWizardStateProvider);
    final flatWizardService = ref.read(flatWizardServiceProvider);
    final sequenceProvider = ref.read(currentSequenceProvider.notifier);

    // Convert filter plans to flat results
    final calibrations = wizardState.filterPlans.map((plan) {
      return FlatResult(
        filter: plan.filterName,
        exposure: plan.exposureTime,
        adu: plan.targetAdu,
        success: true,
      );
    }).toList();

    // Generate sequence
    final sequence = flatWizardService.generateCompleteSequence(
      calibrations: calibrations,
      framesPerFilter: wizardState.filterPlans.first.frameCount,
      sequenceName: 'Flat Frames - ${DateTime.now().toLocal()}',
    );

    // Load into sequence editor
    sequenceProvider.loadSequence(sequence);

//     // Show success message
//     if (context.mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Flat sequence generated successfully'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//     }
  }
}

/// Sky flats tab with dawn/dusk detection
class _SkyFlatsTab extends ConsumerWidget {
  final NightshadeColors colors;

  const _SkyFlatsTab({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skyBrightness = ref.watch(skyBrightnessProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sky brightness monitor
          _SkyBrightnessCard(
            brightness: skyBrightness,
            colors: colors,
            onMeasure: () => _measureSkyBrightness(ref),
          ),
          const SizedBox(height: 20),

          // Timing information
          _SkyTimingCard(colors: colors),
          const SizedBox(height: 20),

          // Auto capture settings
          _SectionHeader(title: 'Auto Capture Settings', colors: colors),
          const SizedBox(height: 12),
          _SkyFlatsSettingsCard(colors: colors),
          const SizedBox(height: 24),

          // Start button
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _startSkyFlatsCapture(ref),
              icon: const Icon(LucideIcons.sunrise, size: 18),
              label: const Text('Start Sky Flats'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Measure sky brightness by taking a short test exposure
  Future<void> _measureSkyBrightness(WidgetRef ref) async {
    final notifier = ref.read(flatWizardStateProvider.notifier);
    final cameraState = ref.read(cameraStateProvider);

    if (cameraState.deviceId == null) {
      return;
    }

    try {
      // Take a 1 second test exposure to measure sky brightness
      final adu = await notifier.captureTestFrame(
        exposureTime: 1.0,
      );

      if (adu != null) {
        // Store sky brightness (ADU per second)
        ref.read(skyBrightnessProvider.notifier).state = adu;
      }
    } catch (e) {
      debugPrint('Failed to measure sky brightness: $e');
    }
  }

  /// Start sky flats capture sequence
  Future<void> _startSkyFlatsCapture(WidgetRef ref) async {
    final wizardState = ref.read(flatWizardStateProvider);
    final notifier = ref.read(flatWizardStateProvider.notifier);
    final cameraState = ref.read(cameraStateProvider);
    final filterState = ref.read(filterWheelStateProvider);

    if (cameraState.deviceId == null) {
      return;
    }

    // If no filter plans exist, create plans for all available filters
    if (wizardState.filterPlans.isEmpty && filterState.filterNames.isNotEmpty) {
      // Auto-generate plans for all filters
      for (final filterName in filterState.filterNames) {
        // Auto-tune exposure for this filter
        final optimalExposure = await notifier.autoTuneExposure(
          minExposure: 0.001,
          maxExposure: 30.0,
          targetAdu: wizardState.targetAdu,
          tolerancePercent: wizardState.aduTolerance,
          filterName: filterName,
        );

        if (optimalExposure != null) {
          notifier.addFilterPlan(FlatFilterPlan(
            filterName: filterName,
            frameCount: 25, // Default frame count
            targetAdu: wizardState.targetAdu,
            exposureTime: optimalExposure,
          ));
        }
      }
    }

    // Start the batch capture
    await notifier.startCapture();
  }
}

// Helper widgets
class _SectionHeader extends StatelessWidget {
  final String title;
  final NightshadeColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    );
  }
}

class _AduSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;

  const _AduSlider({
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Target ADU',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            Text(
              value.toInt().toString(),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.border,
            thumbColor: colors.primary,
            overlayColor: colors.primary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: 10000,
            max: 55000,
            divisions: 45,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _AduToleranceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;

  const _AduToleranceSlider({
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tolerance',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            Text(
              '±${value.toInt()}%',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.textSecondary,
            inactiveTrackColor: colors.border,
            thumbColor: colors.textSecondary,
            overlayColor: colors.textSecondary.withValues(alpha: 0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: 2,
            max: 25,
            divisions: 23,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _FilterDisplay extends ConsumerWidget {
  final String filterName;
  final NightshadeColors colors;

  const _FilterDisplay({required this.filterName, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.filter, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filterName,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showChangeFilterDialog(context, ref),
            child: Text(
              'Change',
              style: TextStyle(color: colors.primary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeFilterDialog(BuildContext context, WidgetRef ref) async {
    final filterState = ref.read(filterWheelStateProvider);
    final backend = ref.read(backendProvider);

    if (filterState.deviceName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Filter wheel not connected'),
          backgroundColor: colors.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (filterState.filterNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No filters available'),
          backgroundColor: colors.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final selectedFilter = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(LucideIcons.filter, color: colors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              'Select Filter',
              style: TextStyle(color: colors.textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: filterState.filterNames.asMap().entries.map((entry) {
              final index = entry.key;
              final filter = entry.value;
              final isCurrent = index == filterState.currentPosition;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.pop(dialogContext, filter),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? colors.primary.withValues(alpha: 0.1)
                          : colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrent ? colors.primary : colors.border,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              filter[0].toUpperCase(),
                              style: TextStyle(
                                color: isCurrent ? colors.primary : colors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            filter,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isCurrent)
                          Icon(LucideIcons.checkCircle2, size: 18, color: colors.primary),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
        ],
      ),
    );

    if (selectedFilter != null && context.mounted) {
      // Change filter
      final filterIndex = filterState.filterNames.indexOf(selectedFilter);
      if (filterIndex >= 0) {
        try {
          await backend.filterWheelSetPosition(filterState.deviceName!, filterIndex);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Changed to $selectedFilter filter'),
                backgroundColor: colors.success,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to change filter: $e'),
                backgroundColor: colors.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }
  }
}

class _PanelControlSection extends StatelessWidget {
  final bool isEnabled;
  final double? brightness;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double?> onBrightnessChanged;
  final NightshadeColors colors;

  const _PanelControlSection({
    required this.isEnabled,
    required this.brightness,
    required this.onEnabledChanged,
    required this.onBrightnessChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sun, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Flat Panel Control',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Switch(
                value: isEnabled,
                onChanged: onEnabledChanged,
                activeTrackColor: colors.primary,
                thumbColor: WidgetStateProperty.all(Colors.white),
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colors.warning,
                      inactiveTrackColor: colors.border,
                      thumbColor: colors.warning,
                      overlayColor: colors.warning.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: brightness ?? 50,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (v) => onBrightnessChanged(v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(brightness ?? 50).toInt()}%',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FrameCountInput extends StatelessWidget {
  final NightshadeColors colors;

  const _FrameCountInput({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.hash, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Frames',
            style: TextStyle(color: colors.textPrimary),
          ),
          const Spacer(),
          SizedBox(
            width: 80,
            height: 32,
            child: TextField(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              controller: TextEditingController(text: '20'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AduIndicator extends StatelessWidget {
  final double currentAdu;
  final double targetAdu;
  final double tolerance;
  final NightshadeColors colors;

  const _AduIndicator({
    required this.currentAdu,
    required this.targetAdu,
    required this.tolerance,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final lowerBound = targetAdu * (1 - tolerance / 100);
    final upperBound = targetAdu * (1 + tolerance / 100);
    final isInRange = currentAdu >= lowerBound && currentAdu <= upperBound;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isInRange
            ? colors.success.withValues(alpha: 0.1)
            : colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInRange
              ? colors.success.withValues(alpha: 0.3)
              : colors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInRange ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
            size: 14,
            color: isInRange ? colors.success : colors.warning,
          ),
          const SizedBox(width: 6),
          Text(
            'ADU: ${currentAdu.toInt()}',
            style: TextStyle(
              color: isInRange ? colors.success : colors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePreviewWidget extends StatelessWidget {
  final NightshadeColors colors;

  const _LivePreviewWidget({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.image, size: 64, color: colors.textMuted),
        const SizedBox(height: 16),
        Text(
          'Take a test exposure to preview',
          style: TextStyle(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _NoConnectionPlaceholder extends StatelessWidget {
  final NightshadeColors colors;

  const _NoConnectionPlaceholder({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.cameraOff, size: 64, color: colors.textMuted),
        const SizedBox(height: 16),
        Text(
          'Camera not connected',
          style: TextStyle(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect a camera in Equipment settings',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _FilterPlanCard extends StatelessWidget {
  final FlatFilterPlan plan;
  final int index;
  final bool isActive;
  final VoidCallback onRemove;
  final NightshadeColors colors;

  const _FilterPlanCard({
    required this.plan,
    required this.index,
    required this.isActive,
    required this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? colors.primary : colors.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                plan.filterName[0].toUpperCase(),
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.filterName,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.capturedCount}/${plan.frameCount} frames • ADU ${plan.targetAdu.toInt()}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (plan.isComplete)
            Icon(LucideIcons.checkCircle2, size: 18, color: colors.success)
          else if (isActive)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _BatchProgressWidget extends StatelessWidget {
  final List<FlatFilterPlan> filterPlans;
  final int currentFilterIndex;
  final NightshadeColors colors;

  const _BatchProgressWidget({
    required this.filterPlans,
    required this.currentFilterIndex,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (filterPlans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'Add filter plans to see progress',
            style: TextStyle(color: colors.textMuted),
          ),
        ),
      );
    }

    final totalFrames = filterPlans.fold<int>(0, (sum, p) => sum + p.frameCount);
    final capturedFrames = filterPlans.fold<int>(0, (sum, p) => sum + p.capturedCount);
    final progress = totalFrames > 0 ? capturedFrames / totalFrames : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Progress',
                style: TextStyle(color: colors.textSecondary),
              ),
              Text(
                '$capturedFrames / $totalFrames frames',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.border,
              valueColor: AlwaysStoppedAnimation(colors.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalSettingsCard extends StatelessWidget {
  final double targetAdu;
  final double aduTolerance;
  final ValueChanged<double> onTargetAduChanged;
  final ValueChanged<double> onToleranceChanged;
  final NightshadeColors colors;

  const _GlobalSettingsCard({
    required this.targetAdu,
    required this.aduTolerance,
    required this.onTargetAduChanged,
    required this.onToleranceChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          _AduSlider(
            value: targetAdu,
            onChanged: onTargetAduChanged,
            colors: colors,
          ),
          const SizedBox(height: 12),
          _AduToleranceSlider(
            value: aduTolerance,
            onChanged: onToleranceChanged,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _SkyBrightnessCard extends ConsumerWidget {
  final double? brightness;
  final NightshadeColors colors;
  final VoidCallback onMeasure;

  const _SkyBrightnessCard({
    required this.brightness,
    required this.colors,
    required this.onMeasure,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.1),
            colors.surfaceAlt,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.sunrise, size: 32, color: colors.primary),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sky Brightness',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  brightness != null
                      ? '${brightness!.toStringAsFixed(1)} ADU/s'
                      : 'Not measured',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onMeasure,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Measure'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkyTimingCard extends StatelessWidget {
  final NightshadeColors colors;

  const _SkyTimingCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    // TODO: Get actual astronomical times
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _TimeInfo(
            label: 'Nautical Dawn',
            time: '05:32',
            icon: LucideIcons.sunrise,
            colors: colors,
          ),
          const SizedBox(width: 20),
          _TimeInfo(
            label: 'Civil Dawn',
            time: '06:04',
            icon: LucideIcons.sun,
            colors: colors,
          ),
          const SizedBox(width: 20),
          _TimeInfo(
            label: 'Sunrise',
            time: '06:34',
            icon: LucideIcons.sunDim,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _TimeInfo extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final NightshadeColors colors;

  const _TimeInfo({
    required this.label,
    required this.time,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: colors.textSecondary),
          const SizedBox(height: 8),
          Text(
            time,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SkyFlatsSettingsCard extends StatelessWidget {
  final NightshadeColors colors;

  const _SkyFlatsSettingsCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(LucideIcons.clock, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Start Time', style: TextStyle(color: colors.textPrimary)),
              const Spacer(),
              DropdownButton<String>(
                value: 'Dawn',
                items: const [
                  DropdownMenuItem(value: 'Dawn', child: Text('Dawn')),
                  DropdownMenuItem(value: 'Dusk', child: Text('Dusk')),
                ],
                onChanged: (value) {},
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                dropdownColor: colors.surface,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.zap, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Auto-adjust exposure', style: TextStyle(color: colors.textPrimary)),
              const Spacer(),
              Switch(
                value: true,
                onChanged: (v) {},
                activeTrackColor: colors.primary,
                thumbColor: WidgetStateProperty.all(Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
