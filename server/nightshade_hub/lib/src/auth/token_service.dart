import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../db/hub_database.dart';

/// Access scopes a bearer token may carry. Mirrors the contract (§5): clients
/// `read` shared tiles, imagers `contribute`, operators `admin`. `admin`
/// implies the lower scopes.
enum HubScope {
  read,
  contribute,
  admin;

  static HubScope? parse(String raw) {
    switch (raw) {
      case 'read':
        return HubScope.read;
      case 'contribute':
        return HubScope.contribute;
      case 'admin':
        return HubScope.admin;
    }
    return null;
  }

  /// Whether a token with this scope satisfies a requirement for [required].
  bool satisfies(HubScope required) => index >= required.index;
}

/// An authenticated principal resolved from a bearer token.
class AuthIdentity {
  AuthIdentity({
    required this.accountId,
    required this.scope,
    required this.tokenHash,
  });

  final String accountId;
  final HubScope scope;

  /// SHA-256 of the raw token — the only form ever stored or put in a request
  /// context, so a diagnostic dump of the context cannot leak the secret.
  final String tokenHash;
}

/// Issues and resolves bearer tokens. The hub stores only the SHA-256 of each
/// raw token (never the token itself), and compares hashes — the same
/// hash-not-plaintext discipline `TokenManager`/`server_identity` use.
class TokenService {
  TokenService(this._db) : _random = Random.secure();

  final HubDatabase _db;
  final Random _random;

  /// Generate a cryptographically secure 32-byte token, hex-encoded (64 chars),
  /// persist its hash for [accountId] with [scope], and return the RAW token to
  /// hand to the caller exactly once.
  String issue({
    required String accountId,
    required HubScope scope,
    Duration? lifetime,
  }) {
    final raw = _generateRawToken();
    final hash = hashToken(raw);
    final now = DateTime.now().toUtc();
    _db.db.execute(
      'INSERT INTO tokens (token_hash, account_id, scope, created_at, '
      'expires_at) VALUES (?, ?, ?, ?, ?);',
      <Object?>[
        hash,
        accountId,
        scope.name,
        now.toIso8601String(),
        lifetime == null ? null : now.add(lifetime).toIso8601String(),
      ],
    );
    return raw;
  }

  /// Resolve a raw bearer token to its [AuthIdentity], or null if unknown,
  /// expired, or pointing at a deleted account.
  AuthIdentity? resolve(String rawToken) {
    final hash = hashToken(rawToken);
    final rows = _db.db.select(
      'SELECT account_id, scope, expires_at FROM tokens WHERE token_hash = ?;',
      <Object?>[hash],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final expiresAt = row['expires_at'] as String?;
    if (expiresAt != null) {
      final exp = DateTime.tryParse(expiresAt);
      if (exp != null && !DateTime.now().toUtc().isBefore(exp)) {
        // Expired: purge and deny.
        _db.db.execute('DELETE FROM tokens WHERE token_hash = ?;', <Object?>[
          hash,
        ]);
        return null;
      }
    }
    final scope = HubScope.parse(row['scope'] as String);
    if (scope == null) return null;
    return AuthIdentity(
      accountId: row['account_id'] as String,
      scope: scope,
      tokenHash: hash,
    );
  }

  /// Revoke every token for [accountId] (used on account suspension).
  void revokeAllForAccount(String accountId) {
    _db.db.execute('DELETE FROM tokens WHERE account_id = ?;', <Object?>[
      accountId,
    ]);
  }

  String _generateRawToken() {
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// SHA-256 hex of a raw token. Public so the audit layer can log a token's
  /// stable identity without the secret.
  static String hashToken(String rawToken) {
    return sha256.convert(utf8.encode(rawToken)).toString();
  }
}
