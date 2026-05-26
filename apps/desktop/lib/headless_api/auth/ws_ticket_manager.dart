import 'dart:math';

import 'timing.dart';

/// One-shot WebSocket auth tickets.
///
/// Why: Browsers cannot set Authorization headers on WebSocket upgrades, so
/// authenticated WS connections traditionally pass the bearer token via
/// `?token=...`. That writes the token into HTTP access logs, browser history,
/// and proxy logs. Instead, the client requests a short-lived single-use
/// ticket via an authenticated `POST /api/ws/ticket` and presents it as
/// `?ticket=...`. Tickets expire in [_ticketLifetime] and are invalidated on
/// the first WS upgrade that consumes them.
class WsTicketManager {
  static const Duration _ticketLifetime = Duration(seconds: 60);
  static const int _ticketLengthBytes = 32;

  final Random _random;
  final DateTime Function() _now;
  // Stored ticket -> expiry, keyed by the issued ticket value. We never log
  // the ticket value alongside identifying info; constant-time comparison is
  // used at consumption to avoid timing-side-channel ticket leaks.
  final Map<String, _Ticket> _tickets = {};

  WsTicketManager({Random? random, DateTime Function()? now})
      : _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  /// Issues a fresh ticket bound to [identity] (the SHA-256 digest of the
  /// bearer token that authenticated `POST /api/ws/ticket`). The caller is
  /// responsible for confirming that the requestor presented a full bearer
  /// token before calling this.
  ///
  /// P2-15: binding the ticket to the issuing identity means a client
  /// cannot launder its identity through the ticket flow — the WS
  /// upgrade carries the same principal as the HTTP request that minted
  /// the ticket, which is what the collaboration manager uses to fill
  /// `viewerId`.
  String issue({String? identity}) {
    _purgeExpired();
    final ticket = _generateTicket();
    _tickets[ticket] = _Ticket(
      expiresAt: _now().add(_ticketLifetime),
      identity: identity,
    );
    return ticket;
  }

  /// Consumes [presented] iff a non-expired matching ticket exists.
  /// Returns the identity that was bound at [issue] time on success, or
  /// `null` when no matching ticket exists or it's expired. Returning the
  /// identity instead of a bool lets the caller propagate the principal
  /// onto the upgraded socket without a second resolve pass.
  ///
  /// When the ticket was issued without an identity (legacy paths that
  /// have not yet been wired through) the returned value is the empty
  /// string — distinct from null so callers can still tell "ticket
  /// matched" from "ticket missing", but tells them the identity is not
  /// known and the WS path must fall back to its anonymous handling.
  String? consume(String? presented) {
    if (presented == null || presented.isEmpty) {
      return null;
    }
    _purgeExpired();
    // Iterate full set to keep comparison O(n) constant-time-ish; the map is
    // small (60s lifetime, single-shot) so this is cheap and avoids map-key
    // hash-based timing leaks.
    String? matchedKey;
    for (final entry in _tickets.entries) {
      if (constantTimeCompareStrings(entry.key, presented)) {
        matchedKey = entry.key;
      }
    }
    if (matchedKey == null) {
      return null;
    }
    final ticket = _tickets.remove(matchedKey);
    return ticket?.identity ?? '';
  }

  /// Visible for diagnostics/tests.
  int get outstandingTickets {
    _purgeExpired();
    return _tickets.length;
  }

  Duration get ticketLifetime => _ticketLifetime;

  void _purgeExpired() {
    final now = _now();
    _tickets.removeWhere((_, t) => now.isAfter(t.expiresAt));
  }

  String _generateTicket() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer();
    for (var i = 0; i < _ticketLengthBytes; i++) {
      buffer.writeCharCode(alphabet.codeUnitAt(_random.nextInt(alphabet.length)));
    }
    return buffer.toString();
  }
}

class _Ticket {
  final DateTime expiresAt;

  /// P2-15: the SHA-256 digest of the bearer token that minted this
  /// ticket. Null only for tickets issued through the legacy unbound
  /// path; see [WsTicketManager.consume] for the semantics.
  final String? identity;

  _Ticket({required this.expiresAt, this.identity});
}
