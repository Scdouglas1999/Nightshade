import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

import '../models/backend/event_types.dart' as core;

/// Reconstructs a typed [bridge.NightshadeEvent] from the collapsed
/// [core.NightshadeEvent] envelope that [FfiBackend] emits onto
/// [NetworkBackend.eventStream] over WebSocket.
///
/// Remote subscribers (`nightshadeEventsProvider`, recovery bridge,
/// scheduler trigger stream) depend on the typed `EventPayload_*` shape;
/// this mapper closes the loop on the network path.
bridge.NightshadeEvent bridgeEventFromCoreEvent(core.NightshadeEvent event) {
  final payload = _payloadFromCoreEvent(event);
  return bridge.NightshadeEvent(
    eventId: BigInt.from(event.timestamp),
    timestamp: event.timestamp,
    severity: _bridgeSeverity(event.severity),
    category: _bridgeCategory(event.category),
    payload: payload,
  );
}

bridge.EventSeverity _bridgeSeverity(core.EventSeverity severity) {
  switch (severity) {
    case core.EventSeverity.info:
      return bridge.EventSeverity.info;
    case core.EventSeverity.warning:
      return bridge.EventSeverity.warning;
    case core.EventSeverity.error:
      return bridge.EventSeverity.error;
    case core.EventSeverity.critical:
      return bridge.EventSeverity.critical;
  }
}

bridge.EventCategory _bridgeCategory(core.EventCategory category) {
  switch (category) {
    case core.EventCategory.equipment:
      return bridge.EventCategory.equipment;
    case core.EventCategory.imaging:
      return bridge.EventCategory.imaging;
    case core.EventCategory.guiding:
      return bridge.EventCategory.guiding;
    case core.EventCategory.sequencer:
      return bridge.EventCategory.sequencer;
    case core.EventCategory.safety:
      return bridge.EventCategory.safety;
    case core.EventCategory.system:
      return bridge.EventCategory.system;
    case core.EventCategory.polarAlignment:
      return bridge.EventCategory.polarAlignment;
    case core.EventCategory.job:
    case core.EventCategory.session:
    case core.EventCategory.catalog:
      // These categories have no FRB bridge counterpart —
      // they are produced server-side and consumed via the headless API
      // (run-watch SSE / WS events), never round-tripped through the
      // bridge. Treat as system so any code paths that incidentally hit
      // _bridgeCategory don't lose the event, while keeping the bridge
      // schema unchanged.
      return bridge.EventCategory.system;
  }
}

bridge.EventPayload _payloadFromCoreEvent(core.NightshadeEvent event) {
  switch (event.category) {
    case core.EventCategory.sequencer:
      return bridge.EventPayload.sequencer(
        _sequencerEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.guiding:
      return bridge.EventPayload.guiding(
        _guidingEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.equipment:
      return bridge.EventPayload.equipment(
        _equipmentEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.safety:
      return bridge.EventPayload.safety(
        _safetyEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.system:
      return bridge.EventPayload.system(
        _systemEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.imaging:
      return bridge.EventPayload.imaging(
        _imagingEventFromCore(event.eventType, event.data),
      );
    case core.EventCategory.polarAlignment:
      return bridge.EventPayload.polarAlignment(
        bridge.PolarAlignmentEvent(
          azimuthError: _doubleField(event.data, 'azimuth_error'),
          altitudeError: _doubleField(event.data, 'altitude_error'),
          totalError: _doubleField(event.data, 'total_error'),
          currentRa: _doubleField(event.data, 'current_ra'),
          currentDec: _doubleField(event.data, 'current_dec'),
          targetRa: _doubleField(event.data, 'target_ra'),
          targetDec: _doubleField(event.data, 'target_dec'),
        ),
      );
    case core.EventCategory.job:
    case core.EventCategory.session:
    case core.EventCategory.catalog:
      // These categories live on the headless API side.
      // There is no matching FRB EventPayload variant; route through the
      // system payload so the bridge schema does not need to change.
      // The eventType + data carry the actual content unchanged.
      return bridge.EventPayload.system(
        _systemEventFromCore(event.eventType, event.data),
      );
  }
}

bridge.SequencerEvent _sequencerEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'Started':
      return bridge.SequencerEvent.started(
        sequenceName: data['sequence_name'] as String? ?? '',
      );
    case 'PhotometryFrame':
      // Rebuild the typed science-photometry frame variant from the wire
      // envelope serialized by `_extractSequencerEventInfo`. Mirrors that
      // branch field-for-field so remote (network-backend) subscribers receive
      // the same typed variant the local FFI path does.
      return bridge.SequencerEvent.photometryFrame(
        nodeId: data['node_id'] as String? ?? '',
        targetDesignation: data['target_designation'] as String? ?? '',
        referenceStars: _stringList(data, 'reference_stars'),
        frame: _intField(data, 'frame'),
        total: _intField(data, 'total'),
        filter: data['filter'] as String? ?? '',
        exposureSecs: _doubleField(data, 'exposure_secs'),
        airmass: _optionalDouble(data, 'airmass'),
        fwhmArcsec: _optionalDouble(data, 'fwhm_arcsec'),
        snr: _optionalDouble(data, 'snr'),
        mjdObs: _doubleField(data, 'mjd_obs'),
        frameStartUnix: _doubleField(data, 'frame_start_unix'),
        accepted: data['accepted'] as bool? ?? false,
        rejectReason: _optionalString(data, 'reject_reason'),
        reduceLive: data['reduce_live'] as bool? ?? false,
        applyDifferential: data['apply_differential'] as bool? ?? false,
      );
    case 'PhotometryCadenceBroken':
      return bridge.SequencerEvent.photometryCadenceBroken(
        nodeId: data['node_id'] as String? ?? '',
        frame: _intField(data, 'frame'),
        total: _intField(data, 'total'),
        gapSecs: _doubleField(data, 'gap_secs'),
        maxGapSecs: _doubleField(data, 'max_gap_secs'),
        cadenceBreaks: _intField(data, 'cadence_breaks'),
      );
    case 'PhotometrySummary':
      return bridge.SequencerEvent.photometrySummary(
        nodeId: data['node_id'] as String? ?? '',
        targetDesignation: data['target_designation'] as String? ?? '',
        filter: data['filter'] as String? ?? '',
        framesCaptured: _intField(data, 'frames_captured'),
        cadenceBreaks: _intField(data, 'cadence_breaks'),
        lastRejectReason: _optionalString(data, 'last_reject_reason'),
      );
    case 'RecoveryStarted':
      return bridge.SequencerEvent.recoveryStarted(
        startedAtIso: _stringField(data, 'started_at_iso'),
        causeKind: _stringField(data, 'cause_kind'),
        causeCustomLabel: _optionalString(data, 'cause_custom_label'),
        lastAttemptAtIso: _optionalString(data, 'last_attempt_at_iso'),
        attemptCount: _intField(data, 'attempt_count'),
        maxAttempts: _intField(data, 'max_attempts'),
        retryIntervalSecs: _doubleField(data, 'retry_interval_secs'),
        maxDurationSecs: _doubleField(data, 'max_duration_secs'),
        phase: _stringField(data, 'phase'),
        lastError: _optionalString(data, 'last_error'),
      );
    case 'RecoveryProgress':
      return bridge.SequencerEvent.recoveryProgress(
        startedAtIso: _stringField(data, 'started_at_iso'),
        causeKind: _stringField(data, 'cause_kind'),
        causeCustomLabel: _optionalString(data, 'cause_custom_label'),
        lastAttemptAtIso: _optionalString(data, 'last_attempt_at_iso'),
        attemptCount: _intField(data, 'attempt_count'),
        maxAttempts: _intField(data, 'max_attempts'),
        retryIntervalSecs: _doubleField(data, 'retry_interval_secs'),
        maxDurationSecs: _doubleField(data, 'max_duration_secs'),
        phase: _stringField(data, 'phase'),
        lastError: _optionalString(data, 'last_error'),
      );
    case 'RecoveryCompleted':
      return bridge.SequencerEvent.recoveryCompleted(
        startedAtIso: _stringField(data, 'started_at_iso'),
        causeKind: _stringField(data, 'cause_kind'),
        causeCustomLabel: _optionalString(data, 'cause_custom_label'),
        lastAttemptAtIso: _optionalString(data, 'last_attempt_at_iso'),
        attemptCount: _intField(data, 'attempt_count'),
        maxAttempts: _intField(data, 'max_attempts'),
        retryIntervalSecs: _doubleField(data, 'retry_interval_secs'),
        maxDurationSecs: _doubleField(data, 'max_duration_secs'),
        phase: _stringField(data, 'phase'),
        lastError: _optionalString(data, 'last_error'),
      );
    case 'RecoveryGaveUp':
      return bridge.SequencerEvent.recoveryGaveUp(
        startedAtIso: _stringField(data, 'started_at_iso'),
        causeKind: _stringField(data, 'cause_kind'),
        causeCustomLabel: _optionalString(data, 'cause_custom_label'),
        lastAttemptAtIso: _optionalString(data, 'last_attempt_at_iso'),
        attemptCount: _intField(data, 'attempt_count'),
        maxAttempts: _intField(data, 'max_attempts'),
        retryIntervalSecs: _doubleField(data, 'retry_interval_secs'),
        maxDurationSecs: _doubleField(data, 'max_duration_secs'),
        phase: _stringField(data, 'phase'),
        lastError: _optionalString(data, 'last_error'),
        abortedByUser: data['aborted_by_user'] as bool? ?? false,
      );
    default:
      return bridge.SequencerEvent.error(
        message: data['message'] as String? ?? eventType,
      );
  }
}

bridge.GuidingEvent _guidingEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'GuidingStarted':
      return const bridge.GuidingEvent.guidingStarted();
    case 'GuidingStopped':
      return const bridge.GuidingEvent.guidingStopped();
    case 'StarLost':
      return const bridge.GuidingEvent.lostStar();
    case 'SettleDone':
      return bridge.GuidingEvent.settled(
        rms: (data['rms'] as num?)?.toDouble() ?? 0.0,
      );
    case 'GuideStep':
      return bridge.GuidingEvent.correction(
        ra: (data['RADistance'] as num?)?.toDouble() ?? 0.0,
        dec: (data['DECDistance'] as num?)?.toDouble() ?? 0.0,
        raRaw: (data['RADistanceRaw'] as num?)?.toDouble() ?? 0.0,
        decRaw: (data['DECDistanceRaw'] as num?)?.toDouble() ?? 0.0,
      );
    case 'Connected':
      return const bridge.GuidingEvent.connected();
    case 'Disconnected':
      return const bridge.GuidingEvent.disconnected();
    case 'Paused':
      return const bridge.GuidingEvent.paused();
    case 'Resumed':
      return const bridge.GuidingEvent.resumed();
    case 'DitherStarted':
      return bridge.GuidingEvent.ditherStarted(
        pixels: (data['pixels'] as num?)?.toDouble() ?? 0.0,
      );
    case 'DitherCompleted':
      return const bridge.GuidingEvent.ditherCompleted();
    default:
      return const bridge.GuidingEvent.looping();
  }
}

bridge.EquipmentEvent _equipmentEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'MountParkCompleted':
      return const bridge.EquipmentEvent.mountParkCompleted();
    case 'MountUnparked':
      return const bridge.EquipmentEvent.mountUnparked();
    case 'MountParkStarted':
      return const bridge.EquipmentEvent.mountParkStarted();
    case 'MountTrackingStarted':
      return const bridge.EquipmentEvent.mountTrackingStarted();
    case 'MountTrackingStopped':
      return const bridge.EquipmentEvent.mountTrackingStopped();
    case 'Connected':
      return bridge.EquipmentEvent.connected(
        deviceType: _stringField(data, 'device_type'),
        deviceId: _stringField(data, 'device_id'),
      );
    case 'Disconnected':
      return bridge.EquipmentEvent.disconnected(
        deviceType: _stringField(data, 'device_type'),
        deviceId: _stringField(data, 'device_id'),
      );
    case 'PropertyChanged':
      // Hot-plug device_discovered / device_lost events
      // and other property changes ride the PropertyChanged channel. The
      // mapper rebuilds the typed variant verbatim so round-tripping
      // through WS does not lose the property name or value the
      // hotplug_event_bridge_provider depends on.
      return bridge.EquipmentEvent.propertyChanged(
        deviceType: _stringField(data, 'device_type'),
        deviceId: _stringField(data, 'device_id'),
        property: _stringField(data, 'property'),
        value: data['value'] as String? ?? '',
      );
    default:
      return bridge.EquipmentEvent.error(
        deviceType: _stringField(data, 'device_type'),
        deviceId: _stringField(data, 'device_id'),
        message: data['message'] as String? ?? eventType,
      );
  }
}

bridge.SafetyEvent _safetyEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'WeatherSafe':
      return const bridge.SafetyEvent.weatherSafe();
    case 'EmergencyStop':
      return bridge.SafetyEvent.emergencyStop(
        reason: data['reason'] as String? ?? 'Emergency stop',
      );
    default:
      return bridge.SafetyEvent.weatherUnsafe(
        reason:
            data['reason'] as String? ??
            data['message'] as String? ??
            eventType,
      );
  }
}

bridge.SystemEvent _systemEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'BackendReconnected':
      return const bridge.SystemEvent.initialized();
    case 'DiskSpaceLow':
      return bridge.SystemEvent.diskSpaceLow(
        availableGb: (data['available_gb'] as num?)?.toDouble() ?? 0.0,
      );
    default:
      return bridge.SystemEvent.error(
        message: data['message'] as String? ?? eventType,
      );
  }
}

bridge.ImagingEvent _imagingEventFromCore(
  String eventType,
  Map<String, dynamic> data,
) {
  switch (eventType) {
    case 'ExposureFailed':
      return bridge.ImagingEvent.exposureFailedOld(
        reason: data['reason'] as String? ?? 'Exposure failed',
      );
    default:
      return bridge.ImagingEvent.exposureComplete(
        success: data['success'] as bool? ?? true,
      );
  }
}

String _stringField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing required string field "$key" in event data');
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is String && value.isEmpty) return null;
  return value as String?;
}

int _intField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Missing required int field "$key" in event data');
}

double _doubleField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return 0.0;
}

double? _optionalDouble(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is num) return value.toDouble();
  return null;
}

List<String> _stringList(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const [];
}

/// Shared recovery field map for [FfiBackend._extractSequencerEventInfo]
/// and the inverse mapper above.
Map<String, dynamic> recoveryFieldsFromTyped({
  required String startedAtIso,
  required String causeKind,
  String? causeCustomLabel,
  String? lastAttemptAtIso,
  required int attemptCount,
  required int maxAttempts,
  required double retryIntervalSecs,
  required double maxDurationSecs,
  required String phase,
  String? lastError,
  bool? abortedByUser,
}) {
  return {
    'started_at_iso': startedAtIso,
    'cause_kind': causeKind,
    'cause_custom_label': causeCustomLabel,
    'last_attempt_at_iso': lastAttemptAtIso,
    'attempt_count': attemptCount,
    'max_attempts': maxAttempts,
    'retry_interval_secs': retryIntervalSecs,
    'max_duration_secs': maxDurationSecs,
    'phase': phase,
    'last_error': lastError,
    if (abortedByUser != null) 'aborted_by_user': abortedByUser,
  };
}
