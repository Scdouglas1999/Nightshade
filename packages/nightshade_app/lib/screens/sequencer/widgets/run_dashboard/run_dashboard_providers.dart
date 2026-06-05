import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
// EventCategory exists in both core (via the nightshade_backend re-export
// chain in the barrel) and the bridge. The unprefixed barrel above gives
// us the core enum; bridge_event below is prefixed so the two stay
// disambiguated at call sites in this file.
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
  /// Filter name -> seconds of *accepted* integration acquired this session.
  /// This is the integration that actually counts toward the goal — rejected
  /// subs are excluded so the bar never over-reports usable signal.
  final Map<String, double> integrationSecs;

  /// Filter name -> seconds of *total acquired* integration this session,
  /// i.e. accepted + rejected. Surfaced separately so the operator can see
  /// how much time was spent versus how much produced usable data (a large
  /// gap means a lot of subs are being thrown away — clouds, wind, focus).
  final Map<String, double> totalAcquiredSecs;

  /// Filter name -> goal seconds taken from each `ExposureNode` in the
  /// loaded sequence (count * durationSecs). When the same filter is
  /// reused across multiple exposure nodes the values accumulate.
  final Map<String, double> goalSecs;

  /// The filter the executor is currently exposing, or null when idle.
  final String? inFlightFilter;

  /// Elapsed seconds of the in-flight exposure (0 when idle). Kept separate
  /// from [integrationSecs] because the current sub hasn't been written to
  /// disk or accepted yet — folding it into the accepted total would lie.
  final double inFlightElapsedSecs;

  const RunDashboardFilterTotals({
    required this.integrationSecs,
    required this.totalAcquiredSecs,
    required this.goalSecs,
    this.inFlightFilter,
    this.inFlightElapsedSecs = 0.0,
  });

  static const empty = RunDashboardFilterTotals(
    integrationSecs: {},
    totalAcquiredSecs: {},
    goalSecs: {},
  );

  /// Returns true if no exposures are configured for any filter.
  bool get isEmpty => integrationSecs.isEmpty && goalSecs.isEmpty;

  /// Rejected (accepted-vs-total gap) seconds for [filter].
  double rejectedSecsFor(String filter) {
    final total = totalAcquiredSecs[filter] ?? 0.0;
    final accepted = integrationSecs[filter] ?? 0.0;
    final gap = total - accepted;
    return gap > 0 ? gap : 0.0;
  }
}

/// Accepted + total-acquired per-filter integration for a session.
class RunDashboardSessionIntegration {
  /// Filter -> accepted (isAccepted == true) light-frame seconds.
  final Map<String, double> acceptedSecs;

  /// Filter -> all light-frame seconds (accepted + rejected).
  final Map<String, double> totalSecs;

  const RunDashboardSessionIntegration({
    required this.acceptedSecs,
    required this.totalSecs,
  });

  static const empty =
      RunDashboardSessionIntegration(acceptedSecs: {}, totalSecs: {});
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

/// Pulls light-frame integration totals from the database for the session id
/// provided, split into accepted-only and total-acquired (accepted +
/// rejected). A single DB scan produces both so the dashboard can show "usable
/// vs spent" without a second query.
final runDashboardSessionIntegrationProvider = FutureProvider.family<
    RunDashboardSessionIntegration, int>((ref, sessionId) async {
  final dao = ref.watch(imagesDaoProvider);
  final images = await dao.getImagesForSession(sessionId);
  final accepted = <String, double>{};
  final total = <String, double>{};
  for (final img in images) {
    if (img.frameType != 'light') continue;
    final filter = (img.filter == null || img.filter!.isEmpty)
        ? 'Unfiltered'
        : img.filter!;
    total[filter] = (total[filter] ?? 0.0) + img.exposureDuration;
    if (img.isAccepted) {
      accepted[filter] = (accepted[filter] ?? 0.0) + img.exposureDuration;
    }
  }
  return RunDashboardSessionIntegration(
    acceptedSecs: accepted,
    totalSecs: total,
  );
});

/// Pulls accepted light-frame integration totals from the database for the
/// session id provided. Derived from [runDashboardSessionIntegrationProvider]
/// so callers that only need the accepted map (e.g. the budget panel) don't
/// trigger a second DB scan.
final runDashboardSessionFilterTotalsProvider =
    Provider.family<AsyncValue<Map<String, double>>, int>((ref, sessionId) {
  return ref
      .watch(runDashboardSessionIntegrationProvider(sessionId))
      .whenData((integration) => integration.acceptedSecs);
});

/// Combined per-filter totals + goals for the active sequence/session.
///
/// Surfaces three honest quantities per filter:
///   * accepted integration (counts toward the goal),
///   * total acquired integration (accepted + rejected; what was spent),
///   * the in-flight exposure's elapsed seconds against the current filter,
///     so the operator sees integration tick up live rather than jumping a
///     whole sub at a time once a frame is written.
final runDashboardFilterTotalsProvider =
    Provider<RunDashboardFilterTotals>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  final goals = _computeGoalSecs(sequence);

  final progress = ref.watch(sequenceProgressProvider);
  final exposure = ref.watch(exposureProgressProvider);
  final executionState = ref.watch(sequenceExecutionStateProvider);
  final isActive = executionState == SequenceExecutionState.running ||
      executionState == SequenceExecutionState.paused ||
      executionState == SequenceExecutionState.stopping;
  // Only treat the current exposure's elapsed time as "in flight" while the
  // executor is actually running a frame — not during downloads or when idle.
  final inFlightFilter = isActive ? progress.currentFilter : null;
  final inFlightElapsed = (isActive &&
          !exposure.isDownloading &&
          exposure.frameNumber > 0 &&
          exposure.elapsed > 0)
      ? exposure.elapsed
      : 0.0;

  final sessionId = ref.watch(sessionStateProvider).dbSessionId;
  if (sessionId == null) {
    return RunDashboardFilterTotals(
      integrationSecs: const {},
      totalAcquiredSecs: const {},
      goalSecs: goals,
      inFlightFilter: inFlightFilter,
      inFlightElapsedSecs: inFlightElapsed,
    );
  }

  final integration =
      ref.watch(runDashboardSessionIntegrationProvider(sessionId)).valueOrNull ??
          RunDashboardSessionIntegration.empty;

  return RunDashboardFilterTotals(
    integrationSecs: integration.acceptedSecs,
    totalAcquiredSecs: integration.totalSecs,
    goalSecs: goals,
    inFlightFilter: inFlightFilter,
    inFlightElapsedSecs: inFlightElapsed,
  );
});

/// Wave 3 Agent 3 — per-target integration budget progress for the
/// active TargetHeader. `null` when the active target has no budget
/// configured (so the dashboard hides the panel).
class RunDashboardBudgetProgress {
  /// The TargetHeader node id this progress applies to.
  final String targetId;

  /// Resolved per-filter cap (seconds), keyed by filter name. Computed
  /// from the budget config — same math as
  /// `IntegrationBudget::resolved_filter_cap` on the Rust side.
  final Map<String, double> resolvedCapSecs;

  /// Total budget cap (seconds). `0.0` when no total cap is set.
  final double totalSecs;

  /// Completed per-filter integration (seconds), pulled from the
  /// database's accepted-frame totals for the active session.
  final Map<String, double> completedSecs;

  /// True iff the budget is met (every per-filter cap reached OR
  /// total reached). Computed locally for UI; the Rust runtime is the
  /// authoritative source.
  final bool budgetMet;

  const RunDashboardBudgetProgress({
    required this.targetId,
    required this.resolvedCapSecs,
    required this.totalSecs,
    required this.completedSecs,
    required this.budgetMet,
  });

  double get completedTotalSecs =>
      completedSecs.values.fold(0.0, (a, b) => a + b);

  double get fraction {
    if (totalSecs > 0) {
      return (completedTotalSecs / totalSecs).clamp(0.0, 1.0);
    }
    final capSum =
        resolvedCapSecs.values.fold<double>(0, (a, b) => a + b);
    if (capSum <= 0) return 0;
    return (completedTotalSecs / capSum).clamp(0.0, 1.0);
  }
}

/// Wave 3 Agent 3 — surfaces the integration-budget progress for the
/// currently-active TargetHeader. Returns `null` when no target is
/// active or the active target has no budget configured.
///
/// Reads:
/// * `runDashboardActiveTargetProvider` — the in-flight target.
/// * `runDashboardSessionFilterTotalsProvider` — accepted-frame
///   integration per filter for the active session.
///
/// Computes the resolved per-filter caps locally (cheap; same math as
/// the Rust side) and asserts the "budget met" flag when every cap is
/// reached. The Rust runtime is still the authoritative gate — this
/// provider exists purely to render the panel.
final runDashboardActiveBudgetProvider =
    Provider<RunDashboardBudgetProgress?>((ref) {
  final target = ref.watch(runDashboardActiveTargetProvider);
  if (target == null) return null;
  final budget = target.integrationBudget;
  if (budget == null || !budget.isActive) return null;

  final resolvedCaps = <String, double>{};
  for (final filter in budget.perFilter.keys) {
    final cap = budget.resolvedFilterCap(filter);
    if (cap != null) resolvedCaps[filter] = cap;
  }

  final sessionId = ref.watch(sessionStateProvider).dbSessionId;
  final completedSecs = sessionId == null
      ? const <String, double>{}
      : ref
              .watch(runDashboardSessionFilterTotalsProvider(sessionId))
              .valueOrNull ??
          const <String, double>{};

  // Budget-met check mirrors `BudgetState::evaluate` on the Rust side.
  final completedTotal =
      completedSecs.values.fold<double>(0, (a, b) => a + b);
  final totalMet = budget.totalSecs > 0 && completedTotal >= budget.totalSecs;
  final allFiltersMet = resolvedCaps.isNotEmpty &&
      resolvedCaps.entries.every(
        (e) => (completedSecs[e.key] ?? 0) >= e.value,
      );
  final budgetMet = totalMet || allFiltersMet;

  return RunDashboardBudgetProgress(
    targetId: target.id,
    resolvedCapSecs: resolvedCaps,
    totalSecs: budget.totalSecs,
    completedSecs: completedSecs,
    budgetMet: budgetMet,
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

/// Cooldown between consecutive audible alerts so a storm of critical
/// events (e.g. a power loss that cascades into mount + camera + guider
/// disconnects in the same second) doesn't machine-gun-beep at the user.
const Duration _audibleAlertCooldown = Duration(seconds: 5);

/// Map bridge event categories to the `EventCategory` enum that
/// [PushNotificationService] expects on its synthetic-injection API.
/// Why two enums: the bridge layer's enum is generated from FRB and lives
/// in `nightshade_bridge`; `nightshade_core` has its own copy used by
/// services (`PushNotification.category` is the core enum).
EventCategory _bridgeCategoryToCore(
    bridge_event.EventCategory cat) {
  switch (cat) {
    case bridge_event.EventCategory.equipment:
      return EventCategory.equipment;
    case bridge_event.EventCategory.imaging:
      return EventCategory.imaging;
    case bridge_event.EventCategory.guiding:
      return EventCategory.guiding;
    case bridge_event.EventCategory.sequencer:
      return EventCategory.sequencer;
    case bridge_event.EventCategory.safety:
      return EventCategory.safety;
    case bridge_event.EventCategory.system:
      return EventCategory.system;
    case bridge_event.EventCategory.polarAlignment:
      return EventCategory.polarAlignment;
  }
}

/// True when the router's own backend event-stream classifier already routes
/// this event to systemPush — i.e. the eager-mounted [NotificationRouter] will
/// push it on its own from the core stream. The dashboard bridge must NOT also
/// push those, or the operator's phone pages twice for one alert.
///
/// This mirrors exactly the `isCriticalEvent` payload variants that the shared
/// [NotificationEventClassifier] maps to a systemPush-by-default category:
/// exposure-failed, weather-unsafe / emergency-stop, disk-low, sequencer
/// error / stop, and recovery-gave-up. The remaining critical events the
/// dashboard escalates (notably generic system errors / FITS save failures,
/// which the classifier returns null for) are NOT covered by the router, so
/// the bridge still forwards those — that is the gap this bridge exists to
/// fill. The router's content-signature dedup is a backstop; this predicate is
/// the primary, intent-level guard so the two paths never both page.
bool _routerClassifierAlreadyPushes(bridge_event.NightshadeEvent event) {
  final payload = event.payload;
  return switch (payload) {
    bridge_event.EventPayload_Imaging(field0: final v) => switch (v) {
        bridge_event.ImagingEvent_ExposureFailed() => true,
        bridge_event.ImagingEvent_ExposureFailedOld() => true,
        _ => false,
      },
    bridge_event.EventPayload_Safety(field0: final v) => switch (v) {
        bridge_event.SafetyEvent_WeatherUnsafe() => true,
        bridge_event.SafetyEvent_EmergencyStop() => true,
        _ => false,
      },
    bridge_event.EventPayload_System(field0: final v) => switch (v) {
        // The classifier maps only "disk*" system events to a category; a
        // generic SystemEvent.error classifies to null, so the bridge must
        // still push it (that is the gap below).
        bridge_event.SystemEvent_DiskSpaceLow() => true,
        _ => false,
      },
    bridge_event.EventPayload_Sequencer(field0: final v) => switch (v) {
        bridge_event.SequencerEvent_Error() => true,
        bridge_event.SequencerEvent_Stopped() => true,
        bridge_event.SequencerEvent_RecoveryGaveUp() => true,
        _ => false,
      },
    // Guiding / equipment events only reach this bridge as critical when they
    // carry critical severity (their normal error-severity StarLost /
    // Disconnected are NOT `isCriticalEvent`, so the classifier alone pushes
    // those). At critical severity the classifier only pushes the specific
    // StarLost/Disconnected/Error eventTypes; any OTHER critical guiding/
    // equipment event would classify to null and get no push. Rather than risk
    // MISSING such a page (errors-are-a-feature: never drop an operator
    // alert), we let the bridge forward these and rely on the router's
    // content-signature dedup to collapse the rare matching-copy overlap. A
    // possible duplicate is strictly safer than a missed critical page.
    _ => false,
  };
}

/// Side-effect provider: subscribes to the event history and routes
/// critical events through the dashboard notifier, the in-app
/// notification queue, the audible alert player, and the mobile push
/// notification stream.
///
/// This provider must be `ref.watch`-ed somewhere in the widget tree for
/// the side effects to run. The Run Dashboard scaffolding watches it in
/// its build method.
final runDashboardCriticalEventsBridgeProvider = Provider<void>((ref) {
  // Use ref.listen on the history so we react to new entries without
  // depending on the order or count of rebuilds.
  BigInt? lastSeenId;
  // Last time we played the audible alert. We hold this in the provider
  // closure scope so the cooldown survives provider rebuilds.
  DateTime? lastAlertAt;

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

      // Read settings once per batch; the user can't toggle these mid-batch
      // and re-reading per event would race the AsyncNotifier update.
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final audibleEnabled = settings?.audibleAlertsOnCritical ?? false;
      final soundChoice = settings?.criticalAlertSound ?? 'systemBell';
      final pushEnabled = settings?.pushCriticalAlerts ?? true;

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

        // Audible alert: respects the user setting + the 5-second cooldown
        // so a storm of critical events doesn't make the laptop sound like
        // a slot machine.
        if (audibleEnabled && soundChoice != 'none') {
          final now = DateTime.now();
          if (lastAlertAt == null ||
              now.difference(lastAlertAt!) >= _audibleAlertCooldown) {
            lastAlertAt = now;
            // Fire-and-forget: SystemSound.play returns Future<void> and we
            // don't gate further work on it. Errors from the platform
            // channel are surfaced via developer.log inside the player
            // rather than thrown — a failed audio cue must not crash the
            // event dispatch path.
            final player = ref.read(criticalAlertPlayerProvider);
            player.play(sound: soundChoice);
          }
        }

        // Mobile push notification: forwarded through the NotificationRouter
        // — the single systemPush producer after the architecture-unification
        // collapse. The router's SystemPushTransport broadcasts to paired
        // phones as a critical WebSocket message. This path covers criticality
        // classifications the router's core-stream classifier does not push on
        // its own (e.g. generic system errors / FITS save failures); for
        // events the classifier DOES recognise, the router's systemPush
        // content-signature dedup collapses this push and the classifier's
        // into exactly one page. The router honours the master push gate, so
        // the `pushEnabled` check here mirrors the user's `pushCriticalAlerts`
        // preference (an extra, cheap short-circuit).
        if (pushEnabled && !_routerClassifierAlreadyPushes(event)) {
          final router = ref.read(notificationRouterProvider);
          router.routeBridgeCriticalPush(
            title: 'Critical · ${dashboardEvent.category}',
            body: detail,
            eventType: bridge_event.nightshadeEventDisplayTitle(event),
            eventCategory: _bridgeCategoryToCore(event.category),
          );
        }
      }
    },
    fireImmediately: true,
  );
});
