/// Nightshade WebRTC - LAN discovery, pairing, and remote-control protocol shims.
library nightshade_webrtc;

// Why the package is still called nightshade_webrtc: legacy name kept for v2.5.0
// to avoid churning every downstream pubspec. The package no longer ships WebRTC
// peer-connection or signaling primitives (deleted in §2.3 audit 2026-05-09);
// live remote control runs over REST + WebSocket via headless_api_server.dart.
//
// web_server.dart was deleted in §2.2 (audit 2026-05-09) — the consolidated
// HTTP/REST server now lives at apps/desktop/lib/headless_api_server.dart and
// is shared by both GUI and headless modes.
export 'src/discovery.dart';
export 'src/enhanced_discovery.dart';
export 'src/server_compatibility.dart';
export 'src/collaboration/live_collaboration_session.dart';

// Secure authentication and encryption
export 'src/auth/token_manager.dart';
export 'src/crypto/channel_encryption.dart';

// Secure pairing-mode discovery (used by W1.5 pairing flow)
export 'src/discovery/secure_discovery.dart';

// Database
export 'src/database/paired_devices_table.dart';
export 'src/database/pairing_database.dart';
