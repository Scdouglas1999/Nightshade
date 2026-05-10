import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for sequencer control endpoints
class SequencerHandlers {
  final ProviderContainer container;
  SequencerHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequencerHandlers');

  Future<Response> handleSequencerStatus(Request request) async {
    final backend = container.read(backendProvider);
    final status = await backend.sequencerGetStatus();

    return jsonOk({
      'state': status.state,
      'currentNodeId': status.currentNodeId,
      'currentNodeName': status.currentNodeName,
      'progress': status.progress,
      'message': status.message,
    });
  }

  Future<Response> handleSequencerStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/start');
    final backend = container.read(backendProvider);
    await backend.sequencerStart();
    return jsonOk({'status': 'started'});
  }

  Future<Response> handleSequencerStop(Request request) async {
    _logInfo('[API] POST /api/sequencer/stop');
    final backend = container.read(backendProvider);
    await backend.sequencerStop();
    return jsonOk({'status': 'stopped'});
  }

  Future<Response> handleSequencerPause(Request request) async {
    _logInfo('[API] POST /api/sequencer/pause');
    final backend = container.read(backendProvider);
    await backend.sequencerPause();
    return jsonOk({'status': 'paused'});
  }

  Future<Response> handleSequencerResume(Request request) async {
    _logInfo('[API] POST /api/sequencer/resume');
    final backend = container.read(backendProvider);
    await backend.sequencerResume();
    return jsonOk({'status': 'resumed'});
  }

  Future<Response> handleSequencerSkip(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip');
    final backend = container.read(backendProvider);
    await backend.sequencerSkip();
    return jsonOk({'status': 'skipped'});
  }

  Future<Response> handleSequencerReset(Request request) async {
    _logInfo('[API] POST /api/sequencer/reset');
    final backend = container.read(backendProvider);
    await backend.sequencerReset();
    return jsonOk({'status': 'reset'});
  }

  Future<Response> handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    final payload = await readJsonObject(request);
    final json = requireString(payload, 'json');

    final backend = container.read(backendProvider);
    await backend.sequencerLoadJson(json);
    return jsonOk({'status': 'loaded'});
  }

  Future<Response> handleSequencerSetSimulationMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/simulation');
    final payload = await readJsonObject(request);
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(backendProvider);
    await backend.sequencerSetSimulationMode(enabled);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetDevices(Request request) async {
    _logInfo('[API] POST /api/sequencer/devices');
    final payload = await readJsonObject(request);

    // Why: filterFocusOffsets has dynamic-typed JSON object keys; validate
    // each value is numeric since requireList can't express map<string,int>
    // and we want a precise per-key error path instead of a ClassCastException.
    Map<String, int>? filterFocusOffsets;
    final rawOffsets = payload['filterFocusOffsets'];
    if (rawOffsets != null) {
      if (rawOffsets is! Map) {
        throw BadRequestError(
          field: 'filterFocusOffsets',
          expected: 'object',
        );
      }
      filterFocusOffsets = <String, int>{};
      rawOffsets.forEach((key, value) {
        if (value is! num) {
          throw BadRequestError(
            field: 'filterFocusOffsets.$key',
            expected: 'integer',
          );
        }
        filterFocusOffsets![key.toString()] = value.toInt();
      });
    }

    final backend = container.read(backendProvider);
    await backend.sequencerSetDevices(
      cameraId: optionalString(payload, 'cameraId'),
      mountId: optionalString(payload, 'mountId'),
      focuserId: optionalString(payload, 'focuserId'),
      filterwheelId: optionalString(payload, 'filterwheelId'),
      rotatorId: optionalString(payload, 'rotatorId'),
      filterNames: optionalList<String>(payload, 'filterNames'),
      filterFocusOffsets: filterFocusOffsets,
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetSafetyFailMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/safety-fail-mode');
    final payload = await readJsonObject(request);
    final mode = requireString(payload, 'mode');

    final backend = container.read(backendProvider);
    await backend.sequencerSetSafetyFailMode(mode);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetSavePath(Request request) async {
    _logInfo('[API] POST /api/sequencer/save-path');
    final payload = await readJsonObject(request);
    final backend = container.read(backendProvider);
    await backend.sequencerSetSavePath(optionalString(payload, 'path'));
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateDitherConfig(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-dither-config');
    final payload = await readJsonObject(request);
    final backend = container.read(backendProvider);
    await backend.sequencerUpdateDitherConfig(
      pixels: requireDouble(payload, 'pixels'),
      settlePixels: requireDouble(payload, 'settlePixels'),
      settleTime: requireDouble(payload, 'settleTime'),
      settleTimeout: requireDouble(payload, 'settleTimeout'),
      raOnly: optionalBool(payload, 'raOnly') ?? false,
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateLocation(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-location');
    final payload = await readJsonObject(request);
    final backend = container.read(backendProvider);
    await backend.sequencerUpdateLocation(
      latitude: requireDouble(payload, 'latitude'),
      longitude: requireDouble(payload, 'longitude'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateFilterOffsets(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-filter-offsets');
    final payload = await readJsonObject(request);
    final rawOffsets = payload['offsets'];
    // Why: same as set-devices — Dart's Map<String,int> can't be expressed
    // through requireList; we validate per-entry to give callers a precise
    // error path rather than a generic ClassCastException.
    final offsets = <String, int>{};
    if (rawOffsets != null) {
      if (rawOffsets is! Map) {
        throw BadRequestError(field: 'offsets', expected: 'object');
      }
      rawOffsets.forEach((key, value) {
        if (value is! num) {
          throw BadRequestError(
            field: 'offsets.$key',
            expected: 'integer',
          );
        }
        offsets[key.toString()] = value.toInt();
      });
    }

    final backend = container.read(backendProvider);
    await backend.sequencerUpdateFilterOffsets(offsets);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetCheckpointDir(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/dir');
    final payload = await readJsonObject(request);
    final path = requireString(payload, 'path');

    final backend = container.read(backendProvider);
    await backend.sequencerSetCheckpointDir(path);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerHasCheckpoint(Request request) async {
    final backend = container.read(backendProvider);
    final hasCheckpoint = await backend.hasCheckpoint();
    return jsonOk({'hasCheckpoint': hasCheckpoint});
  }

  Future<Response> handleSequencerGetCheckpointInfo(Request request) async {
    final backend = container.read(backendProvider);
    final info = await backend.getCheckpointInfo();
    return jsonOk({'info': info?.toJson()});
  }

  Future<Response> handleSequencerResumeFromCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/resume');
    final backend = container.read(backendProvider);
    await backend.resumeFromCheckpoint();
    return jsonOk({'status': 'resumed'});
  }

  Future<Response> handleSequencerDiscardCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/discard');
    final backend = container.read(backendProvider);
    await backend.discardCheckpoint();
    return jsonOk({'status': 'discarded'});
  }

  Future<Response> handleSequencerSaveCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/save');
    final backend = container.read(backendProvider);
    await backend.saveCheckpoint();
    return jsonOk({'status': 'saved'});
  }
}
