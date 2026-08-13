part of '../bridge_stub.dart';

extension _NativeBridgeGuidingOperations on _NativeBridgeImplementation {
  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  /// Check if PHD2 is running
  Future<bool> isPhd2Running({
    String host = 'localhost',
    int port = 4400,
  }) async {
    return phd2.checkPhd2Running(host: host, port: port);
  }

  /// Connect to PHD2 (auto-launches if not running on Windows)
  Future<void> phd2Connect({String? host, int? port}) async {
    final targetHost = host ?? 'localhost';
    final targetPort = port ?? 4400;

    // Guider commands (loop, guide, find star, etc.) use the Rust PHD2 client
    // when the native bridge is loaded. Connect must use the same backend or
    // Dart will show "connected" while Rust returns NotConnected(PHD2).
    if (_nativeAvailable) {
      _phd2Client?.dispose();
      _phd2Client = null;
      await gen_api.apiPhd2Connect(host: targetHost, port: targetPort);
      return;
    }

    // Check if PHD2 is already running
    bool phd2Running = await phd2.checkPhd2Running(
      host: targetHost,
      port: targetPort,
    );

    // If PHD2 is not running and we're on localhost, try to launch it
    if (!phd2Running &&
        (targetHost == 'localhost' || targetHost == '127.0.0.1')) {
      developer.log(
        '[PHD2] not running on localhost. Platform.isWindows: ${Platform.isWindows}',
        name: 'NativeBridge',
        level: 800,
      );
      if (Platform.isWindows) {
        developer.log(
          '[PHD2] not running, attempting to launch...',
          name: 'NativeBridge',
          level: 800,
        );
        try {
          // Common PHD2 installation paths on Windows
          final phd2Paths = [
            r'C:\Program Files (x86)\PHDGuiding2\phd2.exe',
            r'C:\Program Files\PHDGuiding2\phd2.exe',
            r'C:\Program Files (x86)\PHD2\phd2.exe',
            r'C:\Program Files\PHD2\phd2.exe',
          ];

          String? phd2Path;
          for (final path in phd2Paths) {
            if (await File(path).exists()) {
              phd2Path = path;
              break;
            }
          }

          if (phd2Path != null) {
            await Process.start(phd2Path, [], mode: ProcessStartMode.detached);
            developer.log(
              '[PHD2] launched from: $phd2Path',
              name: 'NativeBridge',
              level: 800,
            );

            // Wait for PHD2 to start and open its server
            for (int i = 0; i < 30; i++) {
              await Future<void>.delayed(const Duration(seconds: 1));
              if (await phd2.checkPhd2Running(
                host: targetHost,
                port: targetPort,
              )) {
                phd2Running = true;
                developer.log(
                  '[PHD2] is now running',
                  name: 'NativeBridge',
                  level: 800,
                );
                break;
              }
            }

            if (!phd2Running) {
              throw Exception(
                'PHD2 was launched but did not start its server within 30 seconds',
              );
            }
          } else {
            throw Exception(
              'PHD2 not found. Please install PHD2 from https://openphdguiding.org/',
            );
          }
        } catch (e) {
          developer.log(
            '[PHD2] Failed to launch: $e',
            name: 'NativeBridge',
            level: 1000,
          );
          throw Exception('Could not launch PHD2: $e');
        }
      } else {
        developer.log(
          '[PHD2] Not on Windows, cannot auto-launch PHD2. Platform: ${Platform.operatingSystem}',
          name: 'NativeBridge',
          level: 900,
        );
        throw Exception(
          'PHD2 is not running. Platform: ${Platform.operatingSystem}. Please start PHD2 manually.',
        );
      }
    }

    // Now connect to PHD2
    _phd2Client?.dispose();
    _phd2Client = phd2.Phd2Client(host: targetHost, port: targetPort);

    await _phd2Client!.connect();

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'PHD2Connected',
        data: {'host': targetHost, 'port': targetPort},
      ),
    );
  }

  /// Disconnect from PHD2
  Future<void> phd2Disconnect() async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2Disconnect();
      _phd2Client?.dispose();
      _phd2Client = null;
      return;
    }

    unawaited(_phd2Client?.disconnect() ?? Future<void>.value());
    _phd2Client = null;

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'PHD2Disconnected',
        data: {},
      ),
    );
  }

  /// Start guiding
  Future<void> phd2StartGuiding({
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2StartGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected. Connect to PHD2 first.');
    }

    await _phd2Client!.startGuiding(
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'GuidingStarted',
        data: {},
      ),
    );
  }

  /// Stop guiding
  Future<void> phd2StopGuiding() async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2StopGuiding();
      return;
    }
    if (_phd2Client != null && _phd2Client!.isConnected) {
      await _phd2Client!.stopGuiding();
    }

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'GuidingStopped',
        data: {},
      ),
    );
  }

  /// Dither
  Future<void> phd2Dither({
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2Dither(
        amount: amount,
        raOnly: raOnly ? 1 : 0,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected. Connect to PHD2 first.');
    }

    await _phd2Client!.dither(
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'DitherStarted',
        data: {'amount': amount, 'raOnly': raOnly},
      ),
    );
  }

  /// Get PHD2 status
  Future<Phd2Status> phd2GetStatus() async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetStatus();
    }
    if (_phd2Client == null) {
      return const Phd2Status(
        connected: false,
        state: 'Disconnected',
        rmsRa: 0,
        rmsDec: 0,
        rmsTotal: 0,
        snr: 0,
        starMass: 0,
        pixelScale: 0,
      );
    }

    return Phd2Status(
      connected: _phd2Client!.isConnected,
      state: _phd2Client!.state.name,
      rmsRa: _phd2Client!.rmsRa,
      rmsDec: _phd2Client!.rmsDec,
      rmsTotal: _phd2Client!.rmsTotal,
      snr: _phd2Client!.snr,
      starMass: _phd2Client!.starMass,
      pixelScale: 0, // Would need to call getPixelScale() separately
    );
  }

  Future<void> guiderStartGuiding({
    required String deviceId,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderStartGuiding(
        deviceId: normalizedDeviceId,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2StartGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    _nativeBridgeRequired('guiderStartGuiding');
  }

  Future<void> guiderStop({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderStop(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2StopGuiding();
      return;
    }
    _nativeBridgeRequired('guiderStop');
  }

  Future<void> guiderDither({
    required String deviceId,
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderDither(
        deviceId: normalizedDeviceId,
        amount: amount,
        raOnly: raOnly ? 1 : 0,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2Dither(
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    _nativeBridgeRequired('guiderDither');
  }

  Future<void> guiderLoop({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderLoop(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2Loop();
      return;
    }
    _nativeBridgeRequired('guiderLoop');
  }

  Future<(double, double)> guiderFindStar({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderFindStar(deviceId: normalizedDeviceId);
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2FindStar();
    }
    _nativeBridgeRequired('guiderFindStar');
  }

  Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderSetLockPosition(
        deviceId: normalizedDeviceId,
        x: x,
        y: y,
        exact: exact,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2SetLockPosition(x: x, y: y, exact: exact);
      return;
    }
    _nativeBridgeRequired('guiderSetLockPosition');
  }

  Future<(double, double)> guiderGetLockPosition({
    required String deviceId,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderGetLockPosition(deviceId: normalizedDeviceId);
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2GetLockPosition();
    }
    _nativeBridgeRequired('guiderGetLockPosition');
  }

  Future<void> guiderDeselectStar({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderDeselectStar(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2DeselectStar();
      return;
    }
    _nativeBridgeRequired('guiderDeselectStar');
  }

  Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderGetStarImage(
        deviceId: normalizedDeviceId,
        size: size,
      );
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2GetStarImage(size: size);
    }
    _nativeBridgeRequired('guiderGetStarImage');
  }

  // =========================================================================
  // Built-in Guider Configuration
  // =========================================================================

  /// Get the built-in guider configuration.
  /// Returns a map with keys matching GuiderConfig fields.
  Future<Map<String, dynamic>> builtinGuiderGetConfigRaw() async {
    if (_nativeAvailable) {
      final config = await gen_api.apiBuiltinGuiderGetConfig();
      return {
        'exposureSecs': config.exposureSecs,
        'gain': config.gain,
        'offset': config.offset,
        'binning': config.binning,
        'calibrationMs': config.calibrationMs,
        'settleSleepMs': config.settleSleepMs.toInt(),
        'minPulseMs': config.minPulseMs,
        'maxPulseMs': config.maxPulseMs,
      };
    }
    _nativeBridgeRequired('builtinGuiderGetConfig');
  }

  /// Per-star tracked-star list for the built-in multi-star guider, as a JSON
  /// string (`{"count":N,"stars":[...]}`).
  ///
  /// Bridges the native `api_builtin_guider_get_tracked_stars_json` so the host
  /// FFI backend can populate `Phd2Status.trackedStars` (the per-star guider UI
  /// list). Returns `{"count":0,"stars":[]}` when the built-in guider is not the
  /// active guider or is not tracking, so it is always safe to call on the
  /// status path. Off-native (no bridge) the built-in guider cannot run, so the
  /// empty snapshot is returned.
  Future<String> builtinGuiderGetTrackedStarsJson() async {
    if (_nativeAvailable) {
      return gen_api.apiBuiltinGuiderGetTrackedStarsJson();
    }
    return '{"count":0,"stars":[]}';
  }

  /// Set the built-in guider configuration.
  Future<void> builtinGuiderSetConfigRaw({
    required double exposureSecs,
    required int gain,
    required int offset,
    required int binning,
    required int calibrationMs,
    required int settleSleepMs,
    required double minPulseMs,
    required double maxPulseMs,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiBuiltinGuiderSetConfig(
        exposureSecs: exposureSecs,
        gain: gain,
        offset: offset,
        binning: binning,
        calibrationMs: calibrationMs,
        settleSleepMs: BigInt.from(settleSleepMs),
        minPulseMs: minPulseMs,
        maxPulseMs: maxPulseMs,
      );
      return;
    }
    _nativeBridgeRequired('builtinGuiderSetConfig');
  }

  /// Auto-select guide star in PHD2.
  ///
  /// The native PHD2 client exposes no auto-select entry point, so this runs on
  /// the Dart client in both modes.
  Future<void> phd2AutoSelectStar() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.autoSelectStar();
  }

  /// Start looping exposures in PHD2
  Future<void> phd2Loop() async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2Loop();
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.loop();
  }

  /// Get PHD2 star image
  Future<Phd2StarImage> phd2GetStarImage({int size = 50}) async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetStarImage(size: size);
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }

    final result = await _phd2Client!.getStarImage(size: size);

    // PHD2 get_star_image returns:
    //   frame: scalar frame number
    //   width, height: top-level integers
    //   star_pos: [x, y] array (if star is selected)
    //   pixels: base64-encoded pixel data
    //
    // Why: route every field through safelyCast* so a malformed PHD2 reply
    // surfaces a structured CastFailureException with the offending field
    // name instead of a bare TypeError.
    const ctx = 'phd2GetStarImage.result';
    final frame = safelyCastIntOpt(result, 'frame', contextPrefix: ctx) ?? 0;
    final width = safelyCastIntOpt(result, 'width', contextPrefix: ctx) ?? size;
    final height =
        safelyCastIntOpt(result, 'height', contextPrefix: ctx) ?? size;

    // star_pos is a positional array [x, y], not a named map
    final starPos = safelyCastOpt<List<Object?>>(
      result['star_pos'],
      context: '$ctx["star_pos"]',
    );
    final starX = (starPos != null && starPos.isNotEmpty)
        ? safelyCast<num>(starPos[0], context: '$ctx["star_pos"][0]').toDouble()
        : width / 2.0;
    final starY = (starPos != null && starPos.length >= 2)
        ? safelyCast<num>(starPos[1], context: '$ctx["star_pos"][1]').toDouble()
        : height / 2.0;

    // Decode base64 pixel data
    final pixelsB64 = safelyCastOpt<String>(
      result['pixels'],
      context: '$ctx["pixels"]',
    );
    if (pixelsB64 == null) {
      throw Exception('No pixel data in PHD2 star image response');
    }
    final pixels = base64Decode(pixelsB64);

    return Phd2StarImage(
      frame: frame,
      width: width,
      height: height,
      starX: starX,
      starY: starY,
      pixels: pixels,
    );
  }

  /// Get PHD2 algorithm parameter names
  Future<List<String>> phd2GetAlgoParamNames({required String axis}) async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetAlgoParamNames(axis: axis);
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getAlgoParamNames(axis: axis);
  }

  /// Get PHD2 algorithm parameter value
  Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetAlgoParam(axis: axis, name: name);
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getAlgoParam(axis: axis, name: name);
  }

  /// Set PHD2 algorithm parameter
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2SetAlgoParam(axis: axis, name: name, value: value);
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.setAlgoParam(axis: axis, name: name, value: value);
  }

  /// Set PHD2 paused state
  Future<void> phd2SetPaused({required bool paused}) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2SetPaused(paused: paused);
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    if (paused) {
      await _phd2Client!.pauseGuiding();
    } else {
      await _phd2Client!.resumeGuiding();
    }
  }

  /// Clear PHD2 calibration
  Future<void> phd2ClearCalibration({String which = 'both'}) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2ClearCalibration(which: which);
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.clearCalibration(which: which);
  }

  /// Flip PHD2 calibration (for meridian flip)
  Future<void> phd2FlipCalibration() async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2FlipCalibration();
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.flipCalibration();
  }

  /// Get PHD2 calibration data
  Future<gen_api.Phd2CalibrationData> phd2GetCalibrationData() async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetCalibrationData();
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }

    // Query PHD2 for calibration data
    final result = await _phd2Client!.getCalibrationData();

    // PHD2 returns null if not calibrated
    if (result == null) {
      return const gen_api.Phd2CalibrationData(
        isCalibrated: false,
        raAngle: null,
        decAngle: null,
        raRate: null,
        decRate: null,
      );
    }

    // Extract calibration parameters from PHD2's response.
    // PHD2 returns xAngle/yAngle for RA/Dec rotation angles and xRate/yRate
    // for guide rates in pixels/second.
    //
    // Why: any of these can be absent (older PHD2 builds) or wrong-typed
    // (PHD2 plugin shims) — surface the offending field name via
    // CastFailureException rather than a bare TypeError.
    const ctx = 'phd2GetCalibrationData.result';
    final xAngle = safelyCastDoubleOpt(result, 'xAngle', contextPrefix: ctx);
    final yAngle = safelyCastDoubleOpt(result, 'yAngle', contextPrefix: ctx);
    final xRate = safelyCastDoubleOpt(result, 'xRate', contextPrefix: ctx);
    final yRate = safelyCastDoubleOpt(result, 'yRate', contextPrefix: ctx);

    return gen_api.Phd2CalibrationData(
      isCalibrated: true,
      raAngle: xAngle,
      decAngle: yAngle,
      raRate: xRate,
      decRate: yRate,
    );
  }

  /// Find a guide star in PHD2
  Future<(double, double)> phd2FindStar() async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2FindStar();
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.findStar();
  }

  /// Set PHD2 lock position
  Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2SetLockPosition(x: x, y: y, exact: exact);
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.setLockPosition(x: x, y: y, exact: exact);
  }

  /// Get PHD2 lock position
  Future<(double, double)> phd2GetLockPosition() async {
    if (_nativeAvailable) {
      return gen_api.apiPhd2GetLockPosition();
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getLockPosition();
  }

  /// Deselect star in PHD2
  Future<void> phd2DeselectStar() async {
    if (_nativeAvailable) {
      await gen_api.apiPhd2DeselectStar();
      return;
    }
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.deselectStar();
  }
}
