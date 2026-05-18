import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_event;

/// The active target during execution.
///
/// Prefers the live `currentTarget` name from `sequenceProgressProvider`
/// (set by the executor) and falls back to the first `TargetHeaderNode`
/// in the loaded sequence. Returns null when nothing is loaded — the
/// dashboard shows an idle state in that case.
final runDashboardActiveTargetProvider = Provider<TargetHeaderNode?>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  if (sequence == null) return null;

  final progress = ref.watch(sequenceProgressProvider);
  final liveName = progress.currentTarget;

  if (liveName != null && liveName.isNotEmpty) {
    for (final t in sequence.targetHeaders) {
      if (t.targetName == liveName) return t;
    }
  }

  if (sequence.targetHeaders.isNotEmpty) {
    return sequence.targetHeaders.first;
  }
  return null;
});

/// Sky-derived stats for the active target evaluated against the observer
/// location stored in app settings. Returns null when location isn't set or
/// no target is active.
class RunDashboardSkyStats {
  /// Current altitude in degrees.
  final double altitudeDeg;

  /// Azimuth in degrees (0 = north, 90 = east).
  final double azimuthDeg;

  /// Time remaining until the target falls below the user-configured
  /// effective horizon. `null` when the target is circumpolar with
  /// respect to that horizon, [Duration.zero] when it's already below.
  final Duration? timeToSet;

  /// Time remaining until meridian transit, or null if already past.
  final Duration? timeToTransit;

  /// The horizon (in degrees) that [timeToSet] was computed against —
  /// kept here so the UI can label the stat correctly when the user
  /// changes the effective horizon between non-zero (e.g. 20°) values.
  final double horizonDeg;

  const RunDashboardSkyStats({
    required this.altitudeDeg,
    required this.azimuthDeg,
    required this.timeToSet,
    required this.timeToTransit,
    required this.horizonDeg,
  });
}

final runDashboardSkyStatsProvider =
    Provider<RunDashboardSkyStats?>((ref) {
  final target = ref.watch(runDashboardActiveTargetProvider);
  if (target == null) return null;

  final location = ref.watch(appObserverLocationProvider);
  if (location == null) return null;

  // Single shared 30s tick across the whole dashboard. Sky altitude only
  // moves at ~0.25°/min so a 30s cadence is plenty for the dashboard
  // header and avoids waking the executor.
  final tickAsync = ref.watch(tickerProvider(TickerCadence.thirtySeconds));
  final now = tickAsync.valueOrNull ?? DateTime.now();

  final scheduler = ref.read(schedulerServiceProvider);
  final (altitude, azimuth) = scheduler.calculateAltAz(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    time: now,
    latitudeDegrees: location.latitude,
    longitudeDegrees: location.longitude,
  );

  final transit = scheduler.calculateTransitTime(
    raHours: target.raHours,
    date: now.toUtc(),
    longitudeDegrees: location.longitude,
  );
  Duration? timeToTransit;
  if (transit.isAfter(now)) {
    timeToTransit = transit.difference(now);
  }

  // The same effectiveHorizonDeg is consumed by the planetarium altitude
  // card via `effectiveHorizonDegProvider`, so this stat matches the
  // planetarium's "Time to set" exactly.
  final horizonDeg = ref.watch(effectiveHorizonDegProvider);
  final timeToSet = scheduler.nextSetTime(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    now: now,
    latitudeDegrees: location.latitude,
    longitudeDegrees: location.longitude,
    horizonDeg: horizonDeg,
  );

  return RunDashboardSkyStats(
    altitudeDeg: altitude,
    azimuthDeg: azimuth,
    timeToSet: timeToSet,
    timeToTransit: timeToTransit,
    horizonDeg: horizonDeg,
  );
});

/// Per-filter integration data for the active session, in seconds.
///
/// Combines:
///   * In-flight session progress (from `sequenceProgressProvider`,
///     which gives the *current* filter only) — kept zero for non-current
///     filters because the executor doesn't yet maintain a per-filter map.
///   * Persisted accepted-frame totals from the database for the active
///     `dbSessionId` (most-accurate "what's already on disk").
///
/// We sum the two so the bar reads as "total acquired so far this run."
class RunDashboardFilterTotals {
  /// Filter name -> seconds of integration acquired this session.
  final Map<String, double> integrationSecs;

  /// Filter name -> goal seconds taken from each `ExposureNode` in the
  /// loaded sequence (count * durationSecs). When the same filter is
  /// reused across multiple exposure nodes the values accumulate.
  final Map<String, double> goalSecs;

  const RunDashboardFilterTotals({
    required this.integrationSecs,
    required this.goalSecs,
  });

  static const empty =
      RunDashboardFilterTotals(integrationSecs: {}, goalSecs: {});

  /// Returns true if no exposures are configured for any filter.
  bool get isEmpty => integrationSecs.isEmpty && goalSecs.isEmpty;
}

/// Compute the goal totals from the loaded sequence's exposure nodes.
Map<String, double> _computeGoalSecs(Sequence? sequence) {
  if (sequence == null) return const {};
  final out = <String, double>{};
  for (final node in sequence.nodes.values.whereType<ExposureNode>()) {
    if (node.frameType != FrameType.light) continue;
    if (!node.isEnabled) continue;
    final filter = (node.filter == null || node.filter!.isEmpty)
        ? 'Unfiltered'
        : node.filter!;
    out[filter] = (out[filter] ?? 0.0) + node.totalDurationSecs;
  }
  return out;
}

/// Pulls accepted light-frame integration totals from the database for the
/// session id provided.
final runDashboardSessionFilterTotalsProvider =
    FutureProvider.family<Map<String, double>, int>((ref, sessionId) async {
  final dao = ref.watch(imagesDaoProvider);
  final images = await dao.getImagesForSession(sessionId);
  final totals = <String, double>{};
  for (final img in images) {
    if (img.frameType != 'light') continue;
    if (!img.isAccepted) continue;
    final filter = (img.filter == null || img.filter!.isEmpty)
        ? 'Unfiltered'
        : img.filter!;
    totals[filter] = (totals[filter] ?? 0.0) + img.exposureDuration;
  }
  return totals;
});

/// Combined per-filter totals + goals for the active sequence/session.
final runDashboardFilterTotalsProvider =
    Provider<RunDashboardFilterTotals>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  final goals = _computeGoalSecs(sequence);

  final sessionId = ref.watch(sessionStateProvider).dbSessionId;
  if (sessionId == null) {
    return RunDashboardFilterTotals(
      integrationSecs: const {},
      goalSecs: goals,
    );
  }

  final totalsAsync =
      ref.watch(runDashboardSessionFilterTotalsProvider(sessionId));
  final totals = totalsAsync.valueOrNull ?? const <String, double>{};

  return RunDashboardFilterTotals(
    integrationSecs: totals,
    goalSecs: goals,
  );
});

/// Severity classification used by the trigger feed.
enum RunDashboardEventSeverity { info, warning, error, critical }

/// A normalised event entry for the trigger feed.
class RunDashboardEvent {
  /// Stable identity for de-duplication / banner dismissal. Sourced from
  /// the bridge's monotonic `eventId`.
  final BigInt eventId;
  final DateTime time;
  final RunDashboardEventSeverity severity;
  final String category;
  final String title;
  final String message;

  /// True for events that the user must not miss — drives the persistent
  /// banner at the top of the dashboard.
  final bool isCritical;

  const RunDashboardEvent({
    required this.eventId,
    required this.time,
    required this.severity,
    required this.category,
    required this.title,
    required this.message,
    required this.isCritical,
  });
}

RunDashboardEventSeverity _mapSeverity(bridge_event.EventSeverity sev) {
  switch (sev) {
    case bridge_event.EventSeverity.info:
      return RunDashboardEventSeverity.info;
    case bridge_event.EventSeverity.warning:
      return RunDashboardEventSeverity.warning;
    case bridge_event.EventSeverity.error:
      return RunDashboardEventSeverity.error;
    case bridge_event.EventSeverity.critical:
      return RunDashboardEventSeverity.critical;
  }
}

String _categoryLabel(bridge_event.EventCategory cat) {
  switch (cat) {
    case bridge_event.EventCategory.equipment:
      return 'Equipment';
    case bridge_event.EventCategory.imaging:
      return 'Imaging';
    case bridge_event.EventCategory.guiding:
      return 'Guiding';
    case bridge_event.EventCategory.sequencer:
      return 'Sequencer';
    case bridge_event.EventCategory.safety:
      return 'Safety';
    case bridge_event.EventCategory.system:
      return 'System';
    case bridge_event.EventCategory.polarAlignment:
      return 'Polar align';
  }
}

/// Convert a freezed bridge event into the dashboard's compact model.
///
/// Uses the exhaustive switch helpers in `event_display.dart` so a new
/// payload variant becomes a compile error here instead of a silent
/// "Unknown event" row on the live rig.
RunDashboardEvent _toDashboardEvent(bridge_event.NightshadeEvent event) {
  final ms = event.timestamp.toInt();
  final severity = _mapSeverity(event.severity);
  final isCritical = bridge_event.isCriticalEvent(event);
  return RunDashboardEvent(
    eventId: event.eventId,
    time: DateTime.fromMillisecondsSinceEpoch(ms),
    severity: isCritical ? RunDashboardEventSeverity.critical : severity,
    category: _categoryLabel(event.category),
    title: bridge_event.nightshadeEventDisplayTitle(event),
    message: bridge_event.nightshadeEventDisplayDetail(event),
    isCritical: isCritical,
  );
}

/// Last N events (default 5) classified for the trigger feed.
///
/// Built off the existing `eventHistoryProvider` so we don't run a second
/// subscription. The rendering layer can configure how many to show.
final runDashboardRecentEventsProvider =
    Provider.family<List<RunDashboardEvent>, int>((ref, limit) {
  final history = ref.watch(eventHistoryProvider);
  return history.take(limit).map(_toDashboardEvent).toList(growable: false);
});

// ============================================================================
// Critical event escalation
// ============================================================================

/// State of critical events that the user has *not* dismissed yet.
///
/// A user who walks away from the laptop for an hour and comes back needs
/// to be able to see at-a-glance whether anything critical happened. The
/// trigger feed alone is not enough — it only holds 5 rows and they
/// scroll off. Critical events are escalated by:
///
///   * Holding them in this notifier indefinitely (until the user
///     dismisses them or clears via "Mark all seen").
///   * Rendering a persistent banner above the Run Dashboard
///     (`run_dashboard_critical_banner.dart`).
///   * Forwarding them to [uiNotificationProvider] as toast / center
///     notifications so the global app notification queue surfaces them
///     consistently with other in-app alerts.
///   * Optionally firing an audible alert (system bell) when the user has
///     enabled `audibleAlertsOnCritical` in settings.
class RunDashboardCriticalEventsNotifier
    extends StateNotifier<List<RunDashboardEvent>> {
  RunDashboardCriticalEventsNotifier() : super(const []);

  /// Maximum number of unsigned events to retain. If the user is
  /// genuinely racking up dozens of unresolved critical events something
  /// is very wrong, but we still want to bound memory.
  static const int _maxRetained = 50;

  void add(RunDashboardEvent event) {
    if (!mounted) return;
    // Skip exact duplicates (same eventId) — the bridge emits the same
    // event to multiple subscribers and we may receive it twice.
    if (state.any((e) => e.eventId == event.eventId)) return;
    final next = [event, ...state];
    if (next.length > _maxRetained) {
      next.removeRange(_maxRetained, next.length);
    }
    state = next;
  }

  void dismiss(BigInt eventId) {
    if (!mounted) return;
    state = state.where((e) => e.eventId != eventId).toList();
  }

  void clearAll() {
    if (!mounted) return;
    state = const [];
  }
}

final runDashboardCriticalEventsProvider = StateNotifierProvider<
    RunDashboardCriticalEventsNotifier, List<RunDashboardEvent>>((ref) {
  return RunDashboardCriticalEventsNotifier();
});

/// Side-effect provider: subscribes to the event history and routes
/// critical events through the dashboard notifier, the in-app
/// notification queue, and (if enabled) the platform audible-bell.
///
/// This provider must be `ref.watch`-ed somewhere in the widget tree for
/// the side effects to run. The Run Dashboard scaffolding watches it in
/// its build method.
final runDashboardCriticalEventsBridgeProvider = Provider<void>((ref) {
  // Use ref.listen on the history so we react to new entries without
  // depending on the order or count of rebuilds.
  BigInt? lastSeenId;
  ref.listen<List<bridge_event.NightshadeEvent>>(
    eventHistoryProvider,
    (previous, next) {
      if (next.isEmpty) return;
      // Iterate from oldest-to-newest among entries the bridge hasn't
      // seen before. The history list is newest-first.
      final fresh = <bridge_event.NightshadeEvent>[];
      for (final event in next) {
        if (lastSeenId != null && event.eventId <= lastSeenId!) break;
        fresh.add(event);
      }
      if (fresh.isEmpty) return;
      lastSeenId = fresh.first.eventId;

      // Process oldest-first so the most recent ends up at the head of
      // the notifier's state list.
      for (final event in fresh.reversed) {
        if (!bridge_event.isCriticalEvent(event)) continue;
        final dashboardEvent = _toDashboardEvent(event);
        ref
            .read(runDashboardCriticalEventsProvider.notifier)
            .add(dashboardEvent);

        // Forward to the in-app notification queue. Title is the
        // category, message is the event detail (or title if there is
        // no detail). Long duration so the toast doesn't time out while
        // the user is reading.
        final notif = ref.read(uiNotificationProvider.notifier);
        final detail = dashboardEvent.message.isNotEmpty
            ? dashboardEvent.message
            : dashboardEvent.title;
        notif.showError(
          detail,
          title: 'Critical · ${dashboardEvent.category}',
          duration: const Duration(seconds: 30),
        );
      }
    },
    fireImmediately: true,
  );
});
