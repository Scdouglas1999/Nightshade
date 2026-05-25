import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../models/backend/device_info.dart';
import '../models/backend/device_types.dart';
import '../models/backend/event_types.dart';
import '../models/backend/sequencer_status.dart';
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../models/sequence/sequence_models.dart';
import '../models/backend/host_mutation_event.dart';
import '../services/phd2_status_poll.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'framing_provider.dart';
import 'profiles_provider.dart';
import 'remote_sync_events.dart';
import 'sequence/sequence_catalog_sync.dart';
import 'sequence_provider.dart';
import 'session_provider.dart';
import 'unified_discovery_provider.dart';
import 'target_progress_provider.dart'
    show allTargetProgressProvider, targetProgressProvider;

/// Applies a backend or host-sync event to Riverpod state so UI refreshes
/// without navigation. Used by remote companions ([NetworkBackend]), the
/// desktop host when remote access is enabled, and API mutation publishers.
Future<void> applyRemoteSyncEvent(
  Object reader,
  NightshadeEvent event, {
  NetworkBackend? networkBackend,
}) async {
  if (event.eventType == 'BackendReconnected' && networkBackend != null) {
    await hydrateRemoteSessionState(reader, networkBackend);
    return;
  }

  switch (event.category) {
    case EventCategory.system:
      await _applySystemSyncEvent(reader, event,
          networkBackend: networkBackend);
      break;
    case EventCategory.equipment:
      _applyEquipmentEvent(reader, event);
      break;
    case EventCategory.guiding:
      await _applyGuidingEvent(reader, event, networkBackend: networkBackend);
      break;
    case EventCategory.sequencer:
      _applySequencerEvent(reader, event, networkBackend: networkBackend);
      break;
    case EventCategory.imaging:
      if (event.eventType == 'ImageCaptured' ||
          event.eventType == 'ImageSaved') {
        _invalidateHostCapturedImages(reader);
      }
      break;
    case EventCategory.safety:
    case EventCategory.polarAlignment:
    case EventCategory.job:
    case EventCategory.session:
    case EventCategory.catalog:
      // P1-2/P1-3/P1-5/P1-12 — no remote-sync invalidations needed; these
      // categories are end-state notifications consumed by UI widgets
      // (toasts, progress badges) rather than caches.
      break;
  }
}

Future<void> _applySystemSyncEvent(
  Object reader,
  NightshadeEvent event, {
  NetworkBackend? networkBackend,
}) async {
  if (event.eventType == hostStateChangedEventType) {
    _applyHostMutation(reader, event.data);
    return;
  }

  switch (event.eventType) {
    case RemoteSyncEventTypes.sequenceUpdated:
      _invalidateSequenceLibrary(
        reader,
        sequenceId: event.data['sequenceId'] as int?,
      );
      break;
    case RemoteSyncEventTypes.profileChanged:
      _invalidateEquipmentSyncProviders(reader);
      break;
    case RemoteSyncEventTypes.framingTargetChanged:
      _applyFramingTargetChanged(reader, event);
      break;
    case RemoteSyncEventTypes.guiderState:
      if (networkBackend != null) {
        await _hydratePhd2GuiderState(reader, networkBackend);
      }
      break;
    case RemoteSyncEventTypes.deviceConnected:
      _applyDeviceConnectedFromSyncPayload(reader, event.data);
      break;
    case RemoteSyncEventTypes.deviceDisconnected:
      _applyDeviceDisconnectedFromSyncPayload(reader, event.data);
      break;
  }
}

void _applyEquipmentEvent(Object reader, NightshadeEvent event) {
  final data = event.data;
  switch (event.eventType) {
    case 'Connecting':
      _applyConnectingDevice(
        reader,
        data['device_type'] as String?,
        data['device_id'] as String?,
        data['device_name'] as String?,
      );
      break;
    case 'Connected':
      _applyConnectedDeviceFromPayload(
        reader,
        data['device_type'] as String?,
        data['device_id'] as String?,
        data['device_name'] as String?,
      );
      _invalidateEquipmentSyncProviders(reader);
      break;
    case 'Disconnected':
      _applyDeviceDisconnectedFromSyncPayload(reader, data);
      _invalidateEquipmentSyncProviders(reader);
      break;
  }
}

void _invalidateEquipmentSyncProviders(Object reader) {
  _invalidate(reader, equipmentProfilesProvider);
  _invalidate(reader, unifiedDiscoveryProvider);
}

Future<void> _applyGuidingEvent(
  Object reader,
  NightshadeEvent event, {
  NetworkBackend? networkBackend,
}) async {
  switch (event.eventType) {
    case 'Connected':
      final notifier = _readDeviceNotifier(reader, DeviceType.guider);
      if (!_isDeviceAlreadyConnected(
          reader, DeviceType.guider, 'phd2_guider')) {
        notifier.setConnecting('phd2_guider', 'PHD2');
      }
      notifier.setConnected();
      break;
    case 'Disconnected':
      _readDeviceNotifier(reader, DeviceType.guider).setDisconnected();
      break;
    case 'GuidingStarted':
    case 'GuidingStopped':
    case 'AppState':
      if (networkBackend != null) {
        await _hydratePhd2GuiderState(reader, networkBackend);
      }
      break;
  }
}

void _applySequencerEvent(
  Object reader,
  NightshadeEvent event, {
  NetworkBackend? networkBackend,
}) {
  final progressNotifier = _read(reader, sequenceProgressProvider.notifier);
  final data = event.data;

  switch (event.eventType) {
    case 'SequenceStarted':
      final sequenceName = data['sequence_name'] as String? ?? 'Unknown';
      progressNotifier.updateState(SequenceExecutionState.running);
      progressNotifier.updateProgress(
          message: 'Started sequence: $sequenceName');
      _read(reader, sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      break;
    case 'SequencePaused':
      progressNotifier.updateState(SequenceExecutionState.paused);
      _read(reader, sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.paused;
      break;
    case 'SequenceResumed':
      progressNotifier.updateState(SequenceExecutionState.running);
      _read(reader, sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      break;
    case 'SequenceStopped':
      progressNotifier.updateState(SequenceExecutionState.idle);
      _read(reader, sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.idle;
      break;
    case 'SequenceCompleted':
      progressNotifier.updateState(SequenceExecutionState.completed);
      _read(reader, sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.completed;
      break;
    case 'NodeStarted':
      progressNotifier.updateProgress(
        currentNodeId: data['node_id'] as String? ?? '',
        currentNodeName: data['node_type'] as String? ?? '',
        currentNodeStatus: NodeStatus.running,
      );
      break;
    case 'ProgressUpdated':
    case 'InstructionProgress':
      if (networkBackend != null) {
        unawaited(_refreshSequencerStatus(reader, networkBackend));
      }
      break;
    case sequenceUpdatedEventType:
      _invalidateSequenceLibrary(
        reader,
        sequenceId: data['sequenceId'] as int?,
      );
      break;
  }
}

void _applyHostMutation(
  Object reader,
  Map<String, dynamic> data,
) {
  final entityType = data['entityType'] as String?;
  final action = data['action'] as String?;
  if (entityType == null || action == null) {
    return;
  }

  switch (entityType) {
    case HostMutationEntity.equipment:
      _applyEquipmentMutationFromHost(reader, action, data);
    case HostMutationEntity.guider:
      _applyGuiderMutationFromHost(reader, action, data);
    case HostMutationEntity.framing:
      _applyFramingMutationFromHost(reader, action, data);
    case HostMutationEntity.sequencer:
      _applySequencerMutationFromHost(reader, action, data);
    case HostMutationEntity.profile:
    case HostMutationEntity.settings:
      _invalidateHostProfiles(reader);
    case HostMutationEntity.sequence:
      _invalidateSequenceLibrary(reader, sequenceId: _parseSequenceId(data));
    case HostMutationEntity.target:
      _invalidateHostTargets(reader);
      _invalidateSequenceLibrary(reader);
    case HostMutationEntity.session:
      _invalidateHostSessions(reader);
    case HostMutationEntity.capturedImage:
      _invalidateHostCapturedImages(reader);
    default:
      break;
  }
}

void _applyEquipmentMutationFromHost(
  Object reader,
  String action,
  Map<String, dynamic> data,
) {
  final deviceTypeStr = data['deviceType'] as String?;
  final deviceId = data['deviceId'] as String? ?? '';
  final deviceName = data['deviceName'] as String? ?? deviceId;

  final parsed = deviceTypeStr == null ? null : _parseDeviceType(deviceTypeStr);
  if (parsed == null) {
    return;
  }

  switch (action) {
    case HostMutationAction.connected:
      final notifier = _readDeviceNotifier(reader, parsed);
      if (!_isDeviceAlreadyConnected(reader, parsed, deviceId)) {
        notifier.setConnecting(deviceId, deviceName);
      }
      notifier.setConnected();
    case HostMutationAction.disconnected:
      _readDeviceNotifier(reader, parsed).setDisconnected();
    default:
      break;
  }
}

void _applyGuiderMutationFromHost(
  Object reader,
  String action,
  Map<String, dynamic> data,
) {
  final notifier = _readDeviceNotifier(reader, DeviceType.guider);
  switch (action) {
    case HostMutationAction.connected:
      if (!_isDeviceAlreadyConnected(
          reader, DeviceType.guider, 'phd2_guider')) {
        notifier.setConnecting('phd2_guider', 'PHD2');
      }
      notifier.setConnected();
    case HostMutationAction.disconnected:
      notifier.setDisconnected();
    case HostMutationAction.started:
    case HostMutationAction.stopped:
    case HostMutationAction.paused:
    case HostMutationAction.resumed:
      notifier.setConnected();
    default:
      final state = data['state'] as String?;
      if (state != null && state.isNotEmpty) {
        notifier.setConnected();
      }
  }
}

void _applyFramingMutationFromHost(
  Object reader,
  String action,
  Map<String, dynamic> data,
) {
  if (action != HostMutationAction.updated &&
      action != HostMutationAction.created) {
    return;
  }

  final ra = data['ra'];
  final dec = data['dec'];
  final name = data['name'] as String?;
  if (ra is! num || dec is! num) {
    return;
  }

  _read(reader, framingProvider.notifier).setTargetCoordinates(
    ra.toDouble(),
    dec.toDouble(),
    name: name,
  );
}

void _applySequencerMutationFromHost(
  Object reader,
  String action,
  Map<String, dynamic> data,
) {
  SequenceExecutionState mapped;
  switch (action) {
    case HostMutationAction.started:
      mapped = SequenceExecutionState.running;
    case HostMutationAction.paused:
      mapped = SequenceExecutionState.paused;
    case HostMutationAction.resumed:
      mapped = SequenceExecutionState.running;
    case HostMutationAction.stopped:
      mapped = SequenceExecutionState.idle;
    default:
      final rawState = data['state'] as String?;
      if (rawState == null) {
        return;
      }
      mapped = _mapSequencerState(rawState);
  }

  _read(reader, sequenceExecutionStateProvider.notifier).state = mapped;
  _read(reader, sequenceProgressProvider.notifier).updateState(mapped);

  final message = data['message'] as String?;
  if (message != null) {
    _read(reader, sequenceProgressProvider.notifier)
        .updateProgress(message: message);
  }
}

int? _parseSequenceId(Map<String, dynamic> data) {
  final raw = data['entityId'] ?? data['sequenceId'];
  if (raw is int) {
    return raw;
  }
  if (raw is String) {
    return int.tryParse(raw);
  }
  return null;
}

void _invalidateSequenceLibrary(
  Object reader, {
  int? sequenceId,
}) {
  _invalidate(reader, savedSequencesProvider);
  if (sequenceId != null && reader is Ref) {
    unawaited(reloadOpenSequenceIfIdle(reader, sequenceId));
  }
}

void _invalidateHostProfiles(Object reader) {
  _invalidateEquipmentSyncProviders(reader);
  _invalidate(reader, allProfilesProvider);
  _invalidate(reader, activeProfileProvider);
}

void _invalidateHostTargets(Object reader) {
  _invalidate(reader, allDbTargetsProvider);
  _invalidate(reader, favoriteDbTargetsProvider);
  _invalidateTargetProgress(reader);
}

void _invalidateHostCapturedImages(Object reader) {
  _invalidate(reader, allDbImagesProvider);
  _invalidate(reader, capturedImageByIdProvider);
  _invalidateTargetProgress(reader);
}

void _invalidateHostSessions(Object reader) {
  _invalidate(reader, allSessionsProvider);
  _invalidate(reader, incompleteSessionsProvider);
  _invalidate(reader, sessionStateProvider);
}

void _invalidateTargetProgress(Object reader) {
  _invalidate(reader, allTargetProgressProvider);
  _invalidate(reader, targetProgressProvider);
}

Future<void> _refreshSequencerStatus(
  Object reader,
  NetworkBackend backend,
) async {
  try {
    final status = await backend.sequencerGetStatus();
    _applySequencerStatus(reader, status);
  } catch (_) {
    // Fail closed on the event path — hydration/polling will recover.
  }
}

void _applyFramingTargetChanged(Object reader, NightshadeEvent event) {
  final ra = (event.data['ra'] as num?)?.toDouble();
  final dec = (event.data['dec'] as num?)?.toDouble();
  final name = event.data['name'] as String?;
  if (ra == null || dec == null || name == null || name.isEmpty) {
    return;
  }

  _read(reader, framingProvider.notifier).setTargetCoordinates(
    ra,
    dec,
    name: name,
  );
}

void _applyDeviceConnectedFromSyncPayload(
  Object reader,
  Map<String, dynamic> data,
) {
  _applyConnectedDeviceFromPayload(
    reader,
    data['device_type'] as String? ?? data['deviceType'] as String?,
    data['device_id'] as String? ?? data['deviceId'] as String?,
    data['device_name'] as String? ?? data['deviceName'] as String?,
  );
}

void _applyDeviceDisconnectedFromSyncPayload(
  Object reader,
  Map<String, dynamic> data,
) {
  final deviceType =
      data['device_type'] as String? ?? data['deviceType'] as String?;
  if (deviceType == null) {
    return;
  }

  switch (deviceType.toLowerCase()) {
    case 'camera':
      _readDeviceNotifier(reader, DeviceType.camera).setDisconnected();
      break;
    case 'mount':
      _readDeviceNotifier(reader, DeviceType.mount).setDisconnected();
      break;
    case 'focuser':
      _readDeviceNotifier(reader, DeviceType.focuser).setDisconnected();
      break;
    case 'filterwheel':
    case 'filter wheel':
      _readDeviceNotifier(reader, DeviceType.filterWheel).setDisconnected();
      break;
    case 'guider':
      _readDeviceNotifier(reader, DeviceType.guider).setDisconnected();
      break;
    case 'rotator':
      _readDeviceNotifier(reader, DeviceType.rotator).setDisconnected();
      break;
    case 'dome':
      _readDeviceNotifier(reader, DeviceType.dome).setDisconnected();
      break;
    case 'weather':
      _readDeviceNotifier(reader, DeviceType.weather).setDisconnected();
      break;
    case 'safetymonitor':
    case 'safety monitor':
      _readDeviceNotifier(reader, DeviceType.safetyMonitor).setDisconnected();
      break;
    case 'covercalibrator':
    case 'cover calibrator':
      _readDeviceNotifier(reader, DeviceType.coverCalibrator).setDisconnected();
      break;
  }
}

void _applyConnectingDevice(
  Object reader,
  String? deviceType,
  String? deviceId,
  String? deviceName,
) {
  if (deviceType == null || deviceId == null) {
    return;
  }

  final parsed = _parseDeviceType(deviceType);
  if (parsed == null) {
    return;
  }

  final notifier = _readDeviceNotifier(reader, parsed);
  if (!_isDeviceAlreadyConnected(reader, parsed, deviceId)) {
    notifier.setConnecting(deviceId, deviceName ?? deviceId);
  }
}

void _applyConnectedDeviceFromPayload(
  Object reader,
  String? deviceType,
  String? deviceId,
  String? deviceName,
) {
  if (deviceType == null || deviceId == null) {
    return;
  }

  final parsed = _parseDeviceType(deviceType);
  if (parsed == null) {
    return;
  }

  final notifier = _readDeviceNotifier(reader, parsed);
  if (!_isDeviceAlreadyConnected(reader, parsed, deviceId)) {
    notifier.setConnecting(deviceId, deviceName ?? deviceId);
  }
  notifier.setConnected();
}

DeviceType? _parseDeviceType(String raw) {
  switch (raw.toLowerCase()) {
    case 'camera':
      return DeviceType.camera;
    case 'mount':
      return DeviceType.mount;
    case 'focuser':
      return DeviceType.focuser;
    case 'filterwheel':
    case 'filter wheel':
      return DeviceType.filterWheel;
    case 'guider':
      return DeviceType.guider;
    case 'rotator':
      return DeviceType.rotator;
    case 'dome':
      return DeviceType.dome;
    case 'weather':
      return DeviceType.weather;
    case 'safetymonitor':
    case 'safety monitor':
      return DeviceType.safetyMonitor;
    case 'covercalibrator':
    case 'cover calibrator':
      return DeviceType.coverCalibrator;
    case 'switch':
    case 'switch_':
      return DeviceType.switch_;
    default:
      return null;
  }
}

dynamic _readDeviceNotifier(Object reader, DeviceType deviceType) {
  switch (deviceType) {
    case DeviceType.camera:
      return _read(reader, cameraStateProvider.notifier);
    case DeviceType.mount:
      return _read(reader, mountStateProvider.notifier);
    case DeviceType.focuser:
      return _read(reader, focuserStateProvider.notifier);
    case DeviceType.filterWheel:
      return _read(reader, filterWheelStateProvider.notifier);
    case DeviceType.guider:
      return _read(reader, guiderStateProvider.notifier);
    case DeviceType.rotator:
      return _read(reader, rotatorStateProvider.notifier);
    case DeviceType.dome:
      return _read(reader, domeStateProvider.notifier);
    case DeviceType.weather:
      return _read(reader, weatherStateProvider.notifier);
    case DeviceType.safetyMonitor:
      return _read(reader, safetyMonitorStateProvider.notifier);
    case DeviceType.coverCalibrator:
      return _read(reader, coverCalibratorStateProvider.notifier);
    case DeviceType.switch_:
      // DEV-P2-1: switch device now has a first-class connection notifier.
      return _read(reader, switchStateProvider.notifier);
  }
}

dynamic _readDeviceState(Object reader, DeviceType deviceType) {
  switch (deviceType) {
    case DeviceType.camera:
      return _read(reader, cameraStateProvider);
    case DeviceType.mount:
      return _read(reader, mountStateProvider);
    case DeviceType.focuser:
      return _read(reader, focuserStateProvider);
    case DeviceType.filterWheel:
      return _read(reader, filterWheelStateProvider);
    case DeviceType.guider:
      return _read(reader, guiderStateProvider);
    case DeviceType.rotator:
      return _read(reader, rotatorStateProvider);
    case DeviceType.dome:
      return _read(reader, domeStateProvider);
    case DeviceType.weather:
      return _read(reader, weatherStateProvider);
    case DeviceType.safetyMonitor:
      return _read(reader, safetyMonitorStateProvider);
    case DeviceType.coverCalibrator:
      return _read(reader, coverCalibratorStateProvider);
    case DeviceType.switch_:
      return _read(reader, switchStateProvider);
  }
}

bool _isDeviceAlreadyConnected(
  Object reader,
  DeviceType deviceType,
  String deviceId,
) {
  final state = _readDeviceState(reader, deviceType);
  return state.connectionState == DeviceConnectionState.connected &&
      state.deviceId == deviceId;
}

T _read<T>(Object reader, ProviderListenable<T> provider) {
  if (reader is Ref) {
    return reader.read(provider);
  }
  if (reader is ProviderContainer) {
    return reader.read(provider);
  }
  throw ArgumentError.value(
    reader,
    'reader',
    'Expected Ref or ProviderContainer',
  );
}

void _invalidate(Object reader, ProviderOrFamily provider) {
  if (reader is Ref) {
    reader.invalidate(provider);
    return;
  }
  if (reader is ProviderContainer) {
    reader.invalidate(provider);
    return;
  }
  throw ArgumentError.value(
    reader,
    'reader',
    'Expected Ref or ProviderContainer',
  );
}

void _applySequencerStatus(Object reader, SequencerStatus status) {
  final mapped = _mapSequencerState(status.state);
  _read(reader, sequenceExecutionStateProvider.notifier).state = mapped;
  _read(reader, sequenceProgressProvider.notifier).updateState(mapped);
  _read(reader, sequenceProgressProvider.notifier).updateProgress(
    message: status.message,
    currentNodeId: status.currentNodeId,
    currentNodeName: status.currentNodeName,
  );
}

SequenceExecutionState _mapSequencerState(String rawState) {
  switch (rawState.toLowerCase()) {
    case 'running':
      return SequenceExecutionState.running;
    case 'paused':
      return SequenceExecutionState.paused;
    case 'stopping':
      return SequenceExecutionState.stopping;
    case 'completed':
      return SequenceExecutionState.completed;
    case 'failed':
    case 'error':
      return SequenceExecutionState.failed;
    case 'recovering':
      return SequenceExecutionState.paused;
    case 'idle':
    case 'stopped':
    default:
      return SequenceExecutionState.idle;
  }
}

void _clearLocalDeviceState(Object reader, {bool includeGuider = false}) {
  _readDeviceNotifier(reader, DeviceType.camera).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.mount).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.focuser).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.filterWheel).setDisconnected();
  if (includeGuider) {
    _readDeviceNotifier(reader, DeviceType.guider).setDisconnected();
  }
  _readDeviceNotifier(reader, DeviceType.rotator).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.dome).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.weather).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.safetyMonitor).setDisconnected();
  _readDeviceNotifier(reader, DeviceType.coverCalibrator).setDisconnected();
}

Future<void> _hydratePhd2GuiderState(
  Object reader,
  NetworkBackend backend,
) async {
  final notifier = _readDeviceNotifier(reader, DeviceType.guider);
  final priorState = _read(reader, guiderStateProvider);

  try {
    final status = await pollPhd2Connected(
      backend,
      timeout: const Duration(seconds: 5),
      interval: const Duration(milliseconds: 250),
    );
    if (!status.connected) {
      if (isPhd2GuiderDeviceId(priorState.deviceId)) {
        notifier.setDisconnected();
      }
      return;
    }
    if (!_isDeviceAlreadyConnected(reader, DeviceType.guider, 'phd2_guider')) {
      notifier.setConnecting('phd2_guider', 'PHD2');
    }
    notifier.setConnected();
  } catch (_) {
    // Do not clear a PHD2 guider restored from getConnectedDevices when the
    // status endpoint is briefly unavailable during host launch.
  }
}

void _applyConnectedDevice(Object reader, DeviceInfo device) {
  final notifier = _readDeviceNotifier(reader, device.deviceType);
  if (!_isDeviceAlreadyConnected(reader, device.deviceType, device.id)) {
    notifier.setConnecting(device.id, device.name);
  }
  notifier.setConnected();
}

/// Full session hydration for remote companions (and reconnect recovery).
Future<void> hydrateRemoteSessionState(
  Object reader,
  NetworkBackend backend,
) async {
  final status = await backend.sequencerGetStatus();
  _applySequencerStatus(reader, status);

  final devices = await backend.getConnectedDevices();
  // PHD2 is not always listed in getConnectedDevices(); avoid clearing the
  // guider chip before we re-hydrate from phd2/status.
  _clearLocalDeviceState(reader);
  for (final device in devices) {
    _applyConnectedDevice(reader, device);
  }

  await _hydratePhd2GuiderState(reader, backend);
  _invalidateEquipmentSyncProviders(reader);
  backend.invalidateDeviceCache();
  _invalidate(reader, savedSequencesProvider);
}
