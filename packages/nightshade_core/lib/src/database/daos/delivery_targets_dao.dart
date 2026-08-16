import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/darkroom/delivery.dart';
import '../../providers/database_provider.dart';
import '../database.dart';

/// A destination row was addressed by an id that has no row.
class ArtifactDestinationMissingException implements Exception {
  final int destinationId;

  const ArtifactDestinationMissingException(this.destinationId);

  @override
  String toString() => 'Delivery target $destinationId does not exist';
}

/// Data-access object for the v58 `delivery_targets` table — the configured
/// places the night's artifacts are delivered to.
///
/// The table is managed with raw DDL (see
/// [NightshadeDatabase._createDarkroomTables]) rather than a drift `Table`
/// class, so this DAO is a plain class that reads/writes through the database's
/// `customSelect`/`customInsert`/`customStatement` APIs — mirroring
/// [MosaicProjectsDao] and [CampaignsDao]. It is deliberately NOT a
/// `@DriftAccessor`.
///
/// NO SECRETS IN `config_json`. Every write runs [assertNoSecretsInConfig],
/// which throws [DeliveryConfigSecretException] when the config carries key
/// material anywhere in its object graph. That column is plaintext in the
/// profile database, which rides export and backup; an SFTP password written
/// there would leave the machine with the backup. Key material belongs in
/// `SecretsStore` (`services/notification/secrets_store.dart`), the
/// keyring-backed store that already holds the WebDAV password, the S3 secret
/// key, and the TNS API key. [ArtifactDestination.secretRef] names the keyring
/// entry; reading it belongs to the delivery service, in a later workstream.
class DeliveryTargetsDao {
  DeliveryTargetsDao(this._db);

  final NightshadeDatabase _db;

  static const String _columns =
      'id, name, kind, config_json, enabled, content_json, secret_ref, '
      'created_at, updated_at';

  /// Insert a destination row and return its id.
  ///
  /// Throws [DeliveryConfigSecretException] when [configJson] carries key
  /// material, and [FormatException] when it is not a JSON object.
  Future<int> create({
    required String name,
    required ArtifactDestinationKind kind,
    String configJson = '{}',
    bool enabled = true,
    Set<ArtifactContent> content = const <ArtifactContent>{},
    String? secretRef,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    if (name.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'a delivery target needs the name the morning report will use',
      );
    }
    assertNoSecretsInConfig(configJson);

    final created = _toEpochSeconds(createdAt ?? DateTime.now());
    final updated = updatedAt == null ? created : _toEpochSeconds(updatedAt);
    return _db.customInsert(
      'INSERT INTO delivery_targets('
      'name, kind, config_json, enabled, content_json, secret_ref, '
      'created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(name),
        Variable<String>(kind.wire),
        Variable<String>(configJson),
        Variable<int>(enabled ? 1 : 0),
        Variable<String>(ArtifactContent.encodeSelection(content)),
        Variable<String>(secretRef),
        Variable<int>(created),
        Variable<int>(updated),
      ],
    );
  }

  /// Fetch a destination by id, or null when absent.
  Future<ArtifactDestination?> getById(int id) async {
    final rows = await _db
        .customSelect(
          'SELECT $_columns FROM delivery_targets WHERE id = ? LIMIT 1',
          variables: [Variable<int>(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return _map(rows.first);
  }

  /// All destinations, in configuration order (oldest first).
  Future<List<ArtifactDestination>> listAll() async {
    final rows = await _db
        .customSelect(
          'SELECT $_columns FROM delivery_targets '
          'ORDER BY created_at ASC, id ASC',
        )
        .get();
    return rows.map(_map).toList();
  }

  /// The destinations delivery should actually visit tonight, in configuration
  /// order.
  Future<List<ArtifactDestination>> listEnabled() async {
    final rows = await _db
        .customSelect(
          'SELECT $_columns FROM delivery_targets WHERE enabled = 1 '
          'ORDER BY created_at ASC, id ASC',
        )
        .get();
    return rows.map(_map).toList();
  }

  /// Update the fields a caller passes and leave the rest alone, bumping
  /// `updated_at`. Returns the destination as it now stands.
  ///
  /// Throws [ArtifactDestinationMissingException] when the row is gone, and
  /// [DeliveryConfigSecretException] when a new [configJson] carries key
  /// material.
  Future<ArtifactDestination> update(
    int id, {
    String? name,
    String? configJson,
    Set<ArtifactContent>? content,
    String? secretRef,
    bool? enabled,
    DateTime? now,
  }) async {
    if (configJson != null) assertNoSecretsInConfig(configJson);
    await _require(id);

    final at = _toEpochSeconds(now ?? DateTime.now());
    await _db.customUpdate(
      'UPDATE delivery_targets SET '
      'name = COALESCE(?, name), '
      'config_json = COALESCE(?, config_json), '
      'content_json = COALESCE(?, content_json), '
      'secret_ref = COALESCE(?, secret_ref), '
      'enabled = COALESCE(?, enabled), '
      'updated_at = ? WHERE id = ?',
      variables: [
        Variable<String>(name),
        Variable<String>(configJson),
        Variable<String>(
          content == null ? null : ArtifactContent.encodeSelection(content),
        ),
        Variable<String>(secretRef),
        Variable<int>(enabled == null ? null : (enabled ? 1 : 0)),
        Variable<int>(at),
        Variable<int>(id),
      ],
      updateKind: UpdateKind.update,
    );
    return _require(id);
  }

  /// Clear this destination's keyring reference — the row keeps its transport
  /// config and stops claiming to hold key material. `COALESCE` in [update]
  /// cannot express a null, so clearing has its own call.
  Future<ArtifactDestination> clearSecretRef(int id, {DateTime? now}) async {
    await _require(id);
    final at = _toEpochSeconds(now ?? DateTime.now());
    await _db.customUpdate(
      'UPDATE delivery_targets SET secret_ref = NULL, updated_at = ? '
      'WHERE id = ?',
      variables: [Variable<int>(at), Variable<int>(id)],
      updateKind: UpdateKind.update,
    );
    return _require(id);
  }

  /// Delete a destination by id. Its `delivery_journal` rows cascade. Returns
  /// the number of rows changed.
  Future<int> deleteTarget(int id) {
    return _db.customUpdate(
      'DELETE FROM delivery_targets WHERE id = ?',
      variables: [Variable<int>(id)],
      updateKind: UpdateKind.delete,
    );
  }

  Future<ArtifactDestination> _require(int id) async {
    final destination = await getById(id);
    if (destination == null) throw ArtifactDestinationMissingException(id);
    return destination;
  }

  ArtifactDestination _map(QueryRow row) {
    return ArtifactDestination(
      id: row.read<int>('id'),
      name: row.read<String>('name'),
      kind: ArtifactDestinationKind.fromWire(row.read<String>('kind')),
      configJson: row.read<String>('config_json'),
      enabled: row.read<int>('enabled') != 0,
      content: ArtifactContent.decodeSelection(
        row.read<String>('content_json'),
      ),
      secretRef: row.readNullable<String>('secret_ref'),
      createdAt: _fromEpochSeconds(row.read<int>('created_at')),
      updatedAt: _fromEpochSeconds(row.read<int>('updated_at')),
    );
  }

  static int _toEpochSeconds(DateTime when) =>
      when.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromEpochSeconds(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Riverpod provider for [DeliveryTargetsDao].
final deliveryTargetsDaoProvider = Provider<DeliveryTargetsDao>((ref) {
  return DeliveryTargetsDao(ref.watch(databaseProvider));
});
