import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planning/target_suggestion.dart';
import 'target_suggestion_provider.dart';

// ============================================================================
// Filter State
// ============================================================================

/// Client-side filter state for narrowing down the suggestions list.
///
/// All fields default to null / empty, which means "no filter applied".
/// This sits between [tonightSuggestionsProvider] and the UI — the scoring
/// service and [TargetSuggestionConfig] are never modified by these filters.
class SuggestionFilterState {
  final double? minMagnitude;
  final double? maxMagnitude;
  final double? minSizeArcmin;
  final double? maxSizeArcmin;
  final Set<String> selectedConstellations;
  final double? minMoonDistance;
  final double? minImagingHours;

  const SuggestionFilterState({
    this.minMagnitude,
    this.maxMagnitude,
    this.minSizeArcmin,
    this.maxSizeArcmin,
    this.selectedConstellations = const {},
    this.minMoonDistance,
    this.minImagingHours,
  });

  SuggestionFilterState copyWith({
    double? Function()? minMagnitude,
    double? Function()? maxMagnitude,
    double? Function()? minSizeArcmin,
    double? Function()? maxSizeArcmin,
    Set<String>? selectedConstellations,
    double? Function()? minMoonDistance,
    double? Function()? minImagingHours,
  }) {
    return SuggestionFilterState(
      minMagnitude: minMagnitude != null ? minMagnitude() : this.minMagnitude,
      maxMagnitude: maxMagnitude != null ? maxMagnitude() : this.maxMagnitude,
      minSizeArcmin:
          minSizeArcmin != null ? minSizeArcmin() : this.minSizeArcmin,
      maxSizeArcmin:
          maxSizeArcmin != null ? maxSizeArcmin() : this.maxSizeArcmin,
      selectedConstellations:
          selectedConstellations ?? this.selectedConstellations,
      minMoonDistance:
          minMoonDistance != null ? minMoonDistance() : this.minMoonDistance,
      minImagingHours:
          minImagingHours != null ? minImagingHours() : this.minImagingHours,
    );
  }

  /// Returns the number of active (non-default) filters.
  int get activeCount {
    int count = 0;
    if (minMagnitude != null) count++;
    if (maxMagnitude != null) count++;
    if (minSizeArcmin != null) count++;
    if (maxSizeArcmin != null) count++;
    if (selectedConstellations.isNotEmpty) count++;
    if (minMoonDistance != null) count++;
    if (minImagingHours != null) count++;
    return count;
  }
}

// ============================================================================
// Providers
// ============================================================================

/// Holds the current UI filter state. Defaults = no filtering.
final suggestionFilterProvider =
    StateProvider<SuggestionFilterState>((ref) => const SuggestionFilterState());

/// Applies [SuggestionFilterState] on top of [tonightSuggestionsProvider].
///
/// The upstream provider handles scoring, sorting, min-altitude, min-score,
/// object-type, and sort-mode. This provider only does additional client-side
/// filtering on the already-generated list.
final filteredSuggestionsProvider =
    Provider.autoDispose<AsyncValue<List<TargetSuggestion>>>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);
  final filters = ref.watch(suggestionFilterProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      final filtered = _applyFilters(suggestions, filters);
      return AsyncData(filtered);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

List<TargetSuggestion> _applyFilters(
  List<TargetSuggestion> suggestions,
  SuggestionFilterState filters,
) {
  // Fast path: no filters active
  if (filters.activeCount == 0) return suggestions;

  return suggestions.where((s) {
    // Magnitude filter
    if (filters.minMagnitude != null) {
      // Null magnitude passes if no filter set — but we have a filter,
      // so null magnitude means we can't evaluate; skip the target.
      if (s.magnitude == null) return false;
      if (s.magnitude! < filters.minMagnitude!) return false;
    }
    if (filters.maxMagnitude != null) {
      if (s.magnitude == null) return false;
      if (s.magnitude! > filters.maxMagnitude!) return false;
    }

    // Size filter
    if (filters.minSizeArcmin != null) {
      if (s.sizeArcmin == null) return false;
      if (s.sizeArcmin! < filters.minSizeArcmin!) return false;
    }
    if (filters.maxSizeArcmin != null) {
      if (s.sizeArcmin == null) return false;
      if (s.sizeArcmin! > filters.maxSizeArcmin!) return false;
    }

    // Constellation filter — empty set = no filter
    if (filters.selectedConstellations.isNotEmpty) {
      if (s.constellation == null) return false;
      if (!filters.selectedConstellations.contains(s.constellation)) {
        return false;
      }
    }

    // Moon distance filter
    if (filters.minMoonDistance != null) {
      if (s.visibility.moonDistance < filters.minMoonDistance!) return false;
    }

    // Imaging hours filter
    if (filters.minImagingHours != null) {
      final hours = s.visibility.hoursAboveMinAlt;
      if (hours == null) return false;
      if (hours < filters.minImagingHours!) return false;
    }

    return true;
  }).toList();
}

// ============================================================================
// Derived / Convenience Providers
// ============================================================================

/// Extracts sorted unique constellation abbreviations from the full
/// (unfiltered) suggestion list.
final availableConstellationsProvider =
    Provider.autoDispose<List<String>>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      final constellations = <String>{};
      for (final s in suggestions) {
        if (s.constellation != null && s.constellation!.isNotEmpty) {
          constellations.add(s.constellation!);
        }
      }
      final sorted = constellations.toList()..sort();
      return sorted;
    },
    loading: () => <String>[],
    error: (_, __) => <String>[],
  );
});

/// Returns the (min, max) magnitude range present in the unfiltered data.
/// Returns null if no suggestions have magnitude data.
final availableMagnitudeRangeProvider =
    Provider.autoDispose<(double, double)?>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      double? lo;
      double? hi;
      for (final s in suggestions) {
        if (s.magnitude != null) {
          final m = s.magnitude!;
          if (lo == null || m < lo) lo = m;
          if (hi == null || m > hi) hi = m;
        }
      }
      if (lo == null || hi == null) return null;
      return (lo, hi);
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Returns the (min, max) angular size range (arcmin) present in the
/// unfiltered data. Returns null if no suggestions have size data.
final availableSizeRangeProvider =
    Provider.autoDispose<(double, double)?>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      double? lo;
      double? hi;
      for (final s in suggestions) {
        if (s.sizeArcmin != null && s.sizeArcmin! > 0) {
          final sz = s.sizeArcmin!;
          if (lo == null || sz < lo) lo = sz;
          if (hi == null || sz > hi) hi = sz;
        }
      }
      if (lo == null || hi == null) return null;
      return (lo, hi);
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Count of active UI filters (for badge display).
final activeFilterCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(suggestionFilterProvider).activeCount;
});
