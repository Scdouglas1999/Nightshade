import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

void main() {
  group('computeServerFingerprint', () {
    test('is stable for the same secret', () {
      final a = computeServerFingerprint('nightshade-test-secret');
      final b = computeServerFingerprint('nightshade-test-secret');
      expect(a, equals(b));
      expect(a.length, 64);
    });

    test('rejects empty secret', () {
      expect(
        () => computeServerFingerprint(''),
        throwsArgumentError,
      );
    });
  });

  group('QrConnectionData pairingCode', () {
    test('round-trips pairingCode in QR JSON', () {
      const payload = '''
{"service":"nightshade","host":"192.168.1.10","port":8080,"version":"2.5.0","fingerprint":"abcdef1234567890","pairingCode":"STAR-LYRA-1234"}
''';
      final data = QrConnectionData.parseStrict(payload);
      expect(data.pairingCode, 'STAR-LYRA-1234');
      expect(data.toJson()['pairingCode'], 'STAR-LYRA-1234');
    });
  });
}
