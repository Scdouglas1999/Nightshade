import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for flat frame calibration and sequence generation
class FlatWizardHandlers {
  final ProviderContainer container;

  FlatWizardHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FlatWizardHandlers');

  // ===========================================================================
  // Calibrate Single Filter
  // ===========================================================================

  Future<Response> handleCalibrateFilter(Request request) async {
    _logInfo('[API] POST /api/flat-wizard/calibrate');
    final payload = await readJsonObject(request);

    final deviceId = requireString(payload, 'deviceId');
    final filter = requireString(payload, 'filter');
    final targetAdu = requireDouble(payload, 'targetAdu');
    final tolerance = optionalDouble(payload, 'tolerance') ?? 10.0;
    final minExposure = optionalDouble(payload, 'minExposure') ?? 0.001;
    final maxExposure = optionalDouble(payload, 'maxExposure') ?? 30.0;
    final maxIterations = optionalInt(payload, 'maxIterations') ?? 10;
    final binX = optionalInt(payload, 'binX') ?? 1;
    final binY = optionalInt(payload, 'binY') ?? 1;
    final (gain, offset) = _resolveGainOffset(payload);

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
      gain: gain,
      offset: offset,
    );

    return jsonOk({
      'result': _flatResultToJson(result),
    });
  }

  // ===========================================================================
  // Calibrate Multiple Filters
  // ===========================================================================

  Future<Response> handleCalibrateMultipleFilters(Request request) async {
    _logInfo('[API] POST /api/flat-wizard/calibrate-multi');
    final payload = await readJsonObject(request);

    final deviceId = requireString(payload, 'deviceId');
    final filters = requireList<String>(payload, 'filters');
    final targetAdu = requireDouble(payload, 'targetAdu');
    final tolerance = optionalDouble(payload, 'tolerance') ?? 10.0;
    final minExposure = optionalDouble(payload, 'minExposure') ?? 0.001;
    final maxExposure = optionalDouble(payload, 'maxExposure') ?? 30.0;
    final maxIterations = optionalInt(payload, 'maxIterations') ?? 10;
    final binX = optionalInt(payload, 'binX') ?? 1;
    final binY = optionalInt(payload, 'binY') ?? 1;
    final (gain, offset) = _resolveGainOffset(payload);

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
      gain: gain,
      offset: offset,
    );

    return jsonOk({
      'results': results.map((r) => _flatResultToJson(r)).toList(),
    });
  }

  // ===========================================================================
  // Generate Sequence from Calibrations
  // ===========================================================================

  Future<Response> handleGenerateSequence(Request request) async {
    _logInfo('[API] POST /api/flat-wizard/generate-sequence');
    final payload = await readJsonObject(request);

    // Why we hand-validate each calibration entry instead of using the
    // typed helpers: requireList<Map<String, dynamic>> rejects List<dynamic>
    // (JSON's natural list type), so we read as a generic list and validate
    // each element through readJsonObject-equivalent shape checks.
    final calibrationsRaw = payload['calibrations'];
    if (calibrationsRaw is! List) {
      throw BadRequestError(field: 'calibrations', expected: 'array');
    }
    final calibrations = <FlatResult>[];
    for (var i = 0; i < calibrationsRaw.length; i++) {
      final entry = calibrationsRaw[i];
      if (entry is! Map<String, dynamic>) {
        throw BadRequestError(
          field: 'calibrations[$i]',
          expected: 'object',
        );
      }
      calibrations.add(FlatResult(
        filter: requireString(entry, 'filter'),
        exposure: requireDouble(entry, 'exposure'),
        adu: requireDouble(entry, 'adu'),
        success: requireBool(entry, 'success'),
        iterations: optionalInt(entry, 'iterations') ?? 0,
        errorMessage: optionalString(entry, 'errorMessage'),
      ));
    }

    final framesPerFilter = requireInt(payload, 'framesPerFilter', min: 1);
    final sequenceName =
        optionalString(payload, 'sequenceName') ?? 'Flat Frame Sequence';
    final description = optionalString(payload, 'description');
    final binX = optionalInt(payload, 'binX') ?? 1;
    final binY = optionalInt(payload, 'binY') ?? 1;
    final gain = optionalInt(payload, 'gain');
    final offset = optionalInt(payload, 'offset');
    final onlySuccessful = optionalBool(payload, 'onlySuccessful') ?? false;

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

    return jsonOk({
      'sequence': _sequenceToJson(sequence),
    });
  }

  // ===========================================================================
  // Quick Calibrate
  // ===========================================================================

  Future<Response> handleQuickCalibrate(Request request) async {
    _logInfo('[API] POST /api/flat-wizard/quick-calibrate');
    final payload = await readJsonObject(request);

    final deviceId = requireString(payload, 'deviceId');
    final filter = requireString(payload, 'filter');
    final targetAdu = optionalDouble(payload, 'targetAdu') ?? 30000;
    final tolerancePercent =
        optionalDouble(payload, 'tolerancePercent') ?? 10.0;
    final binX = optionalInt(payload, 'binX') ?? 1;
    final binY = optionalInt(payload, 'binY') ?? 1;
    final (gain, offset) = _resolveGainOffset(payload);

    final service = container.read(flatWizardServiceProvider);
    final result = await service.quickCalibrate(
      deviceId: deviceId,
      filter: filter,
      targetAdu: targetAdu,
      tolerancePercent: tolerancePercent,
      binX: binX,
      binY: binY,
      gain: gain,
      offset: offset,
    );

    return jsonOk({
      'result': _flatResultToJson(result),
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  (int, int) _resolveGainOffset(Map<String, dynamic> payload) {
    final gain = optionalInt(payload, 'gain');
    final offset = optionalInt(payload, 'offset');
    if (gain != null && offset != null) return (gain, offset);

    final profile = container.read(activeEquipmentProfileProvider);
    final resolvedGain = gain ?? profile?.defaultGain;
    final resolvedOffset = offset ?? profile?.defaultOffset;
    if (resolvedGain != null && resolvedOffset != null) {
      return (resolvedGain, resolvedOffset);
    }

    throw BadRequestError(
      field: gain == null ? 'gain' : 'offset',
      expected: 'integer',
      message:
          'Flat calibration requires gain and offset, either in the request or on the active equipment profile.',
    );
  }

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
      'nodes':
          sequence.nodes.map((key, node) => MapEntry(key, _nodeToJson(node))),
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
