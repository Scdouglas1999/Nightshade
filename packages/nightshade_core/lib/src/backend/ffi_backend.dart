import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart'
    as models;
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_bridge/src/api.dart' as bridge_api;

/// FFI backend implementation that wraps the native Rust bridge
///
/// This backend uses direct FFI calls to the Rust native library
/// and is used by Desktop and Headless modes.
class FfiBackend implements NightshadeBackend {
  final NightshadeDatabase? _database;

  /// Cached broadcast stream for events - allows multiple subscribers
  Stream<NightshadeEvent>? _cachedEventStream;

  FfiBackend({NightshadeDatabase? database}) : _database = database;

  @override
  Stream<NightshadeEvent> get eventStream {
    // Return cached broadcast stream to allow multiple subscribers
    _cachedEventStream ??= bridge.NativeBridge.eventStream().map((bridgeEvent) {
      // Extract eventType and data from the EventPayload
      final payloadInfo = _extractPayloadInfo(bridgeEvent.payload);
      return NightshadeEvent(
        timestamp: bridgeEvent.timestamp,
        severity: _fromBridgeSeverity(bridgeEvent.severity),
        category: _fromBridgeCategory(bridgeEvent.category),
        eventType: payloadInfo.$1,
        data: payloadInfo.$2,
      );
    }).asBroadcastStream();
    return _cachedEventStream!;
  }

  /// Extract eventType string and data map from an EventPayload
  (String, Map<String, dynamic>) _extractPayloadInfo(dynamic payload) {
    // Handle guiding events with proper field extraction
    if (payload is bridge.EventPayload_Guiding) {
      final guidingEvent = payload.field0;
      return _extractGuidingEventInfo(guidingEvent);
    }

    // Handle equipment events with proper field extraction
    if (payload is bridge.EventPayload_Equipment) {
      return _extractEquipmentEventInfo(payload.field0);
    }

    // Handle sequencer events with proper field extraction
    if (payload is bridge.EventPayload_Sequencer) {
      return _extractSequencerEventInfo(payload.field0);
    }

    // Handle imaging events with proper field extraction
    if (payload is bridge.EventPayload_Imaging) {
      return _extractImagingEventInfo(payload.field0);
    }

    // For other event types, use string parsing as fallback
    final payloadStr = payload.toString();
    final match = RegExp(r'^EventPayload\.(\w+)\(').firstMatch(payloadStr);
    final eventType = match?.group(1) ?? 'unknown';
    return (eventType, {'payload': payloadStr});
  }

  /// Extract event type and data from an EquipmentEvent
  (String, Map<String, dynamic>) _extractEquipmentEventInfo(dynamic equipmentEvent) {
    // Connection events
    if (equipmentEvent is bridge.EquipmentEvent_Connecting) {
      return ('Connecting', {
        'device_type': equipmentEvent.deviceType,
        'device_id': equipmentEvent.deviceId,
      });
    } else if (equipmentEvent is bridge.EquipmentEvent_Connected) {
      return ('Connected', {
        'device_type': equipmentEvent.deviceType,
        'device_id': equipmentEvent.deviceId,
      });
    } else if (equipmentEvent is bridge.EquipmentEvent_Disconnected) {
      return ('Disconnected', {
        'device_type': equipmentEvent.deviceType,
        'device_id': equipmentEvent.deviceId,
      });
    } else if (equipmentEvent is bridge.EquipmentEvent_PropertyChanged) {
      return ('PropertyChanged', {
        'device_type': equipmentEvent.deviceType,
        'device_id': equipmentEvent.deviceId,
        'property': equipmentEvent.property,
        'value': equipmentEvent.value,
      });
    } else if (equipmentEvent is bridge.EquipmentEvent_Error) {
      return ('Error', {
        'device_type': equipmentEvent.deviceType,
        'device_id': equipmentEvent.deviceId,
        'message': equipmentEvent.message,
      });
    }
    // Mount events
    else if (equipmentEvent is bridge.EquipmentEvent_MountSlewStarted) {
      return ('MountSlewStarted', {'ra': equipmentEvent.ra, 'dec': equipmentEvent.dec});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountSlewCompleted) {
      return ('MountSlewCompleted', {'ra': equipmentEvent.ra, 'dec': equipmentEvent.dec});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountTrackingStarted) {
      return ('MountTrackingStarted', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountTrackingStopped) {
      return ('MountTrackingStopped', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountParkStarted) {
      return ('MountParkStarted', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountParkCompleted) {
      return ('MountParkCompleted', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_MountUnparked) {
      return ('MountUnparked', {});
    }
    // Focuser events
    else if (equipmentEvent is bridge.EquipmentEvent_FocuserMoveStarted) {
      return ('FocuserMoveStarted', {'target_position': equipmentEvent.targetPosition});
    } else if (equipmentEvent is bridge.EquipmentEvent_FocuserMoveCompleted) {
      return ('FocuserMoveCompleted', {'position': equipmentEvent.position});
    } else if (equipmentEvent is bridge.EquipmentEvent_FocuserTemperatureChanged) {
      return ('FocuserTemperatureChanged', {'temperature': equipmentEvent.temperature});
    }
    // Filter wheel events
    else if (equipmentEvent is bridge.EquipmentEvent_FilterChanging) {
      return ('FilterChanging', {
        'from_position': equipmentEvent.fromPosition,
        'to_position': equipmentEvent.toPosition,
        'filter_name': equipmentEvent.filterName,
      });
    } else if (equipmentEvent is bridge.EquipmentEvent_FilterChanged) {
      return ('FilterChanged', {
        'position': equipmentEvent.position,
        'filter_name': equipmentEvent.filterName,
      });
    }
    // Rotator events
    else if (equipmentEvent is bridge.EquipmentEvent_RotatorMoveStarted) {
      return ('RotatorMoveStarted', {'target_angle': equipmentEvent.targetAngle});
    } else if (equipmentEvent is bridge.EquipmentEvent_RotatorMoveCompleted) {
      return ('RotatorMoveCompleted', {'angle': equipmentEvent.angle});
    }
    // Camera events
    else if (equipmentEvent is bridge.EquipmentEvent_CameraCoolingStarted) {
      return ('CameraCoolingStarted', {'target_temp': equipmentEvent.targetTemp});
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraCoolingReached) {
      return ('CameraCoolingReached', {'temperature': equipmentEvent.temperature});
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraWarmingStarted) {
      return ('CameraWarmingStarted', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraWarmingCompleted) {
      return ('CameraWarmingCompleted', {});
    }
    // Fallback
    return ('UnknownEquipmentEvent', {'event': equipmentEvent.toString()});
  }

  /// Extract event type and data from a GuidingEvent
  (String, Map<String, dynamic>) _extractGuidingEventInfo(dynamic guidingEvent) {
    if (guidingEvent is bridge.GuidingEvent_Correction) {
      return ('GuideStep', {
        'RADistanceRaw': guidingEvent.raRaw,
        'DECDistanceRaw': guidingEvent.decRaw,
        'RADistance': guidingEvent.ra,
        'DECDistance': guidingEvent.dec,
      });
    } else if (guidingEvent is bridge.GuidingEvent_GuidingStarted) {
      return ('GuidingStarted', {});
    } else if (guidingEvent is bridge.GuidingEvent_GuidingStopped) {
      return ('GuidingStopped', {});
    } else if (guidingEvent is bridge.GuidingEvent_Connected) {
      return ('Connected', {});
    } else if (guidingEvent is bridge.GuidingEvent_Disconnected) {
      return ('Disconnected', {});
    } else if (guidingEvent is bridge.GuidingEvent_Paused) {
      return ('Paused', {});
    } else if (guidingEvent is bridge.GuidingEvent_Resumed) {
      return ('Resumed', {});
    } else if (guidingEvent is bridge.GuidingEvent_LostStar) {
      return ('StarLost', {});
    } else if (guidingEvent is bridge.GuidingEvent_Settled) {
      return ('SettleDone', {'rms': guidingEvent.rms});
    } else if (guidingEvent is bridge.GuidingEvent_DitherStarted) {
      return ('DitherStarted', {'pixels': guidingEvent.pixels});
    } else if (guidingEvent is bridge.GuidingEvent_DitherCompleted) {
      return ('DitherCompleted', {});
    }

    return ('UnknownGuidingEvent', {'event': guidingEvent.toString()});
  }

  /// Extract event type and data from a SequencerEvent
  (String, Map<String, dynamic>) _extractSequencerEventInfo(dynamic sequencerEvent) {
    if (sequencerEvent is bridge.SequencerEvent_Started) {
      return ('Started', {'sequence_name': sequencerEvent.sequenceName});
    } else if (sequencerEvent is bridge.SequencerEvent_Paused) {
      return ('Paused', {});
    } else if (sequencerEvent is bridge.SequencerEvent_Resumed) {
      return ('Resumed', {});
    } else if (sequencerEvent is bridge.SequencerEvent_Stopped) {
      return ('Stopped', {});
    } else if (sequencerEvent is bridge.SequencerEvent_Completed) {
      return ('Completed', {});
    } else if (sequencerEvent is bridge.SequencerEvent_NodeStarted) {
      return ('NodeStarted', {
        'node_id': sequencerEvent.nodeId,
        'node_type': sequencerEvent.nodeType,
      });
    } else if (sequencerEvent is bridge.SequencerEvent_NodeCompleted) {
      return ('NodeCompleted', {
        'node_id': sequencerEvent.nodeId,
        'success': sequencerEvent.success,
      });
    } else if (sequencerEvent is bridge.SequencerEvent_Progress) {
      return ('Progress', {
        'current': sequencerEvent.current,
        'total': sequencerEvent.total,
      });
    } else if (sequencerEvent is bridge.SequencerEvent_TargetChanged) {
      return ('TargetChanged', {'target_name': sequencerEvent.targetName});
    } else if (sequencerEvent is bridge.SequencerEvent_TargetCompleted) {
      return ('TargetCompleted', {'target_name': sequencerEvent.targetName});
    } else if (sequencerEvent is bridge.SequencerEvent_ExposureStarted) {
      return ('ExposureStarted', {
        'frame': sequencerEvent.frame,
        'total': sequencerEvent.total,
        'filter': sequencerEvent.filter,
        'duration_secs': sequencerEvent.durationSecs,
      });
    } else if (sequencerEvent is bridge.SequencerEvent_ExposureCompleted) {
      return ('ExposureCompleted', {
        'frame': sequencerEvent.frame,
        'total': sequencerEvent.total,
        'duration_secs': sequencerEvent.durationSecs,
      });
    } else if (sequencerEvent is bridge.SequencerEvent_Error) {
      return ('Error', {'message': sequencerEvent.message});
    } else if (sequencerEvent is bridge.SequencerEvent_InstructionProgress) {
      return ('InstructionProgress', {
        'node_id': sequencerEvent.nodeId,
        'instruction': sequencerEvent.instruction,
        'progress_percent': sequencerEvent.progressPercent,
        'detail': sequencerEvent.detail,
      });
    }

    return ('UnknownSequencerEvent', {'event': sequencerEvent.toString()});
  }

  /// Extract event type and data from an ImagingEvent
  (String, Map<String, dynamic>) _extractImagingEventInfo(dynamic imagingEvent) {
    if (imagingEvent is bridge.ImagingEvent_ExposureStarted) {
      return ('ExposureStarted', {
        'duration_secs': imagingEvent.durationSecs,
        'frame_type': imagingEvent.frameType.toString(),
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureStartedWithFrame) {
      return ('ExposureStarted', {
        'duration_secs': imagingEvent.durationSecs,
        'frame': imagingEvent.frameNumber,
        'total': imagingEvent.totalFrames,
        'frame_type': imagingEvent.frameType.toString(),
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureProgress) {
      return ('ExposureProgress', {
        'progress': imagingEvent.progress,
        'remainingSecs': imagingEvent.remainingSecs,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCompleted) {
      return ('ExposureCompleted', {
        'file_path': imagingEvent.filePath,
        'hfr': imagingEvent.hfr,
        'stars_detected': imagingEvent.starsDetected,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCompletedWithFrame) {
      return ('ExposureCompleted', {
        'frame': imagingEvent.frameNumber,
        'total': imagingEvent.totalFrames,
        'hfr': imagingEvent.hfr,
        'stars_detected': imagingEvent.starsDetected,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureFailed) {
      return ('ExposureFailed', {
        'error': imagingEvent.error,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCancelled) {
      return ('ExposureCancelled', {});
    } else if (imagingEvent is bridge.ImagingEvent_DownloadStarted) {
      return ('DownloadStarted', {});
    } else if (imagingEvent is bridge.ImagingEvent_DownloadCompleted) {
      return ('DownloadCompleted', {});
    } else if (imagingEvent is bridge.ImagingEvent_ImageReady) {
      return ('ImageReady', {
        'width': imagingEvent.width,
        'height': imagingEvent.height,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ImageSaved) {
      return ('ImageSaved', {
        'file_path': imagingEvent.filePath,
      });
    } else if (imagingEvent is bridge.ImagingEvent_TemperatureChanged) {
      return ('TemperatureChanged', {
        'temp_celsius': imagingEvent.tempCelsius,
        'cooler_power': imagingEvent.coolerPower,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureComplete) {
      // Legacy event type - map to 'ExposureComplete' for compatibility with imaging_service.dart
      return ('ExposureComplete', {
        'success': imagingEvent.success,
      });
    } else if (imagingEvent is bridge.ImagingEvent_ExposureFailedOld) {
      return ('ExposureFailed', {
        'reason': imagingEvent.reason,
      });
    }
    return ('UnknownImagingEvent', {'event': imagingEvent.toString()});
  }

  EventSeverity _fromBridgeSeverity(dynamic severity) {
    final name = severity.toString().split('.').last;
    switch (name) {
      case 'info':
        return EventSeverity.info;
      case 'warning':
        return EventSeverity.warning;
      case 'error':
        return EventSeverity.error;
      case 'critical':
        return EventSeverity.critical;
      default:
        return EventSeverity.info;
    }
  }

  EventCategory _fromBridgeCategory(dynamic category) {
    final name = category.toString().split('.').last;
    switch (name) {
      case 'equipment':
        return EventCategory.equipment;
      case 'imaging':
        return EventCategory.imaging;
      case 'guiding':
        return EventCategory.guiding;
      case 'sequencer':
        return EventCategory.sequencer;
      case 'safety':
        return EventCategory.safety;
      case 'system':
        return EventCategory.system;
      case 'polarAlignment':
        return EventCategory.polarAlignment;
      default:
        return EventCategory.system;
    }
  }

  // =========================================================================
  // Device Discovery & Connection
  // =========================================================================

  @override
  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
    final bridgeType = _toBridgeDeviceType(deviceType);
    final bridgeDevices = await bridge.NativeBridge.discoverDevices(bridgeType);

    return bridgeDevices
        .map((d) => DeviceInfo(
              id: d.id,
              name: d.name,
              deviceType: deviceType,
              driverType: _fromBridgeDriverType(d.driverType),
              description: d.description,
              driverVersion: d.driverVersion,
            ))
        .toList();
  }

  @override
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    final bridgeDevices =
        await bridge_api.apiDiscoverIndiAtAddress(host: host, port: port);
    return bridgeDevices
        .map((d) => DeviceInfo(
              id: d.id,
              name: d.name,
              deviceType: _fromBridgeDeviceType(d.deviceType),
              driverType: _fromBridgeDriverType(d.driverType),
              description: d.description,
              driverVersion: d.driverVersion,
            ))
        .toList();
  }

  @override
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(
      String host, int port) async {
    final bridgeDevices =
        await bridge_api.apiDiscoverAlpacaAtAddress(host: host, port: port);
    return bridgeDevices
        .map((d) => DeviceInfo(
              id: d.id,
              name: d.name,
              deviceType: _fromBridgeDeviceType(d.deviceType),
              driverType: _fromBridgeDriverType(d.driverType),
              description: d.description,
              driverVersion: d.driverVersion,
            ))
        .toList();
  }

  @override
  Future<void> connectDevice(DeviceType deviceType, String deviceId) async {
    final bridgeType = _toBridgeDeviceType(deviceType);
    await bridge.NativeBridge.connectDevice(bridgeType, deviceId);
  }

  @override
  Future<void> disconnectDevice(DeviceType deviceType, String deviceId) async {
    final bridgeType = _toBridgeDeviceType(deviceType);
    await bridge.NativeBridge.disconnectDevice(bridgeType, deviceId);
  }

  @override
  Future<List<DeviceInfo>> getConnectedDevices() async {
    final bridgeDevices = await bridge.NativeBridge.getConnectedDevices();

    return bridgeDevices
        .map((d) => DeviceInfo(
              id: d.id,
              name: d.name,
              deviceType: _fromBridgeDeviceType(d.deviceType),
              driverType: _fromBridgeDriverType(d.driverType),
              description: d.description,
              driverVersion: d.driverVersion,
            ))
        .toList();
  }

  // =========================================================================
  // Camera Control
  // =========================================================================

  @override
  Future<void> cameraStartExposure({
    required String deviceId,
    required double exposureTime,
    required FrameType frameType,
    required int gain,
    required int offset,
    int binX = 1,
    int binY = 1,
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {
    // Use the gain/offset passed from the UI settings
    await bridge.NativeBridge.startExposure(
      deviceId: deviceId,
      durationSecs: exposureTime,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
    );
  }

  @override
  Future<void> cameraAbortExposure(String deviceId) async {
    await bridge.NativeBridge.cancelExposure(deviceId);
  }

  @override
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId) async {
    final bridgeImage = await bridge.NativeBridge.getLastImage();
    if (bridgeImage == null) return null;

    return CapturedImageResult(
      width: bridgeImage.width,
      height: bridgeImage.height,
      displayData: bridgeImage.displayData,
      histogram: bridgeImage.histogram,
      stats: ImageStatsResult(
        min: bridgeImage.stats.min,
        max: bridgeImage.stats.max,
        mean: bridgeImage.stats.mean,
        median: bridgeImage.stats.median,
        stdDev: bridgeImage.stats.stdDev,
        hfr: bridgeImage.stats.hfr,
        starCount: bridgeImage.stats.starCount,
      ),
      exposureTime: bridgeImage.exposureTime,
      timestamp: bridgeImage.timestamp,
      isColor: bridgeImage.isColor, // Pass isColor from bridge
    );
  }

  @override
  Future<List<int>> getLastRawImageData() async {
    // Use the FFI API directly
    return await bridge_api.apiGetLastRawImageData();
  }

  @override
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required bridge.FitsWriteHeader headerData,
  }) async {
    // Convert List<int> to List<int> for u16 data (already correct type)
    await bridge_api.apiSaveFitsFile(
      filePath: filePath,
      width: width,
      height: height,
      data: data,
      headerData: headerData,
    );
  }

  @override
  Future<void> cameraSetCooling({
    required String deviceId,
    required bool enabled,
    double? targetTemp,
  }) async {
    await bridge.NativeBridge.setCameraCooler(
      deviceId,
      enabled,
      targetTemp,
    );
  }

  @override
  Future<void> cameraSetGain(String deviceId, int gain) async {
    await bridge.NativeBridge.setCameraGain(deviceId, gain);
  }

  @override
  Future<void> cameraSetOffset(String deviceId, int offset) async {
    await bridge.NativeBridge.setCameraOffset(deviceId, offset);
  }

  // =========================================================================
  // Mount Control
  // =========================================================================

  @override
  Future<void> mountSlewToCoordinates(
      String deviceId, double ra, double dec) async {
    await bridge.NativeBridge.mountSlewToCoordinates(deviceId, ra, dec);
  }

  @override
  Future<void> mountSync(String deviceId, double ra, double dec) async {
    await bridge.NativeBridge.mountSync(deviceId, ra, dec);
  }

  @override
  Future<void> mountPark(String deviceId) async {
    await bridge.NativeBridge.mountPark(deviceId);
  }

  @override
  Future<void> mountUnpark(String deviceId) async {
    await bridge.NativeBridge.mountUnpark(deviceId);
  }

  @override
  Future<void> mountSetTracking(String deviceId, bool enabled) async {
    await bridge.NativeBridge.mountSetTracking(deviceId, enabled);
  }

  @override
  Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    await bridge_api.mountSetTrackingRate(deviceId: deviceId, rate: rate);
  }

  @override
  Future<void> mountMoveAxis(String deviceId, int axis, double rate) async {
    await bridge_api.mountMoveAxis(deviceId: deviceId, axis: axis, rate: rate);
  }

  @override
  Future<void> mountPulseGuide({
    required String deviceId,
    required String direction,
    required int durationMs,
  }) async {
    await bridge.NativeBridge.mountPulseGuide(deviceId, direction, durationMs);
  }

  @override
  Future<void> mountAbort(String deviceId) async {
    await bridge_api.mountAbort(deviceId: deviceId);
  }

  @override
  Future<dynamic> mountGetStatus(String deviceId) async {
    return await bridge_api.apiGetMountStatus(deviceId: deviceId);
  }

  // =========================================================================
  // Focuser Control
  // =========================================================================

  @override
  Future<void> focuserMoveTo(String deviceId, int position) async {
    await bridge.NativeBridge.focuserMoveTo(deviceId, position);
  }

  @override
  Future<void> focuserMoveRelative(String deviceId, int delta) async {
    await bridge.NativeBridge.focuserMoveRelative(deviceId, delta);
  }

  @override
  Future<void> focuserHalt(String deviceId) async {
    await bridge.NativeBridge.apiFocuserHalt(deviceId: deviceId);
  }

  @override
  Future<bridge_api.AutofocusResultApi> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
  }) async {
    final config = bridge_api.AutofocusConfigApi(
      exposureTime: exposureTime,
      stepSize: stepSize,
      stepsOut: stepsOut,
      method: method,
      binning: binning,
    );
    return await bridge_api.apiRunAutofocus(
      deviceId: deviceId,
      cameraId: cameraId,
      config: config,
    );
  }

  @override
  Future<void> autofocusCancel() async {
    await bridge_api.apiCancelAutofocus();
  }

  // =========================================================================
  // Filter Wheel Control
  // =========================================================================

  @override
  Future<void> filterWheelSetPosition(String deviceId, int position) async {
    await bridge.NativeBridge.apiFilterwheelSetPosition(
        deviceId: deviceId, position: position);
  }

  @override
  Future<List<String>> filterWheelGetNames(String deviceId) async {
    return await bridge.NativeBridge.apiFilterwheelGetNames(deviceId: deviceId);
  }

  @override
  Future<void> filterWheelSetByName(String deviceId, String name) async {
    await bridge.NativeBridge.apiFilterwheelSetByName(
        deviceId: deviceId, name: name);
  }

  // =========================================================================
  // Rotator Control
  // =========================================================================

  @override
  Future<void> rotatorMoveTo(String deviceId, double angle) async {
    await bridge.NativeBridge.apiRotatorMoveTo(
        deviceId: deviceId, angle: angle);
  }

  @override
  Future<void> rotatorMoveRelative(String deviceId, double delta) async {
    await bridge.NativeBridge.apiRotatorMoveRelative(
        deviceId: deviceId, delta: delta);
  }

  @override
  Future<double> rotatorGetAngle(String deviceId) async {
    // Note: bridge returns RotatorStatus, we need to extract position
    // Or we can add a specific getter. api_get_rotator_status returns RotatorStatus.
    // Wait, api.rs has api_get_rotator_status.
    // But I implemented api_rotator_get_angle in real_device_ops.rs.
    // In api.rs, I implemented api_get_rotator_status which calls real_device_ops.rotator_get_angle.
    // I should probably use apiGetRotatorStatus and extract position.
    final status =
        await bridge.NativeBridge.apiGetRotatorStatus(deviceId: deviceId);
    return status.position;
  }

  @override
  Future<void> rotatorHalt(String deviceId) async {
    await bridge.NativeBridge.apiRotatorHalt(deviceId: deviceId);
  }

  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  @override
  Future<void> phd2Connect({String host = 'localhost', int port = 4400}) async {
    await bridge.NativeBridge.phd2Connect(host: host, port: port);
  }

  @override
  Future<void> phd2Disconnect() async {
    await bridge.NativeBridge.phd2Disconnect();
  }

  @override
  Future<void> phd2StartGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await bridge.NativeBridge.phd2StartGuiding(
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  @override
  Future<void> phd2StopGuiding() async {
    await bridge.NativeBridge.phd2StopGuiding();
  }

  @override
  Future<void> phd2Dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await bridge.NativeBridge.phd2Dither(
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  @override
  Future<Phd2Status> phd2GetStatus() async {
    final status = await bridge.NativeBridge.phd2GetStatus();
    return Phd2Status(
      state: status.state,
      connected: status.connected,
      rmsRa: status.rmsRa,
      rmsDec: status.rmsDec,
      rmsTotal: status.rmsTotal,
      snr: status.snr,
      starMass: status.starMass,
      // FRB Phd2Status no longer provides avgDistance; keep legacy field at 0
      avgDistance: 0.0,
    );
  }

  @override
  Future<Phd2StarImage> phd2GetStarImage({int size = 50}) async {
    final image = await bridge_api.apiPhd2GetStarImage(size: size);
    return Phd2StarImage(
      frame: image.frame,
      width: image.width,
      height: image.height,
      starX: image.starX,
      starY: image.starY,
      pixels: Uint8List.fromList(image.pixels),
    );
  }

  @override
  Future<List<String>> phd2GetAlgoParamNames({required String axis}) async {
    return await bridge.NativeBridge.phd2GetAlgoParamNames(axis: axis);
  }

  @override
  Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    return await bridge.NativeBridge.phd2GetAlgoParam(axis: axis, name: name);
  }

  @override
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    await bridge.NativeBridge.phd2SetAlgoParam(
      axis: axis,
      name: name,
      value: value,
    );
  }

  @override
  Future<void> phd2SetPaused(bool paused) async {
    await bridge.NativeBridge.phd2SetPaused(paused: paused);
  }

  @override
  Future<void> phd2ClearCalibration({String which = 'both'}) async {
    await bridge.NativeBridge.phd2ClearCalibration(which: which);
  }

  @override
  Future<void> phd2FlipCalibration() async {
    await bridge.NativeBridge.phd2FlipCalibration();
  }

  @override
  Future<Phd2CalibrationData> phd2GetCalibrationData() async {
    final data = await bridge.NativeBridge.phd2GetCalibrationData();
    return Phd2CalibrationData(
      isCalibrated: data.isCalibrated,
      rotationAngle: data.raAngle,
      raRate: data.raRate,
      decRate: data.decRate,
      calibratedAt: data.isCalibrated ? DateTime.now() : null,
    );
  }

  @override
  Future<(double, double)> phd2FindStar() async {
    final result = await bridge.NativeBridge.phd2FindStar();
    return (result.$1, result.$2);
  }

  @override
  Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  }) async {
    await bridge.NativeBridge.phd2SetLockPosition(x: x, y: y, exact: exact);
  }

  @override
  Future<(double, double)> phd2GetLockPosition() async {
    final result = await bridge.NativeBridge.phd2GetLockPosition();
    return (result.$1, result.$2);
  }

  @override
  Future<void> phd2Loop() async {
    await bridge.NativeBridge.phd2Loop();
  }

  @override
  Future<void> phd2DeselectStar() async {
    await bridge.NativeBridge.phd2DeselectStar();
  }

  // =========================================================================
  // Plate Solving
  // =========================================================================

  @override
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
  }) async {
    final bridgeResult = ra != null && dec != null
        ? await bridge.NativeBridge.plateSolveNear(
            imagePath,
            ra,
            dec,
            fovDegrees ?? 30.0,
          )
        : await bridge.NativeBridge.plateSolveBlind(imagePath);

    return PlateSolveResult(
      success: bridgeResult.success,
      ra: bridgeResult.ra,
      dec: bridgeResult.dec,
      pixelScale: bridgeResult.pixelScale,
      rotation: bridgeResult.rotation,
      fieldWidth: bridgeResult.fieldWidth,
      fieldHeight: bridgeResult.fieldHeight,
      solveTimeSecs: bridgeResult.solveTimeSecs,
      error: bridgeResult.error,
    );
  }

  // =========================================================================
  // Sequencer Control
  // =========================================================================

  @override
  Future<void> sequencerStart() async {
    await bridge.NativeBridge.sequencerStart();
  }

  @override
  Future<void> sequencerStop() async {
    await bridge.NativeBridge.sequencerStop();
  }

  @override
  Future<void> sequencerPause() async {
    await bridge.NativeBridge.sequencerPause();
  }

  @override
  Future<void> sequencerResume() async {
    await bridge.NativeBridge.sequencerResume();
  }

  @override
  Future<void> sequencerLoadJson(String json) async {
    await bridge.NativeBridge.sequencerLoadJson(json);
  }

  @override
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    await bridge.NativeBridge.sequencerSetSimulationMode(enabled);
  }

  @override
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
  }) async {
    await bridge.NativeBridge.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
    );
  }

  @override
  Future<SequencerStatus> sequencerGetStatus() async {
    final dynamic status = await bridge.NativeBridge.sequencerGetStatus();

    // FRB now returns SequencerState (no progress); bridge_stub returns SequencerStatus (with progress).
    // Support both to keep mobile stubs working.
    if (status is bridge.SequencerState) {
      final progress = status.totalExposures > 0
          ? status.completedExposures / status.totalExposures
          : (status.totalIntegrationSecs > 0
              ? status.elapsedSecs / status.totalIntegrationSecs
              : 0.0);

      return SequencerStatus(
        state: status.state,
        currentNodeId: status.currentNodeId,
        currentNodeName: status.currentNodeName,
        progress: progress.clamp(0.0, 1.0),
        message: status.message,
      );
    }

    if (status is bridge.SequencerStatus) {
      return SequencerStatus(
        state: status.state,
        currentNodeId: status.currentNodeId,
        currentNodeName: status.currentNodeName,
        progress: status.progress,
        message: status.message,
      );
    }

    // Unknown shape; fall back to zero progress.
    return SequencerStatus(
      state: 'unknown',
      currentNodeId: null,
      currentNodeName: null,
      progress: 0.0,
      message: null,
    );
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  @override
  Future<void> sequencerSetCheckpointDir(String path) async {
    await bridge.NativeBridge.sequencerSetCheckpointDir(path);
  }

  @override
  Future<bool> hasCheckpoint() async {
    return await bridge.NativeBridge.sequencerHasCheckpoint();
  }

  @override
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final info = await bridge.NativeBridge.sequencerGetCheckpointInfo();
    if (info == null) return null;

    return CheckpointInfo(
      sequenceName: info.sequenceName,
      timestamp: DateTime.parse(info.timestamp),
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      canResume: info.canResume,
      ageSeconds: info.ageSeconds.toInt(),
    );
  }

  @override
  Future<void> resumeFromCheckpoint() async {
    await bridge.NativeBridge.sequencerResumeFromCheckpoint();
  }

  @override
  Future<void> discardCheckpoint() async {
    await bridge.NativeBridge.sequencerDiscardCheckpoint();
  }

  @override
  Future<void> saveCheckpoint() async {
    await bridge.NativeBridge.sequencerSaveCheckpoint();
  }

  @override
  Future<LocationSettings> getLocationFromInternet() async {
    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return LocationSettings(
          latitude: (data['lat'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['lon'] as num?)?.toDouble() ?? 0.0,
          elevation: 0.0,
        );
      }
      throw Exception('Failed to fetch location: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error fetching location: $e');
    }
  }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  @override
  Future<dynamic> getCameraStatus(String deviceId) async {
    return await bridge.NativeBridge.getCameraStatus(deviceId);
  }

  @override
  Future<dynamic> getMountStatus(String deviceId) async {
    return await bridge.NativeBridge.getMountStatus(deviceId);
  }

  @override
  Future<dynamic> getFocuserStatus(String deviceId) async {
    return await bridge.NativeBridge.getFocuserStatus(deviceId);
  }

  @override
  Future<dynamic> getFilterWheelStatus(String deviceId) async {
    return await bridge.NativeBridge.getFilterWheelStatus(deviceId);
  }

  // =========================================================================
  // Type Conversion Helpers
  // =========================================================================

  bridge.DeviceType _toBridgeDeviceType(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return bridge.DeviceType.camera;
      case DeviceType.mount:
        return bridge.DeviceType.mount;
      case DeviceType.focuser:
        return bridge.DeviceType.focuser;
      case DeviceType.filterWheel:
        return bridge.DeviceType.filterWheel;
      case DeviceType.guider:
        return bridge.DeviceType.guider;
      case DeviceType.dome:
        return bridge.DeviceType.dome;
      case DeviceType.rotator:
        return bridge.DeviceType.rotator;
      case DeviceType.weather:
        return bridge.DeviceType.weather;
      case DeviceType.safetyMonitor:
        return bridge.DeviceType.safetyMonitor;
      case DeviceType.switch_:
        return bridge.DeviceType.switch_;
      case DeviceType.coverCalibrator:
        return bridge.DeviceType.coverCalibrator;
    }
  }

  DeviceType _fromBridgeDeviceType(bridge.DeviceType type) {
    switch (type) {
      case bridge.DeviceType.camera:
        return DeviceType.camera;
      case bridge.DeviceType.mount:
        return DeviceType.mount;
      case bridge.DeviceType.focuser:
        return DeviceType.focuser;
      case bridge.DeviceType.filterWheel:
        return DeviceType.filterWheel;
      case bridge.DeviceType.guider:
        return DeviceType.guider;
      case bridge.DeviceType.dome:
        return DeviceType.dome;
      case bridge.DeviceType.rotator:
        return DeviceType.rotator;
      case bridge.DeviceType.weather:
        return DeviceType.weather;
      case bridge.DeviceType.safetyMonitor:
        return DeviceType.safetyMonitor;
      case bridge.DeviceType.switch_:
        return DeviceType.switch_;
      case bridge.DeviceType.coverCalibrator:
        return DeviceType.coverCalibrator;
    }
  }

  DriverType _fromBridgeDriverType(bridge.DriverType type) {
    switch (type) {
      case bridge.DriverType.ascom:
        return DriverType.ascom;
      case bridge.DriverType.alpaca:
        return DriverType.alpaca;
      case bridge.DriverType.indi:
        return DriverType.indi;
      case bridge.DriverType.native:
        return DriverType.native;
      case bridge.DriverType.simulator:
        return DriverType.simulator;
    }
  }

  // =========================================================================
  // Equipment Profiles
  // =========================================================================

  @override
  Future<List<EquipmentProfile>> getProfiles() async {
    final bridgeProfiles = await bridge.NativeBridge.apiGetProfiles();
    return bridgeProfiles.map(_fromBridgeProfile).toList();
  }

  @override
  Future<void> saveProfile(EquipmentProfile profile) async {
    await bridge.NativeBridge.apiSaveProfile(
        profile: _toBridgeProfile(profile));
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    await bridge.NativeBridge.apiDeleteProfile(profileId: profileId);
  }

  @override
  Future<void> loadProfile(String profileId) async {
    await bridge.NativeBridge.apiLoadProfile(profileId: profileId);
  }

  @override
  Future<EquipmentProfile?> getActiveProfile() async {
    final bridgeProfile = await bridge.NativeBridge.apiGetActiveProfile();
    return bridgeProfile != null ? _fromBridgeProfile(bridgeProfile) : null;
  }

  // =========================================================================
  // Settings & Location
  // =========================================================================

  @override
  Future<models.AppSettings> getSettings() async {
    final bridgeSettings = await bridge.NativeBridge.apiGetSettings();
    return _fromBridgeSettings(bridgeSettings);
  }

  @override
  Future<void> updateSettings(models.AppSettings settings) async {
    await bridge.NativeBridge.apiUpdateSettings(
        settings: _toBridgeSettings(settings));
  }

  @override
  Future<models.ObserverLocation?> getLocation() async {
    final bridgeLocation = await bridge.NativeBridge.apiGetLocation();
    return bridgeLocation != null ? _fromBridgeLocation(bridgeLocation) : null;
  }

  @override
  Future<void> setLocation(models.ObserverLocation? location) async {
    if (location != null) {
      print('[FFI-BACKEND] setLocation called with lat=${location.latitude}, lon=${location.longitude}, elev=${location.elevation}');
    } else {
      print('[FFI-BACKEND] setLocation called with null');
    }
    final bridgeLoc = location != null ? _toBridgeLocation(location) : null;
    if (bridgeLoc != null) {
      print('[FFI-BACKEND] bridgeLoc: lat=${bridgeLoc.latitude}, lon=${bridgeLoc.longitude}, elev=${bridgeLoc.elevation}');
    }
    print('[FFI-BACKEND] Calling apiSetLocation...');
    bridge.NativeBridge.apiSetLocation(location: bridgeLoc);
    print('[FFI-BACKEND] apiSetLocation returned');
  }

  // =========================================================================
  // Image Processing
  // =========================================================================

  @override
  Future<ImageStats> getImageStats(
      int width, int height, Uint16List data) async {
    final bridgeStats = await bridge.NativeBridge.apiGetImageStats(
      width: width,
      height: height,
      data: data,
    );
    return _fromBridgeImageStats(bridgeStats);
  }

  @override
  Future<Uint8List> autoStretchImage(
      int width, int height, Uint16List data) async {
    return await bridge.NativeBridge.apiAutoStretchImage(
      width: width,
      height: height,
      data: data,
    );
  }

  @override
  Future<Uint8List> debayerImage(
    int width,
    int height,
    Uint16List data,
    String pattern,
    String algorithm,
  ) async {
    return await bridge.NativeBridge.apiDebayerImage(
      width: width,
      height: height,
      data: data,
      patternStr: pattern,
      algoStr: algorithm,
    );
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  final _polarAlignController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents =>
      _polarAlignController.stream;

  @override
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
  }) async {
    await bridge_api.apiStartPolarAlignment(
      exposureTime: exposureTime,
      stepSize: stepSize,
      binning: binning,
      isNorth: isNorth,
      manualRotation: manualRotation,
      rotateEast: rotateEast,
    );
  }

  @override
  Future<void> stopPolarAlignment() async {
    await bridge_api.apiStopPolarAlignment();
  }

  ImageStats _fromBridgeImageStats(bridge.ImageStats s) {
    return ImageStats(
      min: s.min,
      max: s.max,
      mean: s.mean,
      median: s.median,
      stdDev: s.stdDev,
      mad: s.mad,
    );
  }

  // Mappers
  models.AppSettings _fromBridgeSettings(bridge.AppSettings s) {
    final loc = s.location != null ? _fromBridgeLocation(s.location!) : null;
    return models.AppSettings(
      location: loc,
      theme: s.theme,
      language: s.language,
      autoConnect: s.autoConnect,
      // Map location fields to direct fields for compatibility
      latitude: loc?.latitude ?? 0.0,
      longitude: loc?.longitude ?? 0.0,
      elevation: loc?.elevation ?? 0.0,
      // Keep defaults for other fields
      fileNamingPattern: '',
      meridianFlipMinutes: 5,
      autoFocusEveryMinutes: 60,
      ditherEveryFrames: 3,
      plateSolveTimeout: 60,
      plateSolveSearchRadius: 30.0,
      discordWebhook: '',
      pushoverKey: '',
      pushoverUser: '',
    );
  }

  bridge.AppSettings _toBridgeSettings(models.AppSettings s) {
    // Use location if available, otherwise create from direct fields
    final loc = s.location ??
        (s.latitude != 0.0 || s.longitude != 0.0
            ? models.ObserverLocation(
                latitude: s.latitude,
                longitude: s.longitude,
                elevation: s.elevation,
              )
            : null);
    return bridge.AppSettings(
      location: loc != null ? _toBridgeLocation(loc) : null,
      theme: s.theme,
      language: s.language,
      autoConnect: s.autoConnect,
    );
  }

  models.ObserverLocation _fromBridgeLocation(bridge.ObserverLocation l) {
    return models.ObserverLocation(
      latitude: l.latitude,
      longitude: l.longitude,
      elevation: l.elevation,
    );
  }

  bridge.ObserverLocation _toBridgeLocation(models.ObserverLocation l) {
    return bridge.ObserverLocation(
      latitude: l.latitude,
      longitude: l.longitude,
      elevation: l.elevation,
    );
  }

  EquipmentProfile _fromBridgeProfile(bridge.EquipmentProfile p) {
    return EquipmentProfile(
      id: p.id,
      name: p.name,
      cameraId: p.cameraId,
      mountId: p.mountId,
      focuserId: p.focuserId,
      filterWheelId: p.filterWheelId,
      guiderId: p.guiderId,
      rotatorId: p.rotatorId,
      domeId: p.domeId,
      weatherId: p.weatherId,
      coverCalibratorId: p.coverCalibratorId,
      telescopeFocalLength: p.telescopeFocalLength,
      telescopeAperture: p.telescopeAperture,
    );
  }

  bridge.EquipmentProfile _toBridgeProfile(EquipmentProfile p) {
    return bridge.EquipmentProfile(
      id: p.id,
      name: p.name,
      cameraId: p.cameraId,
      mountId: p.mountId,
      focuserId: p.focuserId,
      filterWheelId: p.filterWheelId,
      guiderId: p.guiderId,
      rotatorId: p.rotatorId,
      domeId: p.domeId,
      weatherId: p.weatherId,
      coverCalibratorId: p.coverCalibratorId,
      telescopeFocalLength: p.telescopeFocalLength,
      telescopeAperture: p.telescopeAperture,
    );
  }

  // =========================================================================
  // Image Download (for Mobile - local FFI)
  // =========================================================================

  @override
  Future<List<CapturedImage>> getSessionImages(int sessionId) async {
    if (_database == null) {
      throw StateError('Database not available in FFI backend');
    }

    try {
      final imagesDao = ImagesDao(_database!);
      final dbImages = await imagesDao.getImagesForSession(sessionId);

      return dbImages.map((dbImg) {
        return CapturedImage(
          id: dbImg.id.toString(),
          filePath: dbImg.filePath,
          capturedAt: dbImg.capturedAt,
          settings: ExposureSettings(
            exposureTime: dbImg.exposureDuration,
            gain: dbImg.gain ?? 0,
            offset: dbImg.offset ?? 0,
            binningX: dbImg.binX,
            binningY: dbImg.binY,
            filter: dbImg.filter,
            frameType: _frameTypeFromString(dbImg.frameType),
          ),
          stats: dbImg.hfr != null || dbImg.starCount != null
              ? ImageStats(
                  hfr: dbImg.hfr,
                  starCount: dbImg.starCount,
                  background: dbImg.background,
                  noise: dbImg.noise,
                )
              : null,
          targetName: null, // Would need to join with targets table
          format: _imageFormatFromString(dbImg.fileFormat),
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to get session images: $e');
    }
  }

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    if (_database == null) {
      throw StateError('Database not available in FFI backend');
    }

    try {
      // Get image metadata from database
      final imagesDao = ImagesDao(_database!);
      final dbImage = await imagesDao.getImageById(imageId);

      if (dbImage == null) {
        throw Exception('Image not found: $imageId');
      }

      // Check if file exists
      final file = File(dbImage.filePath);
      if (!await file.exists()) {
        throw Exception('Image file not found: ${dbImage.filePath}');
      }

      // Generate thumbnail using Rust FFI function
      // This reads the FITS file, downscales to ~512x512, auto-stretches, and encodes as JPEG
      final jpegData = await bridge_api.apiGenerateFitsThumbnail(
        filePath: dbImage.filePath,
        maxSize: 512,
      );

      return Uint8List.fromList(jpegData);
    } catch (e) {
      throw Exception('Failed to get image thumbnail: $e');
    }
  }

  @override
  Future<void> downloadImage(int imageId, String localPath,
      {void Function(double)? onProgress}) async {
    if (_database == null) {
      throw StateError('Database not available in FFI backend');
    }

    try {
      // Get image metadata from database
      final imagesDao = ImagesDao(_database!);
      final dbImage = await imagesDao.getImageById(imageId);

      if (dbImage == null) {
        throw Exception('Image not found: $imageId');
      }

      // Check if source file exists
      final sourceFile = File(dbImage.filePath);
      if (!await sourceFile.exists()) {
        throw Exception('Image file not found: ${dbImage.filePath}');
      }

      // Create destination directory if needed
      final destFile = File(localPath);
      await destFile.parent.create(recursive: true);

      // Get file size for progress tracking
      final fileSize = await sourceFile.length();

      // Copy file with progress tracking
      final sourceStream = sourceFile.openRead();
      final sink = destFile.openWrite();

      try {
        int bytesWritten = 0;
        await for (final chunk in sourceStream) {
          sink.add(chunk);
          bytesWritten += chunk.length;

          if (onProgress != null && fileSize > 0) {
            onProgress(bytesWritten / fileSize);
          }
        }
      } finally {
        await sink.close();
      }

      // Final progress callback
      if (onProgress != null) {
        onProgress(1.0);
      }
    } catch (e) {
      throw Exception('Failed to download image: $e');
    }
  }

  FrameType _frameTypeFromString(String str) {
    switch (str.toLowerCase()) {
      case 'light':
        return FrameType.light;
      case 'dark':
        return FrameType.dark;
      case 'flat':
        return FrameType.flat;
      case 'bias':
        return FrameType.bias;
      case 'darkflat':
        return FrameType.darkFlat;
      default:
        return FrameType.light;
    }
  }

  ImageFileFormat _imageFormatFromString(String str) {
    switch (str.toLowerCase()) {
      case 'fits':
        return ImageFileFormat.fits;
      case 'xisf':
        return ImageFileFormat.xisf;
      case 'tiff':
        return ImageFileFormat.tiff;
      case 'png':
        return ImageFileFormat.png;
      case 'jpeg':
      case 'jpg':
        return ImageFileFormat.jpeg;
      default:
        return ImageFileFormat.fits;
    }
  }

  // =========================================================================
  // Device Health Monitoring
  // =========================================================================

  @override
  Future<void> startDeviceHeartbeat({
    required DeviceType deviceType,
    required String deviceId,
    required int intervalMs,
  }) async {
    final bridgeType = _toBridgeDeviceType(deviceType);
    await bridge_api.apiStartDeviceHeartbeat(
      deviceType: bridgeType,
      deviceId: deviceId,
      intervalMs: BigInt.from(intervalMs),
    );
  }

  @override
  Future<void> stopDeviceHeartbeat(String deviceId) async {
    await bridge_api.apiStopDeviceHeartbeat(deviceId: deviceId);
  }

  @override
  Future<(int, bool)> getDeviceHealth(String deviceId) async {
    final result = await bridge_api.apiGetDeviceHealth(deviceId: deviceId);
    // Convert PlatformInt64 to int
    final timestamp = result.$1.toInt();
    final isHealthy = result.$2;
    return (timestamp, isHealthy);
  }
}
