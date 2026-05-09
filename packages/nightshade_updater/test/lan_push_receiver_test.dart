import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_updater/src/services/lan_push_receiver.dart';

void main() {
  test('rejects concurrent connections while authentication is in progress',
      () async {
    final receiver = LanPushReceiver(
      currentVersion: '2.0.0',
      currentBuildNumber: 1,
      pushSecret: 'secret',
      serverPort: 45691,
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
