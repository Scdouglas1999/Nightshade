import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart' as db;
import '../database/daos/sequences_dao.dart';
import '../models/sequence/sequence_models.dart';
import '../providers/database_provider.dart';

/// Repository for saving and loading sequences from the database
class SequenceRepository {
  final SequencesDao _dao;

  SequenceRepository(this._dao);

  /// Save a sequence to the database
  /// Returns the database ID of the saved sequence
  Future<int> saveSequence(Sequence sequence, {bool isTemplate = false}) async {
    // Check if this sequence already exists in database
    final existingId = sequence.databaseId;
    
    if (existingId != null) {
      // Update existing sequence
      await _updateSequence(existingId, sequence, isTemplate);
      return existingId;
    } else {
      // Create new sequence
      return await _createSequence(sequence, isTemplate);
    }
  }

  Future<int> _createSequence(Sequence sequence, bool isTemplate) async {
    // Create the sequence record
    final sequenceId = await _dao.createSequence(
      db.SequencesCompanion.insert(
        name: sequence.name,
        description: Value(sequence.description),
        rootNodeId: Value(sequence.rootNodeId),
        estimatedDurationMins: Value(
          (sequence.totalIntegrationSecs / 60).ceil(),
        ),
        isTemplate: Value(isTemplate),
      ),
    );

    // Save all nodes
    await _saveNodes(sequenceId, sequence.nodes);

    return sequenceId;
  }

  Future<void> _updateSequence(int sequenceId, Sequence sequence, bool isTemplate) async {
    // Get existing sequence
    final existing = await _dao.getSequenceById(sequenceId);
    if (existing == null) {
      throw Exception('Sequence $sequenceId not found');
    }

    // Update sequence metadata
    await _dao.updateSequence(
      db.Sequence(
        id: sequenceId,
        name: sequence.name,
        description: sequence.description,
        rootNodeId: sequence.rootNodeId,
        estimatedDurationMins: (sequence.totalIntegrationSecs / 60).ceil(),
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        isTemplate: isTemplate,
      ),
    );

    // Delete existing nodes and recreate
    await _dao.deleteSequence(sequenceId);
    await _createSequence(sequence, isTemplate);
  }

  Future<void> _saveNodes(int sequenceId, Map<String, SequenceNode> nodes) async {
    for (final node in nodes.values) {
      await _dao.createNode(
        db.SequenceNodesCompanion.insert(
          nodeId: node.id,
          sequenceId: sequenceId,
          nodeType: _getNodeCategory(node),
          specificType: node.nodeType,
          name: node.name,
          properties: Value(jsonEncode(_nodeToProperties(node))),
          parentNodeId: Value(node.parentId),
          orderIndex: Value(node.orderIndex),
          isEnabled: Value(node.isEnabled),
        ),
      );
    }
  }

  String _getNodeCategory(SequenceNode node) {
    if (node is TargetGroupNode || node is LoopNode || 
        node is ParallelNode || node is ConditionalNode || 
        node is RecoveryNode) {
      return 'logic';
    }
    return 'instruction';
  }

  /// Load a sequence from the database
  Future<Sequence?> loadSequence(int sequenceId) async {
    final dbSequence = await _dao.getSequenceById(sequenceId);
    if (dbSequence == null) return null;

    final dbNodes = await _dao.getNodesForSequence(sequenceId);
    
    // Convert database nodes to model nodes
    final nodes = <String, SequenceNode>{};
    for (final dbNode in dbNodes) {
      final node = _dbNodeToModel(dbNode);
      if (node != null) {
        nodes[node.id] = node;
      }
    }

    // Build child relationships
    for (final dbNode in dbNodes) {
      if (dbNode.parentNodeId != null && nodes.containsKey(dbNode.parentNodeId)) {
        final parent = nodes[dbNode.parentNodeId!]!;
        final childIds = [...parent.childIds, dbNode.nodeId];
        nodes[dbNode.parentNodeId!] = parent.copyWith(childIds: childIds);
      }
    }

    return Sequence(
      id: dbSequence.id.toString(),
      databaseId: dbSequence.id,
      name: dbSequence.name,
      description: dbSequence.description ?? '',
      nodes: nodes,
      rootNodeId: dbSequence.rootNodeId,
      isTemplate: dbSequence.isTemplate,
      createdAt: dbSequence.createdAt,
      modifiedAt: dbSequence.updatedAt,
    );
  }

  /// Load all sequences from the database
  Future<List<Sequence>> loadAllSequences() async {
    final dbSequences = await _dao.getAllSequences();
    final sequences = <Sequence>[];
    
    for (final dbSequence in dbSequences) {
      final sequence = await loadSequence(dbSequence.id);
      if (sequence != null) {
        sequences.add(sequence);
      }
    }
    
    return sequences;
  }

  /// Load all templates from the database
  Future<List<Sequence>> loadAllTemplates() async {
    final dbTemplates = await _dao.getAllTemplates();
    final templates = <Sequence>[];
    
    for (final dbTemplate in dbTemplates) {
      final template = await loadSequence(dbTemplate.id);
      if (template != null) {
        templates.add(template);
      }
    }
    
    return templates;
  }

  /// Delete a sequence from the database
  Future<void> deleteSequence(int sequenceId) async {
    await _dao.deleteSequence(sequenceId);
  }

  /// Duplicate a sequence
  Future<Sequence?> duplicateSequence(int sequenceId, String newName) async {
    final newId = await _dao.duplicateSequence(sequenceId, newName);
    return loadSequence(newId);
  }

  SequenceNode? _dbNodeToModel(db.SequenceNode dbNode) {
    final props = jsonDecode(dbNode.properties) as Map<String, dynamic>;
    
    switch (dbNode.specificType) {
      case 'exposure':
        return ExposureNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          durationSecs: (props['durationSecs'] as num?)?.toDouble() ?? 60.0,
          count: (props['count'] as num?)?.toInt() ?? 1,
          filter: props['filter'] as String?,
          gain: (props['gain'] as num?)?.toInt(),
          offset: (props['offset'] as num?)?.toInt(),
          binning: _stringToBinning(props['binning'] as String?),
          ditherEvery: (props['ditherEvery'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'slew':
        return SlewNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          useTargetCoords: props['useTargetCoords'] as bool? ?? true,
          customRa: (props['customRa'] as num?)?.toDouble(),
          customDec: (props['customDec'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'center':
        return CenterNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          useTargetCoords: props['useTargetCoords'] as bool? ?? true,
          accuracyArcsec: (props['accuracyArcsec'] as num?)?.toDouble() ?? 5.0,
          maxAttempts: (props['maxAttempts'] as num?)?.toInt() ?? 5,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'autofocus':
        return AutofocusNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          method: _stringToAutofocusMethod(props['method'] as String?),
          stepSize: (props['stepSize'] as num?)?.toInt() ?? 100,
          stepsOut: (props['stepsOut'] as num?)?.toInt() ?? 7,
          exposureDuration: (props['exposureDuration'] as num?)?.toDouble() ?? 3.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'dither':
        return DitherNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          pixels: (props['pixels'] as num?)?.toDouble() ?? 5.0,
          settlePixels: (props['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (props['settleTime'] as num?)?.toDouble() ?? 30.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'filterChange':
        return FilterChangeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          filterName: props['filterName'] as String? ?? '',
          filterPosition: (props['filterPosition'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'coolCamera':
        return CoolCameraNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetTemp: (props['targetTemp'] as num?)?.toDouble() ?? -10.0,
          durationMins: (props['durationMins'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'warmCamera':
        return WarmCameraNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          ratePerMin: (props['ratePerMin'] as num?)?.toDouble() ?? 2.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'rotator':
        return RotatorNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetAngle: (props['targetAngle'] as num?)?.toDouble() ?? 0.0,
          relative: props['relative'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'park':
        return ParkNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'unpark':
        return UnparkNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'waitTime':
        return WaitTimeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          waitUntil: props['waitUntil'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(props['waitUntil'] as int)
              : null,
          waitForTwilight: _stringToTwilight(props['waitForTwilight'] as String?),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'delay':
        return DelayNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          seconds: (props['seconds'] as num?)?.toDouble() ?? 5.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'notification':
        return NotificationNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          title: props['title'] as String? ?? '',
          message: props['message'] as String? ?? '',
          level: _stringToNotificationLevel(props['level'] as String?),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'script':
        return ScriptNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          scriptPath: props['scriptPath'] as String? ?? '',
          arguments: (props['arguments'] as List<dynamic>?)?.cast<String>() ?? [],
          timeoutSecs: (props['timeoutSecs'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'targetGroup':
        return TargetGroupNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetName: props['targetName'] as String? ?? '',
          raHours: (props['raHours'] as num?)?.toDouble() ?? 0.0,
          decDegrees: (props['decDegrees'] as num?)?.toDouble() ?? 0.0,
          rotation: (props['rotation'] as num?)?.toDouble(),
          minAltitude: (props['minAltitude'] as num?)?.toDouble(),
          maxAltitude: (props['maxAltitude'] as num?)?.toDouble(),
          priority: (props['priority'] as num?)?.toInt() ?? 0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'loop':
        return LoopNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          conditionType: _stringToLoopCondition(props['conditionType'] as String?),
          repeatCount: (props['repeatCount'] as num?)?.toInt() ?? 1,
          repeatUntil: props['repeatUntil'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(props['repeatUntil'] as int)
              : null,
          repeatUntilAltitude: (props['repeatUntilAltitude'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'parallel':
        return ParallelNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          requiredSuccesses: (props['requiredSuccesses'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'conditional':
        return ConditionalNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          conditionType: _stringToConditionalType(props['conditionType'] as String?),
          thresholdValue: (props['thresholdValue'] as num?)?.toDouble(),
          thresholdTime: props['thresholdTime'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(props['thresholdTime'] as int)
              : null,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      case 'recovery':
        return RecoveryNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          recoveryAction: _stringToRecoveryAction(props['recoveryAction'] as String?),
          maxRetries: (props['maxRetries'] as num?)?.toInt() ?? 3,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
        );
        
      default:
        return null;
    }
  }

  Map<String, dynamic> _nodeToProperties(SequenceNode node) {
    if (node is ExposureNode) {
      return {
        'durationSecs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'gain': node.gain,
        'offset': node.offset,
        'binning': _binningToString(node.binning),
        'ditherEvery': node.ditherEvery,
      };
    } else if (node is SlewNode) {
      return {
        'useTargetCoords': node.useTargetCoords,
        'customRa': node.customRa,
        'customDec': node.customDec,
      };
    } else if (node is CenterNode) {
      return {
        'useTargetCoords': node.useTargetCoords,
        'accuracyArcsec': node.accuracyArcsec,
        'maxAttempts': node.maxAttempts,
      };
    } else if (node is AutofocusNode) {
      return {
        'method': _autofocusMethodToString(node.method),
        'stepSize': node.stepSize,
        'stepsOut': node.stepsOut,
        'exposureDuration': node.exposureDuration,
      };
    } else if (node is DitherNode) {
      return {
        'pixels': node.pixels,
        'settlePixels': node.settlePixels,
        'settleTime': node.settleTime,
      };
    } else if (node is FilterChangeNode) {
      return {
        'filterName': node.filterName,
        'filterPosition': node.filterPosition,
      };
    } else if (node is CoolCameraNode) {
      return {
        'targetTemp': node.targetTemp,
        'durationMins': node.durationMins,
      };
    } else if (node is WarmCameraNode) {
      return {
        'ratePerMin': node.ratePerMin,
      };
    } else if (node is RotatorNode) {
      return {
        'targetAngle': node.targetAngle,
        'relative': node.relative,
      };
    } else if (node is WaitTimeNode) {
      return {
        'waitUntil': node.waitUntil?.millisecondsSinceEpoch,
        'waitForTwilight': node.waitForTwilight != null 
            ? _twilightToString(node.waitForTwilight!) 
            : null,
      };
    } else if (node is DelayNode) {
      return {
        'seconds': node.seconds,
      };
    } else if (node is NotificationNode) {
      return {
        'title': node.title,
        'message': node.message,
        'level': _notificationLevelToString(node.level),
      };
    } else if (node is ScriptNode) {
      return {
        'scriptPath': node.scriptPath,
        'arguments': node.arguments,
        'timeoutSecs': node.timeoutSecs,
      };
    } else if (node is TargetGroupNode) {
      return {
        'targetName': node.targetName,
        'raHours': node.raHours,
        'decDegrees': node.decDegrees,
        'rotation': node.rotation,
        'minAltitude': node.minAltitude,
        'maxAltitude': node.maxAltitude,
        'priority': node.priority,
      };
    } else if (node is LoopNode) {
      return {
        'conditionType': _loopConditionToString(node.conditionType),
        'repeatCount': node.repeatCount,
        'repeatUntil': node.repeatUntil?.millisecondsSinceEpoch,
        'repeatUntilAltitude': node.repeatUntilAltitude,
      };
    } else if (node is ParallelNode) {
      return {
        'requiredSuccesses': node.requiredSuccesses,
      };
    } else if (node is ConditionalNode) {
      return {
        'conditionType': _conditionalTypeToString(node.conditionType),
        'thresholdValue': node.thresholdValue,
        'thresholdTime': node.thresholdTime?.millisecondsSinceEpoch,
      };
    } else if (node is RecoveryNode) {
      return {
        'recoveryAction': _recoveryActionToString(node.recoveryAction),
        'maxRetries': node.maxRetries,
      };
    }
    return {};
  }

  // Helper methods for enum conversion
  String _binningToString(BinningMode mode) {
    switch (mode) {
      case BinningMode.one: return 'one';
      case BinningMode.two: return 'two';
      case BinningMode.three: return 'three';
      case BinningMode.four: return 'four';
    }
  }

  BinningMode _stringToBinning(String? s) {
    switch (s) {
      case 'two': return BinningMode.two;
      case 'three': return BinningMode.three;
      case 'four': return BinningMode.four;
      default: return BinningMode.one;
    }
  }

  String _autofocusMethodToString(AutofocusMethod method) {
    switch (method) {
      case AutofocusMethod.vCurve: return 'vCurve';
      case AutofocusMethod.hyperbolic: return 'hyperbolic';
      case AutofocusMethod.parabolic: return 'parabolic';
    }
  }

  AutofocusMethod _stringToAutofocusMethod(String? s) {
    switch (s) {
      case 'hyperbolic': return AutofocusMethod.hyperbolic;
      case 'parabolic': return AutofocusMethod.parabolic;
      default: return AutofocusMethod.vCurve;
    }
  }

  String _twilightToString(TwilightType type) {
    switch (type) {
      case TwilightType.civil: return 'civil';
      case TwilightType.nautical: return 'nautical';
      case TwilightType.astronomical: return 'astronomical';
    }
  }

  TwilightType? _stringToTwilight(String? s) {
    switch (s) {
      case 'civil': return TwilightType.civil;
      case 'nautical': return TwilightType.nautical;
      case 'astronomical': return TwilightType.astronomical;
      default: return null;
    }
  }

  String _notificationLevelToString(NotificationLevel level) {
    switch (level) {
      case NotificationLevel.info: return 'info';
      case NotificationLevel.warning: return 'warning';
      case NotificationLevel.error: return 'error';
      case NotificationLevel.success: return 'success';
    }
  }

  NotificationLevel _stringToNotificationLevel(String? s) {
    switch (s) {
      case 'warning': return NotificationLevel.warning;
      case 'error': return NotificationLevel.error;
      case 'success': return NotificationLevel.success;
      default: return NotificationLevel.info;
    }
  }

  String _loopConditionToString(LoopConditionType type) {
    switch (type) {
      case LoopConditionType.count: return 'count';
      case LoopConditionType.untilTime: return 'untilTime';
      case LoopConditionType.untilAltitude: return 'untilAltitude';
      case LoopConditionType.forever: return 'forever';
      case LoopConditionType.whileDark: return 'whileDark';
    }
  }

  LoopConditionType _stringToLoopCondition(String? s) {
    switch (s) {
      case 'untilTime': return LoopConditionType.untilTime;
      case 'untilAltitude': return LoopConditionType.untilAltitude;
      case 'forever': return LoopConditionType.forever;
      case 'whileDark': return LoopConditionType.whileDark;
      default: return LoopConditionType.count;
    }
  }

  String _conditionalTypeToString(ConditionalType type) {
    switch (type) {
      case ConditionalType.always: return 'always';
      case ConditionalType.altitudeAbove: return 'altitudeAbove';
      case ConditionalType.timeAfter: return 'timeAfter';
      case ConditionalType.guidingRmsBelow: return 'guidingRmsBelow';
      case ConditionalType.hfrBelow: return 'hfrBelow';
      case ConditionalType.weatherSafe: return 'weatherSafe';
      case ConditionalType.moonSeparationAbove: return 'moonSeparationAbove';
      case ConditionalType.safetyMonitorSafe: return 'safetyMonitorSafe';
    }
  }

  ConditionalType _stringToConditionalType(String? s) {
    switch (s) {
      case 'altitudeAbove': return ConditionalType.altitudeAbove;
      case 'timeAfter': return ConditionalType.timeAfter;
      case 'guidingRmsBelow': return ConditionalType.guidingRmsBelow;
      case 'hfrBelow': return ConditionalType.hfrBelow;
      case 'weatherSafe': return ConditionalType.weatherSafe;
      case 'moonSeparationAbove': return ConditionalType.moonSeparationAbove;
      case 'safetyMonitorSafe': return ConditionalType.safetyMonitorSafe;
      default: return ConditionalType.always;
    }
  }

  String _recoveryActionToString(RecoveryActionType action) {
    switch (action) {
      case RecoveryActionType.continueExecution: return 'continue';
      case RecoveryActionType.pause: return 'pause';
      case RecoveryActionType.autofocus: return 'autofocus';
      case RecoveryActionType.nextTarget: return 'nextTarget';
      case RecoveryActionType.retry: return 'retry';
      case RecoveryActionType.parkAndAbort: return 'parkAndAbort';
      case RecoveryActionType.customBranch: return 'customBranch';
    }
  }

  RecoveryActionType _stringToRecoveryAction(String? s) {
    switch (s) {
      case 'pause': return RecoveryActionType.pause;
      case 'autofocus': return RecoveryActionType.autofocus;
      case 'nextTarget': return RecoveryActionType.nextTarget;
      case 'retry': return RecoveryActionType.retry;
      case 'parkAndAbort': return RecoveryActionType.parkAndAbort;
      case 'customBranch': return RecoveryActionType.customBranch;
      default: return RecoveryActionType.continueExecution;
    }
  }
}

/// Provider for the sequence repository
final sequenceRepositoryProvider = Provider<SequenceRepository>((ref) {
  return SequenceRepository(ref.watch(sequencesDaoProvider));
});

