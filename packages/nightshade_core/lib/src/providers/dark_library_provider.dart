import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/dark_library_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/database.dart';
import '../models/calibration/dark_library_match_tolerances.dart';
import '../models/calibration/remote_calibration_models.dart';
import '../services/calibration_service.dart';
import '../services/dark_library_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// DAO provider for DarkLibraryDao.
final darkLibraryDaoProvider = Provider<DarkLibraryDao>((ref) {
  return DarkLibraryDao(ref.watch(databaseProvider));
});

/// Service provider for DarkLibraryService.
final darkLibraryServiceProvider = Provider<DarkLibraryService>((ref) {
  return DarkLibraryService(ref.watch(darkLibraryDaoProvider));
});

/// Reactive stream of all dark library entries (newest first).
///
/// On a remote client (`NetworkBackend`) the slave's local `dark_library`
/// table is never populated — the user's darks/biases live on the master —
/// so the DAO stream would render empty. We branch to a poll of the host's
/// `GET /api/calibration/darks` (`listDarks()`) and map each
/// [RemoteDarkLibraryEntry] onto the local [DarkLibraryEntry] shape the
/// settings panel + coverage stats read. The stats/groups providers below
/// already `ref.watch(darkLibraryEntriesProvider)`, so they become
/// remote-correct transitively.
final darkLibraryEntriesProvider = StreamProvider<List<DarkLibraryEntry>>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteDarkEntries(backend);
  }
  return ref.watch(darkLibraryDaoProvider).watchAllEntries();
});

/// Reactive stream of dark-only entries.
final darkFrameEntriesProvider = StreamProvider<List<DarkLibraryEntry>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteDarkEntries(
      backend,
    ).map((entries) => entries.where((e) => e.frameType == 'dark').toList());
  }
  return ref.watch(darkLibraryDaoProvider).watchEntriesByFrameType('dark');
});

/// Reactive stream of bias-only entries.
final biasFrameEntriesProvider = StreamProvider<List<DarkLibraryEntry>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteDarkEntries(
      backend,
    ).map((entries) => entries.where((e) => e.frameType == 'bias').toList());
  }
  return ref.watch(darkLibraryDaoProvider).watchEntriesByFrameType('bias');
});

/// Library statistics (refreshes when entries change).
///
/// On a remote client the local DAO `getStats()` reads the empty slave DB, so
/// derive the stats from the (remote-aware) entries stream instead.
final darkLibraryStatsProvider = FutureProvider<DarkLibraryStats>((ref) async {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    final entries = await ref.watch(darkLibraryEntriesProvider.future);
    return _statsFromEntries(entries);
  }
  // Depend on the entries stream so stats refresh on any change
  ref.watch(darkLibraryEntriesProvider);
  return ref.read(darkLibraryDaoProvider).getStats();
});

/// Distinct parameter groups in the library.
final darkLibraryGroupsProvider = FutureProvider<List<DarkGroupKey>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    final entries = await ref.watch(darkLibraryEntriesProvider.future);
    return _groupsFromEntries(entries);
  }
  ref.watch(darkLibraryEntriesProvider);
  return ref.read(darkLibraryDaoProvider).getDistinctGroups();
});

/// Polls the host's dark library and emits only on change, mirroring the
/// `_pollRemote` change-guard used by the canonical remote list providers in
/// `database_provider.dart`.
Stream<List<DarkLibraryEntry>> _pollRemoteDarkEntries(
  NetworkBackend backend, {
  Duration interval = const Duration(seconds: 10),
}) async* {
  var last = await _fetchRemoteDarkEntries(backend);
  yield last;
  while (true) {
    await Future<void>.delayed(interval);
    final next = await _fetchRemoteDarkEntries(backend);
    if (!listEquals(last, next)) {
      last = next;
      yield next;
    }
  }
}

Future<List<DarkLibraryEntry>> _fetchRemoteDarkEntries(
  NetworkBackend backend,
) async {
  // listDarks() with no filter returns both darks and biases (frameType
  // carried on each row). Order newest-first to match `watchAllEntries()`.
  final rows = await backend.listDarks();
  final mapped = rows.map(_darkEntryFromRemote).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return mapped;
}

DarkLibraryEntry _darkEntryFromRemote(RemoteDarkLibraryEntry row) {
  return DarkLibraryEntry(
    id: row.id,
    filePath: row.filePath,
    exposureTime: row.exposureDuration,
    temperature: row.sensorTempC,
    gain: row.gain,
    offset: row.offset,
    binX: row.binX,
    binY: row.binY,
    frameType: row.frameType,
    width: row.width,
    height: row.height,
    masterDarkPath: row.masterPath,
    masterFrameCount: row.frameCount,
    createdAt: row.createdAt,
  );
}

/// Reconstructs [DarkLibraryStats] from a flat entry list so the remote
/// (host-polled) path produces the same counts the local DAO would.
DarkLibraryStats _statsFromEntries(List<DarkLibraryEntry> entries) {
  var darkCount = 0;
  var biasCount = 0;
  var masterCount = 0;
  for (final e in entries) {
    if (e.frameType == 'bias') {
      biasCount++;
    } else {
      darkCount++;
    }
    if (e.masterDarkPath != null) masterCount++;
  }
  return DarkLibraryStats(
    totalEntries: entries.length,
    darkCount: darkCount,
    biasCount: biasCount,
    masterCount: masterCount,
  );
}

/// Reconstructs the distinct parameter groups from a flat entry list.
List<DarkGroupKey> _groupsFromEntries(List<DarkLibraryEntry> entries) {
  final seen = <String, DarkGroupKey>{};
  for (final e in entries) {
    final key = DarkGroupKey(
      exposureTime: e.exposureTime,
      gain: e.gain,
      binX: e.binX,
      binY: e.binY,
      frameType: e.frameType,
    );
    seen['${e.exposureTime}|${e.gain}|${e.binX}|${e.binY}|${e.frameType}'] = key;
  }
  return seen.values.toList();
}

/// Whether auto-dark-subtraction is enabled.
///
/// Why: dark-library settings used to live under `dark_library.auto_subtract`
/// but the calibration pipeline (`imaging_service.dart`) only consults
/// `calibrationSettingsProvider.autoCalibrate`. Pointing this provider at
/// the calibration store keeps the dark-library UI in sync with what the
/// pipeline actually evaluates so the toggle is no longer dead-write
/// The legacy
/// `dark_library.auto_subtract` key is preserved as a one-time migration
/// source via [migrateLegacyDarkLibrarySettings].
final autoDarkSubtractEnabledProvider = Provider<bool>((ref) {
  // Watch calibration settings so dark-library UI updates reactively.
  return ref.watch(calibrationSettingsProvider.select((s) => s.autoCalibrate));
});

/// Settings key for the dark-library exposure-match tolerance (seconds).
///
/// Default written into `app_settings` is `0.5`. See [DarkLibraryMatchTolerances]
/// for the rationale.
const String darkLibraryExposureToleranceKey =
    'dark_library.exposure_tolerance';

/// Settings key for the dark-library temperature-match tolerance (°C).
const String darkLibraryTempToleranceKey = 'dark_library.temp_tolerance';

/// Unified tolerances for dark-frame matching.
///
/// This is the SINGLE source of truth that both the coverage UI
/// (`DarkLibraryCoverageService.evaluate`) and the runtime calibration
/// matcher (`DarkLibraryDao.findBestMatch` via `DarkLibraryService`) must
/// consult so the green "all darks present" badge can never contradict
/// `findMatchingDark` returning null.
///
/// Values are read from `app_settings`:
///   * `dark_library.exposure_tolerance` (default 0.5s)
///   * `dark_library.temp_tolerance`     (default 1.0°C — the historical
///     migration default of 2.0 is honored if already present)
///
/// Invalid stored values (negative, NaN, inf, unparseable) cause the
/// provider to throw via [DarkLibraryMatchTolerances.validated] so the
/// problem surfaces immediately instead of being silently clamped — per
/// Errors are a feature here.
final darkLibraryMatchTolerancesProvider = Provider<DarkLibraryMatchTolerances>(
  (ref) {
    final settings = ref.watch(allSettingsProvider);
    return settings.when(
      data: (s) {
        final exposureRaw = s[darkLibraryExposureToleranceKey];
        final tempRaw = s[darkLibraryTempToleranceKey];
        // Defaults: 0.5s exposure, 1.0°C temperature. If the legacy
        // dark_library.temp_tolerance default of 2.0 is present it is
        // honored as-is (it is a user-tunable value, not a migration).
        final exposureSecs = exposureRaw == null
            ? DarkLibraryMatchTolerances.defaults.exposureSecs
            : (double.tryParse(exposureRaw) ??
                  (throw ArgumentError.value(
                    exposureRaw,
                    darkLibraryExposureToleranceKey,
                    'Setting "$darkLibraryExposureToleranceKey" is not a valid '
                    'number of seconds',
                  )));
        final temperatureC = tempRaw == null
            ? DarkLibraryMatchTolerances.defaults.temperatureC
            : (double.tryParse(tempRaw) ??
                  (throw ArgumentError.value(
                    tempRaw,
                    darkLibraryTempToleranceKey,
                    'Setting "$darkLibraryTempToleranceKey" is not a valid '
                    'number of degrees',
                  )));
        return DarkLibraryMatchTolerances.validated(
          exposureSecs: exposureSecs,
          temperatureC: temperatureC,
        );
      },
      loading: () => DarkLibraryMatchTolerances.defaults,
      error: (_, __) => DarkLibraryMatchTolerances.defaults,
    );
  },
);

/// Legacy convenience accessor for the temperature tolerance value alone.
///
/// Retained so the existing Settings UI (`dark_library_settings.dart`)
/// continues to compile without modification. New code should consume
/// [darkLibraryMatchTolerancesProvider] directly.
final darkTempToleranceProvider = Provider<double>((ref) {
  return ref.watch(darkLibraryMatchTolerancesProvider).temperatureC;
});

/// Migrate the legacy `dark_library.auto_subtract` setting into
/// `calibrationSettingsProvider` on first launch after the unification.
///
/// Why: existing users who toggled the dark-library UI before the v2.5
/// reconciliation had their preference written to a key the calibration
/// pipeline never read. This helper is invoked from the calibration
/// notifier's load path so the user's intent is preserved across the
/// upgrade. The legacy key is cleared after migration so we don't keep
/// reading the stale value.
Future<bool?> readLegacyAutoSubtractFlag(SettingsDao dao) async {
  final value = await dao.getSetting('dark_library.auto_subtract');
  if (value == null) return null;
  return value == 'true';
}

/// StateNotifier for managing the dark library UI state.
final darkLibraryNotifierProvider =
    StateNotifierProvider<DarkLibraryNotifier, DarkLibraryUiState>((ref) {
      return DarkLibraryNotifier(ref);
    });

/// UI state for the dark library management screen.
class DarkLibraryUiState {
  final bool isCreatingMaster;
  final String? statusMessage;
  final String? errorMessage;
  final int? selectedGroupIndex;

  const DarkLibraryUiState({
    this.isCreatingMaster = false,
    this.statusMessage,
    this.errorMessage,
    this.selectedGroupIndex,
  });

  DarkLibraryUiState copyWith({
    bool? isCreatingMaster,
    String? statusMessage,
    String? errorMessage,
    int? selectedGroupIndex,
  }) {
    return DarkLibraryUiState(
      isCreatingMaster: isCreatingMaster ?? this.isCreatingMaster,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
      selectedGroupIndex: selectedGroupIndex ?? this.selectedGroupIndex,
    );
  }
}

class DarkLibraryNotifier extends StateNotifier<DarkLibraryUiState> {
  final Ref ref;

  DarkLibraryNotifier(this.ref) : super(const DarkLibraryUiState());

  DarkLibraryService get _service => ref.read(darkLibraryServiceProvider);

  /// Create a master dark from all raw frames matching the given parameters.
  Future<void> createMasterDark({
    required double exposureTime,
    required int gain,
    required int binX,
    required int binY,
    required String outputPath,
    String frameType = 'dark',
  }) async {
    state = state.copyWith(
      isCreatingMaster: true,
      statusMessage: 'Finding matching frames...',
      errorMessage: null,
    );

    try {
      final frames = await _service.getMatchingFrames(
        exposureTime: exposureTime,
        gain: gain,
        binX: binX,
        binY: binY,
        frameType: frameType,
      );

      if (frames.length < 2) {
        state = state.copyWith(
          isCreatingMaster: false,
          errorMessage:
              'Need at least 2 matching frames to create a master dark. '
              'Found ${frames.length}.',
        );
        return;
      }

      state = state.copyWith(
        statusMessage: 'Median-combining ${frames.length} frames...',
      );

      await _service.createMasterDark(frames: frames, outputPath: outputPath);

      state = state.copyWith(
        isCreatingMaster: false,
        statusMessage: 'Master dark created from ${frames.length} frames.',
      );
    } catch (e) {
      state = state.copyWith(
        isCreatingMaster: false,
        errorMessage: 'Failed to create master dark: $e',
      );
    }
  }

  /// Clean up orphaned entries where files have been deleted from disk.
  Future<void> cleanOrphans() async {
    state = state.copyWith(
      statusMessage: 'Scanning for orphaned entries...',
      errorMessage: null,
    );

    try {
      final removed = await _service.cleanOrphanedEntries();
      state = state.copyWith(
        statusMessage: removed > 0
            ? 'Removed $removed orphaned entries.'
            : 'No orphaned entries found.',
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to clean orphans: $e');
    }
  }

  /// Delete a single entry.
  Future<void> deleteEntry(int id, {bool deleteFile = false}) async {
    try {
      await _service.deleteEntry(id, deleteFile: deleteFile);
      state = state.copyWith(statusMessage: 'Entry deleted.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete entry: $e');
    }
  }

  /// Clear the entire library.
  Future<void> clearLibrary({bool deleteFiles = false}) async {
    state = state.copyWith(
      statusMessage: 'Clearing library...',
      errorMessage: null,
    );

    try {
      await _service.clearLibrary(deleteFiles: deleteFiles);
      state = state.copyWith(statusMessage: 'Library cleared.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to clear library: $e');
    }
  }

  void selectGroup(int? index) {
    state = state.copyWith(selectedGroupIndex: index);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearStatus() {
    state = state.copyWith(statusMessage: null);
  }
}
