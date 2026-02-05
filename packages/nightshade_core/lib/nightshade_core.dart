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
export 'src/database/daos/flat_history_dao.dart';
export 'src/database/daos/tutorial_progress_dao.dart';
export 'src/database/daos/polar_alignment_history_dao.dart';

// Data models (domain models, distinct from DB entities)
// TrackingRate is re-exported from equipment_models.dart (canonical source: device_capabilities.dart)
export 'src/models/equipment/equipment_models.dart';
export 'src/models/equipment/unified_device.dart';
export 'src/models/equipment/discovery_state.dart';
export 'src/models/equipment_profile.dart';
export 'src/models/settings/app_settings.dart' hide AppSettings;
export 'src/models/imaging/imaging_models.dart';
export 'src/models/imaging/camera_preset.dart';
export 'src/models/imaging/auto_stretch_settings.dart';
export 'src/models/sequence/sequence_models.dart';
export 'src/models/sequence/template_snippet.dart';
export 'src/models/target/target_models.dart';
export 'src/models/annotation_data.dart';
export 'src/models/annotation_settings.dart';
export 'src/models/tutorial/tutorial_models.dart';
export 'src/models/phd2_models.dart';
export 'src/models/weather/weather_models.dart';
export 'src/models/autofocus_progress.dart';
export 'src/models/meridian_flip_settings.dart';
export 'src/models/meridian_flip_event.dart';
export 'src/models/flat_wizard/flat_wizard_settings.dart';
export 'src/models/flat_wizard/flat_wizard_state.dart';
export 'src/models/polar_alignment_config.dart';
export 'src/models/alerts/transient_alert.dart';
export 'src/models/planning/target_suggestion.dart';

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
export 'src/providers/meridian_flip_provider.dart';
export 'src/providers/flat_wizard_provider.dart';
export 'src/providers/ui_notification_provider.dart';
export 'src/providers/operation_progress_provider.dart';
export 'src/providers/current_screen_provider.dart';
export 'src/providers/polar_alignment_provider.dart';
export 'src/providers/template_snippet_provider.dart';
export 'src/providers/target_suggestion_provider.dart';
export 'src/providers/transient_alert_provider.dart';
export 'src/providers/auto_stretch_provider.dart';

// Backend interface
export 'src/backend/nightshade_backend.dart' hide CameraState;
export 'src/backend/ffi_backend.dart';
export 'src/backend/network_backend.dart';
export 'src/backend/disconnected_backend.dart';
export 'src/models/backend/fits_header.dart';
export 'src/models/backend/image_result.dart';

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
export 'src/services/sky_brightness_tracker.dart';
export 'src/services/flat_exposure_calculator.dart';
export 'src/services/backup_service.dart';
export 'src/services/auto_save_service.dart';
export 'src/services/notification_service.dart';
export 'src/services/session_export_service.dart';
export 'src/services/mosaic_service.dart';
export 'src/services/session_service.dart';
export 'src/services/quick_start_service.dart';
export 'src/services/weather/weather_radar_service.dart';
export 'src/services/weather/cloud_motion_analyzer.dart';
export 'src/services/weather/weather_alert_service.dart';
export 'src/services/smart_notification_service.dart';
export 'src/services/target_suggestion_service.dart';
export 'src/services/transient_alert_service.dart';
export 'src/services/sequence_time_estimator.dart';

// Utilities
export 'src/utils/coordinate_parser.dart';
export 'src/utils/plate_solver_utils.dart';
