/// System-info HTTP handlers for the headless API.
///
/// Owns the four read-only endpoints a remote client polls to discover
/// the server before doing any work:
///   * `GET /api/info` — server name, build version, API-version
///     envelope, pairing support, fingerprint, scope list, full
///     endpoint catalog, and the replay-buffer cursor.
///   * `GET /api/status` — sequencer state snapshot (the lightweight
///     poll endpoint mobile clients use to render the run badge).
///   * `GET /api/self-test` — full release-quality probe: platform
///     capabilities, application-data directory write probes, Drift
///     database initialisation check, connected-device round-trip,
///     auth/dashboard advertised state.
///   * `GET /api/openapi.json` — generated OpenAPI 3 document; the
///     route list is the same hand-maintained array advertised on
///     `/api/info`'s `endpoints` field.
///
/// None of these endpoints mutate state, so they share a single
/// constructor that captures the server snapshot getters (the auth
/// fingerprint, the event replay cursor, the static-file availability
/// flag, etc.) as a typed lookup interface.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';

import '../request_context.dart';
import '../response_helpers.dart';
import '../route_metadata.dart' as route_metadata;
import 'static_file_handlers.dart';

/// Authoritative catalog of every public HTTP endpoint the headless
/// server exposes. Surfaced in two places:
///   * the `endpoints` array on `GET /api/info`,
///   * the OpenAPI route list driving `GET /api/openapi.json`.
///
/// The headless-API contract audit
/// (`tools/production/headless_api_contract_audit.dart`) scans this
/// list and the actual `router.get/post/…` registrations and fails CI
/// if the two drift apart, so any new endpoint must be added here in
/// the same commit that registers it.
List<String> availableHeadlessEndpoints() {
  return const [
    // Core
    'GET /api/info',
    'GET /api/status',
    'GET /api/self-test',
    'GET /api/openapi.json',
    'POST /api/pairing/start',
    'POST /api/pairing/verify',
    'POST /api/pairing/lan-claim',
    // admin-only diagnostic listing currently-valid pairing
    // codes so a headless operator on a paired admin client can
    // retrieve the code without watching stdout.
    'GET /api/pairing/active',
    'POST /api/ws/ticket',
    'POST /api/auth/cookie',
    'GET /api/auth/csrf',
    'POST /api/auth/logout',
    'GET /api/collaboration/state',
    'POST /api/collaboration/viewers/join',
    'POST /api/collaboration/viewers/leave',
    'POST /api/collaboration/preview',
    'POST /api/collaboration/chat',
    'POST /api/collaboration/annotations',
    'GET /api/session-handoff',
    'POST /api/session-handoff',
    'DELETE /api/session-handoff',
    'GET /api/devices',
    'GET /api/devices/discover-indi',
    'GET /api/devices/discover-alpaca',
    'GET /api/devices/connected',
    'POST /api/devices/connect',
    'POST /api/devices/disconnect',
    'POST /api/devices/rescan',
    // Camera
    'POST /api/camera/expose',
    'POST /api/camera/abort',
    'GET /api/camera/last-image',
    'GET /api/camera/last-image/jpeg',
    'GET /api/camera/live-view/frame',
    // push-based live-view streaming. Listed alongside the pull
    // endpoint so OpenAPI consumers see both options.
    'WS /ws/live-view',
    // WebRTC datachannel live-view signalling. Operator
    // POSTs an SDP offer, server replies with answer; ICE candidates
    // trickle via POST and an SSE replay channel; DELETE tears down.
    'POST /api/webrtc/live-view/offer',
    'POST /api/webrtc/live-view/ice/<sessionId>',
    'GET /api/webrtc/live-view/ice/<sessionId>/events',
    'DELETE /api/webrtc/live-view/<sessionId>',
    'POST /api/camera/cooling',
    'GET /api/camera/cooling',
    'GET /api/camera/readout-modes',
    'POST /api/camera/readoutMode',
    'POST /api/camera/gain',
    'POST /api/camera/offset',
    'GET /api/camera/recommended-settings',
    // Mount
    'POST /api/mount/slew',
    'POST /api/mount/sync',
    'POST /api/mount/park',
    'POST /api/mount/unpark',
    'POST /api/mount/tracking',
    'POST /api/mount/pulse-guide',
    'POST /api/mount/abort',
    'GET /api/mount/status',
    'POST /api/mount/set-tracking-rate',
    'POST /api/mount/move-axis',
    'POST /api/mount/slew-alt-az',
    'POST /api/mount/find-home',
    // Focuser
    'POST /api/focuser/move-to',
    'POST /api/focuser/move-relative',
    'POST /api/focuser/halt',
    'POST /api/focuser/autofocus/start',
    'POST /api/focuser/autofocus/cancel',
    // Filter Wheel
    'POST /api/filter-wheel/position',
    'GET /api/filter-wheel/position',
    'GET /api/filter-wheel/names',
    'POST /api/filter-wheel/names',
    'POST /api/filter-wheel/set-by-name',
    // Rotator
    'POST /api/rotator/move-to',
    'POST /api/rotator/move-relative',
    'GET /api/rotator/status',
    'POST /api/rotator/halt',
    'POST /api/rotator/sync',
    // PHD2
    'POST /api/phd2/connect',
    'POST /api/phd2/disconnect',
    'POST /api/phd2/start-guiding',
    'POST /api/phd2/stop-guiding',
    'POST /api/phd2/dither',
    'GET /api/phd2/status',
    'POST /api/phd2/pause',
    'POST /api/phd2/clear-calibration',
    'POST /api/phd2/flip-calibration',
    'POST /api/phd2/get-calibration-data',
    'POST /api/phd2/find-star',
    'POST /api/phd2/set-lock-position',
    'GET /api/phd2/lock-position',
    'POST /api/phd2/loop',
    'POST /api/phd2/deselect-star',
    'GET /api/phd2/star-image',
    'GET /api/phd2/algo-params',
    'GET /api/phd2/algo-param',
    'POST /api/phd2/algo-param',
    // Generic Guider
    'POST /api/guider/start-guiding',
    'POST /api/guider/stop-guiding',
    'POST /api/guider/dither',
    'POST /api/guider/loop',
    'POST /api/guider/find-star',
    'POST /api/guider/set-lock-position',
    'GET /api/guider/lock-position',
    'POST /api/guider/deselect-star',
    'GET /api/guider/star-image',
    'GET /api/builtin-guider/config',
    'POST /api/builtin-guider/config',
    // Broadcast
    'GET /api/broadcast/info',
    'GET /api/broadcast/live-stack',
    'GET /api/broadcast/sse',
    // Plate Solving
    'POST /api/plate-solve',
    // Plate Solver Setup (host-owned detect/verify/config for remote clients)
    'GET /api/plate-solver/detect',
    'POST /api/plate-solver/verify',
    'GET /api/plate-solver/config',
    'POST /api/plate-solver/config',
    // Legacy Sequencer
    'GET /api/sequences/status',
    'POST /api/sequences/start',
    'POST /api/sequences/stop',
    // Sequencer
    'GET /api/sequencer/status',
    'POST /api/sequencer/start',
    'POST /api/sequencer/stop',
    'POST /api/sequencer/pause',
    'POST /api/sequencer/resume',
    'POST /api/sequencer/skip',
    'POST /api/sequencer/skip-to-node',
    'POST /api/sequencer/plugin-node-finished',
    'POST /api/sequencer/reset',
    'POST /api/sequencer/load',
    'POST /api/sequencer/simulation',
    'POST /api/sequencer/devices',
    'POST /api/sequencer/safety-fail-mode',
    'POST /api/sequencer/safety-check-interval',
    'POST /api/sequencer/save-path',
    'POST /api/sequencer/active-sequence-run-id',
    'POST /api/sequencer/decision-logging-enabled',
    'POST /api/sequencer/update-dither-config',
    'POST /api/sequencer/update-location',
    'POST /api/sequencer/update-filter-offsets',
    'POST /api/sequencer/update-pending-integration-carry-over',
    'POST /api/sequencer/update-autofocus-interval',
    'POST /api/sequencer/update-default-quality-check',
    'POST /api/sequencer/update-reject-folder-path',
    'POST /api/sequencer/update-observer-profile',
    'POST /api/sequencer/update-sky-brightness',
    'POST /api/sequencer/update-default-adaptive-exposure',
    'POST /api/sequencer/clear-default-adaptive-exposure',
    'POST /api/sequencer/checkpoint/dir',
    'GET /api/sequencer/checkpoint/has',
    'GET /api/sequencer/checkpoint/info',
    'POST /api/sequencer/checkpoint/resume',
    'POST /api/sequencer/checkpoint/discard',
    'POST /api/sequencer/checkpoint/save',
    'POST /api/sequencer/recovery/try-now',
    'POST /api/sequencer/recovery/abort',
    'POST /api/sequencer/recovery/update-config',
    'GET /api/sequencer/recovery/current',
    'GET /api/sequencer/recovery/history',
    'POST /api/sequencer/update-cloud-motion',
    'GET /api/sequencer/cloud-motion',
    'POST /api/sequencer/update-conditions-score',
    'GET /api/sequencer/adaptive-swap',
    'POST /api/sequencer/meridian-flip',
    'POST /api/sequencer/update-weather-verdict',
    // Secondary rig (dual-rig dither coordination)
    'GET /api/sequencer/secondary-rig',
    'POST /api/sequencer/secondary-rig/start',
    'POST /api/sequencer/secondary-rig/stop',
    // Equipment Status
    'GET /api/equipment/camera/status',
    'GET /api/equipment/mount/status',
    'GET /api/equipment/focuser/status',
    'GET /api/equipment/filter-wheel/status',
    'GET /api/equipment/rotator/status',
    // Equipment Capabilities
    'GET /api/equipment/camera/capabilities',
    'GET /api/equipment/mount/capabilities',
    'GET /api/equipment/focuser/capabilities',
    'GET /api/equipment/filter-wheel/capabilities',
    'GET /api/equipment/rotator/capabilities',
    // Device Health
    'POST /api/device/heartbeat/start',
    'POST /api/device/heartbeat/stop',
    'GET /api/device/health/<deviceId>',
    // Profiles
    'GET /api/profiles',
    'POST /api/profiles',
    'DELETE /api/profiles/<profileId>',
    'POST /api/profiles/<profileId>/load',
    'GET /api/profiles/active',
    // Settings
    'GET /api/settings',
    'POST /api/settings',
    'GET /api/settings/location',
    'POST /api/settings/location',
    'GET /api/location',
    // Imaging
    'POST /api/imaging/stats',
    'POST /api/imaging/stretch',
    'GET /api/imaging/star-crops',
    'POST /api/imaging/debayer',
    'GET /api/imaging/raw-data',
    'POST /api/imaging/save-fits',
    'POST /api/imaging/save-fits-from-capture',
    'POST /api/imaging/calibrate-file',
    'DELETE /api/imaging/device-image/<deviceId>',
    // Polar Alignment
    'POST /api/polar-alignment/start',
    'POST /api/polar-alignment/all-sky/start',
    'POST /api/polar-alignment/stop',
    // Session Images
    'GET /api/sessions/<sessionId>/images',
    'GET /api/images',
    'GET /api/images/recent',
    'GET /api/images/standalone',
    'POST /api/images',
    'GET /api/images/<imageId>',
    'PUT /api/images/<imageId>',
    'GET /api/images/<imageId>/thumbnail',
    // thumbnail cache management.
    'POST /api/images/backfill-thumbnails',
    'POST /api/images/<imageId>/regenerate-thumbnail',
    'GET /api/images/<imageId>/download',
    'GET /api/sessions/<sessionId>/export/json',
    'GET /api/sessions/<sessionId>/export/csv',
    'GET /api/sessions/<sessionId>/export/html',
    'GET /api/sessions/<sessionId>/export/<format>',
    // Targets
    'GET /api/targets',
    'GET /api/targets/favorites',
    'GET /api/targets/search',
    'GET /api/targets/by-type',
    'GET /api/targets/by-priority',
    'GET /api/targets/<id>',
    'POST /api/targets',
    'PUT /api/targets/<id>',
    'DELETE /api/targets/<id>',
    'POST /api/targets/<id>/favorite',
    'PUT /api/targets/<id>/progress',
    // Sequence Management
    'GET /api/sequence-management/list',
    'GET /api/sequence-management/list-full',
    'GET /api/sequence-management/templates-full',
    'POST /api/sequence-management/save-full',
    'GET /api/sequence-management/templates',
    'GET /api/sequence-management/<id>',
    'GET /api/sequence-management/<id>/nodes',
    'GET /api/sequence-management/<id>/children',
    'POST /api/sequence-management',
    'PUT /api/sequence-management/<id>',
    'DELETE /api/sequence-management/<id>',
    'POST /api/sequence-management/<id>/duplicate',
    'POST /api/sequence-management/<id>/nodes',
    'PUT /api/sequence-management/nodes/<nodeId>',
    'DELETE /api/sequence-management/nodes/<nodeId>',
    'POST /api/sequence-management/<id>/reorder',
    'POST /api/sequence-management/nodes/<nodeId>/enabled',
    // Flat Wizard
    'POST /api/flat-wizard/calibrate',
    'POST /api/flat-wizard/calibrate-multi',
    'POST /api/flat-wizard/generate-sequence',
    'POST /api/flat-wizard/quick-calibrate',
    // Mosaic
    'POST /api/mosaic/generate-panels',
    'POST /api/mosaic/generate-sequence',
    'POST /api/mosaic/calculate-area',
    'POST /api/mosaic/validate',
    'POST /api/mosaic/estimate-time',
    'GET /api/mosaic/recommended-exposure',
    // Sessions & Analytics
    'GET /api/sessions',
    'GET /api/sessions/active',
    'GET /api/sessions/recent',
    'GET /api/sessions/<id>',
    'GET /api/sessions/<id>/stats',
    'GET /api/sessions/<id>/psf-tiles',
    'GET /api/sessions/<id>/residuals',
    'GET /api/sessions/target/<targetId>',
    'POST /api/sessions',
    'PUT /api/sessions/<id>',
    'POST /api/sessions/<id>/end',
    'DELETE /api/sessions/<id>',
    'GET /api/files/browse',
    'POST /api/files/validate',
    // Science
    'GET /api/science/session/<sessionId>/bundle',
    'GET /api/science/sessionless/recent',
    'GET /api/science/settings',
    'POST /api/science/settings',
    'GET /api/science/session/<sessionId>/config',
    'POST /api/science/session/<sessionId>/config',
    'GET /api/science/transforms',
    'POST /api/science/calibration/image/<imageId>/match-stars',
    'POST /api/science/calibration/compute-transform',
    'POST /api/science/calibration/save-transform',
    'POST /api/science/session/<sessionId>/generate-line-ratios',
    'POST /api/science/session/<sessionId>/export/aavso',
    'GET /api/science/session/<sessionId>/report/pdf',
    'GET /api/analytics/summary',
    'GET /api/analytics/integration-time',
    'GET /api/analytics/target-statistics/<targetId>',
    'GET /api/analytics/untracked-targets/count',
    'POST /api/analytics/untracked-targets/remove',
    // Live stacking (EAA real-time integration)
    'POST /api/stacking/start',
    'POST /api/stacking/add-frame',
    'POST /api/stacking/config',
    'POST /api/stacking/reset',
    'POST /api/stacking/stop',
    'GET /api/stacking/status',
    'GET /api/stacking/stats',
    'GET /api/stacking/result',
    'GET /api/stacking/preview',
    // Post-session integration / finishing ("finish last night")
    'POST /api/post-session/integrate',
    'POST /api/post-session/drizzle',
    'POST /api/post-session/analyze-night',
    'POST /api/post-session/build-master-flat',
    'POST /api/post-session/color-calibrate',
    'POST /api/post-session/detect-stars',
    'POST /api/post-session/extract-background',
    'POST /api/post-session/combine-channels',
    'POST /api/post-session/master-accumulate',
    // Imaging / calibration host-compute helpers
    'GET /api/imaging/fits-dimensions',
    'POST /api/calibration/match-dark',
    'POST /api/calibration/defect-maps/build',
    'POST /api/calibration/defect-maps/apply',
    // Weather
    'GET /api/weather/radar',
    'GET /api/weather/forecast',
    'GET /api/weather/alerts',
    'GET /api/weather/cloud-cover',
    'GET /api/weather/settings',
    'POST /api/weather/settings',
    'GET /api/weather/safe-imaging',
    'GET /api/weather/current',
    'POST /api/weather/clear-cache',
    // Suggestions
    'GET /api/suggestions/tonight',
    'GET /api/suggestions/config',
    'GET /api/suggestions/score/<targetId>',
    // Transients
    'GET /api/transients',
    'GET /api/transients/settings',
    'POST /api/transients/settings',
    'GET /api/transients/queued',
    'POST /api/transients/<id>/queue',
    'POST /api/transients/<id>/dismiss',
    'POST /api/transients/refresh',
    // Backup
    'GET /api/backup/list',
    'POST /api/backup/create',
    'POST /api/backup/restore',
    'POST /api/backup/auto-save',
    'POST /api/backup/upload-restore',
    'GET /api/backup/<id>/metadata',
    'GET /api/backup/<id>/download',
    'DELETE /api/backup/<id>',
    // Framing
    'POST /api/framing/slew-to-target',
    'POST /api/framing/center-on-target',
    'POST /api/framing/sync',
    'GET /api/framing/current-position',
    'POST /api/framing/rotate-to',
    'POST /api/framing/abort-slew',
    'POST /api/framing/park',
    'POST /api/framing/unpark',
    'POST /api/framing/set-target',
    'POST /api/framing/save',
    // Planetarium (remote client support)
    'GET /api/planetarium/mount-position',
    'GET /api/planetarium/fov-config',
    'POST /api/planetarium/slew-to',
    'POST /api/planetarium/center-on',
    'POST /api/planetarium/sync-to',
    'GET /api/planetarium/catalog/search',
    'GET /api/planetarium/catalog/region',
    'GET /api/planetarium/catalog/object/<objectId>',
    'GET /api/planetarium/subscribe-info',
    'GET /api/planetarium/location',
    // Dome
    'POST /api/dome/open',
    'POST /api/dome/close',
    'POST /api/dome/slew',
    'POST /api/dome/sync',
    'POST /api/dome/park',
    'POST /api/dome/home',
    'POST /api/dome/halt',
    'GET /api/dome/status',
    'GET /api/dome/capabilities',
    // Night Narrator (read-only feed for remote clients)
    'GET /api/narrator/feed',
    'GET /api/narrator/recent',
    // Safety Monitor
    'GET /api/safety/status',
    'GET /api/safety/settings',
    'POST /api/safety/settings',
    'POST /api/safety/acknowledge',
    // Switch
    'GET /api/switch/status',
    'POST /api/switch/set',
    // Cover Calibrator
    'GET /api/cover/status',
    'POST /api/cover/open',
    'POST /api/cover/close',
    'POST /api/cover/brightness',
    'POST /api/cover/calibrator-on',
    'POST /api/cover/calibrator-off',
    // Intelligent Scheduler
    'GET /api/scheduler/altitude',
    'GET /api/scheduler/transit-time',
    'GET /api/scheduler/rise-set',
    'GET /api/scheduler/hours-above-horizon',
    'POST /api/scheduler/optimize-targets',
    'GET /api/scheduler/twilight-times',
    'GET /api/scheduler/moon-info',
    // Focus Model
    'GET /api/focus-model/data',
    'POST /api/focus-model/add-point',
    'DELETE /api/focus-model/clear',
    'GET /api/focus-model/model',
    'GET /api/focus-model/predict',
    'GET /api/focus-model/filter-offsets',
    'POST /api/focus-model/filter-offsets',
    'GET /api/focus-model/should-refocus',
    'GET /api/focus-model/export',
    'POST /api/focus-model/import',
    // Long-running operation jobs
    'GET /api/jobs',
    'GET /api/jobs/<jobId>',
    'POST /api/jobs/<jobId>/cancel',
    'DELETE /api/jobs/<jobId>',
    // Session ownership
    'GET /api/session/owner',
    'GET /api/session/status',
    'POST /api/session/claim',
    'POST /api/session/take-over',
    'POST /api/session/release',
    // System / OTA update endpoints
    'GET /api/system/version',
    'POST /api/system/update/check',
    'GET /api/system/update/status',
    'POST /api/system/update/download',
    'POST /api/system/update/apply',
    'POST /api/system/update/abort',
    'POST /api/system/update/rollback',
    'GET /api/system/update/staged',
    'DELETE /api/system/update/staged',
    // WebSocket
    'WS /api/ws',
    'WS /events',
    // Run-Watch (phone/tablet monitoring SPA)
    'GET /api/run-watch/snapshot',
    'GET /api/run-watch/frame-thumbnail',
    'GET /api/run-watch/events',
    // Remote log retrieval / tail
    'GET /api/logs',
    'GET /api/logs/recent',
    'GET /api/logs/files/<filename>/download',
    'GET /api/logs/tail',
    'POST /api/logs/clear',
    'POST /api/logs/test-entry',
    // Remote calibration library management
    'GET /api/calibration/darks',
    'POST /api/calibration/darks',
    'POST /api/calibration/darks/upload',
    'POST /api/calibration/darks/find-match',
    'POST /api/calibration/darks/backfill-sizes',
    'GET /api/calibration/darks/<id>',
    'GET /api/calibration/darks/<id>/download',
    'DELETE /api/calibration/darks/<id>',
    'GET /api/calibration/flats',
    'POST /api/calibration/flats',
    'GET /api/calibration/flats/recommendation',
    'GET /api/calibration/flats/<id>',
    'DELETE /api/calibration/flats/<id>',
    'GET /api/calibration/defect-maps',
    'POST /api/calibration/defect-maps',
    'GET /api/calibration/defect-maps/<id>',
    'DELETE /api/calibration/defect-maps/<id>',
    'POST /api/calibration/defect-maps/<id>/regenerate',
    // v46 — unified Calibration Library Manager (hyphenated prefix so it
    // does not collide with the per-table /api/calibration/ surface).
    'GET /api/calibration-library',
    'POST /api/calibration-library/match',
    'PUT /api/calibration-library/<type>/<id>/tags',
    'DELETE /api/calibration-library/<type>/<id>',
    // Mobile push token registry + per-device preferences
    'POST /api/push/register-token',
    'DELETE /api/push/token',
    'GET /api/push/preferences',
    'PUT /api/push/preferences',
    // Cloud sync
    'GET /api/sync/status',
    'POST /api/sync/push',
    // Catalog management (download / upload / verify / etc.)
    'GET /api/catalog/status',
    'GET /api/catalog/available',
    'POST /api/catalog/download',
    'POST /api/catalog/upload',
    'POST /api/catalog/verify',
    'POST /api/catalog/reload',
    'DELETE /api/catalog/<name>',

    // Read-only DB endpoints (paginated)
    'GET /api/sequence-runs',
    // session replay scrubber: per-run detail + paginated events
    // + paginated frames. Order in registration matters (specific paths
    // before catch-all) but the advertised set is unordered.
    'GET /api/sequence-runs/<runId>',
    'GET /api/sequence-runs/<runId>/events',
    'GET /api/sequence-runs/<runId>/frames',
    'GET /api/notes-journal',
    'GET /api/guide-rms-history',
    'GET /api/polar-alignment-history',
    'GET /api/db/dark-library',
    'GET /api/db/flat-history',

    // Plugin management
    'GET /api/plugins',
    'POST /api/plugins/upload',
    'POST /api/plugins/<pluginId>/enable',
    'POST /api/plugins/<pluginId>/disable',
    'DELETE /api/plugins/<pluginId>',
  ];
}

/// Read-only snapshot the system handlers pull off the live
/// [HeadlessApiServer]. Every field is a getter so we never cache stale
/// values (the event-seq cursor in particular advances on every
/// broadcast, so a snapshot taken at construction time would be useless
/// ten seconds later).
class SystemServerView {
  /// Hex-encoded server fingerprint. TLS pins to the SubjectPublicKeyInfo
  /// digest when TLS is active; plain-HTTP falls back to
  /// `computeServerFingerprint(adminToken)`.
  final String Function() fingerprint;

  /// UUID assigned at server-construction time. Mirrored onto every
  /// outbound event and returned by /api/info so clients detect a
  /// server restart by mismatch.
  final String Function() instanceId;

  /// Monotonically increasing event sequence counter; 0 before the
  /// first broadcast.
  final int Function() currentEventSeq;

  /// Configured capacity of the event ring buffer.
  final int Function() eventReplayBufferSize;

  /// Oldest seq retained in the ring buffer, or null when no events
  /// have been emitted yet.
  final int? Function() eventReplayBufferOldestSeq;

  /// Bound TCP port (post `start()` resolution).
  final int Function() port;

  /// Whether the bind address is loopback-only (`127.0.0.1`).
  final bool Function() bindLocalOnly;

  /// Whether the server has any configured auth tokens (admin +
  /// scoped). When false, `authMode='none'` and the dashboard banner
  /// warns the operator that anonymous LAN access is enabled.
  final bool Function() authRequired;

  /// Distinct scope names across every configured token. Returned
  /// alphabetised for stable comparison.
  final List<String> Function() availableAuthScopes;

  /// Active pairing-policy wire string (`lan-open` / `code-required`) so a
  /// client knows whether to one-tap claim on the LAN or prompt for a code.
  final String Function() pairingModeWire;

  /// The rig's Tailscale endpoint (MagicDNS `*.ts.net` or `100.x` literal) when
  /// a tailnet interface is present, else null. Lets a remote client learn the
  /// host instead of the operator reading it off the appliance log.
  final String? Function() tailscaleHost;

  /// The self-hosted-relay appliance id when a relay uplink is active, else
  /// null. Same purpose as [tailscaleHost] for the relay path.
  final String? Function() relayApplianceId;

  const SystemServerView({
    required this.fingerprint,
    required this.instanceId,
    required this.currentEventSeq,
    required this.eventReplayBufferSize,
    required this.eventReplayBufferOldestSeq,
    required this.port,
    required this.bindLocalOnly,
    required this.authRequired,
    required this.availableAuthScopes,
    required this.pairingModeWire,
    required this.tailscaleHost,
    required this.relayApplianceId,
  });
}

/// HTTP handlers for the four system-info endpoints. Constructed once
/// per server with the [SystemServerView] snapshot and the
/// [StaticFileHandlers] reference (for the dashboard-available flag).
class SystemHandlers {
  final ProviderContainer container;
  final SystemServerView view;
  final StaticFileHandlers staticFileHandlers;
  final LoggingService logger;

  SystemHandlers({
    required this.container,
    required this.view,
    required this.staticFileHandlers,
    required this.logger,
  });

  void _logInfo(String message) =>
      logger.info(message, source: 'SystemHandlers');
  void _logError(String message) =>
      logger.error(message, source: 'SystemHandlers');

  /// `GET /api/system/version` — build metadata, ALWAYS available.
  ///
  /// Sourced from [appVersionProvider] (populated at startup), so it works even
  /// on a headless instance with no OTA [UpdateController] wired. The richer
  /// update-aware version handler lives in the optional update-routes group,
  /// which is skipped (→ 404) when updates aren't provisioned; this base
  /// endpoint guarantees a client can always read the running build.
  Future<Response> handleVersion(Request request) async {
    final versionInfo = container.read(appVersionProvider);
    return jsonOk({
      'currentVersion': versionInfo.version,
      'buildNumber': versionInfo.buildNumber,
      'platform': Platform.operatingSystem,
    });
  }

  /// `GET /api/info` — server discovery envelope. Returns the build
  /// version, API-version envelope, fingerprint, paired/scoped auth
  /// metadata, the replay-buffer cursor, and the full endpoint
  /// catalog so a remote client can render its capabilities map
  /// without polling individual probes.
  Future<Response> handleInfo(Request request) async {
    final platformCapabilities = PlatformCapabilityMatrix.forPlatform(
      Platform.operatingSystem,
    );
    final versionInfo = container.read(appVersionProvider);
    final dashboardAvailable = staticFileHandlers.dashboardAvailable;

    return jsonOk({
      'name': 'Nightshade Headless',
      'version': versionInfo.version,
      'apiVersion': RemoteApiCompatibility.serverApiVersion.format(),
      'minimumSupportedApiVersion': RemoteApiCompatibility
          .minimumSupportedVersion
          .format(),
      'apiVersionHeader': RemoteApiCompatibility.apiVersionHeader,
      'mode': 'headless',
      'platform': platformCapabilities.platform,
      'platformCapabilities': platformCapabilities.toJson(),
      'authRequired': view.authRequired(),
      'authenticationMode': view.authRequired() ? 'token' : 'none',
      'authScopes': view.availableAuthScopes(),
      'pairingSupported': true,
      // Pairing policy so the client knows whether to one-tap LAN-claim or
      // prompt for a code. `lanPairing` is the convenience boolean.
      'pairingMode': view.pairingModeWire(),
      'lanPairing': view.pairingModeWire() == 'lan-open',
      // Remote-access identifiers surfaced so the client never has to read them
      // off the appliance's terminal. Null/omitted when not applicable.
      if (view.tailscaleHost() != null) 'tailscaleHost': view.tailscaleHost(),
      if (view.relayApplianceId() != null)
        'relayApplianceId': view.relayApplianceId(),
      'fingerprint': view.fingerprint(),
      // surface the sequencing + replay state so a reconnecting
      // client can decide between `?since=` replay and a full
      // `/api/run-watch/snapshot` rehydrate without guessing.
      'serverInstanceId': view.instanceId(),
      'currentEventSeq': view.currentEventSeq(),
      'eventReplayBufferSize': view.eventReplayBufferSize(),
      'eventReplayBufferOldestSeq': view.eventReplayBufferOldestSeq(),
      'apiOnlyMode': true,
      'webUIAvailable': dashboardAvailable,
      'publicEndpoints': [
        '/api/info',
        '/api/pairing/start',
        '/api/pairing/verify',
        '/api/pairing/lan-claim',
        '/dashboard',
        // the run-watch SPA bundle is auth-exempt so the
        // phone can load it before pairing. The /api/run-watch/*
        // endpoints themselves still require a Bearer token.
        '/run-watch',
        // browser pairing page: a no-app, no-SSH way to pair from any
        // LAN browser. Auth-exempt like /api/info; the page calls the
        // already-public pairing endpoints client-side.
        '/pair',
      ],
      'endpoints': availableHeadlessEndpoints(),
    }, headers: _apiCompatibilityHeaders());
  }

  /// `GET /pair` — a self-contained browser pairing page.
  ///
  /// Lets an operator pair from ANY browser on the LAN without the mobile
  /// app and without reading the appliance terminal. The page is pure
  /// vanilla JS (no build pipeline, kept inline like `/broadcast`) and does
  /// all its work client-side against the already-public pairing endpoints:
  ///
  ///   * Fetches `GET /api/info` (same origin) to show the rig name and the
  ///     active pairing mode (lan-open vs code-required).
  ///   * In **lan-open** mode a "Pair this browser" button POSTs
  ///     `/api/pairing/lan-claim`; on success it shows "Paired ✓" and the
  ///     minted token so an advanced user can copy it.
  ///   * In **code-required** mode it POSTs `/api/pairing/start` (which only
  ///     returns the expiry — the code itself is deliberately never sent over
  ///     HTTP, see PairingHandlers) and instructs the operator to read the
  ///     6-digit code from the appliance log / stdout, then enter it; the
  ///     page then POSTs `/api/pairing/verify` to complete pairing.
  ///
  /// Security note: this page never surfaces the pairing code itself. The
  /// code is the out-of-band trust factor and is intentionally kept to the
  /// operator-visible log only; printing it on a same-LAN HTTP page would
  /// defeat the code flow (any LAN device could read it). The expiry
  /// envelope from `/api/pairing/start` is safe to show.
  Future<Response> handlePairPage(Request request) async {
    return contentResponse(
      _pairPageHtml,
      contentType: 'text/html; charset=utf-8',
      headers: {
        'cache-control': 'no-cache, no-store, must-revalidate',
        // Same-origin only; the page uses inline <style>/<script> and fetches
        // its own /api/* endpoints, nothing external.
        'content-security-policy':
            "default-src 'self'; img-src 'self'; "
            "style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
            "connect-src 'self'",
      },
    );
  }

  /// `GET /api/status` — sequencer state snapshot. Mobile clients poll
  /// this every second or so to render the run badge; keep the
  /// envelope small to keep the poll loop cheap.
  Future<Response> handleStatus(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/status');
    try {
      final backend = container.read(sequencerBackendProvider);
      final status = await backend.sequencerGetStatus();
      return jsonOk({
        "sequencer": {
          "state": status.state,
          "currentNodeId": status.currentNodeId,
          "currentNodeName": status.currentNodeName,
          "progress": status.progress,
          "message": status.message,
        },
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Status error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
    }
  }

  /// `GET /api/self-test` — release-quality probe. Walks the storage
  /// directories (write-then-delete a probe file), confirms the Drift
  /// database provider is initialised, fires a 2s-timeout
  /// connected-device probe at the backend, and returns the aggregate
  /// in a single envelope.
  Future<Response> handleSelfTest(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/self-test');
    try {
      final platformCapabilities = PlatformCapabilityMatrix.forPlatform(
        Platform.operatingSystem,
      );
      // A-12: self-test needs `backend.runtimeType` to report which backend
      // implementation is active (FfiBackend / NetworkBackend / Disconnected).
      // Role providers all return the same instance widened to a role
      // interface, so the concrete-type query stays on backendProvider.
      final backend = container.read(backendProvider);
      final storageChecks = await _runStorageSelfTests();
      final databaseCheck = _runDatabaseSelfTest();
      final connectedDeviceProbe = await _probeConnectedDevices(backend);
      final endpointCount = availableHeadlessEndpoints().length;

      final checks = [
        ...storageChecks.map((check) => check['status']),
        databaseCheck['status'],
        connectedDeviceProbe['status'],
      ];
      final hasFailures = checks.contains('error');

      return jsonOk({
        'status': hasFailures ? 'degraded' : 'ok',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': {
          'operatingSystem': platformCapabilities.platform,
          'operatingSystemVersion': Platform.operatingSystemVersion,
          'executable': Platform.resolvedExecutable,
        },
        'server': {
          'port': view.port(),
          'bindMode': view.bindLocalOnly() ? 'loopback' : 'lan',
          'authMode': view.authRequired() ? 'token' : 'none',
          'authRequired': view.authRequired(),
          'authScopes': view.availableAuthScopes(),
          'dashboardAvailable': staticFileHandlers.dashboardAvailable,
        },
        'backend': {
          'type': backend.runtimeType.toString(),
          'connectedDevices': connectedDeviceProbe,
        },
        'deviceDrivers': platformCapabilities.toJson(),
        'storagePaths': storageChecks,
        'database': databaseCheck,
        'api': {
          'endpointCount': endpointCount,
          'selfTestEndpoint': 'GET /api/self-test',
        },
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Self-test error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  /// `GET /api/openapi.json` — OpenAPI 3 spec generated from the
  /// canonical endpoint list. Consumers (the audit, the dashboard
  /// route-table validator, external client generators) all read this
  /// rather than re-deriving the list from the source.
  Future<Response> handleOpenApiSpec(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/openapi.json');
    try {
      return jsonOk(
        route_metadata.buildOpenApiSpec(
          routes: availableHeadlessEndpoints(),
          port: view.port(),
        ),
      );
    } catch (e, stackTrace) {
      _logError('[API][$requestId] OpenAPI generation error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  Map<String, String> _apiCompatibilityHeaders() {
    return {
      RemoteApiCompatibility.apiVersionHeader: RemoteApiCompatibility
          .serverApiVersion
          .format(),
      'x-nightshade-minimum-api-version': RemoteApiCompatibility
          .minimumSupportedVersion
          .format(),
    };
  }

  Map<String, dynamic> _runDatabaseSelfTest() {
    try {
      container.read(databaseProvider);
      return {
        'name': 'driftDatabase',
        'status': 'ok',
        'message': 'Database provider is initialized.',
      };
    } catch (e) {
      return {
        'name': 'driftDatabase',
        'status': 'error',
        // Sanitized: the failing check is identified by name+status; the raw
        // exception is not surfaced on the health endpoint.
        'message': 'Database provider check failed.',
      };
    }
  }

  Future<Map<String, dynamic>> _probeConnectedDevices(
    NightshadeBackend backend,
  ) async {
    try {
      final devices = await backend.getConnectedDevices().timeout(
        const Duration(seconds: 2),
      );
      return {
        'status': 'ok',
        'count': devices.length,
        'devices': devices.map((device) => device.toJson()).toList(),
      };
    } catch (e) {
      return {
        'status': 'warning',
        'count': null,
        'devices': <Map<String, dynamic>>[],
        'message': 'Connected-device probe unavailable: $e',
      };
    }
  }

  Future<List<Map<String, dynamic>>> _runStorageSelfTests() async {
    final checks = <Map<String, dynamic>>[];

    Future<void> addDirectoryCheck(
      String name,
      Future<Directory> Function() resolver,
    ) async {
      try {
        final directory = await resolver();
        checks.add(await _checkWritableDirectory(name, directory));
      } catch (e) {
        checks.add({
          'name': name,
          'status': 'error',
          'path': null,
          'exists': false,
          'writable': false,
          // Sanitized: the check is identified by name+status; the raw
          // exception is not surfaced on the health endpoint.
          'message': 'Directory check failed.',
        });
      }
    }

    await addDirectoryCheck(
      'applicationDocuments',
      getApplicationDocumentsDirectory,
    );
    await addDirectoryCheck(
      'applicationSupport',
      getApplicationSupportDirectory,
    );
    await addDirectoryCheck('systemTemp', () async => Directory.systemTemp);

    return checks;
  }

  Future<Map<String, dynamic>> _checkWritableDirectory(
    String name,
    Directory directory,
  ) async {
    final exists = await directory.exists();
    if (!exists) {
      return {
        'name': name,
        'status': 'error',
        'path': directory.path,
        'exists': false,
        'writable': false,
        'message': 'Directory does not exist.',
      };
    }

    final probeFile = File(
      p.join(
        directory.path,
        '.nightshade-self-test-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await probeFile.writeAsString('ok');
      await probeFile.delete();
      return {
        'name': name,
        'status': 'ok',
        'path': directory.path,
        'exists': true,
        'writable': true,
      };
    } catch (e) {
      // Best-effort cleanup of a half-written probe file. We capture
      // the cleanup error (rather than silently swallowing it) because
      // a probe that leaves debris is itself a defect worth surfacing
      // — the operator's storage-write self-test should not lie about
      // a clean teardown.
      String? cleanupNote;
      try {
        if (await probeFile.exists()) {
          await probeFile.delete();
        }
      } catch (cleanupErr) {
        cleanupNote =
            ' (cleanup of probe file failed: $cleanupErr — manual removal may '
            'be required at ${probeFile.path})';
      }
      return {
        'name': name,
        'status': 'error',
        'path': directory.path,
        'exists': true,
        'writable': false,
        // Sanitized: report the writability failure without leaking the raw
        // exception; the optional cleanup note (a path hint) is retained.
        'message': 'Directory is not writable.${cleanupNote ?? ''}',
      };
    }
  }
}

/// Inline HTML for `GET /pair` (see [SystemHandlers.handlePairPage]).
///
/// A raw Dart string so the embedded JavaScript can use `$`, `${}`, and
/// backslashes without Dart interpolation getting in the way. The page is
/// fully self-contained: no external CSS/JS/images, no build pipeline.
const String _pairPageHtml = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pair with Nightshade</title>
<style>
  :root {
    color-scheme: dark;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    --color-background: #0A0C0F;
    --color-surface: #111418;
    --color-surface-alt: #181C22;
    --color-border: #2E353F;
    --color-text-primary: #E8EAED;
    --color-text-muted: #6B7380;
    --color-accent: #4C8DFF;
    --color-success: #3DAA6D;
    --color-warning: #D49A3A;
    --color-error: #D85C5C;
    --tint-warning: rgba(212, 154, 58, 0.2);
    --tint-success: rgba(61, 170, 109, 0.18);
  }
  body {
    background: var(--color-background);
    color: var(--color-text-primary);
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    box-sizing: border-box;
  }
  .card {
    width: 100%;
    max-width: 460px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 10px;
    padding: 24px;
  }
  h1 { font-size: 1.25rem; margin: 0 0 4px; }
  .rig { color: var(--color-text-muted); margin: 0 0 20px; font-size: 0.95rem; }
  .mode {
    display: inline-block;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 3px 8px;
    border-radius: 4px;
    border: 1px solid var(--color-border);
    color: var(--color-text-muted);
    margin-bottom: 16px;
  }
  p { line-height: 1.5; }
  button {
    width: 100%;
    background: var(--color-accent);
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 12px 16px;
    font-size: 1rem;
    font-weight: 600;
    cursor: pointer;
    margin-top: 8px;
  }
  button:disabled { opacity: 0.5; cursor: default; }
  input[type=text] {
    width: 100%;
    box-sizing: border-box;
    background: var(--color-surface-alt);
    color: var(--color-text-primary);
    border: 1px solid var(--color-border);
    border-radius: 8px;
    padding: 12px;
    font-size: 1.4rem;
    letter-spacing: 0.3em;
    text-align: center;
    margin-top: 12px;
  }
  .banner {
    border-radius: 8px;
    padding: 12px 14px;
    font-size: 0.9rem;
    margin-top: 16px;
    border: 1px solid var(--color-border);
  }
  .banner.ok { background: var(--tint-success); border-color: var(--color-success); }
  .banner.warn { background: var(--tint-warning); border-color: var(--color-warning); }
  .banner.err { background: rgba(216,92,92,0.18); border-color: var(--color-error); }
  code {
    background: var(--color-surface-alt);
    padding: 1px 6px;
    border-radius: 3px;
    word-break: break-all;
  }
  .token {
    display: block;
    margin-top: 8px;
    font-size: 0.8rem;
    user-select: all;
  }
  .muted { color: var(--color-text-muted); font-size: 0.85rem; }
  .hidden { display: none; }
</style>
</head>
<body>
  <div class="card">
    <h1>Pair with Nightshade</h1>
    <p class="rig" id="rig-name">Connecting to this appliance…</p>
    <span class="mode" id="mode-badge">checking…</span>

    <!-- lan-open flow -->
    <div id="lan-open" class="hidden">
      <p>This appliance allows one-tap pairing from the local network. Click
        below to pair this browser.</p>
      <button id="lan-claim-btn" type="button">Pair this browser</button>
    </div>

    <!-- code-required flow -->
    <div id="code-required" class="hidden">
      <p>This appliance requires a pairing code. Click below to start pairing,
        then read the 6-digit code from the appliance's log
        (<code>journalctl -fu nightshade-headless</code>) and enter it here.</p>
      <button id="start-btn" type="button">Start pairing</button>
      <div id="code-entry" class="hidden">
        <input id="code-input" type="text" inputmode="numeric"
               autocomplete="one-time-code" maxlength="12"
               placeholder="000000">
        <p class="muted" id="expiry-note"></p>
        <button id="verify-btn" type="button">Complete pairing</button>
      </div>
    </div>

    <div id="result" class="banner hidden"></div>
  </div>

  <script>
    var modeBadge = document.getElementById('mode-badge');
    var rigName = document.getElementById('rig-name');
    var lanOpenEl = document.getElementById('lan-open');
    var codeReqEl = document.getElementById('code-required');
    var resultEl = document.getElementById('result');

    function show(el) { el.classList.remove('hidden'); }
    function hide(el) { el.classList.add('hidden'); }

    function showResult(kind, html) {
      resultEl.className = 'banner ' + kind;
      resultEl.innerHTML = html;
      show(resultEl);
    }

    function escapeHtml(s) {
      return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
    }

    function showPaired(token) {
      var html = 'Paired ✓';
      if (token) {
        html += '<code class="token">' + escapeHtml(token) + '</code>'
             + '<span class="muted">Advanced: copy this token to use the API '
             + 'directly.</span>';
      }
      showResult('ok', html);
    }

    // Discover this rig: name + pairing mode.
    fetch('/api/info', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (info) {
        rigName.textContent = (info.name || 'Nightshade')
          + ' · v' + (info.version || '?');
        var mode = info.pairingMode || (info.lanPairing ? 'lan-open' : 'code-required');
        modeBadge.textContent = mode;
        if (mode === 'lan-open') {
          show(lanOpenEl);
        } else {
          show(codeReqEl);
        }
      })
      .catch(function () {
        rigName.textContent = 'Could not reach this appliance.';
        showResult('err', 'Failed to contact <code>/api/info</code>. '
          + 'Reload the page and try again.');
      });

    // lan-open: one-tap claim.
    var lanBtn = document.getElementById('lan-claim-btn');
    lanBtn.addEventListener('click', function () {
      lanBtn.disabled = true;
      lanBtn.textContent = 'Pairing…';
      fetch('/api/pairing/lan-claim', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ deviceName: 'Browser', deviceType: 'browser' })
      })
        .then(function (r) { return r.json().then(function (b) { return { ok: r.ok, body: b }; }); })
        .then(function (res) {
          if (res.ok && res.body && res.body.token) {
            showPaired(res.body.token);
            lanBtn.textContent = 'Paired ✓';
          } else {
            lanBtn.disabled = false;
            lanBtn.textContent = 'Pair this browser';
            var msg = (res.body && res.body.message) || 'Pairing was refused.';
            showResult('err', escapeHtml(msg));
          }
        })
        .catch(function () {
          lanBtn.disabled = false;
          lanBtn.textContent = 'Pair this browser';
          showResult('err', 'Network error while pairing. Try again.');
        });
    });

    // code-required: start, then verify the operator-entered code.
    var startBtn = document.getElementById('start-btn');
    var codeEntry = document.getElementById('code-entry');
    var verifyBtn = document.getElementById('verify-btn');
    var codeInput = document.getElementById('code-input');
    var expiryNote = document.getElementById('expiry-note');

    startBtn.addEventListener('click', function () {
      startBtn.disabled = true;
      startBtn.textContent = 'Starting…';
      fetch('/api/pairing/start', { method: 'POST' })
        .then(function (r) { return r.json().then(function (b) { return { ok: r.ok, body: b }; }); })
        .then(function (res) {
          if (res.ok) {
            show(codeEntry);
            startBtn.textContent = 'Restart pairing';
            startBtn.disabled = false;
            var secs = res.body && res.body.expiresInSeconds;
            expiryNote.textContent = secs
              ? ('Code is valid for about ' + Math.round(secs / 60)
                 + ' minute(s). Read it from the appliance log.')
              : 'Read the code from the appliance log.';
            showResult('warn', 'Pairing started. The 6-digit code was printed '
              + 'to the appliance log — it is deliberately not sent over '
              + 'the network. Enter it below.');
          } else {
            startBtn.disabled = false;
            startBtn.textContent = 'Start pairing';
            var msg = (res.body && res.body.error) || 'Could not start pairing.';
            showResult('err', escapeHtml(msg));
          }
        })
        .catch(function () {
          startBtn.disabled = false;
          startBtn.textContent = 'Start pairing';
          showResult('err', 'Network error while starting pairing.');
        });
    });

    verifyBtn.addEventListener('click', function () {
      var code = (codeInput.value || '').trim();
      if (!code) { showResult('err', 'Enter the code first.'); return; }
      verifyBtn.disabled = true;
      verifyBtn.textContent = 'Verifying…';
      fetch('/api/pairing/verify', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ code: code, deviceName: 'Browser', deviceType: 'browser' })
      })
        .then(function (r) { return r.json().then(function (b) { return { ok: r.ok, body: b }; }); })
        .then(function (res) {
          verifyBtn.disabled = false;
          verifyBtn.textContent = 'Complete pairing';
          if (res.ok && res.body && res.body.token) {
            hide(codeEntry);
            showPaired(res.body.token);
          } else {
            var msg = (res.body && res.body.message) || 'The code was not accepted.';
            showResult('err', escapeHtml(msg));
          }
        })
        .catch(function () {
          verifyBtn.disabled = false;
          verifyBtn.textContent = 'Complete pairing';
          showResult('err', 'Network error while verifying the code.');
        });
    });
  </script>
</body>
</html>
''';
