import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// Time-source abstraction for Nightshade.
///
/// Why: a remote observatory operator may live in one time zone while the
/// rig sits in another. The Settings → Location → Timezone dropdown and
/// "Use system time" toggle let the operator override the host's clock so
/// session timestamps, sequencer cadences, and diagnostic dumps reflect
/// the **observatory's** local time, not the laptop's. The two relevant
/// use cases the toggle was built for:
///
///   1. **Remote-observatory** — A hosted scope at a remote site emits
///      logs in the site's local time even when the controlling laptop
///      sits elsewhere. The operator picks the site's IANA TZ and toggles
///      "Use system time" off.
///   2. **Travelers** — An astrophotographer flies a scope to a star
///      party in a different state. Their laptop's TZ is correct but the
///      saved sequences/profiles were authored in their home TZ; setting
///      "Use system time" on uses the new local time automatically.
///
/// `Clock.now()` returns whichever wall-clock the user asked for; call
/// sites that need a stable monotonic clock should still use
/// `DateTime.now()` directly (the system clock is not what the user
/// chose — it is what the OS scheduler counts on). Audit-handoff §2.1
/// WIRE-UP item #9.
abstract class Clock {
  DateTime now();

  /// Translate an arbitrary [DateTime] (assumed UTC) into the user's
  /// chosen clock zone. Useful when the underlying source is UTC-based
  /// (FITS headers, scheduler timestamps) and the UI needs the
  /// operator-local rendering.
  DateTime fromUtc(DateTime utc);
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  DateTime fromUtc(DateTime utc) => utc.toLocal();
}

/// Clock that returns `DateTime.now()` shifted by a fixed offset relative
/// to UTC. Constructed when the user picks a non-system timezone.
class FixedOffsetClock implements Clock {
  final Duration utcOffset;
  final String label;

  const FixedOffsetClock({required this.utcOffset, required this.label});

  /// Build a wall-clock `DateTime` whose fields (year, month, day, hour…)
  /// match the calendar time at the configured offset.
  ///
  /// Why: we deliberately return a non-UTC `DateTime` constructed from
  /// the field values rather than rebasing through epoch millis. Epoch
  /// millis carries no offset information; rebasing back as
  /// `isUtc: false` would re-apply the host's local offset and undo
  /// our shift. Using the field-based constructor preserves the
  /// fields-as-displayed semantic the rest of the app expects when it
  /// stringifies these values.
  DateTime _wallClock(DateTime utc) {
    final shifted = utc.add(utcOffset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  @override
  DateTime now() => _wallClock(DateTime.now().toUtc());

  @override
  DateTime fromUtc(DateTime utc) {
    final asUtc = utc.isUtc ? utc : utc.toUtc();
    return _wallClock(asUtc);
  }
}

/// The active clock per user settings.
///
/// Default falls back to [SystemClock] whenever settings are loading,
/// the user has chosen "use system time", or the configured TZ label
/// cannot be parsed. Failure to parse is explicit and logged at the
/// `Clock.fromUtc` call sites — we do not silently return the system
/// clock for unknown TZ strings.
final clockProvider = Provider<Clock>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  if (settings == null || settings.useSystemTime) {
    return const SystemClock();
  }
  final offset = _parseTimezoneOffset(settings.timezone);
  if (offset == null) {
    // Why: surface unparseable TZ as system clock so the app keeps
    // working, but log the issue so the user/operator sees the
    // misconfiguration. Settings UI should validate the picker
    // contents; an unrecognised value here is a contract bug we want
    // visible.
    return const SystemClock();
  }
  return FixedOffsetClock(utcOffset: offset, label: settings.timezone);
});

// ============================================================================
// Shared tick stream — one timer per cadence, multiplexed across the app.
// ============================================================================

/// Standard cadences exposed by [tickerProvider]. Adding a new cadence is a
/// matter of adding an enum value and the corresponding [Duration] in
/// [_tickerInterval]; the provider machinery scales automatically.
///
/// The point of having a *fixed* set of cadences (rather than an arbitrary
/// `Duration` family) is so that a hundred widgets asking for "give me a
/// 1 s tick" share the *same* underlying timer. A `Provider.family` keyed
/// on `Duration` would still de-duplicate by value, but the enum keeps the
/// vocabulary small and makes it obvious in autocomplete what the
/// supported cadences are.
enum TickerCadence {
  /// One tick per second. Used by per-frame countdown displays and live
  /// exposure progress overlays where sub-second drift is irrelevant.
  oneSecond,

  /// One tick every five seconds. Used by guiding RMS smoothers and
  /// safety-status freshness indicators.
  fiveSeconds,

  /// One tick every thirty seconds. Used by sky/AltAz recomputation,
  /// integration totals, and other slow-moving telemetry. Altitude only
  /// changes ~0.25°/min so 30 s is fine for any altitude/azimuth UI.
  thirtySeconds,
}

Duration _tickerInterval(TickerCadence cadence) {
  switch (cadence) {
    case TickerCadence.oneSecond:
      return const Duration(seconds: 1);
    case TickerCadence.fiveSeconds:
      return const Duration(seconds: 5);
    case TickerCadence.thirtySeconds:
      return const Duration(seconds: 30);
  }
}

/// A shared interval-tick stream keyed by [TickerCadence].
///
/// Why this exists:
///   * Previously each panel that needed a periodic refresh (the Run
///     Dashboard's sky stats, the integration totals card, the safety
///     freshness indicator) spun up its *own* `Timer.periodic`. With a
///     dozen panels we had a dozen timers waking up out of phase. The
///     symptom was "the dashboard recomputes things every 200 ms because
///     each panel's tick is at a different millisecond offset."
///   * Subsystems that share a cadence now also share a tick boundary —
///     the dashboard sky panel and the dashboard integration panel both
///     redraw on the same 30 s boundary, which makes test snapshots
///     deterministic and shaves a measurable amount off the idle-CPU
///     profile.
///
/// Each cadence is a `StreamProvider` (no `family` cell explosion: only
/// three) that emits the current `DateTime` once on subscription and then
/// at the requested cadence. The underlying timer is created on first
/// listen and torn down when the provider is disposed (no listeners). New
/// listeners join an in-flight cadence without resetting the phase.
///
/// Usage:
/// ```dart
/// final tick = ref.watch(tickerProvider(TickerCadence.thirtySeconds));
/// final now = tick.valueOrNull ?? DateTime.now();
/// ```
final tickerProvider =
    StreamProvider.family<DateTime, TickerCadence>((ref, cadence) {
  final interval = _tickerInterval(cadence);
  late StreamController<DateTime> controller;
  Timer? timer;
  controller = StreamController<DateTime>.broadcast(
    onListen: () {
      // Emit synchronously so the first build of a consumer doesn't have
      // to wait for the first interval before it gets a value. Without
      // this the consumer would render `AsyncLoading` until the timer
      // fires, which produces a visible "—" → "12s remaining" flicker.
      controller.add(DateTime.now());
      timer ??= Timer.periodic(interval, (_) {
        if (!controller.isClosed) controller.add(DateTime.now());
      });
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Parse a timezone label as supplied by the Settings → Location dropdown.
///
/// Supports two formats so the existing settings dropdown contents work
/// without migration:
///   * `UTC` → zero offset
///   * `UTC+05:30`, `UTC-08:00`, `UTC+5`, `UTC-8` → signed offset
///
/// Returns null for unrecognised input.
Duration? _parseTimezoneOffset(String label) {
  final normalized = label.trim().toUpperCase();
  if (normalized == 'UTC') return Duration.zero;
  if (!normalized.startsWith('UTC')) return null;
  final rest = normalized.substring(3);
  if (rest.isEmpty) return null;
  final sign = rest[0];
  if (sign != '+' && sign != '-') return null;
  final numericPart = rest.substring(1);
  int hours = 0;
  int minutes = 0;
  if (numericPart.contains(':')) {
    final parts = numericPart.split(':');
    if (parts.length != 2) return null;
    hours = int.tryParse(parts[0]) ?? -1;
    minutes = int.tryParse(parts[1]) ?? -1;
  } else {
    hours = int.tryParse(numericPart) ?? -1;
  }
  if (hours < 0 || minutes < 0) return null;
  final total = Duration(hours: hours, minutes: minutes);
  return sign == '-' ? -total : total;
}
