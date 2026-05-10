import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// MosaicConfig/MosaicPanel collide with framing_provider's UI-level versions
// in the public barrel; this handler operates on MosaicService geometry types,
// so we hide the barrel versions and pull the service variants directly.
import 'package:nightshade_core/nightshade_core.dart'
    hide MosaicConfig, MosaicPanel;
import 'package:nightshade_core/src/services/mosaic_service.dart'
    show MosaicConfig, MosaicPanel;
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for mosaic generation
class MosaicHandlers {
  final ProviderContainer container;

  MosaicHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'MosaicHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'MosaicHandlers');

  // ===========================================================================
  // Generate Mosaic Panels
  // ===========================================================================

  Future<Response> handleGeneratePanels(Request request) async {
    _logInfo('[API] POST /api/mosaic/generate-panels');
    try {
      final payload = jsonDecode(await request.readAsString());

      final config =
          _parseMosaicConfig(payload['config'] as Map<String, dynamic>);

      const service = MosaicService();
      final panels = service.generatePanels(config);

      return jsonOk({
        "panels": panels.map((p) => _panelToJson(p)).toList(),
      });
    } catch (e) {
      _logError('[API] Generate panels error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Generate Mosaic Sequence
  // ===========================================================================

  Future<Response> handleGenerateSequence(Request request) async {
    _logInfo('[API] POST /api/mosaic/generate-sequence');
    try {
      final payload = jsonDecode(await request.readAsString());

      final mosaicName = payload['mosaicName'] as String? ?? 'Mosaic';
      final config =
          _parseMosaicConfig(payload['config'] as Map<String, dynamic>);
      final exposure =
          _parseExposureSettings(payload['exposure'] as Map<String, dynamic>);
      final options = payload['options'] != null
          ? _parseSequenceOptions(payload['options'] as Map<String, dynamic>)
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
        "sequence": {
          "name": mosaicName,
          "rootNodeId": rootNodeId,
          "nodes": nodes.map((key, node) => MapEntry(key, _nodeToJson(node))),
          "totalPanels": config.totalPanels,
          "estimatedTimeSecs": service.estimateMosaicTime(config, exposure),
        },
      });
    } catch (e) {
      _logError('[API] Generate mosaic sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Calculate Mosaic Area
  // ===========================================================================

  Future<Response> handleCalculateArea(Request request) async {
    _logInfo('[API] POST /api/mosaic/calculate-area');
    try {
      final payload = jsonDecode(await request.readAsString());

      final config =
          _parseMosaicConfig(payload['config'] as Map<String, dynamic>);

      const service = MosaicService();
      final area = service.calculateMosaicArea(config);

      return jsonOk({
        "areaSquareDegrees": area,
        "totalPanels": config.totalPanels,
      });
    } catch (e) {
      _logError('[API] Calculate area error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Validate Mosaic Configuration
  // ===========================================================================

  Future<Response> handleValidateMosaic(Request request) async {
    _logInfo('[API] POST /api/mosaic/validate');
    try {
      final payload = jsonDecode(await request.readAsString());

      final config =
          _parseMosaicConfig(payload['config'] as Map<String, dynamic>);

      const service = MosaicService();
      final validation = service.validateMosaic(config);

      return jsonOk({
        "isValid": validation.isValid,
        "errors": validation.errors,
        "warnings": validation.warnings,
      });
    } catch (e) {
      _logError('[API] Validate mosaic error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Estimate Mosaic Time
  // ===========================================================================

  Future<Response> handleEstimateTime(Request request) async {
    _logInfo('[API] POST /api/mosaic/estimate-time');
    try {
      final payload = jsonDecode(await request.readAsString());

      final config =
          _parseMosaicConfig(payload['config'] as Map<String, dynamic>);
      final exposure =
          _parseExposureSettings(payload['exposure'] as Map<String, dynamic>);
      final overheadPerPanel =
          (payload['overheadPerPanelSecs'] as num?)?.toDouble() ?? 60.0;

      const service = MosaicService();
      final timeSecs = service.estimateMosaicTime(
        config,
        exposure,
        overheadPerPanelSecs: overheadPerPanel,
      );

      return jsonOk({
        "estimatedTimeSecs": timeSecs,
        "estimatedTimeHours": timeSecs / 3600,
        "totalPanels": config.totalPanels,
      });
    } catch (e) {
      _logError('[API] Estimate time error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  MosaicConfig _parseMosaicConfig(Map<String, dynamic> json) {
    return MosaicConfig(
      centerRa: (json['centerRa'] as num).toDouble(),
      centerDec: (json['centerDec'] as num).toDouble(),
      panelWidthArcmin: (json['panelWidthArcmin'] as num).toDouble(),
      panelHeightArcmin: (json['panelHeightArcmin'] as num).toDouble(),
      overlapPercent: (json['overlapPercent'] as num?)?.toDouble() ?? 10.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      panelsHorizontal: json['panelsHorizontal'] as int,
      panelsVertical: json['panelsVertical'] as int,
    );
  }

  MosaicExposureSettings _parseExposureSettings(Map<String, dynamic> json) {
    return MosaicExposureSettings(
      exposureSeconds: (json['exposureSeconds'] as num).toDouble(),
      exposuresPerPanel: json['exposuresPerPanel'] as int,
      filterName: json['filterName'] as String?,
      binning: json['binning'] as int?,
      gain: (json['gain'] as num?)?.toDouble(),
      offset: (json['offset'] as num?)?.toDouble(),
    );
  }

  MosaicSequenceOptions _parseSequenceOptions(Map<String, dynamic> json) {
    return MosaicSequenceOptions(
      serpentineOrdering: json['serpentineOrdering'] as bool? ?? false,
      autofocusPerPanel: json['autofocusPerPanel'] as bool? ?? false,
      autofocusInterval: json['autofocusInterval'] as int? ?? 0,
      centerAfterSlew: json['centerAfterSlew'] as bool? ?? false,
      ditherBetweenExposures: json['ditherBetweenExposures'] as bool? ?? false,
      ditherPixels: (json['ditherPixels'] as num?)?.toDouble(),
      minAltitude: (json['minAltitude'] as num?)?.toDouble(),
      maxAltitude: (json['maxAltitude'] as num?)?.toDouble(),
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
