import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart'
    as models;
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_bridge/src/api_barrel.dart' as bridge_api;
import 'package:nightshade_bridge/src/device_capabilities.dart' as bridge_caps;
import 'package:nightshade_bridge/src/device.dart' as bridge_device;
import 'package:nightshade_bridge/src/error.dart' as bridge_error;
import 'package:nightshade_bridge/src/utils/safe_cast.dart'
    show safelyCast, safelyCastOpt;

// Import pure Dart types from backend_types for return types
import '../models/backend/device_capabilities.dart' as dart_caps;
import '../models/backend/device_status.dart' as dart_status;
import '../models/backend/device_types.dart' as dart_types;
import '../models/errors/nightshade_error.dart' as dart_error;

/// FFI backend implementation that wraps the native Rust bridge
///
/// This backend uses direct FFI calls to the Rust native library
/// and is used by Desktop and Headless modes.
class FfiBackend implements NightshadeBackend {
  static final _logger = Logger('FfiBackend');
  final NightshadeDatabase? _database;

  /// Cached broadcast stream for events - allows multiple subscribers
  Stream<NightshadeEvent>? _cachedEventStream;

  /// Subscription to polar alignment events - must be cancelled on dispose
  StreamSubscription<NightshadeEvent>? _polarAlignSubscription;

  /// Whether this backend has been disposed
  bool _disposed = false;

  FfiBackend({NightshadeDatabase? database}) : _database = database;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _polarAlignSubscription?.cancel();
    _polarAlignSubscription = null;
    _polarAlignController.close();
    _cachedEventStream = null;

    _logger.info('FfiBackend disposed');
  }

  @override
  Stream<NightshadeEvent> get eventStream {
    if (_disposed) {
      throw StateError('Cannot access eventStream after dispose');
    }

    // Return cached broadcast stream to allow multiple subscribers
    if (_cachedEventStream == null) {
      _logger.info('Creating event stream from native bridge');
      _cachedEventStream = bridge.NativeBridge.eventStream().map((bridgeEvent) {
        // Extract eventType and data from the EventPayload
        final payloadInfo = _extractPayloadInfo(bridgeEvent.payload);
        final category = _fromBridgeCategory(bridgeEvent.category);

        // Log guiding events at info level for diagnostics
        if (category == EventCategory.guiding) {
          _logger.info(
              'FfiBackend received guiding event: ${payloadInfo.$1} data=${payloadInfo.$2}');
        }

        return NightshadeEvent(
          timestamp: bridgeEvent.timestamp,
          severity: _fromBridgeSeverity(bridgeEvent.severity),
          category: category,
          eventType: payloadInfo.$1,
          data: payloadInfo.$2,
        );
      }).asBroadcastStream();

      _logger.info('Event stream created as broadcast stream');

      // Wire up polar alignment events to the dedicated stream
      // Store subscription for proper cleanup on dispose
      _polarAlignSubscription = _cachedEventStream!.listen((event) {
        if (event.category == EventCategory.polarAlignment) {
          _polarAlignController.add(event.data);
        }
      });
    }
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

    // Handle polar alignment events
    if (payload is bridge.EventPayload_PolarAlignment) {
      final pa = payload.field0;
      return (
        'PolarAlignment',
        {
          'azimuth_error': pa.azimuthError,
          'altitude_error': pa.altitudeError,
          'total_error': pa.totalError,
          'current_ra': pa.currentRa,
          'current_dec': pa.currentDec,
          'target_ra': pa.targetRa,
          'target_dec': pa.targetDec,
        }
      );
    }

    if (payload is bridge.EventPayload_PolarAlignmentStatus) {
      final status = payload.field0;
      return (
        'PolarAlignmentStatus',
        {
          'status': status.status,
          'phase': status.phase,
          'point': status.point,
        }
      );
    }

    if (payload is bridge.EventPayload_PolarAlignmentImage) {
      final img = payload.field0;
      return (
        'PolarAlignmentImage',
        {
          'image_data': img.imageData,
          'width': img.width,
          'height': img.height,
          'solved_ra': img.solvedRa,
          'solved_dec': img.solvedDec,
          'point': img.point,
          'phase': img.phase,
        }
      );
    }

    // For other event types, use string parsing as fallback
    final payloadStr = payload.toString();
    final match = RegExp(r'^EventPayload\.(\w+)\(').firstMatch(payloadStr);
    final eventType = match?.group(1) ?? 'unknown';
    return (eventType, {'payload': payloadStr});
  }

  /// Extract event type and data from an EquipmentEvent
  (String, Map<String, dynamic>) _extractEquipmentEventInfo(
      dynamic equipmentEvent) {
    // Connection events
    if (equipmentEvent is bridge.EquipmentEvent_Connecting) {
      return (
        'Connecting',
        {
          'device_type': equipmentEvent.deviceType,
          'device_id': equipmentEvent.deviceId,
        }
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_Connected) {
      return (
        'Connected',
        {
          'device_type': equipmentEvent.deviceType,
          'device_id': equipmentEvent.deviceId,
        }
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_Disconnected) {
      return (
        'Disconnected',
        {
          'device_type': equipmentEvent.deviceType,
          'device_id': equipmentEvent.deviceId,
        }
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_PropertyChanged) {
      return (
        'PropertyChanged',
        {
          'device_type': equipmentEvent.deviceType,
          'device_id': equipmentEvent.deviceId,
          'property': equipmentEvent.property,
          'value': equipmentEvent.value,
        }
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_Error) {
      return (
        'Error',
        {
          'device_type': equipmentEvent.deviceType,
          'device_id': equipmentEvent.deviceId,
          'message': equipmentEvent.message,
        }
      );
    }
    // Mount events
    else if (equipmentEvent is bridge.EquipmentEvent_MountSlewStarted) {
      return (
        'MountSlewStarted',
        {'ra': equipmentEvent.ra, 'dec': equipmentEvent.dec}
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_MountSlewCompleted) {
      return (
        'MountSlewCompleted',
        {'ra': equipmentEvent.ra, 'dec': equipmentEvent.dec}
      );
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
      return (
        'FocuserMoveStarted',
        {'target_position': equipmentEvent.targetPosition}
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_FocuserMoveCompleted) {
      return ('FocuserMoveCompleted', {'position': equipmentEvent.position});
    } else if (equipmentEvent
        is bridge.EquipmentEvent_FocuserTemperatureChanged) {
      return (
        'FocuserTemperatureChanged',
        {'temperature': equipmentEvent.temperature}
      );
    }
    // Filter wheel events
    else if (equipmentEvent is bridge.EquipmentEvent_FilterChanging) {
      return (
        'FilterChanging',
        {
          'from_position': equipmentEvent.fromPosition,
          'to_position': equipmentEvent.toPosition,
          'filter_name': equipmentEvent.filterName,
        }
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_FilterChanged) {
      return (
        'FilterChanged',
        {
          'position': equipmentEvent.position,
          'filter_name': equipmentEvent.filterName,
        }
      );
    }
    // Rotator events
    else if (equipmentEvent is bridge.EquipmentEvent_RotatorMoveStarted) {
      return (
        'RotatorMoveStarted',
        {'target_angle': equipmentEvent.targetAngle}
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_RotatorMoveCompleted) {
      return ('RotatorMoveCompleted', {'angle': equipmentEvent.angle});
    }
    // Camera events
    else if (equipmentEvent is bridge.EquipmentEvent_CameraCoolingStarted) {
      return (
        'CameraCoolingStarted',
        {'target_temp': equipmentEvent.targetTemp}
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraCoolingReached) {
      return (
        'CameraCoolingReached',
        {'temperature': equipmentEvent.temperature}
      );
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraWarmingStarted) {
      return ('CameraWarmingStarted', {});
    } else if (equipmentEvent is bridge.EquipmentEvent_CameraWarmingCompleted) {
      return ('CameraWarmingCompleted', {});
    }
    // Fallback
    return ('UnknownEquipmentEvent', {'event': equipmentEvent.toString()});
  }

  /// Extract event type and data from a GuidingEvent
  (String, Map<String, dynamic>) _extractGuidingEventInfo(
      dynamic guidingEvent) {
    if (guidingEvent is bridge.GuidingEvent_Correction) {
      return (
        'GuideStep',
        {
          'RADistanceRaw': guidingEvent.raRaw,
          'DECDistanceRaw': guidingEvent.decRaw,
          'RADistance': guidingEvent.ra,
          'DECDistance': guidingEvent.dec,
        }
      );
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
    } else if (guidingEvent is bridge.GuidingEvent_Looping) {
      return ('LoopingExposures', {});
    } else if (guidingEvent is bridge.GuidingEvent_Settling) {
      return ('Settling', {});
    } else if (guidingEvent is bridge.GuidingEvent_Calibrating) {
      return ('Calibrating', {});
    } else if (guidingEvent is bridge.GuidingEvent_CalibrationComplete) {
      return ('CalibrationComplete', {});
    } else if (guidingEvent is bridge.GuidingEvent_StarSelected) {
      return (
        'StarSelected',
        {
          'X': guidingEvent.x,
          'Y': guidingEvent.y,
        }
      );
    } else if (guidingEvent is bridge.GuidingEvent_AppState) {
      return (
        'AppState',
        {
          'State': guidingEvent.state,
        }
      );
    } else if (guidingEvent is bridge.GuidingEvent_GuideStats) {
      return (
        'GuideStats',
        {
          'SNR': guidingEvent.snr,
          'StarMass': guidingEvent.starMass,
        }
      );
    }

    return ('UnknownGuidingEvent', {'event': guidingEvent.toString()});
  }

  /// Extract event type and data from a SequencerEvent
  (String, Map<String, dynamic>) _extractSequencerEventInfo(
      dynamic sequencerEvent) {
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
      return (
        'NodeStarted',
        {
          'node_id': sequencerEvent.nodeId,
          'node_type': sequencerEvent.nodeType,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_NodeCompleted) {
      return (
        'NodeCompleted',
        {
          'node_id': sequencerEvent.nodeId,
          'status': sequencerEvent.status,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_Progress) {
      return (
        'Progress',
        {
          'current': sequencerEvent.current,
          'total': sequencerEvent.total,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_TargetChanged) {
      return (
        'TargetChanged',
        {
          'target_name': sequencerEvent.targetName,
          'ra': sequencerEvent.ra,
          'dec': sequencerEvent.dec,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_TargetCompleted) {
      return ('TargetCompleted', {'target_name': sequencerEvent.targetName});
    } else if (sequencerEvent is bridge.SequencerEvent_ExposureStarted) {
      return (
        'ExposureStarted',
        {
          'frame': sequencerEvent.frame,
          'total': sequencerEvent.total,
          'filter': sequencerEvent.filter,
          'duration_secs': sequencerEvent.durationSecs,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_ExposureCompleted) {
      return (
        'ExposureCompleted',
        {
          'frame': sequencerEvent.frame,
          'total': sequencerEvent.total,
          'duration_secs': sequencerEvent.durationSecs,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_Error) {
      return ('Error', {'message': sequencerEvent.message});
    } else if (sequencerEvent is bridge.SequencerEvent_TriggerFired) {
      return (
        'TriggerFired',
        {
          'trigger_id': sequencerEvent.triggerId,
          'trigger_name': sequencerEvent.triggerName,
          'action': sequencerEvent.action,
        }
      );
    } else if (sequencerEvent is bridge.SequencerEvent_InstructionProgress) {
      return (
        'InstructionProgress',
        {
          'node_id': sequencerEvent.nodeId,
          'instruction': sequencerEvent.instruction,
          'progress_percent': sequencerEvent.progressPercent,
          'detail': sequencerEvent.detail,
        }
      );
    }

    return ('UnknownSequencerEvent', {'event': sequencerEvent.toString()});
  }

  /// Extract event type and data from an ImagingEvent
  (String, Map<String, dynamic>) _extractImagingEventInfo(
      dynamic imagingEvent) {
    if (imagingEvent is bridge.ImagingEvent_ExposureStarted) {
      return (
        'ExposureStarted',
        {
          'duration_secs': imagingEvent.durationSecs,
          'frame_type': imagingEvent.frameType.toString(),
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureStartedWithFrame) {
      return (
        'ExposureStarted',
        {
          'duration_secs': imagingEvent.durationSecs,
          'frame': imagingEvent.frameNumber,
          'total': imagingEvent.totalFrames,
          'frame_type': imagingEvent.frameType.toString(),
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureProgress) {
      return (
        'ExposureProgress',
        {
          'progress': imagingEvent.progress,
          'remainingSecs': imagingEvent.remainingSecs,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCompleted) {
      return (
        'ExposureCompleted',
        {
          'file_path': imagingEvent.filePath,
          'hfr': imagingEvent.hfr,
          'stars_detected': imagingEvent.starsDetected,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCompletedWithFrame) {
      return (
        'ExposureCompleted',
        {
          'frame': imagingEvent.frameNumber,
          'total': imagingEvent.totalFrames,
          'hfr': imagingEvent.hfr,
          'stars_detected': imagingEvent.starsDetected,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureFailed) {
      return (
        'ExposureFailed',
        {
          'error': imagingEvent.error,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureCancelled) {
      return ('ExposureCancelled', {});
    } else if (imagingEvent is bridge.ImagingEvent_DownloadStarted) {
      return ('DownloadStarted', {});
    } else if (imagingEvent is bridge.ImagingEvent_DownloadCompleted) {
      return ('DownloadCompleted', {});
    } else if (imagingEvent is bridge.ImagingEvent_ImageReady) {
      return (
        'ImageReady',
        {
          'width': imagingEvent.width,
          'height': imagingEvent.height,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ImageSaved) {
      return (
        'ImageSaved',
        {
          'file_path': imagingEvent.filePath,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_TemperatureChanged) {
      return (
        'TemperatureChanged',
        {
          'temp_celsius': imagingEvent.tempCelsius,
          'cooler_power': imagingEvent.coolerPower,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureComplete) {
      // Legacy event type - map to 'ExposureComplete' for compatibility with imaging_service.dart
      return (
        'ExposureComplete',
        {
          'success': imagingEvent.success,
        }
      );
    } else if (imagingEvent is bridge.ImagingEvent_ExposureFailedOld) {
      return (
        'ExposureFailed',
        {
          'reason': imagingEvent.reason,
        }
      );
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
    final bridgeDevices = await _discoverAddressDevices(
      label: 'INDI',
      host: host,
      port: port,
      discover: () => bridge_api.apiDiscoverIndiAtAddress(
        host: host,
        port: port,
      ),
    );
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
    final bridgeDevices = await _discoverAddressDevices(
      label: 'Alpaca',
      host: host,
      port: port,
      discover: () => bridge_api.apiDiscoverAlpacaAtAddress(
        host: host,
        port: port,
      ),
    );
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

  Future<List<bridge.DeviceInfo>> _discoverAddressDevices({
    required String label,
    required String host,
    required int port,
    required Future<List<bridge.DeviceInfo>> Function() discover,
  }) async {
    try {
      return await discover();
    } catch (e, stackTrace) {
      _logger.warning(
        '$label address discovery failed for $host:$port; returning no devices',
        e,
        stackTrace,
      );
      return const <bridge.DeviceInfo>[];
    }
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
    int? gain,
    int? offset,
    int binX = 1,
    int binY = 1,
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {
    // Use provided gain/offset or fall back to 0 (camera defaults)
    await bridge.NativeBridge.startExposure(
      deviceId: deviceId,
      durationSecs: exposureTime,
      gain: gain ?? 0,
      offset: offset ?? 0,
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
    final bridgeImage = await bridge_api.apiGetLastImage(deviceId: deviceId);

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
      isColor: bridgeImage.isColor,
    );
  }

  @override
  Future<List<int>> getLastRawImageData(String deviceId) async {
    return await bridge_api.apiGetLastRawImageData(deviceId: deviceId);
  }

  @override
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required FitsWriteHeader headerData,
  }) async {
    await bridge_api.apiSaveFitsFile(
      filePath: filePath,
      width: width,
      height: height,
      data: data,
      headerData: _toBridgeFitsHeader(headerData),
    );
  }

  @override
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  }) async {
    await bridge_api.apiSaveFitsFromLastCapture(
      deviceId: deviceId,
      filePath: filePath,
      headerData: _toBridgeFitsHeader(headerData),
    );
  }

  @override
  Future<void> clearDeviceImage(String deviceId) async {
    await bridge_api.apiClearDeviceImage(deviceId: deviceId);
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
  Future<void> cameraSetReadoutMode(String deviceId, int modeIndex) async {
    await bridge.NativeBridge.setReadoutMode(
      deviceId: deviceId,
      modeIndex: modeIndex,
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
  Future<void> mountSlewAltAz(
      String deviceId, double altitude, double azimuth) async {
    await bridge_api.mountSlewAltAz(
        deviceId: deviceId, altitude: altitude, azimuth: azimuth);
  }

  @override
  Future<void> mountFindHome(String deviceId) async {
    await bridge_api.mountFindHome(deviceId: deviceId);
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
  Future<AutofocusResult> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    String curveFitting = 'Hyperbolic',
    int numberOfAttempts = 1,
    int exposuresPerPoint = 1,
    double rSquaredThreshold = 0.7,
    double outerCropRatio = 1.0,
    double innerCropRatio = 0.0,
    int useBrightestNStars = 0,
    int focuserSettleTimeMs = 500,
    String backlashCompMethod = 'Overshoot',
    int backlashIn = 350,
    int backlashOut = 0,
  }) async {
    final config = bridge_api.AutofocusConfigApi(
      exposureTime: exposureTime,
      stepSize: stepSize,
      stepsOut: stepsOut,
      method: method,
      binning: binning,
    );
    final bridgeResult = await bridge_api.apiRunAutofocus(
      deviceId: deviceId,
      cameraId: cameraId,
      config: config,
    );
    return _fromBridgeAutofocusResult(bridgeResult);
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

  @override
  Future<void> rotatorSyncToPa(String deviceId, double pa) async {
    await bridge.NativeBridge.apiRotatorSyncToPa(deviceId: deviceId, pa: pa);
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
  // Generic Guiding (driver-agnostic abstraction)
  // =========================================================================

  @override
  Future<void> guiderStartGuiding({
    required String deviceId,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await bridge.NativeBridge.guiderStartGuiding(
      deviceId: deviceId,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  @override
  Future<void> guiderStopGuiding({required String deviceId}) async {
    await bridge.NativeBridge.guiderStop(deviceId: deviceId);
  }

  @override
  Future<void> guiderDither({
    required String deviceId,
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await bridge.NativeBridge.guiderDither(
      deviceId: deviceId,
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  @override
  Future<void> guiderLoop({required String deviceId}) async {
    await bridge.NativeBridge.guiderLoop(deviceId: deviceId);
  }

  @override
  Future<(double, double)> guiderFindStar({required String deviceId}) async {
    final result = await bridge.NativeBridge.guiderFindStar(deviceId: deviceId);
    return (result.$1, result.$2);
  }

  @override
  Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  }) async {
    await bridge.NativeBridge.guiderSetLockPosition(
      deviceId: deviceId,
      x: x,
      y: y,
      exact: exact,
    );
  }

  @override
  Future<(double, double)> guiderGetLockPosition(
      {required String deviceId}) async {
    final result =
        await bridge.NativeBridge.guiderGetLockPosition(deviceId: deviceId);
    return (result.$1, result.$2);
  }

  @override
  Future<void> guiderDeselectStar({required String deviceId}) async {
    await bridge.NativeBridge.guiderDeselectStar(deviceId: deviceId);
  }

  @override
  Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  }) async {
    final image = await bridge.NativeBridge.guiderGetStarImage(
      deviceId: deviceId,
      size: size,
    );
    return Phd2StarImage(
      frame: image.frame,
      width: image.width,
      height: image.height,
      starX: image.starX,
      starY: image.starY,
      pixels: image.pixels,
    );
  }

  @override
  Future<BuiltinGuiderConfig> builtinGuiderGetConfig() async {
    final raw = await bridge.NativeBridge.builtinGuiderGetConfigRaw();
    return BuiltinGuiderConfig.fromJson(raw);
  }

  @override
  Future<void> builtinGuiderSetConfig(BuiltinGuiderConfig config) async {
    await bridge.NativeBridge.builtinGuiderSetConfigRaw(
      exposureSecs: config.exposureSecs,
      gain: config.gain,
      offset: config.offset,
      binning: config.binning,
      calibrationMs: config.calibrationMs,
      settleSleepMs: config.settleSleepMs,
      minPulseMs: config.minPulseMs,
      maxPulseMs: config.maxPulseMs,
    );
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
    // `bridge.NativeBridge.plateSolve*` already returns the FRB-canonical
    // `PlateSolveResult` (see `bridge_stub.dart` typedef), so no conversion
    // is needed since the model-layer copy was removed.
    return ra != null && dec != null
        ? bridge.NativeBridge.plateSolveNear(
            imagePath,
            ra,
            dec,
            fovDegrees ?? 30.0,
          )
        : bridge.NativeBridge.plateSolveBlind(imagePath);
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
  Future<void> sequencerSkip() async {
    await bridge.NativeBridge.sequencerSkip();
  }

  @override
  Future<void> sequencerReset() async {
    await bridge.NativeBridge.sequencerReset();
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
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    await bridge.NativeBridge.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
      filterNames: filterNames,
      filterFocusOffsets: filterFocusOffsets,
    );
  }

  @override
  Future<void> sequencerSetSafetyFailMode(String mode) async {
    await bridge.NativeBridge.sequencerSetSafetyFailMode(mode);
  }

  @override
  Future<void> sequencerSetSavePath(String? path) async {
    await bridge.NativeBridge.sequencerSetSavePath(path: path);
  }

  @override
  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    await bridge.NativeBridge.sequencerUpdateDitherConfig(
      pixels: pixels,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
      raOnly: raOnly,
    );
  }

  @override
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    await bridge.NativeBridge.sequencerUpdateLocation(
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<void> sequencerUpdateFilterOffsets(Map<String, int> offsets) async {
    await bridge.NativeBridge.sequencerUpdateFilterOffsets(offsets: offsets);
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
        // Why: ip-api.com returns a free-form JSON body. Validate it is a
        // map before indexing, and run each numeric field through
        // [safelyCastOpt] so a malformed payload surfaces a structured
        // CastFailureException (audit-rust §1.4, CLAUDE.md "errors are a
        // feature") instead of a bare TypeError or silent 0.0.
        final decoded = jsonDecode(response.body);
        final data = safelyCast<Map<String, dynamic>>(
          decoded,
          context: 'ip-api.com response body',
        );
        final lat = safelyCastOpt<num>(
          data['lat'],
          context: 'ip-api.com response["lat"]',
        );
        final lon = safelyCastOpt<num>(
          data['lon'],
          context: 'ip-api.com response["lon"]',
        );
        return LocationSettings(
          latitude: lat?.toDouble() ?? 0.0,
          longitude: lon?.toDouble() ?? 0.0,
          elevation: 0.0,
        );
      }
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Failed to fetch location: HTTP ${response.statusCode}',
        isRecoverable: true,
      );
    } catch (e) {
      if (e is dart_error.NightshadeError) rethrow;
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Error fetching location: $e',
        isRecoverable: true,
      );
    }
  }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  @override
  Future<CameraStatus> getCameraStatus(String deviceId) async {
    final bridgeStatus = await bridge.NativeBridge.getCameraStatus(deviceId);
    return _fromBridgeCameraStatus(bridgeStatus);
  }

  @override
  Future<MountStatus> getMountStatus(String deviceId) async {
    final bridgeStatus = await bridge.NativeBridge.getMountStatus(deviceId);
    return _fromBridgeMountStatus(bridgeStatus);
  }

  @override
  Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    final bridgeStatus = await bridge.NativeBridge.getFocuserStatus(deviceId);
    return _fromBridgeFocuserStatus(bridgeStatus);
  }

  @override
  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    final bridgeStatus =
        await bridge.NativeBridge.getFilterWheelStatus(deviceId);
    return _fromBridgeFilterWheelStatus(bridgeStatus);
  }

  @override
  Future<RotatorStatus> getRotatorStatus(String deviceId) async {
    final bridgeStatus =
        await bridge_api.apiGetRotatorStatus(deviceId: deviceId);
    return _fromBridgeRotatorStatus(bridgeStatus);
  }

  // Status conversion helpers
  dart_status.CameraStatus _fromBridgeCameraStatus(
      bridge_device.CameraStatus s) {
    return dart_status.CameraStatus(
      connected: s.connected,
      state: _fromBridgeCameraState(s.state),
      sensorTemp: s.sensorTemp,
      coolerPower: s.coolerPower,
      targetTemp: s.targetTemp,
      coolerOn: s.coolerOn,
      gain: s.gain,
      offset: s.offset,
      binX: s.binX,
      binY: s.binY,
      sensorWidth: s.sensorWidth,
      sensorHeight: s.sensorHeight,
      pixelSizeX: s.pixelSizeX,
      pixelSizeY: s.pixelSizeY,
      maxAdu: s.maxAdu,
      canCool: s.canCool,
      canSetGain: s.canSetGain,
      canSetOffset: s.canSetOffset,
    );
  }

  dart_types.CameraState _fromBridgeCameraState(bridge_device.CameraState s) {
    switch (s) {
      case bridge_device.CameraState.idle:
        return dart_types.CameraState.idle;
      case bridge_device.CameraState.waiting:
        return dart_types.CameraState.waiting;
      case bridge_device.CameraState.exposing:
        return dart_types.CameraState.exposing;
      case bridge_device.CameraState.reading:
        return dart_types.CameraState.reading;
      case bridge_device.CameraState.download:
        return dart_types.CameraState.download;
      case bridge_device.CameraState.error:
        return dart_types.CameraState.error;
    }
  }

  dart_status.MountStatus _fromBridgeMountStatus(bridge_device.MountStatus s) {
    return dart_status.MountStatus(
      connected: s.connected,
      tracking: s.tracking,
      slewing: s.slewing,
      parked: s.parked,
      atHome: s.atHome ?? false,
      sideOfPier: s.sideOfPier == null
          ? dart_types.PierSide.unknown
          : _fromBridgePierSide(s.sideOfPier!),
      rightAscension: s.rightAscension,
      declination: s.declination,
      altitude: s.altitude ?? 0.0,
      azimuth: s.azimuth ?? 0.0,
      siderealTime: s.siderealTime ?? 0.0,
      trackingRate: s.trackingRate == null
          ? dart_caps.TrackingRate.sidereal
          : _fromBridgeTrackingRate(s.trackingRate!),
      canPark: s.canPark,
      canSlew: s.canSlew,
      canSync: s.canSync,
      canPulseGuide: s.canPulseGuide,
      canSetTrackingRate: s.canSetTrackingRate,
      availability: s.availability.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  dart_types.PierSide _fromBridgePierSide(bridge_device.PierSide s) {
    switch (s) {
      case bridge_device.PierSide.east:
        return dart_types.PierSide.east;
      case bridge_device.PierSide.west:
        return dart_types.PierSide.west;
      case bridge_device.PierSide.unknown:
        return dart_types.PierSide.unknown;
    }
  }

  dart_caps.TrackingRate _fromBridgeTrackingRate(bridge_device.TrackingRate r) {
    switch (r) {
      case bridge_device.TrackingRate.sidereal:
        return dart_caps.TrackingRate.sidereal;
      case bridge_device.TrackingRate.lunar:
        return dart_caps.TrackingRate.lunar;
      case bridge_device.TrackingRate.solar:
        return dart_caps.TrackingRate.solar;
      case bridge_device.TrackingRate.king:
        return dart_caps.TrackingRate.king;
      case bridge_device.TrackingRate.custom:
        return dart_caps.TrackingRate.custom;
    }
  }

  dart_status.FocuserStatus _fromBridgeFocuserStatus(
      bridge_device.FocuserStatus s) {
    return dart_status.FocuserStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      temperature: s.temperature,
      maxPosition: s.maxPosition,
      stepSize: s.stepSize,
      isAbsolute: s.isAbsolute,
      hasTemperature: s.hasTemperature,
    );
  }

  dart_status.FilterWheelStatus _fromBridgeFilterWheelStatus(
      bridge_device.FilterWheelStatus s) {
    return dart_status.FilterWheelStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      filterCount: s.filterCount,
      filterNames: s.filterNames,
    );
  }

  dart_status.RotatorStatus _fromBridgeRotatorStatus(
      bridge_device.RotatorStatus s) {
    return dart_status.RotatorStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      mechanicalPosition: s.mechanicalPosition,
      isMoving: s.isMoving,
      canReverse: s.canReverse,
    );
  }

  // =========================================================================
  // Device Capabilities
  // =========================================================================

  @override
  Future<CameraCapabilities?> getCameraCapabilities(String deviceId) async {
    try {
      final bridgeCaps =
          await bridge_api.apiGetCameraCapabilities(deviceId: deviceId);
      return _fromBridgeCameraCapabilities(bridgeCaps);
    } catch (e) {
      _logger.warning('Failed to get camera capabilities: $e');
      return null;
    }
  }

  @override
  Future<MountCapabilities?> getMountCapabilities(String deviceId) async {
    try {
      final bridgeCaps =
          await bridge_api.apiGetMountCapabilities(deviceId: deviceId);
      return _fromBridgeMountCapabilities(bridgeCaps);
    } catch (e) {
      _logger.warning('Failed to get mount capabilities: $e');
      return null;
    }
  }

  @override
  Future<FocuserCapabilities?> getFocuserCapabilities(String deviceId) async {
    try {
      final bridgeCaps =
          await bridge_api.apiGetFocuserCapabilities(deviceId: deviceId);
      return _fromBridgeFocuserCapabilities(bridgeCaps);
    } catch (e) {
      _logger.warning('Failed to get focuser capabilities: $e');
      return null;
    }
  }

  @override
  Future<FilterWheelCapabilities?> getFilterWheelCapabilities(
      String deviceId) async {
    try {
      final bridgeCaps =
          await bridge_api.apiGetFilterwheelCapabilities(deviceId: deviceId);
      return _fromBridgeFilterWheelCapabilities(bridgeCaps);
    } catch (e) {
      _logger.warning('Failed to get filter wheel capabilities: $e');
      return null;
    }
  }

  @override
  Future<RotatorCapabilities?> getRotatorCapabilities(String deviceId) async {
    try {
      // Use generic device capabilities and extract rotator
      final result =
          await bridge_api.apiGetDeviceCapabilities(deviceId: deviceId);
      if (result is bridge_caps.DeviceCapabilities_Rotator) {
        return _fromBridgeRotatorCapabilities(result.field0);
      }
      return null;
    } catch (e) {
      _logger.warning('Failed to get rotator capabilities: $e');
      return null;
    }
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
    final bridgeLoc = location != null ? _toBridgeLocation(location) : null;
    _logger.fine(
        'setLocation: ${location != null ? "lat=${location.latitude}, lon=${location.longitude}, elev=${location.elevation}" : "null"}');
    bridge.NativeBridge.apiSetLocation(location: bridgeLoc);
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
  Future<List<StarCrop>> getStarCropsFromLastImage(String deviceId,
      {int maxCrops = 5}) async {
    final bridgeCrops = await bridge_api.apiGetStarCropsFromLastImage(
      deviceId: deviceId,
      maxCrops: maxCrops,
    );
    return bridgeCrops
        .map((crop) => StarCrop(
              pixelsBase64: crop.pixelsBase64,
              width: crop.width.toInt(),
              height: crop.height.toInt(),
              hfr: crop.hfr,
              snr: crop.snr,
            ))
        .toList();
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
    int? gain,
    int? offset,
    double? solveTimeout,
    bool? startFromCurrent,
  }) async {
    await bridge_api.apiStartPolarAlignment(
      exposureTime: exposureTime,
      stepSize: stepSize,
      binning: binning,
      isNorth: isNorth,
      manualRotation: manualRotation,
      rotateEast: rotateEast,
      gain: gain,
      offset: offset,
      solveTimeout: solveTimeout,
      startFromCurrent: startFromCurrent,
    );
  }

  @override
  Future<void> stopPolarAlignment() async {
    await bridge_api.apiStopPolarAlignment();
  }

  @override
  Future<void> startAllSkyPolarAlignment({
    required double exposureTime,
    required double solveTimeout,
    required int binning,
    required bool isNorth,
    required double acceptanceThresholdArcsec,
    required double iterationCadenceSecs,
    int? gain,
    int? offset,
  }) async {
    // Rust implementation lives in
    // `native/.../bridge/src/api/polar_alignment.rs::api_start_all_sky_polar_alignment`.
    // FRB bindings are regenerated under `apiStartAllSkyPolarAlignment` and
    // re-exported via `api_barrel.dart` — wire them directly. Errors from
    // Rust (missing solver / no devices / no observer location) surface as
    // a `NightshadeError` and propagate up; we do not swallow them.
    await bridge_api.apiStartAllSkyPolarAlignment(
      exposureTime: exposureTime,
      solveTimeout: solveTimeout,
      binning: binning,
      isNorth: isNorth,
      acceptanceThresholdArcsec: acceptanceThresholdArcsec,
      iterationCadenceSecs: iterationCadenceSecs,
      gain: gain,
      offset: offset,
    );
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
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Database not available in FFI backend',
      );
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
      throw _toNightshadeError(e, 'Failed to get session images');
    }
  }

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    if (_database == null) {
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Database not available in FFI backend',
      );
    }

    try {
      // Get image metadata from database
      final imagesDao = ImagesDao(_database!);
      final dbImage = await imagesDao.getImageById(imageId);

      if (dbImage == null) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.imaging,
          message: 'Image not found: $imageId',
        );
      }

      // Check if file exists
      final file = File(dbImage.filePath);
      if (!await file.exists()) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.io,
          message: 'Image file not found: ${dbImage.filePath}',
        );
      }

      // Generate thumbnail using Rust FFI function
      // This reads the FITS file, downscales to ~512x512, auto-stretches, and encodes as JPEG
      final jpegData = await bridge_api.apiGenerateFitsThumbnail(
        filePath: dbImage.filePath,
        maxSize: 512,
      );

      return Uint8List.fromList(jpegData);
    } catch (e) {
      throw _toNightshadeError(e, 'Failed to get image thumbnail');
    }
  }

  @override
  Future<void> downloadImage(int imageId, String localPath,
      {void Function(double)? onProgress}) async {
    if (_database == null) {
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Database not available in FFI backend',
      );
    }

    try {
      // Get image metadata from database
      final imagesDao = ImagesDao(_database!);
      final dbImage = await imagesDao.getImageById(imageId);

      if (dbImage == null) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.imaging,
          message: 'Image not found: $imageId',
        );
      }

      // Check if source file exists
      final sourceFile = File(dbImage.filePath);
      if (!await sourceFile.exists()) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.io,
          message: 'Image file not found: ${dbImage.filePath}',
        );
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
      throw _toNightshadeError(e, 'Failed to download image');
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

  // =========================================================================
  // FRB->Dart Type Mappers
  // =========================================================================

  /// Convert pure Dart FitsWriteHeader to bridge FitsWriteHeader
  bridge.FitsWriteHeader _toBridgeFitsHeader(FitsWriteHeader h) {
    return bridge.FitsWriteHeader(
      objectName: h.objectName,
      exposureTime: h.exposureTime,
      captureTimestamp: h.captureTimestamp,
      frameType: h.frameType,
      filter: h.filter,
      gain: h.gain,
      offset: h.offset,
      ccdTemp: h.ccdTemp,
      ra: h.ra,
      dec: h.dec,
      altitude: h.altitude,
      telescope: h.telescope,
      instrument: h.instrument,
      observer: h.observer,
      binX: h.binX ?? 1, // Default to 1x1 binning
      binY: h.binY ?? 1,
      focalLength: h.focalLength,
      aperture: h.aperture,
      pixelSizeX: h.pixelSizeX,
      pixelSizeY: h.pixelSizeY,
      siteLatitude: h.siteLatitude,
      siteLongitude: h.siteLongitude,
      siteElevation: h.siteElevation,
    );
  }

  /// Convert bridge AutofocusResultApi to pure Dart AutofocusResult
  AutofocusResult _fromBridgeAutofocusResult(bridge_api.AutofocusResultApi r) {
    return AutofocusResult(
      bestPosition: r.bestPosition,
      bestHfr: r.bestHfr,
      focusData: r.focusData
          .map((dp) => FocusDataPoint(
                position: dp.position,
                hfr: dp.hfr,
                fwhm: dp.fwhm,
                starCount: dp.starCount,
              ))
          .toList(),
      method: r.method,
      temperature: r.temperature,
      timestamp: r.timestamp,
      curveFitQuality: r.curveFitQuality,
      backlashApplied: r.backlashApplied,
    );
  }

  /// Convert bridge CameraCapabilities to pure Dart CameraCapabilities
  CameraCapabilities _fromBridgeCameraCapabilities(
      bridge_caps.CameraCapabilities c) {
    return CameraCapabilities(
      maxWidth: c.maxWidth,
      maxHeight: c.maxHeight,
      bitDepth: c.bitDepth,
      hasShutter: c.hasShutter,
      canSetCcdTemperature: c.canSetCcdTemperature,
      canSetCooler: c.canSetCooler,
      canGetCoolerPower: c.canGetCoolerPower,
      canBin: c.canBin,
      maxBinX: c.maxBinX,
      maxBinY: c.maxBinY,
      canAsymmetricBin: c.canAsymmetricBin,
      canSetGain: c.canSetGain,
      gainMin: c.gainMin,
      gainMax: c.gainMax,
      canSetOffset: c.canSetOffset,
      offsetMin: c.offsetMin,
      offsetMax: c.offsetMax,
      canAbortExposure: c.canAbortExposure,
      canStopExposure: c.canStopExposure,
      canSubframe: c.canSubframe,
      pixelSizeX: c.pixelSizeX,
      pixelSizeY: c.pixelSizeY,
      isColor: c.isColor,
      bayerPattern: c.bayerPattern,
      sensorType: c.sensorType,
      hasFastReadout: c.hasFastReadout,
      readoutModes: c.readoutModes,
      exposureMin: c.exposureMin,
      exposureMax: c.exposureMax,
      ccdTemperature: c.ccdTemperature,
      setCcdTemperature: c.setCcdTemperature,
      coolerPower: c.coolerPower,
      coolerOn: c.coolerOn,
    );
  }

  /// Convert bridge MountCapabilities to pure Dart MountCapabilities
  MountCapabilities _fromBridgeMountCapabilities(
      bridge_caps.MountCapabilities m) {
    return MountCapabilities(
      canSlew: m.canSlew,
      canSlewAsync: m.canSlewAsync,
      canSync: m.canSync,
      canPark: m.canPark,
      canUnpark: m.canUnpark,
      canSetPark: m.canSetPark,
      canPulseGuide: m.canPulseGuide,
      canGetSideOfPier: m.canGetSideOfPier,
      canSetSideOfPier: m.canSetSideOfPier,
      canSetTracking: m.canSetTracking,
      canSetTrackingRate: m.canSetTrackingRate,
      supportedTrackingRates: m.supportedTrackingRates
          .map((r) => _fromBridgeTrackingRate(r))
          .toList(),
      isEquatorial: m.isEquatorial,
      supportsAltAz: m.supportsAltAz,
      canGetPointingState: m.canGetPointingState,
      canFindHome: m.canFindHome,
      tracking: m.tracking,
      trackingRate: m.trackingRate != null
          ? _fromBridgeTrackingRate(m.trackingRate!)
          : null,
      canAbortSlew: m.canAbortSlew,
      maxSlewRate: m.maxSlewRate,
      canMoveAxis: m.canMoveAxis,
      axisCount: m.axisCount,
    );
  }

  /// Convert bridge FocuserCapabilities to pure Dart FocuserCapabilities
  FocuserCapabilities _fromBridgeFocuserCapabilities(
      bridge_caps.FocuserCapabilities f) {
    return FocuserCapabilities(
      maxPosition: f.maxPosition,
      maxIncrement: f.maxIncrement,
      stepSize: f.stepSize,
      absolute: f.absolute,
      tempCompAvailable: f.tempCompAvailable,
      tempComp: f.tempComp,
      temperature: f.temperature,
      isMoving: f.isMoving,
      position: f.position,
      canHalt: f.canHalt,
      canReverse: f.canReverse,
      reverse: f.reverse,
    );
  }

  /// Convert bridge FilterWheelCapabilities to pure Dart FilterWheelCapabilities
  FilterWheelCapabilities _fromBridgeFilterWheelCapabilities(
      bridge_caps.FilterWheelCapabilities fw) {
    return FilterWheelCapabilities(
      positionCount: fw.positionCount,
      currentPosition: fw.currentPosition,
      filterNames: fw.filterNames,
      focusOffsets: fw.focusOffsets,
      isMoving: fw.isMoving,
      canSetFilterNames: fw.canSetFilterNames,
      canSetFocusOffsets: fw.canSetFocusOffsets,
    );
  }

  /// Convert bridge RotatorCapabilities to pure Dart RotatorCapabilities
  RotatorCapabilities _fromBridgeRotatorCapabilities(
      bridge_caps.RotatorCapabilities r) {
    return RotatorCapabilities(
      canReverse: r.canReverse,
      reverse: r.reverse,
      stepSize: r.stepSize,
      isMoving: r.isMoving,
      mechanicalPosition: r.mechanicalPosition,
      position: r.position,
      canMoveAbsolute: r.canMoveAbsolute,
      canHalt: r.canHalt,
      canSync: r.canSync,
    );
  }

  // =========================================================================
  // Error Conversion
  // =========================================================================

  /// Convert any exception to a structured NightshadeError.
  ///
  /// This handles:
  /// - FRB-generated NightshadeError (from Rust)
  /// - AnyhowException (fallback from Rust)
  /// - Generic Dart exceptions
  dart_error.NightshadeError _toNightshadeError(Object exception,
      [String? context]) {
    // Handle FRB-generated NightshadeError from Rust
    if (exception is bridge_error.NightshadeError) {
      return _fromBridgeNightshadeError(exception);
    }

    // Handle generic exceptions with context
    final message = context != null
        ? '$context: ${exception.toString()}'
        : exception.toString();

    return dart_error.NightshadeError.fromString(message);
  }

  /// Convert FRB-generated NightshadeError to pure Dart NightshadeError.
  ///
  /// This preserves all the structured error information from Rust.
  dart_error.NightshadeError _fromBridgeNightshadeError(
      bridge_error.NightshadeError e) {
    return e.when(
      // Connection errors
      deviceNotFound: (deviceId) =>
          dart_error.NightshadeError.deviceNotFound(deviceId),
      connectionFailed: (deviceId, reason) =>
          dart_error.NightshadeError.connectionFailed(deviceId, reason),
      alreadyConnected: (deviceId) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.connection,
        message: 'Device already connected: $deviceId',
        userMessage: "'$deviceId' is already connected",
        deviceId: deviceId,
      ),
      notConnected: (deviceId) =>
          dart_error.NightshadeError.notConnected(deviceId),
      deviceDisconnected: (deviceId, reason) =>
          dart_error.NightshadeError.deviceDisconnected(deviceId, reason),

      // Hardware errors
      hardwareError: (deviceId, message, errorCode) =>
          dart_error.NightshadeError.hardwareError(deviceId, message,
              errorCode: errorCode),
      communicationError: (deviceId, message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.hardware,
        message: 'Communication error: $deviceId - $message',
        userMessage: "Communication error with '$deviceId'",
        isRecoverable: true,
        shouldReconnect: true,
        deviceId: deviceId,
      ),

      // Timeout errors
      timeout: (message) => dart_error.NightshadeError.timeout(message),
      deviceTimeout: (deviceId, operation, timeoutSecs) =>
          dart_error.NightshadeError.timeout(operation,
              deviceId: deviceId, timeoutSecs: timeoutSecs),
      connectionTimeout: (deviceId, timeoutSecs) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.timeout,
        message:
            'Connection timeout: $deviceId after ${timeoutSecs.toStringAsFixed(1)}s',
        userMessage: "Connection to '$deviceId' timed out",
        isRecoverable: true,
        isTimeout: true,
        shouldReconnect: true,
        deviceId: deviceId,
      ),

      // Validation errors
      invalidParameter: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.validation,
        message: 'Invalid parameter: $message',
      ),
      invalidInput: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.validation,
        message: 'Invalid input: $message',
      ),
      invalidDeviceId: (deviceId, reason) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.validation,
        message: 'Invalid device ID: $deviceId - $reason',
        deviceId: deviceId,
      ),
      parameterOutOfRange: (paramName, value, min, max) =>
          dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.validation,
        message:
            'Parameter out of range: $paramName = $value (valid: $min to $max)',
        userMessage: '$paramName value $value is out of range ($min to $max)',
      ),

      // Operation errors
      operationFailed: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Operation failed: $message',
        isRecoverable: true,
      ),
      notSupported: (deviceId, operation) =>
          dart_error.NightshadeError.notSupported(deviceId, operation),
      deviceBusy: (deviceId, currentOperation) =>
          dart_error.NightshadeError.deviceBusy(deviceId, currentOperation),

      // Imaging errors
      imageError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.imaging,
        message: 'Image error: $message',
      ),
      cameraError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.imaging,
        message: 'Camera error: $message',
      ),
      noImageAvailable: () => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.imaging,
        message: 'No image available',
      ),
      exposureCancelled: () => dart_error.NightshadeError.cancelled(),
      exposureFailed: (cameraId, reason) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.imaging,
        message: 'Exposure failed: $cameraId - $reason',
        userMessage: "Exposure failed on '$cameraId'",
        deviceId: cameraId,
      ),
      downloadFailed: (cameraId, reason) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.imaging,
        message: 'Image download failed: $cameraId - $reason',
        deviceId: cameraId,
      ),

      // I/O errors
      ioError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'I/O error: $message',
      ),
      serializationError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Serialization error: $message',
      ),
      plateSolveError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Plate solve failed: $message',
      ),

      // Sequence errors
      sequenceError: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.sequence,
        message: 'Sequence error: $message',
      ),

      // Driver-specific errors
      ascomError: (progId, message, errorCode) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.driver,
        message: 'ASCOM error: $progId - $message (code: $errorCode)',
        errorCode: errorCode,
      ),
      alpacaError: (baseUrl, deviceNumber, message, errorCode) =>
          dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.driver,
        message:
            'Alpaca error: $baseUrl device $deviceNumber - $message (code: $errorCode)',
        errorCode: errorCode,
      ),
      indiError: (server, port, deviceName, message) =>
          dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.driver,
        message: 'INDI error: $server:$port device $deviceName - $message',
      ),
      nativeError: (vendor, message, errorCode) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.driver,
        message: 'Native SDK error: $vendor - $message (code: $errorCode)',
        errorCode: errorCode,
      ),
      comError: (message, hresult) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.driver,
        message:
            'COM error: $message (HRESULT: 0x${hresult.toRadixString(16).padLeft(8, '0')})',
        errorCode: hresult,
        shouldReconnect: true,
      ),

      // System errors
      internal: (message) => dart_error.NightshadeError.internal(message),
      cancelled: () => dart_error.NightshadeError.cancelled(),
      runtimeInitFailed: (message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Runtime initialization failed: $message',
      ),
      resourceExhausted: (resource, message) => dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message: 'Resource exhausted: $resource - $message',
        isRecoverable: true,
      ),
    );
  }
}
