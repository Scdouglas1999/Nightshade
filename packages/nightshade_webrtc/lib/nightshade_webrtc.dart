/// Nightshade WebRTC - P2P communication for remote control
library nightshade_webrtc;

// Legacy exports (for backward compatibility)
export 'src/peer_connection.dart';
export 'src/signaling.dart';
export 'src/discovery.dart';
export 'src/enhanced_discovery.dart';
export 'src/server_compatibility.dart';
export 'src/web_server.dart';
export 'src/collaboration/live_collaboration_session.dart';

// Secure authentication and encryption
export 'src/auth/token_manager.dart';
export 'src/crypto/channel_encryption.dart';

// Secure signaling and discovery
export 'src/signaling/secure_signaling_server.dart';
export 'src/discovery/secure_discovery.dart';

// Database
export 'src/database/paired_devices_table.dart';
export 'src/database/pairing_database.dart';
