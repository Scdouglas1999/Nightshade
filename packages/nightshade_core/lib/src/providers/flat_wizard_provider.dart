import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/flat_wizard/flat_wizard_state.dart';
import '../models/flat_wizard/flat_wizard_settings.dart';
import '../services/sky_brightness_tracker.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'profiles_provider.dart';

/// Provider for flat wizard state
final flatWizardProvider =
    StateNotifierProvider<FlatWizardNotifier, FlatWizardState>((ref) {
  return FlatWizardNotifier(ref);
});

/// Provider for sky brightness tracker (sky flats mode)
final skyBrightnessTrackerProvider = Provider<SkyBrightnessTracker>((ref) {
  return SkyBrightnessTracker();
});

class FlatWizardNotifier extends StateNotifier<FlatWizardState> {
  final Ref ref;
  bool _cancelRequested = false;

  FlatWizardNotifier(this.ref) : super(const FlatWizardState());

  // --- Mode Management ---

  void setMode(FlatWizardMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setTwilightMode(TwilightMode mode) {
    state = state.copyWith(twilightMode: mode);
  }

  // --- Global Settings ---

  void updateGlobalSettings(FlatWizardGlobalSettings settings) {
    state = state.copyWith(globalSettings: settings);
  }

  void setHistogramTarget(double percent) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        histogramTarget: percent.clamp(0, 100),
      ),
    );
  }

  void setTolerance(double percent) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        tolerancePercent: percent.clamp(1, 25),
      ),
    );
  }

  void setFrameCount(int count) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        frameCount: count.clamp(1, 999),
      ),
    );
  }

  void setSavePath(String? path) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(savePath: path),
    );
  }

  // --- Filter Management ---

  /// Load filters from connected filter wheel
  Future<void> loadFiltersFromWheel() async {
    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.filterNames.isEmpty) return;

    final db = ref.read(databaseProvider);
    final profileId = ref.read(activeEquipmentProfileProvider)?.id;

    final filterSettings = <FlatFilterSettings>[];
    for (int i = 0; i < fwState.filterNames.length; i++) {
      final filterName = fwState.filterNames[i];

      // Get suggested exposure from history
      final suggested = await db.flatHistoryDao.getSuggestedExposure(
        filterName: filterName,
        equipmentProfileId: profileId,
      );

      filterSettings.add(FlatFilterSettings(
        filterName: filterName,
        filterPosition: i,
        suggestedExposure: suggested,
      ));
    }

    state = state.copyWith(filterSettings: filterSettings);
  }

  /// Toggle filter enabled state
  void toggleFilter(int index, bool enabled) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(enabled: enabled);
    state = state.copyWith(filterSettings: updated);
  }

  /// Update per-filter settings
  void updateFilterSettings(int index, FlatFilterSettings settings) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = settings;
    state = state.copyWith(filterSettings: updated);
  }

  /// Reorder filters
  void reorderFilters(int oldIndex, int newIndex) {
    final updated = [...state.filterSettings];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex < oldIndex ? newIndex : newIndex - 1, item);
    state = state.copyWith(filterSettings: updated);
  }

  /// Auto-order filters for twilight
  void autoOrderForTwilight() {
    if (state.filterSettings.isEmpty) return;

    // Define filter restrictiveness (higher = more restrictive = less light)
    const restrictiveness = {
      'Ha': 100, 'H-alpha': 100, 'Halpha': 100,
      'SII': 95, 'S-II': 95, 'S2': 95,
      'OIII': 90, 'O-III': 90, 'O3': 90,
      'NII': 85, 'N-II': 85,
      'R': 50, 'Red': 50,
      'G': 45, 'Green': 45,
      'B': 40, 'Blue': 40,
      'L': 10, 'Lum': 10, 'Luminance': 10, 'Clear': 10,
    };

    int getRestrictiveness(String filter) {
      for (final entry in restrictiveness.entries) {
        if (filter.toLowerCase().contains(entry.key.toLowerCase())) {
          return entry.value;
        }
      }
      return 50; // Default middle value
    }

    final sorted = [...state.filterSettings];
    sorted.sort((a, b) {
      final aVal = getRestrictiveness(a.filterName);
      final bVal = getRestrictiveness(b.filterName);

      if (state.twilightMode == TwilightMode.dusk) {
        // Dusk (darkening): most restrictive first
        return bVal.compareTo(aVal);
      } else {
        // Dawn (brightening): least restrictive first
        return aVal.compareTo(bVal);
      }
    });

    state = state.copyWith(filterSettings: sorted);
  }

  // --- Visualization Toggles ---

  void toggleAduGraph(bool show) {
    state = state.copyWith(showAduGraph: show);
  }

  void toggleExposureTimeline(bool show) {
    state = state.copyWith(showExposureTimeline: show);
  }

  void toggleSkyBrightness(bool show) {
    state = state.copyWith(showSkyBrightness: show);
  }

  void toggleFilterCards(bool show) {
    state = state.copyWith(showFilterCards: show);
  }

  void toggleHistogramOverlay(bool show) {
    state = state.copyWith(showHistogramOverlay: show);
  }

  // --- Capture Control ---

  void requestCancel() {
    _cancelRequested = true;
    state = state.copyWith(statusMessage: 'Cancelling...');
  }

  bool get cancelRequested => _cancelRequested;

  void clearCancelRequest() {
    _cancelRequested = false;
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearWarning() {
    state = state.copyWith(warningMessage: null);
  }

  void setStatusMessage(String? message) {
    state = state.copyWith(statusMessage: message);
  }

  void setErrorMessage(String? message) {
    state = state.copyWith(errorMessage: message);
  }

  void setWarningMessage(String? message) {
    state = state.copyWith(warningMessage: message);
  }

  void setCapturing(bool capturing) {
    state = state.copyWith(isCapturing: capturing);
  }

  void setExposing(bool exposing, {DateTime? startTime, double? duration}) {
    state = state.copyWith(
      isExposing: exposing,
      exposureStartTime: startTime,
      currentExposureDuration: duration,
    );
  }

  // --- ADU History ---

  void addAduMeasurement(double exposure, double adu) {
    final measurement = AduMeasurement(
      exposure: exposure,
      adu: adu,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      aduHistory: [...state.aduHistory, measurement],
    );
  }

  void clearAduHistory() {
    state = state.copyWith(aduHistory: []);
  }

  // --- Image Preview ---

  void setLastImage(String? path, dynamic imageData) {
    state = state.copyWith(
      lastImagePath: path,
      lastImageData: imageData,
    );
  }

  // --- Filter Progress ---

  void setCurrentFilterIndex(int index) {
    state = state.copyWith(currentFilterIndex: index);
  }

  void setCurrentFrameIndex(int index) {
    state = state.copyWith(currentFrameIndex: index);
  }

  void updateFilterStatus(int index, FilterCalibrationStatus status) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(status: status);
    state = state.copyWith(filterSettings: updated);
  }

  void updateFilterCalibration(int index, double exposure, double adu) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(
      calibratedExposure: exposure,
      currentAdu: adu,
    );
    state = state.copyWith(filterSettings: updated);
  }

  void incrementFilterCapturedCount(int index) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(
      capturedCount: updated[index].capturedCount + 1,
    );
    state = state.copyWith(filterSettings: updated);
  }

  // --- Reset ---

  void reset() {
    _cancelRequested = false;
    state = const FlatWizardState();
  }
}
