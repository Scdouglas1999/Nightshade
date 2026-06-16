import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Headless control surface for live stacking (real-time EAA integration).
///
/// The live-stacking engine runs on the HOST (the appliance that captures the
/// frames) — pixel data never crosses the wire on the way *in*. A remote tablet
/// drives it through these endpoints: configure + start, then poll the stacked
/// preview/stats; the host auto-feeds each newly-saved frame into the stacker.
///
/// Why a host-side coordinator rather than client-driven add-frame: the primary
/// couch scenario is "watch my running sequence stack live". Sequencer captures
/// happen on the host with no client in the loop, so the host must feed the
/// stacker itself ([onImageSaved], wired to the `ImageSaved` event stream in
/// the server lifecycle). This also means stacking keeps accumulating even if
/// the tablet disconnects.
class StackingHandlers {
  final ProviderContainer container;

  StackingHandlers(this.container);

  LiveStackingService get _service =>
      container.read(liveStackingServiceProvider);
  LoggingService get _logger => container.read(loggingServiceProvider);

  // --- Coordinator state -----------------------------------------------------

  /// True once the client has started stacking and the host should feed frames.
  bool _armed = false;

  /// True once a reference frame has been established (the first fed frame in
  /// arm-mode, or the explicit reference path passed to [handleStart]).
  bool _started = false;

  LiveStackingConfig _config = const LiveStackingConfig();

  /// Serializes all stacker mutations (start/add/reset/stop) so an auto-fed
  /// frame can't race a client-initiated op or another frame. The Rust stacker
  /// is single-threaded; overlapping calls would interleave alignment state.
  Future<void> _chain = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final completer = _chain.then((_) => op());
    // Keep the chain alive even if this op throws, but don't swallow the
    // result the caller awaits.
    _chain = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  // --- Host auto-feed hook ----------------------------------------------------

  /// Called by the server's `ImageSaved` event subscription for every frame the
  /// host writes to disk. No-op unless stacking is armed.
  Future<void> onImageSaved(String filePath) async {
    if (!_armed || filePath.isEmpty) return;
    await _enqueue(() async {
      try {
        if (!_started) {
          await _service.startFromFile(
            referenceImagePath: filePath,
            config: _config,
          );
          _started = true;
          _logger.info(
            '[stacking] reference frame established from $filePath',
            source: 'StackingHandlers',
          );
        } else {
          await _service.addFrameFromFile(filePath);
        }
      } catch (e) {
        // A single rejected frame (alignment failure, unreadable file) must not
        // tear down the stack — log and keep going.
        _logger.warning(
          '[stacking] auto-feed of $filePath failed: $e',
          source: 'StackingHandlers',
        );
      }
    });
  }

  // --- Endpoints --------------------------------------------------------------

  /// POST /api/stacking/start
  /// Body: `{ config?: {...}, referencePath?: "host-path" }`
  /// With a referencePath the stack starts immediately from that host frame.
  /// Without one, stacking is "armed": the next saved frame becomes the
  /// reference and subsequent frames are added automatically.
  Future<Response> handleStart(Request request) async {
    // Arming with defaults needs no body, so tolerate an empty/absent one
    // rather than forcing clients to POST a bare `{}`.
    final payload = await _readJsonObjectOrEmpty(request);
    _config = _configFromJson(optionalObject(payload, 'config')) ?? _config;
    final referencePath = optionalString(payload, 'referencePath');

    return _enqueue(() async {
      // Always reset first so a re-start doesn't accumulate onto a stale stack.
      try {
        await _service.reset();
      } catch (e, stackTrace) {
        throw HandlerFailure(
          code: 'stacking_reset_failed',
          message: 'Live stacking could not be reset before starting.',
          statusCode: 500,
          cause: e,
          stackTrace: stackTrace,
        );
      }
      _armed = true;
      if (referencePath != null && referencePath.isNotEmpty) {
        final stats = await _service.startFromFile(
          referenceImagePath: referencePath,
          config: _config,
        );
        _started = true;
        return jsonOk({'status': 'started', 'stats': _statsToJson(stats)});
      }
      _started = false;
      return jsonOk({
        'status': 'armed',
        'message':
            'Stacking armed; the next captured frame becomes the reference.',
      });
    });
  }

  /// POST /api/stacking/add-frame  Body: `{ imagePath: "host-path" }`
  /// Explicit client-driven add (host paths only — full-frame pixel upload is
  /// not supported remotely, matching the imaging-stats policy).
  Future<Response> handleAddFrame(Request request) async {
    final payload = await readJsonObject(request);
    final imagePath = requireString(payload, 'imagePath');
    return _enqueue(() async {
      if (!_started) {
        final stats = await _service.startFromFile(
          referenceImagePath: imagePath,
          config: _config,
        );
        _armed = true;
        _started = true;
        return jsonOk({'status': 'started', 'stats': _statsToJson(stats)});
      }
      final result = await _service.addFrameFromFile(imagePath);
      return jsonOk({
        'status': 'added',
        'width': result.width,
        'height': result.height,
        'channels': result.channels,
        'stats': _statsToJson(result.stats),
      });
    });
  }

  /// GET /api/stacking/status -> liveness + counters (cheap, no pixels).
  Future<Response> handleStatus(Request request) async {
    return jsonOk({
      'active': _service.isActive,
      'frameCount': _service.frameCount,
      'armed': _armed,
      'started': _started,
    });
  }

  /// GET /api/stacking/stats -> current accumulation stats.
  ///
  /// Before the first frame the native stacker isn't initialized, so querying
  /// it throws "not initialized". Armed-but-not-started simply has nothing
  /// accumulated yet — report zeroed stats rather than a 500.
  Future<Response> handleStats(Request request) async {
    if (!_started && !_service.isActive) {
      return jsonOk({'stats': _statsToJson(const LiveStackingStats())});
    }
    final stats = await _service.getStats();
    return jsonOk({'stats': _statsToJson(stats)});
  }

  /// GET /api/stacking/result -> dimensions + stats (the JSON header the client
  /// pairs with /api/stacking/preview to assemble a LiveStackingResult).
  Future<Response> handleResult(Request request) async {
    if (!_service.isActive) {
      return jsonNotFound({
        'error': 'no_active_stack',
        'message': 'Live stacking is not running.',
      });
    }
    final result = await _service.getCurrentResult();
    return jsonOk({
      'active': true,
      'width': result.width,
      'height': result.height,
      'channels': result.channels,
      'stats': _statsToJson(result.stats),
    });
  }

  /// GET /api/stacking/preview -> raw little-endian u16 pixel buffer
  /// (width*height*channels samples). Dimensions/channels are echoed in
  /// response headers so the client can decode without a second round-trip.
  Future<Response> handlePreview(Request request) async {
    if (!_service.isActive) {
      return jsonNotFound({
        'error': 'no_active_stack',
        'message': 'Live stacking is not running.',
      });
    }
    final result = await _service.getCurrentResult();
    final samples = Uint16List.fromList(result.data);
    final bytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    return contentResponse(
      bytes,
      contentType: 'application/octet-stream',
      contentLength: bytes.length,
      headers: {
        'x-stack-width': result.width.toString(),
        'x-stack-height': result.height.toString(),
        'x-stack-channels': result.channels.toString(),
        'x-stack-endian': 'little',
      },
    );
  }

  /// POST /api/stacking/config  Body: { config: {...} }
  /// Updates the config used for the next start. (The Rust stacker fixes its
  /// alignment parameters at start; changing mid-stack would invalidate the
  /// running integration, so this takes effect on the next start/restart.)
  Future<Response> handleUpdateConfig(Request request) async {
    final payload = await readJsonObject(request);
    final parsed = _configFromJson(optionalObject(payload, 'config'));
    if (parsed == null) {
      throw BadRequestError(
        field: 'config',
        expected: 'object',
        message: "Body must include a 'config' object",
      );
    }
    _config = parsed;
    return jsonOk({'status': 'ok', 'appliesOn': 'next-start'});
  }

  /// POST /api/stacking/reset -> clear accumulation, keep armed.
  ///
  /// Like [handleStop], tolerates the armed-but-never-started case: with no
  /// reference frame yet the native stacker isn't initialized, so resetting the
  /// engine would throw "not initialized". There's nothing accumulated to
  /// clear, so we just drop back to the armed-waiting-for-reference state.
  Future<Response> handleReset(Request request) async {
    return _enqueue(() async {
      try {
        if (_started || _service.isActive) {
          await _service.reset();
        }
      } catch (e) {
        _logger.warning(
          '[stacking] reset on an uninitialized stacker ignored: $e',
          source: 'StackingHandlers',
        );
      } finally {
        _started = false;
      }
      return jsonOk({'status': 'reset'});
    });
  }

  /// POST /api/stacking/stop -> stop the stacker and disarm auto-feed.
  ///
  /// Tolerates the armed-but-never-started case: if no reference frame has
  /// landed yet the native stacker was never initialized, so calling stop on it
  /// throws "not initialized". That's not an error from the caller's view — they
  /// just want stacking off — so we only stop the engine when it actually
  /// started, and always clear the coordinator's armed/started state.
  Future<Response> handleStop(Request request) async {
    return _enqueue(() async {
      try {
        if (_started || _service.isActive) {
          await _service.stop();
        }
      } catch (e) {
        _logger.warning(
          '[stacking] stop on an uninitialized stacker ignored: $e',
          source: 'StackingHandlers',
        );
      } finally {
        _armed = false;
        _started = false;
      }
      return jsonOk({'status': 'stopped'});
    });
  }

  // --- (de)serialization ------------------------------------------------------

  /// Like [readJsonObject] but returns an empty map when the request carries no
  /// body, so endpoints whose every field is optional don't reject a bodyless
  /// POST.
  Future<Map<String, dynamic>> _readJsonObjectOrEmpty(Request request) async {
    try {
      return await readJsonObject(request);
    } on BadRequestError {
      return <String, dynamic>{};
    }
  }

  LiveStackingConfig? _configFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    const def = LiveStackingConfig();
    return LiveStackingConfig(
      sigmaClipEnabled:
          json['sigmaClipEnabled'] as bool? ?? def.sigmaClipEnabled,
      sigmaClipThreshold:
          (json['sigmaClipThreshold'] as num?)?.toDouble() ??
          def.sigmaClipThreshold,
      maxMatchStars:
          (json['maxMatchStars'] as num?)?.toInt() ?? def.maxMatchStars,
      matchRadiusPx:
          (json['matchRadiusPx'] as num?)?.toDouble() ?? def.matchRadiusPx,
      matchFluxTolerance:
          (json['matchFluxTolerance'] as num?)?.toDouble() ??
          def.matchFluxTolerance,
      minMatchedPairs:
          (json['minMatchedPairs'] as num?)?.toInt() ?? def.minMatchedPairs,
      sensorMode: json['sensorMode'] as String? ?? def.sensorMode,
      bayerPattern: json['bayerPattern'] as String? ?? def.bayerPattern,
      demosaicQuality:
          json['demosaicQuality'] as String? ?? def.demosaicQuality,
    );
  }

  Map<String, Object?> _statsToJson(LiveStackingStats s) => {
    'stackedFrameCount': s.stackedFrameCount,
    'totalFramesAttempted': s.totalFramesAttempted,
    'rejectedAlignmentFailures': s.rejectedAlignmentFailures,
    'avgMatchedPairs': s.avgMatchedPairs,
    'avgAlignmentResidual': s.avgAlignmentResidual,
    'totalSigmaRejectedPixels': s.totalSigmaRejectedPixels,
  };
}
