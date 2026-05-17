import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_remote_protocol/src/auth/token_manager.dart';
import 'package:nightshade_remote_protocol/src/database/pairing_database.dart';

class MockPairingDatabase extends Mock implements PairingDatabase {}

class FakePairedDevicesCompanion extends Fake
    implements PairedDevicesCompanion {}

void main() {
  group('TokenManager', () {
    late MockPairingDatabase mockDb;
    late TokenManager tokenManager;

    setUp(() {
      mockDb = MockPairingDatabase();
      tokenManager = TokenManager(mockDb);
    });

    group('generateSecureToken', () {
      test('produces a 64-character hex string', () {
        final token = tokenManager.generateSecureToken();

        expect(token.length, equals(64));
        expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
      });

      test('generates unique tokens on successive calls', () {
        final tokens = <String>{};
        for (int i = 0; i < 50; i++) {
          tokens.add(tokenManager.generateSecureToken());
        }
        // All 50 should be unique
        expect(tokens.length, equals(50));
      });
    });

    group('generatePairingCode', () {
      test('follows WORD-WORD-NNNN format', () {
        final token = tokenManager.generateSecureToken();
        final code = tokenManager.generatePairingCode(token);

        expect(code, matches(RegExp(r'^[A-Z]+-[A-Z]+-\d{4}$')));
      });

      test('is deterministic for the same token', () {
        final token = tokenManager.generateSecureToken();
        final code1 = tokenManager.generatePairingCode(token);
        final code2 = tokenManager.generatePairingCode(token);

        expect(code1, equals(code2));
      });
    });

    group('verifySessionToken', () {
      test('returns valid for correct device and token', () async {
        final device = _fakePairedDevice(
          deviceId: 'device-1',
          sessionToken: 'aabbccdd' * 8, // 64 hex chars
          isActive: true,
        );

        when(() => mockDb.getPairedDevice('device-1'))
            .thenAnswer((_) async => device);
        when(() => mockDb.updateLastConnected('device-1'))
            .thenAnswer((_) async {});

        final result = await tokenManager.verifySessionToken(
          deviceId: 'device-1',
          token: 'aabbccdd' * 8,
        );

        expect(result, equals(TokenVerificationResult.valid));
        verify(() => mockDb.updateLastConnected('device-1')).called(1);
      });

      test('returns invalid for wrong token', () async {
        final device = _fakePairedDevice(
          deviceId: 'device-1',
          sessionToken: 'aabbccdd' * 8,
          isActive: true,
        );

        when(() => mockDb.getPairedDevice('device-1'))
            .thenAnswer((_) async => device);

        final result = await tokenManager.verifySessionToken(
          deviceId: 'device-1',
          token: '11223344' * 8,
        );

        expect(result, equals(TokenVerificationResult.invalid));
        verifyNever(() => mockDb.updateLastConnected(any()));
      });

      test('returns deviceNotFound for unknown device', () async {
        when(() => mockDb.getPairedDevice('unknown'))
            .thenAnswer((_) async => null);

        final result = await tokenManager.verifySessionToken(
          deviceId: 'unknown',
          token: 'anything',
        );

        expect(result, equals(TokenVerificationResult.deviceNotFound));
      });

      test('returns deviceRevoked for inactive device', () async {
        final device = _fakePairedDevice(
          deviceId: 'device-revoked',
          sessionToken: 'aabbccdd' * 8,
          isActive: false,
        );

        when(() => mockDb.getPairedDevice('device-revoked'))
            .thenAnswer((_) async => device);

        final result = await tokenManager.verifySessionToken(
          deviceId: 'device-revoked',
          token: 'aabbccdd' * 8,
        );

        expect(result, equals(TokenVerificationResult.deviceRevoked));
      });
    });

    group('revokeDevice', () {
      test('delegates to database revokeDevice', () async {
        when(() => mockDb.revokeDevice('dev-1')).thenAnswer((_) async {});

        await tokenManager.revokeDevice('dev-1');

        verify(() => mockDb.revokeDevice('dev-1')).called(1);
      });
    });

    group('hashToken', () {
      test('returns consistent SHA-256 hash for same input', () {
        final hash1 = tokenManager.hashToken('my-token');
        final hash2 = tokenManager.hashToken('my-token');

        expect(hash1, equals(hash2));
        // SHA-256 produces a 64-char hex string
        expect(hash1.length, equals(64));
        expect(hash1, matches(RegExp(r'^[0-9a-f]{64}$')));
      });

      test('different tokens produce different hashes', () {
        final hash1 = tokenManager.hashToken('token-a');
        final hash2 = tokenManager.hashToken('token-b');

        expect(hash1, isNot(equals(hash2)));
      });
    });

    group('verifyPairing', () {
      test('returns invalidCode when session not found', () async {
        when(() => mockDb.getPairingSession('BAD-0000'))
            .thenAnswer((_) async => null);

        final result = await tokenManager.verifyPairing(
          pairingCode: 'BAD-0000',
          deviceId: 'dev-1',
          deviceName: 'Test Phone',
        );

        expect(result, equals(PairingResult.invalidCode));
      });

      test('returns codeAlreadyUsed when session is consumed', () async {
        final session = _fakePairingSession(
          pairingCode: 'STAR-1234',
          isUsed: true,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        when(() => mockDb.getPairingSession('STAR-1234'))
            .thenAnswer((_) async => session);

        final result = await tokenManager.verifyPairing(
          pairingCode: 'STAR-1234',
          deviceId: 'dev-1',
          deviceName: 'Test Phone',
        );

        expect(result, equals(PairingResult.codeAlreadyUsed));
      });

      test('returns codeExpired when session is past expiry', () async {
        final session = _fakePairingSession(
          pairingCode: 'MOON-LYRA-5678',
          isUsed: false,
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );

        when(() => mockDb.getPairingSession('MOON-LYRA-5678'))
            .thenAnswer((_) async => session);

        final result = await tokenManager.verifyPairing(
          pairingCode: 'MOON-LYRA-5678',
          deviceId: 'dev-1',
          deviceName: 'Test Phone',
        );

        expect(result, equals(PairingResult.codeExpired));
      });

      test('reissues a fresh token when pairing an already paired device',
          () async {
        final session = _fakePairingSession(
          pairingCode: 'STAR-LYRA-1234',
          sessionToken: '11223344' * 8,
          isUsed: false,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
        final existingDevice = _fakePairedDevice(
          deviceId: 'dev-1',
          sessionToken: 'aabbccdd' * 8,
          isActive: true,
        );

        when(() => mockDb.getPairingSession('STAR-LYRA-1234'))
            .thenAnswer((_) async => session);
        when(() => mockDb.getPairedDevice('dev-1'))
            .thenAnswer((_) async => existingDevice);
        when(() => mockDb.markPairingSessionUsed('STAR-LYRA-1234'))
            .thenAnswer((_) async {});
        when(() => mockDb.deletePairedDevice('dev-1')).thenAnswer((_) async {});
        when(
          () => mockDb.addPairedDevice(
            deviceId: 'dev-1',
            deviceName: 'Test Phone',
            sessionToken: '11223344' * 8,
            deviceType: 'mobile',
          ),
        ).thenAnswer((_) async {});
        when(() => mockDb.deleteUsedPairingSessions()).thenAnswer((_) async {});

        final result = await tokenManager.completePairing(
          pairingCode: 'star-lyra-1234',
          deviceId: 'dev-1',
          deviceName: 'Test Phone',
        );

        expect(result.result, equals(PairingResult.deviceAlreadyPaired));
        expect(result.sessionToken, equals('11223344' * 8));
        verify(() => mockDb.deletePairedDevice('dev-1')).called(1);
        verify(
          () => mockDb.addPairedDevice(
            deviceId: 'dev-1',
            deviceName: 'Test Phone',
            sessionToken: '11223344' * 8,
            deviceType: 'mobile',
          ),
        ).called(1);
      });
    });
  });
}

/// Creates a fake [PairedDevice] with the given properties.
/// PairedDevice is a Drift-generated data class, so we construct it directly.
PairedDevice _fakePairedDevice({
  required String deviceId,
  required String sessionToken,
  required bool isActive,
}) {
  return PairedDevice(
    deviceId: deviceId,
    deviceName: 'Test Device',
    sessionToken: sessionToken,
    pairedAt: DateTime(2025, 1, 1),
    lastConnectedAt: null,
    deviceType: 'mobile',
    isActive: isActive,
  );
}

/// Creates a fake [PairingSession] with the given properties.
PairingSession _fakePairingSession({
  required String pairingCode,
  required bool isUsed,
  required DateTime expiresAt,
  String sessionToken = '',
}) {
  return PairingSession(
    id: 1,
    pairingCode: pairingCode,
    sessionToken: sessionToken.isEmpty ? 'aabbccdd' * 8 : sessionToken,
    createdAt: DateTime(2025, 1, 1),
    expiresAt: expiresAt,
    isUsed: isUsed,
  );
}
