import 'dart:collection';

import '../auth_policy.dart';
import 'timing.dart';

/// Resolves bearer tokens to their [HeadlessTokenScope] using constant-time
/// comparison and a token-bucket rate limiter on comparison failures.
///
/// Why: A naive `Map[token]` lookup leaks per-character timing because Dart's
/// String hashCode comparisons short-circuit. We iterate the full token table
/// and XOR-compare in constant time. The failure rate-limiter prevents the
/// O(N*L) loop from being weaponised into a CPU exhaustion vector by an
/// attacker spamming bad tokens.
class TokenResolver {
  final UnmodifiableMapView<String, HeadlessTokenScope> _tokensByValue;
  final int maxFailuresPerWindow;
  final Duration failureWindow;
  final DateTime Function() _now;

  // Per-client failure counters. Kept small (LRU-evicted) since it grows on
  // bad-token attempts only.
  final LinkedHashMap<String, _FailureBucket> _failureBuckets =
      LinkedHashMap<String, _FailureBucket>();
  static const int _maxFailureBuckets = 1024;

  TokenResolver({
    required Map<String, HeadlessTokenScope> tokensByValue,
    this.maxFailuresPerWindow = 30,
    this.failureWindow = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _tokensByValue =
            UnmodifiableMapView<String, HeadlessTokenScope>(tokensByValue),
        _now = now ?? DateTime.now;

  bool get isEmpty => _tokensByValue.isEmpty;
  bool get isNotEmpty => _tokensByValue.isNotEmpty;
  int get tokenCount => _tokensByValue.length;

  /// Resolve [presented] to a scope using constant-time comparison.
  /// Returns `null` if the token is missing, empty, or no match found.
  HeadlessTokenScope? resolve(String? presented) {
    if (presented == null || presented.isEmpty) {
      return null;
    }
    HeadlessTokenScope? matched;
    // Iterate the full map; do not break early so timing is independent of
    // which entry (if any) matched.
    for (final entry in _tokensByValue.entries) {
      if (constantTimeCompareStrings(entry.key, presented)) {
        matched = entry.value;
      }
    }
    return matched;
  }

  /// Returns true iff [clientKey] is currently rate-limited from making
  /// further token-comparison attempts.
  bool isRateLimited(String clientKey) {
    final bucket = _failureBuckets[clientKey];
    if (bucket == null) return false;
    bucket.prune(_now(), failureWindow);
    return bucket.failures.length >= maxFailuresPerWindow;
  }

  /// Records a failed token comparison from [clientKey].
  void recordFailure(String clientKey) {
    final now = _now();
    var bucket = _failureBuckets.remove(clientKey);
    bucket ??= _FailureBucket();
    bucket.prune(now, failureWindow);
    bucket.failures.add(now);
    _failureBuckets[clientKey] = bucket;
    while (_failureBuckets.length > _maxFailureBuckets) {
      _failureBuckets.remove(_failureBuckets.keys.first);
    }
  }

  /// Clears failure tracking for [clientKey] (e.g. after a success).
  void clearFailures(String clientKey) {
    _failureBuckets.remove(clientKey);
  }

  /// Distinct scopes available across all configured tokens, in stable order.
  List<HeadlessTokenScope> distinctScopes() {
    final seen = <HeadlessTokenScope>{};
    for (final scope in _tokensByValue.values) {
      seen.add(scope);
    }
    return seen.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
  }
}

class _FailureBucket {
  final List<DateTime> failures = [];

  void prune(DateTime now, Duration window) {
    failures.removeWhere((t) => now.difference(t) > window);
  }
}
