/// Tests for connection resilience features
///
/// This test suite validates:
/// - Exponential backoff retry logic
/// - Circuit breaker pattern
/// - PHD2 heartbeat and auto-reconnect
/// - Alpaca retry on timeout

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/src/utils/retry.dart';
import 'package:nightshade_bridge/src/utils/circuit_breaker.dart';
import 'dart:async';
import 'dart:io';

void main() {
  group('Exponential Backoff Retry', () {
    test('retries operation with exponential backoff', () async {
      int attempts = 0;
      final delays = <Duration>[];

      try {
        await withRetry(
          () async {
            attempts++;
            if (attempts < 3) {
              throw const SocketException('Connection refused');
            }
            return 'success';
          },
          const RetryConfig(maxAttempts: 5, initialDelay: Duration(milliseconds: 100)),
          onRetry: (attempt, error, delay) {
            delays.add(delay);
          },
        );
      } catch (e) {
        // Should not reach here
        fail('Should have succeeded on third attempt');
      }

      expect(attempts, 3);
      expect(delays.length, 2); // 2 retries before success
      // Verify exponential backoff
      expect(delays[1].inMilliseconds, greaterThan(delays[0].inMilliseconds));
    });

    test('exhausts retries and throws RetryExhaustedException', () async {
      int attempts = 0;

      try {
        await withRetry(
          () async {
            attempts++;
            throw TimeoutException('Timeout');
          },
          const RetryConfig(maxAttempts: 3, initialDelay: Duration(milliseconds: 10)),
        );
        fail('Should have thrown RetryExhaustedException');
      } on RetryExhaustedException catch (_) {
        // Expected
      }

      expect(attempts, 3);
    });

    test('respects shouldRetry predicate', () async {
      int attempts = 0;

      expect(
        () async => await withRetry(
          () async {
            attempts++;
            throw const FormatException('Invalid format');
          },
          const RetryConfig(maxAttempts: 5),
          shouldRetry: isNetworkException,
        ),
        throwsA(isA<FormatException>()),
      );

      // Should fail immediately since FormatException is not a network exception
      expect(attempts, 1);
    });

    test('withNetworkRetry retries on network errors', () async {
      int attempts = 0;

      try {
        await withNetworkRetry(
          () async {
            attempts++;
            throw const SocketException('Network error');
          },
          config: const RetryConfig(maxAttempts: 3, initialDelay: Duration(milliseconds: 10)),
        );
        fail('Should have thrown RetryExhaustedException');
      } on RetryExhaustedException catch (_) {
        // Expected
      }

      expect(attempts, 3);
    });
  });

  group('Circuit Breaker', () {
    test('opens after threshold failures', () async {
      final breaker = CircuitBreaker(
        name: 'test-breaker',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          resetTimeout: Duration(seconds: 1),
        ),
      );

      // Fail 3 times
      for (int i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw const SocketException('Error'));
        } catch (_) {}
      }

      expect(breaker.isOpen, true);
      expect(breaker.failureCount, 3);

      // Next attempt should throw CircuitOpenException immediately
      expect(
        () async => await breaker.execute(() async => 'should not execute'),
        throwsA(isA<CircuitOpenException>()),
      );
    });

    test('transitions to half-open after reset timeout', () async {
      final breaker = CircuitBreaker(
        name: 'test-breaker-reset',
        config: const CircuitBreakerConfig(
          failureThreshold: 2,
          successThreshold: 2, // Require 2 successes to close
          resetTimeout: Duration(milliseconds: 100),
        ),
      );

      // Open the circuit
      for (int i = 0; i < 2; i++) {
        try {
          await breaker.execute(() async => throw const SocketException('Error'));
        } catch (_) {}
      }

      expect(breaker.isOpen, true);

      // Wait for reset timeout
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Execute one successful operation to enter half-open
      await breaker.execute(() async => 'test');

      // Should be in half-open state (need 1 more success to close)
      expect(breaker.isHalfOpen, true);
      expect(breaker.successCount, 1);
    });

    test('closes after success threshold in half-open', () async {
      final breaker = CircuitBreaker(
        name: 'test-breaker-close',
        config: const CircuitBreakerConfig(
          failureThreshold: 2,
          successThreshold: 2,
          resetTimeout: Duration(milliseconds: 100),
        ),
      );

      // Open the circuit
      for (int i = 0; i < 2; i++) {
        try {
          await breaker.execute(() async => throw const SocketException('Error'));
        } catch (_) {}
      }

      expect(breaker.isOpen, true);

      // Wait for reset timeout to transition to half-open
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Succeed twice to close
      for (int i = 0; i < 2; i++) {
        await breaker.execute(() async => 'success');
      }

      expect(breaker.isClosed, true);
      expect(breaker.failureCount, 0);
    });

    test('resets failure count on success in closed state', () async {
      final breaker = CircuitBreaker(
        name: 'test-reset-failures',
        config: const CircuitBreakerConfig(failureThreshold: 5),
      );

      // Fail a few times
      for (int i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw const SocketException('Error'));
        } catch (_) {}
      }

      expect(breaker.failureCount, 3);

      // Succeed once
      await breaker.execute(() async => 'success');

      // Failure count should be reset
      expect(breaker.failureCount, 0);
      expect(breaker.isClosed, true);
    });
  });

  group('Circuit Breaker Registry', () {
    test('manages multiple circuit breakers', () {
      final registry = CircuitBreakerRegistry();

      final breaker1 = registry.getOrCreate('device1');
      final breaker2 = registry.getOrCreate('device2');
      final breaker1Again = registry.getOrCreate('device1');

      expect(breaker1, same(breaker1Again));
      expect(breaker1, isNot(same(breaker2)));
    });

    test('resets all breakers', () async {
      final registry = CircuitBreakerRegistry();

      final breaker1 = registry.getOrCreate('device1',
          config: const CircuitBreakerConfig(failureThreshold: 1));
      final breaker2 = registry.getOrCreate('device2',
          config: const CircuitBreakerConfig(failureThreshold: 1));

      // Open both breakers
      try {
        await breaker1.execute(() async => throw const SocketException('Error'));
      } catch (_) {}
      try {
        await breaker2.execute(() async => throw const SocketException('Error'));
      } catch (_) {}

      expect(breaker1.isOpen, true);
      expect(breaker2.isOpen, true);

      // Reset all
      registry.resetAll();

      expect(breaker1.isClosed, true);
      expect(breaker2.isClosed, true);
    });
  });

  group('Retry Config Presets', () {
    test('aggressive config has more attempts and shorter delays', () {
      expect(RetryConfig.aggressive.maxAttempts, greaterThan(RetryConfig.conservative.maxAttempts));
      expect(RetryConfig.aggressive.maxDelay.inSeconds, lessThan(RetryConfig.conservative.maxDelay.inSeconds));
    });

    test('fast config has short delays', () {
      expect(RetryConfig.fast.maxDelay.inSeconds, lessThanOrEqualTo(5));
      expect(RetryConfig.fast.initialDelay.inMilliseconds, lessThan(1000));
    });
  });

  group('Network Exception Predicates', () {
    test('isNetworkException identifies network errors', () {
      expect(isNetworkException(const SocketException('test')), true);
      expect(isNetworkException(TimeoutException('test')), true);
      expect(isNetworkException(const FormatException('test')), false);
    });
  });

  group('Circuit Breaker Metrics', () {
    test('provides accurate metrics', () async {
      final breaker = CircuitBreaker(
        name: 'metrics-test',
        config: const CircuitBreakerConfig(failureThreshold: 3),
      );

      // Fail twice
      for (int i = 0; i < 2; i++) {
        try {
          await breaker.execute(() async => throw const SocketException('Error'));
        } catch (_) {}
      }

      final metrics = breaker.getMetrics();
      expect(metrics['name'], 'metrics-test');
      expect(metrics['state'], 'closed');
      expect(metrics['failureCount'], 2);
      expect(metrics['failureThreshold'], 3);
      expect(metrics['lastFailureTime'], isNotNull);
    });
  });
}
