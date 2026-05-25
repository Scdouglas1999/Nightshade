/// Nightshade Planetarium v2 — Flutter shell for the Rust+wgpu renderer.
///
/// Phase 7 tasks 76+ add bridge handles, providers, and widgets.
library nightshade_planetarium_v2;

export 'src/bridge/planetarium_driver.dart';
export 'src/bridge/planetarium_handle.dart';
export 'src/models/planetarium_astro_time.dart';
export 'src/models/render_config_state.dart';
export 'src/models/view_pose_state.dart';
export 'src/providers/core_observation_time_provider.dart';
export 'src/providers/observer_provider.dart';
export 'src/providers/observation_time_provider.dart';
export 'src/providers/planetarium_handle_provider.dart';
export 'src/providers/render_config_provider.dart';
export 'src/providers/view_pose_provider.dart';
export 'src/widgets/interactive_sky_view.dart';
