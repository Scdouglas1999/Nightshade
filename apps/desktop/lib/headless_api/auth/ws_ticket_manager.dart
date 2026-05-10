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

  /// Issues a fresh ticket. The caller is responsible for confirming that the
  /// requestor presented a full bearer token before calling this.
  String issue() {
    _purgeExpired();
    final ticket = _generateTicket();
    _tickets[ticket] = _Ticket(expiresAt: _now().add(_ticketLifetime));
    return ticket;
  }

  /// Consumes [presented] iff a non-expired matching ticket exists. Returns
  /// `true` on success and removes the ticket so it cannot be reused.
  bool consume(String? presented) {
    if (presented == null || presented.isEmpty) {
      return false;
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
      return false;
    }
    _tickets.remove(matchedKey);
    return true;
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
  _Ticket({required this.expiresAt});
}
