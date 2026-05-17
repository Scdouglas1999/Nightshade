import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/imaging/imaging_models.dart' show FrameType;
import '../models/sequence/sequence_models.dart';
import '../providers/profiles_provider.dart';
import '../providers/settings_provider.dart';

/// Service for saving and loading sequences to/from JSON files
typedef SequenceImportValidator = void Function(Sequence sequence);

class SequenceFileService {
  final SequenceImportValidator? _importValidator;

  /// Default directory for export/import file pickers.
  ///
  /// Why: Settings → File Paths → Sequences exposes a "Sequences" folder so
  /// users can keep sequence JSON exports alongside the rest of their
  /// observatory documentation. Routing the file_selector dialogs at this
  /// directory makes the setting actually consequential
  /// (audit-handoff §2.1 WIRE-UP item #8). Empty string means "let the
  /// platform pick the default location".
  final String _defaultDirectory;

  SequenceFileService({
    SequenceImportValidator? importValidator,
    String defaultDirectory = '',
  })  : _importValidator = importValidator,
        _defaultDirectory = defaultDirectory;

  String? get _initialDirectoryOrNull =>
      _defaultDirectory.isEmpty ? null : _defaultDirectory;

  /// Export a sequence to a JSON file
  Future<void> exportSequence(Sequence sequence) async {
    // Prepare JSON
    final json = _sequenceToJson(sequence);
    final jsonString = const JsonEncoder.withIndent('  ').convert(json);

    // Show save dialog
    final saveLocation = await file_selector.getSaveLocation(
      initialDirectory: _initialDirectoryOrNull,
      suggestedName: '${sequence.name}.nseq.json',
      acceptedTypeGroups: [
        const file_selector.XTypeGroup(
          label: 'Nightshade Sequence',
          extensions: ['json', 'nseq'],
        ),
      ],
    );

    if (saveLocation == null) return;

    // Write file
    final file = File(saveLocation.path);
    await file.writeAsString(jsonString);
  }

  /// Import a sequence from a JSON file
  Future<Sequence?> importSequence() async {
    // Show open dialog
    final file = await file_selector.openFile(
      initialDirectory: _initialDirectoryOrNull,
      acceptedTypeGroups: [
        const file_selector.XTypeGroup(
          label: 'Nightshade Sequence',
          extensions: ['json', 'nseq'],
        ),
      ],
    );

    if (file == null) return null;

    // Read and parse file
    final jsonString = await file.readAsString();
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      throw FormatException('Invalid JSON in sequence file: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Sequence file must contain a JSON object, got ${decoded.runtimeType}',
      );
    }

    _validateSequenceJson(decoded);

    // Read schema version and apply migrations if needed
    final migrated = _migrateSchema(decoded);

    final sequence = _jsonToSequence(migrated);
    _importValidator?.call(sequence);
    return sequence;
  }

  /// Read the schemaVersion from a sequence JSON and apply any needed migrations.
  /// Files without a schemaVersion are treated as version 0 (pre-versioning format).
  /// Returns the migrated JSON (may be the same object if no migration needed).
  Map<String, dynamic> _migrateSchema(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    final version = rawVersion is int ? rawVersion : 0;

    if (version > currentSchemaVersion) {
      throw FormatException(
        'Sequence file has schemaVersion $version, but this version of Nightshade '
        'only supports up to schemaVersion $currentSchemaVersion. '
        'Please update Nightshade to open this file.',
      );
    }

    // Apply migrations in order. Each case falls through to the next.
    // Add new migration cases here when incrementing currentSchemaVersion.
    //
    // Example for future migration:
    // if (version < 2) {
    //   // Migrate from v1 to v2: e.g., rename a field
    //   json['newFieldName'] = json.remove('oldFieldName');
    // }

    // Version 0 -> 1: No structural changes needed. Version 0 files
    // (pre-versioning) are compatible with version 1.

    // Stamp the current version so re-exports are up to date
    json['schemaVersion'] = currentSchemaVersion;
    return json;
  }

  /// Validate that a sequence JSON object has the required fields and types
  /// before attempting to parse it. Throws [FormatException] on validation failure.
  void _validateSequenceJson(Map<String, dynamic> json) {
    // 'nodes' is required and must be a map
    if (!json.containsKey('nodes')) {
      throw const FormatException(
        'Sequence file missing required field "nodes"',
      );
    }
    if (json['nodes'] is! Map) {
      throw FormatException(
        'Sequence field "nodes" must be a JSON object, '
        'got ${json['nodes'].runtimeType}',
      );
    }

    // 'name' must be a string if present
    if (json.containsKey('name') && json['name'] is! String) {
      throw FormatException(
        'Sequence field "name" must be a string, got ${json['name'].runtimeType}',
      );
    }

    // 'rootNodeId' must be a string if present
    if (json.containsKey('rootNodeId') &&
        json['rootNodeId'] != null &&
        json['rootNodeId'] is! String) {
      throw FormatException(
        'Sequence field "rootNodeId" must be a string, '
        'got ${json['rootNodeId'].runtimeType}',
      );
    }

    // 'isTemplate' must be a bool if present
    if (json.containsKey('isTemplate') &&
        json['isTemplate'] != null &&
        json['isTemplate'] is! bool) {
      throw FormatException(
        'Sequence field "isTemplate" must be a boolean, '
        'got ${json['isTemplate'].runtimeType}',
      );
    }

    // Validate each node has a 'nodeType' string
    final nodesMap = (json['nodes'] as Map).cast<String, dynamic>();
    for (final entry in nodesMap.entries) {
      if (entry.value is! Map) {
        throw FormatException(
          'Sequence node "${entry.key}" must be a JSON object, '
          'got ${entry.value.runtimeType}',
        );
      }
      final nodeJson = (entry.value as Map).cast<String, dynamic>();
      if (!nodeJson.containsKey('nodeType') ||
          nodeJson['nodeType'] is! String ||
          (nodeJson['nodeType'] as String).trim().isEmpty) {
        throw FormatException(
          'Sequence node "${entry.key}" missing required string field "nodeType"',
        );
      }
    }
  }

  /// Current schema version for exported sequences.
  /// Increment this when making breaking changes to the JSON format
  /// and add a migration case in [_migrateSchema].
  static const int currentSchemaVersion = 1;

  /// Parse a pre-decoded sequence JSON map (no file I/O, no migration).
  /// Used by [SampleSequenceService] to decode bundled assets through the
  /// same node-type switch the file-picker importer uses, so the on-disk
  /// schema stays the single source of truth.
  ///
  /// Callers are expected to supply a map that already conforms to the
  /// current schema version. Validation is identical to the file importer
  /// (missing `nodes` / bad `nodeType` throws [FormatException]) but the
  /// import-validator callback is NOT invoked — that hook is reserved for
  /// user-imported files and shouldn't run on bundled templates.
  Sequence parseFromMap(Map<String, dynamic> json) {
    _validateSequenceJson(json);
    final migrated = _migrateSchema(json);
    return _jsonToSequence(migrated);
  }

  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
      'schemaVersion': currentSchemaVersion,
      'version': '2.0',
      'name': sequence.name,
      'description': sequence.description,
      'rootNodeId': sequence.rootNodeId,
      'isTemplate': sequence.isTemplate,
      'nodes':
          sequence.nodes.map((id, node) => MapEntry(id, _nodeToJson(node))),
      'createdAt': sequence.createdAt.toIso8601String(),
      'modifiedAt': sequence.modifiedAt.toIso8601String(),
    };
  }

  Sequence _jsonToSequence(Map<String, dynamic> json) {
    final nodes = <String, SequenceNode>{};
    final nodesJson = (json['nodes'] as Map?)?.cast<String, dynamic>() ?? {};

    for (final entry in nodesJson.entries) {
      final node = _jsonToNode(entry.value as Map<String, dynamic>,
          fallbackId: entry.key);
      nodes[node.id] = node;
    }

    return Sequence(
      id: const Uuid().v4(), // Generate new ID for imported sequence
      name: json['name'] as String? ?? 'Imported Sequence',
      description: json['description'] as String? ?? '',
      nodes: nodes,
      rootNodeId: json['rootNodeId'] as String?,
      isTemplate: json['isTemplate'] as bool? ?? false,
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      modifiedAt: _parseDate(json['modifiedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> _nodeToJson(SequenceNode node) {
    final base = <String, dynamic>{
      'id': node.id,
      'nodeType': node.nodeType,
      'name': node.name,
      'parentId': node.parentId,
      'childIds': node.childIds,
      'orderIndex': node.orderIndex,
      'isEnabled': node.isEnabled,
    };

    // Exhaustive switch over the sealed SequenceNode hierarchy so new node
    // subtypes fail to compile here rather than silently exporting without
    // their type-specific properties (which would corrupt the JSON schema).
    final extras = switch (node) {
      TargetHeaderNode() => <String, dynamic>{
          'targetName': node.targetName,
          'raHours': node.raHours,
          'decDegrees': node.decDegrees,
          'rotation': node.rotation,
          'priority': node.priority,
          'minAltitude': node.minAltitude,
          'maxAltitude': node.maxAltitude,
          'startAfter': node.startAfter?.toIso8601String(),
          'endBefore': node.endBefore?.toIso8601String(),
          'mosaicPanel': node.mosaicPanel?.toJson(),
        },
      LoopNode() => <String, dynamic>{
          'conditionType': node.conditionType.name,
          'repeatCount': node.repeatCount,
          'repeatUntil': node.repeatUntil?.toIso8601String(),
          'repeatUntilAltitude': node.repeatUntilAltitude,
          'integrationTimeTarget': node.integrationTimeTarget,
          'maxSafetyIterations': node.maxSafetyIterations,
        },
      ParallelNode() => <String, dynamic>{
          'requiredSuccesses': node.requiredSuccesses,
        },
      ConditionalNode() => <String, dynamic>{
          'conditionType': node.conditionType.name,
          'thresholdValue': node.thresholdValue,
          'thresholdTime': node.thresholdTime?.toIso8601String(),
        },
      RecoveryNode() => <String, dynamic>{
          'recoveryAction': node.recoveryAction.name,
          'maxRetries': node.maxRetries,
          'triggerType': node.triggerType?.name,
          'triggerThreshold': node.triggerThreshold,
          'hfrThresholdPercent': node.hfrThresholdPercent,
          'hfrConsecutiveFrames': node.hfrConsecutiveFrames,
        },
      SlewNode() => <String, dynamic>{
          'useTargetCoords': node.useTargetCoords,
          'customRa': node.customRa,
          'customDec': node.customDec,
        },
      CenterNode() => <String, dynamic>{
          'useTargetCoords': node.useTargetCoords,
          'customRa': node.customRa,
          'customDec': node.customDec,
          'accuracyArcsec': node.accuracyArcsec,
          'maxAttempts': node.maxAttempts,
          'exposureDuration': node.exposureDuration,
          'filter': node.filter,
        },
      ExposureNode() => <String, dynamic>{
          'durationSecs': node.durationSecs,
          'count': node.count,
          'frameType': node.frameType.name,
          'filter': node.filter,
          'filterIndex': node.filterIndex,
          'gain': node.gain,
          'offset': node.offset,
          'binning': node.binning.name,
          'ditherEvery': node.ditherEvery,
          'triggers': node.triggers,
        },
      AutofocusNode() => <String, dynamic>{
          'method': node.method.name,
          'stepSize': node.stepSize,
          'stepsOut': node.stepsOut,
          'exposuresPerPoint': node.exposuresPerPoint,
          'exposureDuration': node.exposureDuration,
          'useSettingsDefaults': node.useSettingsDefaults,
          'maxDurationSecs': node.maxDurationSecs,
        },
      DitherNode() => <String, dynamic>{
          'pixels': node.pixels,
          'settlePixels': node.settlePixels,
          'settleTime': node.settleTime,
          'settleTimeout': node.settleTimeout,
          'raOnly': node.raOnly,
        },
      StartGuidingNode() => <String, dynamic>{
          'settlePixels': node.settlePixels,
          'settleTime': node.settleTime,
          'settleTimeout': node.settleTimeout,
          'autoSelectStar': node.autoSelectStar,
        },
      FilterChangeNode() => <String, dynamic>{
          'filterName': node.filterName,
          'filterPosition': node.filterPosition,
        },
      CoolCameraNode() => <String, dynamic>{
          'targetTemp': node.targetTemp,
          'durationMins': node.durationMins,
        },
      WarmCameraNode() => <String, dynamic>{
          'ratePerMin': node.ratePerMin,
          'targetTemp': node.targetTemp,
        },
      RotatorNode() => <String, dynamic>{
          'targetAngle': node.targetAngle,
          'relative': node.relative,
        },
      WaitTimeNode() => <String, dynamic>{
          'waitUntil': node.waitUntil?.toIso8601String(),
          'waitForTwilight': node.waitForTwilight?.name,
        },
      DelayNode() => <String, dynamic>{
          'seconds': node.seconds,
        },
      NotificationNode() => <String, dynamic>{
          'title': node.title,
          'message': node.message,
          'level': node.level.name,
        },
      ScriptNode() => <String, dynamic>{
          'scriptPath': node.scriptPath,
          'arguments': node.arguments,
          'timeoutSecs': node.timeoutSecs,
        },
      MeridianFlipNode() => <String, dynamic>{
          'triggerMethod': node.triggerMethod.name,
          'minutesPastMeridian': node.minutesPastMeridian,
          'minutesBeforeLimit': node.minutesBeforeLimit,
          'hourAngleThreshold': node.hourAngleThreshold,
          'pauseGuiding': node.pauseGuiding,
          'autoCenter': node.autoCenter,
          'refocusAfter': node.refocusAfter,
          'settleTime': node.settleTime,
          'resumeGuiding': node.resumeGuiding,
          'maxRetries': node.maxRetries,
          'failureAction': node.failureAction.name,
        },
      OpenDomeNode() => <String, dynamic>{
          'shutterOnly': node.shutterOnly,
        },
      CloseDomeNode() => <String, dynamic>{
          'shutterOnly': node.shutterOnly,
        },
      ParkDomeNode() => <String, dynamic>{
          'shutterOnly': node.shutterOnly,
        },
      PolarAlignmentNode() => <String, dynamic>{
          'exposureDuration': node.exposureDuration,
          'binning': node.binning,
          'startAltitude': node.startAltitude,
          'rotationStep': node.rotationStep,
          'gain': node.gain,
          'offset': node.offset,
          'startFromCurrent': node.startFromCurrent,
          'isNorth': node.isNorth,
          'manualSlew': node.manualSlew,
        },
      // Side-effect-only nodes have no type-specific fields beyond the base.
      InstructionSetNode() ||
      StopGuidingNode() ||
      ParkNode() ||
      UnparkNode() ||
      OpenCoverNode() ||
      CloseCoverNode() ||
      CalibratorOnNode() ||
      CalibratorOffNode() =>
        const <String, dynamic>{},
    };

    base.addAll(extras);
    return base;
  }

  SequenceNode _jsonToNode(Map<String, dynamic> json, {String? fallbackId}) {
    final rawType = json['nodeType'] as String?;
    if (rawType == null || rawType.trim().isEmpty) {
      throw const FormatException('Sequence node missing nodeType');
    }

    final nodeType = _normalizeNodeType(rawType);
    final id = (json['id'] as String?) ?? fallbackId ?? const Uuid().v4();
    final name = json['name'] as String?;
    final parentId = json['parentId'] as String?;
    final childIds =
        (json['childIds'] as List<dynamic>?)?.cast<String>() ?? const [];
    final orderIndex = (json['orderIndex'] as num?)?.toInt() ?? 0;
    final isEnabled = json['isEnabled'] as bool? ?? false;

    switch (nodeType) {
      case 'targetheader':
      case 'targetgroup':
        final targetName = json['targetName'] as String?;
        final raHours = json['raHours'] as num?;
        final decDegrees = json['decDegrees'] as num?;
        if (targetName == null || raHours == null || decDegrees == null) {
          throw const FormatException('Target node missing required fields');
        }
        return TargetHeaderNode(
          id: id,
          name: name ?? 'Target',
          targetName: targetName,
          raHours: raHours.toDouble(),
          decDegrees: decDegrees.toDouble(),
          rotation: (json['rotation'] as num?)?.toDouble(),
          priority: (json['priority'] as num?)?.toInt() ?? 0,
          minAltitude: (json['minAltitude'] as num?)?.toDouble(),
          maxAltitude: (json['maxAltitude'] as num?)?.toDouble(),
          startAfter: _parseDate(json['startAfter']),
          endBefore: _parseDate(json['endBefore']),
          mosaicPanel: json['mosaicPanel'] != null
              ? MosaicPanelInfo.fromJson(
                  json['mosaicPanel'] as Map<String, dynamic>)
              : null,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'loop':
        return LoopNode(
          id: id,
          name: name ?? 'Loop',
          conditionType: _parseLoopConditionType(json['conditionType']),
          repeatCount: (json['repeatCount'] as num?)?.toInt(),
          repeatUntil: _parseDate(json['repeatUntil']),
          repeatUntilAltitude:
              (json['repeatUntilAltitude'] as num?)?.toDouble(),
          integrationTimeTarget:
              (json['integrationTimeTarget'] as num?)?.toDouble(),
          maxSafetyIterations: (json['maxSafetyIterations'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'parallel':
        return ParallelNode(
          id: id,
          name: name ?? 'Parallel',
          requiredSuccesses: (json['requiredSuccesses'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'conditional':
        return ConditionalNode(
          id: id,
          name: name ?? 'Conditional',
          conditionType: _parseConditionalType(json['conditionType']),
          thresholdValue: (json['thresholdValue'] as num?)?.toDouble(),
          thresholdTime: _parseDate(json['thresholdTime']),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'recovery':
        return RecoveryNode(
          id: id,
          name: name ?? 'Recovery',
          recoveryAction: _parseRecoveryActionType(json['recoveryAction']),
          maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 3,
          triggerType: _parseTriggerType(json['triggerType']),
          triggerThreshold: (json['triggerThreshold'] as num?)?.toDouble(),
          hfrThresholdPercent:
              (json['hfrThresholdPercent'] as num?)?.toDouble() ?? 20.0,
          hfrConsecutiveFrames:
              (json['hfrConsecutiveFrames'] as num?)?.toInt() ?? 3,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'instructionset':
        return InstructionSetNode(
          id: id,
          name: name ?? 'Instructions',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'slewtotarget':
      case 'slew':
        return SlewNode(
          id: id,
          name: name ?? 'Slew to Target',
          useTargetCoords: json['useTargetCoords'] as bool? ?? true,
          customRa: (json['customRa'] as num?)?.toDouble(),
          customDec: (json['customDec'] as num?)?.toDouble(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'centertarget':
      case 'center':
        return CenterNode(
          id: id,
          name: name ?? 'Center Target',
          useTargetCoords: json['useTargetCoords'] as bool? ?? true,
          customRa: (json['customRa'] as num?)?.toDouble(),
          customDec: (json['customDec'] as num?)?.toDouble(),
          accuracyArcsec: (json['accuracyArcsec'] as num?)?.toDouble() ?? 5.0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 5,
          exposureDuration:
              (json['exposureDuration'] as num?)?.toDouble() ?? 5.0,
          filter: json['filter'] as String?,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'takeexposure':
      case 'exposure':
        return ExposureNode(
          id: id,
          name: name ?? 'Take Exposures',
          durationSecs: (json['durationSecs'] as num?)?.toDouble() ?? 60.0,
          count: (json['count'] as num?)?.toInt() ?? 10,
          frameType: _parseFrameType(json['frameType']),
          filter: json['filter'] as String?,
          gain: (json['gain'] as num?)?.toInt(),
          offset: (json['offset'] as num?)?.toInt(),
          filterIndex: (json['filterIndex'] as num?)?.toInt(),
          binning: _parseBinningMode(json['binning']),
          ditherEvery: (json['ditherEvery'] as num?)?.toInt(),
          triggers: ((json['triggers'] as List?) ?? const [])
              .whereType<Map>()
              .map((trigger) => trigger.cast<String, dynamic>())
              .toList(growable: false),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'autofocus':
        return AutofocusNode(
          id: id,
          name: name ?? 'Autofocus',
          method: _parseAutofocusMethod(json['method']),
          stepSize: (json['stepSize'] as num?)?.toInt() ?? 100,
          stepsOut: (json['stepsOut'] as num?)?.toInt() ?? 7,
          exposuresPerPoint: (json['exposuresPerPoint'] as num?)?.toInt() ?? 1,
          exposureDuration:
              (json['exposureDuration'] as num?)?.toDouble() ?? 3.0,
          useSettingsDefaults: json['useSettingsDefaults'] as bool? ?? true,
          maxDurationSecs:
              (json['maxDurationSecs'] as num?)?.toDouble() ?? 600.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'dither':
        return DitherNode(
          id: id,
          name: name ?? 'Dither',
          pixels: (json['pixels'] as num?)?.toDouble() ?? 5.0,
          settlePixels: (json['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 30.0,
          settleTimeout: (json['settleTimeout'] as num?)?.toDouble() ?? 120.0,
          raOnly: json['raOnly'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'startguiding':
        return StartGuidingNode(
          id: id,
          name: name ?? 'Start Guiding',
          settlePixels: (json['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 10.0,
          settleTimeout: (json['settleTimeout'] as num?)?.toDouble() ?? 60.0,
          autoSelectStar: json['autoSelectStar'] as bool? ?? true,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'stopguiding':
        return StopGuidingNode(
          id: id,
          name: name ?? 'Stop Guiding',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'changefilter':
      case 'filterchange':
        return FilterChangeNode(
          id: id,
          name: name ?? 'Change Filter',
          filterName: json['filterName'] as String? ?? '',
          filterPosition: (json['filterPosition'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'coolcamera':
        return CoolCameraNode(
          id: id,
          name: name ?? 'Cool Camera',
          targetTemp: (json['targetTemp'] as num?)?.toDouble() ?? -10.0,
          durationMins: (json['durationMins'] as num?)?.toDouble(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'warmcamera':
        return WarmCameraNode(
          id: id,
          name: name ?? 'Warm Camera',
          ratePerMin: (json['ratePerMin'] as num?)?.toDouble() ?? 2.0,
          targetTemp: (json['targetTemp'] as num?)?.toDouble() ?? 20.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'moverotator':
      case 'rotator':
        return RotatorNode(
          id: id,
          name: name ?? 'Move Rotator',
          targetAngle: (json['targetAngle'] as num?)?.toDouble() ?? 0.0,
          relative: json['relative'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'park':
        return ParkNode(
          id: id,
          name: name ?? 'Park Mount',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'unpark':
        return UnparkNode(
          id: id,
          name: name ?? 'Unpark Mount',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'waitfortime':
      case 'waittime':
        return WaitTimeNode(
          id: id,
          name: name ?? 'Wait for Time',
          waitUntil: _parseDate(json['waitUntil']),
          waitForTwilight: _parseTwilightType(json['waitForTwilight']),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'delay':
        return DelayNode(
          id: id,
          name: name ?? 'Delay',
          seconds: (json['seconds'] as num?)?.toDouble() ?? 5.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'notification':
        return NotificationNode(
          id: id,
          name: name ?? 'Send Notification',
          title: json['title'] as String? ?? '',
          message: json['message'] as String? ?? '',
          level: _parseNotificationLevel(json['level']),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'runscript':
      case 'script':
        return ScriptNode(
          id: id,
          name: name ?? 'Run Script',
          scriptPath: json['scriptPath'] as String? ?? '',
          arguments:
              (json['arguments'] as List<dynamic>?)?.cast<String>() ?? const [],
          timeoutSecs: (json['timeoutSecs'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'meridianflip':
        return MeridianFlipNode(
          id: id,
          name: name ?? 'Meridian Flip',
          triggerMethod: _parseMeridianTriggerMethod(json['triggerMethod']),
          minutesPastMeridian:
              (json['minutesPastMeridian'] as num?)?.toDouble() ?? 5.0,
          minutesBeforeLimit:
              (json['minutesBeforeLimit'] as num?)?.toDouble() ?? 10.0,
          hourAngleThreshold:
              (json['hourAngleThreshold'] as num?)?.toDouble() ?? 0.5,
          pauseGuiding: json['pauseGuiding'] as bool? ?? true,
          autoCenter: json['autoCenter'] as bool? ?? true,
          refocusAfter: json['refocusAfter'] as bool? ?? false,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 10.0,
          resumeGuiding: json['resumeGuiding'] as bool? ?? true,
          maxRetries: json['maxRetries'] as int? ?? 3,
          failureAction: _parseFlipFailureAction(json['failureAction']),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'opendome':
        return OpenDomeNode(
          id: id,
          name: name ?? 'Open Dome',
          shutterOnly: json['shutterOnly'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'closedome':
        return CloseDomeNode(
          id: id,
          name: name ?? 'Close Dome',
          shutterOnly: json['shutterOnly'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'parkdome':
        return ParkDomeNode(
          id: id,
          name: name ?? 'Park Dome',
          shutterOnly: json['shutterOnly'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'polalignment':
      case 'polaralignment':
        return PolarAlignmentNode(
          id: id,
          name: name ?? 'Polar Alignment',
          exposureDuration:
              (json['exposureDuration'] as num?)?.toDouble() ?? 2.0,
          binning: (json['binning'] as num?)?.toInt() ?? 2,
          startAltitude: (json['startAltitude'] as num?)?.toDouble() ?? 45.0,
          rotationStep: (json['rotationStep'] as num?)?.toDouble() ?? 20.0,
          gain: (json['gain'] as num?)?.toInt(),
          offset: (json['offset'] as num?)?.toInt(),
          startFromCurrent: json['startFromCurrent'] as bool? ?? false,
          isNorth: json['isNorth'] as bool? ?? false,
          manualSlew: json['manualSlew'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      default:
        throw FormatException('Unsupported sequence node type: $rawType');
    }
  }

  String _normalizeNodeType(String nodeType) {
    return nodeType.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    return null;
  }

  FrameType _parseFrameType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return FrameType.light;
    return FrameType.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => FrameType.light,
    );
  }

  BinningMode _parseBinningMode(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return BinningMode.one;
    return BinningMode.values.firstWhere(
      (mode) => mode.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => BinningMode.one,
    );
  }

  AutofocusMethod _parseAutofocusMethod(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return AutofocusMethod.vCurve;
    // Handle legacy 'parabolic' name from old files
    final normalized = raw.toLowerCase() == 'parabolic' ? 'quadratic' : raw;
    return AutofocusMethod.values.firstWhere(
      (method) => method.name.toLowerCase() == normalized.toLowerCase(),
      orElse: () => AutofocusMethod.vCurve,
    );
  }

  LoopConditionType _parseLoopConditionType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return LoopConditionType.count;
    return LoopConditionType.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => LoopConditionType.count,
    );
  }

  NotificationLevel _parseNotificationLevel(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return NotificationLevel.info;
    return NotificationLevel.values.firstWhere(
      (level) => level.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => NotificationLevel.info,
    );
  }

  ConditionalType _parseConditionalType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return ConditionalType.always;
    return ConditionalType.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => ConditionalType.always,
    );
  }

  RecoveryActionType _parseRecoveryActionType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return RecoveryActionType.retry;
    return RecoveryActionType.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => RecoveryActionType.retry,
    );
  }

  TriggerType? _parseTriggerType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return null;
    for (final type in TriggerType.values) {
      if (type.name.toLowerCase() == raw.toLowerCase()) {
        return type;
      }
    }
    return null;
  }

  TwilightType? _parseTwilightType(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return null;
    for (final type in TwilightType.values) {
      if (type.name.toLowerCase() == raw.toLowerCase()) {
        return type;
      }
    }
    return null;
  }

  MeridianTriggerMethod _parseMeridianTriggerMethod(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return MeridianTriggerMethod.minutesPastMeridian;
    return MeridianTriggerMethod.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => MeridianTriggerMethod.minutesPastMeridian,
    );
  }

  FlipFailureAction _parseFlipFailureAction(dynamic value) {
    final raw = value is String ? value : null;
    if (raw == null) return FlipFailureAction.pauseAndAlert;
    return FlipFailureAction.values.firstWhere(
      (type) => type.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => FlipFailureAction.pauseAndAlert,
    );
  }
}

/// Provider for the sequence file service
final sequenceFileServiceProvider = Provider<SequenceFileService>((ref) {
  // Why: route export/import dialogs through the user-configured
  // Settings → File Paths → Sequences directory when set. We do not
  // `watch` the settings provider here — the file-service factory is
  // long-lived and rebuilding it on every settings tick would invalidate
  // dependents. Instead we read the current snapshot and capture it; the
  // app uses the path at dialog-open time which already reads through
  // the same provider tree.
  String defaultDir = '';
  try {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    defaultDir = settings?.sequencesPath ?? '';
  } catch (_) {
    // Why: a unit test may construct this provider without a database.
    // The fall-through to empty string mirrors the "not configured"
    // path in production. Fail-loud is reserved for real consumers.
    defaultDir = '';
  }
  return SequenceFileService(
    defaultDirectory: defaultDir,
    importValidator: (sequence) {
      final activeProfile = ref.read(activeEquipmentProfileProvider);
      final availableFilters =
          activeProfile?.filterNames.toSet() ?? const <String>{};
      final referencedFilters = <String>{};

      for (final node in sequence.nodes.values) {
        if (node is ExposureNode &&
            node.filter != null &&
            node.filter!.isNotEmpty) {
          referencedFilters.add(node.filter!);
        } else if (node is FilterChangeNode && node.filterName.isNotEmpty) {
          referencedFilters.add(node.filterName);
        }
      }

      if (referencedFilters.isEmpty) {
        return;
      }

      if (availableFilters.isEmpty) {
        throw FormatException(
          'Sequence import requires an active equipment profile with filters configured. '
          'Referenced filters: ${referencedFilters.toList()..sort()}',
        );
      }

      final missingFilters = referencedFilters.difference(availableFilters);
      if (missingFilters.isNotEmpty) {
        final missing = missingFilters.toList()..sort();
        throw FormatException(
          'Sequence references filters not present in the active equipment profile: $missing',
        );
      }
    },
  );
});
