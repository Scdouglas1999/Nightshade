/// Nightshade remote-control protocol — LAN discovery, pairing, token
/// management, and channel encryption used by the headless API server and
/// the mobile companion.
library;

// Why the rename: this package was originally named nightshade_webrtc, but the
// WebRTC peer-connection + signaling primitives were removed in §2.3 audit
// 2026-05-09. Live remote control now runs over REST + WebSocket via
// headless_api_server.dart. Renamed to nightshade_remote_protocol in
// AUDIT-FIX-5A (audit-handoff §4.2) so the name reflects what the package
// actually contains: discovery, auth, crypto, and pairing primitives.
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
