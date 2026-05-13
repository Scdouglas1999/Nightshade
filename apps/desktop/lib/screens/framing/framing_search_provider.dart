import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// State for the target search in Framing tool
class TargetSearchState {
  final String query;
  final List<FramingTarget> results;
  final bool isSearching;

  const TargetSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
  });

  TargetSearchState copyWith({
    String? query,
    List<FramingTarget>? results,
    bool? isSearching,
  }) {
    return TargetSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

class TargetSearchNotifier extends StateNotifier<TargetSearchState> {
  final Ref _ref;

  TargetSearchNotifier(this._ref) : super(const TargetSearchState());

  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = const TargetSearchState();
      return;
    }

    state = state.copyWith(query: query, isSearching: true);

    try {
      final results = <FramingTarget>[];
      final qLower = query.toLowerCase().trim();

      // Normalize query
      final normalizedQuery = qLower.replaceAll(RegExp(r'\s+'), '');

      // Search DSOs using the planetarium's loaded database
      try {
        final loadedDsos = await _ref.read(loadedDsosProvider.future);

        final matchingDsos = loadedDsos
            .where((o) {
              final idLower = o.id.toLowerCase();
              final nameLower = o.name.toLowerCase();

              // Direct matches
              if (idLower.contains(qLower) || nameLower.contains(qLower)) {
                return true;
              }
              if (o.catalogIds.any((c) => c.toLowerCase().contains(qLower))) {
                return true;
              }

              // Normalized matches
              final normalizedId = idLower.replaceAll(RegExp(r'\s+'), '');
              if (normalizedId.contains(normalizedQuery)) return true;

              final normalizedName = nameLower.replaceAll(RegExp(r'\s+'), '');
              if (normalizedName.contains(normalizedQuery)) return true;

              if (o.catalogIds.any((c) {
                final cNormalized =
                    c.toLowerCase().replaceAll(RegExp(r'\s+'), '');
                return cNormalized.contains(normalizedQuery);
              })) {
                return true;
              }

              return false;
            })
            .take(50)
            .toList();

        // Convert to FramingTarget
        for (final dso in matchingDsos) {
          TargetType targetType;
          switch (dso.type) {
            case DsoType.galaxy:
            case DsoType.galaxyPair:
            case DsoType.galaxyTriplet:
            case DsoType.galaxyGroup:
              targetType = TargetType.galaxy;
              break;
            case DsoType.nebula:
            case DsoType.emissionNebula:
            case DsoType.reflectionNebula:
            case DsoType.planetaryNebula:
            case DsoType.darkNebula:
            case DsoType.hiiRegion:
            case DsoType.supernova:
              targetType = TargetType.nebula;
              break;
            case DsoType.openCluster:
            case DsoType.globularCluster:
            case DsoType.clusterWithNebulosity:
            case DsoType.association:
            case DsoType.starCloud:
              targetType = TargetType.cluster;
              break;
            case DsoType.star:
            case DsoType.doubleStar:
            case DsoType.nova:
              targetType = TargetType.star;
              break;
            default:
              targetType = TargetType.other;
          }

          results.add(FramingTarget(
            name: dso.name,
            raHours: dso.coordinates.ra,
            decDegrees: dso.coordinates.dec,
            catalogId: dso.id,
            magnitude: dso.magnitude,
            sizeArcmin: dso.sizeArcMin,
            type: targetType,
          ));
        }
      } catch (e) {
        _ref.read(loggingServiceProvider).error(
          'Framing search failed',
          source: 'FramingSearch',
          fields: {'error': '$e', 'query': query},
        );
      }

      // Sort results
      results.sort((a, b) {
        // Exact matches first (including normalized)
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        final aId = a.catalogId?.toLowerCase();
        final bId = b.catalogId?.toLowerCase();

        // Check exact match
        bool isExact(String val) => val == qLower || val == normalizedQuery;

        final aExact = isExact(aName) || (aId != null && isExact(aId));
        final bExact = isExact(bName) || (bId != null && isExact(bId));

        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        // Then by magnitude (brighter first)
        return (a.magnitude ?? 99).compareTo(b.magnitude ?? 99);
      });

      state = TargetSearchState(
        query: query,
        results: results,
        isSearching: false,
      );
    } catch (e) {
      state = TargetSearchState(
        query: query,
        results: [],
        isSearching: false,
      );
    }
  }

  void clear() {
    state = const TargetSearchState();
  }
}

final targetSearchProvider =
    StateNotifierProvider<TargetSearchNotifier, TargetSearchState>((ref) {
  return TargetSearchNotifier(ref);
});
