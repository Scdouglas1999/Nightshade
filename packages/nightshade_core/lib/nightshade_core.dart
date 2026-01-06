/// Nightshade Core - Shared business logic
library nightshade_core;

// Database - hide conflicting entity names
export 'src/database/database.dart' hide Target, Sequence, SequenceNode, CapturedImage, EquipmentProfile;
export 'src/database/seed_data.dart';

// DAOs
export 'src/database/daos/equipment_profiles_dao.dart';
export 'src/database/daos/targets_dao.dart';
export 'src/database/daos/sessions_dao.dart';
export 'src/database/daos/images_dao.dart';
export 'src/database/daos/sequences_dao.dart';
export 'src/database/daos/sequence_checkpoints_dao.dart';
export 'src/database/daos/settings_dao.dart';
export 'src/database/daos/weather_settings_dao.dart';

// Data models (domain models, distinct from DB entities)
// Hide TrackingRate from equipment_models - canonical version is in backend/device_capabilities
export 'src/models/equipment/equipment_models.dart' hide TrackingRate;
export 'src/models/equipment/unified_device.dart';
export 'src/models/equipment/discovery_state.dart';
export 'src/models/equipment_profile.dart';
export 'src/models/settings/app_settings.dart' hide AppSettings;
export 'src/models/imaging/imaging_models.dart';
export 'src/models/imaging/camera_preset.dart';
export 'src/models/sequence/sequence_models.dart';
export 'src/models/target/target_models.dart';
export 'src/models/annotation_data.dart';
export 'src/models/annotation_settings.dart';
export 'src/models/tutorial/tutorial_models.dart';
export 'src/models/phd2_models.dart';
export 'src/models/weather/weather_models.dart';
export 'src/models/autofocus_progress.dart';
export 'src/models/meridian_flip_settings.dart';

// Providers
export 'src/providers/database_provider.dart';
export 'src/providers/equipment_provider.dart';
export 'src/providers/unified_discovery_provider.dart';
export 'src/providers/device_backend_selection_provider.dart';
export 'src/providers/event_provider.dart';
export 'src/providers/framing_provider.dart' hide MosaicConfig, MosaicPanel;
export 'src/providers/imaging_provider.dart';
export 'src/providers/sequence_provider.dart';
export 'src/providers/session_provider.dart';
export 'src/providers/settings_provider.dart';
export 'src/providers/profiles_provider.dart';
export 'src/providers/guiding_provider.dart';
export 'src/providers/backend_provider.dart';
export 'src/providers/simbad_provider.dart';
export 'src/providers/exoplanet_provider.dart';
export 'src/providers/gaia_provider.dart';
export 'src/providers/annotation_settings_provider.dart';
export 'src/providers/tutorial_provider.dart';
export 'src/providers/filter_offset_provider.dart';
export 'src/providers/camera_presets_provider.dart';
export 'src/providers/weather_providers.dart';
export 'src/providers/capability_provider.dart';

// Backend interface
export 'src/backend/nightshade_backend.dart' hide CameraState;
export 'src/backend/ffi_backend.dart';
export 'src/backend/network_backend.dart';
export 'src/backend/disconnected_backend.dart';

// Services
export 'src/services/device_service.dart';
export 'src/services/device_matching_service.dart';
export 'src/services/imaging_service.dart';
export 'src/services/plate_solve_service.dart' hide PlateSolveResult;
export 'src/services/centering_service.dart';
export 'src/services/profile_service.dart';
export 'src/services/sequence_repository.dart';
export 'src/services/sequence_file_service.dart';
export 'src/services/wcs_overlay.dart';
export 'src/services/annotation_service.dart';
export 'src/services/scheduler_service.dart';
// Hide FocusDataPoint from focus_model_service - canonical version is in backend/autofocus_result
export 'src/services/focus_model_service.dart' hide FocusDataPoint;
export 'src/services/logging_service.dart';
export 'src/services/error_service.dart';
export 'src/services/flat_wizard_service.dart';
export 'src/services/backup_service.dart';
export 'src/services/auto_save_service.dart';
export 'src/services/notification_service.dart';
export 'src/services/session_export_service.dart';
export 'src/services/mosaic_service.dart';
export 'src/services/session_service.dart';
export 'src/services/weather/weather_radar_service.dart';
export 'src/services/weather/cloud_motion_analyzer.dart';
export 'src/services/weather/weather_alert_service.dart';

// Utilities
export 'src/utils/retry.dart';
export 'src/utils/coordinate_parser.dart';
export 'src/utils/circuit_breaker.dart';
export 'src/utils/plate_solver_utils.dart';
