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
import 'notification_signature.dart';
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

  /// Recently-emitted content signatures per transport kind, for
  /// cross-producer de-duplication.
  ///
  /// After the architecture-unification collapse the router is the single
  /// producer for every transport, but it is driven from SEVERAL converging
  /// inputs that describe one physical happening:
  ///   * its own [attachEventStream] subscription (core event stream), which
  ///     the classifier may map to the same category from more than one wire
  ///     event — an operator Stop arrives as BOTH a sequencer `Error` carrying
  ///     the "Sequence cancelled" notice AND the `Stopped` lifecycle event, and
  ///   * an explicit [route] / [routeBridgeCriticalPush] call from the Run
  ///     Dashboard critical-events bridge (which observes the bridge-typed
  ///     event history — a different representation of the SAME backend events
  ///     with no shared id to dedup on).
  ///
  /// Without dedup one operator Stop published THREE identical toasts and three
  /// RECENT EVENTS rows, 86 microseconds apart (WF-N4 / WF-STOP-N3), and one
  /// failed connect said the same refusal twice (WD-EQ-3). The router is the
  /// one place every producer converges, so this is where the repetition is
  /// collapsed — keyed on what the operator SEES, not on the producer.
  ///
  /// Per transport kind, never global: an at-idle external alert (webhook,
  /// e-mail, MQTT) must not be swallowed because the UI already said it.
  final Map<NotificationTransportKind, Map<String, DateTime>>
  _recentSignatures = {};

  /// How long a systemPush content signature suppresses an identical repeat.
  /// Long enough to absorb the small skew between the core stream and the
  /// bridge's event-history update, short enough that a genuinely repeated
  /// alert minutes later still fires.
  static const Duration _pushDedupeWindow = Duration(seconds: 15);

  /// The same window for every other transport. Shorter than the push window
  /// because the converging producers fire in the same millisecond, and a
  /// repeat the operator can plausibly read as new information should still
  /// get through.
  static const Duration _contentDedupeWindow = Duration(seconds: 5);

  /// Injectable clock. Production uses `DateTime.now`; tests drive the dedupe
  /// windows and the rendered clock time deterministically.
  final DateTime Function() _now;

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
    NotificationRoutingMatrix matrix = const NotificationRoutingMatrix(
      enabled: true,
    ),
    DateTime Function()? clock,
  }) : _transports = {for (final t in transports) t.kind: t},
       _now = clock ?? DateTime.now,
       _matrix = matrix.rules.isEmpty
           ? NotificationRoutingMatrix.defaults().copyWith(
               enabled: matrix.enabled,
             )
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
        developer.log(
          '[NotificationRouter] Event stream error: $e',
          name: 'NotificationRouter',
          level: 1000,
          error: e,
        );
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

    final eligible = _eligibleTransports(rule.transports);
    if (eligible.isEmpty) return;

    _lastFireTime[category] = _now();
    _recordRateHit(category);

    final ctx = NotificationContext(contextValues);
    final title = renderNotificationTemplate(
      rule.titleTemplate ?? _defaultTitleTemplate(category),
      ctx,
      clock: _now,
    );
    final body = renderNotificationTemplate(
      rule.bodyTemplate ?? _defaultBodyTemplate(category),
      ctx,
      clock: _now,
    );

    for (final transport in eligible) {
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
    if (_isDuplicate(NotificationTransportKind.systemPush, title, body)) return;

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
    if (severity.index < baseRule.minSeverity.index) return;
    if (_isDebounced(NotificationCategory.custom, baseRule)) return;
    if (_isRateLimited(NotificationCategory.custom, baseRule)) return;

    final eligible = _eligibleTransports(
      explicitTransports ?? baseRule.transports,
    );
    if (eligible.isEmpty) return;

    _lastFireTime[NotificationCategory.custom] = _now();
    _recordRateHit(NotificationCategory.custom);
    for (final transport in eligible) {
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
    late NotificationResult result;
    try {
      result = await transport.send(
        category: category,
        title: title,
        body: body,
      );
    } catch (error) {
      result = NotificationResult.fail(error.toString());
    }
    _lastResults[kind] = result;
    return result;
  }

  /// Read the live config from a typed transport, if registered.
  NotificationTransport? transportOf(NotificationTransportKind kind) =>
      _transports[kind];

  // ----- Internal: event mapping ------------------------------------------

  void _onEvent(NightshadeEvent event) {
    if (!_matrix.enabled) return;

    // NotificationNode emits a sequencer event of type
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

    // OTA "update available" is an operator-driven system event the
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
      final title = 'Nightshade $latest available';
      final body =
          'Open Settings > Updates to install the new build (currently on $current).';
      for (final transport in _eligibleTransports(const [
        NotificationTransportKind.inApp,
        NotificationTransportKind.systemPush,
      ])) {
        _dispatch(transport, NotificationCategory.custom, title, body);
      }
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
    Map<String, dynamic> data,
  ) {
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
    NightshadeEvent event,
    Map<String, String> overrides,
  ) {
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
    NotificationCategory category,
    NotificationRoutingRule rule,
  ) {
    if (rule.debounceSeconds <= 0) return false;
    final last = _lastFireTime[category];
    if (last == null) return false;
    return _now().difference(last) < Duration(seconds: rule.debounceSeconds);
  }

  bool _isRateLimited(
    NotificationCategory category,
    NotificationRoutingRule rule,
  ) {
    if (rule.maxPerHour <= 0) return false;
    final window = _rateWindows.putIfAbsent(
      category,
      () => _RateWindow(maxAge: const Duration(hours: 1)),
    );
    window.prune(now: _now());
    return window.count >= rule.maxPerHour;
  }

  void _recordRateHit(NotificationCategory category) {
    final window = _rateWindows.putIfAbsent(
      category,
      () => _RateWindow(maxAge: const Duration(hours: 1)),
    );
    window.record(_now());
  }

  void _dispatch(
    NotificationTransport transport,
    NotificationCategory category,
    String title,
    String body,
  ) {
    // Cross-producer de-duplication. Several converging inputs describe one
    // physical happening (see [_recentSignatures]); the operator must be told
    // once. The signature is per transport kind, so an external alert is never
    // swallowed because the UI already said it.
    if (_isDuplicate(transport.kind, title, body)) return;

    // Fire and forget — the transport's own timeout caps the wait. We
    // record the result so the settings UI can show the latest status.
    Future.microtask(() async {
      late NotificationResult result;
      try {
        result = await transport.send(
          category: category,
          title: title,
          body: body,
        );
      } catch (error, stackTrace) {
        result = NotificationResult.fail(error.toString());
        developer.log(
          '[NotificationRouter] ${transport.name} threw while sending: $error',
          name: 'NotificationRouter',
          level: 1000,
          error: error,
          stackTrace: stackTrace,
        );
      }
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

  List<NotificationTransport> _eligibleTransports(
    Iterable<NotificationTransportKind> kinds,
  ) {
    final eligible = <NotificationTransport>[];
    final seen = <NotificationTransportKind>{};
    for (final kind in kinds) {
      if (!seen.add(kind)) continue;
      final transport = _transports[kind];
      if (transport != null && transport.isConfigured) {
        eligible.add(transport);
      }
    }
    return eligible;
  }

  /// True if a notification with the same NORMALIZED (title + body) already
  /// went out on [kind] inside its dedupe window. Records the signature when
  /// it is not a duplicate so the next identical copy inside the window is
  /// suppressed.
  ///
  /// ## Why the key is normalized
  ///
  /// The first version of this keyed on the exact rendered strings, and the
  /// case it was written for defeated it by ONE CHARACTER: two producers of the
  /// same guider refusal emitted
  ///
  ///   Built-in guider requires an active profile with a guide focal length
  ///   Built-in guider requires an active profile with a guide focal length.
  ///
  /// so the operator read the identical sentence twice (WD-EQ-3, still open
  /// after two waves). Trailing sentence punctuation and whitespace are
  /// cosmetic differences between producers of ONE statement, never a
  /// difference the operator can act on, so they are stripped before keying —
  /// as is letter case, and internal whitespace runs.
  ///
  /// `?` is deliberately NOT stripped: a question and a statement are different
  /// notifications.
  bool _isDuplicate(NotificationTransportKind kind, String title, String body) {
    final window = kind == NotificationTransportKind.systemPush
        ? _pushDedupeWindow
        : _contentDedupeWindow;
    final now = _now();
    final seen = _recentSignatures.putIfAbsent(kind, () => {});
    seen.removeWhere((_, when) => now.difference(when) > window);
    // One shared rule, in `notification_signature.dart`. WD-EQ-3 outlived two
    // fixes because each surface had its own copy of "same statement?"; the
    // toast overlay's copy still keyed on the exact strings while this one
    // normalized. There is now one implementation and both call it.
    final signature = notificationContentSignature(
      discriminator: kind.name,
      title: title,
      body: body,
    );
    final last = seen[signature];
    if (last != null && now.difference(last) < window) return true;
    seen[signature] = now;
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
      case NotificationCategory.sequenceStopped:
        return 'Sequence stopped';
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
      case NotificationCategory.transientDiscovered:
        return 'Possible new transient';
      case NotificationCategory.custom:
        return 'Nightshade notification';
    }
  }

  static String _defaultBodyTemplate(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.targetStarted:
        return 'Starting target \${target.name} at \${time.clock}.';
      case NotificationCategory.targetCompleted:
        return 'Finished imaging \${target.name} at \${time.clock}.';
      case NotificationCategory.sequenceStarted:
        return 'Sequence started at \${time.clock}.';
      case NotificationCategory.sequenceCompleted:
        return 'Sequence completed successfully at \${time.clock}.';
      case NotificationCategory.sequenceFailed:
        return 'Sequence aborted at \${time.clock}.';
      case NotificationCategory.sequenceStopped:
        return 'Sequence stopped by request at \${time.clock}.';
      case NotificationCategory.frameCaptured:
        return 'Frame \${frame} captured (\${exposure.duration}s).';
      case NotificationCategory.exposureFailed:
        return 'Exposure failed: \${frame.reason}.';
      case NotificationCategory.equipmentDisconnected:
        // WD-EQ-2a: names the device, never its wire id. The classifier
        // resolves `equipment.device_name` through `friendlyNameFromDeviceId`
        // and falls back to the device type, so this sentence always has a
        // subject. The type is deliberately not repeated in front of the name
        // ("Guider Built-in Multi-Star Guider disconnected.").
        return '\${equipment.device_name} disconnected.';
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
        return 'Executor entered recovery at \${time.clock}.';
      case NotificationCategory.recoveryRecovered:
        return 'Executor recovered at \${time.clock}.';
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
      case NotificationCategory.transientDiscovered:
        return 'First Light caught something at \${transient.coords} '
            '(SNR \${transient.snr}). Chase it before it fades.';
      case NotificationCategory.sequencePaused:
        return 'Sequence paused at \${time.clock}.';
      case NotificationCategory.sequenceResumed:
        return 'Sequence resumed at \${time.clock}.';
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
