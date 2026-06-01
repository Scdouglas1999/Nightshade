part of '../sequence_file_service.dart';

extension _SequenceFileEncoder on SequenceFileService {
  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
      'schemaVersion': SequenceFileService.currentSchemaVersion,
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
          // Audit C2 — per-monitor targeting for multi-safety setups.
          'safetyMonitorId': node.safetyMonitorId,
        },
      RecoveryNode() => <String, dynamic>{
          'recoveryAction': node.recoveryAction.name,
          'maxRetries': node.maxRetries,
          'triggerType': node.triggerType?.name,
          'triggerThreshold': node.triggerThreshold,
          'hfrThresholdPercent': node.hfrThresholdPercent,
          'hfrConsecutiveFrames': node.hfrConsecutiveFrames,
          // Wave 1 Pack A added focusDrift as a distinct trigger type
          // with its own rolling-window parameters. Persist them so a
          // saved-then-reloaded sequence preserves the trigger config —
          // previously they would silently reset to defaults on import.
          'focusDriftWindowSize': node.focusDriftWindowSize,
          'focusDriftMinIncreasingCount': node.focusDriftMinIncreasingCount,
          'focusDriftMinTotalIncrease': node.focusDriftMinTotalIncrease,
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
          'pattern': node.pattern.name,
          'gridSize': node.gridSize,
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
          if (node.explicitTransports != null)
            'explicitTransports':
                node.explicitTransports!.map((t) => t.storageKey).toList(),
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
          // Why: persist the override flag so reloading a sequence preserves
          // whether the user explicitly overrode meridian flip behavior at the
          // node level vs. pulling from Sequencer Settings (audit §1.2).
          'useGlobalDefaults': node.useGlobalDefaults,
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
      // Wave 3 Agent 2: SmartExposure. Plans are serialised as a list of
      // FilterPlan JSON maps (snake_case Rust shape) so the same blob
      // round-trips through both disk persistence and the executor's
      // `_nodeToConfig` payload.
      SmartExposureNode() => <String, dynamic>{
          'plans': node.plans.map((p) => p.toJson()).toList(growable: false),
          'rotateFilters': node.rotateFilters,
          'ditherOnFilterChange': node.ditherOnFilterChange,
          'integrationBudgetSecs': node.integrationBudgetSecs,
          'batchSize': node.batchSize,
          'loopUntilStopped': node.loopUntilStopped,
        },
      // Wave 3 Agent 1: TargetScheduler config — eight knobs that
      // round-trip through disk persistence and the executor payload.
      TargetSchedulerNode() => <String, dynamic>{
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
        },
      // Wave 7 Agent 2: LiveStacking — broadcast / EAA node config.
      LiveStackingNode() => <String, dynamic>{
          'mode': node.mode.storageKey,
          'stackMethod': node.stackMethod.storageKey,
          'maxFramesToStack': node.maxFramesToStack,
          'broadcastEnabled': node.broadcastEnabled,
          'broadcastPort': node.broadcastPort,
          'broadcastPath': node.broadcastPath,
          'authToken': node.authToken,
          'watermarkText': node.watermarkText,
          'thumbnailWidth': node.thumbnailWidth,
          'thumbnailHeight': node.thumbnailHeight,
        },
      // Wave 7 Science: SciencePhotometry — cadence-enforced
      // photometric capture node config.
      SciencePhotometryNode() => <String, dynamic>{
          'targetDesignation': node.targetDesignation,
          'referenceStars': node.referenceStars,
          'maxCadenceGapSecs': node.maxCadenceGapSecs,
          'filter': node.filter,
          'exposureSecs': node.exposureSecs,
          'count': node.count,
          'reduceLive': node.reduceLive,
          'applyDifferential': node.applyDifferential,
          'quality': node.quality.toJson(),
          'gain': node.gain,
          'offset': node.offset,
          'binning': node.binning.name,
        },
      // Audit §11 — plugin-contributed instruction. Round-trip the
      // plugin identifiers + opaque config so an exported sequence
      // loads back into the same node configuration (assuming the
      // plugin is installed on the importing side).
      PluginInstructionNode() => <String, dynamic>{
          'pluginId': node.pluginId,
          'nodeTypeId': node.nodeTypeId,
          'configJson': node.configJson,
          'timeoutSecs': node.timeoutSecs,
          'pluginName': node.pluginName,
          'iconHint': node.iconHint,
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
}
