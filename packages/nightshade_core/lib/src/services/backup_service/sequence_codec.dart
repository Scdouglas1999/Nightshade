part of '../backup_service.dart';

extension _BackupSequenceCodec on BackupService {
  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
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
    } else if (node is TargetHeaderNode) {
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
    } else if (node is TargetSchedulerNode) {
      base.addAll({
        'altitudeWeight': node.altitudeWeight,
        'moonDistanceWeight': node.moonDistanceWeight,
        'transitProximityWeight': node.transitProximityWeight,
        'darknessWeight': node.darknessWeight,
        'airmassWeight': node.airmassWeight,
        'minScoreToRun': node.minScoreToRun,
        'recomputeEveryNExposures': node.recomputeEveryNExposures,
        'finishIterationOnSwitch': node.finishIterationOnSwitch,
        'swapOnConditionsBelow': node.swapOnConditionsBelow,
        'swapHysteresisSecs': node.swapHysteresisSecs,
        'brightnessTierPreferences': node.brightnessTierPreferences.toJson(),
        'maxConditionsScoreAgeSecs': node.maxConditionsScoreAgeSecs,
        'horizonProfile': _backupHorizonToJson(node.horizonProfile),
      });
    } else if (node is SmartExposureNode) {
      base.addAll({
        'plans': node.plans.map((p) => p.toJson()).toList(growable: false),
        'rotateFilters': node.rotateFilters,
        'ditherOnFilterChange': node.ditherOnFilterChange,
        'integrationBudgetSecs': node.integrationBudgetSecs,
        'batchSize': node.batchSize,
        'loopUntilStopped': node.loopUntilStopped,
      });
    }

    return base;
  }

  // =========================================================================
  // Private import methods
  // =========================================================================

  Future<int> _importSettings(Map<String, dynamic> settingsMap,
      {bool replace = false}) async {
    final settingsDao = SettingsDao(database);
    int count = 0;

    for (final entry in settingsMap.entries) {
      await settingsDao.setSetting(entry.key, entry.value?.toString() ?? '');
      count++;
    }

    return count;
  }

  Future<int> _importProfiles(List<dynamic> profilesList,
      {bool replace = false}) async {
    int count = 0;

    for (final profileJson in profilesList) {
      final profile = profileJson as Map<String, dynamic>;

      await database.into(database.equipmentProfiles).insert(
            EquipmentProfilesCompanion.insert(
              name: profile['name'] as String,
              description: Value(_stringOrNull(profile['description'])),
              isActive: Value(profile['isActive'] as bool? ?? false),
              cameraId: Value(_stringOrNull(profile['cameraId'])),
              mountId: Value(_stringOrNull(profile['mountId'])),
              focuserId: Value(_stringOrNull(profile['focuserId'])),
              filterWheelId: Value(_stringOrNull(profile['filterWheelId'])),
              guiderId: Value(_stringOrNull(profile['guiderId'])),
              rotatorId: Value(_stringOrNull(profile['rotatorId'])),
              domeId: Value(_stringOrNull(profile['domeId'])),
              weatherId: Value(_stringOrNull(profile['weatherId'])),
              focalLength: Value(_doubleOrDefault(profile['focalLength'], 0.0)),
              aperture: Value(_doubleOrDefault(profile['aperture'], 0.0)),
              focalRatio: Value(_doubleOrNull(profile['focalRatio'])),
              defaultGain: Value(_intOrNull(profile['defaultGain'])),
              defaultOffset: Value(_intOrNull(profile['defaultOffset'])),
              defaultBinX: Value(_intOrDefault(profile['defaultBinX'], 1)),
              defaultBinY: Value(_intOrDefault(profile['defaultBinY'], 1)),
              defaultCoolingTemp:
                  Value(_doubleOrNull(profile['defaultCoolingTemp'])),
              filterNames: Value(_stringOrNull(profile['filterNames'])),
              filterFocusOffsets:
                  Value(_stringOrNull(profile['filterFocusOffsets'])),
            ),
            mode: replace ? InsertMode.replace : InsertMode.insertOrIgnore,
          );
      count++;
    }

    return count;
  }

  Future<int> _importTargets(List<dynamic> targetsList,
      {bool replace = false}) async {
    int count = 0;

    for (final targetJson in targetsList) {
      final target = targetJson as Map<String, dynamic>;

      await database.into(database.targets).insert(
            TargetsCompanion.insert(
              name: target['name'] as String,
              catalogId: Value(_stringOrNull(target['catalogId'])),
              ra: _doubleOrDefault(target['ra'], 0.0),
              dec: _doubleOrDefault(target['dec'], 0.0),
              constellation: Value(_stringOrNull(target['constellation'])),
              objectType: Value(_stringOrNull(target['objectType'])),
              magnitude: Value(_doubleOrNull(target['magnitude'])),
              sizeArcmin: Value(_doubleOrNull(target['sizeArcmin'])),
              notes: Value(_stringOrNull(target['notes'])),
              isFavorite: Value(target['isFavorite'] as bool? ?? false),
              priority: Value(_intOrDefault(target['priority'], 0)),
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

      return Sequence.create(
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
      _logger.debug('Failed to parse sequence: $e');
      return null;
    }
  }

  SequenceNode? _jsonToNode(Map<String, dynamic> json) {
    try {
      final rawNodeType = json['nodeType'] as String;
      final nodeType =
          rawNodeType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      switch (nodeType) {
        case 'takeexposure':
        case 'exposure':
          return ExposureNode(
            id: json['id'] as String,
            name: json['name'] as String,
            durationSecs: (json['durationSecs'] as num?)?.toDouble() ?? 60.0,
            count: (json['count'] as num?)?.toInt() ?? 1,
            filter: json['filter'] as String?,
            filterIndex: (json['filterIndex'] as num?)?.toInt(),
            gain: (json['gain'] as num?)?.toInt(),
            offset: (json['offset'] as num?)?.toInt(),
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
            ditherEvery: (json['ditherEvery'] as num?)?.toInt(),
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
          );

        case 'targetheader':
        case 'targetgroup':
          return TargetHeaderNode(
            id: json['id'] as String,
            name: json['name'] as String,
            targetName: json['targetName'] as String,
            raHours: (json['raHours'] as num).toDouble(),
            decDegrees: (json['decDegrees'] as num).toDouble(),
            rotation: (json['rotation'] as num?)?.toDouble(),
            minAltitude: (json['minAltitude'] as num?)?.toDouble(),
            maxAltitude: (json['maxAltitude'] as num?)?.toDouble(),
            priority: (json['priority'] as num?)?.toInt() ?? 0,
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
          );

        case 'instructionset':
          return InstructionSetNode(
            id: json['id'] as String,
            name: json['name'] as String,
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
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
            repeatUntilAltitude:
                (json['repeatUntilAltitude'] as num?)?.toDouble(),
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
          );

        case 'targetscheduler':
        case 'targetschedulernode':
          return TargetSchedulerNode(
            id: json['id'] as String,
            name: json['name'] as String,
            altitudeWeight:
                (json['altitudeWeight'] as num?)?.toDouble() ?? 0.25,
            moonDistanceWeight:
                (json['moonDistanceWeight'] as num?)?.toDouble() ?? 0.25,
            transitProximityWeight:
                (json['transitProximityWeight'] as num?)?.toDouble() ?? 0.20,
            darknessWeight:
                (json['darknessWeight'] as num?)?.toDouble() ?? 0.15,
            airmassWeight: (json['airmassWeight'] as num?)?.toDouble() ?? 0.15,
            minScoreToRun: (json['minScoreToRun'] as num?)?.toDouble() ?? 30.0,
            recomputeEveryNExposures:
                (json['recomputeEveryNExposures'] as num?)?.toInt() ?? 0,
            finishIterationOnSwitch:
                json['finishIterationOnSwitch'] as bool? ?? true,
            swapOnConditionsBelow:
                (json['swapOnConditionsBelow'] as num?)?.toDouble() ??
                    (json['swap_on_conditions_below'] as num?)?.toDouble(),
            swapHysteresisSecs:
                (json['swapHysteresisSecs'] as num?)?.toDouble() ??
                    (json['swap_hysteresis_secs'] as num?)?.toDouble() ??
                    180.0,
            brightnessTierPreferences: _parseBrightnessTierPreferences(
              json['brightnessTierPreferences'] ??
                  json['brightness_tier_preferences'],
            ),
            maxConditionsScoreAgeSecs:
                (json['maxConditionsScoreAgeSecs'] as num?)?.toInt() ??
                    (json['max_conditions_score_age_secs'] as num?)?.toInt() ??
                    300,
            horizonProfile: _backupHorizonFromJson(
              json['horizonProfile'] ?? json['horizon_profile'],
            ),
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
          );

        case 'smartexposure':
        case 'smartexposurenode':
          return SmartExposureNode(
            id: json['id'] as String,
            name: json['name'] as String,
            plans: ((json['plans'] as List?) ?? const [])
                .whereType<Map>()
                .map((plan) => FilterPlan.fromJson(
                      plan.cast<String, dynamic>(),
                    ))
                .toList(growable: false),
            rotateFilters: json['rotateFilters'] as bool? ?? true,
            ditherOnFilterChange:
                json['ditherOnFilterChange'] as bool? ?? false,
            integrationBudgetSecs:
                (json['integrationBudgetSecs'] as num?)?.toDouble() ?? 0.0,
            batchSize: (json['batchSize'] as num?)?.toInt() ?? 1,
            loopUntilStopped: json['loopUntilStopped'] as bool? ?? false,
            parentId: json['parentId'] as String?,
            childIds:
                (json['childIds'] as List<dynamic>?)?.cast<String>() ?? [],
            orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
            isEnabled: json['isEnabled'] as bool? ?? false,
          );

        default:
          _logger.debug('Unknown node type: $rawNodeType');
          return null;
      }
    } catch (e) {
      _logger.debug('Failed to parse node: $e');
      return null;
    }
  }
}
