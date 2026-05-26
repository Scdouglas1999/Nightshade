/// Event types for Nightshade backend communication.
///
/// These types are used to communicate events between the Rust backend
/// and Dart frontend, as well as across network boundaries for remote operation.

/// Event severity levels
enum EventSeverity {
  info,
  warning,
  error,
  critical,
}

// [Wave 6B settings sync] Canonical event-type string broadcast over the WS
// `/events` channel when a single setting changes on the headless host. The
// payload `data` map carries `{ key, value, changedAt }`. Distinct from the
// coarse `HostStateChanged + entityType: settings` envelope which only tells
// remote clients to refresh — `settings.changed` lets `AppSettingsNotifier`
// apply the delta in-place without a round-trip GET. Originating clients
// filter their own echoes by matching `correlatingCommandId` against the
// `commandId` they received in the POST /api/settings response.
const String settingsChangedEventType = 'settings.changed';

// Wave 6B (P2-1) — Hot-plug discovery wire event types. The Rust side
// publishes these as `EquipmentEvent::PropertyChanged { property:
// 'device_discovered' | 'device_lost', value: <json> }` (see
// `native/nightshade_native/bridge/src/hotplug.rs`). The Dart provider
// `hotplugEventBridgeProvider` watches the backend event stream for these
// types and invalidates the equipment discovery providers so the equipment
// screen refreshes without a manual pull-to-refresh. The `value` is a
// JSON-stringified map: `{ driver, deviceClass, id, name, displayName,
// uniqueId? }`.
const String deviceDiscoveredProperty = 'device_discovered';
const String deviceLostProperty = 'device_lost';

/// Event categories for filtering and routing
enum EventCategory {
  equipment,
  imaging,
  guiding,
  sequencer,
  safety,
  system,
  polarAlignment,

  /// P1-2/P1-3: long-running job lifecycle events (autofocus, plate-solve,
  /// center-on-target, polar alignment, mosaic plan, etc.). Events in this
  /// category carry `data: {jobId, operation, progress?, message?, result?,
  /// error?}` so clients can correlate progress and completion back to the
  /// originating `POST /api/.../start` response.
  job,

  /// P1-5: session-ownership lifecycle events. Broadcast when an operator
  /// claims, releases, is taken over, or is auto-released after a heartbeat
  /// timeout. `data: {clientId, clientName, reason?, previousOwner?}` so
  /// the displaced client can show a toast attribution.
  session,

  /// P1-12: catalog management lifecycle events. Broadcast for star/DSO/
  /// annotation catalog downloads, hash-verification runs, uninstall, and
  /// reload triggered via `/api/catalog/...`. `data` is event-specific —
  /// see [CatalogHandlers] for the per-event shape. Catalog ops are owned
  /// by the headless server (NOT the connecting client) so a freshly
  /// imaged Pi can be populated remotely without ever touching the host
  /// GUI.
  catalog,
}

/// Nightshade event for backend-to-frontend communication
class NightshadeEvent {
  final int timestamp;
  final EventSeverity severity;
  final EventCategory category;
  final String eventType;
  final Map<String, dynamic> data;

  /// P1-1: monotonic server-assigned sequence number, present on events
  /// emitted by the headless API server. Null when the event is constructed
  /// locally (FFI bridge, NetworkBackend synthetic events) or by a server
  /// that pre-dates this field.
  ///
  /// Pair `(serverInstanceId, seq)` uniquely identifies an event across
  /// server restarts so a reconnecting client knows whether to attempt
  /// replay from the ring buffer or call /api/run-watch/snapshot to
  /// rehydrate.
  final int? seq;

  /// P1-1: random UUID generated once at server start, mirrored onto every
  /// outbound event. A change in this value between two events tells the
  /// client the server has restarted and the local sequence cursor is
  /// stale.
  final String? serverInstanceId;

  /// P1-4: command-id of the originating REST POST that the server
  /// best-effort matched against this event. Null on events that have no
  /// matching command (e.g. background telemetry).
  final String? correlatingCommandId;

  const NightshadeEvent({
    required this.timestamp,
    required this.severity,
    required this.category,
    required this.eventType,
    required this.data,
    this.seq,
    this.serverInstanceId,
    this.correlatingCommandId,
  });

  /// Convert to JSON for wire protocol (WebSocket/HTTP)
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'severity': severity.name,
        'category': category.name,
        'eventType': eventType,
        'data': data,
        if (seq != null) 'seq': seq,
        if (serverInstanceId != null) 'serverInstanceId': serverInstanceId,
        if (correlatingCommandId != null)
          'correlatingCommandId': correlatingCommandId,
      };

  /// Return a copy of this event with [seq], [serverInstanceId], and/or
  /// [correlatingCommandId] overridden. Used by the headless server to
  /// stamp metadata onto events before broadcasting without mutating the
  /// upstream object the FFI bridge handed us.
  NightshadeEvent copyWith({
    int? seq,
    String? serverInstanceId,
    String? correlatingCommandId,
  }) {
    return NightshadeEvent(
      timestamp: timestamp,
      severity: severity,
      category: category,
      eventType: eventType,
      data: data,
      seq: seq ?? this.seq,
      serverInstanceId: serverInstanceId ?? this.serverInstanceId,
      correlatingCommandId: correlatingCommandId ?? this.correlatingCommandId,
    );
  }

  /// Create from JSON (used by NetworkBackend)
  factory NightshadeEvent.fromJson(Map<String, dynamic> json) {
    return NightshadeEvent.fromWireJson(json);
  }

  /// Parse headless `/events` payloads (`type: event` wrapper + canonical fields).
  factory NightshadeEvent.fromWireJson(Map<String, dynamic> json) {
    final payload = Map<String, dynamic>.from(json);
    payload.remove('type');

    final rawTimestamp = payload['timestamp'];
    final timestamp = switch (rawTimestamp) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    final rawSeverity = payload['severity'];
    final severityName =
        rawSeverity is String ? rawSeverity : rawSeverity?.toString() ?? 'info';
    final severity = EventSeverity.values.firstWhere(
      (e) => e.name.toLowerCase() == severityName.toLowerCase(),
      orElse: () => EventSeverity.info,
    );

    final rawCategory = payload['category'];
    final categoryName =
        rawCategory is String ? rawCategory : rawCategory?.toString() ?? 'system';
    final category = EventCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == categoryName.toLowerCase(),
      orElse: () => EventCategory.system,
    );

    final eventType = (payload['eventType'] ?? payload['event_type']) as String?;
    if (eventType == null || eventType.isEmpty) {
      throw FormatException('NightshadeEvent missing eventType: $payload');
    }

    final rawData = payload['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    // P1-1 / P1-4: read optional sequencing + correlation metadata. The
    // fields are omitted by pre-P1-1 servers and by FFI-originated events,
    // so accept null without complaint.
    final rawSeq = payload['seq'];
    final seq = switch (rawSeq) {
      final int v => v,
      final num v => v.toInt(),
      _ => null,
    };
    final serverInstanceId = payload['serverInstanceId'] is String
        ? payload['serverInstanceId'] as String
        : null;
    final correlatingCommandId = payload['correlatingCommandId'] is String
        ? payload['correlatingCommandId'] as String
        : null;

    return NightshadeEvent(
      timestamp: timestamp,
      severity: severity,
      category: category,
      eventType: eventType,
      data: data,
      seq: seq,
      serverInstanceId: serverInstanceId,
      correlatingCommandId: correlatingCommandId,
    );
  }

  @override
  String toString() =>
      'NightshadeEvent($eventType, $category, $severity, $data'
      '${seq != null ? ', seq=$seq' : ''}'
      '${correlatingCommandId != null ? ', cmd=$correlatingCommandId' : ''})';
}
