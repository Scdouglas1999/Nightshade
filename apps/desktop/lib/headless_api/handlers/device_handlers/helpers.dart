part of '../device_handlers.dart';

// ===========================================================================
// Helpers
// ===========================================================================

FrameType _parseFrameType(String type) {
  switch (type.toLowerCase()) {
    case 'light':
      return FrameType.light;
    case 'dark':
      return FrameType.dark;
    case 'flat':
      return FrameType.flat;
    case 'bias':
      return FrameType.bias;
    case 'darkflat':
      return FrameType.darkFlat;
    default:
      return FrameType.light;
  }
}

/// Internal sentinel raised by `_dispatchConnect` when the requested
/// device id does not match anything `DeviceService.discoverDevices`
/// returned. The connect handler translates this into a structured
/// `device_not_found` HTTP 404 with the original service message.
class _DeviceNotFoundFailure implements Exception {
  final String message;
  _DeviceNotFoundFailure(this.message);
  @override
  String toString() => message;
}

/// Sentinel used to flag the cancellation branch of a `Future.any` race
/// against a long-running backend call. We can't pass `null` because the
/// race's result type is non-nullable; a sentinel keeps the type system
/// happy without requiring a wrapper class on every result type.
class _CancelledMarker {
  const _CancelledMarker._();
  static const _CancelledMarker instance = _CancelledMarker._();
}
