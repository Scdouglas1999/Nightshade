import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for sequencer control endpoints
class SequencerHandlers {
  final ProviderContainer container;
  SequencerHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequencerHandlers');

  Future<Response> handleSequencerStatus(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final status = await backend.sequencerGetStatus();

      return jsonOk({
        "state": status.state,
        "currentNodeId": status.currentNodeId,
        "currentNodeName": status.currentNodeName,
        "progress": status.progress,
        "message": status.message
      });
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/start');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerStart();
      return jsonOk({"status": "started"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerStop(Request request) async {
    _logInfo('[API] POST /api/sequencer/stop');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerStop();
      return jsonOk({"status": "stopped"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerPause(Request request) async {
    _logInfo('[API] POST /api/sequencer/pause');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerPause();
      return jsonOk({"status": "paused"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerResume(Request request) async {
    _logInfo('[API] POST /api/sequencer/resume');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerResume();
      return jsonOk({"status": "resumed"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSkip(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerSkip();
      return jsonOk({"status": "skipped"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerReset(Request request) async {
    _logInfo('[API] POST /api/sequencer/reset');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerReset();
      return jsonOk({"status": "reset"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    try {
      final payload = jsonDecode(await request.readAsString());
      final json = payload['json'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerLoadJson(json);
      return jsonOk({"status": "loaded"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSetSimulationMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/simulation');
    try {
      final payload = jsonDecode(await request.readAsString());
      final enabled = payload['enabled'] as bool;

      final backend = container.read(backendProvider);
      await backend.sequencerSetSimulationMode(enabled);
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSetDevices(Request request) async {
    _logInfo('[API] POST /api/sequencer/devices');
    try {
      final payload = jsonDecode(await request.readAsString());

      final backend = container.read(backendProvider);
      await backend.sequencerSetDevices(
        cameraId: payload['cameraId'] as String?,
        mountId: payload['mountId'] as String?,
        focuserId: payload['focuserId'] as String?,
        filterwheelId: payload['filterwheelId'] as String?,
        rotatorId: payload['rotatorId'] as String?,
        filterNames: (payload['filterNames'] as List?)?.cast<String>(),
        filterFocusOffsets: (payload['filterFocusOffsets'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ),
      );
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSetSafetyFailMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/safety-fail-mode');
    try {
      final payload = jsonDecode(await request.readAsString());
      final mode = payload['mode'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerSetSafetyFailMode(mode);
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSetSavePath(Request request) async {
    _logInfo('[API] POST /api/sequencer/save-path');
    try {
      final payload = jsonDecode(await request.readAsString());
      final backend = container.read(backendProvider);
      await backend.sequencerSetSavePath(payload['path'] as String?);
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerUpdateDitherConfig(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-dither-config');
    try {
      final payload = jsonDecode(await request.readAsString());
      final backend = container.read(backendProvider);
      await backend.sequencerUpdateDitherConfig(
        pixels: (payload['pixels'] as num).toDouble(),
        settlePixels: (payload['settlePixels'] as num).toDouble(),
        settleTime: (payload['settleTime'] as num).toDouble(),
        settleTimeout: (payload['settleTimeout'] as num).toDouble(),
        raOnly: payload['raOnly'] as bool? ?? false,
      );
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerUpdateLocation(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-location');
    try {
      final payload = jsonDecode(await request.readAsString());
      final backend = container.read(backendProvider);
      await backend.sequencerUpdateLocation(
        latitude: (payload['latitude'] as num).toDouble(),
        longitude: (payload['longitude'] as num).toDouble(),
      );
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerUpdateFilterOffsets(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-filter-offsets');
    try {
      final payload = jsonDecode(await request.readAsString());
      final rawOffsets = payload['offsets'] as Map? ?? const {};
      final offsets = rawOffsets.map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      );

      final backend = container.read(backendProvider);
      await backend.sequencerUpdateFilterOffsets(offsets);
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSetCheckpointDir(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/dir');
    try {
      final payload = jsonDecode(await request.readAsString());
      final path = payload['path'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerSetCheckpointDir(path);
      return jsonOk({"status": "ok"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerHasCheckpoint(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final hasCheckpoint = await backend.hasCheckpoint();
      return jsonOk({"hasCheckpoint": hasCheckpoint});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerGetCheckpointInfo(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final info = await backend.getCheckpointInfo();
      return jsonOk({"info": info?.toJson()});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerResumeFromCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/resume');
    try {
      final backend = container.read(backendProvider);
      await backend.resumeFromCheckpoint();
      return jsonOk({"status": "resumed"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerDiscardCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/discard');
    try {
      final backend = container.read(backendProvider);
      await backend.discardCheckpoint();
      return jsonOk({"status": "discarded"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSequencerSaveCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/save');
    try {
      final backend = container.read(backendProvider);
      await backend.saveCheckpoint();
      return jsonOk({"status": "saved"});
    } catch (e) {
      return jsonInternalServerError({"error": e.toString()});
    }
  }
}
