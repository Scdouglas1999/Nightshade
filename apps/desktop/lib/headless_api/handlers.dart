// Export all handler modules
export 'handlers/auth_handlers.dart';
export 'handlers/collaboration_handlers.dart';
export 'handlers/device_handlers.dart';
export 'handlers/device_discovery_handlers.dart';
export 'handlers/static_file_handlers.dart';
export 'handlers/pairing_handlers.dart';
export 'handlers/push_handlers.dart';
export 'handlers/system_handlers.dart';
export 'handlers/equipment_handlers.dart';
export 'handlers/guiding_handlers.dart';
export 'handlers/imaging_handlers.dart';
export 'handlers/profile_handlers.dart';
export 'handlers/sequencer_handlers.dart';
export 'handlers/session_handlers.dart';

// New feature parity handlers
export 'handlers/target_handlers.dart';
export 'handlers/sequence_management_handlers.dart';
export 'handlers/flat_wizard_handlers.dart';
export 'handlers/mosaic_handlers.dart';
export 'handlers/analytics_handlers.dart';
export 'handlers/weather_handlers.dart';
export 'handlers/suggestion_handlers.dart';
export 'handlers/transient_handlers.dart';
export 'handlers/backup_handlers.dart';
export 'handlers/sync_handlers.dart';
export 'handlers/framing_handlers.dart';
export 'handlers/filesystem_handlers.dart';
export 'handlers/science_handlers.dart';

// Auxiliary device handlers
export 'handlers/dome_handlers.dart';
export 'handlers/safety_monitor_handlers.dart';
export 'handlers/auxiliary_handlers.dart';

// Planetarium support for remote clients
export 'handlers/planetarium_handlers.dart';

// Intelligent scheduler and focus model
export 'handlers/scheduler_handlers.dart';
export 'handlers/focus_model_handlers.dart';

// Wave 6 — phone/tablet run-watch monitoring surface
export 'handlers/run_watch_handlers.dart';

// P2-10 — push-based live-view streaming over WebSocket
export 'handlers/live_view_stream_handlers.dart';

// Wave 7A — WebRTC datachannel fan-out for the same live-view producer
export 'handlers/webrtc_live_view_handlers.dart';

// Wave 7 Agent 2 — live-stacking broadcast for EAA / outreach
export 'handlers/broadcast_handlers.dart';

// P1-14 — remote log retrieval and tail SSE
export 'handlers/log_handlers.dart';

// P1-2 / P1-3 — long-running job model handlers
export 'handlers/job_handlers.dart';

// P1-5 — session ownership handlers
export 'handlers/session_ownership_handlers.dart';

// P1-11 — headless OTA update endpoints
export 'handlers/update_handlers.dart';

// P1-10 — remote calibration library (dark/flat/defect-map) management
export 'handlers/calibration_handlers.dart';

// v46 — unified Calibration Library Manager (browse / match / tag)
export 'handlers/calibration_library_handlers.dart';

// P1-12 — catalog management (download/upload/verify/uninstall/reload)
export 'handlers/catalog_handlers.dart';

// P2-8 — read-only DB endpoints (sequence runs, notes journal,
// guide RMS history, polar alignment history, dark library, flat history)
export 'handlers/db_read_handlers.dart';

// P2-11 — plugin management API (list / upload / enable / disable / uninstall)
export 'handlers/plugin_handlers.dart';
