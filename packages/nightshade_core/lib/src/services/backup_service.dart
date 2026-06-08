import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../database/database.dart' hide Sequence, SequenceNode;
import '../database/daos/settings_dao.dart';
import '../database/daos/equipment_profiles_dao.dart';
import '../database/daos/targets_dao.dart';
import '../providers/database_provider.dart';
import '../models/sequence/sequence_models.dart';
import '../models/imaging/imaging_models.dart';
import 'logging_service.dart';
import 'scheduler/horizon_profile.dart';
import 'sequence_repository.dart';

part 'backup_service/sequence_codec.dart';

/// Result of a backup operation
class BackupResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;
  final DateTime timestamp;
  final int itemsBackedUp;

  const BackupResult({
    required this.success,
    this.filePath,
    this.errorMessage,
    required this.timestamp,
    this.itemsBackedUp = 0,
  });
}

/// Result of a restore operation
class RestoreResult {
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;
  final int itemsRestored;
  final Map<String, int> categoryCounts;

  const RestoreResult({
    required this.success,
    this.errorMessage,
    required this.timestamp,
    this.itemsRestored = 0,
    this.categoryCounts = const {},
  });
}

/// Metadata about a backup file
class BackupMetadata {
  final String version;
  final DateTime createdAt;
  final String appVersion;
  final String platform;
  final int settingsCount;
  final int profilesCount;
  final int sequencesCount;
  final int targetsCount;

  const BackupMetadata({
    required this.version,
    required this.createdAt,
    required this.appVersion,
    required this.platform,
    this.settingsCount = 0,
    this.profilesCount = 0,
    this.sequencesCount = 0,
    this.targetsCount = 0,
  });

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>?;
    return BackupMetadata(
      version: json['version'] as String? ?? '1.0',
      createdAt: DateTime.parse(json['createdAt'] as String),
      appVersion: json['appVersion'] as String? ?? 'unknown',
      platform: json['platform'] as String? ?? 'unknown',
      settingsCount: metadata?['settingsCount'] as int? ??
          json['settingsCount'] as int? ??
          0,
      profilesCount: metadata?['profilesCount'] as int? ??
          json['profilesCount'] as int? ??
          0,
      sequencesCount: metadata?['sequencesCount'] as int? ??
          json['sequencesCount'] as int? ??
          0,
      targetsCount: metadata?['targetsCount'] as int? ??
          json['targetsCount'] as int? ??
          0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'appVersion': appVersion,
      'platform': platform,
      'settingsCount': settingsCount,
      'profilesCount': profilesCount,
      'sequencesCount': sequencesCount,
      'targetsCount': targetsCount,
    };
  }
}

/// Comprehensive backup and restore service for Nightshade data
class BackupService {
  final NightshadeDatabase database;
  final SequenceRepository sequenceRepository;
  final LoggingService _logger;

  // P2-9: bumped from '2.0' to '2.1' when we broadened backup coverage to
  // include dark_library, flat_history, defect_maps, polar_alignment_history,
  // guide_rms_history, sequence_runs, observation_logs (notes journal),
  // and the science_* tables. Restore is idempotent (insertOrIgnore) so
  // older v2.0 backups remain restorable on the new code path.
  static const String backupVersion = '2.1';
  static const String appVersion = '2.6.0'; // Must match version.yaml

  BackupService({
    required this.database,
    required this.sequenceRepository,
    required LoggingService logger,
  }) : _logger = logger;

  /// Create a full backup of all application data
  ///
  /// Backs up:
  /// - Application settings
  /// - Equipment profiles
  /// - Sequences (both regular and templates)
  /// - Targets
  ///
  /// Returns [BackupResult] with backup file path if successful
  Future<BackupResult> createBackup({String? customPath}) async {
    try {
      _logger.debug('Starting full backup...', source: 'BackupService');

      // Export all data
      final settings = await _exportSettings();
      final profiles = await _exportProfiles();
      final sequences = await _exportSequences();
      final targets = await _exportTargets();

      // P2-9 — extended coverage: each entry is the literal table name and
      // a list of rows (each row is the drift-generated `toJson()` map).
      // Restore round-trips through `_genericTableImport` which uses the
      // companion's `fromJson` + InsertMode.insertOrIgnore so existing
      // primary keys are preserved and user data is never overwritten.
      final extendedTables = await _exportExtendedTables();

      // Build backup data structure
      final backup = <String, dynamic>{
        'version': backupVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'appVersion': appVersion,
        'platform': Platform.operatingSystem,
        'metadata': {
          'settingsCount': settings.length,
          'profilesCount': profiles.length,
          'sequencesCount': sequences.length,
          'targetsCount': targets.length,
          // P2-9: per-extended-table row counts so an operator can spot
          // a partial backup (a table with unexpected 0 rows) before
          // committing to a restore.
          for (final entry in extendedTables.entries)
            '${entry.key}Count': entry.value.length,
        },
        'settings': settings,
        'equipmentProfiles': profiles,
        'sequences': sequences,
        'targets': targets,
        // Flatten the extended tables into top-level keys so a JSON
        // viewer surfaces the same structure as the original four keys.
        for (final entry in extendedTables.entries) entry.key: entry.value,
      };

      // Determine save location
      final filePath = customPath ?? await _getBackupFilePath();
      if (filePath == null) {
        return BackupResult(
          success: false,
          errorMessage: 'No backup file path specified',
          timestamp: DateTime.now(),
        );
      }

      // Write backup file
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final jsonString = const JsonEncoder.withIndent('  ').convert(backup);
      await file.writeAsString(jsonString);

      final extendedItems =
          extendedTables.values.fold<int>(0, (sum, rows) => sum + rows.length);
      final totalItems = settings.length +
          profiles.length +
          sequences.length +
          targets.length +
          extendedItems;

      _logger.info(
        'Backup completed successfully\n'
        '  File: $filePath\n'
        '  Settings: ${settings.length}\n'
        '  Profiles: ${profiles.length}\n'
        '  Sequences: ${sequences.length}\n'
        '  Targets: ${targets.length}\n'
        '  Extended tables: ${extendedTables.length} '
        '(rows: $extendedItems)\n'
        '  Total items: $totalItems',
        source: 'BackupService',
      );

      return BackupResult(
        success: true,
        filePath: filePath,
        timestamp: DateTime.now(),
        itemsBackedUp: totalItems,
      );
    } catch (e, stackTrace) {
      _logger.error('Backup failed: $e\n$stackTrace', source: 'BackupService');
      return BackupResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// Restore data from a backup file
  ///
  /// Restores all backed up data, optionally merging with existing data
  /// or replacing it completely.
  ///
  /// DATA-LOSS GUARD (P1): when [replaceExisting] is true the live database
  /// is wiped before the backup is imported. To avoid destroying the user's
  /// data behind a corrupt or truncated backup file, the ENTIRE payload is
  /// read and validated *before* any destructive operation runs. If the
  /// payload is missing its version, isn't a JSON object, has a
  /// wrong-shaped top-level section, or any typed row fails to decode, the
  /// restore aborts with the live data fully intact (`_clearAllData` is
  /// never reached). Only after validation passes do we clear + import.
  Future<RestoreResult> restoreBackup({
    required String filePath,
    bool replaceExisting = false,
  }) async {
    try {
      _logger.debug('Starting restore from: $filePath');

      // Read and parse backup file
      final file = File(filePath);
      if (!await file.exists()) {
        return RestoreResult(
          success: false,
          errorMessage: 'Backup file not found',
          timestamp: DateTime.now(),
        );
      }

      final jsonString = await file.readAsString();

      // ---------------------------------------------------------------
      // PHASE 1 — Validate & stage. Nothing below this block touches the
      // live database. Any failure returns a non-destructive error.
      // ---------------------------------------------------------------
      final _ValidatedBackup staged;
      try {
        staged = _validateBackupPayload(jsonString);
      } on _BackupValidationException catch (e) {
        _logger.error(
          'Restore aborted before touching live data: ${e.message}',
          source: 'BackupService',
        );
        return RestoreResult(
          success: false,
          errorMessage: e.message,
          timestamp: DateTime.now(),
        );
      }

      _logger.debug('Restoring backup version: ${staged.version}');

      final backup = staged.backup;

      // ---------------------------------------------------------------
      // PHASE 2 — Apply. The payload is now known to be structurally
      // sound and every typed section decodes, so the destructive clear
      // can run without risking unrecoverable data loss against garbage.
      // ---------------------------------------------------------------

      // Clear existing data if requested
      if (replaceExisting) {
        _logger.debug('Clearing existing data...');
        await _clearAllData();
      }

      // Restore data in order
      final categoryCounts = <String, int>{};

      // Restore settings — re-use the validated copy so we never re-parse.
      if (staged.settings != null) {
        final count = await _importSettings(
          staged.settings!,
          replace: replaceExisting,
        );
        categoryCounts['settings'] = count;
        _logger.debug('Restored $count settings');
      }

      // Restore equipment profiles
      if (staged.profiles != null) {
        final count = await _importProfiles(
          staged.profiles!,
          replace: replaceExisting,
        );
        categoryCounts['profiles'] = count;
        _logger.debug('Restored $count profiles');
      }

      // Restore sequences — the staged list holds fully-decoded sequences
      // so a malformed node can't slip past validation into a half-wiped DB.
      if (staged.sequences != null) {
        var count = 0;
        for (final sequence in staged.sequences!) {
          await sequenceRepository.saveSequence(sequence);
          count++;
        }
        categoryCounts['sequences'] = count;
        _logger.debug('Restored $count sequences');
      }

      // Restore targets
      if (staged.targets != null) {
        final count = await _importTargets(
          staged.targets!,
          replace: replaceExisting,
        );
        categoryCounts['targets'] = count;
        _logger.debug('Restored $count targets');
      }

      // P2-9 — restore the extended-coverage tables. Idempotent:
      // insertOrIgnore on the row's primary key. We never overwrite
      // existing rows, even when `replaceExisting` is true — the
      // `_clearAllData` step that runs before this branch wipes the
      // tables that the legacy backup pass owns, and the extended
      // tables (calibration / science / forensics / notes / runs /
      // alignments / guide history) are intentionally NOT cleared so
      // a corrupted-payload restore can never destroy field-collected
      // data.
      for (final entry in _extendedTableImporters.entries) {
        final key = entry.key;
        if (!backup.containsKey(key)) continue;
        final rows = backup[key];
        if (rows is! List) {
          _logger
              .debug('Skipping extended table "$key": payload is not a list');
          continue;
        }
        try {
          final count = await entry.value(rows);
          categoryCounts[key] = count;
          _logger.debug('Restored $count rows into "$key"');
        } catch (e, st) {
          // One bad table must not abort the whole restore — log and
          // continue with the rest so the operator still gets the
          // recoverable subset.
          _logger.error('Failed to restore extended table "$key": $e\n$st',
              source: 'BackupService');
        }
      }

      final totalItems =
          categoryCounts.values.fold<int>(0, (sum, count) => sum + count);

      _logger.info(
        'Restore completed successfully\n'
        '  Total items restored: $totalItems',
        source: 'BackupService',
      );

      return RestoreResult(
        success: true,
        timestamp: DateTime.now(),
        itemsRestored: totalItems,
        categoryCounts: categoryCounts,
      );
    } catch (e, stackTrace) {
      _logger.error('Restore failed: $e\n$stackTrace', source: 'BackupService');
      return RestoreResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// P1 DATA-LOSS GUARD — fully parse and validate a backup payload before
  /// the caller is allowed to touch the live database.
  ///
  /// Validates, in order:
  ///   * the file is valid JSON and decodes to a top-level object;
  ///   * a non-null `version` string is present;
  ///   * each present top-level section has the expected shape
  ///     (`settings` is an object; `equipmentProfiles` / `sequences` /
  ///     `targets` are lists);
  ///   * every profile / target row is an object carrying a non-empty
  ///     `name` (the only NOT NULL column the importer relies on);
  ///   * every sequence entry decodes end-to-end (root + all nodes) — a
  ///     malformed sequence aborts rather than being silently dropped
  ///     into a half-wiped database.
  ///
  /// Throws [_BackupValidationException] (caught by [restoreBackup]) on the
  /// first problem. On success returns a [_ValidatedBackup] holding both the
  /// raw map (for the never-cleared extended tables) and the eagerly-decoded
  /// typed sections so the apply phase never re-parses.
  _ValidatedBackup _validateBackupPayload(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      throw _BackupValidationException('Invalid backup file: not valid JSON ($e)');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _BackupValidationException(
          'Invalid backup file: root is not a JSON object');
    }
    final backup = decoded;

    final version = backup['version'];
    if (version is! String || version.isEmpty) {
      throw const _BackupValidationException(
          'Invalid backup file: missing version');
    }

    // Settings — must be a JSON object when present.
    Map<String, dynamic>? settings;
    if (backup.containsKey('settings')) {
      final raw = backup['settings'];
      if (raw is! Map<String, dynamic>) {
        throw const _BackupValidationException(
            'Invalid backup file: "settings" is not an object');
      }
      settings = raw;
    }

    // Equipment profiles — list of objects each carrying a non-empty name.
    List<Map<String, dynamic>>? profiles;
    if (backup.containsKey('equipmentProfiles')) {
      profiles = _validateNamedRows(
        backup['equipmentProfiles'],
        section: 'equipmentProfiles',
      );
    }

    // Targets — same contract as profiles.
    List<Map<String, dynamic>>? targets;
    if (backup.containsKey('targets')) {
      targets = _validateNamedRows(
        backup['targets'],
        section: 'targets',
      );
    }

    // Sequences — must be a list, and every entry must decode fully.
    List<Sequence>? sequences;
    if (backup.containsKey('sequences')) {
      final raw = backup['sequences'];
      if (raw is! List) {
        throw const _BackupValidationException(
            'Invalid backup file: "sequences" is not a list');
      }
      final decodedSequences = <Sequence>[];
      for (var i = 0; i < raw.length; i++) {
        final entry = raw[i];
        if (entry is! Map<String, dynamic>) {
          throw _BackupValidationException(
              'Invalid backup file: sequences[$i] is not an object');
        }
        final sequence = _jsonToSequence(entry);
        if (sequence == null) {
          throw _BackupValidationException(
              'Invalid backup file: sequences[$i] failed to decode '
              '(name: ${entry['name'] ?? '<unknown>'})');
        }
        decodedSequences.add(sequence);
      }
      sequences = decodedSequences;
    }

    return _ValidatedBackup(
      version: version,
      backup: backup,
      settings: settings,
      profiles: profiles,
      targets: targets,
      sequences: sequences,
    );
  }

  /// Shared validator for the profile/target sections: the value must be a
  /// list of JSON objects, each with a non-empty `name` (the importer inserts
  /// that as a NOT NULL column, so a missing name would otherwise blow up
  /// *after* the live DB has already been wiped).
  List<Map<String, dynamic>> _validateNamedRows(
    Object? raw, {
    required String section,
  }) {
    if (raw is! List) {
      throw _BackupValidationException(
          'Invalid backup file: "$section" is not a list');
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, dynamic>) {
        throw _BackupValidationException(
            'Invalid backup file: $section[$i] is not an object');
      }
      final name = entry['name'];
      if (name is! String || name.isEmpty) {
        throw _BackupValidationException(
            'Invalid backup file: $section[$i] is missing a non-empty "name"');
      }
      out.add(entry);
    }
    return out;
  }

  /// Read metadata from a backup file without restoring
  Future<BackupMetadata?> readBackupMetadata(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonString = await file.readAsString();
      final backup = jsonDecode(jsonString) as Map<String, dynamic>;

      return BackupMetadata.fromJson(backup);
    } catch (e) {
      _logger.debug('Failed to read backup metadata: $e');
      return null;
    }
  }

  /// List all backups in the default backup directory
  Future<List<File>> listBackups() async {
    try {
      final backupDir = await _getBackupDirectory();
      if (!await backupDir.exists()) {
        return [];
      }

      final files = await backupDir
          .list()
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.nsbackup') ||
                  entity.path.endsWith('.json')))
          .map((entity) => entity as File)
          .toList();

      // Sort by modification time (newest first)
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      return files;
    } catch (e) {
      _logger.debug('Failed to list backups: $e');
      return [];
    }
  }

  /// Auto-save a backup with timestamp
  Future<BackupResult> autoSaveBackup() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupDir = await _getBackupDirectory();
    await backupDir.create(recursive: true);

    final filePath = path.join(
      backupDir.path,
      'nightshade_autosave_$timestamp.nsbackup',
    );

    return createBackup(customPath: filePath);
  }

  // =========================================================================
  // Private export methods
  // =========================================================================

  Future<Map<String, dynamic>> _exportSettings() async {
    final settingsDao = SettingsDao(database);
    final allSettings = await settingsDao.getAllSettings();
    return allSettings;
  }

  Future<List<Map<String, dynamic>>> _exportProfiles() async {
    final profilesDao = EquipmentProfilesDao(database);
    final profiles = await profilesDao.getAllProfiles();

    return profiles.map((profile) {
      return {
        'name': profile.name,
        'description': profile.description,
        'isActive': profile.isActive,
        'cameraId': profile.cameraId,
        'mountId': profile.mountId,
        'focuserId': profile.focuserId,
        'filterWheelId': profile.filterWheelId,
        'guiderId': profile.guiderId,
        'rotatorId': profile.rotatorId,
        'domeId': profile.domeId,
        'weatherId': profile.weatherId,
        'focalLength': profile.focalLength,
        'aperture': profile.aperture,
        'focalRatio': profile.focalRatio,
        'defaultGain': profile.defaultGain,
        'defaultOffset': profile.defaultOffset,
        'defaultBinX': profile.defaultBinX,
        'defaultBinY': profile.defaultBinY,
        'defaultCoolingTemp': profile.defaultCoolingTemp,
        'filterNames': profile.filterNames,
        'filterFocusOffsets': profile.filterFocusOffsets,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _exportSequences() async {
    final sequences = await sequenceRepository.loadAllSequences();

    return sequences.map((sequence) {
      return _sequenceToJson(sequence);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _exportTargets() async {
    final targetsDao = TargetsDao(database);
    final targets = await targetsDao.getAllTargets();

    return targets.map((target) {
      return {
        'name': target.name,
        'catalogId': target.catalogId,
        'ra': target.ra,
        'dec': target.dec,
        'constellation': target.constellation,
        'objectType': target.objectType,
        'magnitude': target.magnitude,
        'sizeArcmin': target.sizeArcmin,
        'notes': target.notes,
        'isFavorite': target.isFavorite,
        'priority': target.priority,
      };
    }).toList();
  }

  // =========================================================================
  // P2-9 — Extended-coverage export/import. Each table is exported as a
  // JSON array of the drift-generated `toJson()` representation. Restore
  // uses the corresponding companion's `fromJson` + InsertMode.insertOrIgnore
  // so existing primary keys round-trip without overwriting current data.
  // =========================================================================

  /// Export every extended-coverage table to a `tableKey -> rows` map.
  /// Keys are the same strings the restore branch looks for in the backup
  /// JSON. Missing dependencies (e.g. an empty table) yield an empty list,
  /// never a missing key, so an old backup file is structurally complete.
  Future<Map<String, List<Map<String, dynamic>>>>
      _exportExtendedTables() async {
    return {
      // Calibration library
      'darkLibrary': await _dumpTable(database.darkLibrary),
      'flatHistory': await _dumpTable(database.flatHistory),
      'defectMaps': await _dumpTable(database.defectMaps),
      // Run history
      'sequenceRuns': await _dumpTable(database.sequenceRuns),
      // Notes journal (observation_logs)
      'notesJournal': await _dumpTable(database.observationLogs),
      // Polar alignment / guide history
      'polarAlignmentHistory': await _dumpTable(database.polarAlignmentHistory),
      'guideRmsHistory': await _dumpTable(database.guideRmsHistory),
      // Science tables.
      'scienceSessionConfig': await _dumpTable(database.scienceSessionConfig),
      'photometryMeasurements':
          await _dumpTable(database.photometryMeasurements),
      'framePhotometricCalibration':
          await _dumpTable(database.framePhotometricCalibration),
      'transparencySamples': await _dumpTable(database.transparencySamples),
      'psfFieldTiles': await _dumpTable(database.psfFieldTiles),
      'scienceFrameQualityMetrics':
          await _dumpTable(database.scienceFrameQualityMetrics),
      'scienceTileMetrics': await _dumpTable(database.scienceTileMetrics),
      'astrometryResidualVectors':
          await _dumpTable(database.astrometryResidualVectors),
      'movingObjectCandidates':
          await _dumpTable(database.movingObjectCandidates),
      'photometricTransforms': await _dumpTable(database.photometricTransforms),
      'lineRatioProducts': await _dumpTable(database.lineRatioProducts),
      // Focus models
      'focusModels': await _dumpTable(database.focusModels),
    };
  }

  /// Generic "select * + toJson" dump. Each drift TableInfo exposes a
  /// `map(Map<String, dynamic>)` factory that hydrates a typed
  /// DataClass from a row map. We pair `customSelect` (which gives a
  /// row as `Map<String, dynamic>` keyed by SQL column names) with that
  /// `map()` factory and then call the DataClass's `toJson()` so the
  /// import side can read the same camelCase keys back via
  /// `*.fromJson`. This is the only way to keep the export/import code
  /// table-agnostic without threading a typed generic through every
  /// call site (which trips Dart's `couldn't infer T` due to the
  /// drift-generated multi-level inheritance).
  Future<List<Map<String, dynamic>>> _dumpTable(TableInfo table) async {
    final rows = await database
        .customSelect('SELECT * FROM ${table.actualTableName}')
        .get();
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      // ignore: avoid_dynamic_calls
      final dataClass = (table as dynamic).map(row.data);
      // ignore: avoid_dynamic_calls
      out.add((dataClass as dynamic).toJson() as Map<String, dynamic>);
    }
    return out;
  }

  /// Importer signature used by [_extendedTableImporters]. Returns the
  /// number of rows that were successfully inserted (rejected duplicates
  /// don't count).
  late final Map<String, Future<int> Function(List<dynamic>)>
      _extendedTableImporters = {
    'darkLibrary': (rows) => _importRows(
          rows,
          (json) => DarkLibraryEntry.fromJson(json),
          database.darkLibrary,
        ),
    'flatHistory': (rows) => _importRows(
          rows,
          (json) => FlatHistoryEntry.fromJson(json),
          database.flatHistory,
        ),
    'defectMaps': (rows) => _importRows(
          rows,
          (json) => DefectMapEntry.fromJson(json),
          database.defectMaps,
        ),
    'sequenceRuns': (rows) => _importRows(
          rows,
          (json) => SequenceRun.fromJson(json),
          database.sequenceRuns,
        ),
    'notesJournal': (rows) => _importRows(
          rows,
          (json) => ObservationLogEntry.fromJson(json),
          database.observationLogs,
        ),
    'polarAlignmentHistory': (rows) => _importRows(
          rows,
          (json) => PolarAlignmentHistoryEntry.fromJson(json),
          database.polarAlignmentHistory,
        ),
    'guideRmsHistory': (rows) => _importRows(
          rows,
          (json) => GuideRmsHistoryEntry.fromJson(json),
          database.guideRmsHistory,
        ),
    'scienceSessionConfig': (rows) => _importRows(
          rows,
          (json) => ScienceSessionConfigRow.fromJson(json),
          database.scienceSessionConfig,
        ),
    'photometryMeasurements': (rows) => _importRows(
          rows,
          (json) => PhotometryMeasurementRow.fromJson(json),
          database.photometryMeasurements,
        ),
    'framePhotometricCalibration': (rows) => _importRows(
          rows,
          (json) => FramePhotometricCalibrationRow.fromJson(json),
          database.framePhotometricCalibration,
        ),
    'transparencySamples': (rows) => _importRows(
          rows,
          (json) => TransparencySampleRow.fromJson(json),
          database.transparencySamples,
        ),
    'psfFieldTiles': (rows) => _importRows(
          rows,
          (json) => PsfFieldTileRow.fromJson(json),
          database.psfFieldTiles,
        ),
    'scienceFrameQualityMetrics': (rows) => _importRows(
          rows,
          (json) => ScienceFrameQualityMetricsRow.fromJson(json),
          database.scienceFrameQualityMetrics,
        ),
    'scienceTileMetrics': (rows) => _importRows(
          rows,
          (json) => ScienceTileMetricRow.fromJson(json),
          database.scienceTileMetrics,
        ),
    'astrometryResidualVectors': (rows) => _importRows(
          rows,
          (json) => AstrometryResidualVectorRow.fromJson(json),
          database.astrometryResidualVectors,
        ),
    'movingObjectCandidates': (rows) => _importRows(
          rows,
          (json) => MovingObjectCandidateRow.fromJson(json),
          database.movingObjectCandidates,
        ),
    'photometricTransforms': (rows) => _importRows(
          rows,
          (json) => PhotometricTransformRow.fromJson(json),
          database.photometricTransforms,
        ),
    'lineRatioProducts': (rows) => _importRows(
          rows,
          (json) => LineRatioProductRow.fromJson(json),
          database.lineRatioProducts,
        ),
    'focusModels': (rows) => _importRows(
          rows,
          (json) => FocusModelEntry.fromJson(json),
          database.focusModels,
        ),
  };

  /// Generic per-row import. Each row's JSON is decoded into its companion
  /// via `fromJson`, then inserted with [InsertMode.insertOrIgnore] so
  /// existing primary keys are preserved. We never use `InsertMode.replace`
  /// here — restoring a backup must never destroy field-collected data the
  /// user generated after the backup was taken.
  Future<int> _importRows<T extends Insertable<dynamic>>(
    List<dynamic> rows,
    T Function(Map<String, dynamic>) decoder,
    TableInfo table,
  ) async {
    var count = 0;
    for (final raw in rows) {
      if (raw is! Map) continue;
      try {
        final row = decoder(raw.cast<String, dynamic>());
        final inserted = await database
            .into(table)
            .insert(row, mode: InsertMode.insertOrIgnore);
        // `insert` returns the row id on success (or the existing one on
        // conflict). Drift returns 0 specifically when an InsertOrIgnore
        // conflicted and nothing was written.
        if (inserted != 0) {
          count++;
        }
      } catch (e) {
        _logger.debug('Skipped malformed row during import: $e');
      }
    }
    return count;
  }

  // =========================================================================
  // Private utility methods
  // =========================================================================

  Future<String?> _getBackupFilePath() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

    final saveLocation = await file_selector.getSaveLocation(
      suggestedName: 'nightshade_backup_$timestamp.nsbackup',
      acceptedTypeGroups: [
        const file_selector.XTypeGroup(
          label: 'Nightshade Backup',
          extensions: ['nsbackup', 'json'],
        ),
      ],
    );

    return saveLocation?.path;
  }

  Future<Directory> _getBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(docsDir.path, 'Nightshade', 'backups'));
  }

  Future<Directory> getBackupDirectory() => _getBackupDirectory();

  Future<void> _clearAllData() async {
    // Clear all tables (except settings if desired)
    await database.delete(database.equipmentProfiles).go();
    await database.delete(database.sequences).go();
    await database.delete(database.sequenceNodes).go();
    await database.delete(database.targets).go();
    // Note: Not clearing imaging_sessions and captured_images to preserve historical data
    _logger.debug('Cleared existing data');
  }
}

String? _stringOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

double? _doubleOrNull(Object? value) {
  return (value as num?)?.toDouble();
}

double _doubleOrDefault(Object? value, double fallback) {
  return (value as num?)?.toDouble() ?? fallback;
}

int? _intOrNull(Object? value) {
  return (value as num?)?.toInt();
}

int _intOrDefault(Object? value, int fallback) {
  return (value as num?)?.toInt() ?? fallback;
}

BrightnessTierPreferences _parseBrightnessTierPreferences(Object? value) {
  if (value is Map) {
    return BrightnessTierPreferences.fromJson(value.cast<String, dynamic>());
  }
  return const BrightnessTierPreferences();
}

/// Persist a [TargetSchedulerNode]'s azimuth horizon mask as
/// `{id?, name, samples:[{az,alt}]}`. `null` profile encodes to `null`.
Map<String, dynamic>? _backupHorizonToJson(HorizonProfile? profile) {
  if (profile == null) return null;
  return {
    if (profile.id != null) 'id': profile.id,
    'name': profile.name,
    'samples': profile.samples.map((s) => s.toJson()).toList(),
  };
}

/// Inverse of [_backupHorizonToJson]. Tolerates a missing/empty samples list
/// (returns `null` — flat altitude floor) so legacy backups restore.
HorizonProfile? _backupHorizonFromJson(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final samplesRaw = map['samples'] as List<dynamic>? ?? const [];
  if (samplesRaw.isEmpty) return null;
  return HorizonProfile(
    id: (map['id'] as num?)?.toInt(),
    name: map['name'] as String? ?? 'Site horizon',
    samples: samplesRaw
        .map((e) => HorizonSample.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

/// Raised by [BackupService._validateBackupPayload] when a backup file is
/// structurally invalid. Caught inside [BackupService.restoreBackup] and
/// turned into a non-destructive failure result so live data is never wiped
/// for a corrupt payload.
class _BackupValidationException implements Exception {
  final String message;
  const _BackupValidationException(this.message);

  @override
  String toString() => 'BackupValidationException: $message';
}

/// Fully-validated, eagerly-decoded backup payload produced by
/// [BackupService._validateBackupPayload]. Holds the raw map (consumed by the
/// never-cleared extended-table importers) alongside the typed sections so the
/// apply phase never re-parses what validation already proved sound.
class _ValidatedBackup {
  final String version;
  final Map<String, dynamic> backup;
  final Map<String, dynamic>? settings;
  final List<Map<String, dynamic>>? profiles;
  final List<Map<String, dynamic>>? targets;
  final List<Sequence>? sequences;

  const _ValidatedBackup({
    required this.version,
    required this.backup,
    required this.settings,
    required this.profiles,
    required this.targets,
    required this.sequences,
  });
}

/// Provider for BackupService
final backupServiceProvider = Provider<BackupService>((ref) {
  final database = ref.watch(databaseProvider);
  final sequenceRepo = ref.watch(sequenceRepositoryProvider);
  final logger = ref.watch(loggingServiceProvider);

  return BackupService(
    database: database,
    sequenceRepository: sequenceRepo,
    logger: logger,
  );
});
