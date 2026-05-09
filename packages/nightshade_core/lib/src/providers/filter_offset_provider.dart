import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/imaging/imaging_models.dart' show AutofocusSettings;
import '../services/focus_model_service.dart';
import 'profiles_provider.dart';
import 'equipment_provider.dart';
import 'settings_provider.dart';

/// Offset interpretation mode for filter focus offsets.
enum FilterOffsetMode {
  /// Offsets are relative to a reference filter (default / classic behavior).
  relative,

  /// Offsets are absolute focuser positions per filter.
  absolute,
}

/// Filter offset state for the current profile
class FilterOffsetState {
  final Map<String, int> offsets; // filterName -> offset in steps
  final String? referenceFilter;
  final bool isLoading;
  final String? error;

  /// Whether offsets represent absolute positions or relative-to-reference.
  final FilterOffsetMode offsetMode;

  const FilterOffsetState({
    this.offsets = const {},
    this.referenceFilter,
    this.isLoading = false,
    this.error,
    this.offsetMode = FilterOffsetMode.relative,
  });

  FilterOffsetState copyWith({
    Map<String, int>? offsets,
    String? referenceFilter,
    bool? isLoading,
    String? error,
    bool clearError = false,
    FilterOffsetMode? offsetMode,
  }) {
    return FilterOffsetState(
      offsets: offsets ?? this.offsets,
      referenceFilter: referenceFilter ?? this.referenceFilter,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      offsetMode: offsetMode ?? this.offsetMode,
    );
  }
}

/// Notifier for managing filter offsets
class FilterOffsetNotifier extends StateNotifier<FilterOffsetState> {
  final Ref _ref;
  String? _currentProfileId;
  int _loadGeneration = 0;

  FilterOffsetNotifier(this._ref)
      : super(const FilterOffsetState(isLoading: true)) {
    unawaited(_init());
    // Reload offsets whenever the active equipment profile changes
    _ref.listen(activeEquipmentProfileProvider, (_, __) {
      unawaited(_loadOffsetsForActiveProfile());
    });
  }

  /// Initialize by loading offsets for active profile
  Future<void> _init() async {
    await _loadOffsetsForActiveProfile();
  }

  /// Determine the offset mode from AppSettings.
  ///
  /// When `useFilterFocusOffsets` is enabled AND per-filter AF configs contain
  /// absolute focus positions, we operate in absolute mode. Otherwise we use
  /// relative mode (offsets relative to a reference filter).
  FilterOffsetMode _resolveOffsetMode() {
    final settingsAsync = _ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings == null) return FilterOffsetMode.relative;

    if (!settings.useFilterFocusOffsets) return FilterOffsetMode.relative;

    // Check if the AF backlash compensation method is 'Absolute' as a hint
    // that the user wants absolute offsets.
    if (settings.afBacklashCompMethod == 'Absolute') {
      return FilterOffsetMode.absolute;
    }
    return FilterOffsetMode.relative;
  }

  /// Load offsets for the currently active profile
  Future<void> _loadOffsetsForActiveProfile() async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile == null) {
        if (generation == _loadGeneration) {
          state = const FilterOffsetState();
        }
        return;
      }

      _currentProfileId = activeProfile.id.toString();

      final offsetMode = _resolveOffsetMode();

      // Get focus data from service
      final focusService = _ref.read(focusModelServiceProvider);
      await focusService.initialize();

      final focusData = focusService.getProfileData(_currentProfileId!);

      if (focusData == null) {
        if (generation == _loadGeneration) {
          state = FilterOffsetState(
            offsets: {},
            referenceFilter: null,
            isLoading: false,
            offsetMode: offsetMode,
          );
        }
        return;
      }

      final offsetMap = <String, int>{};

      if (offsetMode == FilterOffsetMode.absolute) {
        // In absolute mode, use ONLY the per-filter AF config focusOffset
        // values from AppSettings. The focusData.filterOffsets are relative
        // to a reference filter and must NOT be mixed with absolute positions.
        final settingsAsync = _ref.read(appSettingsProvider);
        final settings = settingsAsync.valueOrNull;
        if (settings != null) {
          final afFilterSettings = AutofocusSettings.parseFilterSettingsJson(
              settings.afFilterSettingsJson);
          for (final entry in afFilterSettings.entries) {
            if (entry.value.focusOffset != 0) {
              offsetMap[entry.key] = entry.value.focusOffset;
            }
          }
        }
      } else {
        // In relative mode, convert FilterOffset objects to simple int map.
        // These offsets are relative to the reference filter.
        for (final entry in focusData.filterOffsets.entries) {
          offsetMap[entry.key] = entry.value.offsetSteps;
        }
      }

      if (generation == _loadGeneration) {
        state = FilterOffsetState(
          offsets: offsetMap,
          referenceFilter: focusData.referenceFilter,
          isLoading: false,
          offsetMode: offsetMode,
        );
      }
    } catch (e) {
      if (generation == _loadGeneration) {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load filter offsets: $e',
        );
      }
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
