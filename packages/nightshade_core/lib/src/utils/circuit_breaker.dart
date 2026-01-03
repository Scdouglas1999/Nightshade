/// Circuit breaker pattern for preventing cascade failures
///
/// When a service fails repeatedly, the circuit breaker "opens" and prevents
/// further requests for a timeout period. This protects both the caller and
/// the failing service from being overwhelmed with requests.
///
/// States:
/// - Closed: Normal operation, requests pass through
/// - Open: Service is failing, requests are rejected immediately
/// - Half-Open: Testing if service has recovered, limited requests allowed

import 'dart:async';

/// Circuit breaker state
enum CircuitState {
  /// Normal operation - requests pass through
  closed,

  /// Service is failing - requests are rejected
  open,

  /// Testing recovery - limited requests allowed
  halfOpen,
}

/// Exception thrown when circuit breaker is open
class CircuitOpenException implements Exception {
  final String message;
  final DateTime openedAt;
  final Duration retryAfter;

  CircuitOpenException(this.message, this.openedAt, this.retryAfter);

  @override
  String toString() =>
      'CircuitOpenException: $message (retry after ${retryAfter.inSeconds}s)';
}

/// Configuration for circuit breaker behavior
class CircuitBreakerConfig {
  /// Number of consecutive failures before opening the circuit
  final int failureThreshold;

  /// Number of consecutive successes in half-open state to close circuit
  final int successThreshold;

  /// How long to wait before transitioning from open to half-open
  final Duration resetTimeout;

  /// Timeout for individual operations (optional)
  final Duration? operationTimeout;

  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.successThreshold = 2,
    this.resetTimeout = const Duration(seconds: 30),
    this.operationTimeout,
  });

  /// Aggressive circuit breaker (fails fast, recovers quickly)
  static const aggressive = CircuitBreakerConfig(
    failureThreshold: 3,
    successThreshold: 1,
    resetTimeout: Duration(seconds: 10),
  );

  /// Conservative circuit breaker (tolerates more failures)
  static const conservative = CircuitBreakerConfig(
    failureThreshold: 10,
    successThreshold: 3,
    resetTimeout: Duration(minutes: 1),
  );
}

/// Circuit breaker for protecting against cascading failures
class CircuitBreaker {
  final String name;
  final CircuitBreakerConfig config;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _openedAt;

  /// Optional callback when circuit state changes
  void Function(CircuitState oldState, CircuitState newState)? onStateChange;

  /// Optional callback for operation failures
  void Function(Exception error)? onFailure;

  /// Optional callback for operation successes
  void Function()? onSuccess;

  CircuitBreaker({
    required this.name,
    this.config = const CircuitBreakerConfig(),
    this.onStateChange,
    this.onFailure,
    this.onSuccess,
  });

  /// Get current circuit state
  CircuitState get state => _state;

  /// Get number of consecutive failures
  int get failureCount => _failureCount;

  /// Get number of consecutive successes (in half-open state)
  int get successCount => _successCount;

  /// Check if circuit is open
  bool get isOpen => _state == CircuitState.open;

  /// Check if circuit is closed
  bool get isClosed => _state == CircuitState.closed;

  /// Check if circuit is half-open
  bool get isHalfOpen => _state == CircuitState.halfOpen;

  /// Get time when circuit was opened (null if not open)
  DateTime? get openedAt => _openedAt;

  /// Execute an operation through the circuit breaker
  ///
  /// If the circuit is open, throws [CircuitOpenException] immediately.
  /// If the circuit is half-open, allows limited requests to test recovery.
  /// If the circuit is closed, executes normally and tracks success/failure.
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check if we should transition from open to half-open
    if (_state == CircuitState.open) {
      final timeSinceOpen = DateTime.now().difference(_openedAt!);
      if (timeSinceOpen >= config.resetTimeout) {
        _transitionTo(CircuitState.halfOpen);
      } else {
        throw CircuitOpenException(
          'Circuit breaker for $name is open',
          _openedAt!,
          config.resetTimeout - timeSinceOpen,
        );
      }
    }

    try {
      // Execute operation with optional timeout
      final T result;
      if (config.operationTimeout != null) {
        result = await operation().timeout(config.operationTimeout!);
      } else {
        result = await operation();
      }

      // Record success
      _onSuccess();
      return result;
    } on Exception catch (e) {
      // Record failure
      _onFailure(e);
      rethrow;
    }
  }

  /// Record a successful operation
  void _onSuccess() {
    onSuccess?.call();

    if (_state == CircuitState.halfOpen) {
      _successCount++;
      if (_successCount >= config.successThreshold) {
        // Recovered! Close the circuit
        _transitionTo(CircuitState.closed);
        _failureCount = 0;
        _successCount = 0;
      }
    } else if (_state == CircuitState.closed) {
      // Reset failure count on success
      _failureCount = 0;
    }
  }

  /// Record a failed operation
  void _onFailure(Exception error) {
    _lastFailureTime = DateTime.now();
    onFailure?.call(error);

    if (_state == CircuitState.halfOpen) {
      // Failed recovery attempt - back to open
      _transitionTo(CircuitState.open);
      _openedAt = DateTime.now();
      _successCount = 0;
    } else if (_state == CircuitState.closed) {
      _failureCount++;
      if (_failureCount >= config.failureThreshold) {
        // Too many failures - open the circuit
        _transitionTo(CircuitState.open);
        _openedAt = DateTime.now();
      }
    }
  }

  /// Transition to a new state
  void _transitionTo(CircuitState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;
    onStateChange?.call(oldState, newState);
  }

  /// Manually reset the circuit breaker to closed state
  void reset() {
    _transitionTo(CircuitState.closed);
    _failureCount = 0;
    _successCount = 0;
    _lastFailureTime = null;
    _openedAt = null;
  }

  /// Manually open the circuit breaker
  void open() {
    _transitionTo(CircuitState.open);
    _openedAt = DateTime.now();
  }

  /// Get current health metrics
  Map<String, dynamic> getMetrics() {
    return {
      'name': name,
      'state': _state.name,
      'failureCount': _failureCount,
      'successCount': _successCount,
      'lastFailureTime': _lastFailureTime?.toIso8601String(),
      'openedAt': _openedAt?.toIso8601String(),
      'failureThreshold': config.failureThreshold,
      'successThreshold': config.successThreshold,
    };
  }

  @override
  String toString() {
    return 'CircuitBreaker($name: ${_state.name}, '
        'failures=$_failureCount/${config.failureThreshold}, '
        'successes=$_successCount/${config.successThreshold})';
  }
}

/// Manager for multiple circuit breakers
class CircuitBreakerRegistry {
  final Map<String, CircuitBreaker> _breakers = {};

  /// Get or create a circuit breaker for a given name
  CircuitBreaker getOrCreate(
    String name, {
    CircuitBreakerConfig? config,
    void Function(CircuitState oldState, CircuitState newState)? onStateChange,
    void Function(Exception error)? onFailure,
    void Function()? onSuccess,
  }) {
    return _breakers.putIfAbsent(
      name,
      () => CircuitBreaker(
        name: name,
        config: config ?? const CircuitBreakerConfig(),
        onStateChange: onStateChange,
        onFailure: onFailure,
        onSuccess: onSuccess,
      ),
    );
  }

  /// Get an existing circuit breaker
  CircuitBreaker? get(String name) => _breakers[name];

  /// Remove a circuit breaker
  void remove(String name) => _breakers.remove(name);

  /// Reset all circuit breakers
  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }

  /// Get metrics for all circuit breakers
  List<Map<String, dynamic>> getAllMetrics() {
    return _breakers.values.map((b) => b.getMetrics()).toList();
  }

  /// Get all open circuit breakers
  List<CircuitBreaker> getOpenBreakers() {
    return _breakers.values.where((b) => b.isOpen).toList();
  }
}
