import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../models/backend/device_info.dart';
import '../models/backend/device_status.dart';
import '../models/backend/device_types.dart';
import '../models/backend/event_types.dart';
import '../models/backend/sequencer_status.dart';
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../models/sequence/sequence_models.dart';
import '../models/backend/host_mutation_event.dart';
import '../models/imaging/imaging_models.dart'
    show CapturePreviewSource, ExposureSettings;
import '../services/capture_preview_loader.dart'
    show capturePreviewPublisherProvider, capturedImageDataFromResult;
import '../services/imaging_service.dart' show exposureProgressProvider;
import '../services/phd2_status_poll.dart';
import '../services/sequence_file_service.dart'
    show sequenceFileServiceProvider;
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'framing_provider.dart';
import 'imaging_provider.dart' show exposureSettingsProvider;
import 'profiles_provider.dart';
import 'remote_sync_events.dart';
import 'scheduler_provider.dart' show schedulerPreviewDecisionProvider;
import 'sequence_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart' show appSettingsProvider;
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
      await _applySystemSyncEvent(
        reader,
        event,
        networkBackend: networkBackend,
      );
      break;
    case EventCategory.equipment:
      _applyEquipmentEvent(reader, event, networkBackend: networkBackend);
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
      // Remote parity: the host-local capture path publishes
      // `currentImageProvider` via [CapturePreviewPublisher]; that path never
      // runs on a remote companion (NetworkBackend, no local executor), so the
      // dashboard's "current frame" hero tile would stay blank during a
      // host-run sequence. When the host reports a fresh frame, pull it over
      // the existing remoted JPEG path and publish it locally so the tile +
      // histogram/stats update exactly as they do on the host.
      //
      // `ImageReady` is the canonical "host has a freshly decoded frame"
      // event (carries width/height); `ImageSaved`/`ImageCaptured` are also
      // accepted so the tile still populates if the ready event is missed.
      if (networkBackend != null &&
          (event.eventType == 'ImageReady' ||
              event.eventType == 'ImageSaved' ||
              event.eventType == 'ImageCaptured')) {
        unawaited(_publishRemoteCurrentFrame(reader, networkBackend));
      }
      // Slave-only: mirror the master's per-frame exposure countdown onto the
      // camera card + exposure-progress dashboard. These imaging events drive
      // [cameraStateProvider.setExposing] / [exposureProgressProvider] exactly
      // as ImagingService does on the host (whose capture loop never runs on a
      // remote companion), so the slave's "Exposing" status and the remaining-
      // time countdown track the master frame-for-frame.
      if (networkBackend != null) {
        _applyExposureMirror(reader, event.eventType, event.data);
      }
      break;
    case EventCategory.safety:
    case EventCategory.polarAlignment:
    case EventCategory.job:
    case EventCategory.session:
    case EventCategory.catalog:
      // /// no remote-sync invalidations needed; these
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

void _applyEquipmentEvent(
  Object reader,
  NightshadeEvent event, {
  NetworkBackend? networkBackend,
}) {
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
      // Do NOT invalidate equipmentProfilesProvider here. A device
      // connecting/disconnecting does not change the profile LIST or the active
      // profile, but on a slave equipmentProfilesProvider is network-backed:
      // invalidating it round-trips to the host and cascades through
      // opticalConfigProvider -> tonightSuggestionsProvider, so doing it on
      // every mirrored Connected/Disconnected event made "Plan Tonight" thrash
      // (constant refresh). Connection STATE is already applied above via the
      // per-device state providers. Profile refreshes happen on actual profile
      // events (profileChanged / HostMutationEntity.profile) instead.
      break;
    case 'Disconnected':
      _applyDeviceDisconnectedFromSyncPayload(reader, data);
      break;
    default:
      // Live telemetry mirroring is SLAVE-ONLY: on the host both
      // DeviceService.event_handling AND host_local_sync run, so applying
      // these here when networkBackend == null (the host path) would
      // double-apply state DeviceService already wrote. The slave is a pure
      // observer with no DeviceService, so networkBackend != null cleanly
      // scopes this to the remote companion. Connection-state cases above
      // stay unconditional (they run on both host and slave).
      if (networkBackend != null) {
        _applyEquipmentTelemetry(reader, event.eventType, data);
      }
      break;
  }
}

/// Slave-only: mirror the master's per-frame exposure countdown by driving the
/// same notifiers [ImagingService] drives on the host. The host capture loop
/// never runs on a remote companion, so these imaging-category events are the
/// slave's only source for the camera card's "Exposing" status and the
/// remaining-time countdown. Payload keys match the host emitter
/// (`progress`/`remainingSecs`), with snake_case fallbacks for the
/// `ExposureStarted` frame fields.
void _applyExposureMirror(
  Object reader,
  String eventType,
  Map<String, dynamic> data,
) {
  final cameraNotifier = _read(reader, cameraStateProvider.notifier);
  final progressNotifier = _read(reader, exposureProgressProvider.notifier);
  switch (eventType) {
    case 'ExposureStarted':
    case 'ExposureStartedWithFrame':
      final duration =
          (data['durationSecs'] as num?)?.toDouble() ??
          (data['duration_secs'] as num?)?.toDouble() ??
          0.0;
      final frameNumber =
          (data['frameNumber'] as num?)?.toInt() ??
          (data['frame_number'] as num?)?.toInt() ??
          0;
      final totalFrames =
          (data['totalFrames'] as num?)?.toInt() ??
          (data['total_frames'] as num?)?.toInt();
      cameraNotifier.setExposing(true, progress: 0.0);
      if (duration > 0) {
        progressNotifier.startExposure(duration, frameNumber, totalFrames);
      }
      break;
    case 'ExposureProgress':
      final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
      final remaining =
          (data['remainingSecs'] as num?)?.toDouble() ??
          (data['remaining_secs'] as num?)?.toDouble() ??
          0.0;
      // The slave does not know the configured exposure time locally, so derive
      // elapsed defensively from progress + remaining.
      final total = (progress > 0.0 && progress < 1.0)
          ? remaining / (1.0 - progress)
          : null;
      final elapsed = total != null
          ? (total - remaining).clamp(0.0, total).toDouble()
          : 0.0;
      cameraNotifier.setExposing(true, progress: progress);
      progressNotifier.updateProgress(elapsed, remaining, progress * 100);
      break;
    case 'ExposureComplete':
    case 'ExposureCancelled':
      cameraNotifier.setExposing(false);
      break;
  }
}

/// Slave-only: mirror the master's live equipment telemetry into the same
/// per-device notifiers [DeviceService.event_handling] writes on the host, but
/// with NO reconnect / critical-device / heartbeat side effects (a remote
/// companion must never originate connect commands back to the host).
///
/// Event names + payload shapes are kept in lock-step with
/// `device_service/event_handling.dart`. Only camera/mount/focuser/filter-
/// wheel/rotator carry live values; dome/weather/safetyMonitor/coverCalibrator/
/// switch mirror CONNECTION STATE ONLY (no source telemetry events). The
/// per-frame exposure countdown is mirrored via the imaging-category
/// `ExposureStarted`/`ExposureProgress`/`ExposureComplete` events in
/// [_applyExposureMirror]; the current-frame hero tile is mirrored separately
/// via the imaging/current-frame path.
void _applyEquipmentTelemetry(
  Object reader,
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    // --- Camera temperature / cooling ------------------------------------
    case 'CameraTemperatureChanged':
      final temp = (data['temperature'] as num?)?.toDouble();
      final power = (data['coolerPower'] as num?)?.toDouble() ?? 0.0;
      if (temp != null) {
        _read(
          reader,
          cameraStateProvider.notifier,
        ).updateTemperature(temp, power);
      }
      break;
    case 'CameraCoolingStarted':
      final targetTemp = (data['target_temp'] as num?)?.toDouble();
      _read(reader, cameraStateProvider.notifier).setCooling(true);
      if (targetTemp != null) {
        _read(reader, cameraStateProvider.notifier).setTargetTemp(targetTemp);
      }
      break;
    case 'CameraCoolingReached':
      final temp = (data['temperature'] as num?)?.toDouble();
      if (temp != null) {
        _read(
          reader,
          cameraStateProvider.notifier,
        ).updateTemperature(temp, 0.0);
      }
      break;
    case 'CameraWarmingStarted':
      _read(reader, cameraStateProvider.notifier).setCooling(false);
      break;
    case 'CameraWarmingCompleted':
      // No additional state change (matches event_handling.dart).
      break;

    // --- Mount position / motion -----------------------------------------
    case 'MountPositionChanged':
      final ra = (data['ra'] as num?)?.toDouble();
      final dec = (data['dec'] as num?)?.toDouble();
      final alt = (data['altitude'] as num?)?.toDouble() ?? 0.0;
      final az = (data['azimuth'] as num?)?.toDouble() ?? 0.0;
      if (ra != null && dec != null) {
        _read(
          reader,
          mountStateProvider.notifier,
        ).updatePosition(ra, dec, alt, az);
      }
      if (data['isSlewing'] is bool) {
        _read(
          reader,
          mountStateProvider.notifier,
        ).setSlewing(data['isSlewing'] as bool);
      }
      if (data['isTracking'] is bool) {
        _read(
          reader,
          mountStateProvider.notifier,
        ).setTracking(data['isTracking'] as bool);
      }
      if (data['isParked'] is bool) {
        _read(
          reader,
          mountStateProvider.notifier,
        ).setParked(data['isParked'] as bool);
      }
      break;
    case 'MountSlewStarted':
      _read(reader, mountStateProvider.notifier).setSlewing(true);
      break;
    case 'MountSlewCompleted':
      _read(reader, mountStateProvider.notifier).setSlewing(false);
      final ra = (data['ra'] as num?)?.toDouble();
      final dec = (data['dec'] as num?)?.toDouble();
      if (ra != null && dec != null) {
        _read(
          reader,
          mountStateProvider.notifier,
        ).updatePosition(ra, dec, 0.0, 0.0);
      }
      break;
    case 'MountTrackingStarted':
      _read(reader, mountStateProvider.notifier).setTracking(true);
      break;
    case 'MountTrackingStopped':
      _read(reader, mountStateProvider.notifier).setTracking(false);
      break;
    case 'MountParkStarted':
      _read(reader, mountStateProvider.notifier).setSlewing(true);
      break;
    case 'MountParkCompleted':
      _read(reader, mountStateProvider.notifier).setSlewing(false);
      _read(reader, mountStateProvider.notifier).setParked(true);
      _read(reader, mountStateProvider.notifier).setTracking(false);
      break;
    case 'MountUnparked':
      _read(reader, mountStateProvider.notifier).setParked(false);
      break;

    // --- Focuser ----------------------------------------------------------
    case 'FocuserMoveStarted':
      _read(reader, focuserStateProvider.notifier).setMoving(true);
      break;
    case 'FocuserMoveCompleted':
      _read(reader, focuserStateProvider.notifier).setMoving(false);
      final position = data['position'] as int?;
      if (position != null) {
        _read(reader, focuserStateProvider.notifier).updatePosition(position);
      }
      break;
    case 'FocuserTemperatureChanged':
      final temperature = (data['temperature'] as num?)?.toDouble();
      if (temperature != null) {
        _read(
          reader,
          focuserStateProvider.notifier,
        ).updateTemperature(temperature);
      }
      break;
    case 'FocuserPositionChanged':
      final focuserPosition = data['position'] as int?;
      if (focuserPosition != null) {
        _read(
          reader,
          focuserStateProvider.notifier,
        ).updatePosition(focuserPosition);
      }
      final focuserMoving = data['isMoving'] as bool?;
      if (focuserMoving != null) {
        _read(reader, focuserStateProvider.notifier).setMoving(focuserMoving);
      }
      final focuserTemp = (data['temperature'] as num?)?.toDouble();
      if (focuserTemp != null) {
        _read(
          reader,
          focuserStateProvider.notifier,
        ).updateTemperature(focuserTemp);
      }
      break;

    // --- Filter wheel -----------------------------------------------------
    case 'FilterChanging':
      _read(reader, filterWheelStateProvider.notifier).setMoving(true);
      break;
    case 'FilterChanged':
      _read(reader, filterWheelStateProvider.notifier).setMoving(false);
      final position = data['position'] as int?;
      if (position != null) {
        _read(
          reader,
          filterWheelStateProvider.notifier,
        ).updatePosition(position);
      }
      break;
    case 'FilterWheelPositionChanged':
      final filterPosition = data['position'] as int?;
      if (filterPosition != null) {
        _read(
          reader,
          filterWheelStateProvider.notifier,
        ).updatePosition(filterPosition);
      }
      final filterMoving = data['isMoving'] as bool?;
      if (filterMoving != null) {
        _read(
          reader,
          filterWheelStateProvider.notifier,
        ).setMoving(filterMoving);
      }
      break;

    // --- Rotator ----------------------------------------------------------
    case 'RotatorMoveStarted':
      _read(reader, rotatorStateProvider.notifier).setMoving(true);
      break;
    case 'RotatorMoveCompleted':
      _read(reader, rotatorStateProvider.notifier).setMoving(false);
      final angle = (data['angle'] as num?)?.toDouble();
      if (angle != null) {
        _read(reader, rotatorStateProvider.notifier).updatePosition(angle);
      }
      break;
  }
}

void _invalidateEquipmentSyncProviders(Object reader) {
  _invalidate(reader, equipmentProfilesProvider);
  // Deliberately NOT invalidating unifiedDiscoveryProvider here. It is a
  // StateNotifier whose state resets to an EMPTY device list on invalidation
  // and does not auto-rediscover, so invalidating it on every remote
  // Connected/Disconnected event wipes the user's scanned "Available Devices"
  // list (the whole panel goes blank the instant they connect a device in
  // remote-client mode). Device connection *status* is tracked by the
  // per-class device state providers (updated above via the sync payload),
  // not by the discovery list, so the discovered set is stable across
  // connect/disconnect and must be left intact.
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
        reader,
        DeviceType.guider,
        'phd2_guider',
      )) {
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
        message: 'Started sequence: $sequenceName',
      );
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
      // A new node/target means the host autopilot's live pick likely changed;
      // refresh the mirrored preview so the slave's banner tracks the switch
      // (no-op when the banner isn't mounted — it's autoDispose).
      if (networkBackend != null) {
        _invalidate(reader, schedulerPreviewDecisionProvider);
      }
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

void _applyHostMutation(Object reader, Map<String, dynamic> data) {
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
    case HostMutationEntity.sequenceEditor:
      _applySequenceEditorMirror(reader, action, data);
    case HostMutationEntity.profile:
      _invalidateHostProfiles(reader);
    case HostMutationEntity.settings:
      // Deliberately NOT invalidating anything per-event here. The host
      // broadcasts `settings/updated` at very high frequency — the scheduler
      // persists runtime config (e.g. conditions_score) many times a second and
      // each persist emits a settings mutation (measured ~14/s on a live rig).
      // Reacting per-event reloaded the entire "Plan Tonight" Recommendation tab
      // dozens of times a second on a slave (it also previously, wrongly,
      // invalidated the equipment-PROFILE providers — a settings change is not a
      // profile change). appSettings is already re-pulled every 30s by
      // hydrateRemoteSessionState (and on reconnect), so a genuine settings
      // change mirrors within one poll cycle without the churn.
      break;
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
        reader,
        DeviceType.guider,
        'phd2_guider',
      )) {
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

  _read(
    reader,
    framingProvider.notifier,
  ).setTargetCoordinates(ra.toDouble(), dec.toDouble(), name: name);
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
    _read(
      reader,
      sequenceProgressProvider.notifier,
    ).updateProgress(message: message);
  }
}

/// SLAVE apply: mirror the master's OPEN sequence-editor canvas.
///
/// The master broadcasts its working/dirty open sequence via the
/// [HostMutationEntity.sequenceEditor] host-mutation (see
/// `masterSequenceEditorMirrorProvider`). Here the slave reflects it onto its
/// own [currentSequenceProvider] so the sequencer screen follows the master's
/// live canvas — not just re-saved library rows.
///
/// Guards (single-hardware-owner invariant; master is authoritative but never
/// silently clobbers a slave operator mid-edit):
///   * If the slave editor has unsaved edits ([CurrentSequenceNotifier.isDirty])
///     we SKIP the apply — same guard as [reloadOpenSequenceIfIdle].
///   * `cleared` empties the slave canvas to match the master closing its
///     editor.
/// Applies use `discardUnsaved: true` only after the isDirty guard has already
/// passed (the editor is clean), so no confirmed-clean work is lost.
void _applySequenceEditorMirror(
  Object reader,
  String action,
  Map<String, dynamic> data,
) {
  final editor = _read(reader, currentSequenceProvider.notifier);

  if (action == HostMutationAction.cleared) {
    // Don't wipe a slave operator's unsaved canvas just because the master
    // closed its editor.
    if (editor.isDirty) {
      return;
    }
    editor.clearSequence(discardUnsaved: true);
    return;
  }

  // Never clobber the slave operator's in-progress edits. The slave diverges
  // until it returns to a clean state, which is the documented master-
  // authoritative behavior.
  if (editor.isDirty) {
    return;
  }

  final rawSequence = data['sequence'];
  if (rawSequence is! Map) {
    return;
  }

  final Sequence parsed;
  try {
    final map = Map<String, dynamic>.from(rawSequence);
    var seq = _read(reader, sequenceFileServiceProvider).parseFromMap(map);
    final dbId = data['databaseId'];
    if (dbId is int) {
      seq = seq.copyWith(databaseId: dbId);
    }
    parsed = seq;
  } catch (_) {
    // Best-effort: a malformed mirror frame must not crash the slave's sync
    // loop. The next frame (or a library reload) will recover.
    return;
  }

  editor.loadSequence(parsed, discardUnsaved: true);
}

/// G2: seed the slave's sequencer canvas with the master's currently-open
/// editor sequence on connect.
///
/// The live master->slave editor mirror ([masterSequenceEditorMirrorProvider])
/// only emits on edit, so a slave connecting mid-session sees a blank canvas
/// until the next master edit. This fetches the master's open editor sequence
/// in the SAME payload shape that mirror broadcasts (`HostStateChanged` /
/// [HostMutationEntity.sequenceEditor]) and feeds it through the identical
/// [_applySequenceEditorMirror] apply path, so seed and live update share one
/// code path. Returns silently when no sequence is open host-side (the endpoint
/// reports `open: false`) or the endpoint is unavailable on an older host.
Future<void> _hydrateOpenEditorSequence(
  Object reader,
  NetworkBackend backend,
) async {
  final Map<String, dynamic>? payload;
  try {
    payload = await backend.getOpenEditorSequence();
  } catch (_) {
    // Older headless host without the endpoint, or a transient fetch error:
    // the live mirror still seeds the canvas on the master's next edit.
    return;
  }
  if (payload == null) {
    // No sequence open in the master's editor — leave the slave's canvas as-is
    // (don't clear, mirroring _applySequenceEditorMirror's dirty-safe behavior).
    return;
  }
  _applySequenceEditorMirror(
    reader,
    HostMutationAction.updated,
    payload,
  );
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

void _invalidateSequenceLibrary(Object reader, {int? sequenceId}) {
  _invalidate(reader, savedSequencesProvider);
  _invalidate(reader, savedSequenceSummariesProvider);
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

/// Guards against re-entrant / chatty frame fetches. Host frame events
/// (`ImageReady`, `ImageSaved`, `ImageCaptured`) often arrive back-to-back for
/// the same capture; we only ever want one in-flight `cameraGetLastImage` at a
/// time. A coalescing flag is sufficient here — a fresh frame event always
/// triggers another fetch once the prior one resolves, so we never miss the
/// latest frame, but we never stack redundant network round-trips either.
bool _remoteFrameFetchInFlight = false;
bool _remoteFrameFetchPending = false;

/// Remote-only: fetch the host's latest frame and publish it into
/// `currentImageProvider` so the dashboard cockpit "current frame" tile (and
/// its histogram/stats) updates during a host-run sequence.
///
/// Reuses the exact remoted path the Camera tab uses
/// ([NetworkBackend.cameraGetLastImage] → JPEG wire), builds the same
/// [CapturedImageData] shape via [capturedImageDataFromResult], and hands it to
/// the shared [CapturePreviewPublisher] so the remote source tag and background
/// raw-pixel load behave identically to a local capture.
Future<void> _publishRemoteCurrentFrame(
  Object reader,
  NetworkBackend backend,
) async {
  // Coalesce: if a fetch is already running, mark that another frame arrived
  // and let the current fetch re-run once on completion.
  if (_remoteFrameFetchInFlight) {
    _remoteFrameFetchPending = true;
    return;
  }
  _remoteFrameFetchInFlight = true;

  try {
    // The imaging events do not carry a device id; resolve the connected
    // camera from local equipment state (mirrored from the host).
    final cameraState = _read(reader, cameraStateProvider);
    final deviceId = cameraState.deviceId;
    if (deviceId == null ||
        cameraState.connectionState != DeviceConnectionState.connected) {
      return;
    }

    final result = await backend.cameraGetLastImage(deviceId);
    if (result == null) {
      // No frame cached host-side yet — leave the tile as-is.
      return;
    }

    DateTime capturedAt;
    try {
      capturedAt = DateTime.parse(result.timestamp);
    } catch (_) {
      capturedAt = DateTime.now();
    }

    // Mirror the operator's current exposure controls, but let the host's
    // reported exposure time win so the frame badge matches the real frame.
    final baseSettings = _read(reader, exposureSettingsProvider);
    final filterState = _readDeviceState(reader, DeviceType.filterWheel);
    final settings = ExposureSettings(
      exposureTime: result.exposureTime,
      gain: baseSettings.gain,
      offset: baseSettings.offset,
      binningX: baseSettings.binningX,
      binningY: baseSettings.binningY,
      filter: filterState.currentFilterName ?? baseSettings.filter,
      frameType: baseSettings.frameType,
      fastReadout: baseSettings.fastReadout,
      readoutModeIndex: baseSettings.readoutModeIndex,
    );

    final imageData = capturedImageDataFromResult(
      capturedImage: result,
      settings: settings,
      capturedAt: capturedAt,
      previewSource: CapturePreviewSource.remote,
    );

    // Publish through the shared publisher: it tags the source from the live
    // backend, schedules the background raw-pixel load, and writes both
    // `currentImageProvider` and `lastImageStatsProvider`.
    _read(
      reader,
      capturePreviewPublisherProvider,
    ).publish(reader, imageData, deviceId);
  } catch (_) {
    // Degrade gracefully: a failed/aborted fetch must never crash the event
    // pump or spam logs. The tile simply keeps its previous frame; the next
    // frame event will try again.
  } finally {
    _remoteFrameFetchInFlight = false;
    if (_remoteFrameFetchPending) {
      _remoteFrameFetchPending = false;
      unawaited(_publishRemoteCurrentFrame(reader, backend));
    }
  }
}

void _applyFramingTargetChanged(Object reader, NightshadeEvent event) {
  final ra = (event.data['ra'] as num?)?.toDouble();
  final dec = (event.data['dec'] as num?)?.toDouble();
  final name = event.data['name'] as String?;
  if (ra == null || dec == null || name == null || name.isEmpty) {
    return;
  }

  _read(
    reader,
    framingProvider.notifier,
  ).setTargetCoordinates(ra, dec, name: name);
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
      // Switch device now has a first-class connection notifier.
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
///
/// Makes the slave correct IMMEDIATELY on first connect and TELEMETRY-STABLE
/// across the 30s repoll: it never blanks a populated card. Per-device live
/// status is fetched into a LOCAL BUFFER first (each fetch wrapped in its own
/// try/catch, all run in parallel via [Future.wait]), then applied in a single
/// pass. On a per-device failure the prior telemetry for that device is left
/// intact — one slow device on a high-latency link can neither stall nor wipe
/// the others. Connection state is applied first so cards exist before live
/// values land.
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

  // Buffer-then-apply per-device live telemetry. Only camera/mount/focuser/
  // filterwheel/rotator expose a status GET; dome/weather/safetyMonitor/
  // coverCalibrator/switch mirror connection state only (no status endpoint).
  await _hydrateDeviceTelemetry(reader, backend, devices);

  // G3 (current-frame hero tile): seed the master's last cached frame on
  // connect. The host-local capture publisher never runs on a slave, so without
  // this the dashboard's "current frame" tile stays blank until the next
  // ImageReady event. _publishRemoteCurrentFrame resolves the connected camera
  // from the (now-hydrated) camera state and no-ops if none is connected or no
  // frame is cached host-side, so the guard mirrors the live-event path.
  final cameraState = _read(reader, cameraStateProvider);
  if (cameraState.connectionState == DeviceConnectionState.connected) {
    unawaited(_publishRemoteCurrentFrame(reader, backend));
  }

  // G2 (open sequence-editor canvas): seed the master's live/dirty editor
  // canvas. It otherwise mirrors only via edit-triggered WS frames, so a slave
  // connecting mid-edit shows a blank sequencer screen until the next master
  // edit. Fetch the master's currently-open editor sequence in the same payload
  // shape the live mirror emits and feed it through the existing apply path.
  await _hydrateOpenEditorSequence(reader, backend);

  await _hydratePhd2GuiderState(reader, backend);

  // Active-profile + populated cards parity at first connect: refetch the
  // profile providers from the (now SQLite-backed) host /api/profiles so the
  // slave's equipment screen reflects the master's real active profile
  // immediately, not only after the next 10s poll / profile mutation.
  _invalidateHostProfiles(reader);

  // Settings parity at first connect must not wait for the 10s poll: force a
  // re-pull of appSettingsProvider (its build() re-fetches backend.getSettings
  // in NetworkBackend mode). No-op cost on the host (settings are local there;
  // hydration only runs on the slave / on BackendReconnected).
  _invalidate(reader, appSettingsProvider);

  // Framing target is NOT seeded from framing/current-position here: that GET
  // returns the mount's current pointing (already mirrored via getMountStatus),
  // not a chosen framing target, and FramingNotifier.setTargetCoordinates would
  // clobber the real target + trigger a survey-image load + push back to the
  // host. Framing target parity flows through the framingTargetChanged event +
  // HostMutationEntity.framing path instead.

  _invalidateEquipmentSyncProviders(reader);
  backend.invalidateDeviceCache();
  _invalidate(reader, savedSequencesProvider);
  _invalidate(reader, savedSequenceSummariesProvider);

  // Mirror the host's autopilot pick on connect (and each 30s re-hydrate): in
  // NetworkBackend mode schedulerPreviewDecisionProvider re-fetches GET
  // /api/scheduler/preview, so the slave's autopilot banner shows the host's
  // real "what the rig would slew to next" instead of recomputing "nothing
  // eligible" against the slave's empty local catalog.
  _invalidate(reader, schedulerPreviewDecisionProvider);
}

/// Buffer-then-apply per-device live status for the connected equipment that
/// exposes a status GET. Each fetch is isolated in its own try/catch and run in
/// parallel; results are applied only after ALL fetches settle, so a failed or
/// slow device never blanks a card.
Future<void> _hydrateDeviceTelemetry(
  Object reader,
  NetworkBackend backend,
  List<DeviceInfo> devices,
) async {
  String? idFor(DeviceType type) =>
      devices.where((d) => d.deviceType == type).map((d) => d.id).firstOrNull;

  final cameraId = idFor(DeviceType.camera);
  final mountId = idFor(DeviceType.mount);
  final focuserId = idFor(DeviceType.focuser);
  final filterWheelId = idFor(DeviceType.filterWheel);
  final rotatorId = idFor(DeviceType.rotator);

  CameraStatus? cameraStatus;
  MountStatus? mountStatus;
  FocuserStatus? focuserStatus;
  FilterWheelStatus? filterWheelStatus;
  RotatorStatus? rotatorStatus;

  Future<void> fetchCamera() async {
    if (cameraId == null) return;
    try {
      cameraStatus = await backend.getCameraStatus(cameraId);
    } catch (_) {
      // Leave prior camera telemetry intact.
    }
  }

  Future<void> fetchMount() async {
    if (mountId == null) return;
    try {
      mountStatus = await backend.getMountStatus(mountId);
    } catch (_) {}
  }

  Future<void> fetchFocuser() async {
    if (focuserId == null) return;
    try {
      focuserStatus = await backend.getFocuserStatus(focuserId);
    } catch (_) {}
  }

  Future<void> fetchFilterWheel() async {
    if (filterWheelId == null) return;
    try {
      filterWheelStatus = await backend.getFilterWheelStatus(filterWheelId);
    } catch (_) {}
  }

  Future<void> fetchRotator() async {
    if (rotatorId == null) return;
    try {
      rotatorStatus = await backend.getRotatorStatus(rotatorId);
    } catch (_) {}
  }

  await Future.wait([
    fetchCamera(),
    fetchMount(),
    fetchFocuser(),
    fetchFilterWheel(),
    fetchRotator(),
  ]);

  // Single apply pass — no intervening clear, so cards never blank.
  final camera = cameraStatus;
  if (camera != null) {
    final notifier = _read(reader, cameraStateProvider.notifier);
    final temp = camera.sensorTemp;
    if (temp != null) {
      notifier.updateTemperature(temp, camera.coolerPower ?? 0.0);
    }
    notifier.setCooling(camera.coolerOn);
    final target = camera.targetTemp;
    if (target != null) {
      notifier.setTargetTemp(target);
    }
    // G4 (in-flight exposure): the fetched status already reports whether the
    // master is mid-exposure. Seed the Exposing flag the same way the live
    // ExposureStarted handler does so the card/status isn't stuck Idle on a
    // mid-session connect. Precise remaining-time legitimately waits for the
    // first live ExposureProgress tick; here we only flip the flag.
    if (camera.state == CameraState.exposing) {
      notifier.setExposing(true);
    }
  }

  final mount = mountStatus;
  if (mount != null) {
    final notifier = _read(reader, mountStateProvider.notifier);
    notifier.updatePosition(
      mount.rightAscension,
      mount.declination,
      mount.altitude,
      mount.azimuth,
    );
    notifier.setTracking(mount.tracking);
    notifier.setSlewing(mount.slewing);
    notifier.setParked(mount.parked);
    notifier.setTrackingRate(mount.trackingRate);
  }

  final focuser = focuserStatus;
  if (focuser != null) {
    final notifier = _read(reader, focuserStateProvider.notifier);
    notifier.updatePosition(focuser.position);
    notifier.setMoving(focuser.moving);
    final temp = focuser.temperature;
    if (temp != null) {
      notifier.updateTemperature(temp);
    }
  }

  final filterWheel = filterWheelStatus;
  if (filterWheel != null) {
    final notifier = _read(reader, filterWheelStateProvider.notifier);
    notifier.updatePosition(filterWheel.position);
    notifier.setMoving(filterWheel.moving);
    // The fetched status already carries the wheel's filter names; apply them
    // so the slave shows the filter list (not just the position). Without this
    // the names were fetched and silently dropped, leaving filterNames empty on
    // the slave. setConnected preserves position/state and merges the names.
    if (filterWheel.filterNames.isNotEmpty) {
      notifier.setConnected(filterNames: filterWheel.filterNames);
    }
  }

  final rotator = rotatorStatus;
  if (rotator != null) {
    final notifier = _read(reader, rotatorStateProvider.notifier);
    notifier.updatePosition(
      rotator.position,
      mechanicalPosition: rotator.mechanicalPosition,
    );
    notifier.setMoving(rotator.moving || rotator.isMoving);
  }
}
