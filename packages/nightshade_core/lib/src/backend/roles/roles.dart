// Barrel for the role-interface decomposition of NightshadeBackend.
//
// Consumers that need only a slice of the backend surface should import
// this barrel (or the specific role file) instead of pulling in the full
// NightshadeBackend interface. New consumers SHOULD depend on the
// smallest role that satisfies them; existing consumers can continue to
// depend on NightshadeBackend without change because the marker
// interface composes every role here.
export 'device_backend.dart';
export 'diagnostics_backend.dart';
export 'guiding_backend.dart';
export 'imaging_backend.dart';
export 'profile_settings_backend.dart';
export 'sequencer_backend.dart';
