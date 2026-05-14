/// Nightshade Core - Shared business logic
library nightshade_core;

// Database - hide entity names that collide with domain-model classes of the
// same name. The drift row types for `CapturedImage` / `EquipmentProfile` are
// still reachable through this barrel via the `DbCapturedImage` /
// `DbEquipmentProfile` typedef aliases re-exported below
// (see audit-arch §3.2, §8 #13, CQ-W4-BARREL-EXPOSE).
export 'src/database/database.dart'
    hide Target, Sequence, SequenceNode, CapturedImage, EquipmentProfile;
export 'src/database/database_aliases.dart';
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
export 'src/database/daos/tutorial_dao.dart';
export 'src/database/daos/polar_alignment_history_dao.dart';
export 'src/database/daos/science_dao.dart';
export 'src/database/daos/dark_library_dao.dart';
export 'src/database/daos/observation_logs_dao.dart';
export 'src/database/daos/observing_lists_dao.dart';
export 'src/database/daos/sequence_runs_dao.dart';

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
// The model-layer FirstNightWizard class collides with the widget class of
// the same name in nightshade_app. We hide it from the barrel so callers
// either import tutorial_step.dart directly (the widget does) or just use
// FirstNightWizardStep.
export 'src/models/tutorial/tutorial_step.dart' hide FirstNightWizard;
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
export 'src/models/optical_config.dart';
export 'src/models/science/science_models.dart';
export 'src/models/defect_map.dart';
export 'src/models/plate_solver.dart';

// Scheduler (W6-SCHED: RoboTarget-class dynamic scheduler)
export 'src/models/scheduler/integration_goal.dart';
export 'src/models/scheduler/target_constraint.dart';
export 'src/models/scheduler/scheduler_decision.dart';
export 'src/models/scheduler/scheduler_status.dart';
export 'src/models/scheduler/target_progress.dart';
export 'src/services/scheduler/target_progress_service.dart';
export 'src/providers/target_progress_provider.dart';

// Sequence import (W6-NINA-IMPORT: NINA / SGP sequence import)
export 'src/models/import/canonical_sequence_node.dart';
export 'src/models/import/import_result.dart';

// Providers
export 'src/providers/app_version_provider.dart';
export 'src/providers/database_provider.dart';
export 'src/providers/equipment_provider.dart';
export 'src/providers/unified_discovery_provider.dart';
export 'src/providers/device_backend_selection_provider.dart';
export 'src/providers/event_provider.dart';
// framing_provider exposes the UI-facing FramingMosaicConfig /
// FramingMosaicPanel (grid-based: columns/rows/overlapPercent). The
// service-layer MosaicConfig / MosaicPanel in mosaic_service.dart
// (geometry-flavored: centerRa/panelWidthArcmin/...) live under their
// canonical names and are now safe to re-export from the barrel.
export 'src/providers/framing_provider.dart';
export 'src/providers/imaging_provider.dart';
export 'src/providers/imaging_viewer_state_provider.dart';
export 'src/providers/sequence_provider.dart';
export 'src/providers/sequence_stats_provider.dart';
export 'src/providers/import_provider.dart';
export 'src/providers/session_provider.dart';
// Hide settings_provider's legacy HorizonProfile so the scheduler's
// samples-based HorizonProfile (services/scheduler/horizon_profile.dart) wins
// at the barrel. Direct importers of settings_provider.dart still see it.
export 'src/providers/settings_provider.dart' hide HorizonProfile;
export 'src/providers/profiles_provider.dart';
export 'src/providers/guiding_provider.dart';
export 'src/providers/backend_provider.dart';
export 'src/providers/simbad_provider.dart';
export 'src/providers/exoplanet_provider.dart';
export 'src/providers/gaia_provider.dart';
export 'src/providers/annotation_settings_provider.dart';
export 'src/providers/annotation_presets_provider.dart'
    hide AnnotationPreset, annotationPresetsProvider, AnnotationPresetsNotifier;
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
export 'src/providers/suggestion_filter_provider.dart';
export 'src/providers/transient_alert_provider.dart';
export 'src/providers/auto_stretch_provider.dart';
export 'src/providers/science_provider.dart';
export 'src/providers/autofocus_progress_provider.dart';
export 'src/providers/push_notification_provider.dart';
export 'src/providers/dark_library_provider.dart';
export 'src/providers/live_stacking_provider.dart';
export 'src/providers/project_tracking_provider.dart';
export 'src/providers/equipment_health_provider.dart';
export 'src/providers/optical_train_diagnostics_provider.dart';
export 'src/providers/session_handoff_provider.dart';
export 'src/providers/session_optimizer_provider.dart';
export 'src/providers/web_server_provider.dart';
export 'src/providers/observation_log_provider.dart';
export 'src/providers/observing_list_provider.dart';
export 'src/providers/imaging_history_provider.dart';
export 'src/providers/live_validation_provider.dart';
export 'src/providers/period_analysis_provider.dart';
export 'src/providers/photometric_transform_provider.dart';
export 'src/providers/defect_map_provider.dart';
export 'src/providers/plate_solver_provider.dart';

// Backend interface
export 'src/backend/nightshade_backend.dart';
export 'src/backend/ffi_backend.dart';
export 'src/backend/network_backend.dart';
export 'src/backend/disconnected_backend.dart';
export 'src/models/backend/fits_header.dart';
export 'src/models/backend/image_result.dart';
export 'src/models/backend/platform_capabilities.dart';
export 'src/models/backend/remote_api_compatibility.dart';

// Services
export 'src/services/device_service.dart';
export 'src/services/device_matching_service.dart';
export 'src/services/imaging_service.dart';
export 'src/services/plate_solve_service.dart' hide PlateSolveResult;
export 'src/services/polar_alignment_service.dart';
export 'src/services/centering_service.dart';
export 'src/services/profile_service.dart';
export 'src/services/sequence_repository.dart';
export 'src/services/sequence_file_service.dart';
export 'src/services/sample_sequence_service.dart';
export 'src/services/import/sequence_importer.dart';
export 'src/services/import/nina_sequence_parser.dart';
export 'src/services/import/sgp_sequence_parser.dart';
export 'src/services/import/canonical_node_mapper.dart';
export 'src/services/wcs_overlay.dart';
export 'src/services/annotation_service.dart';
export 'src/services/scheduler_service.dart';
export 'src/services/scheduler/scheduler_engine.dart';
export 'src/services/scheduler/integration_goal_service.dart'
    hide
        integrationGoalsSchemaSql,
        integrationGoalsTargetIndexSql,
        targetConstraintsSchemaSql,
        targetConstraintsTargetIndexSql,
        horizonProfilesSchemaSql;
export 'src/services/scheduler/target_constraint_service.dart';
// Two HorizonProfile classes exist in the codebase:
//   * settings_provider.dart::HorizonProfile  - legacy 8-point compass profile
//     stored as JSON in app_settings.horizon_profile_json
//   * services/scheduler/horizon_profile.dart::HorizonProfile  - newer
//     samples-based profile persisted in the horizon_profiles drift table
// The legacy one is still referenced by target_suggestion_service.dart via a
// `show` import; we hide it from the barrel so the scheduler's profile is the
// canonical public class.
export 'src/services/scheduler/horizon_profile.dart';
export 'src/services/scheduler/sky_calculations.dart';
export 'src/providers/scheduler_provider.dart';
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
export 'src/services/push_notification_service.dart';
export 'src/services/session_export_service.dart';
export 'src/services/mosaic_service.dart';
export 'src/services/session_service.dart';
export 'src/services/quick_start_service.dart';
export 'src/services/calibration_service.dart';
export 'src/services/frame_quality_assessment_service.dart';
export 'src/services/session_optimizer_service.dart';
export 'src/services/optical_train_diagnostics_service.dart';
export 'src/services/equipment_health_service.dart';
export 'src/services/session_handoff_service.dart';
export 'src/services/weather/weather_radar_service.dart';
export 'src/services/weather/cloud_motion_analyzer.dart';
export 'src/services/weather/weather_alert_service.dart';
export 'src/services/smart_notification_service.dart';
export 'src/services/target_suggestion_service.dart';
export 'src/services/transient_alert_service.dart';
export 'src/services/sequence_time_estimator.dart';
export 'src/services/science/science_backend.dart';
export 'src/services/science/default_science_backend.dart';
export 'src/services/science/science_processing_service.dart';
export 'src/services/science/photometric_transform_service.dart';
export 'src/services/science/aavso_export_service.dart';
export 'src/services/science/mpc_export_service.dart';
export 'src/services/science/period_analysis_service.dart';
export 'src/services/dark_library_service.dart';
export 'src/services/live_stacking_service.dart';
export 'src/services/project_tracking_service.dart';
export 'src/services/calibration/defect_map_service.dart';

// Utilities
export 'src/utils/coordinate_parser.dart';
export 'src/utils/plate_solver_utils.dart';
