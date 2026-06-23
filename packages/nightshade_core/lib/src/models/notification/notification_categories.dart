// Notification routing categories and per-transport configuration models.
//
// Why this file exists: wired the critical-event push path
// (PushNotificationService), but only a fixed set of toggles. Users need
// per-event-type routing across multiple transports (the "NINA Ground
// Station" UX): "send target-complete to Pushover, send weather-unsafe to
// Telegram + Discord, send disk-low to email". This file is the
// vocabulary all those routing rules speak.
//
// Single source of truth: `NotificationCategory` is the canonical enum
// everything else keys off. Adding a new category here surfaces a switch
// exhaustiveness warning at every dispatch site (router event mapper,
// settings UI rows, default-routing-rules table) so we can never forget
// to handle a new event class.

import 'package:equatable/equatable.dart';
import '../backend/event_types.dart';

/// One semantic class of sequencer / system event the user can route.
///
/// These intentionally do NOT mirror Rust `EventCategory` 1:1 — that enum
/// is too coarse (a single `sequencer` value covers start, complete, fail,
/// target start, target complete, meridian flip…). The router maps from
/// the raw [NightshadeEvent] stream onto these finer-grained categories;
/// users see only these labels in the settings UI.
enum NotificationCategory {
  // ----- Sequence lifecycle ------------------------------------------------
  sequenceStarted('Sequence Started'),
  sequenceCompleted('Sequence Completed'),
  sequenceFailed('Sequence Failed'),
  sequencePaused('Sequence Paused'),
  sequenceResumed('Sequence Resumed'),

  // ----- Target lifecycle --------------------------------------------------
  targetStarted('Target Started'),
  targetCompleted('Target Completed'),

  // ----- Mount / hardware milestones ---------------------------------------
  meridianFlipPerformed('Meridian Flip Performed'),
  autofocusCompleted('Autofocus Completed'),
  autofocusFailed('Autofocus Failed'),

  // ----- Imaging -----------------------------------------------------------
  frameCaptured('Frame Captured'),
  frameRejected('Frame Rejected'),
  exposureFailed('Exposure Failed'),

  // ----- Recovery / executor health ----------------------------------------
  recoveryStarted('Recovery Started'),
  recoveryRecovered('Recovery Recovered'),
  recoveryGaveUp('Recovery Gave Up'),

  // ----- Guiding -----------------------------------------------------------
  guidingLost('Guiding Lost'),
  guidingRecovered('Guiding Recovered'),

  // ----- Weather / safety --------------------------------------------------
  weatherUnsafe('Weather Unsafe'),
  weatherSafeAgain('Weather Safe Again'),
  cloudArriving('Cloud Arriving'),
  cloudOpening('Cloud Clearing'),

  // ----- Astronomical discovery (First Light / Pillar B) -------------------
  transientDiscovered('Transient Discovered'),

  // ----- System / operational ----------------------------------------------
  diskSpaceLow('Disk Space Low'),
  equipmentDisconnected('Equipment Disconnected'),
  triggerFired('Sequencer Trigger Fired'),

  // ----- Custom (user-script / NotificationNode-defined) -------------------
  custom('Custom');

  final String label;
  const NotificationCategory(this.label);

  /// Stable string key for JSON / DAO storage. Uses the enum `name` so a
  /// future label rewording (English wording is the `label`) never changes
  /// the persisted key.
  String get storageKey => name;

  /// Default severity for the category. Used as the lower bound for
  /// "min severity" filters when the user hasn't customised the rule.
  EventSeverity get defaultSeverity {
    switch (this) {
      case NotificationCategory.sequenceStarted:
      case NotificationCategory.sequenceResumed:
      case NotificationCategory.sequencePaused:
      case NotificationCategory.targetStarted:
      case NotificationCategory.targetCompleted:
      case NotificationCategory.meridianFlipPerformed:
      case NotificationCategory.autofocusCompleted:
      case NotificationCategory.frameCaptured:
      case NotificationCategory.recoveryRecovered:
      case NotificationCategory.guidingRecovered:
      case NotificationCategory.weatherSafeAgain:
      case NotificationCategory.cloudOpening:
      case NotificationCategory.triggerFired:
      case NotificationCategory.custom:
        return EventSeverity.info;
      case NotificationCategory.sequenceCompleted:
        return EventSeverity.info;
      case NotificationCategory.frameRejected:
      case NotificationCategory.cloudArriving:
      case NotificationCategory.recoveryStarted:
        return EventSeverity.warning;
      case NotificationCategory.sequenceFailed:
      case NotificationCategory.autofocusFailed:
      case NotificationCategory.exposureFailed:
      case NotificationCategory.guidingLost:
      case NotificationCategory.weatherUnsafe:
      case NotificationCategory.diskSpaceLow:
      case NotificationCategory.equipmentDisconnected:
        return EventSeverity.error;
      // A possible new transient is a time-critical, must-not-miss event: the
      // chase window closes by morning. Severity `critical` so it clears the
      // default min-severity bar on the systemPush transport.
      case NotificationCategory.transientDiscovered:
      case NotificationCategory.recoveryGaveUp:
        return EventSeverity.critical;
    }
  }

  /// Single source of truth for "is this category operationally critical?".
  ///
  /// Critical categories are the ones an unattended operator must not miss:
  /// they default into the `systemPush` (mobile) transport in the routing
  /// matrix and drive the Run Dashboard's persistent critical banner. Both
  /// the matrix defaults ([_criticalByDefault]) and any criticality check
  /// elsewhere derive from this one list so they can never drift.
  bool get isCritical {
    switch (this) {
      case NotificationCategory.sequenceFailed:
      case NotificationCategory.recoveryGaveUp:
      case NotificationCategory.weatherUnsafe:
      case NotificationCategory.guidingLost:
      case NotificationCategory.diskSpaceLow:
      case NotificationCategory.equipmentDisconnected:
      case NotificationCategory.autofocusFailed:
      case NotificationCategory.exposureFailed:
      // A possible new transient is operationally critical for a discovery
      // imager: it pushes to the phone by default so the chase happens tonight.
      case NotificationCategory.transientDiscovered:
        return true;
      default:
        return false;
    }
  }

  static NotificationCategory? fromStorageKey(String key) {
    for (final c in NotificationCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// Transport channels a routing rule may target.
///
/// `inApp` and `systemPush` exist for completeness so the routing matrix
/// can replace the legacy `PushNotificationConfig` boolean grid wholesale;
/// the actual implementations of those two predate this file and live in
/// `UiNotificationNotifier` / `PushNotificationService`.
enum NotificationTransportKind {
  inApp('In-app banner'),
  systemPush('Mobile push'),
  email('Email (SMTP)'),
  webhookGeneric('Generic webhook'),
  pushover('Pushover'),
  telegram('Telegram'),
  discord('Discord'),
  mqtt('MQTT');

  final String label;
  const NotificationTransportKind(this.label);

  String get storageKey => name;

  static NotificationTransportKind? fromStorageKey(String key) {
    for (final t in NotificationTransportKind.values) {
      if (t.name == key) return t;
    }
    return null;
  }
}

/// Outcome of a single transport send attempt. Surfaced back to the UI
/// (test-send button shows status, router logs persist last-result per
/// transport).
class NotificationResult extends Equatable {
  final bool success;
  final String? error;
  final int? statusCode;
  final DateTime timestamp;

  NotificationResult.ok({this.statusCode})
    : success = true,
      error = null,
      timestamp = DateTime.now();

  NotificationResult.fail(this.error, {this.statusCode})
    : success = false,
      timestamp = DateTime.now();

  @override
  List<Object?> get props => [success, error, statusCode, timestamp];

  @override
  String toString() =>
      success ? 'NotificationResult.ok' : 'NotificationResult.fail($error)';
}

/// Per-category routing rule: which transports fire, with optional
/// filtering / rate-limiting / templating.
///
/// Persisted as JSON inside the [NotificationRoutingMatrix].
class NotificationRoutingRule extends Equatable {
  /// Transports that should fire for this category. Order matters for the
  /// settings UI summary line ("→ In-app + Pushover").
  final List<NotificationTransportKind> transports;

  /// Minimum event severity required to fire. Events below this are
  /// dropped (e.g. user sets "errors only" for Telegram on the
  /// targetCompleted row → success events are silently dropped).
  final EventSeverity minSeverity;

  /// Maximum number of notifications per hour for this category. `0`
  /// disables rate limiting.
  final int maxPerHour;

  /// Suppress repeated fires for the same category within this many
  /// seconds. `0` disables debouncing.
  final int debounceSeconds;

  /// Custom message template (uses the interpolation engine).
  /// `null` falls back to the per-category default template baked into
  /// the router.
  final String? titleTemplate;
  final String? bodyTemplate;

  /// Whether the rule is enabled. Disabling drops a category from the
  /// dispatcher without losing its configuration.
  final bool enabled;

  const NotificationRoutingRule({
    this.transports = const [NotificationTransportKind.inApp],
    this.minSeverity = EventSeverity.info,
    this.maxPerHour = 0,
    this.debounceSeconds = 0,
    this.titleTemplate,
    this.bodyTemplate,
    this.enabled = true,
  });

  NotificationRoutingRule copyWith({
    List<NotificationTransportKind>? transports,
    EventSeverity? minSeverity,
    int? maxPerHour,
    int? debounceSeconds,
    String? titleTemplate,
    String? bodyTemplate,
    bool? enabled,
    bool clearTitleTemplate = false,
    bool clearBodyTemplate = false,
  }) {
    return NotificationRoutingRule(
      transports: transports ?? this.transports,
      minSeverity: minSeverity ?? this.minSeverity,
      maxPerHour: maxPerHour ?? this.maxPerHour,
      debounceSeconds: debounceSeconds ?? this.debounceSeconds,
      titleTemplate: clearTitleTemplate
          ? null
          : (titleTemplate ?? this.titleTemplate),
      bodyTemplate: clearBodyTemplate
          ? null
          : (bodyTemplate ?? this.bodyTemplate),
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'transports': transports.map((t) => t.storageKey).toList(),
    'minSeverity': minSeverity.name,
    'maxPerHour': maxPerHour,
    'debounceSeconds': debounceSeconds,
    'titleTemplate': titleTemplate,
    'bodyTemplate': bodyTemplate,
    'enabled': enabled,
  };

  factory NotificationRoutingRule.fromJson(Map<String, dynamic> json) {
    final transportsRaw = json['transports'];
    final transports = <NotificationTransportKind>[];
    if (transportsRaw is List) {
      for (final entry in transportsRaw) {
        if (entry is String) {
          final t = NotificationTransportKind.fromStorageKey(entry);
          if (t != null) transports.add(t);
        }
      }
    }
    final sevName = json['minSeverity'] as String? ?? 'info';
    final severity = EventSeverity.values.firstWhere(
      (e) => e.name == sevName,
      orElse: () => EventSeverity.info,
    );
    return NotificationRoutingRule(
      transports: transports.isEmpty
          ? const [NotificationTransportKind.inApp]
          : transports,
      minSeverity: severity,
      maxPerHour: (json['maxPerHour'] as num?)?.toInt() ?? 0,
      debounceSeconds: (json['debounceSeconds'] as num?)?.toInt() ?? 0,
      titleTemplate: json['titleTemplate'] as String?,
      bodyTemplate: json['bodyTemplate'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
    transports,
    minSeverity,
    maxPerHour,
    debounceSeconds,
    titleTemplate,
    bodyTemplate,
    enabled,
  ];
}

/// The full per-category routing table.
///
/// Persisted under a single settings key (`notification_routing_matrix`)
/// as JSON. Missing categories fall back to a built-in default that the
/// router seeds on first access.
class NotificationRoutingMatrix extends Equatable {
  /// Master "notifications enabled" switch. Mirrors the existing
  /// `AppSettingsState.notificationsEnabled` flag, but stays local to the
  /// router so the matrix is self-contained.
  final bool enabled;

  final Map<NotificationCategory, NotificationRoutingRule> rules;

  const NotificationRoutingMatrix({this.enabled = true, this.rules = const {}});

  NotificationRoutingRule ruleFor(NotificationCategory category) {
    return rules[category] ?? _defaultRuleFor(category);
  }

  NotificationRoutingMatrix copyWith({
    bool? enabled,
    Map<NotificationCategory, NotificationRoutingRule>? rules,
  }) {
    return NotificationRoutingMatrix(
      enabled: enabled ?? this.enabled,
      rules: rules ?? this.rules,
    );
  }

  NotificationRoutingMatrix withRule(
    NotificationCategory category,
    NotificationRoutingRule rule,
  ) {
    final next = Map<NotificationCategory, NotificationRoutingRule>.from(rules);
    next[category] = rule;
    return copyWith(rules: next);
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'rules': {
      for (final entry in rules.entries)
        entry.key.storageKey: entry.value.toJson(),
    },
  };

  factory NotificationRoutingMatrix.fromJson(Map<String, dynamic> json) {
    final rulesRaw = json['rules'];
    final parsed = <NotificationCategory, NotificationRoutingRule>{};
    if (rulesRaw is Map<String, dynamic>) {
      rulesRaw.forEach((key, value) {
        final cat = NotificationCategory.fromStorageKey(key);
        if (cat != null && value is Map<String, dynamic>) {
          parsed[cat] = NotificationRoutingRule.fromJson(value);
        }
      });
    }
    return NotificationRoutingMatrix(
      enabled: json['enabled'] as bool? ?? true,
      rules: parsed,
    );
  }

  /// Built-in defaults: in-app for everything; the categories the mobile
  /// push feed escalates also opt into systemPush.
  ///
  /// After the architecture-unification collapse the [SystemPushTransport] is
  /// the single mobile-push producer, so the default matrix must route to
  /// systemPush every category the (now demoted) PushNotificationService used
  /// to push — otherwise the collapse would silently drop pushes. That is the
  /// 8 critical-by-default categories PLUS the three non-critical completion
  /// milestones the legacy feed pushed (sequenceCompleted, targetCompleted,
  /// meridianFlipPerformed). The per-event toggle still gates each of those
  /// inside the transport via [PushNotificationConfig].
  factory NotificationRoutingMatrix.defaults() {
    const inApp = [NotificationTransportKind.inApp];
    const inAppPush = [
      NotificationTransportKind.inApp,
      NotificationTransportKind.systemPush,
    ];
    final rules = <NotificationCategory, NotificationRoutingRule>{
      for (final c in NotificationCategory.values)
        c: NotificationRoutingRule(
          transports: _systemPushByDefault(c) ? inAppPush : inApp,
          minSeverity: c.defaultSeverity,
        ),
    };
    return NotificationRoutingMatrix(enabled: true, rules: rules);
  }

  @override
  List<Object?> get props => [enabled, rules];
}

/// Categories routed to systemPush by default. The 8 critical-by-default
/// categories plus the three non-critical completion milestones the legacy
/// mobile feed escalated, so the single-producer collapse loses no push.
bool _systemPushByDefault(NotificationCategory c) {
  if (c.isCritical) return true;
  switch (c) {
    case NotificationCategory.sequenceCompleted:
    case NotificationCategory.targetCompleted:
    case NotificationCategory.meridianFlipPerformed:
      return true;
    default:
      return false;
  }
}

NotificationRoutingRule _defaultRuleFor(NotificationCategory category) {
  return NotificationRoutingMatrix.defaults().ruleFor(category);
}
