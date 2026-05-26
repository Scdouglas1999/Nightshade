import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'paired_devices_table.dart';

part 'pairing_database.g.dart';

/// Database for managing paired devices and pairing sessions
@DriftDatabase(tables: [PairedDevices, PairingSessions])
class PairingDatabase extends _$PairingDatabase {
  PairingDatabase() : super(_openConnection());

  /// For testing with a custom QueryExecutor
  PairingDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // v1 -> v2 (P0-10): add expires_at column to paired_devices. Existing
        // rows are migrated with NULL (treated as "no expiry" for backward
        // compatibility); new pairings will populate the column going forward.
        if (from < 2) {
          await m.addColumn(pairedDevices, pairedDevices.expiresAt);
        }
      },
      beforeOpen: (details) async {
        // Enable foreign key enforcement
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ============================================================================
  // Paired Devices Operations
  // ============================================================================

  /// Get all active paired devices
  Future<List<PairedDevice>> getActivePairedDevices() async {
    return (select(pairedDevices)..where((tbl) => tbl.isActive.equals(true)))
        .get();
  }

  /// Get a specific paired device by device ID
  Future<PairedDevice?> getPairedDevice(String deviceId) async {
    return (select(pairedDevices)
          ..where((tbl) => tbl.deviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  /// Add a new paired device
  ///
  /// [expiresAt] is the absolute moment after which the issued session token
  /// MUST be rejected by `TokenManager.verifySessionToken` and by the headless
  /// auth middleware. May be `null` only for callers that explicitly opt out
  /// (test fixtures); the production pairing flow always populates it.
  Future<void> addPairedDevice({
    required String deviceId,
    required String deviceName,
    required String sessionToken,
    required String deviceType,
    DateTime? expiresAt,
  }) async {
    await into(pairedDevices).insert(
      PairedDevicesCompanion.insert(
        deviceId: deviceId,
        deviceName: deviceName,
        sessionToken: sessionToken,
        pairedAt: DateTime.now(),
        deviceType: Value(deviceType),
        expiresAt: Value(expiresAt),
      ),
    );
  }

  /// Update the last connected timestamp for a device
  Future<void> updateLastConnected(String deviceId) async {
    await (update(pairedDevices)
          ..where((tbl) => tbl.deviceId.equals(deviceId)))
        .write(
      PairedDevicesCompanion(
        lastConnectedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Revoke a paired device (mark as inactive)
  Future<void> revokeDevice(String deviceId) async {
    await (update(pairedDevices)
          ..where((tbl) => tbl.deviceId.equals(deviceId)))
        .write(
      const PairedDevicesCompanion(
        isActive: Value(false),
      ),
    );
  }

  /// Delete a paired device completely
  Future<void> deletePairedDevice(String deviceId) async {
    await (delete(pairedDevices)
          ..where((tbl) => tbl.deviceId.equals(deviceId)))
        .go();
  }

  // ============================================================================
  // Pairing Sessions Operations
  // ============================================================================

  /// Create a new pairing session
  Future<int> createPairingSession({
    required String pairingCode,
    required String sessionToken,
    required Duration expiresIn,
  }) async {
    final now = DateTime.now();
    return await into(pairingSessions).insert(
      PairingSessionsCompanion.insert(
        pairingCode: pairingCode,
        sessionToken: sessionToken,
        createdAt: now,
        expiresAt: now.add(expiresIn),
      ),
    );
  }

  /// Get a pairing session by code
  Future<PairingSession?> getPairingSession(String pairingCode) async {
    return (select(pairingSessions)
          ..where((tbl) => tbl.pairingCode.equals(pairingCode)))
        .getSingleOrNull();
  }

  /// Mark a pairing session as used
  Future<void> markPairingSessionUsed(String pairingCode) async {
    await (update(pairingSessions)
          ..where((tbl) => tbl.pairingCode.equals(pairingCode)))
        .write(
      const PairingSessionsCompanion(
        isUsed: Value(true),
      ),
    );
  }

  /// Delete expired pairing sessions (cleanup)
  Future<void> deleteExpiredPairingSessions() async {
    final now = DateTime.now();
    await (delete(pairingSessions)
          ..where((tbl) => tbl.expiresAt.isSmallerThanValue(now)))
        .go();
  }

  /// Delete all used pairing sessions
  Future<void> deleteUsedPairingSessions() async {
    await (delete(pairingSessions)..where((tbl) => tbl.isUsed.equals(true)))
        .go();
  }

  /// Find all paired-device rows whose session token has either expired
  /// (`expires_at <= now`) or been revoked (`is_active = false`).
  ///
  /// Used by the headless server's periodic sweep to:
  ///  - evict revoked tokens from the in-memory `_pairedSessionTokens` map
  ///    so revocation propagates without a server restart, and
  ///  - delete genuinely expired rows from the DB (revoked rows are retained
  ///    for audit purposes).
  Future<List<PairedDevice>> getExpiredOrRevokedDevices(DateTime now) async {
    final query = select(pairedDevices)
      ..where(
        (tbl) =>
            tbl.isActive.equals(false) |
            (tbl.expiresAt.isNotNull() &
                tbl.expiresAt.isSmallerOrEqualValue(now)),
      );
    return query.get();
  }

  /// Hard-delete a paired-device row whose session token has expired.
  ///
  /// Revoked-but-unexpired rows are kept by [getExpiredOrRevokedDevices]
  /// callers (the headless sweep uses [deletePairedDevice] on the revoked
  /// half only when explicitly requested).
  Future<void> deleteExpiredPairedDevices(DateTime now) async {
    await (delete(pairedDevices)
          ..where((tbl) =>
              tbl.expiresAt.isNotNull() &
              tbl.expiresAt.isSmallerOrEqualValue(now)))
        .go();
  }

  /// Active (`is_active = true`) AND not yet expired (`expires_at IS NULL OR
  /// expires_at > now`). This is the canonical "tokens the auth middleware
  /// should accept" snapshot, used to hydrate the in-memory token map at
  /// server startup.
  Future<List<PairedDevice>> getActiveUnexpiredPairedDevices(
      DateTime now) async {
    final query = select(pairedDevices)
      ..where(
        (tbl) =>
            tbl.isActive.equals(true) &
            (tbl.expiresAt.isNull() | tbl.expiresAt.isBiggerThanValue(now)),
      );
    return query.get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'Nightshade', 'pairing.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase.createInBackground(file);
  });
}
