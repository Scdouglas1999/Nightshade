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
// Aliases for class names hidden from the barrel due to symbol collisions
// (legacy HorizonProfile vs scheduler HorizonProfile; tutorial-step
// FirstNightWizard model vs nightshade_app FirstNightWizard widget).
export 'src/legacy_aliases.dart';
export 'src/database/integrity_check.dart';
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
// Stack-and-Share Loop (component C3): persisted stacked-result provenance.
export 'src/database/daos/stacked_results_dao.dart';
export 'src/database/daos/observation_logs_dao.dart';
export 'src/database/daos/observing_lists_dao.dart';
export 'src/database/daos/sequence_runs_dao.dart';

// Data models (domain models, distinct from DB entities)
// TrackingRate is re-exported from equipment_models.dart (canonical source: device_capabilities.dart)
export 'src/models/equipment/equipment_models.dart';
export 'src/models/equipment/unified_device.dart';
export 'src/models/equipment/discovery_state.dart';
export 'src/models/equipment_profile.dart';
export 'src/models/settings/app_settings.dart';
export 'src/models/imaging/imaging_models.dart';
export 'src/models/imaging/camera_preset.dart';
export 'src/models/imaging/auto_stretch_settings.dart';
// Stack-and-Share Loop (component C7): config, progress, result, export models.
export 'src/models/imaging/stack_and_share_models.dart';
// Post-session integration: advanced settings model + integrated-master models.
export 'src/models/imaging/integration_settings.dart';
export 'src/models/imaging/integrated_master.dart';
// Wave 6E — push-based live-view streaming over WebSocket.
export 'src/models/live_view/live_view_frame.dart';
export 'src/models/calibration/dark_library_match_tolerances.dart';
// P1-10 — wire-level model classes for the headless calibration API.
export 'src/models/calibration/remote_calibration_models.dart';
export 'src/models/sequence/sequence_models.dart';
// Wave 5 Agent 2 — sky-brightness adaptive exposure event surface.
export 'src/models/sequence/adaptive_exposure_event.dart';
export 'src/models/sequence/instruction_progress_detail.dart';
export 'src/models/sequence/template_snippet.dart';
// Wave 4 — variable / expression interpolation catalog. Dart-side mirror
// of the Rust `expressions::catalog`. Drives the VariablePicker UI.
export 'src/models/sequence/interpolation_catalog.dart';
export 'src/models/target/target_models.dart';
// HiPS framing tile-layer value types (pure Dart): properties parser, tile
// addressing, and the SurveySource -> CDS HiPS survey registry.
export 'src/models/hips/hips_properties.dart';
export 'src/models/hips/hips_tile_id.dart';
export 'src/models/hips/hips_survey_registry.dart';
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
// Multi-Night & Forecast Planning (Roadmap #5).
//   * project.dart           - Project / ProjectTarget campaign models.
//   * project_progress.dart  - FilterProgressLine / ProjectTargetProgress /
//     CampaignProgress (derived accrued-vs-goal roll-ups). FilterProgressLine
//     is deliberately named to avoid colliding with scheduler FilterProgress;
//     the project roll-up is named `CampaignProgress` (a project IS a
//     multi-night campaign) to avoid colliding with the unrelated, pre-existing
//     analytics project_tracking_service.dart::ProjectProgress (also on the
//     barrel, consumed by analytics/widgets/project_tracking_panel.dart). Both
//     are exported under their own names — no `hide`, no inferred-only type.
//   * night_forecast.dart    - ForecastTargetUp / NightForecast / WeekForecast.
export 'src/models/planning/project.dart';
export 'src/models/planning/project_progress.dart';
export 'src/models/planning/night_forecast.dart';
export 'src/models/optical_config.dart';
export 'src/models/onboarding/onboarding_state.dart';
// Quick Wins Bundle (C1/C2) — post-onboarding "next use" nudge surface.
//   * next_use_steps.dart            - pure-Dart action-step catalog
//     (NextUseActionId / NextUseStep / kNextUseSteps / stepFor).
//   * next_use_prompt_provider.dart  - readiness/completion/dismissal
//     wiring + the pure selectNextUseStep decision and the
//     nextUsePromptProvider the dashboard prompt card watches.
export 'src/models/onboarding/next_use_steps.dart';
export 'src/models/hardware_presets/hardware_preset_models.dart';
export 'src/models/science/science_models.dart';
export 'src/models/defect_map.dart';
export 'src/models/plate_solver.dart';
export 'src/models/readiness/readiness_models.dart';
export 'src/models/session_report.dart';
export 'src/models/campaign_rollup.dart';

// Scheduler (W6-SCHED: RoboTarget-class dynamic scheduler)
export 'src/models/scheduler/integration_goal.dart';
export 'src/models/scheduler/target_constraint.dart';
export 'src/models/scheduler/scheduler_decision.dart';
export 'src/models/scheduler/scheduler_status.dart';
export 'src/models/scheduler/target_progress.dart';
export 'src/services/scheduler/target_progress_service.dart';
export 'src/providers/target_progress_provider.dart';
export 'src/services/catalog_target_resolver.dart';
export 'src/services/target_library_service.dart'
    show TargetLibraryService, targetLibraryServiceProvider;

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
// framingImageCacheServiceProvider is the canonical DI handle for the survey
// snapshot cache; export it so framing UI (action rail, screen) can resolve
// and override the same instance the framing notifier uses.
export 'src/providers/framing_image_cache_provider.dart';
// HiPS framing tile-layer Riverpod wiring (C7): fetcher/cache/loader DI handles,
// the resident-tiles snapshot the framing painter watches, and the feature flag
// gating the GPU-composited tiled survey background. Renders inside the framing
// path (not the planetarium renderer).
export 'src/providers/hips_framing_provider.dart';
export 'src/providers/imaging_provider.dart';
export 'src/providers/imaging_viewer_state_provider.dart';
export 'src/providers/sequence_provider.dart';
export 'src/providers/sequence/remote_sequence_editor_sync.dart';
export 'src/providers/sequence_stats_provider.dart';
// Wave 6 Thumbnails — inline frame thumbnails in the sequence tree.
export 'src/providers/sequence/exposure_node_thumbnails_provider.dart';
// Wave 6 Pack P — plugin-node dispatcher abstraction. The app entry
// point overrides this provider with the real PluginNodeExecutor
// (from nightshade_plugins) via `pluginNodeDispatcherOverride()`.
export 'src/providers/plugin_node_dispatcher.dart';
export 'src/providers/session_report_provider.dart';
export 'src/providers/campaign_rollup_provider.dart';
export 'src/providers/import_provider.dart';
export 'src/providers/session_provider.dart';
// Hide settings_provider's legacy HorizonProfile so the scheduler's
// samples-based HorizonProfile (services/scheduler/horizon_profile.dart) wins
// at the barrel. Direct importers of settings_provider.dart still see it.
export 'src/providers/settings_provider.dart' hide HorizonProfile;
export 'src/providers/clock_provider.dart';
export 'src/providers/profiles_provider.dart';
export 'src/providers/equipment_fov_provider.dart';
export 'src/providers/guiding_provider.dart';
export 'src/providers/backend_provider.dart';
export 'src/providers/remote_session_sync_provider.dart';
export 'src/providers/remote_sync_events.dart';
export 'src/providers/remote_sync_handler.dart';
export 'src/providers/host_mutation_event_provider.dart';
export 'src/providers/host_local_sync_provider.dart';
// Wave 6B (P2-1) — hot-plug device-detection event bridge.
export 'src/providers/hotplug_event_bridge_provider.dart';
export 'src/models/backend/host_mutation_event.dart';
export 'src/services/host_mutation_event_hub.dart';
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
export 'src/providers/equipment/device_capability_provider.dart';
export 'src/providers/meridian_countdown_provider.dart';
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
export 'src/providers/critical_alert_provider.dart';
export 'src/providers/device_connection_progress_provider.dart';
// Wave 4 Recovery Mode — providers for the recovery state machine
// (currentRecoveryProvider, recoveryHistoryProvider, recoveryControlProvider,
// recoveryEventBridgeProvider, recoveryAudibleBridgeProvider,
// recoveryPushBridgeProvider).
export 'src/providers/recovery_provider.dart';
// Wave 7B — Mobile session replay scrubber provider + types.
export 'src/providers/session_replay_provider.dart';
export 'src/providers/auto_stretch_provider.dart';
export 'src/providers/science_provider.dart';
export 'src/providers/science_status_provider.dart';
export 'src/providers/autofocus_progress_provider.dart';
export 'src/providers/push_notification_provider.dart';
export 'src/providers/dark_library_provider.dart';
export 'src/providers/live_stacking_provider.dart';
// Stack-and-Share Loop (component C7): orchestrator state + result viewer.
export 'src/providers/stack_and_share_provider.dart';
export 'src/providers/project_tracking_provider.dart';
export 'src/providers/equipment_health_provider.dart';
export 'src/providers/device_heartbeat_health_provider.dart';
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
export 'src/providers/readiness_provider.dart';
export 'src/providers/onboarding_provider.dart';
// Quick Wins Bundle (C2) — next-use prompt selection wiring. Exposes
// nextUsePromptProvider (the step the dashboard card surfaces), the pure
// selectNextUseStep decision, the completed/dismissed action providers, and
// the next_use.<id> screen-id helpers used to persist dismissals.
export 'src/providers/next_use_prompt_provider.dart';
export 'src/providers/disk_space_provider.dart';

// Backend interface
export 'src/backend/nightshade_backend.dart';
export 'src/backend/ffi_backend.dart';
export 'src/backend/network_backend.dart';
export 'src/backend/disconnected_backend.dart';
export 'src/models/backend/fits_header.dart';
export 'src/models/backend/image_result.dart';
export 'src/models/backend/platform_capabilities.dart';
export 'src/models/backend/remote_api_compatibility.dart';
// Wave 4 Recovery Mode — Dart mirror of the Rust `RecoveryContext`,
// `RecoveryHistoryEntry`, `RecoveryCause`, and `RecoveryPhase` so the Run
// Dashboard recovery banner and post-session report render the same data
// the executor publishes.
export 'src/models/sequencer/recovery_status.dart';

// Services
export 'src/services/device_service.dart';
export 'src/services/device_exceptions.dart';
export 'src/utils/device_id_utils.dart' show isValidDeviceIdFormat;
// Single source of truth for device-identity logic: parsing, canonicalization,
// matching, and id-pattern friendly-name fallback.
export 'src/utils/device_id.dart'
    show
        DeviceId,
        DeviceDriverKind,
        canonicalGuiderId,
        isPhd2DeviceId,
        deviceIdsMatch,
        friendlyNameFromDeviceId,
        kPhd2CanonicalId;
export 'src/services/phd2_status_poll.dart';
export 'src/services/device_matching_service.dart';
export 'src/services/imaging_service.dart';
export 'src/services/thumbnail_sidecar_service.dart';
export 'src/providers/thumbnail_sidecar_provider.dart';
export 'src/services/plate_solve_service.dart';
export 'src/services/first_light/first_light_orchestrator.dart';
export 'src/providers/first_light_provider.dart';
export 'src/services/polar_alignment_service.dart';
export 'src/services/centering_service.dart';
export 'src/services/profile_service.dart';
export 'src/services/sequence_repository.dart';
export 'src/services/sequence_file_service.dart';
export 'src/services/snippet_file_service.dart';
export 'src/services/sample_sequence_service.dart';
export 'src/services/import/sequence_importer.dart';
export 'src/services/import/nina_sequence_parser.dart';
export 'src/services/import/sgp_sequence_parser.dart';
export 'src/services/import/canonical_node_mapper.dart';
export 'src/services/import/csv_parser.dart';
export 'src/services/import/telescopius_csv_importer.dart';
export 'src/services/import/observing_list_json_importer.dart';
export 'src/services/import/astrobin_importer.dart';
export 'src/services/import/ics_calendar_importer.dart';
export 'src/services/import/generic_csv_importer.dart';
export 'src/services/wcs_overlay.dart';
export 'src/services/wcs/gnomonic_projection.dart';
export 'src/services/hips/healpix_nested.dart';
export 'src/services/catalog_overlay_service.dart';
export 'src/providers/catalog_overlay_provider.dart';
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
// Multi-Night & Forecast Planning (Roadmap #5) — services + Riverpod wiring.
//   * project_service.dart           - Project/membership CRUD + derived
//     CampaignProgress roll-up over the raw projects / project_targets tables.
//     The schema DDL constants are hidden from the barrel (mirroring the
//     scheduler stack); scheduler_provider.dart imports them directly via the
//     src path to ensure the planner tables exist alongside the scheduler ones.
//   * forecast_planning_service.dart - pure, I/O-free N-night clear-dark-hours
//     scorer fed already-fetched hourly cloud data + project target candidates.
//   * planning_provider.dart         - active-project selection, project list /
//     progress, and the week-ahead forecast providers (forecast fetch lives at
//     this provider layer, per the scheduler-stack convention).
export 'src/services/planning/project_service.dart'
    hide
        projectsSchemaSql,
        projectTargetsSchemaSql,
        projectTargetsProjectIndexSql,
        projectTargetsTargetIndexSql;
export 'src/services/planning/forecast_planning_service.dart';
export 'src/providers/planning_provider.dart';
export 'src/services/focus_model_service.dart';
// Wave 8 — Predictive autofocus persisted per-filter learning + drift detection.
export 'src/services/predictive_af_service.dart';
export 'src/services/logging_service.dart';
export 'src/services/diagnostic_dump_service.dart';
export 'src/services/error_service.dart';
export 'src/services/flat_wizard_service.dart';
export 'src/services/sky_brightness_tracker.dart';
export 'src/services/flat_exposure_calculator.dart';
export 'src/services/backup_service.dart';
export 'src/services/auto_save_service.dart';
// P2-11 — plugin management (upload/enable/disable/uninstall)
export 'src/services/plugin_management_service.dart';
export 'src/services/notification_service.dart';
export 'src/services/push_notification_service.dart';

// Wave 5 — Comprehensive notification routing.
//   * Per-event-type routing matrix across in-app / mobile push / email /
//     webhook / Pushover / Telegram / Discord / MQTT.
//   * Per-transport configuration models.
//   * NotificationRouter dispatcher (event-stream → transports).
export 'src/models/notification/notification_categories.dart';
export 'src/models/notification/transport_configs.dart';
export 'src/services/notification/notification_router.dart';
export 'src/services/notification/notification_template.dart';
export 'src/services/notification/secrets_store.dart';
export 'src/services/notification/transports/notification_transport.dart';
export 'src/services/notification/transports/discord_transport.dart';
export 'src/services/notification/transports/email_transport.dart';
export 'src/services/notification/transports/in_app_transport.dart';
export 'src/services/notification/transports/mqtt_transport.dart';
export 'src/services/notification/transports/pushover_transport.dart';
export 'src/services/notification/transports/system_push_transport.dart';
export 'src/services/notification/transports/telegram_transport.dart';
export 'src/services/notification/transports/webhook_transport.dart';
export 'src/providers/notification_router_provider.dart';
export 'src/services/critical_alert_player.dart';
export 'src/services/session_export_service.dart';
export 'src/services/session_report_service.dart';
// Wave 6 Agent 5 — per-target / per-run notes journal + sequence diff.
export 'src/models/notes/journal_note.dart';
export 'src/services/notes_service.dart';
export 'src/services/sequence_diff_service.dart';
export 'src/providers/notes_provider.dart';
export 'src/services/campaign_rollup_service.dart';
export 'src/services/mosaic_service.dart';
export 'src/services/framing_image_cache_service.dart';
export 'src/services/session_service.dart';
export 'src/services/quick_start_service.dart';
export 'src/services/calibration_service.dart';
export 'src/services/frame_quality_assessment_service.dart';
// Wave 8 — Adaptive sky-conditions target-swap composer + dashboard
// snapshot decoder.
export 'src/services/adaptive_swap_service.dart';
// Wave 8 — Frame-Failure Forensics (per-rejection cause classification).
export 'src/models/forensics/frame_forensics.dart';
export 'src/services/forensics_service.dart';
export 'src/providers/forensics_provider.dart';
// Wave 8 — Replay Debug (retrospective decision-tree scrubber).
export 'src/models/replay_decision.dart';
export 'src/services/replay_debug_service.dart';
export 'src/providers/replay_debug_provider.dart';
export 'src/services/session_optimizer_service.dart';
export 'src/services/smart_night/exposure_calculator.dart';
export 'src/services/smart_night/guide_rms_collector.dart';
export 'src/services/smart_night/hardware_specs_service.dart';
export 'src/services/smart_night/dark_library_coverage.dart';
export 'src/services/smart_night/smart_night_draft_service.dart';
export 'src/providers/smart_night_draft_provider.dart';
// Wave 6 — Smart Night auto-builder (the one-click "plan tonight").
export 'src/services/smart_night_service.dart';
// Wave 8 — Conversational sequence builder (LLM-driven sequence planning).
export 'src/services/conversational_builder/llm_provider.dart';
export 'src/services/conversational_builder/llm_settings.dart';
export 'src/services/conversational_builder/conversational_builder_service.dart';
export 'src/services/conversational_builder/conversational_history_service.dart';
export 'src/services/conversational_builder/system_prompt_builder.dart';
export 'src/providers/conversational_builder_provider.dart';
export 'src/services/optical_train_diagnostics_service.dart';
export 'src/services/equipment_health_service.dart';
// Wave 5.5 — USB disconnect log (production source for
// DeviceHealthSnapshot.disconnectCountLast24h).
export 'src/services/usb_disconnect_log.dart';
export 'src/providers/usb_disconnect_log_provider.dart';
export 'src/services/session_handoff_service.dart';
export 'src/services/weather/weather_radar_service.dart';
export 'src/services/weather/cloud_motion_analyzer.dart';
export 'src/services/weather/weather_alert_service.dart';
export 'src/services/smart_notification_service.dart';
export 'src/services/target_suggestion_service.dart';
export 'src/services/transient_alert_service.dart';
export 'src/services/sequence_time_estimator.dart';
export 'src/services/pre_session_simulator.dart';
export 'src/services/science/science_backend.dart';
export 'src/services/science/default_science_backend.dart';
export 'src/services/science/science_processing_service.dart';
export 'src/services/science/science_status.dart';
export 'src/services/science/science_insights_engine.dart';
export 'src/services/science/science_report_exporter.dart';
export 'src/services/science/fits_header_writer.dart';
export 'src/services/science/frame_grade_rules.dart';
export 'src/services/science/frame_auto_grader.dart';
export 'src/services/science/photometric_transform_service.dart';
export 'src/services/science/aavso_export_service.dart';
export 'src/services/science/mpc_export_service.dart';
export 'src/services/science/period_analysis_service.dart';
export 'src/services/dark_library_service.dart';
export 'src/services/dark_library_coverage_service.dart';
export 'src/services/live_stacking_service.dart';
// Wave 7 Agent 2: broadcast endpoint for EAA / outreach live-stack viewing.
export 'src/services/live_stacking_broadcast_service.dart';
// Stack-and-Share Loop (components C6/C8): orchestrator + share/export service.
export 'src/services/stack_and_share_service.dart';
export 'src/services/stack_share_export_service.dart';
// Post-session (offline/batch) integration: archival masters + multi-night
// accumulation + master-flat library.
export 'src/services/post_session_seam.dart';
export 'src/services/post_session_integration_service.dart';
export 'src/services/master_accumulation_service.dart';
export 'src/services/flat_library_service.dart';
export 'src/database/daos/integrated_masters_dao.dart';
export 'src/database/daos/flat_library_dao.dart';
export 'src/services/project_tracking_service.dart';
export 'src/services/calibration/defect_map_service.dart';
export 'src/services/disk_space_service.dart';
export 'src/services/disk_space_guard.dart';
export 'src/services/safe_rig_service.dart';

// Utilities
export 'src/utils/coordinate_parser.dart';
export 'src/utils/coordinate_format.dart';
export 'src/utils/plate_solver_utils.dart';
