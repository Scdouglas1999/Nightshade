import 'dart:math';
import 'dart:typed_data';

import '../db/hub_database.dart';

/// Single-holder "follow-the-night" handoff per shared target: one contributor
/// holds the active claim (so the swarm does not pile redundant subs on the same
/// object at the same instant), then releases it as the target sets at their
/// site for the next contributor further west to pick up.
class HandoffService {
  HandoffService(this._db) : _random = Random.secure();

  final HubDatabase _db;
  final Random _random;

  /// How long a claim stays valid without renewal. A holder that goes dark
  /// (clouds, crash) frees the target for the next contributor automatically.
  static const Duration claimTtl = Duration(minutes: 30);

  /// Current claim state for [targetId], expiring stale claims lazily.
  HandoffState state(int targetId) {
    _expireStale(targetId);
    final rows = _db.db.select(
      'SELECT account_id, expires_at FROM handoff_claims WHERE target_id = ?;',
      <Object?>[targetId],
    );
    if (rows.isEmpty) {
      return HandoffState(targetId: targetId, holder: null, expiresAt: null);
    }
    return HandoffState(
      targetId: targetId,
      holder: rows.first['account_id'] as String,
      expiresAt: DateTime.tryParse(rows.first['expires_at'] as String),
    );
  }

  /// Claim [targetId] for [accountId]. Succeeds if free or already held by the
  /// same account (renewal). Returns null if another account currently holds it.
  HandoffClaim? claim({required int targetId, required String accountId}) {
    _expireStale(targetId);
    final current = state(targetId);
    if (current.holder != null && current.holder != accountId) {
      return null;
    }
    final token = _generateToken();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(claimTtl);
    _db.db.execute(
      'INSERT INTO handoff_claims (target_id, account_id, claim_token, '
      'claimed_at, expires_at) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(target_id) DO UPDATE SET '
      'account_id = excluded.account_id, '
      'claim_token = excluded.claim_token, '
      'claimed_at = excluded.claimed_at, '
      'expires_at = excluded.expires_at;',
      <Object?>[
        targetId,
        accountId,
        token,
        now.toIso8601String(),
        expiresAt.toIso8601String(),
      ],
    );
    return HandoffClaim(
      targetId: targetId,
      claimToken: token,
      expiresAt: expiresAt,
    );
  }

  /// Release [targetId] if held by [accountId]. Returns true if a claim was
  /// released, false if the account did not hold it.
  bool release({required int targetId, required String accountId}) {
    final current = state(targetId);
    if (current.holder != accountId) return false;
    _db.db.execute('DELETE FROM handoff_claims WHERE target_id = ?;', <Object?>[
      targetId,
    ]);
    return true;
  }

  void _expireStale(int targetId) {
    final rows = _db.db.select(
      'SELECT expires_at FROM handoff_claims WHERE target_id = ?;',
      <Object?>[targetId],
    );
    if (rows.isEmpty) return;
    final exp = DateTime.tryParse(rows.first['expires_at'] as String);
    if (exp != null && !DateTime.now().toUtc().isBefore(exp)) {
      _db.db.execute(
        'DELETE FROM handoff_claims WHERE target_id = ?;',
        <Object?>[targetId],
      );
    }
  }

  String _generateToken() {
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The current handoff state of a target.
class HandoffState {
  HandoffState({
    required this.targetId,
    required this.holder,
    required this.expiresAt,
  });

  final int targetId;
  final String? holder;
  final DateTime? expiresAt;
}

/// A successful claim handed to a contributor.
class HandoffClaim {
  HandoffClaim({
    required this.targetId,
    required this.claimToken,
    required this.expiresAt,
  });

  final int targetId;
  final String claimToken;
  final DateTime expiresAt;
}
