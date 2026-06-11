/// Device-ID format validation.
///
/// The real implementation now lives in `device_id.dart`, which owns the
/// single canonical [DeviceId] abstraction (parsing, canonicalization,
/// matching, friendly-name resolution). This file is retained only as a thin
/// re-export so existing imports of `isValidDeviceIdFormat` (and the
/// `kKnownDeviceId*` constants) keep working.
///
/// Connect methods on `DeviceService` use [isValidDeviceIdFormat]
/// as a cheap structural pre-check before delegating to the backend — they do
/// NOT confirm the device exists or is reachable. See `device_id.dart` for the
/// full rationale.
library;

export 'device_id.dart'
    show
        isValidDeviceIdFormat,
        kKnownDeviceIdPrefixes,
        kKnownDeviceIdSingletons;
