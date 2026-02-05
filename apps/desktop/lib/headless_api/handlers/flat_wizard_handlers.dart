import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for flat frame calibration and sequence generation
class FlatWizardHandlers {
  final ProviderContainer container;

  FlatWizardHandlers(this.container);

  // ===========================================================================
  // Calibrate Single Filter
  // ===========================================================================

  Future<Response> handleCalibrateFilter(Request request) async {
    print('[API] POST /api/flat-wizard/calibrate');
    try {
      final payload = jsonDecode(await request.readAsString());

      final deviceId = payload['deviceId'] as String;
      final filter = payload['filter'] as String;
      final targetAdu = (payload['targetAdu'] as num).toDouble();
      final tolerance = (payload['tolerance'] as num?)?.toDouble() ?? 10.0;
      final minExposure = (payload['minExposure'] as num?)?.toDouble() ?? 0.001;
      final maxExposure = (payload['maxExposure'] as num?)?.toDouble() ?? 30.0;
      final maxIterations = payload['maxIterations'] as int? ?? 10;
      final binX = payload['binX'] as int? ?? 1;
      final binY = payload['binY'] as int? ?? 1;

      final service = container.read(flatWizardServiceProvider);
      final result = await service.calibrateFilter(
        deviceId: deviceId,
        filter: filter,
        targetAdu: targetAdu,
        tolerance: tolerance,
        minExposure: minExposure,
        maxExposure: maxExposure,
        maxIterations: maxIterations,
        binX: binX,
        binY: binY,
      );

      return Response.ok(
        jsonEncode({
          "result": _flatResultToJson(result),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Calibrate filter error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Calibrate Multiple Filters
  // ===========================================================================

  Future<Response> handleCalibrateMultipleFilters(Request request) async {
    print('[API] POST /api/flat-wizard/calibrate-multi');
    try {
      final payload = jsonDecode(await request.readAsString());

      final deviceId = payload['deviceId'] as String;
      final filters = (payload['filters'] as List).cast<String>();
      final targetAdu = (payload['targetAdu'] as num).toDouble();
      final tolerance = (payload['tolerance'] as num?)?.toDouble() ?? 10.0;
      final minExposure = (payload['minExposure'] as num?)?.toDouble() ?? 0.001;
      final maxExposure = (payload['maxExposure'] as num?)?.toDouble() ?? 30.0;
      final maxIterations = payload['maxIterations'] as int? ?? 10;
      final binX = payload['binX'] as int? ?? 1;
      final binY = payload['binY'] as int? ?? 1;

      final service = container.read(flatWizardServiceProvider);
      final results = await service.calibrateMultipleFilters(
        deviceId: deviceId,
        filters: filters,
        targetAdu: targetAdu,
        tolerance: tolerance,
        minExposure: minExposure,
        maxExposure: maxExposure,
        maxIterations: maxIterations,
        binX: binX,
        binY: binY,
      );

      return Response.ok(
        jsonEncode({
          "results": results.map((r) => _flatResultToJson(r)).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Calibrate multiple filters error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Generate Sequence from Calibrations
  // ===========================================================================

  Future<Response> handleGenerateSequence(Request request) async {
    print('[API] POST /api/flat-wizard/generate-sequence');
    try {
      final payload = jsonDecode(await request.readAsString());

      // Parse calibration results
      final calibrationsJson = payload['calibrations'] as List;
      final calibrations = calibrationsJson.map((c) => FlatResult(
        filter: c['filter'] as String,
        exposure: (c['exposure'] as num).toDouble(),
        adu: (c['adu'] as num).toDouble(),
        success: c['success'] as bool,
        iterations: c['iterations'] as int? ?? 0,
        errorMessage: c['errorMessage'] as String?,
      )).toList();

      final framesPerFilter = payload['framesPerFilter'] as int;
      final sequenceName = payload['sequenceName'] as String? ?? 'Flat Frame Sequence';
      final description = payload['description'] as String?;
      final binX = payload['binX'] as int? ?? 1;
      final binY = payload['binY'] as int? ?? 1;
      final gain = payload['gain'] as int?;
      final offset = payload['offset'] as int?;
      final onlySuccessful = payload['onlySuccessful'] as bool? ?? true;

      final service = container.read(flatWizardServiceProvider);
      final sequence = service.generateCompleteSequence(
        calibrations: calibrations,
        framesPerFilter: framesPerFilter,
        sequenceName: sequenceName,
        description: description,
        binX: binX,
        binY: binY,
        gain: gain,
        offset: offset,
        onlySuccessful: onlySuccessful,
      );

      return Response.ok(
        jsonEncode({
          "sequence": _sequenceToJson(sequence),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Generate sequence error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Quick Calibrate
  // ===========================================================================

  Future<Response> handleQuickCalibrate(Request request) async {
    print('[API] POST /api/flat-wizard/quick-calibrate');
    try {
      final payload = jsonDecode(await request.readAsString());

      final deviceId = payload['deviceId'] as String;
      final filter = payload['filter'] as String;
      final targetAdu = (payload['targetAdu'] as num?)?.toDouble() ?? 30000;
      final tolerancePercent = (payload['tolerancePercent'] as num?)?.toDouble() ?? 10.0;
      final binX = payload['binX'] as int? ?? 1;
      final binY = payload['binY'] as int? ?? 1;

      final service = container.read(flatWizardServiceProvider);
      final result = await service.quickCalibrate(
        deviceId: deviceId,
        filter: filter,
        targetAdu: targetAdu,
        tolerancePercent: tolerancePercent,
        binX: binX,
        binY: binY,
      );

      return Response.ok(
        jsonEncode({
          "result": _flatResultToJson(result),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Quick calibrate error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Map<String, dynamic> _flatResultToJson(FlatResult result) {
    return {
      'filter': result.filter,
      'exposure': result.exposure,
      'adu': result.adu,
      'success': result.success,
      'iterations': result.iterations,
      'errorMessage': result.errorMessage,
    };
  }

  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
      'id': sequence.id,
      'name': sequence.name,
      'description': sequence.description,
      'rootNodeId': sequence.rootNodeId,
      'isTemplate': sequence.isTemplate,
      'createdAt': sequence.createdAt.millisecondsSinceEpoch,
      'modifiedAt': sequence.modifiedAt.millisecondsSinceEpoch,
      'nodes': sequence.nodes.map((key, node) => MapEntry(key, _nodeToJson(node))),
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
      base['gain'] = node.gain;
      base['offset'] = node.offset;
      base['binning'] = node.binning.name;
      base['frameType'] = node.frameType.name;
    } else if (node is InstructionSetNode) {
      base['childIds'] = node.childIds;
    }

    return base;
  }
}
