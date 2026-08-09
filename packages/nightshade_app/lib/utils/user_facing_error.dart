import 'dart:async';

import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

/// Renders a caught error as copy a person can read.
///
/// Dart's built-in `Error`/`Exception` types stamp their class name onto
/// `toString()` — `StateError` becomes `"Bad state: <message>"`,
/// `UnsupportedError` becomes `"Unsupported operation: <message>"`,
/// `Exception('x')` becomes `"Exception: x"`. Those prefixes are diagnostics
/// for someone reading a stack trace. Interpolating the error object straight
/// into a snackbar (`'Failed to send: $e'`) ships them as product copy, so the
/// operator reads "Failed to send test notification: Bad state: No push
/// transport is listening."
///
/// Each of those types carries the authored message in a separate field, so
/// this reads the message rather than string-stripping the rendered form —
/// prefix-stripping would also eat a message that legitimately begins with the
/// same words.
///
/// Anything whose authored message is not reachable falls through to
/// `toString()` untouched: dropping detail from an unrecognised error type
/// would be a worse failure than an awkward prefix.
String userFacingError(Object? error) {
  if (error == null) return 'Unknown error';
  final message = _authoredMessage(error)?.trim();
  if (message != null && message.isNotEmpty) return message;
  final rendered = error.toString().trim();
  return rendered.isEmpty ? error.runtimeType.toString() : rendered;
}

String? _authoredMessage(Object error) {
  final bridgeMessage = _bridgeAuthoredMessage(error);
  if (bridgeMessage != null) return bridgeMessage;
  if (error is StateError) return error.message;
  // The unsupported-operation family shares this authored-message field.
  if (error is UnsupportedError) return error.message;
  if (error is FormatException) return error.message;
  if (error is TimeoutException) return error.message;
  if (error is ArgumentError) {
    // `ArgumentError.value` / `.notNull` put the offending name and value in
    // `toString()` only. Keep those verbatim; collapse just the plain form.
    if (error.name != null || error.invalidValue != null) return null;
    final message = error.message;
    return message is String ? message : null;
  }
  // `Exception('...')` is a private class with no message accessor, and its
  // `toString()` is exactly 'Exception: <message>'.
  const exceptionPrefix = 'Exception: ';
  final rendered = error.toString();
  if (error is Exception && rendered.startsWith(exceptionPrefix)) {
    return rendered.substring(exceptionPrefix.length);
  }
  return null;
}

/// The authored text inside a `flutter_rust_bridge` [bridge.NightshadeError].
///
/// The bridge type is a freezed union, so its `toString()` is the *debug*
/// rendering — `NightshadeError.connectionFailed(deviceId: localhost:11111,
/// reason: …)`. Interpolating it into a status line ships the Dart class name,
/// the variant name and the field names as product copy; that is exactly what
/// Settings → Connection → Alpaca/INDI "Test Connection" was doing when a
/// server did not answer. Every variant already carries the sentence the
/// operator needs in one of its fields, so pull that out instead.
///
/// Variants whose payload is only an identifier or a number (`cancelled`,
/// `parameterOutOfRange`, the timeout family, …) fall through to `orElse` and
/// keep the previous behaviour — losing their numbers would be worse than an
/// awkward rendering.
String? _bridgeAuthoredMessage(Object error) {
  if (error is! bridge.NightshadeError) return null;
  return error.maybeWhen(
    deviceNotFound: (deviceId) => "Device '$deviceId' was not found",
    connectionFailed: (_, reason) => reason,
    alreadyConnected: (deviceId) => "'$deviceId' is already connected",
    notConnected: (deviceId) => "'$deviceId' is not connected",
    deviceDisconnected: (_, reason) => reason,
    hardwareError: (_, message, __) => message,
    communicationError: (_, message) => message,
    timeout: (message) => message,
    invalidParameter: (message) => message,
    invalidInput: (message) => message,
    invalidDeviceId: (_, reason) => reason,
    operationFailed: (message) => message,
    notSupported: (deviceId, operation) =>
        "'$deviceId' does not support $operation",
    deviceBusy: (deviceId, currentOperation) =>
        "'$deviceId' is busy with $currentOperation",
    imageError: (message) => message,
    cameraError: (message) => message,
    exposureFailed: (_, reason) => reason,
    downloadFailed: (_, reason) => reason,
    ioError: (message) => message,
    serializationError: (message) => message,
    plateSolveError: (message) => message,
    sequenceError: (message) => message,
    ascomError: (_, message, __) => message,
    alpacaError: (_, __, message, ___) => message,
    indiError: (_, __, ___, message) => message,
    nativeError: (_, message, __) => message,
    comError: (message, _) => message,
    internal: (message) => message,
    runtimeInitFailed: (message) => message,
    resourceExhausted: (_, message) => message,
    orElse: () => null,
  );
}
