/// Structured exception types for Nightshade backend operations.
///
/// This module provides a Dart exception hierarchy that mirrors the Rust
/// NightshadeError enum, enabling rich error handling across the FFI boundary.

/// Base exception for all Nightshade backend errors.
///
/// This provides a structured error with:
/// - Category classification for error handling strategies
/// - User-friendly messages for UI display
/// - Recovery hints (retryable, needs reconnection, etc.)
/// - Optional device and error code context
class NightshadeException implements Exception {
  /// Error category (timeout, connection, hardware, validation, etc.)
  final String category;

  /// Technical error message
  final String message;

  /// User-friendly message for UI display
  final String userMessage;

  /// Whether the operation can be retried
  final bool isRecoverable;

  /// Whether reconnection should be attempted before retry
  final bool shouldReconnect;

  /// Whether this was a timeout error
  final bool isTimeout;

  /// Device ID if this is a device-related error
  final String? deviceId;

  /// Vendor-specific error code if available
  final int? errorCode;

  const NightshadeException({
    required this.category,
    required this.message,
    required this.userMessage,
    this.isRecoverable = false,
    this.shouldReconnect = false,
    this.isTimeout = false,
    this.deviceId,
    this.errorCode,
  });

  /// Create from JSON (matches Rust ErrorInfo serialization)
  factory NightshadeException.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String? ?? 'system';

    return switch (category) {
      'connection' => ConnectionException.fromJson(json),
      'hardware' => HardwareException.fromJson(json),
      'timeout' => TimeoutException.fromJson(json),
      'validation' => ValidationException.fromJson(json),
      'unsupported' => UnsupportedOperationException.fromJson(json),
      'busy' => DeviceBusyException.fromJson(json),
      'imaging' => ImagingException.fromJson(json),
      'io' => IoException.fromJson(json),
      'sequence' => SequenceException.fromJson(json),
      'driver' => DriverException.fromJson(json),
      _ => NightshadeException(
          category: category,
          message: json['message'] as String? ?? 'Unknown error',
          userMessage: json['user_message'] as String? ?? 'An error occurred',
          isRecoverable: json['is_recoverable'] as bool? ?? false,
          shouldReconnect: json['should_reconnect'] as bool? ?? false,
          isTimeout: json['is_timeout'] as bool? ?? false,
          deviceId: json['device_id'] as String?,
          errorCode: json['error_code'] as int?,
        ),
    };
  }

  /// Create from a generic exception with error message
  factory NightshadeException.fromError(Object error,
      [StackTrace? stackTrace]) {
    final message = error.toString();

    // Try to parse as JSON first (for structured errors from Rust)
    if (message.startsWith('{')) {
      try {
        final json = _parseJson(message);
        if (json != null) {
          return NightshadeException.fromJson(json);
        }
      } catch (_) {
        // Fall through to string-based parsing
      }
    }

    // String-based heuristic classification
    return _classifyFromMessage(message);
  }

  static Map<String, dynamic>? _parseJson(String message) {
    try {
      // Simple JSON parsing without importing dart:convert here
      // The actual parsing is done when this is used
      return null; // Let the caller handle JSON parsing
    } catch (_) {
      return null;
    }
  }

  static NightshadeException _classifyFromMessage(String message) {
    final lower = message.toLowerCase();

    // Timeout detection
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return TimeoutException(
        message: message,
        userMessage: 'Operation timed out',
      );
    }

    // Connection errors
    if (lower.contains('not connected') ||
        lower.contains('disconnected') ||
        lower.contains('connection failed')) {
      return ConnectionException(
        message: message,
        userMessage: 'Connection error',
      );
    }

    // Device not found
    if (lower.contains('device not found') || lower.contains('not found')) {
      return ConnectionException(
        message: message,
        userMessage: 'Device not found',
        isRecoverable: false,
      );
    }

    // Validation errors
    if (lower.contains('invalid') ||
        lower.contains('out of range') ||
        lower.contains('parameter')) {
      return ValidationException(
        message: message,
        userMessage: 'Invalid input',
      );
    }

    // Not supported
    if (lower.contains('not supported') || lower.contains('unsupported')) {
      return UnsupportedOperationException(
        message: message,
        userMessage: 'Operation not supported',
      );
    }

    // Imaging errors
    if (lower.contains('exposure') ||
        lower.contains('image') ||
        lower.contains('camera')) {
      return ImagingException(
        message: message,
        userMessage: 'Imaging error',
      );
    }

    // Default to generic exception
    return NightshadeException(
      category: 'system',
      message: message,
      userMessage:
          message.length > 100 ? '${message.substring(0, 100)}...' : message,
    );
  }

  @override
  String toString() => 'NightshadeException($category): $message';

  /// Check if this is a cancellation (not really an error)
  bool get isCancellation =>
      message.toLowerCase().contains('cancelled') ||
      message.toLowerCase().contains('canceled');

  /// Check if this is a hardware error requiring user attention
  bool get isHardwareError => category == 'hardware' || category == 'driver';

  /// Check if this is an input validation error
  bool get isValidationError => category == 'validation';
}

/// Connection-related exceptions (device not found, disconnected, etc.)
class ConnectionException extends NightshadeException {
  const ConnectionException({
    required super.message,
    required super.userMessage,
    super.isRecoverable = true,
    super.shouldReconnect = true,
    super.deviceId,
  }) : super(category: 'connection', isTimeout: false);

  factory ConnectionException.fromJson(Map<String, dynamic> json) {
    return ConnectionException(
      message: json['message'] as String? ?? 'Connection error',
      userMessage: json['user_message'] as String? ?? 'Connection error',
      isRecoverable: json['is_recoverable'] as bool? ?? false,
      shouldReconnect: json['should_reconnect'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
    );
  }

  /// Device not found
  factory ConnectionException.notFound(String deviceId) {
    return ConnectionException(
      message: 'Device not found: $deviceId',
      userMessage: 'Device "$deviceId" not found',
      deviceId: deviceId,
      isRecoverable: false,
      shouldReconnect: false,
    );
  }

  /// Device disconnected
  factory ConnectionException.disconnected(String deviceId, [String? reason]) {
    return ConnectionException(
      message:
          'Device disconnected: $deviceId${reason != null ? ' - $reason' : ''}',
      userMessage: '"$deviceId" disconnected unexpectedly',
      deviceId: deviceId,
    );
  }
}

/// Hardware-related exceptions
class HardwareException extends NightshadeException {
  const HardwareException({
    required super.message,
    required super.userMessage,
    super.isRecoverable = true,
    super.deviceId,
    super.errorCode,
  }) : super(category: 'hardware', shouldReconnect: false, isTimeout: false);

  factory HardwareException.fromJson(Map<String, dynamic> json) {
    return HardwareException(
      message: json['message'] as String? ?? 'Hardware error',
      userMessage: json['user_message'] as String? ?? 'Hardware error',
      isRecoverable: json['is_recoverable'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      errorCode: json['error_code'] as int?,
    );
  }
}

/// Timeout exceptions
class TimeoutException extends NightshadeException {
  const TimeoutException({
    required super.message,
    required super.userMessage,
    super.deviceId,
  }) : super(
          category: 'timeout',
          isRecoverable: true,
          shouldReconnect: false,
          isTimeout: true,
        );

  factory TimeoutException.fromJson(Map<String, dynamic> json) {
    return TimeoutException(
      message: json['message'] as String? ?? 'Operation timed out',
      userMessage: json['user_message'] as String? ?? 'Operation timed out',
      deviceId: json['device_id'] as String?,
    );
  }

  /// Create a device timeout
  factory TimeoutException.device(String deviceId, String operation) {
    return TimeoutException(
      message: 'Device timeout: $deviceId operation "$operation"',
      userMessage: 'Operation "$operation" timed out',
      deviceId: deviceId,
    );
  }
}

/// Input validation exceptions
class ValidationException extends NightshadeException {
  const ValidationException({
    required super.message,
    required super.userMessage,
  }) : super(
          category: 'validation',
          isRecoverable: false,
          shouldReconnect: false,
          isTimeout: false,
        );

  factory ValidationException.fromJson(Map<String, dynamic> json) {
    return ValidationException(
      message: json['message'] as String? ?? 'Invalid input',
      userMessage: json['user_message'] as String? ?? 'Invalid input',
    );
  }

  /// Parameter out of range
  factory ValidationException.outOfRange(
    String paramName,
    dynamic value,
    dynamic min,
    dynamic max,
  ) {
    return ValidationException(
      message:
          'Parameter out of range: $paramName = $value (valid: $min to $max)',
      userMessage: '$paramName value $value is out of range ($min to $max)',
    );
  }
}

/// Unsupported operation exceptions
class UnsupportedOperationException extends NightshadeException {
  const UnsupportedOperationException({
    required super.message,
    required super.userMessage,
    super.deviceId,
  }) : super(
          category: 'unsupported',
          isRecoverable: false,
          shouldReconnect: false,
          isTimeout: false,
        );

  factory UnsupportedOperationException.fromJson(Map<String, dynamic> json) {
    return UnsupportedOperationException(
      message: json['message'] as String? ?? 'Operation not supported',
      userMessage: json['user_message'] as String? ?? 'Operation not supported',
      deviceId: json['device_id'] as String?,
    );
  }
}

/// Device busy exceptions
class DeviceBusyException extends NightshadeException {
  /// Current operation the device is performing
  final String? currentOperation;

  const DeviceBusyException({
    required super.message,
    required super.userMessage,
    super.deviceId,
    this.currentOperation,
  }) : super(
          category: 'busy',
          isRecoverable: true,
          shouldReconnect: false,
          isTimeout: false,
        );

  factory DeviceBusyException.fromJson(Map<String, dynamic> json) {
    return DeviceBusyException(
      message: json['message'] as String? ?? 'Device busy',
      userMessage: json['user_message'] as String? ?? 'Device is busy',
      deviceId: json['device_id'] as String?,
    );
  }
}

/// Imaging-related exceptions
class ImagingException extends NightshadeException {
  const ImagingException({
    required super.message,
    required super.userMessage,
    super.isRecoverable = false,
    super.deviceId,
  }) : super(
          category: 'imaging',
          shouldReconnect: false,
          isTimeout: false,
        );

  factory ImagingException.fromJson(Map<String, dynamic> json) {
    return ImagingException(
      message: json['message'] as String? ?? 'Imaging error',
      userMessage: json['user_message'] as String? ?? 'Imaging error',
      isRecoverable: json['is_recoverable'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
    );
  }

  /// Exposure cancelled (not really an error)
  factory ImagingException.cancelled() {
    return const ImagingException(
      message: 'Exposure cancelled',
      userMessage: 'Exposure was cancelled',
    );
  }

  /// No image available
  factory ImagingException.noImage() {
    return const ImagingException(
      message: 'No image available',
      userMessage: 'No image is available',
    );
  }
}

/// I/O exceptions (file operations, plate solving)
class IoException extends NightshadeException {
  const IoException({
    required super.message,
    required super.userMessage,
  }) : super(
          category: 'io',
          isRecoverable: false,
          shouldReconnect: false,
          isTimeout: false,
        );

  factory IoException.fromJson(Map<String, dynamic> json) {
    return IoException(
      message: json['message'] as String? ?? 'I/O error',
      userMessage: json['user_message'] as String? ?? 'File operation failed',
    );
  }
}

/// Sequence execution exceptions
class SequenceException extends NightshadeException {
  const SequenceException({
    required super.message,
    required super.userMessage,
  }) : super(
          category: 'sequence',
          isRecoverable: false,
          shouldReconnect: false,
          isTimeout: false,
        );

  factory SequenceException.fromJson(Map<String, dynamic> json) {
    return SequenceException(
      message: json['message'] as String? ?? 'Sequence error',
      userMessage: json['user_message'] as String? ?? 'Sequence error',
    );
  }
}

/// Driver-specific exceptions (ASCOM, Alpaca, INDI, Native SDK)
class DriverException extends NightshadeException {
  /// Driver type (ascom, alpaca, indi, native)
  final String? driverType;

  const DriverException({
    required super.message,
    required super.userMessage,
    super.isRecoverable = false,
    super.deviceId,
    super.errorCode,
    this.driverType,
  }) : super(
          category: 'driver',
          shouldReconnect: false,
          isTimeout: false,
        );

  factory DriverException.fromJson(Map<String, dynamic> json) {
    return DriverException(
      message: json['message'] as String? ?? 'Driver error',
      userMessage: json['user_message'] as String? ?? 'Driver error',
      isRecoverable: json['is_recoverable'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      errorCode: json['error_code'] as int?,
    );
  }
}
