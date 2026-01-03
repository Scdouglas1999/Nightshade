import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
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
import 'sequence_repository.dart';

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
    return BackupMetadata(
      version: json['version'] as String? ?? '1.0',
      createdAt: DateTime.parse(json['createdAt'] as String),
      appVersion: json['appVersion'] as String? ?? 'unknown',
      platform: json['platform'] as String? ?? 'unknown',
      settingsCount: json['settingsCount'] as int? ?? 0,
      profilesCount: json['profilesCount'] as int? ?? 0,
      sequencesCount: json['sequencesCount'] as int? ?? 0,
      targetsCount: json['targetsCount'] as int? ?? 0,
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

  static const String backupVersion = '2.0';
  static const String appVersion = '2.0.0'; // Should be from package info

  BackupService({
    required this.database,
    required this.sequenceRepository,
  });

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
      debugPrint('BackupService: Starting full backup...');

      // Export all data
      final settings = await _exportSettings();
      final profiles = await _exportProfiles();
      final sequences = await _exportSequences();
      final targets = await _exportTargets();

      // Build backup data structure
      final backup = {
        'version': backupVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'appVersion': appVersion,
        'platform': Platform.operatingSystem,
        'metadata': {
          'settingsCount': settings.length,
          'profilesCount': profiles.length,
          'sequencesCount': sequences.length,
          'targetsCount': targets.length,
        },
        'settings': settings,
        'equipmentProfiles': profiles,
        'sequences': sequences,
        'targets': targets,
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

      final totalItems = settings.length + profiles.length +
                        sequences.length + targets.length;

      debugPrint(
        'BackupService: Backup completed successfully\n'
        '  File: $filePath\n'
        '  Settings: ${settings.length}\n'
        '  Profiles: ${profiles.length}\n'
        '  Sequences: ${sequences.length}\n'
        '  Targets: ${targets.length}\n'
        '  Total items: $totalItems',
      );

      return BackupResult(
        success: true,
        filePath: filePath,
        timestamp: DateTime.now(),
        itemsBackedUp: totalItems,
      );
    } catch (e, stackTrace) {
      debugPrint('BackupService: Backup failed: $e\n$stackTrace');
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
  /// or replacing it completely
  Future<RestoreResult> restoreBackup({
    required String filePath,
    bool replaceExisting = false,
  }) async {
    try {
      debugPrint('BackupService: Starting restore from: $filePath');

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
      final backup = jsonDecode(jsonString) as Map<String, dynamic>;

      // Verify backup version compatibility
      final version = backup['version'] as String?;
      if (version == null) {
        return RestoreResult(
          success: false,
          errorMessage: 'Invalid backup file: missing version',
          timestamp: DateTime.now(),
        );
      }

      debugPrint('BackupService: Restoring backup version: $version');

      // Clear existing data if requested
      if (replaceExisting) {
        debugPrint('BackupService: Clearing existing data...');
        await _clearAllData();
      }

      // Restore data in order
      final categoryCounts = <String, int>{};

      // Restore settings
      if (backup.containsKey('settings')) {
        final count = await _importSettings(
          backup['settings'] as Map<String, dynamic>,
          replace: replaceExisting,
        );
        categoryCounts['settings'] = count;
        debugPrint('BackupService: Restored $count settings');
      }

      // Restore equipment profiles
      if (backup.containsKey('equipmentProfiles')) {
        final count = await _importProfiles(
          backup['equipmentProfiles'] as List<dynamic>,
          replace: replaceExisting,
        );
        categoryCounts['profiles'] = count;
        debugPrint('BackupService: Restored $count profiles');
      }

      // Restore sequences
      if (backup.containsKey('sequences')) {
        final count = await _importSequences(
          backup['sequences'] as List<dynamic>,
          replace: replaceExisting,
        );
        categoryCounts['sequences'] = count;
        debugPrint('BackupService: Restored $count sequences');
      }

      // Restore targets
      if (backup.containsKey('targets')) {
        final count = await _importTargets(
          backup['targets'] as List<dynamic>,
          replace: replaceExisting,
        );
        categoryCounts['targets'] = count;
        debugPrint('BackupService: Restored $count targets');
      }

      final totalItems = categoryCounts.values.fold<int>(0, (sum, count) => sum + count);

      debugPrint(
        'BackupService: Restore completed successfully\n'
        '  Total items restored: $totalItems',
      );

      return RestoreResult(
        success: true,
        timestamp: DateTime.now(),
        itemsRestored: totalItems,
        categoryCounts: categoryCounts,
      );
    } catch (e, stackTrace) {
      debugPrint('BackupService: Restore failed: $e\n$stackTrace');
      return RestoreResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
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
      debugPrint('BackupService: Failed to read backup metadata: $e');
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
              entity.path.endsWith('.nsbackup') ||
              entity.path.endsWith('.json'))
          .map((entity) => entity as File)
          .toList();

      // Sort by modification time (newest first)
      files.sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));

      return files;
    } catch (e) {
      debugPrint('BackupService: Failed to list backups: $e');
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

  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
      'name': sequence.name,
      'description': sequence.description,
      'rootNodeId': sequence.rootNodeId,
      'isTemplate': sequence.isTemplate,
      'nodes': sequence.nodes.map((id, node) => MapEntry(id, _nodeToJson(node))),
      'createdAt': sequence.createdAt.toIso8601String(),
      'modifiedAt': sequence.modifiedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _nodeToJson(SequenceNode node) {
    // Use the same serialization as SequenceFileService
    final base = {
      'id': node.id,
      'nodeType': node.nodeType,
      'name': node.name,
      'parentId': node.parentId,
      'childIds': node.childIds,
      'orderIndex': node.orderIndex,
      'isEnabled': node.isEnabled,
    };

    if (node is ExposureNode) {
      base.addAll({
        'durationSecs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'gain': node.gain,
        'offset': node.offset,
        'binning': node.binning.name,
        'ditherEvery': node.ditherEvery,
        'frameType': node.frameType.name,
      });
    } else if (node is TargetGroupNode) {
      base.addAll({
        'targetName': node.targetName,
        'raHours': node.raHours,
        'decDegrees': node.decDegrees,
        'rotation': node.rotation,
        'minAltitude': node.minAltitude,
        'maxAltitude': node.maxAltitude,
        'priority': node.priority,
      });
    } else if (node is InstructionSetNode) {
      // No additional fields
    } else if (node is LoopNode) {
      base.addAll({
        'conditionType': node.conditionType.name,
        'repeatCount': node.repeatCount,
        'repeatUntil': node.repeatUntil?.toIso8601String(),
        'repeatUntilAltitude': node.repeatUntilAltitude,
      });
    }

    return base;
  }

  // =========================================================================
  // Private import methods
  // =========================================================================

  Future<int> _importSettings(
    Map<String, dynamic> settingsMap,
    {bool replace = false}
  ) async {
    final settingsDao = SettingsDao(database);
    int count = 0;

    for (final entry in settingsMap.entries) {
      await settingsDao.setSetting(entry.key, entry.value as String);
      count++;
    }

    return count;
  }

  Future<int> _importProfiles(
    List<dynamic> profilesList,
    {bool replace = false}
  ) async {
    int count = 0;

    for (final profileJson in profilesList) {
      final profile = profileJson as Map<String, dynamic>;

      await database.into(database.equipmentProfiles).insert(
        EquipmentProfilesCompanion.insert(
          name: profile['name'] as String,
          description: Value(profile['description'] as String?),
          isActive: Value(profile['isActive'] as bool? ?? false),
          cameraId: Value(profile['cameraId'] as String?),
          mountId: Value(profile['mountId'] as String?),
          focuserId: Value(profile['focuserId'] as String?),
          filterWheelId: Value(profile['filterWheelId'] as String?),
          guiderId: Value(profile['guiderId'] as String?),
          rotatorId: Value(profile['rotatorId'] as String?),
          domeId: Value(profile['domeId'] as String?),
          weatherId: Value(profile['weatherId'] as String?),
          focalLength: Value(profile['focalLength'] as double? ?? 0.0),
          aperture: Value(profile['aperture'] as double? ?? 0.0),
          focalRatio: Value(profile['focalRatio'] as double?),
          defaultGain: Value(profile['defaultGain'] as int?),
          defaultOffset: Value(profile['defaultOffset'] as int?),
          defaultBinX: Value(profile['defaultBinX'] as int? ?? 1),
          defaultBinY: Value(profile['defaultBinY'] as int? ?? 1),
          defaultCoolingTemp: Value(profile['defaultCoolingTemp'] as double?),
          filterNames: Value(profile['filterNames'] as String?),
          filterFocusOffsets: Value(profile['filterFocusOffsets'] as String?),
        ),
        mode: replace ? InsertMode.replace : InsertMode.insertOrIgnore,
      );
      count++;
    }

    return count;
  }

  Future<int> _importSequences(
    List<dynamic> sequencesList,
    {bool replace = false}
  ) async {
    int count = 0;

    for (final sequenceJson in sequencesList) {
      final sequence = _jsonToSequence(sequenceJson as Map<String, dynamic>);
      if (sequence != null) {
        await sequenceRepository.saveSequence(sequence);
        count++;
      }
    }

    return count;
  }

  Future<int> _importTargets(
    List<dynamic> targetsList,
    {bool replace = false}
  ) async {
    int count = 0;

    for (final targetJson in targetsList) {
      final target = targetJson as Map<String, dynamic>;

      await database.into(database.targets).insert(
        TargetsCompanion.insert(
          name: target['name'] as String,
          catalogId: Value(target['catalogId'] as String?),
          ra: target['ra'] as double,
          dec: target['dec'] as double,
          constellation: Value(target['constellation'] as String?),
          objectType: Value(target['objectType'] as String?),
          magnitude: Value(target['magnitude'] as double?),
          sizeArcmin: Value(target['sizeArcmin'] as double?),
          notes: Value(target['notes'] as String?),
          isFavorite: Value(target['isFavorite'] as bool? ?? false),
          priority: Value(target['priority'] as int? ?? 0),
        ),
        mode: replace ? InsertMode.replace : InsertMode.insertOrIgnore,
      );
      count++;
    }

    return count;
  }

  Sequence? _jsonToSequence(Map<String, dynamic> json) {
    try {
      final nodes = <String, SequenceNode>{};
      final nodesJson = json['nodes'] as Map<String, dynamic>;

      for (final entry in nodesJson.entries) {
        final node = _jsonToNode(entry.value as Map<String, dynamic>);
        if (node != null) {
          nodes[entry.key] = node;
        }
      }

      return Sequence(
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        nodes: nodes,
        rootNodeId: json['rootNodeId'] as String,
        isTemplate: json['isTemplate'] as bool? ?? false,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'] as String)
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint('BackupService: Failed to parse sequence: $e');
      return null;
    }
  }

  SequenceNode? _jsonToNode(Map<String, dynamic> json) {
    try {
      final nodeType = json['nodeType'] as String;

      switch (nodeType) {
        case 'exposure':
          return ExposureNode(
            id: json['id'] as String,
            name: json['name'] as String,
            durationSecs: (json['durationSecs'] as num).toDouble(),
            count: json['count'] as int,
            filter: json['filter'] as String?,
            gain: json['gain'] as int?,
            offset: json['offset'] as int?,
            binning: BinningMode.values.firstWhere(
              (e) => e.name == json['binning'],
              orElse: () => BinningMode.one,
            ),
            frameType: json['frameType'] != null
                ? FrameType.values.firstWhere(
                    (e) => e.name == json['frameType'],
                    orElse: () => FrameType.light,
                  )
                : FrameType.light,
            ditherEvery: json['ditherEvery'] as int?,
            parentId: json['parentId'] as String?,
            childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: json['orderIndex'] as int,
            isEnabled: json['isEnabled'] as bool? ?? true,
          );

        case 'targetGroup':
          return TargetGroupNode(
            id: json['id'] as String,
            name: json['name'] as String,
            targetName: json['targetName'] as String,
            raHours: (json['raHours'] as num).toDouble(),
            decDegrees: (json['decDegrees'] as num).toDouble(),
            parentId: json['parentId'] as String?,
            childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: json['orderIndex'] as int,
            isEnabled: json['isEnabled'] as bool? ?? true,
          );

        case 'instructionSet':
          return InstructionSetNode(
            id: json['id'] as String,
            name: json['name'] as String,
            parentId: json['parentId'] as String?,
            childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: json['orderIndex'] as int,
            isEnabled: json['isEnabled'] as bool? ?? true,
          );

        case 'loop':
          return LoopNode(
            id: json['id'] as String,
            name: json['name'] as String,
            conditionType: LoopConditionType.values.firstWhere(
              (e) => e.name == json['conditionType'],
              orElse: () => LoopConditionType.count,
            ),
            repeatCount: json['repeatCount'] as int?,
            repeatUntil: json['repeatUntil'] != null
                ? DateTime.parse(json['repeatUntil'] as String)
                : null,
            repeatUntilAltitude: (json['repeatUntilAltitude'] as num?)?.toDouble(),
            parentId: json['parentId'] as String?,
            childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: json['orderIndex'] as int,
            isEnabled: json['isEnabled'] as bool? ?? true,
          );

        default:
          debugPrint('BackupService: Unknown node type: $nodeType');
          return null;
      }
    } catch (e) {
      debugPrint('BackupService: Failed to parse node: $e');
      return null;
    }
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

  Future<void> _clearAllData() async {
    // Clear all tables (except settings if desired)
    await database.delete(database.equipmentProfiles).go();
    await database.delete(database.sequences).go();
    await database.delete(database.sequenceNodes).go();
    await database.delete(database.targets).go();
    // Note: Not clearing imaging_sessions and captured_images to preserve historical data
    debugPrint('BackupService: Cleared existing data');
  }
}

/// Provider for BackupService
final backupServiceProvider = Provider<BackupService>((ref) {
  final database = ref.watch(databaseProvider);
  final sequenceRepo = ref.watch(sequenceRepositoryProvider);

  return BackupService(
    database: database,
    sequenceRepository: sequenceRepo,
  );
});
