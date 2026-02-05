import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../database/database.dart' as db;
import '../models/planning/target_suggestion.dart';
import '../services/logging_service.dart';
import '../services/target_suggestion_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

// ============================================================================
// Service Provider
// ============================================================================

/// Provider for the target suggestion service.
final targetSuggestionServiceProvider = Provider<TargetSuggestionService>((ref) {
  final logging = ref.watch(loggingServiceProvider);
  return TargetSuggestionService(loggingService: logging);
});

// ============================================================================
// Configuration Provider
// ============================================================================

/// Provider for target suggestion configuration.
///
/// This allows the UI to modify filter and sort settings for suggestions.
/// Default values provide sensible defaults for most imaging scenarios.
final targetSuggestionConfigProvider =
    StateProvider<TargetSuggestionConfig>((ref) {
  return const TargetSuggestionConfig(
    minAltitude: 30.0,
    minScore: 50.0,
    prioritizeIncomplete: true,
    sortMode: SuggestionSortMode.bestScore,
    preferredObjectTypes: [],
  );
});

// ============================================================================
// Refresh Trigger Provider
// ============================================================================

/// Simple counter provider to trigger suggestion refresh.
///
/// UI can call `ref.read(refreshSuggestionsProvider.notifier).state++` to
/// force a rebuild of the suggestions list.
final refreshSuggestionsProvider = StateProvider<int>((ref) => 0);

// ============================================================================
// Tonight's Suggestions Provider
// ============================================================================

/// Provider that generates target suggestions for tonight's imaging session.
///
/// This provider:
/// - Watches the suggestion config for filter/sort settings
/// - Watches app settings for observer latitude/longitude
/// - Watches the refresh trigger for manual refresh
/// - Fetches targets and sessions from the database
/// - Calls TargetSuggestionService to score and filter targets
///
/// Returns a list of [TargetSuggestion] objects sorted and filtered according
/// to the current configuration.
final tonightSuggestionsProvider =
    FutureProvider.autoDispose<List<TargetSuggestion>>((ref) async {
  // Watch configuration for filter/sort changes
  final config = ref.watch(targetSuggestionConfigProvider);

  // Watch refresh trigger for manual refresh
  ref.watch(refreshSuggestionsProvider);

  // Get app settings for observer location
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.valueOrNull;

  if (settings == null) {
    // Settings not loaded yet, return empty list
    return [];
  }

  final latitude = settings.latitude;
  final longitude = settings.longitude;

  // Validate location is set
  if (latitude == 0.0 && longitude == 0.0) {
    // No location configured, return empty list
    // The UI should prompt user to set location in settings
    return [];
  }

  // Get the suggestion service
  final service = ref.read(targetSuggestionServiceProvider);
  final logging = ref.read(loggingServiceProvider);

  // Get database for fetching user targets and sessions
  final database = ref.read(databaseProvider);

  try {
    // Fetch user-created targets from database
    final List<db.Target> userTargets =
        await database.targetsDao.getAllTargets();
    final List<db.ImagingSession> sessions =
        await database.sessionsDao.getAllSessions();

    // Fetch catalog objects from OpenNGC
    final catalogTargets = await _loadCatalogTargets(logging);

    // Combine user targets with catalog targets
    // User targets take precedence (they have imaging progress data)
    final seenCatalogIds = <String>{};
    for (final t in userTargets) {
      if (t.catalogId != null) {
        seenCatalogIds.add(t.catalogId!.toUpperCase());
      }
    }

    // Filter out catalog objects that already exist as user targets
    final filteredCatalog = catalogTargets.where((t) {
      if (t.catalogId == null) return true;
      return !seenCatalogIds.contains(t.catalogId!.toUpperCase());
    }).toList();

    // Combine: user targets first (have progress data), then catalog targets
    final allTargets = [...userTargets, ...filteredCatalog];

    logging.info(
      'Loaded ${userTargets.length} user targets + ${filteredCatalog.length} catalog targets = ${allTargets.length} total',
      source: 'TargetSuggestionProvider',
    );

    // Generate suggestions
    final suggestions = await service.getSuggestionsForTonight(
      config: config,
      latitude: latitude,
      longitude: longitude,
      targets: allTargets,
      sessions: sessions,
    );

    // Keep alive to prevent constant refetching while the user is viewing
    ref.keepAlive();

    return suggestions;
  } catch (e, stackTrace) {
    // Log the error but don't crash - return empty list
    logging.error(
      'Failed to generate target suggestions: $e',
      source: 'TargetSuggestionProvider',
    );
    logging.debug(
      'Stack trace: $stackTrace',
      source: 'TargetSuggestionProvider',
    );

    // Rethrow to let the UI show the error state
    rethrow;
  }
});

/// Load targets from the OpenNGC catalog.
///
/// Converts OpenNgcData objects to db.Target format for scoring.
/// Uses negative IDs to distinguish catalog objects from user targets.
Future<List<db.Target>> _loadCatalogTargets(LoggingService logging) async {
  final manager = CatalogManager.instance;

  if (!manager.isInitialized) {
    logging.warning(
      'CatalogManager not initialized - no catalog suggestions available',
      source: 'TargetSuggestionProvider',
    );
    return [];
  }

  final dsoStatus = await manager.getDsoCatalogStatus();
  if (!dsoStatus.isInstalled || dsoStatus.installedPath == null) {
    logging.info(
      'OpenNGC catalog not installed - suggestions limited to user targets',
      source: 'TargetSuggestionProvider',
    );
    return [];
  }

  try {
    final loader = OpenNgcCatalogLoader(dsoStatus.installedPath!);

    // Load all DSOs with reasonable magnitude limit for imaging
    // (mag < 14 covers most imageable objects)
    final dsos = await loader.loadByMagnitude(14.0);

    logging.debug(
      'Loaded ${dsos.length} DSOs from OpenNGC catalog (mag < 14)',
      source: 'TargetSuggestionProvider',
    );

    // Convert to Target format
    // Use negative IDs to distinguish from user-created targets
    var fakeId = -1;
    final targets = <db.Target>[];

    for (final dso in dsos) {
      // Skip non-existent and duplicate entries
      if (dso.type == 'NonEx' || dso.type == 'Dup') continue;

      // Skip objects with invalid coordinates
      if (dso.ra == 0 && dso.dec == 0) continue;

      targets.add(db.Target(
        id: fakeId--,
        name: dso.displayName,
        catalogId: dso.name,
        objectType: dso.typeDescription,
        // OpenNGC ra is in degrees, Target expects decimal hours
        ra: dso.ra / 15.0,
        dec: dso.dec,
        magnitude: dso.magnitude,
        constellation: dso.constellation,
        sizeArcmin: dso.majorAxis,
        positionAngle: dso.positionAngle,
        minAltitude: 30.0,
        priority: 5,
        totalPlannedSubs: 0,
        capturedSubs: 0,
        totalIntegrationSecs: 0.0,
        filterProgress: null,
        notes: dso.commonNames,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isFavorite: false,
      ));
    }

    return targets;
  } catch (e, stackTrace) {
    logging.error(
      'Failed to load OpenNGC catalog: $e',
      source: 'TargetSuggestionProvider',
    );
    logging.debug(
      'Stack trace: $stackTrace',
      source: 'TargetSuggestionProvider',
    );
    return [];
  }
}

// ============================================================================
// Convenience Providers
// ============================================================================

/// Provider that returns just the top N suggestions.
///
/// Useful for showing a preview or summary in the dashboard.
final topSuggestionsProvider = Provider.autoDispose
    .family<AsyncValue<List<TargetSuggestion>>, int>((ref, count) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      final topN = suggestions.take(count).toList();
      return AsyncData(topN);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

/// Provider that returns suggestions filtered by a specific object type.
final suggestionsByTypeProvider = Provider.autoDispose
    .family<AsyncValue<List<TargetSuggestion>>, String>((ref, objectType) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      // Filter suggestions that have the target name containing the object type
      // This is a simple filter - the UI can use config for more complex filtering
      final filtered = suggestions.where((s) {
        // For now, just return all - the config's preferredObjectTypes handles filtering
        return true;
      }).toList();
      return AsyncData(filtered);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

/// Provider that returns incomplete targets only (less than 50% data collected).
final incompleteSuggestionsProvider =
    Provider.autoDispose<AsyncValue<List<TargetSuggestion>>>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      final incomplete =
          suggestions.where((s) => s.dataProgress < 0.5).toList();
      return AsyncData(incomplete);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

/// Provider that returns the best single suggestion for tonight.
final bestSuggestionProvider =
    Provider.autoDispose<AsyncValue<TargetSuggestion?>>((ref) {
  final suggestionsAsync = ref.watch(tonightSuggestionsProvider);

  return suggestionsAsync.when(
    data: (suggestions) {
      if (suggestions.isEmpty) {
        return const AsyncData(null);
      }
      return AsyncData(suggestions.first);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});
