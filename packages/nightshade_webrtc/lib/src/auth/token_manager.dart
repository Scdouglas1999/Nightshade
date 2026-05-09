import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../database/pairing_database.dart';

/// Result of a pairing attempt
enum PairingResult {
  success,
  invalidCode,
  codeExpired,
  codeAlreadyUsed,
  deviceAlreadyPaired,
}

/// Result of a token verification
enum TokenVerificationResult {
  valid,
  invalid,
  deviceRevoked,
  deviceNotFound,
}

typedef PairingCompletion = ({PairingResult result, String? sessionToken});

/// Manages authentication tokens and pairing for WebRTC connections
class TokenManager {
  final PairingDatabase _database;
  final Random _random = Random.secure();
  static const int _maxPairingCreationAttempts = 5;

  /// Words for generating memorable pairing codes
  static const _codeWords = [
    'STAR',
    'MOON',
    'NOVA',
    'ORION',
    'LYRA',
    'CYGNUS',
    'VEGA',
    'SIRIUS',
    'PLUTO',
    'MARS',
    'VENUS',
    'COMET',
    'NEBULA',
    'GALAXY',
    'PULSAR',
    'QUASAR',
    'METEOR',
    'COSMOS',
    'ZENITH',
    'ASTRO',
  ];

  TokenManager(this._database);

  // ============================================================================
  // Token Generation
  // ============================================================================

  /// Generate a cryptographically secure 32-byte token
  /// Returns the token as a hex-encoded string (64 characters)
  String generateSecureToken() {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return _bytesToHex(bytes);
  }

  /// Generate a user-friendly pairing code (e.g., "STAR-LYRA-1234")
  /// The code is derived from a secure token to ensure uniqueness
  String generatePairingCode(String token) {
    // Use the first 4 bytes of the token to derive a larger, memorable code
    // space than a single-word code would allow.
    final tokenBytes = _hexToBytes(token);
    final firstWordIndex = tokenBytes[0] % _codeWords.length;
    final secondWordIndex = tokenBytes[1] % _codeWords.length;
    final number = ((tokenBytes[2] << 8) | tokenBytes[3]) % 10000;

    return '${_codeWords[firstWordIndex]}-${_codeWords[secondWordIndex]}-${number.toString().padLeft(4, '0')}';
  }

  // ============================================================================
  // Pairing Management
  // ============================================================================

  /// Start a new pairing session
  /// Returns the pairing code to display to the user
  Future<String> startPairing({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Clean up expired sessions before creating a new one
    await _database.deleteExpiredPairingSessions();

    for (var attempt = 0; attempt < _maxPairingCreationAttempts; attempt++) {
      final sessionToken = generateSecureToken();
      final pairingCode = generatePairingCode(sessionToken);

      try {
        await _database.createPairingSession(
          pairingCode: pairingCode,
          sessionToken: sessionToken,
          expiresIn: timeout,
        );
        return pairingCode;
      } catch (_) {
        if (attempt == _maxPairingCreationAttempts - 1) {
          rethrow;
        }
      }
    }

    throw StateError('Failed to create a unique pairing code.');
  }

  /// Verify a pairing attempt and complete the pairing
  Future<PairingResult> verifyPairing({
    required String pairingCode,
    required String deviceId,
    required String deviceName,
    String deviceType = 'mobile',
  }) async {
    final completion = await completePairing(
      pairingCode: pairingCode,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
    );
    return completion.result;
  }

  /// Verify a pairing attempt, persist the device, and return its session token.
  Future<PairingCompletion> completePairing({
    required String pairingCode,
    required String deviceId,
    required String deviceName,
    String deviceType = 'mobile',
  }) async {
    final normalizedPairingCode = pairingCode.trim().toUpperCase();
    final normalizedDeviceId = deviceId.trim();
    final normalizedDeviceName = deviceName.trim();

    // Retrieve pairing session
    final session = await _database.getPairingSession(normalizedPairingCode);

    if (session == null) {
      return (result: PairingResult.invalidCode, sessionToken: null);
    }

    // Check if already used
    if (session.isUsed) {
      return (result: PairingResult.codeAlreadyUsed, sessionToken: null);
    }

    // Check if expired
    if (DateTime.now().isAfter(session.expiresAt)) {
      return (result: PairingResult.codeExpired, sessionToken: null);
    }

    // Check if device already paired
    final existingDevice = await _database.getPairedDevice(normalizedDeviceId);
    final wasAlreadyPaired = existingDevice != null && existingDevice.isActive;

    // Mark session as used
    await _database.markPairingSessionUsed(normalizedPairingCode);

    // Add or update paired device. Existing devices are re-issued the fresh
    // session token from the current pairing flow instead of disclosing any
    // previous token.
    if (existingDevice != null) {
      await _database.deletePairedDevice(normalizedDeviceId);
    }

    await _database.addPairedDevice(
      deviceId: normalizedDeviceId,
      deviceName: normalizedDeviceName,
      sessionToken: session.sessionToken,
      deviceType: deviceType,
    );

    // Clean up used session
    await _database.deleteUsedPairingSessions();

    return (
      result: wasAlreadyPaired
          ? PairingResult.deviceAlreadyPaired
          : PairingResult.success,
      sessionToken: session.sessionToken,
    );
  }

  /// Verify a session token for subsequent connections
  /// Uses constant-time comparison to prevent timing attacks
  Future<TokenVerificationResult> verifySessionToken({
    required String deviceId,
    required String token,
  }) async {
    final device = await _database.getPairedDevice(deviceId);

    if (device == null) {
      return TokenVerificationResult.deviceNotFound;
    }

    if (!device.isActive) {
      return TokenVerificationResult.deviceRevoked;
    }

    // Constant-time comparison to prevent timing attacks
    if (_constantTimeCompare(device.sessionToken, token)) {
      // Update last connected timestamp
      await _database.updateLastConnected(deviceId);
      return TokenVerificationResult.valid;
    }

    return TokenVerificationResult.invalid;
  }

  /// Revoke a paired device
  Future<void> revokeDevice(String deviceId) async {
    await _database.revokeDevice(deviceId);
  }

  /// Delete a paired device completely
  Future<void> deleteDevice(String deviceId) async {
    await _database.deletePairedDevice(deviceId);
  }

  /// Get all active paired devices
  Future<List<PairedDevice>> getActivePairedDevices() async {
    return await _database.getActivePairedDevices();
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Constant-time string comparison to prevent timing attacks
  /// Both strings must be hex-encoded and of the same length
  bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }

    return result == 0;
  }

  /// Hash a token using SHA-256 (for logging/debugging without exposing the token)
  String hashToken(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
