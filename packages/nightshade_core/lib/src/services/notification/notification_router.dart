// Central notification dispatcher.
//
// NotificationRouter sits between two worlds:
//   - INPUT:  the Rust event stream (NightshadeEvent) and the sequence
//             executor's high-level events.
//   - OUTPUT: per-transport NotificationTransport implementations.
//
// Responsibilities, in order they happen for each input event:
//   1. Classify the event into a NotificationCategory. Some categories
//      have a 1:1 mapping (`Completed` -> sequenceCompleted), some are
//      derived from data fields (`InstructionProgress` with
//      "meridian" -> meridianFlipPerformed).
//   2. Look up the routing rule for that category in the matrix.
//   3. Apply min-severity, rate-limit, debounce filters.
//   4. Render title + body templates from the per-rule template (or the
//      built-in default) with the context map extracted from the event.
//   5. Fan out to each enabled transport in parallel.
//
// All work is async and non-blocking. A transport that takes 20 s to
// time out cannot stall sequence execution because the router never
// awaits the transport futures from inside the event handler — it
// schedules them via `Future.microtask` and surfaces failures via the
// per-transport [lastResult] surface for the UI.

import 'dart:async';
import 'dart:developer' as developer;

import '../../models/backend/event_types.dart';
import '../../models/notification/notification_categories.dart';
import 'event_classifier.dart';
import 'notification_template.dart';
import 'transports/notification_transport.dart';
import 'transports/system_push_transport.dart';

/// Public entry point the router uses to fan out a single notification.
/// Tests can construct a router with an in-memory transport set and
/// call [route] directly with a synthetic context.
class NotificationRouter {
  final Map<NotificationTransportKind, NotificationTransport> _transports;
  NotificationRoutingMatrix _matrix;

  /// Last successful / failed result per transport (for the settings UI).
  final Map<NotificationTransportKind, NotificationResult> _lastResults = {};

  /// Per-category rate-limit window state.
  final Map<NotificationCategory, _RateWindow> _rateWindows = {};

  /// Per-category last fire time (for debouncing).
  final Map<NotificationCategory, DateTime> _lastFireTime = {};

  /// Recently-emitted systemPush signatures, for cross-stream de-duplication.
  ///
  /// After the architecture-unification collapse the router is the single
  /// systemPush producer, but it can be driven from TWO converging inputs:
  ///   * its own [attachEventStream] subscription (core event stream), and
  ///   * an explicit [route]/[routeExplicit] call from the Run Dashboard
  ///     critical-events bridge (which observes the bridge-typed event
  ///     history — a different representation of the SAME backend events with
  ///     no shared id to dedup on).
  /// Without dedup a single critical event the classifier recognises would
  /// fire two phone pushes (one per input). We suppress an identical
  /// (category + title + body) systemPush within [_pushDedupeWindow].
  final Map<String, DateTime> _recentPushSignatures = {};

  /// How long a systemPush content signature suppresses an identical repeat.
  /// Long enough to absorb the small skew between the core stream and the
  /// bridge's event-history update, short enough that a genuinely repeated
  /// alert minutes later still fires.
  static const Duration _pushDedupeWindow = Duration(seconds: 15);

  /// Event stream subscription.
  StreamSubscription<NightshadeEvent>? _subscription;

  /// Optional per-sequence overrides. When `_activeSequenceId` matches
  /// the executor's current sequence id (set by the executor bridge),
  /// rules in `_sequenceOverrides[activeId]` take precedence over the
  /// global matrix for that category.
  String? _activeSequenceId;
  final Map<String, Map<NotificationCategory, NotificationRoutingRule>>
      _sequenceOverrides = {};

  NotificationRouter({
    required List<NotificationTransport> transports,
    NotificationRoutingMatrix matrix =
        const NotificationRoutingMatrix(enabled: true),
  })  : _transports = {for (final t in transports) t.kind: t},
        _matrix = matrix.rules.isEmpty
            ? NotificationRoutingMatrix.defaults().copyWith(enabled: matrix.enabled)
            : matrix;

  // ----- Public surface ----------------------------------------------------

  NotificationRoutingMatrix get matrix => _matrix;

  Map<NotificationTransportKind, NotificationResult> get lastResults =>
      Map.unmodifiable(_lastResults);

  /// Update the matrix in-place. Cheap — used by the Riverpod provider
  /// when the user toggles a setting.
  void updateMatrix(NotificationRoutingMatrix matrix) {
    _matrix = matrix.rules.isEmpty
        ? NotificationRoutingMatrix.defaults().copyWith(enabled: matrix.enabled)
        : matrix;
  }

  /// Set per-sequence routing overrides. `null` clears them.
  void setSequenceOverrides(
    String sequenceId,
    Map<NotificationCategory, NotificationRoutingRule>? overrides,
  ) {
    if (overrides == null) {
      _sequenceOverrides.remove(sequenceId);
    } else {
      _sequenceOverrides[sequenceId] = Map.of(overrides);
    }
  }

  /// Tell the router which sequence is currently running. Pass `null`
  /// when no sequence is active.
  void setActiveSequence(String? sequenceId) {
    _activeSequenceId = sequenceId;
  }

  /// Register an event stream and start dispatching. Calling twice
  /// cancels the previous subscription.
  void attachEventStream(Stream<NightshadeEvent> events) {
    _subscription?.cancel();
    _subscription = events.listen(
      _onEvent,
      onError: (e) {
        developer.log('[NotificationRouter] Event stream error: $e',
            name: 'NotificationRouter', level: 1000, error: e);
      },
    );
  }

  /// Dispose all subscriptions + transports.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final t in _transports.values) {
      await t.dispose();
    }
  }

  /// Fire a notification directly. Public so the sequence executor (and
  /// the custom NotificationNode integration) can push events the raw
  /// stream doesn't carry.
  void route(
    NotificationCategory category,
    Map<String, String> contextValues, {
    EventSeverity severity = EventSeverity.info,
  }) {
    if (!_matrix.enabled) return;
    final rule = _ruleFor(category);
    if (!rule.enabled) return;
    if (severity.index < rule.minSeverity.index) return;

    if (_isDebounced(category, rule)) return;
    if (_isRateLimited(category, rule)) return;

    _lastFireTime[category] = DateTime.now();
    _recordRateHit(category);

    final ctx = NotificationContext(contextValues);
    final title = renderNotificationTemplate(
      rule.titleTemplate ?? _defaultTitleTemplate(category),
      ctx,
    );
    final body = renderNotificationTemplate(
      rule.bodyTemplate ?? _defaultBodyTemplate(category),
      ctx,
    );

    for (final kind in rule.transports) {
      final transport = _transports[kind];
      if (transport == null) continue;
      if (!transport.isConfigured) continue;
      _dispatch(transport, category, title, body);
    }
  }

  /// Route the Run Dashboard critical-events bridge's phone-push through the
  /// single systemPush producer.
  ///
  /// The bridge escalates every `isCriticalEvent` (banner + toast + audible);
  /// historically it ALSO owned a parallel phone-push via the push service.
  /// That parallel feed is collapsed here: the bridge now forwards its push
  /// through the router so there is exactly ONE systemPush producer.
  ///
  /// Some bridge-flagged events (generic system errors / FITS save failures)
  /// have no [NotificationCategory] and the classifier path will not push
  /// them, so this entry point forces a `critical` phone push with the copy
  /// the bridge already rendered (`Critical · <category>` / detail). For
  /// events the classifier DOES recognise (e.g. a guiding StarLost), the
  /// router's own core-stream subscription also pushes — the systemPush
  /// content-signature dedup in [_dispatch]/here collapses the pair so the
  /// operator still gets exactly one page.
  ///
  /// Respects the master push gate (the transport's `enabled` config) and the
  /// matrix master `enabled` flag, mirroring the legacy bridge which honoured
  /// `pushCriticalAlerts`.
  void routeBridgeCriticalPush({
    required String title,
    required String body,
    required String eventType,
    required EventCategory eventCategory,
  }) {
    if (!_matrix.enabled) return;
    final transport = _transports[NotificationTransportKind.systemPush];
    if (transport is! SystemPushTransport) return;

    // Cross-stream dedup: the classifier path keys the same phone push on its
    // rendered (title + body). The operator only ever sees title + body, so a
    // shared (title + body) signature is exactly what must not page twice.
    if (_isDuplicatePush(title, body)) return;

    transport.enqueueExplicit(
      title: title,
      body: body,
      eventType: eventType,
      eventCategory: eventCategory,
    );
  }

  /// Bridge for the in-sequence `NotificationNode`.
  ///
  /// The executor (Rust side) raises a `Custom` event whose data map
  /// carries the rendered title + message. UI callers that already have
  /// a rendered title/body can use this entry point to push the node
  /// through the routing matrix without going through the event stream
  /// classifier. The node itself supplies optional explicit transports;
  /// when non-empty those override the matrix entry for `custom`.
  void routeNotificationNode({
    required String title,
    required String body,
    EventSeverity severity = EventSeverity.info,
    List<NotificationTransportKind>? explicitTransports,
  }) {
    if (!_matrix.enabled) return;
    final baseRule = _ruleFor(NotificationCategory.custom);
    if (!baseRule.enabled) return;
    final transports = explicitTransports ?? baseRule.transports;
    for (final kind in transports) {
      final transport = _transports[kind];
      if (transport == null || !transport.isConfigured) continue;
      _dispatch(transport, NotificationCategory.custom, title, body);
    }
  }

  /// Send a single test notification through one specific transport.
  /// Returns the result so the settings UI can render success / error
  /// inline next to the test-send button.
  Future<NotificationResult> sendTest(
    NotificationTransportKind kind, {
    String title = 'Nightshade test',
    String body = 'This is a test notification from Nightshade.',
    NotificationCategory category = NotificationCategory.custom,
  }) async {
    final transport = _transports[kind];
    if (transport == null) {
      return NotificationResult.fail('Transport not available');
    }
    if (!transport.isConfigured) {
      return NotificationResult.fail('${transport.name} is not configured');
    }
    final result =
        await transport.send(category: category, title: title, body: body);
    _lastResults[kind] = result;
    return result;
  }

  /// Read the live config from a typed transport, if registered.
  NotificationTransport? transportOf(NotificationTransportKind kind) =>
      _transports[kind];

  // ----- Internal: event mapping ------------------------------------------

  void _onEvent(NightshadeEvent event) {
    if (!_matrix.enabled) return;

    // Wave 5 Agent 5 — NotificationNode emits a sequencer event of type
    // `Notification` whose data carries title/message/level/transports.
    // It bypasses the auto-classifier because the user's chosen
    // explicit_transports must override the matrix's `custom` rule.
    if (event.category == EventCategory.sequencer &&
        event.eventType == 'Notification') {
      final title = (event.data['title'] as String?) ?? '';
      final body = (event.data['message'] as String?) ?? '';
      final transports = _parseExplicitTransportsFromEvent(event.data);
      routeNotificationNode(
        title: title,
        body: body,
        severity: event.severity,
        explicitTransports: transports,
      );
      return;
    }

    // P1-11 — OTA "update available" is an operator-driven system event the
    // shared classifier deliberately does not route to a notification
    // category. The (now demoted) PushNotificationService used to surface it
    // as a phone push from its own subscription; since that subscription is
    // gone, the router preserves the push here so paired phones still learn a
    // new build is available. Routed as `custom` with explicit in-app +
    // systemPush transports so it does not depend on the user's `custom`
    // matrix wiring.
    if (event.category == EventCategory.system &&
        event.eventType == 'UpdateAvailable') {
      final latest =
          (event.data['latestVersion'] as String?) ?? 'a new version';
      final current =
          (event.data['currentVersion'] as String?) ?? 'the current build';
      routeNotificationNode(
        title: 'Nightshade $latest available',
        body:
            'Open Settings > Updates to install the new build (currently on $current).',
        severity: EventSeverity.info,
        explicitTransports: const [
          NotificationTransportKind.inApp,
          NotificationTransportKind.systemPush,
        ],
      );
      return;
    }

    // Single source of truth for event -> category classification, shared
    // with PushNotificationService (see event_classifier.dart).
    final classified = NotificationEventClassifier.classify(event);
    if (classified == null) return;
    final context = _buildContext(event, classified.context);
    route(classified.category, context, severity: classified.severity);
  }

  /// Pull `explicit_transports` out of a NotificationNode Rust event
  /// payload. Returns null if the field is missing or empty (which means
  /// "inherit the matrix's `custom` rule transports").
  List<NotificationTransportKind>? _parseExplicitTransportsFromEvent(
      Map<String, dynamic> data) {
    final raw = data['explicit_transports'];
    if (raw is! List) return null;
    final out = <NotificationTransportKind>[];
    for (final entry in raw) {
      if (entry is String) {
        final t = NotificationTransportKind.fromStorageKey(entry);
        if (t != null) out.add(t);
      }
    }
    return out.isEmpty ? null : out;
  }

  Map<String, String> _buildContext(
      NightshadeEvent event, Map<String, String> overrides) {
    final ctx = <String, String>{};
    // Pull common scalar fields from the event's data map. We never
    // override a value the classifier set (those are more specific).
    for (final entry in event.data.entries) {
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        ctx[entry.key] = value.toString();
      }
    }
    ctx.addAll(overrides); // overrides win
    return ctx;
  }

  // ----- Internal: filters / dispatch -------------------------------------

  NotificationRoutingRule _ruleFor(NotificationCategory category) {
    final activeSeq = _activeSequenceId;
    if (activeSeq != null) {
      final overrides = _sequenceOverrides[activeSeq];
      if (overrides != null && overrides.containsKey(category)) {
        return overrides[category]!;
      }
    }
    return _matrix.ruleFor(category);
  }

  bool _isDebounced(
      NotificationCategory category, NotificationRoutingRule rule) {
    if (rule.debounceSeconds <= 0) return false;
    final last = _lastFireTime[category];
    if (last == null) return false;
    return DateTime.now().difference(last) <
        Duration(seconds: rule.debounceSeconds);
  }

  bool _isRateLimited(
      NotificationCategory category, NotificationRoutingRule rule) {
    if (rule.maxPerHour <= 0) return false;
    final window =
        _rateWindows.putIfAbsent(category, () => _RateWindow(maxAge: const Duration(hours: 1)));
    window.prune();
    return window.count >= rule.maxPerHour;
  }

  void _recordRateHit(NotificationCategory category) {
    final window = _rateWindows.putIfAbsent(
        category, () => _RateWindow(maxAge: const Duration(hours: 1)));
    window.record(DateTime.now());
  }

  void _dispatch(
    NotificationTransport transport,
    NotificationCategory category,
    String title,
    String body,
  ) {
    // Cross-stream de-duplication for the single systemPush producer: if an
    // identical phone push (same category + title + body) was emitted within
    // the dedupe window, suppress this one. This collapses the case where the
    // router's own classifier path and the dashboard bridge's explicit path
    // converge on the same backend event. Other transports (in-app, email,
    // webhooks, …) are not deduped here — each has its own delivery semantics
    // and an at-idle external alert must not be swallowed by a UI repeat.
    if (transport.kind == NotificationTransportKind.systemPush) {
      if (_isDuplicatePush(title, body)) return;
    }

    // Fire and forget — the transport's own timeout caps the wait. We
    // record the result so the settings UI can show the latest status.
    Future.microtask(() async {
      final result = await transport.send(
        category: category,
        title: title,
        body: body,
      );
      _lastResults[transport.kind] = result;
      if (!result.success) {
        developer.log(
          '[NotificationRouter] ${transport.name} send failed: ${result.error}',
          name: 'NotificationRouter',
          level: 900,
        );
      }
    });
  }

  /// True if an identical phone push (same rendered title + body) was emitted
  /// within [_pushDedupeWindow]. Records the signature when not a duplicate so
  /// the next identical push inside the window is suppressed. This is the one
  /// place the single systemPush producer collapses its two converging inputs
  /// (the classifier core-stream path and the dashboard-bridge explicit path)
  /// keyed on the copy the operator actually sees.
  bool _isDuplicatePush(String title, String body) {
    final now = DateTime.now();
    _recentPushSignatures
        .removeWhere((_, when) => now.difference(when) > _pushDedupeWindow);
    final signature = '$title|$body';
    final last = _recentPushSignatures[signature];
    if (last != null && now.difference(last) < _pushDedupeWindow) return true;
    _recentPushSignatures[signature] = now;
    return false;
  }

  // ----- Default templates ------------------------------------------------

  static String _defaultTitleTemplate(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.sequenceStarted:
        return 'Sequence started';
      case NotificationCategory.sequenceCompleted:
        return 'Sequence complete';
      case NotificationCategory.sequenceFailed:
        return 'Sequence failed';
      case NotificationCategory.sequencePaused:
        return 'Sequence paused';
      case NotificationCategory.sequenceResumed:
        return 'Sequence resumed';
      case NotificationCategory.targetStarted:
        return 'Target started: \${target.name}';
      case NotificationCategory.targetCompleted:
        return 'Target complete: \${target.name}';
      case NotificationCategory.meridianFlipPerformed:
        return 'Meridian flip performed';
      case NotificationCategory.autofocusCompleted:
        return 'Autofocus complete';
      case NotificationCategory.autofocusFailed:
        return 'Autofocus failed';
      case NotificationCategory.frameCaptured:
        return 'Frame captured';
      case NotificationCategory.frameRejected:
        return 'Frame rejected';
      case NotificationCategory.exposureFailed:
        return 'Exposure failed';
      case NotificationCategory.recoveryStarted:
        return 'Recovery started';
      case NotificationCategory.recoveryRecovered:
        return 'Recovery succeeded';
      case NotificationCategory.recoveryGaveUp:
        return 'Recovery gave up';
      case NotificationCategory.guidingLost:
        return 'Guiding lost';
      case NotificationCategory.guidingRecovered:
        return 'Guiding recovered';
      case NotificationCategory.weatherUnsafe:
        return 'Weather unsafe';
      case NotificationCategory.weatherSafeAgain:
        return 'Weather safe again';
      case NotificationCategory.cloudArriving:
        return 'Clouds arriving';
      case NotificationCategory.cloudOpening:
        return 'Sky is clearing';
      case NotificationCategory.diskSpaceLow:
        return 'Disk space low';
      case NotificationCategory.equipmentDisconnected:
        return 'Equipment disconnected';
      case NotificationCategory.triggerFired:
        return 'Trigger fired';
      case NotificationCategory.custom:
        return 'Nightshade notification';
    }
  }

  static String _defaultBodyTemplate(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.targetStarted:
        return 'Starting target \${target.name} at \${time.local}.';
      case NotificationCategory.targetCompleted:
        return 'Finished imaging \${target.name} at \${time.local}.';
      case NotificationCategory.sequenceStarted:
        return 'Sequence started at \${time.local}.';
      case NotificationCategory.sequenceCompleted:
        return 'Sequence completed successfully at \${time.local}.';
      case NotificationCategory.sequenceFailed:
        return 'Sequence aborted at \${time.local}.';
      case NotificationCategory.frameCaptured:
        return 'Frame \${frame} captured (\${exposure.duration}s).';
      case NotificationCategory.exposureFailed:
        return 'Exposure failed: \${frame.reason}.';
      case NotificationCategory.equipmentDisconnected:
        return '\${equipment.device_type} \${equipment.device_id} disconnected.';
      case NotificationCategory.weatherUnsafe:
        return 'Safety monitor reports unsafe conditions.';
      case NotificationCategory.weatherSafeAgain:
        return 'Conditions safe again.';
      case NotificationCategory.diskSpaceLow:
        return 'Storage usage exceeded safe threshold.';
      case NotificationCategory.guidingLost:
        return 'Guide star lost; guiding stopped.';
      case NotificationCategory.guidingRecovered:
        return 'Guiding recovered.';
      case NotificationCategory.recoveryStarted:
        return 'Executor entered recovery at \${time.local}.';
      case NotificationCategory.recoveryRecovered:
        return 'Executor recovered at \${time.local}.';
      case NotificationCategory.recoveryGaveUp:
        return 'Executor exhausted recovery attempts.';
      case NotificationCategory.meridianFlipPerformed:
        return 'Meridian flip completed.';
      case NotificationCategory.autofocusCompleted:
        return 'Autofocus run completed.';
      case NotificationCategory.autofocusFailed:
        return 'Autofocus run failed.';
      case NotificationCategory.frameRejected:
        return 'Frame rejected: \${frame.reason}.';
      case NotificationCategory.cloudArriving:
        return 'Cloud cover increasing.';
      case NotificationCategory.cloudOpening:
        return 'Cloud cover decreasing.';
      case NotificationCategory.triggerFired:
        return 'Trigger \${trigger.name} fired.';
      case NotificationCategory.sequencePaused:
        return 'Sequence paused at \${time.local}.';
      case NotificationCategory.sequenceResumed:
        return 'Sequence resumed at \${time.local}.';
      case NotificationCategory.custom:
        return 'Nightshade fired a custom notification.';
    }
  }
}

/// Sliding rate-limit window for [_isRateLimited] / [_recordRateHit].
class _RateWindow {
  final Duration maxAge;
  final List<DateTime> _hits = [];
  _RateWindow({required this.maxAge});

  int get count => _hits.length;

  void record(DateTime now) {
    _hits.add(now);
    prune(now: now);
  }

  void prune({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    while (_hits.isNotEmpty && _hits.first.isBefore(cutoff)) {
      _hits.removeAt(0);
    }
  }
}
