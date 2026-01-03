import 'package:drift/drift.dart';

/// Table for storing paired devices with their authentication tokens
class PairedDevices extends Table {
  /// Unique device identifier (UUID)
  TextColumn get deviceId => text()();

  /// Device name provided during pairing (e.g., "John's iPhone")
  TextColumn get deviceName => text()();

  /// Secure session token (32 bytes, hex-encoded)
  TextColumn get sessionToken => text()();

  /// Timestamp when this device was paired
  DateTimeColumn get pairedAt => dateTime()();

  /// Last time this device connected successfully
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();

  /// Device type (e.g., "mobile", "tablet", "desktop")
  TextColumn get deviceType => text().withDefault(const Constant('mobile'))();

  /// Whether this device is currently active (not revoked)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// Table for tracking active pairing sessions
class PairingSessions extends Table {
  /// Unique session identifier
  IntColumn get id => integer().autoIncrement()();

  /// User-friendly pairing code (e.g., "STAR-1234")
  TextColumn get pairingCode => text().unique()();

  /// Full session token that will be assigned when pairing completes
  TextColumn get sessionToken => text()();

  /// Timestamp when this pairing session was created
  DateTimeColumn get createdAt => dateTime()();

  /// Timestamp when this pairing session expires (typically createdAt + 5 minutes)
  DateTimeColumn get expiresAt => dateTime()();

  /// Whether this pairing session has been used
  BoolColumn get isUsed => boolean().withDefault(const Constant(false))();
}
