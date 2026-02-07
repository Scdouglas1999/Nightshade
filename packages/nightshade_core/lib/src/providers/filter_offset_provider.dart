import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/focus_model_service.dart';
import 'profiles_provider.dart';
import 'equipment_provider.dart';

/// Filter offset state for the current profile
class FilterOffsetState {
  final Map<String, int> offsets; // filterName -> offset in steps
  final String? referenceFilter;
  final bool isLoading;
  final String? error;

  const FilterOffsetState({
    this.offsets = const {},
    this.referenceFilter,
    this.isLoading = false,
    this.error,
  });

  FilterOffsetState copyWith({
    Map<String, int>? offsets,
    String? referenceFilter,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return FilterOffsetState(
      offsets: offsets ?? this.offsets,
      referenceFilter: referenceFilter ?? this.referenceFilter,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for managing filter offsets
class FilterOffsetNotifier extends StateNotifier<FilterOffsetState> {
  final Ref _ref;
  String? _currentProfileId;

  FilterOffsetNotifier(this._ref) : super(const FilterOffsetState()) {
    _init();
  }

  /// Initialize by loading offsets for active profile
  Future<void> _init() async {
    await _loadOffsetsForActiveProfile();
  }

  /// Load offsets for the currently active profile
  Future<void> _loadOffsetsForActiveProfile() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile == null) {
        state = const FilterOffsetState();
        return;
      }

      _currentProfileId = activeProfile.id.toString();

      // Get focus data from service
      final focusService = _ref.read(focusModelServiceProvider);
      await focusService.initialize();

      final focusData = focusService.getProfileData(_currentProfileId!);

      if (focusData == null) {
        state = FilterOffsetState(
          offsets: {},
          referenceFilter: null,
          isLoading: false,
        );
        return;
      }

      // Convert FilterOffset objects to simple int map
      final offsetMap = <String, int>{};
      for (final entry in focusData.filterOffsets.entries) {
        offsetMap[entry.key] = entry.value.offsetSteps;
      }

      state = FilterOffsetState(
        offsets: offsetMap,
        referenceFilter: focusData.referenceFilter,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load filter offsets: $e',
      );
    }
  }

  /// Set offset for a specific filter
  Future<void> setFilterOffset(String filterName, int offsetSteps) async {
    if (_currentProfileId == null) return;

    try {
      final newOffsets = Map<String, int>.from(state.offsets);
      newOffsets[filterName] = offsetSteps;

      state = state.copyWith(offsets: newOffsets);

      // Save to focus model service
      await _saveOffsetsToService();
    } catch (e) {
      state = state.copyWith(error: 'Failed to save filter offset: $e');
    }
  }

  /// Adjust offset by a delta amount
  Future<void> adjustFilterOffset(String filterName, int delta) async {
    final currentOffset = state.offsets[filterName] ?? 0;
    await setFilterOffset(filterName, currentOffset + delta);
  }

  /// Set the reference filter (all offsets are relative to this)
  Future<void> setReferenceFilter(String filterName) async {
    if (_currentProfileId == null) return;

    try {
      final focusService = _ref.read(focusModelServiceProvider);
      await focusService.setReferenceFilter(_currentProfileId!, filterName);

      state = state.copyWith(referenceFilter: filterName);

      // Reload offsets after changing reference
      await _loadOffsetsForActiveProfile();
    } catch (e) {
      state = state.copyWith(error: 'Failed to set reference filter: $e');
    }
  }

  /// Clear all offsets
  Future<void> clearAllOffsets() async {
    if (_currentProfileId == null) return;

    try {
      final focusService = _ref.read(focusModelServiceProvider);
      await focusService.clearProfileData(_currentProfileId!);

      state = FilterOffsetState(
        offsets: {},
        referenceFilter: state.referenceFilter,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to clear offsets: $e');
    }
  }

  /// Get offset for a specific filter
  int getOffset(String filterName) {
    return state.offsets[filterName] ?? 0;
  }

  /// Save current offsets to focus model service and persist to disk
  Future<void> _saveOffsetsToService() async {
    if (_currentProfileId == null) return;

    final focusService = _ref.read(focusModelServiceProvider);

    // Build FilterOffset map from current state
    final updatedOffsets = <String, FilterOffset>{};
    for (final entry in state.offsets.entries) {
      updatedOffsets[entry.key] = FilterOffset(
        filterName: entry.key,
        referenceFilter: state.referenceFilter ?? 'L',
        offsetSteps: entry.value,
        measurementCount: 1,
        confidence: 1.0,
      );
    }

    await focusService.updateFilterOffsets(
      _currentProfileId!,
      updatedOffsets,
      referenceFilter: state.referenceFilter,
    );
  }

  /// Reload offsets (call this when profile changes)
  Future<void> reload() async {
    await _loadOffsetsForActiveProfile();
  }
}

/// Provider for filter offsets
final filterOffsetProvider =
    StateNotifierProvider<FilterOffsetNotifier, FilterOffsetState>((ref) {
  return FilterOffsetNotifier(ref);
});

/// Helper provider to get offset for a specific filter
final filterOffsetForFilterProvider =
    Provider.family<int, String>((ref, filterName) {
  final state = ref.watch(filterOffsetProvider);
  return state.offsets[filterName] ?? 0;
});

/// Provider to get available filter names from connected filter wheel
final availableFiltersProvider = Provider<List<String>>((ref) {
  final filterWheelState = ref.watch(filterWheelStateProvider);
  return filterWheelState.filterNames;
});
