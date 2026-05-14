import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for mosaic generation
class MosaicHandlers {
  final ProviderContainer container;

  MosaicHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'MosaicHandlers');

  // ===========================================================================
  // Generate Mosaic Panels
  // ===========================================================================

  Future<Response> handleGeneratePanels(Request request) async {
    _logInfo('[API] POST /api/mosaic/generate-panels');
    final payload = await readJsonObject(request);
    final config = _parseMosaicConfig(requireObject(payload, 'config'));

    const service = MosaicService();
    final panels = service.generatePanels(config);

    return jsonOk({
      'panels': panels.map((p) => _panelToJson(p)).toList(),
    });
  }

  // ===========================================================================
  // Generate Mosaic Sequence
  // ===========================================================================

  Future<Response> handleGenerateSequence(Request request) async {
    _logInfo('[API] POST /api/mosaic/generate-sequence');
    final payload = await readJsonObject(request);

    final mosaicName = optionalString(payload, 'mosaicName') ?? 'Mosaic';
    final config = _parseMosaicConfig(requireObject(payload, 'config'));
    final exposure =
        _parseExposureSettings(requireObject(payload, 'exposure'));
    final optionsJson = optionalObject(payload, 'options');
    final options = optionsJson != null
        ? _parseSequenceOptions(optionsJson)
        : const MosaicSequenceOptions();

    const service = MosaicService();
    final nodes = service.createMosaicSequence(
      mosaicName: mosaicName,
      config: config,
      exposure: exposure,
      options: options,
    );

    // Find the root node ID
    String? rootNodeId;
    for (final entry in nodes.entries) {
      if (entry.value is InstructionSetNode) {
        final node = entry.value as InstructionSetNode;
        if (node.parentId == null) {
          rootNodeId = node.id;
          break;
        }
      }
    }

    return jsonOk({
      'sequence': {
        'name': mosaicName,
        'rootNodeId': rootNodeId,
        'nodes': nodes.map((key, node) => MapEntry(key, _nodeToJson(node))),
        'totalPanels': config.totalPanels,
        'estimatedTimeSecs': service.estimateMosaicTime(config, exposure),
      },
    });
  }

  // ===========================================================================
  // Calculate Mosaic Area
  // ===========================================================================

  Future<Response> handleCalculateArea(Request request) async {
    _logInfo('[API] POST /api/mosaic/calculate-area');
    final payload = await readJsonObject(request);
    final config = _parseMosaicConfig(requireObject(payload, 'config'));

    const service = MosaicService();
    final area = service.calculateMosaicArea(config);

    return jsonOk({
      'areaSquareDegrees': area,
      'totalPanels': config.totalPanels,
    });
  }

  // ===========================================================================
  // Validate Mosaic Configuration
  // ===========================================================================

  Future<Response> handleValidateMosaic(Request request) async {
    _logInfo('[API] POST /api/mosaic/validate');
    final payload = await readJsonObject(request);
    final config = _parseMosaicConfig(requireObject(payload, 'config'));

    const service = MosaicService();
    final validation = service.validateMosaic(config);

    return jsonOk({
      'isValid': validation.isValid,
      'errors': validation.errors,
      'warnings': validation.warnings,
    });
  }

  // ===========================================================================
  // Estimate Mosaic Time
  // ===========================================================================

  Future<Response> handleEstimateTime(Request request) async {
    _logInfo('[API] POST /api/mosaic/estimate-time');
    final payload = await readJsonObject(request);

    final config = _parseMosaicConfig(requireObject(payload, 'config'));
    final exposure =
        _parseExposureSettings(requireObject(payload, 'exposure'));
    final overheadPerPanel =
        optionalDouble(payload, 'overheadPerPanelSecs') ?? 60.0;

    const service = MosaicService();
    final timeSecs = service.estimateMosaicTime(
      config,
      exposure,
      overheadPerPanelSecs: overheadPerPanel,
    );

    return jsonOk({
      'estimatedTimeSecs': timeSecs,
      'estimatedTimeHours': timeSecs / 3600,
      'totalPanels': config.totalPanels,
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  MosaicConfig _parseMosaicConfig(Map<String, dynamic> json) {
    return MosaicConfig(
      centerRa: requireDouble(json, 'centerRa'),
      centerDec: requireDouble(json, 'centerDec'),
      panelWidthArcmin: requireDouble(json, 'panelWidthArcmin'),
      panelHeightArcmin: requireDouble(json, 'panelHeightArcmin'),
      overlapPercent: optionalDouble(json, 'overlapPercent') ?? 10.0,
      rotation: optionalDouble(json, 'rotation') ?? 0.0,
      panelsHorizontal: requireInt(json, 'panelsHorizontal', min: 1),
      panelsVertical: requireInt(json, 'panelsVertical', min: 1),
    );
  }

  MosaicExposureSettings _parseExposureSettings(Map<String, dynamic> json) {
    return MosaicExposureSettings(
      exposureSeconds: requireDouble(json, 'exposureSeconds'),
      exposuresPerPanel: requireInt(json, 'exposuresPerPanel', min: 1),
      filterName: optionalString(json, 'filterName'),
      binning: optionalInt(json, 'binning'),
      gain: optionalDouble(json, 'gain'),
      offset: optionalDouble(json, 'offset'),
    );
  }

  MosaicSequenceOptions _parseSequenceOptions(Map<String, dynamic> json) {
    return MosaicSequenceOptions(
      serpentineOrdering: optionalBool(json, 'serpentineOrdering') ?? false,
      autofocusPerPanel: optionalBool(json, 'autofocusPerPanel') ?? false,
      autofocusInterval: optionalInt(json, 'autofocusInterval') ?? 0,
      centerAfterSlew: optionalBool(json, 'centerAfterSlew') ?? false,
      ditherBetweenExposures:
          optionalBool(json, 'ditherBetweenExposures') ?? false,
      ditherPixels: optionalDouble(json, 'ditherPixels'),
      minAltitude: optionalDouble(json, 'minAltitude'),
      maxAltitude: optionalDouble(json, 'maxAltitude'),
    );
  }

  Map<String, dynamic> _panelToJson(MosaicPanel panel) {
    return {
      'raHours': panel.raHours,
      'decDegrees': panel.decDegrees,
      'panelIndex': panel.panelIndex,
      'row': panel.row,
      'col': panel.col,
    };
  }

  Map<String, dynamic> _nodeToJson(SequenceNode node) {
    final base = {
      'id': node.id,
      'name': node.name,
      'type': node.runtimeType.toString(),
      'parentId': node.parentId,
      'orderIndex': node.orderIndex,
      'isEnabled': node.isEnabled,
    };

    // Add type-specific fields
    if (node is ExposureNode) {
      base['durationSecs'] = node.durationSecs;
      base['count'] = node.count;
      base['filter'] = node.filter;
      base['frameType'] = node.frameType.name;
    } else if (node is InstructionSetNode) {
      base['childIds'] = node.childIds;
    } else if (node is TargetHeaderNode) {
      base['targetName'] = node.targetName;
      base['raHours'] = node.raHours;
      base['decDegrees'] = node.decDegrees;
      base['childIds'] = node.childIds;
    } else if (node is LoopNode) {
      base['repeatCount'] = node.repeatCount;
      base['childIds'] = node.childIds;
    } else if (node is SlewNode) {
      base['customRa'] = node.customRa;
      base['customDec'] = node.customDec;
    }

    return base;
  }
}
