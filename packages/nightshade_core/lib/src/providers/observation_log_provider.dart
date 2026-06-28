import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/observation_logs_dao.dart';
import '../database/database.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// DAO provider for ObservationLogsDao.
final observationLogsDaoProvider = Provider<ObservationLogsDao>((ref) {
  return ObservationLogsDao(ref.watch(databaseProvider));
});

/// Reactive stream of all observation log entries (newest first).
///
/// On a remote client (`NetworkBackend`) observation logs live only in the
/// master's DB; the slave's local table is never populated. We poll the
/// host's `GET /api/notes-journal` (which serves the `observation_logs`
/// table) and map each [RemoteNotesJournalEntry] onto the local
/// [ObservationLogEntry] shape the log panel + planetarium markers read.
final observationLogsProvider = StreamProvider<List<ObservationLogEntry>>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteObservationLogs(backend);
  }
  return ref.watch(observationLogsDaoProvider).watchAllLogs();
});

/// Reactive stream of observed catalog IDs, used for planetarium markers.
final observedCatalogIdsProvider = StreamProvider<Set<String>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteObservationLogs(backend).map(
      (logs) => logs
          .map((l) => l.catalogId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet(),
    );
  }
  return ref.watch(observationLogsDaoProvider).watchObservedCatalogIds();
});

/// Observation log statistics (refreshes when logs change).
final observationLogStatsProvider = FutureProvider<ObservationLogStats>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    final logs = await ref.watch(observationLogsProvider.future);
    return _statsFromLogs(logs);
  }
  // Depend on the logs stream so stats refresh on any change
  ref.watch(observationLogsProvider);
  return ref.read(observationLogsDaoProvider).getStats();
});

/// Polls the host's observation logs, emitting only on change (mirrors the
/// `_pollRemote` change-guard in `database_provider.dart`).
Stream<List<ObservationLogEntry>> _pollRemoteObservationLogs(
  NetworkBackend backend, {
  Duration interval = const Duration(seconds: 10),
}) async* {
  var last = await _fetchRemoteObservationLogs(backend);
  yield last;
  while (true) {
    await Future<void>.delayed(interval);
    final next = await _fetchRemoteObservationLogs(backend);
    if (!listEquals(last, next)) {
      last = next;
      yield next;
    }
  }
}

Future<List<ObservationLogEntry>> _fetchRemoteObservationLogs(
  NetworkBackend backend,
) async {
  final page = await backend.fetchNotesJournal();
  final mapped = page.items.map(_observationLogFromRemote).toList()
    // Host orders newest-first already; keep that invariant so `.first`/`.last`
    // the stats reader relies on stay correct.
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return mapped;
}

ObservationLogEntry _observationLogFromRemote(RemoteNotesJournalEntry row) {
  return ObservationLogEntry(
    id: row.id,
    timestamp: row.timestamp,
    objectName: row.objectName,
    objectType: row.objectType,
    catalogId: row.catalogId,
    ra: row.ra,
    dec: row.dec,
    altitude: row.altitude,
    azimuth: row.azimuth,
    notes: row.notes,
    rating: row.rating,
    equipmentProfileId: row.equipmentProfileId,
    seeingConditions: row.seeingConditions,
    transparency: row.transparency,
    locationName: row.locationName,
    latitude: row.latitude,
    longitude: row.longitude,
  );
}

/// Reconstructs [ObservationLogStats] from a host-polled log list so the
/// remote path produces the same summary the local DAO `getStats()` would.
ObservationLogStats _statsFromLogs(List<ObservationLogEntry> logs) {
  if (logs.isEmpty) {
    return const ObservationLogStats(
      totalObservations: 0,
      uniqueObjects: 0,
      averageRating: 0,
      firstObservation: null,
      lastObservation: null,
    );
  }
  final uniqueObjects = <String>{};
  double ratingSum = 0;
  int ratedCount = 0;
  for (final log in logs) {
    uniqueObjects.add(log.catalogId ?? log.objectName);
    if (log.rating != null) {
      ratingSum += log.rating!;
      ratedCount++;
    }
  }
  // `logs` is newest-first (see _fetchRemoteObservationLogs).
  return ObservationLogStats(
    totalObservations: logs.length,
    uniqueObjects: uniqueObjects.length,
    averageRating: ratedCount > 0 ? ratingSum / ratedCount : 0,
    firstObservation: logs.last.timestamp,
    lastObservation: logs.first.timestamp,
  );
}

/// StateNotifier for managing observation log UI interactions.
final observationLogNotifierProvider =
    StateNotifierProvider<ObservationLogNotifier, ObservationLogUiState>((ref) {
      return ObservationLogNotifier(ref);
    });

/// UI state for observation log management.
class ObservationLogUiState {
  final bool isSaving;
  final String? statusMessage;
  final String? errorMessage;
  final String? filterQuery;
  final int? filterMinRating;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;

  const ObservationLogUiState({
    this.isSaving = false,
    this.statusMessage,
    this.errorMessage,
    this.filterQuery,
    this.filterMinRating,
    this.filterStartDate,
    this.filterEndDate,
  });

  ObservationLogUiState copyWith({
    bool? isSaving,
    String? statusMessage,
    String? errorMessage,
    String? filterQuery,
    int? filterMinRating,
    DateTime? filterStartDate,
    DateTime? filterEndDate,
  }) {
    return ObservationLogUiState(
      isSaving: isSaving ?? this.isSaving,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
      filterQuery: filterQuery ?? this.filterQuery,
      filterMinRating: filterMinRating ?? this.filterMinRating,
      filterStartDate: filterStartDate ?? this.filterStartDate,
      filterEndDate: filterEndDate ?? this.filterEndDate,
    );
  }
}

class ObservationLogNotifier extends StateNotifier<ObservationLogUiState> {
  final Ref ref;

  ObservationLogNotifier(this.ref) : super(const ObservationLogUiState());

  ObservationLogsDao get _dao => ref.read(observationLogsDaoProvider);

  /// Log a new observation.
  Future<int?> logObservation({
    required DateTime timestamp,
    required String objectName,
    required double ra,
    required double dec,
    String? objectType,
    String? catalogId,
    double? altitude,
    double? azimuth,
    String? notes,
    int? rating,
    int? equipmentProfileId,
    String? seeingConditions,
    String? transparency,
    String? locationName,
    double? latitude,
    double? longitude,
  }) async {
    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final id = await _dao.insertLog(
        timestamp: timestamp,
        objectName: objectName,
        ra: ra,
        dec: dec,
        objectType: objectType,
        catalogId: catalogId,
        altitude: altitude,
        azimuth: azimuth,
        notes: notes,
        rating: rating,
        equipmentProfileId: equipmentProfileId,
        seeingConditions: seeingConditions,
        transparency: transparency,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
      );
      state = state.copyWith(
        isSaving: false,
        statusMessage: 'Observation logged for $objectName',
      );
      return id;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to log observation: $e',
      );
      return null;
    }
  }

  /// Delete an observation log entry.
  Future<void> deleteLog(int id) async {
    try {
      await _dao.deleteLog(id);
      state = state.copyWith(statusMessage: 'Observation deleted.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete observation: $e');
    }
  }

  /// Export all logs to CSV.
  Future<String?> exportCsv() async {
    try {
      final csv = await _dao.exportToCsv();
      if (csv.isEmpty) {
        state = state.copyWith(statusMessage: 'No observations to export.');
        return null;
      }
      state = state.copyWith(statusMessage: 'Export complete.');
      return csv;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to export: $e');
      return null;
    }
  }

  /// Delete all observation logs.
  Future<void> deleteAllLogs() async {
    try {
      final count = await _dao.deleteAllLogs();
      state = state.copyWith(statusMessage: 'Deleted $count observations.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete observations: $e');
    }
  }

  /// Set filter query text.
  void setFilterQuery(String? query) {
    state = state.copyWith(filterQuery: query);
  }

  /// Set minimum rating filter.
  void setFilterMinRating(int? rating) {
    state = state.copyWith(filterMinRating: rating);
  }

  /// Set date range filter.
  void setFilterDateRange(DateTime? start, DateTime? end) {
    state = state.copyWith(filterStartDate: start, filterEndDate: end);
  }

  /// Clear status/error messages.
  void clearMessages() {
    state = state.copyWith(statusMessage: null, errorMessage: null);
  }
}

/// Filtered observation logs based on current UI filter state.
final filteredObservationLogsProvider =
    FutureProvider<List<ObservationLogEntry>>((ref) async {
      final uiState = ref.watch(observationLogNotifierProvider);
      final backend = ref.watch(backendProvider);

      // On a remote client the DAO reads the empty slave DB; filter the
      // host-polled list (observationLogsProvider) client-side instead so the
      // panel shows the master's logs.
      if (backend is NetworkBackend) {
        final logs = await ref.watch(observationLogsProvider.future);
        Iterable<ObservationLogEntry> result = logs;
        if (uiState.filterStartDate != null && uiState.filterEndDate != null) {
          result = result.where(
            (l) =>
                !l.timestamp.isBefore(uiState.filterStartDate!) &&
                !l.timestamp.isAfter(uiState.filterEndDate!),
          );
        } else if (uiState.filterQuery != null &&
            uiState.filterQuery!.isNotEmpty) {
          final q = uiState.filterQuery!.toLowerCase();
          result = result.where(
            (l) =>
                l.objectName.toLowerCase().contains(q) ||
                (l.catalogId?.toLowerCase().contains(q) ?? false),
          );
        } else if (uiState.filterMinRating != null) {
          result = result.where(
            (l) => (l.rating ?? 0) >= uiState.filterMinRating!,
          );
        }
        return result.toList();
      }

      final dao = ref.read(observationLogsDaoProvider);

      // If we have a date range filter, use it
      if (uiState.filterStartDate != null && uiState.filterEndDate != null) {
        return dao.getLogsByDateRange(
          start: uiState.filterStartDate!,
          end: uiState.filterEndDate!,
        );
      }

      // If we have a text query filter, use it
      if (uiState.filterQuery != null && uiState.filterQuery!.isNotEmpty) {
        return dao.getLogsByObject(uiState.filterQuery!);
      }

      // If we have a rating filter, use it
      if (uiState.filterMinRating != null) {
        return dao.getLogsByMinRating(uiState.filterMinRating!);
      }

      // Default: all logs
      return dao.getAllLogs();
    });
