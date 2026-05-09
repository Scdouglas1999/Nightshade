import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_webrtc/src/crypto/channel_encryption.dart';

void main() {
  group('ChannelEncryption', () {
    late ChannelEncryption encryption;

    setUp(() {
      encryption =
          ChannelEncryption.fromToken('test-session-token-12345');
    });

    tearDown(() {
      encryption.dispose();
    });

    test('encrypt and decrypt round-trip produces original plaintext', () {
      final plaintext = Uint8List.fromList(utf8.encode('Hello, Nightshade!'));
      final ciphertext = encryption.encrypt(plaintext);
      final decrypted = encryption.decrypt(ciphertext);

      expect(decrypted, equals(plaintext));
    });

    test('encryptString and decryptString round-trip preserves text', () {
      const message = 'Slewing to M42 at RA 05h 35m 17s';
      final encrypted = encryption.encryptString(message);
      final decrypted = encryption.decryptString(encrypted);

      expect(decrypted, equals(message));
    });

    test('encryptJson and decryptJson round-trip preserves data', () {
      final data = {
        'command': 'slew',
        'ra': 83.82,
        'dec': -5.39,
        'target': 'M42',
      };
      final encrypted = encryption.encryptJson(data);
      final decrypted = encryption.decryptJson(encrypted);

      expect(decrypted, equals(data));
    });

    test('decrypt fails with wrong key', () {
      final other = ChannelEncryption.fromToken('different-session-token');
      addTearDown(other.dispose);

      final plaintext = Uint8List.fromList(utf8.encode('secret data'));
      final ciphertext = encryption.encrypt(plaintext);

      expect(
        () => other.decrypt(ciphertext),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('encrypting same plaintext twice produces different ciphertext', () {
      final plaintext = Uint8List.fromList(utf8.encode('identical input'));
      final first = encryption.encrypt(plaintext);
      final second = encryption.encrypt(plaintext);

      // The ciphertexts must differ because each uses a unique random nonce.
      expect(first, isNot(equals(second)));
    });

    test('key derivation is deterministic for same inputs', () {
      final a = ChannelEncryption.fromToken('same-token', salt: 'same-salt');
      final b = ChannelEncryption.fromToken('same-token', salt: 'same-salt');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      // Both instances should derive the same key, so one can decrypt the other's output.
      final plaintext = Uint8List.fromList(utf8.encode('round-trip via two instances'));
      final encrypted = a.encrypt(plaintext);
      final decrypted = b.decrypt(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('different tokens produce different keys', () {
      final a = ChannelEncryption.fromToken('token-alpha');
      final b = ChannelEncryption.fromToken('token-beta');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a.getKeyFingerprint(), isNot(equals(b.getKeyFingerprint())));
    });

    test('different salts produce different keys', () {
      final a = ChannelEncryption.fromToken('shared-token', salt: 'salt-one');
      final b = ChannelEncryption.fromToken('shared-token', salt: 'salt-two');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a.getKeyFingerprint(), isNot(equals(b.getKeyFingerprint())));
    });

    test('tampered ciphertext fails integrity check', () {
      final plaintext = Uint8List.fromList(utf8.encode('integrity test'));
      final ciphertext = encryption.encrypt(plaintext);

      // Flip a byte in the middle of the ciphertext (past the nonce region)
      final tampered = Uint8List.fromList(ciphertext);
      final flipIndex = 12 + (tampered.length - 12) ~/ 2; // middle of ciphertext
      tampered[flipIndex] ^= 0xFF;

      expect(
        () => encryption.decrypt(tampered),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('decrypt rejects data shorter than nonce + tag', () {
      // Nonce is 12 bytes, tag is 16 bytes, so minimum valid length is 28
      final tooShort = Uint8List(27);

      expect(
        () => encryption.decrypt(tooShort),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('encrypt and decrypt handles empty plaintext', () {
      final empty = Uint8List(0);
      final encrypted = encryption.encrypt(empty);
      final decrypted = encryption.decrypt(encrypted);

      expect(decrypted, equals(empty));
    });

    test('encrypt and decrypt handles large payload', () {
      // 64 KB payload (simulating image thumbnail transfer)
      final large = Uint8List(65536);
      for (int i = 0; i < large.length; i++) {
        large[i] = i % 256;
      }

      final encrypted = encryption.encrypt(large);
      final decrypted = encryption.decrypt(encrypted);

      expect(decrypted, equals(large));
    });

    test('isEncrypted returns true for valid-length data', () {
      final valid = Uint8List(28); // nonce(12) + tag(16) minimum
      expect(ChannelEncryption.isEncrypted(valid), isTrue);
    });

    test('isEncrypted returns false for too-short data', () {
      final tooShort = Uint8List(27);
      expect(ChannelEncryption.isEncrypted(tooShort), isFalse);
    });

    test('getKeyFingerprint returns 16-character hex string', () {
      final fingerprint = encryption.getKeyFingerprint();

      expect(fingerprint.length, equals(16));
      expect(fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('dispose zeroes the encryption key', () {
      final disposable = ChannelEncryption.fromToken('disposable-key');
      disposable.dispose();

      // After disposal the key is zeroed, so encrypt should either fail
      // or produce output that cannot be decrypted by a fresh instance.
      // Since the key is zeroed (all 0x00), encryption still works but with
      // a zero key, which is different from any PBKDF2-derived key.
      final plaintext = Uint8List.fromList(utf8.encode('test'));
      final ciphertext = disposable.encrypt(plaintext);

      final fresh = ChannelEncryption.fromToken('disposable-key');
      addTearDown(fresh.dispose);

      expect(
        () => fresh.decrypt(ciphertext),
        throwsA(isA<EncryptionException>()),
      );
    });
  });

  group('ChannelEncryptionExtension', () {
    late ChannelEncryption encryption;

    setUp(() {
      encryption = ChannelEncryption.fromToken('extension-test-token');
    });

    tearDown(() {
      encryption.dispose();
    });

    test('encryptWith and decryptWith round-trip via extension methods', () {
      const original = 'extension round-trip test';
      final encrypted = original.encryptWith(encryption);
      final decrypted = base64Encode(encrypted).decryptWith(encryption);

      expect(decrypted, equals(original));
    });
  });
}
