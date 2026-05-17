import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/dark_library_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/database.dart';
import '../services/calibration_service.dart';
import '../services/dark_library_service.dart';
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
final darkLibraryEntriesProvider =
    StreamProvider<List<DarkLibraryEntry>>((ref) {
  return ref.watch(darkLibraryDaoProvider).watchAllEntries();
});

/// Reactive stream of dark-only entries.
final darkFrameEntriesProvider =
    StreamProvider<List<DarkLibraryEntry>>((ref) {
  return ref.watch(darkLibraryDaoProvider).watchEntriesByFrameType('dark');
});

/// Reactive stream of bias-only entries.
final biasFrameEntriesProvider =
    StreamProvider<List<DarkLibraryEntry>>((ref) {
  return ref.watch(darkLibraryDaoProvider).watchEntriesByFrameType('bias');
});

/// Library statistics (refreshes when entries change).
final darkLibraryStatsProvider =
    FutureProvider<DarkLibraryStats>((ref) async {
  // Depend on the entries stream so stats refresh on any change
  ref.watch(darkLibraryEntriesProvider);
  return ref.read(darkLibraryDaoProvider).getStats();
});

/// Distinct parameter groups in the library.
final darkLibraryGroupsProvider =
    FutureProvider<List<DarkGroupKey>>((ref) async {
  ref.watch(darkLibraryEntriesProvider);
  return ref.read(darkLibraryDaoProvider).getDistinctGroups();
});

/// Whether auto-dark-subtraction is enabled.
///
/// Why: dark-library settings used to live under `dark_library.auto_subtract`
/// but the calibration pipeline (`imaging_service.dart`) only consults
/// `calibrationSettingsProvider.autoCalibrate`. Pointing this provider at
/// the calibration store keeps the dark-library UI in sync with what the
/// pipeline actually evaluates so the toggle is no longer dead-write
/// (audit-handoff §2.1 WIRE-UP item #6). The legacy
/// `dark_library.auto_subtract` key is preserved as a one-time migration
/// source via [migrateLegacyDarkLibrarySettings].
final autoDarkSubtractEnabledProvider = Provider<bool>((ref) {
  // Watch calibration settings so dark-library UI updates reactively.
  return ref.watch(
    calibrationSettingsProvider.select((s) => s.autoCalibrate),
  );
});

/// Temperature tolerance for dark matching (degrees C).
///
/// Why: kept in `dark_library.temp_tolerance` since `CalibrationSettings`
/// does not currently model the tolerance (it is consumed inside
/// `DarkLibraryService.findMatchingDark` via the per-frame temperature
/// argument). The tolerance is independent of whether calibration is
/// enabled overall.
final darkTempToleranceProvider = Provider<double>((ref) {
  final settings = ref.watch(allSettingsProvider);
  return settings.when(
    data: (s) {
      final val = s['dark_library.temp_tolerance'];
      if (val == null) return 2.0;
      return double.tryParse(val) ?? 2.0;
    },
    loading: () => 2.0,
    error: (_, __) => 2.0,
  );
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
        statusMessage:
            'Median-combining ${frames.length} frames...',
      );

      await _service.createMasterDark(
        frames: frames,
        outputPath: outputPath,
      );

      state = state.copyWith(
        isCreatingMaster: false,
        statusMessage:
            'Master dark created from ${frames.length} frames.',
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
      state = state.copyWith(
        errorMessage: 'Failed to clean orphans: $e',
      );
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
