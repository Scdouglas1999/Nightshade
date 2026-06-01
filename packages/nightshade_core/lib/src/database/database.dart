import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/settings/app_settings.dart' show kDefaultAccentColorHex;
import 'integrity_check.dart' as integrity;
import 'integrity_check.dart' show DatabaseRecoveryMarker;
import 'tables/equipment_profiles.dart';
import 'tables/imaging_sessions.dart';
import 'tables/targets.dart';
import 'tables/sequences.dart';
import 'tables/captured_images.dart';
import 'tables/settings.dart';
import 'tables/weather_settings.dart';
import 'tables/flat_history.dart';
import 'tables/tutorial_progress.dart';
import 'tables/polar_alignment_history.dart';
import 'tables/science.dart';
import 'tables/dark_library.dart';
import 'tables/observation_logs.dart';
import 'tables/observing_lists.dart';
import 'tables/sequence_runs.dart';
import 'tables/defect_map_table.dart';
import 'tables/focus_models.dart';
import 'tables/guide_rms_history.dart';
import 'daos/images_dao.dart';
import 'daos/equipment_profiles_dao.dart';
import 'daos/sessions_dao.dart';
import 'daos/sequences_dao.dart';
import 'daos/sequence_checkpoints_dao.dart';
import 'daos/targets_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/weather_settings_dao.dart';
import 'daos/flat_history_dao.dart';
import 'daos/tutorial_progress_dao.dart';
import 'daos/polar_alignment_history_dao.dart';
import 'daos/science_dao.dart';
import 'daos/dark_library_dao.dart';
import 'daos/observation_logs_dao.dart';
import 'daos/observing_lists_dao.dart';
import 'daos/sequence_runs_dao.dart';
import 'daos/guide_rms_history_dao.dart';

part 'database.g.dart';
part 'database/migration_strategy.dart';
part 'database/migration_v2_to_v17.dart';
part 'database/migration_v18_to_v22.dart';
part 'database/migration_v23_to_v31.dart';
part 'database/migration_v32_to_v40.dart';
part 'database/schema_helpers.dart';
part 'database/default_settings.dart';
part 'database/connection.dart';

/// The main database class for Nightshade
@DriftDatabase(
  tables: [
    EquipmentProfiles,
    ImagingSessions,
    Targets,
    Sequences,
    SequenceNodes,
    SequenceCheckpoints,
    CapturedImages,
    ImageMetadata,
    AppSettings,
    WeatherSettings,
    FlatHistory,
    TutorialProgress,
    PolarAlignmentHistory,
    ScienceSessionConfig,
    PhotometryMeasurements,
    FramePhotometricCalibration,
    TransparencySamples,
    PsfFieldTiles,
    ScienceFrameQualityMetrics,
    ScienceTileMetrics,
    AstrometryResidualVectors,
    MovingObjectCandidates,
    LineRatioProducts,
    PhotometricTransforms,
    DarkLibrary,
    ObservationLogs,
    ObservingLists,
    ObservingListItems,
    SequenceRuns,
    DefectMaps,
    FocusModels,
    GuideRmsHistory,
  ],
  daos: [
    ImagesDao,
    EquipmentProfilesDao,
    SessionsDao,
    SequencesDao,
    SequenceCheckpointsDao,
    TargetsDao,
    SettingsDao,
    WeatherSettingsDao,
    FlatHistoryDao,
    TutorialProgressDao,
    PolarAlignmentHistoryDao,
    ScienceDao,
    DarkLibraryDao,
    ObservationLogsDao,
    ObservingListsDao,
    SequenceRunsDao,
    GuideRmsHistoryDao,
  ],
)
class NightshadeDatabase extends _$NightshadeDatabase {
  NightshadeDatabase() : super(_openConnection());

  /// For testing with a custom QueryExecutor
  NightshadeDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 40;

  @override
  MigrationStrategy get migration => _buildMigrationStrategy();

  /// One-shot UI hook: returns a [DatabaseRecoveryMarker] iff the previous
  /// app launch rotated a corrupt database into a forensic backup, then
  /// clears every recovery marker in the database directory so the same
  /// dialog is not shown again.
  ///
  /// Why a static helper rather than an instance method: the UI layer needs
  /// to call this at startup, BEFORE constructing the database (otherwise
  /// the freshly-recreated DB has already been "consumed" by the migrator
  /// and the marker has lost its UX meaning of "this is the first launch
  /// AFTER recovery"). Static avoids a chicken-and-egg dependency on a
  /// live [NightshadeDatabase].
  static Future<DatabaseRecoveryMarker?> consumeRecoveryMarker() async {
    final dbFile = await resolveDefaultDatabaseFile();
    return integrity.consumeRecoveryMarker(dbFile.parent);
  }
}
