import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/imaging/imaging_models.dart' show FrameType;
import '../models/sequence/sequence_models.dart';

/// Service for saving and loading sequences to/from JSON files
class SequenceFileService {
  /// Export a sequence to a JSON file
  Future<void> exportSequence(Sequence sequence) async {
    // Prepare JSON
    final json = _sequenceToJson(sequence);
    final jsonString = const JsonEncoder.withIndent('  ').convert(json);

    // Show save dialog
    final saveLocation = await file_selector.getSaveLocation(
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
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    return _jsonToSequence(json);
  }

  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
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
    final base = {
      'id': node.id,
      'nodeType': node.nodeType,
      'name': node.name,
      'parentId': node.parentId,
      'childIds': node.childIds,
      'orderIndex': node.orderIndex,
      'isEnabled': node.isEnabled,
    };

    // Add type-specific properties
    if (node is TargetHeaderNode) {
      base.addAll({
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
      });
    } else if (node is LoopNode) {
      base.addAll({
        'conditionType': node.conditionType.name,
        'repeatCount': node.repeatCount,
        'repeatUntil': node.repeatUntil?.toIso8601String(),
        'repeatUntilAltitude': node.repeatUntilAltitude,
      });
    } else if (node is ParallelNode) {
      base.addAll({
        'requiredSuccesses': node.requiredSuccesses,
      });
    } else if (node is ConditionalNode) {
      base.addAll({
        'conditionType': node.conditionType.name,
        'thresholdValue': node.thresholdValue,
        'thresholdTime': node.thresholdTime?.toIso8601String(),
      });
    } else if (node is RecoveryNode) {
      base.addAll({
        'recoveryAction': node.recoveryAction.name,
        'maxRetries': node.maxRetries,
        'triggerType': node.triggerType?.name,
        'triggerThreshold': node.triggerThreshold,
      });
    } else if (node is SlewNode) {
      base.addAll({
        'useTargetCoords': node.useTargetCoords,
        'customRa': node.customRa,
        'customDec': node.customDec,
      });
    } else if (node is CenterNode) {
      base.addAll({
        'useTargetCoords': node.useTargetCoords,
        'accuracyArcsec': node.accuracyArcsec,
        'maxAttempts': node.maxAttempts,
      });
    } else if (node is ExposureNode) {
      base.addAll({
        'durationSecs': node.durationSecs,
        'count': node.count,
        'frameType': node.frameType.name,
        'filter': node.filter,
        'filterIndex': node.filterIndex,
        'gain': node.gain,
        'offset': node.offset,
        'binning': node.binning.name,
        'ditherEvery': node.ditherEvery,
      });
    } else if (node is AutofocusNode) {
      base.addAll({
        'method': node.method.name,
        'stepSize': node.stepSize,
        'stepsOut': node.stepsOut,
        'exposuresPerPoint': node.exposuresPerPoint,
        'exposureDuration': node.exposureDuration,
      });
    } else if (node is DitherNode) {
      base.addAll({
        'pixels': node.pixels,
        'settlePixels': node.settlePixels,
        'settleTime': node.settleTime,
      });
    } else if (node is StartGuidingNode) {
      base.addAll({
        'settlePixels': node.settlePixels,
        'settleTime': node.settleTime,
        'settleTimeout': node.settleTimeout,
        'autoSelectStar': node.autoSelectStar,
      });
    } else if (node is FilterChangeNode) {
      base.addAll({
        'filterName': node.filterName,
        'filterPosition': node.filterPosition,
      });
    } else if (node is CoolCameraNode) {
      base.addAll({
        'targetTemp': node.targetTemp,
        'durationMins': node.durationMins,
      });
    } else if (node is WarmCameraNode) {
      base.addAll({
        'ratePerMin': node.ratePerMin,
      });
    } else if (node is RotatorNode) {
      base.addAll({
        'targetAngle': node.targetAngle,
        'relative': node.relative,
      });
    } else if (node is WaitTimeNode) {
      base.addAll({
        'waitUntil': node.waitUntil?.toIso8601String(),
        'waitForTwilight': node.waitForTwilight?.name,
      });
    } else if (node is DelayNode) {
      base.addAll({
        'seconds': node.seconds,
      });
    } else if (node is NotificationNode) {
      base.addAll({
        'title': node.title,
        'message': node.message,
        'level': node.level.name,
      });
    } else if (node is ScriptNode) {
      base.addAll({
        'scriptPath': node.scriptPath,
        'arguments': node.arguments,
        'timeoutSecs': node.timeoutSecs,
      });
    } else if (node is MeridianFlipNode) {
      base.addAll({
        'minutesPastMeridian': node.minutesPastMeridian,
        'pauseGuiding': node.pauseGuiding,
        'autoCenter': node.autoCenter,
        'settleTime': node.settleTime,
      });
    } else if (node is OpenDomeNode) {
      base.addAll({
        'shutterOnly': node.shutterOnly,
      });
    } else if (node is CloseDomeNode) {
      base.addAll({
        'shutterOnly': node.shutterOnly,
      });
    } else if (node is ParkDomeNode) {
      base.addAll({
        'shutterOnly': node.shutterOnly,
      });
    } else if (node is PolarAlignmentNode) {
      base.addAll({
        'exposureDuration': node.exposureDuration,
        'binning': node.binning,
        'startAltitude': node.startAltitude,
        'rotationStep': node.rotationStep,
        'gain': node.gain,
        'offset': node.offset,
        'startFromCurrent': node.startFromCurrent,
        'isNorth': node.isNorth,
        'manualSlew': node.manualSlew,
      });
    }

    return base;
  }

  SequenceNode _jsonToNode(Map<String, dynamic> json, {String? fallbackId}) {
    final rawType = json['nodeType'] as String?;
    if (rawType == null || rawType.trim().isEmpty) {
      throw FormatException('Sequence node missing nodeType');
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
          throw FormatException('Target node missing required fields');
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
          useTargetCoords: json['useTargetCoords'] as bool? ?? false,
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
          useTargetCoords: json['useTargetCoords'] as bool? ?? false,
          accuracyArcsec: (json['accuracyArcsec'] as num?)?.toDouble() ?? 5.0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 5,
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
          autoSelectStar: json['autoSelectStar'] as bool? ?? false,
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
          minutesPastMeridian:
              (json['minutesPastMeridian'] as num?)?.toDouble() ?? 5.0,
          pauseGuiding: json['pauseGuiding'] as bool? ?? false,
          autoCenter: json['autoCenter'] as bool? ?? false,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 10.0,
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
    return AutofocusMethod.values.firstWhere(
      (method) => method.name.toLowerCase() == raw.toLowerCase(),
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
}

/// Provider for the sequence file service
final sequenceFileServiceProvider = Provider<SequenceFileService>((ref) {
  return SequenceFileService();
});
