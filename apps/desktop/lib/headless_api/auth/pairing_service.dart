import 'dart:math';
import 'dart:typed_data';

import 'package:nightshade_webrtc/nightshade_webrtc.dart' show PairingDatabase;

/// Outcome of a verify attempt against the [PairingService].
enum PairingVerifyOutcome {
  success,
  invalidCode,
  codeExpired,
  codeAlreadyUsed,
}

class PairingStartResult {
  /// 6-digit code shown on the desktop console for the user to type into the
  /// dashboard's Pair sheet.
  final String code;
  final DateTime expiresAt;

  PairingStartResult({required this.code, required this.expiresAt});
}

class PairingVerifyResult {
  final PairingVerifyOutcome outcome;
  final String? sessionToken;
  final DateTime? expiresAt;

  PairingVerifyResult({
    required this.outcome,
    this.sessionToken,
    this.expiresAt,
  });
}

/// Pairing service tailored to the headless dashboard flow.
///
/// Why a dedicated service rather than re-using `TokenManager` directly:
/// the dashboard needs a 6-digit numeric code (audit §2.1) for casual phone
/// entry, while `TokenManager` issues a word-based code (e.g. STAR-LYRA-1234)
/// keyed off a 32-byte session token. We re-use the same Drift-backed
/// `PairingDatabase` schema for storage so paired-device records remain
/// compatible with the existing GUI server, but mint the user-facing code
/// independently.
class PairingService {
  static const Duration _defaultPairingTimeout = Duration(minutes: 5);
  static const Duration _defaultSessionTokenLifetime = Duration(days: 365);
  static const int _maxStartRetries = 5;

  final PairingDatabase _database;
  final Random _random;
  final DateTime Function() _now;

  PairingService({
    PairingDatabase? database,
    Random? random,
    DateTime Function()? now,
  })  : _database = database ?? PairingDatabase(),
        _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  PairingDatabase get database => _database;

  /// Begins a pairing session. Returns a 6-digit code to display on the
  /// desktop console. The code expires after [_defaultPairingTimeout].
  Future<PairingStartResult> startPairing() async {
    await _database.deleteExpiredPairingSessions();

    for (var attempt = 0; attempt < _maxStartRetries; attempt++) {
      final code = _generate6DigitCode();
      final sessionToken = _generateSessionToken();
      final expiresAt = _now().add(_defaultPairingTimeout);

      try {
        // PairingDatabase.createPairingSession enforces uniqueness on
        // pairingCode; on collision, retry with a new random code.
        await _database.createPairingSession(
          pairingCode: code,
          sessionToken: sessionToken,
          expiresIn: _defaultPairingTimeout,
        );
        return PairingStartResult(code: code, expiresAt: expiresAt);
      } catch (e) {
        if (attempt == _maxStartRetries - 1) {
          rethrow;
        }
        // Loop with a fresh random code.
      }
    }
    throw StateError('Failed to allocate a unique pairing code');
  }

  /// Validates a code submitted by the dashboard and persists the paired
  /// device. Returns the final session token to the dashboard. The dashboard
  /// stores it as its bearer token for subsequent requests.
  Future<PairingVerifyResult> verifyPairing({
    required String code,
    required String deviceId,
    required String deviceName,
    String deviceType = 'browser',
  }) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      return PairingVerifyResult(outcome: PairingVerifyOutcome.invalidCode);
    }

    final session = await _database.getPairingSession(normalizedCode);
    if (session == null) {
      return PairingVerifyResult(outcome: PairingVerifyOutcome.invalidCode);
    }

    if (session.isUsed) {
      return PairingVerifyResult(outcome: PairingVerifyOutcome.codeAlreadyUsed);
    }

    if (_now().isAfter(session.expiresAt)) {
      return PairingVerifyResult(outcome: PairingVerifyOutcome.codeExpired);
    }

    await _database.markPairingSessionUsed(normalizedCode);

    // Replace any existing record for this device id so old session tokens
    // never linger. This also ensures the new bearer takes effect immediately.
    final existing = await _database.getPairedDevice(deviceId);
    if (existing != null) {
      await _database.deletePairedDevice(deviceId);
    }
    await _database.addPairedDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      sessionToken: session.sessionToken,
      deviceType: deviceType,
    );
    await _database.deleteUsedPairingSessions();

    final expiresAt = _now().add(_defaultSessionTokenLifetime);
    return PairingVerifyResult(
      outcome: PairingVerifyOutcome.success,
      sessionToken: session.sessionToken,
      expiresAt: expiresAt,
    );
  }

  /// Visible for tests and bookkeeping.
  Duration get codeLifetime => _defaultPairingTimeout;

  /// Issue a tempered note: returns 0..9 weighted only by entropy of
  /// [_random], padded to 6 digits.
  String _generate6DigitCode() {
    // Why not Random.nextInt(1_000_000): we explicitly use Random.secure() so
    // codes cannot be guessed. Format with leading zeros so e.g. "000123" is
    // valid (otherwise an attacker has 10x fewer codes to guess than the
    // 1_000_000 range implies).
    final n = _random.nextInt(1000000);
    return n.toString().padLeft(6, '0');
  }

  String _generateSessionToken() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> close() async {
    await _database.close();
  }
}
