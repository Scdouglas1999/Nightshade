/// Nightshade Planetarium v2 — Flutter shell for the Rust+wgpu renderer.
///
/// Hosts the Rust-rendered Texture widget plus Flutter overlay layers
/// (labels, constellation art, FOV reticle, ...). The thin shell forwards
/// gestures/lifecycle to Rust and reads a frame-synced scene snapshot to
/// drive the overlays.
library;

export 'src/bridge/gesture_events.dart';
export 'src/bridge/planetarium_driver.dart';
export 'src/bridge/planetarium_handle.dart';
export 'src/models/planetarium_astro_time.dart';
export 'src/models/render_config_state.dart';
export 'src/models/scene_snapshot.dart';
export 'src/models/view_pose_state.dart';
export 'src/providers/constellation_art_placements_provider.dart';
export 'src/providers/core_observation_time_provider.dart';
export 'src/providers/observation_time_provider.dart';
export 'src/providers/observer_provider.dart';
export 'src/providers/planetarium_handle_provider.dart';
export 'src/providers/planetarium_quiesced_provider.dart';
export 'src/providers/render_config_provider.dart';
export 'src/providers/scene_snapshot_provider.dart';
export 'src/providers/selection_provider.dart';
export 'src/providers/view_pose_provider.dart';
export 'src/rendering/label_layout_manager.dart';
export 'src/widgets/constellation_art_layer.dart';
export 'src/widgets/fov_overlay.dart';
export 'src/widgets/interactive_sky_view.dart';
export 'src/widgets/label_layer.dart';
