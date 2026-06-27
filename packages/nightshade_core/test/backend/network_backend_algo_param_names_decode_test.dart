// SLOP-DUP-001 follow-up regression: phd2GetAlgoParamNames decodes the list of
// algorithm parameter names from the SAME JSON key the server emits. The
// headless handler (handlePhd2GetAlgoParamNames) returns
// `{"axis": ..., "names": [...]}`, but the client previously read 'params',
// which always yielded null and threw on cast. This pins the decode to 'names'.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';

import '../fakes/fakes.dart';

void main() {
  test('phd2GetAlgoParamNames decodes the server "names" envelope', () async {
    final body = jsonEncode({
      'axis': 'ra',
      'names': ['MinMove', 'Aggression', 'Hysteresis'],
    });

    final fake = FakeNetworkClient()
      ..setResponse('/api/phd2/algo-params', method: 'GET', body: body);

    final backend = NetworkBackend(
      serverHost: '127.0.0.1',
      serverPort: 9999,
      webSocketPort: 9999,
      httpClient: fake,
      autoConnectWebSocket: false,
    );
    addTearDown(backend.dispose);

    final names = await backend.phd2GetAlgoParamNames(axis: 'ra');

    expect(names, equals(['MinMove', 'Aggression', 'Hysteresis']));
  });
}
