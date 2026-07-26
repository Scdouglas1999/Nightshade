/// Single source of truth for device-identity logic in Nightshade.
///
/// Historically, device-id parsing, equality/matching, canonicalization, and
/// friendly-name resolution were re-implemented in many places with subtly
/// different logic — which caused repeated bugs (the PHD2 guider was
/// mis-handled in three separate spots; native ZWO names showed raw ids).
///
/// This file consolidates all of that into one [DeviceId] value type plus a
/// small set of free functions. Every call-site that needs to parse a device
/// id, compare two ids for "is the connected device the one the profile
/// assigned", canonicalize PHD2 variants, or derive a fallback display name
/// MUST route through here rather than re-deriving the logic.
///
/// Format conventions (mirrors `native/nightshade_native/bridge/src/device_id.rs`,
/// the canonical Rust parser — see the canonical device-ID rules):
///   - `ascom:<prog_id>`                       (Windows ASCOM COM driver)
///   - `alpaca:<proto>://<host>:<port>:<type>:<num>` (cross-platform ASCOM HTTP)
///   - `indi:<host>:<port>:<device_name>`      (Linux/macOS INDI server)
///   - `native:<vendor>:<id>[:...]`            (native vendor SDKs; some 4-part,
///                                              e.g. `native:touptek:<brand>:<idx>`,
///                                              `native:zwo:eaf:0`, `native:zwo_eaf:0`)
///   - `simulator:<type>[:<instance>]`         (in-process simulators)
///   - PHD2 socket guider, which may be recorded several ways:
///     `phd2`, `phd2_guider`, `phd2:<host>:<port>`, `phd2://<host>:<port>` —
///     all collapse to the single canonical id `phd2_guider`.
///   - `builtin_guider`                         (legacy alias before the full
///                                               `native:builtin_guider:...` id
///                                               became canonical)
///
/// Rationale (preserved from the old `device_id_utils.dart`): the
/// connect methods on `DeviceService` only do a cheap *structural* format
/// check via [isValidDeviceIdFormat] before delegating to the backend. They
/// do NOT validate that the device exists or is reachable — that is the
/// backend's job, and its failures must still surface from `connectDevice`.
/// The format check exists purely so a malformed id fails before bothering
/// the backend, instead of being rejected by a stale discovery snapshot.
library;

/// The driver layer a device id belongs to.
enum DeviceDriverKind {
  ascom,
  alpaca,
  indi,
  native,
  simulator,

  /// PHD2 socket guider (any of its representations).
  phd2,

  /// Legacy single-token built-in guider alias (`builtin_guider`).
  builtinGuider,

  /// A structurally-valid-looking id we could not classify, or a malformed
  /// id. Callers that need a hard failure should use [DeviceId.parseStrict].
  unknown,
}

/// Known device-id prefixes used by every Nightshade driver layer.
const List<String> kKnownDeviceIdPrefixes = <String>[
  'ascom:',
  'alpaca:',
  'indi:',
  'native:',
  'simulator:',
  'phd2:',
  'phd2://',
];

/// Single-token device ids that are accepted without a colon prefix.
const List<String> kKnownDeviceIdSingletons = <String>[
  'phd2',
  'phd2_guider',
  'builtin_guider',
];

/// The single canonical id PHD2 always connects under, regardless of how a
/// profile recorded it. See `DeviceService.connectGuider`.
const String kPhd2CanonicalId = 'phd2_guider';

/// A parsed, canonicalizable device identity.
///
/// Construct via [DeviceId.parse] (tolerant — never throws) or
/// [DeviceId.parseStrict] (throws [FormatException] on a malformed id, in
/// keeping with "errors are a feature").
class DeviceId {
  /// The exact raw id as supplied (untrimmed, original case preserved).
  final String raw;

  /// The driver layer this id belongs to.
  final DeviceDriverKind kind;

  /// Lower-cased, trimmed segments after the driver prefix is stripped.
  ///
  /// For `native:touptek:ogma:0` this is `['touptek', 'ogma', '0']`; for
  /// `ascom:ASCOM.Camera.Simulator` it is `['ascom.camera.simulator']`
  /// (ASCOM ProgIDs are not colon-delimited). For PHD2 / builtin singletons
  /// it is empty.
  final List<String> segments;

  const DeviceId._(this.raw, this.kind, this.segments);

  /// Parse [raw] tolerantly. Never throws: an empty or unclassifiable id
  /// yields a [DeviceId] with [kind] == [DeviceDriverKind.unknown].
  ///
  /// Use this for matching / display where a best-effort result is wanted.
  /// Use [parseStrict] where a malformed id must fail loudly.
  factory DeviceId.parse(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();

    if (trimmed.isEmpty) {
      return DeviceId._(raw, DeviceDriverKind.unknown, const <String>[]);
    }

    // PHD2 in any of its representations.
    if (_isPhd2Token(lower)) {
      return DeviceId._(raw, DeviceDriverKind.phd2, const <String>[]);
    }

    if (lower == 'builtin_guider') {
      return DeviceId._(raw, DeviceDriverKind.builtinGuider, const <String>[]);
    }

    if (lower.startsWith('native:')) {
      final segs = trimmed.substring('native:'.length).split(':');
      return DeviceId._(
        raw,
        DeviceDriverKind.native,
        segs.map((s) => s.trim().toLowerCase()).toList(growable: false),
      );
    }
    if (lower.startsWith('ascom:')) {
      // ASCOM ProgIDs are dot-delimited, not colon-delimited.
      final progId = trimmed.substring('ascom:'.length).trim().toLowerCase();
      return DeviceId._(raw, DeviceDriverKind.ascom, <String>[progId]);
    }
    if (lower.startsWith('alpaca:')) {
      final segs = trimmed.substring('alpaca:'.length).split(':');
      return DeviceId._(
        raw,
        DeviceDriverKind.alpaca,
        segs.map((s) => s.trim().toLowerCase()).toList(growable: false),
      );
    }
    if (lower.startsWith('indi:')) {
      final segs = trimmed.substring('indi:'.length).split(':');
      return DeviceId._(
        raw,
        DeviceDriverKind.indi,
        segs.map((s) => s.trim().toLowerCase()).toList(growable: false),
      );
    }
    if (lower.startsWith('simulator:') || lower.startsWith('sim:')) {
      final prefix = lower.startsWith('simulator:') ? 'simulator:' : 'sim:';
      final segs = trimmed.substring(prefix.length).split(':');
      return DeviceId._(
        raw,
        DeviceDriverKind.simulator,
        segs.map((s) => s.trim().toLowerCase()).toList(growable: false),
      );
    }
    // Legacy bare simulator ids (`sim_camera_1`, `sim_mount_1`, ...). The
    // native device layer identifies its in-process simulators by this
    // underscore form — 40+ `id.starts_with("sim_")` branches across the Rust
    // bridge (simulation.rs, camera.rs, imaging.rs, heartbeat.rs) route to it —
    // and discovery emits exactly these ids. Classify them as simulator rather
    // than `unknown` so the connect guard and any kind-based routing agree.
    // Segments split on `_`: `sim_camera_1` -> ['camera', '1'].
    if (lower.startsWith('sim_')) {
      final segs = trimmed.substring('sim_'.length).split('_');
      return DeviceId._(
        raw,
        DeviceDriverKind.simulator,
        segs.map((s) => s.trim().toLowerCase()).toList(growable: false),
      );
    }

    return DeviceId._(raw, DeviceDriverKind.unknown, const <String>[]);
  }

  /// Parse [raw], throwing [FormatException] when the id does not match any
  /// known Nightshade driver-prefix convention. "Errors are a feature": a
  /// malformed id must never be silently accepted into hardware dispatch.
  factory DeviceId.parseStrict(String raw) {
    final id = DeviceId.parse(raw);
    if (!isValidDeviceIdFormat(raw)) {
      throw FormatException('Unrecognized device id format', raw);
    }
    return id;
  }

  /// The canonical form of this id, used as the primary equality key.
  ///
  /// PHD2 in any representation collapses to [kPhd2CanonicalId]. Every other
  /// id canonicalizes to its trimmed, lower-cased raw form so that case- and
  /// whitespace-only differences compare equal.
  String get canonical {
    if (kind == DeviceDriverKind.phd2) return kPhd2CanonicalId;
    return raw.trim().toLowerCase();
  }

  /// Whether this id matches [other] as "the same assigned device".
  ///
  /// Equality is decided in two stages, preserving the historical behavior of
  /// `profile_sidebar.dart`'s `_deviceIdsMatch`:
  ///   1. Canonical equality (collapses PHD2 variants, ignores case/space).
  ///   2. The legacy FUZZY token/normalize matcher, so a profile id that
  ///      drifted from the connected id by index/format still matches (e.g.
  ///      "ZWO EAF" vs "native:zwo_eaf:0", model-number drift).
  bool matches(DeviceId other) {
    if (canonical == other.canonical) return true;
    return _fuzzyDeviceIdsMatch(raw, other.raw);
  }

  /// Convenience: parse [otherRaw] and compare. See [matches].
  bool matchesRaw(String otherRaw) => matches(DeviceId.parse(otherRaw));

  @override
  String toString() => 'DeviceId(${kind.name}, $canonical)';
}

bool _isPhd2Token(String lower) =>
    lower == 'phd2_guider' ||
    lower == 'phd2' ||
    lower.startsWith('phd2:') ||
    lower.startsWith('phd2://');

/// Returns `true` if [deviceId] looks like a Nightshade-formatted device id.
///
/// The check is purely structural — it does NOT confirm the device exists.
/// (Preserved from the old `device_id_utils.dart`;.)
bool isValidDeviceIdFormat(String deviceId) {
  if (deviceId.isEmpty) return false;
  if (kKnownDeviceIdSingletons.contains(deviceId)) return true;
  // Legacy bare simulator ids (`sim_camera_1`, ...). The native device layer
  // keys its in-process simulators off the `sim_` prefix, and discovery emits
  // these, so accept the form here — otherwise the simulator camera/mount/etc.
  // is discoverable but never connectable over the API. The canonical
  // `simulator:<type>` form is accepted via the prefix loop below.
  if (deviceId.startsWith('sim_') && deviceId.length > 'sim_'.length) {
    return true;
  }
  for (final prefix in kKnownDeviceIdPrefixes) {
    if (deviceId.startsWith(prefix) && deviceId.length > prefix.length) {
      return true;
    }
  }
  return false;
}

/// Collapse the several PHD2 representations a profile may have stored to the
/// single canonical id [kPhd2CanonicalId]; every other id is returned
/// unchanged.
///
/// Equivalent to `DeviceId.parse(id).canonical` for PHD2 ids, but preserves
/// the original (untrimmed, original-case) string for non-PHD2 ids — which is
/// exactly what the old `equipment_screen._canonicalGuiderId` did.
String canonicalGuiderId(String id) {
  if (_isPhd2Token(id.toLowerCase())) return kPhd2CanonicalId;
  return id;
}

/// Whether [id] is any PHD2 representation (`phd2`, `phd2_guider`,
/// `phd2:host:port`, `phd2://…`). Single source of truth for the PHD2
/// short-circuit that previously lived inline in `DeviceService`,
/// `profile_sidebar`, and `equipment_screen`.
bool isPhd2DeviceId(String id) => _isPhd2Token(id.trim().toLowerCase());

/// Derive a human-readable name from a device id WITHOUT running discovery.
///
/// e.g. `native:zwo_efw:0` → `ZWO EFW 0`,
///      `ascom:ASCOM.EFWmini.FilterWheel` → `EFWmini FilterWheel`.
///
/// This is the id-pattern fallback used by `DeviceService` when neither the
/// backend's connected list nor the discovery cache knows the device's model
/// name. Ported verbatim from the old `DeviceService._friendlyNameFromId`.
String friendlyNameFromDeviceId(String deviceId) {
  if (deviceId.startsWith('native:zwo_efw:')) {
    final hwId = deviceId.split(':').last;
    return 'ZWO EFW $hwId';
  }
  if (deviceId.startsWith('native:qhy_cfw:')) {
    final camId = deviceId.split(':').last;
    return 'QHY CFW ($camId)';
  }
  if (deviceId.startsWith('native:fli_fw:')) {
    return 'FLI Filter Wheel';
  }
  if (deviceId.startsWith('ascom:')) {
    // "ascom:ASCOM.Vendor.FilterWheel" → keep last two segments
    final progId = deviceId.substring(6); // strip "ascom:"
    final parts = progId.split('.');
    if (parts.length >= 2) {
      return parts.sublist(1).join(' ');
    }
    return progId;
  }
  if (deviceId.startsWith('alpaca:')) {
    final parts = deviceId.split(':');
    final type = parts.length >= 2 ? parts[parts.length - 2].toLowerCase() : '';
    final label = switch (type) {
      'camera' => 'Camera',
      'telescope' || 'mount' => 'Mount',
      'focuser' => 'Focuser',
      'filterwheel' => 'Filter Wheel',
      'rotator' => 'Rotator',
      'dome' => 'Dome',
      'observingconditions' => 'Weather Station',
      'safetymonitor' => 'Safety Monitor',
      'switch' => 'Switch',
      'covercalibrator' => 'Cover Calibrator',
      _ => 'Device',
    };
    return 'Alpaca $label';
  }
  return deviceId;
}

// =========================================================================
// Fuzzy fallback matcher
// =========================================================================
//
// Ported verbatim (logic-for-logic) from `profile_sidebar._deviceIdsMatch`.
// This is the legacy token/normalize matcher that lets a profile id which
// has drifted from the connected id (index/format changes, vendor-name
// reordering) still count as "the same device". The PHD2 short-circuit that
// lived at the top of the old function is handled upstream by canonical
// equality in [DeviceId.matches], so it is intentionally NOT duplicated here.
// Including it here too would be harmless (canonical equality already caught
// it), so for a faithful standalone port we keep it as a fast path.

bool _fuzzyDeviceIdsMatch(String profileId, String connectedId) {
  final p = profileId.trim().toLowerCase();
  final c = connectedId.trim().toLowerCase();

  // PHD2 fast path (mirrors the original inline short-circuit). Canonical
  // equality in DeviceId.matches already covers this, but a standalone fuzzy
  // matcher must remain correct on its own.
  if (_isPhd2Token(p) && _isPhd2Token(c)) return true;

  // Direct match
  if (p == c) return true;

  // Normalize by removing all non-alphanumeric characters
  final normP = p.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final normC = c.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (normP == normC) return true;

  // One contains the other (handles "ZWO EAF" containing "eaf")
  if (normP.contains(normC) || normC.contains(normP)) return true;

  // Extract model identifiers - alphanumeric sequences containing numbers
  final modelPattern = RegExp(r'[a-z]*\d+[a-z0-9]*|[a-z]{2,}');

  final profileModels = modelPattern
      .allMatches(normP)
      .map((m) => m.group(0)!)
      .toSet();
  final connectedModels = modelPattern
      .allMatches(normC)
      .map((m) => m.group(0)!)
      .toSet();

  // Find models that contain numbers (most distinguishing)
  final profileNumberedModels = profileModels
      .where((m) => RegExp(r'\d').hasMatch(m))
      .toSet();
  final connectedNumberedModels = connectedModels
      .where((m) => RegExp(r'\d').hasMatch(m))
      .toSet();

  // If both have numbered model identifiers, they must share at least one
  if (profileNumberedModels.isNotEmpty && connectedNumberedModels.isNotEmpty) {
    if (profileNumberedModels
        .intersection(connectedNumberedModels)
        .isNotEmpty) {
      return true;
    }
    // Check if one model contains another
    for (final pm in profileNumberedModels) {
      for (final cm in connectedNumberedModels) {
        if (pm.contains(cm) || cm.contains(pm)) return true;
      }
    }
    return false;
  }

  // Token-based matching
  final pTokens = p
      .split(RegExp(r'[_\-\s:]+'))
      .where((t) => t.length >= 2)
      .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
      .where((t) => t.isNotEmpty)
      .toSet();
  final cTokens = c
      .split(RegExp(r'[_\-\s:]+'))
      .where((t) => t.length >= 2)
      .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
      .where((t) => t.isNotEmpty)
      .toSet();

  if (pTokens.isEmpty || cTokens.isEmpty) return false;

  int matches = 0;
  for (final pt in pTokens) {
    for (final ct in cTokens) {
      if (pt == ct || pt.contains(ct) || ct.contains(pt)) {
        matches++;
        break;
      }
      if (pt.length >= 4 && ct.length >= 4) {
        int commonLen = 0;
        final minLen = pt.length < ct.length ? pt.length : ct.length;
        for (int i = 0; i < minLen; i++) {
          if (pt[i] == ct[i]) {
            commonLen++;
          } else {
            break;
          }
        }
        if (commonLen >= 4) {
          matches++;
          break;
        }
      }
    }
  }

  final minTokens = pTokens.length < cTokens.length
      ? pTokens.length
      : cTokens.length;
  return matches >= (minTokens * 0.5).ceil();
}

/// Public entry point for the fuzzy + canonical "is the connected device the
/// one the profile assigned" check, for call-sites that have raw strings.
///
/// Equivalent to `DeviceId.parse(profileId).matchesRaw(connectedId)`.
bool deviceIdsMatch(String profileId, String connectedId) {
  return DeviceId.parse(profileId).matchesRaw(connectedId);
}
