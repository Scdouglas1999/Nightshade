import 'roles/device_backend.dart';
import 'roles/diagnostics_backend.dart';
import 'roles/guiding_backend.dart';
import 'roles/imaging_backend.dart';
import 'roles/profile_settings_backend.dart';
import 'roles/sequencer_backend.dart';

// Re-export backend types for backward compatibility
export '../models/backend/backend_types.dart';
// Re-export the FRB-canonical PlateSolveResult so callers can keep importing
// just `nightshade_backend.dart` after the model-layer copy was deleted.
// Also re-export CameraRecommendedSettings so device service / UI code can
// stay on the nightshade_backend import path.
export 'package:nightshade_bridge/nightshade_bridge.dart'
    show PlateSolveResult, CameraRecommendedSettings, FitsReadResult;

// Re-export the role interfaces so consumers that want a single import
// path can write `import '.../nightshade_backend.dart';` and still get
// the role types.
export 'roles/roles.dart';

/// Marker interface composing every role-specific backend interface.
///
/// Concrete backends (`FfiBackend`, `NetworkBackend`, `DisconnectedBackend`)
/// implement [NightshadeBackend], which unconditionally drags in every
/// role. Existing call sites that take a `NightshadeBackend` and use any
/// subset of methods continue to work unchanged.
///
/// **For new code**: prefer depending on the narrowest role you need
/// ([DeviceBackend], [GuidingBackend], [ImagingBackend], [SequencerBackend],
/// [ProfileSettingsBackend], [DiagnosticsBackend]) rather than the full
/// [NightshadeBackend]. Riverpod role-specific providers
/// (`deviceBackendProvider`, `imagingBackendProvider`, etc.) read through
/// the same underlying `backendProvider` state, so swapping backends
/// remains a single state mutation.
///
/// **Why this exists as a marker and not a fat interface body**: the file
/// used to declare 157 abstract methods. Every new backend feature forced a
/// 4-file edit (interface + three impls), and the file mixed unrelated
/// concerns (device control, image processing, sequencer runtime config,
/// recovery, profiles). Splitting the contract along the role seams above
/// makes the intent of each consumer visible at its import list and lets
/// `DisconnectedBackend` future-proof itself by only implementing the roles
/// it can legitimately answer. The marker preserves the 500+ existing call
/// sites that expect a single backend object.
///
/// **DO NOT add new methods to this class**. New methods belong in the
/// role interface for their concern. If no existing role fits, add a new
/// role file under `backend/roles/` and have [NightshadeBackend]
/// `implements` it.
abstract class NightshadeBackend
    implements
        DeviceBackend,
        GuidingBackend,
        ImagingBackend,
        SequencerBackend,
        ProfileSettingsBackend,
        DiagnosticsBackend {
  // Intentionally empty. See class doc.
}
