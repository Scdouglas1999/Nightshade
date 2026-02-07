import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

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

      return Response.ok(
        jsonEncode({
          "state": status.state,
          "currentNodeId": status.currentNodeId,
          "currentNodeName": status.currentNodeName,
          "progress": status.progress,
          "message": status.message
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/start');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerStart();
      return Response.ok(
        jsonEncode({"status": "started"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerStop(Request request) async {
    _logInfo('[API] POST /api/sequencer/stop');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerStop();
      return Response.ok(
        jsonEncode({"status": "stopped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerPause(Request request) async {
    _logInfo('[API] POST /api/sequencer/pause');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerPause();
      return Response.ok(
        jsonEncode({"status": "paused"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerResume(Request request) async {
    _logInfo('[API] POST /api/sequencer/resume');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerResume();
      return Response.ok(
        jsonEncode({"status": "resumed"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerSkip(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerSkip();
      return Response.ok(
        jsonEncode({"status": "skipped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerReset(Request request) async {
    _logInfo('[API] POST /api/sequencer/reset');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerReset();
      return Response.ok(
        jsonEncode({"status": "reset"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    try {
      final payload = jsonDecode(await request.readAsString());
      final json = payload['json'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerLoadJson(json);
      return Response.ok(
        jsonEncode({"status": "loaded"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerSetSimulationMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/simulation');
    try {
      final payload = jsonDecode(await request.readAsString());
      final enabled = payload['enabled'] as bool;

      final backend = container.read(backendProvider);
      await backend.sequencerSetSimulationMode(enabled);
      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
      );
      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerSetSafetyFailMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/safety-fail-mode');
    try {
      final payload = jsonDecode(await request.readAsString());
      final mode = payload['mode'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerSetSafetyFailMode(mode);
      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerSetCheckpointDir(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/dir');
    try {
      final payload = jsonDecode(await request.readAsString());
      final path = payload['path'] as String;

      final backend = container.read(backendProvider);
      await backend.sequencerSetCheckpointDir(path);
      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerHasCheckpoint(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final hasCheckpoint = await backend.hasCheckpoint();
      return Response.ok(
        jsonEncode({"hasCheckpoint": hasCheckpoint}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerGetCheckpointInfo(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final info = await backend.getCheckpointInfo();
      return Response.ok(
        jsonEncode({"info": info?.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerResumeFromCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/resume');
    try {
      final backend = container.read(backendProvider);
      await backend.resumeFromCheckpoint();
      return Response.ok(
        jsonEncode({"status": "resumed"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerDiscardCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/discard');
    try {
      final backend = container.read(backendProvider);
      await backend.discardCheckpoint();
      return Response.ok(
        jsonEncode({"status": "discarded"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSequencerSaveCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/save');
    try {
      final backend = container.read(backendProvider);
      await backend.saveCheckpoint();
      return Response.ok(
        jsonEncode({"status": "saved"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
