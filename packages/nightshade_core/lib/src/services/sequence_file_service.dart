import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
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
      'nodes': sequence.nodes.map((id, node) => MapEntry(id, _nodeToJson(node))),
      'createdAt': sequence.createdAt.toIso8601String(),
      'modifiedAt': sequence.modifiedAt.toIso8601String(),
    };
  }
  
  Sequence _jsonToSequence(Map<String, dynamic> json) {
    final nodes = <String, SequenceNode>{};
    final nodesJson = json['nodes'] as Map<String, dynamic>;
    
    for (final entry in nodesJson.entries) {
      final node = _jsonToNode(entry.value as Map<String, dynamic>);
      if (node != null) {
        nodes[entry.key] = node;
      }
    }
    
    return Sequence(
      id: const Uuid().v4(), // Generate new ID for imported sequence
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
    if (node is ExposureNode) {
      base.addAll({
        'durationSecs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'gain': node.gain,
        'offset': node.offset,
        'binning': node.binning.name,
        'ditherEvery': node.ditherEvery,
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
    } else if (node is AutofocusNode) {
      base.addAll({
        'method': node.method.name,
        'stepSize': node.stepSize,
        'stepsOut': node.stepsOut,
        'exposureDuration': node.exposureDuration,
      });
    } else if (node is DitherNode) {
      base.addAll({
        'pixels': node.pixels,
        'settlePixels': node.settlePixels,
        'settleTime': node.settleTime,
      });
    } else if (node is LoopNode) {
      base.addAll({
        'conditionType': node.conditionType.name,
        'repeatCount': node.repeatCount,
        'repeatUntil': node.repeatUntil?.toIso8601String(),
        'repeatUntilAltitude': node.repeatUntilAltitude,
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
    }
    // Add more node types as needed...
    
    return base;
  }
  
  SequenceNode? _jsonToNode(Map<String, dynamic> json) {
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
        
      case 'center':
        return CenterNode(
          id: json['id'] as String,
          name: json['name'] as String,
          useTargetCoords: json['useTargetCoords'] as bool? ?? true,
          accuracyArcsec: (json['accuracyArcsec'] as num).toDouble(),
          maxAttempts: json['maxAttempts'] as int,
          parentId: json['parentId'] as String?,
          childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
          orderIndex: json['orderIndex'] as int,
          isEnabled: json['isEnabled'] as bool? ?? true,
        );
        
      case 'autofocus':
        return AutofocusNode(
          id: json['id'] as String,
          name: json['name'] as String,
          method: AutofocusMethod.values.firstWhere(
            (e) => e.name == json['method'],
            orElse: () => AutofocusMethod.vCurve,
          ),
          stepSize: json['stepSize'] as int,
          stepsOut: json['stepsOut'] as int,
          exposureDuration: (json['exposureDuration'] as num).toDouble(),
          parentId: json['parentId'] as String?,
          childIds: (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
          orderIndex: json['orderIndex'] as int,
          isEnabled: json['isEnabled'] as bool? ?? true,
        );
        
      case 'dither':
        return DitherNode(
          id: json['id'] as String,
          name: json['name'] as String,
          pixels: (json['pixels'] as num).toDouble(),
          settlePixels: (json['settlePixels'] as num).toDouble(),
          settleTime: (json['settleTime'] as num).toDouble(),
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
        
      // Add more node types as needed...
      default:
        return null;
    }
  }
}

/// Provider for the sequence file service
final sequenceFileServiceProvider = Provider<SequenceFileService>((ref) {
  return SequenceFileService();
});
