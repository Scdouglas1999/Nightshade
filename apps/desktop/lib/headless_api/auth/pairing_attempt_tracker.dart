import 'dart:collection';

/// Per-client failed-pairing tracker with bounded LRU eviction.
///
/// Why LRU: An unauthenticated attacker can pair-attempt from any source IP.
/// Without eviction, the underlying map would grow unbounded under attack
/// (one entry per spoofed source). The LinkedHashMap recency order gives us
/// O(1) eviction of the least-recently-touched client when the cap is hit.
class PairingAttemptTracker {
  final int maxClients;
  final int maxFailuresPerWindow;
  final Duration failureWindow;
  final Duration lockoutDuration;
  final DateTime Function() _now;

  // LinkedHashMap preserves insertion/touch order so we can evict the
  // least-recently-used client when [maxClients] is exceeded.
  final LinkedHashMap<String, _PairingAttemptState> _attempts =
      LinkedHashMap<String, _PairingAttemptState>();

  PairingAttemptTracker({
    this.maxClients = 1024,
    this.maxFailuresPerWindow = 5,
    this.failureWindow = const Duration(minutes: 10),
    this.lockoutDuration = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Returns the [Duration] until [clientKey] may attempt again, or `null`
  /// if it is currently allowed.
  Duration? retryAfter(String clientKey) {
    final state = _attempts[clientKey];
    if (state == null) {
      return null;
    }

    final now = _now();
    state.prune(now, failureWindow);

    final lockedUntil = state.lockedUntil;
    if (lockedUntil == null) {
      if (state.isEmpty) {
        _attempts.remove(clientKey);
      } else {
        _touch(clientKey, state);
      }
      return null;
    }

    if (now.isAfter(lockedUntil)) {
      _attempts.remove(clientKey);
      return null;
    }

    _touch(clientKey, state);
    return lockedUntil.difference(now);
  }

  /// Records a failed pairing attempt for [clientKey]. After
  /// [maxFailuresPerWindow] failures within [failureWindow] the client is
  /// locked out for [lockoutDuration].
  void recordFailure(String clientKey) {
    final now = _now();
    var state = _attempts.remove(clientKey);
    state ??= _PairingAttemptState();
    state.prune(now, failureWindow);
    state.failures.add(now);

    if (state.failures.length >= maxFailuresPerWindow) {
      state.lockedUntil = now.add(lockoutDuration);
      state.failures.clear();
    }

    _attempts[clientKey] = state; // Re-insert at MRU position.
    _evictIfOverCapacity();
  }

  /// Clears all failure history for [clientKey] (e.g. after a success).
  void clear(String clientKey) {
    _attempts.remove(clientKey);
  }

  /// Visible for testing.
  int get clientCount => _attempts.length;

  void _touch(String clientKey, _PairingAttemptState state) {
    // Re-insert to move to MRU end of the LinkedHashMap.
    _attempts.remove(clientKey);
    _attempts[clientKey] = state;
  }

  void _evictIfOverCapacity() {
    while (_attempts.length > maxClients) {
      // LinkedHashMap.keys is iteration order; first key is LRU.
      final lru = _attempts.keys.first;
      _attempts.remove(lru);
    }
  }
}

class _PairingAttemptState {
  final List<DateTime> failures = [];
  DateTime? lockedUntil;

  void prune(DateTime now, Duration window) {
    failures.removeWhere((attempt) => now.difference(attempt) > window);
    final until = lockedUntil;
    if (until != null && now.isAfter(until)) {
      lockedUntil = null;
    }
  }

  bool get isEmpty => failures.isEmpty && lockedUntil == null;
}
