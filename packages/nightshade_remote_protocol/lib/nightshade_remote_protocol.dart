/// Nightshade remote-control protocol — LAN discovery, pairing, token
/// management, and channel encryption used by the headless API server and
/// the mobile companion.
library;

// Why the rename: this package was originally named nightshade_webrtc, but the
// WebRTC peer-connection + signaling primitives were removed in §2.3 audit
// 2026-05-09. Live remote control now runs over REST + WebSocket via
// headless_api_server.dart. Renamed to nightshade_remote_protocol in
// so the name reflects what the package
// actually contains: discovery, auth, crypto, and pairing primitives.
//
// web_server.dart was deleted on 2026-05-09 — the consolidated
// HTTP/REST server now lives at apps/desktop/lib/headless_api_server.dart and
// is shared by both GUI and headless modes.
export 'src/discovery.dart';
export 'src/enhanced_discovery.dart';
export 'src/tailnet_detector.dart';
export 'src/server_compatibility.dart';
export 'src/server_identity.dart';
export 'src/remote_pairing_client.dart';
export 'src/collaboration/live_collaboration_session.dart';

// Secure authentication and encryption
export 'src/auth/token_manager.dart';
export 'src/crypto/channel_encryption.dart';

// Secure pairing-mode discovery (used by the pairing flow)
export 'src/discovery/secure_discovery.dart';

// Server-side mDNS / Bonjour / DNS-SD advertisement.
export 'src/discovery/mdns_registration.dart';

// Database
export 'src/database/device_push_tables.dart';
export 'src/database/paired_devices_table.dart';
export 'src/database/pairing_database.dart';

// LAN UDP push fan-out + FCM/APNs scaffolding. The broadcaster
// runs on the desktop next to the WebSocket fan-out so paired phones
// receive critical alerts even when their WS has dropped. See header
// of lan_push_broadcaster.dart for the wire format + threat model.
export 'src/push/lan_push_broadcaster.dart';
export 'src/push/push_config.dart';
export 'src/push/push_jwt.dart';
export 'src/push/push_token_store.dart';
export 'src/push/remote_push_delivery.dart';

// v4 couch-grade remote — self-hostable relay tunnel (tools/nightshade_relay).
// Re-exported so the desktop headless bootstrap (RelayUplink) and the mobile
// transport (RelayTunnelClient) consume the relay client classes through this
// package, keeping the wire protocol in one place. The RelayServer itself is
// only used by the standalone CLI/Docker image and is intentionally NOT
// re-surfaced here.
export 'package:nightshade_relay/nightshade_relay.dart'
    show
        RelayUplink,
        RelayUplinkState,
        RelayUplinkStatus,
        RelayTunnelClient,
        RelayTunnelException,
        RelayCredentials,
        RelayCredentialsStore,
        FileRelayCredentialsStore,
        MemoryRelayCredentialsStore,
        isValidApplianceId;
