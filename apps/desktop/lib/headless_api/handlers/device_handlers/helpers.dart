part of '../device_handlers.dart';

// ===========================================================================
// Helpers
// ===========================================================================

/// Parse the wire `frameType` string into a [FrameType].
///
/// Why this rejects instead of defaulting: the previous `default:` arm
/// silently coerced ANY unrecognised string to [FrameType.light].
/// Observed on the live rig against a real ZWO ASI1600MM-Cool:
///   POST /api/camera/expose {"frameType":"banana"} -> 200 {"status":"exposing"}
/// The frame was captured and recorded as a light. A typo in a calibration
/// script therefore silently mislabels darks/flats as lights, both in the
/// image record and in the FITS `IMAGETYP` keyword, and the operator is
/// never told. An unknown frame type is a bad request, not a light frame.
///
/// [FrameType.snapshot] is a declared enum value and was missing from the
/// switch, so `"snapshot"` also fell through to `light`; it is mapped here
/// so that adding the rejection arm does not start rejecting a valid type.
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
    case 'dark_flat':
      return FrameType.darkFlat;
    case 'snapshot':
      return FrameType.snapshot;
    default:
      throw BadRequestError(
        field: 'frameType',
        expected: 'one of: light, dark, flat, bias, darkFlat, snapshot',
        message:
            'Unknown frame type "$type"; expected one of '
            'light, dark, flat, bias, darkFlat, snapshot',
      );
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
