import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_updater/src/services/lan_push_receiver.dart';
import 'package:nightshade_updater/src/services/update_verifier.dart';

Future<UpdateVerifier> _verifierWithKey() async {
  // §7A.7: startServer refuses to run without a trusted key compiled
  // in. Tests do not get `--dart-define=NIGHTSHADE_UPDATE_PUBLIC_KEY`,
  // so we inject a freshly generated key explicitly. We never use it
  // to verify a real manifest in this test.
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final base64Key = base64Encode(Uint8List.fromList(publicKey.bytes));
  return UpdateVerifier(trustedPublicKeyBase64: base64Key);
}

void main() {
  test('rejects concurrent connections while authentication is in progress',
      () async {
    final verifier = await _verifierWithKey();
    final receiver = LanPushReceiver(
      currentVersion: '2.0.0',
      currentBuildNumber: 1,
      pushSecret: 'secret',
      serverPort: 45691,
      verifier: verifier,
    );
    await receiver.startServer();
    addTearDown(receiver.stopServer);

    final firstClient =
        await Socket.connect(InternetAddress.loopbackIPv4, 45691);
    addTearDown(firstClient.close);

    // Let the server reserve the receive slot for the first connection.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final secondClient =
        await Socket.connect(InternetAddress.loopbackIPv4, 45691);
    addTearDown(secondClient.close);

    final response = await secondClient
        .map(utf8.decode)
        .join()
        .timeout(const Duration(seconds: 2));

    expect(response, contains('Already receiving update'));
    expect(receiver.versionInfo['isReceiving'], isTrue);
  });
}
