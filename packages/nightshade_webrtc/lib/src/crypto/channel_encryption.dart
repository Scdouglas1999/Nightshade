import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

/// Exception thrown when encryption or decryption fails
class EncryptionException implements Exception {
  final String message;
  EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}

/// Provides AES-256-GCM encryption for WebRTC data channels
/// Uses PBKDF2 for key derivation from session tokens
class ChannelEncryption {
  static const int _keySize = 32; // 256 bits
  static const int _nonceSize = 12; // 96 bits (recommended for GCM)
  static const int _tagSize = 16; // 128 bits
  static const int _pbkdf2Iterations = 100000; // OWASP recommended minimum

  final Uint8List _encryptionKey;

  ChannelEncryption._(this._encryptionKey);

  /// Create a ChannelEncryption instance from a session token
  /// Uses PBKDF2 with 100,000 iterations for key derivation
  factory ChannelEncryption.fromToken(String sessionToken, {String salt = 'nightshade.webrtc.v1'}) {
    final key = _deriveKey(sessionToken, salt);
    return ChannelEncryption._(key);
  }

  // ============================================================================
  // Encryption
  // ============================================================================

  /// Encrypt plaintext and return nonce + ciphertext + tag
  /// Format: [12 bytes nonce][variable ciphertext][16 bytes tag]
  Uint8List encrypt(Uint8List plaintext) {
    try {
      // Generate random nonce
      final nonce = _generateNonce();

      // Create GCM cipher
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true, // encrypt
          AEADParameters(
            KeyParameter(_encryptionKey),
            _tagSize * 8, // tag size in bits
            nonce,
            Uint8List(0), // no additional authenticated data
          ),
        );

      // Encrypt
      final ciphertext = cipher.process(plaintext);

      // Combine nonce + ciphertext (which includes the tag)
      final result = Uint8List(nonce.length + ciphertext.length);
      result.setRange(0, nonce.length, nonce);
      result.setRange(nonce.length, result.length, ciphertext);

      return result;
    } catch (e) {
      throw EncryptionException('Encryption failed: $e');
    }
  }

  /// Encrypt a UTF-8 string
  Uint8List encryptString(String plaintext) {
    final bytes = utf8.encode(plaintext);
    return encrypt(Uint8List.fromList(bytes));
  }

  /// Encrypt a JSON-serializable object
  /// Returns base64-encoded encrypted data
  String encryptJson(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final encrypted = encryptString(jsonString);
    return base64Encode(encrypted);
  }

  // ============================================================================
  // Decryption
  // ============================================================================

  /// Decrypt data that was encrypted with encrypt()
  /// Expects format: [12 bytes nonce][variable ciphertext][16 bytes tag]
  Uint8List decrypt(Uint8List data) {
    try {
      if (data.length < _nonceSize + _tagSize) {
        throw EncryptionException('Data too short to be valid encrypted data');
      }

      // Extract nonce and ciphertext
      final nonce = data.sublist(0, _nonceSize);
      final ciphertext = data.sublist(_nonceSize);

      // Create GCM cipher
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false, // decrypt
          AEADParameters(
            KeyParameter(_encryptionKey),
            _tagSize * 8, // tag size in bits
            nonce,
            Uint8List(0), // no additional authenticated data
          ),
        );

      // Decrypt and verify tag
      final plaintext = cipher.process(ciphertext);

      return plaintext;
    } catch (e) {
      throw EncryptionException('Decryption failed (possibly tampered data): $e');
    }
  }

  /// Decrypt to a UTF-8 string
  String decryptString(Uint8List data) {
    final bytes = decrypt(data);
    return utf8.decode(bytes);
  }

  /// Decrypt base64-encoded data to a JSON object
  Map<String, dynamic> decryptJson(String base64Data) {
    final encrypted = base64Decode(base64Data);
    final jsonString = decryptString(encrypted);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  // ============================================================================
  // Key Derivation
  // ============================================================================

  /// Derive an encryption key from a session token using PBKDF2
  static Uint8List _deriveKey(String sessionToken, String salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
        Uint8List.fromList(utf8.encode(salt)),
        _pbkdf2Iterations,
        _keySize,
      ));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(sessionToken)));
  }

  /// Generate a random nonce for GCM using cryptographically secure RNG
  static Uint8List _generateNonce() {
    final random = Random.secure();
    final nonce = Uint8List(_nonceSize);
    for (int i = 0; i < _nonceSize; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /// Test if data appears to be encrypted (has correct length for nonce + tag)
  static bool isEncrypted(Uint8List data) {
    return data.length >= _nonceSize + _tagSize;
  }

  /// Get the key fingerprint (for debugging, not security)
  String getKeyFingerprint() {
    final digest = sha256.convert(_encryptionKey);
    return digest.toString().substring(0, 16);
  }

  /// Clear the encryption key from memory (best effort)
  void dispose() {
    // Overwrite key with zeros
    for (int i = 0; i < _encryptionKey.length; i++) {
      _encryptionKey[i] = 0;
    }
  }
}

/// Helper extension for encrypting/decrypting strings directly
extension ChannelEncryptionExtension on String {
  /// Encrypt this string using the provided encryption instance
  Uint8List encryptWith(ChannelEncryption encryption) {
    return encryption.encryptString(this);
  }

  /// Decrypt this base64-encoded string using the provided encryption instance
  String decryptWith(ChannelEncryption encryption) {
    final data = base64Decode(this);
    return encryption.decryptString(data);
  }
}
