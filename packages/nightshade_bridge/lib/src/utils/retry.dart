/// Exponential backoff retry utility for resilient connection handling
///
/// Provides configurable retry logic with exponential backoff for network
/// operations that may fail temporarily due to connectivity issues.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Configuration for exponential backoff retry behavior
class RetryConfig {
  /// Maximum number of retry attempts before giving up
  final int maxAttempts;

  /// Initial delay before the first retry
  final Duration initialDelay;

  /// Maximum delay between retries (caps exponential growth)
  final Duration maxDelay;

  /// Multiplier for exponential backoff (typically 2.0)
  final double multiplier;

  /// Whether to add random jitter to prevent thundering herd
  final bool jitter;

  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitter = true,
  });

  /// Aggressive retry for critical operations (more attempts, shorter delays)
  static const aggressive = RetryConfig(
    maxAttempts: 10,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 10),
    multiplier: 1.5,
  );

  /// Conservative retry for non-critical operations
  static const conservative = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 60),
    multiplier: 2.0,
  );

  /// Fast retry for quick operations (short delays)
  static const fast = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 5),
    multiplier: 2.0,
  );
}

/// Exception thrown when all retry attempts are exhausted
class RetryExhaustedException implements Exception {
  final String message;
  final Exception lastException;
  final int attempts;

  RetryExhaustedException(this.message, this.lastException, this.attempts);

  @override
  String toString() =>
      'RetryExhaustedException: $message (after $attempts attempts): $lastException';
}

/// Execute an operation with exponential backoff retry
///
/// [operation] is the async function to execute and retry on failure
/// [config] defines the retry behavior (attempts, delays, backoff)
/// [shouldRetry] is an optional predicate to determine if a specific exception
///   should trigger a retry. If null, all exceptions trigger retry.
/// [onRetry] is an optional callback invoked before each retry attempt
///
/// Returns the result of the operation if it eventually succeeds.
/// Throws [RetryExhaustedException] if all attempts fail.
/// Throws the original exception immediately if [shouldRetry] returns false.
Future<T> withRetry<T>(
  Future<T> Function() operation,
  RetryConfig config, {
  bool Function(Exception)? shouldRetry,
  void Function(int attempt, Exception error, Duration delay)? onRetry,
}) async {
  int attempt = 0;
  Duration delay = config.initialDelay;
  Exception? lastException;

  while (attempt < config.maxAttempts) {
    try {
      return await operation();
    } on Exception catch (e) {
      lastException = e;
      attempt++;

      // Check if we should retry this exception
      if (shouldRetry != null && !shouldRetry(e)) {
        rethrow;
      }

      // If we've exhausted all attempts, throw
      if (attempt >= config.maxAttempts) {
        throw RetryExhaustedException(
          'Operation failed after $attempt attempts',
          e,
          attempt,
        );
      }

      // Calculate next delay with exponential backoff
      var nextDelay = Duration(
        milliseconds: math.min(
          (delay.inMilliseconds * config.multiplier).toInt(),
          config.maxDelay.inMilliseconds,
        ),
      );

      // Add jitter to prevent thundering herd (±25% random variation)
      if (config.jitter) {
        final jitterAmount = (nextDelay.inMilliseconds * 0.25).toInt();
        final randomJitter =
            math.Random().nextInt(jitterAmount * 2) - jitterAmount;
        nextDelay = Duration(
          milliseconds: math.max(
            0,
            nextDelay.inMilliseconds + randomJitter,
          ),
        );
      }

      // Notify caller about retry
      onRetry?.call(attempt, e, nextDelay);

      // Wait before retrying
      await Future<void>.delayed(nextDelay);
      delay = nextDelay;
    }
  }

  // This should never be reached, but satisfies the analyzer
  throw RetryExhaustedException(
    'Operation failed',
    lastException ?? Exception('Unknown error'),
    attempt,
  );
}

/// Predicate to retry only on network-related exceptions
bool isNetworkException(Exception e) {
  return e is SocketException ||
      e is TimeoutException ||
      e is IOException ||
      (e is OSError);
}

/// Predicate to retry on connection refused errors
bool isConnectionRefused(Exception e) {
  if (e is SocketException) {
    return e.osError?.errorCode == 10061 || // Windows WSAECONNREFUSED
        e.osError?.errorCode == 111; // Linux ECONNREFUSED
  }
  return false;
}

/// Convenience function: retry network operations with sensible defaults
Future<T> withNetworkRetry<T>(
  Future<T> Function() operation, {
  RetryConfig config = RetryConfig.fast,
  void Function(int attempt, Exception error, Duration delay)? onRetry,
}) {
  return withRetry<T>(
    operation,
    config,
    shouldRetry: isNetworkException,
    onRetry: onRetry,
  );
}

/// Convenience function: retry connection operations with aggressive config
Future<T> withConnectionRetry<T>(
  Future<T> Function() operation, {
  void Function(int attempt, Exception error, Duration delay)? onRetry,
}) {
  return withRetry<T>(
    operation,
    RetryConfig.aggressive,
    shouldRetry: isNetworkException,
    onRetry: onRetry,
  );
}
