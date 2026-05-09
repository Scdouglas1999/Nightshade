import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

void main() {
  group('NightshadeWebServer collaboration', () {
    late NightshadeWebServer server;
    late LiveCollaborationSessionManager manager;
    late http.Client client;
    late Uri baseUri;

    setUp(() async {
      manager = LiveCollaborationSessionManager();
      server = NightshadeWebServer(port: 0);
      server.liveCollaborationSessionManager = manager;
      await server.start();
      client = http.Client();
      baseUri = Uri.parse('http://127.0.0.1:${server.actualPort}');
    });

    tearDown(() async {
      client.close();
      await server.stop();
      manager.dispose();
    });

    Future<Map<String, dynamic>> getJson(String path) async {
      final response = await client.get(baseUri.resolve(path));
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Future<Map<String, dynamic>> postJson(
      String path,
      Map<String, dynamic> body,
    ) async {
      final response = await client.post(
        baseUri.resolve(path),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    test('rest endpoints update collaboration and session handoff state', () async {
      final initial = await getJson('/api/collaboration/state');
      expect(initial['viewers'], isEmpty);
      expect(initial['sessionHandoff'], isNull);

      final joined = await postJson('/api/collaboration/viewers/join', const {
        'viewerId': 'viewer-1',
        'name': 'Alice',
      });
      expect((joined['viewers'] as List).single['viewerId'], 'viewer-1');

      final preview = await postJson('/api/collaboration/preview', const {
        'preview': {'imageId': 'frame-9', 'stretch': 'linked'},
      });
      expect((preview['preview'] as Map<String, dynamic>)['imageId'], 'frame-9');

      final chat = await postJson('/api/collaboration/chat', const {
        'viewerId': 'viewer-1',
        'viewerName': 'Alice',
        'message': 'Looks good',
      });
      expect((chat['chat'] as List).single['message'], 'Looks good');

      final annotation =
          await postJson('/api/collaboration/annotations', const {
        'annotationId': 'ann-1',
        'viewerId': 'viewer-1',
        'kind': 'marker',
        'payload': {'x': 120, 'y': 44},
      });
      expect((annotation['annotations'] as List).single['kind'], 'marker');

      final handoff = await postJson('/api/session-handoff', const {
        'handoff': {'sessionId': 12, 'targetName': 'NGC 7000'},
      });
      expect(
        (handoff['sessionHandoff'] as Map<String, dynamic>)['targetName'],
        'NGC 7000',
      );

      final fetchedHandoff = await getJson('/api/session-handoff');
      expect(
        (fetchedHandoff['sessionHandoff'] as Map<String, dynamic>)['sessionId'],
        12,
      );

      final clearedResponse = await client.delete(baseUri.resolve('/api/session-handoff'));
      expect(clearedResponse.statusCode, 200);
      final cleared =
          jsonDecode(clearedResponse.body) as Map<String, dynamic>;
      expect(cleared['sessionHandoff'], isNull);
    });

    test('websocket commands broadcast collaboration state', () async {
      final socket =
          await WebSocket.connect('ws://127.0.0.1:${server.actualPort}/api/ws');
      final messages = socket
          .map((event) => jsonDecode(event as String) as Map<String, dynamic>)
          .asBroadcastStream();

      final initialFuture =
          messages.firstWhere((message) => message['type'] == 'collaboration_state');
      final initial = await initialFuture;
      expect((initial['state'] as Map<String, dynamic>)['viewers'], isEmpty);

      final joinedFuture = messages.firstWhere((message) {
        if (message['type'] != 'collaboration_state') {
          return false;
        }
        final state = message['state'] as Map<String, dynamic>;
        return (state['viewers'] as List).length == 1;
      });
      socket.add(jsonEncode(const {
        'type': 'collaboration.join',
        'viewerId': 'viewer-2',
        'name': 'Bob',
      }));
      final joined = await joinedFuture;
      final joinedState = joined['state'] as Map<String, dynamic>;
      expect((joinedState['viewers'] as List).single['name'], 'Bob');

      final handoffFuture = messages.firstWhere((message) {
        if (message['type'] != 'collaboration_state') {
          return false;
        }
        final state = message['state'] as Map<String, dynamic>;
        return state['sessionHandoff'] != null;
      });
      socket.add(jsonEncode(const {
        'type': 'session_handoff.set',
        'handoff': {'sessionId': 77, 'targetName': 'Rosette'},
      }));
      final handoff = await handoffFuture;
      final handoffState = handoff['state'] as Map<String, dynamic>;
      expect(
        (handoffState['sessionHandoff'] as Map<String, dynamic>)['sessionId'],
        77,
      );

      await socket.close();
    });
  });
}
