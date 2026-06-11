part of '../device_service.dart';

extension _DeviceServiceProfileConnections on DeviceService {
  /// Connect all devices from a profile sequentially with per-device timeout
  /// and early abort on failure.
  ///
  /// Imaging-chain devices (camera → mount → focuser → filter wheel) abort
  /// the remainder when any link fails because they often share USB hubs.
  /// Optional peripherals (dome, weather, etc.) still run after imaging
  /// failures when invoked through [connectAllFromProfile] instead.
  Future<void> _connectProfile({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
    String? rotatorId,
    String? domeId,
    String? weatherId,
    String? safetyMonitorId,
    String? switchId,
    String? coverCalibratorId,
    void Function(DeviceConnectProgress progress)? onProgress,
  }) {
    return _trackInFlight(() async {
      final entries = <(String, String, Future<void> Function(String))>[
        if (cameraId != null && cameraId.isNotEmpty)
          ('camera', cameraId, connectCamera),
        if (mountId != null && mountId.isNotEmpty)
          ('mount', mountId, connectMount),
        if (focuserId != null && focuserId.isNotEmpty)
          ('focuser', focuserId, connectFocuser),
        if (filterWheelId != null && filterWheelId.isNotEmpty)
          ('filter wheel', filterWheelId, connectFilterWheel),
        if (guiderId != null && guiderId.isNotEmpty)
          ('guider', guiderId, connectGuider),
        if (rotatorId != null && rotatorId.isNotEmpty)
          ('rotator', rotatorId, connectRotator),
        if (domeId != null && domeId.isNotEmpty) ('dome', domeId, connectDome),
        if (weatherId != null && weatherId.isNotEmpty)
          ('weather station', weatherId, connectWeather),
        if (safetyMonitorId != null && safetyMonitorId.isNotEmpty)
          ('safety monitor', safetyMonitorId, connectSafetyMonitor),
        if (switchId != null && switchId.isNotEmpty)
          ('switch', switchId, connectSwitch),
        if (coverCalibratorId != null && coverCalibratorId.isNotEmpty)
          ('cover calibrator', coverCalibratorId, connectCoverCalibrator),
      ];

      for (final (deviceType, id, connect) in entries) {
        onProgress?.call(
          DeviceConnectProgress(
            deviceType: deviceType,
            deviceId: id,
            status: DeviceConnectProgressStatus.connecting,
          ),
        );

        try {
          await connect(id).timeout(DeviceService._connectProfileDeviceTimeout);
          onProgress?.call(
            DeviceConnectProgress(
              deviceType: deviceType,
              deviceId: id,
              status: DeviceConnectProgressStatus.connected,
            ),
          );
        } catch (e) {
          onProgress?.call(
            DeviceConnectProgress(
              deviceType: deviceType,
              deviceId: id,
              status: DeviceConnectProgressStatus.failed,
              error: e,
              errorMessage: e.toString(),
            ),
          );
          throw Exception('Profile connect aborted at $deviceType: $e');
        }
      }
    });
  }

  /// Connect all devices from the active equipment profile
  Future<void> _connectActiveProfile() async {
    final profilesState = await _ref.read(equipmentProfilesProvider.future);
    final activeProfile = profilesState.activeProfile;

    if (activeProfile == null) {
      throw Exception('No active equipment profile selected');
    }

    await _connectProfile(
      cameraId: activeProfile.cameraId,
      mountId: activeProfile.mountId,
      focuserId: activeProfile.focuserId,
      filterWheelId: activeProfile.filterWheelId,
      guiderId: activeProfile.guiderId,
      rotatorId: activeProfile.rotatorId,
      domeId: activeProfile.domeId,
      weatherId: activeProfile.weatherId,
      safetyMonitorId: activeProfile.safetyMonitorId,
      switchId: activeProfile.switchId,
      coverCalibratorId: activeProfile.coverCalibratorId,
    );
  }

  /// Parallel "Connect All" with per-device progress.
  ///
  /// Returns a [Stream] of [DeviceConnectProgress] events that the caller
  /// (typically the equipment screen) can subscribe to so each device card
  /// can render its own live status: idle → connecting → connected/failed.
  ///
  /// Why this exists: the equipment screen's previous "Connect All" button
  /// iterated devices sequentially with `await`. Ten devices × 3-5 s each
  /// meant 30-50 s of wall-clock time with no feedback per device. A user
  /// staring at a single spinner has no idea whether the focuser is the
  /// one taking forever or whether the dome failed and the mount succeeded.
  ///
  /// Contract:
  ///
  /// * Every configured device-type from [profile] is connected in parallel
  ///   with `Future.wait`. Device connects do not interact with each other
  ///   during the connect phase (mount/camera/focuser/etc. each go to a
  ///   different driver) so parallelism is safe.
  /// * For each device, the stream emits:
  ///     1. `connecting` immediately as the call is dispatched, and
  ///     2. `connected` if the underlying `connectX` completes, or
  ///        `failed` carrying the raw error if it throws.
  /// * One device failing does NOT block any other device. Per-device
  ///   errors are reported as `failed` events; the stream itself never
  ///   errors and always closes cleanly once every device is settled.
  /// * Errors are a feature: the original backend error is preserved on
  ///   the `failed` event so the UI can show it (driver error, "device not
  ///   reachable", USB hub blip, etc.). We do NOT swallow or rewrite the
  ///   error.
  /// * If [profile] has no configured devices, the stream closes
  ///   immediately with no events.
  ///
  /// The returned stream is single-subscription so initial `connecting`
  /// events are buffered until the caller attaches its listener. UI
  /// surfaces that need to fan out to multiple widgets should feed the
  /// stream through [deviceConnectionProgressProvider]
  /// (see `record(event)`), which materializes the events into a
  /// `ref.watch`-able snapshot that any number of widgets can observe.
  Stream<DeviceConnectProgress> _connectAllFromProfile(
    EquipmentProfileModel profile,
  ) {
    // (id, deviceType label, connector). Order is informational only —
    // every device is dispatched in parallel.
    final entries = <(String?, String, Future<void> Function(String))>[
      (profile.cameraId, 'camera', connectCamera),
      (profile.mountId, 'mount', connectMount),
      (profile.focuserId, 'focuser', connectFocuser),
      (profile.filterWheelId, 'filter wheel', connectFilterWheel),
      (profile.guiderId, 'guider', connectGuider),
      (profile.rotatorId, 'rotator', connectRotator),
      (profile.domeId, 'dome', connectDome),
      (profile.weatherId, 'weather station', connectWeather),
      (profile.safetyMonitorId, 'safety monitor', connectSafetyMonitor),
      (profile.switchId, 'switch', connectSwitch),
      (profile.coverCalibratorId, 'cover calibrator', connectCoverCalibrator),
    ];

    // Use a single-subscription StreamController so events are buffered
    // until the caller subscribes. A broadcast controller would drop the
    // initial `connecting` events because the caller hasn't yet attached
    // its `await for` listener at the moment we add them.
    final controller = StreamController<DeviceConnectProgress>();

    // Filter to only configured devices. An empty list still produces a
    // valid stream — the caller just sees no events before close.
    final active = entries
        .where((e) => e.$1 != null && e.$1!.isNotEmpty)
        .map((e) => (e.$1!, e.$2, e.$3))
        .toList(growable: false);

    if (active.isEmpty) {
      // No devices configured — close immediately so the caller's `await
      // for` exits cleanly.
      scheduleMicrotask(controller.close);
      return controller.stream;
    }

    // Defer dispatch one microtask so the caller (typically `await for`)
    // has time to attach its listener before any events fire. The
    // single-subscription controller buffers anyway, but emitting on the
    // next turn also keeps observable ordering deterministic in tests
    // that drive multiple sweeps in the same event-loop turn.
    scheduleMicrotask(() {
      // Dispatch every connect in parallel. Each future swallows its own
      // error and routes it onto the stream as a `failed` event so one
      // bad device cannot abort the sweep.
      final futures = <Future<void>>[];
      for (final (id, deviceType, connect) in active) {
        controller.add(
          DeviceConnectProgress(
            deviceType: deviceType,
            deviceId: id,
            status: DeviceConnectProgressStatus.connecting,
          ),
        );

        futures.add(
          connect(id)
              .then((_) {
                if (!controller.isClosed) {
                  controller.add(
                    DeviceConnectProgress(
                      deviceType: deviceType,
                      deviceId: id,
                      status: DeviceConnectProgressStatus.connected,
                    ),
                  );
                }
              })
              .catchError((Object error, StackTrace stack) {
                if (!controller.isClosed) {
                  controller.add(
                    DeviceConnectProgress(
                      deviceType: deviceType,
                      deviceId: id,
                      status: DeviceConnectProgressStatus.failed,
                      error: error,
                      errorMessage: error.toString(),
                    ),
                  );
                }
              }),
        );
      }

      // Close the stream once every device has settled. We use
      // `Future.wait` without `eagerError` because we've already caught
      // every per-device error above — every future resolves
      // successfully here.
      Future.wait(futures).whenComplete(() {
        if (!controller.isClosed) {
          controller.close();
        }
      });
    });

    return controller.stream;
  }

  /// Disconnect all devices
  ///
  /// Each device-type disconnect now throws [DeviceNotConnectedException]
  /// when the matching state provider has no `deviceId`. For a
  /// bulk-disconnect sweep that is the normal case (most equipment profiles
  /// list only a handful of devices), so we silence that specific exception
  /// and let every other failure (driver error, stale handle, timeout, …)
  /// propagate so the caller can surface it. We deliberately do not use
  /// `Future.wait`: a single failure there cancels reporting of the others.
  Future<void> _disconnectAll() async {
    final disconnects = <(Future<void> Function(), String)>[
      (disconnectCamera, 'camera'),
      (disconnectMount, 'mount'),
      (disconnectFocuser, 'focuser'),
      (disconnectFilterWheel, 'filter wheel'),
      (disconnectGuider, 'guider'),
      (disconnectRotator, 'rotator'),
      (disconnectDome, 'dome'),
      (disconnectWeather, 'weather station'),
      (disconnectSafetyMonitor, 'safety monitor'),
      (disconnectSwitch, 'switch'),
      (disconnectCoverCalibrator, 'cover calibrator'),
    ];

    final errors = <String>[];
    for (final (disconnect, name) in disconnects) {
      try {
        await disconnect();
      } on DeviceNotConnectedException {
        // Expected — the matching device type is not currently connected.
        continue;
      } catch (e) {
        errors.add('$name: $e');
      }
    }

    if (errors.isNotEmpty) {
      throw Exception(
        'Some devices failed to disconnect:\n${errors.join('\n')}',
      );
    }
  }
}
