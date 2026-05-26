import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequence_management_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SequenceManagementHandlers', () {
    late ProviderContainer container;
    late SequenceManagementHandlers handlers;
    late NightshadeDatabase db;

    setUp(() async {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = SequenceManagementHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('invalid sequence ID returns JSON internal error', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetSequenceById(
        Request(
          'GET',
          Uri.parse('http://localhost/api/sequence-management/not-an-id'),
        ),
        'not-an-id',
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('create sequence malformed payload returns JSON internal error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleCreateSequence(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequence-management'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('set node enabled malformed payload returns JSON internal error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleSetNodeEnabled(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequence-management/nodes/1/enabled'),
          body: jsonEncode({}),
        ),
        '1',
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('save-full persists sequence and notifies catalog bus', () async {
      final updates = <SequenceCatalogUpdate>[];
      final sub = container
          .read(sequenceCatalogUpdateBusProvider)
          .stream
          .listen(updates.add);

      const rootId = 'root-save-full-test';
      final response = await translateHandlerErrors(
        handlers.handleSaveFullSequence(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequence-management/save-full'),
            body: jsonEncode({
              'sequence': {
                'schemaVersion': SequenceFileService.currentSchemaVersion,
                'version': '2.0',
                'name': 'Remote Draft',
                'description': '',
                'rootNodeId': rootId,
                'isTemplate': false,
                'createdAt': DateTime(2026, 1, 1).toIso8601String(),
                'modifiedAt': DateTime(2026, 1, 2).toIso8601String(),
                'nodes': {
                  rootId: {
                    'id': rootId,
                    'nodeType': 'instructionSet',
                    'name': 'Sequence',
                    'parentId': null,
                    'childIds': <String>[],
                    'orderIndex': 0,
                    'isEnabled': true,
                  },
                },
              },
              'isTemplate': false,
            }),
            headers: {'Content-Type': 'application/json'},
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['id'], isA<int>());

      expect(updates, hasLength(1));
      expect(updates.single.action, 'saved');
      expect(updates.single.name, 'Remote Draft');
      expect(updates.single.sequenceId, body['id']);

      await sub.cancel();
    });

    test('delete sequence publishes catalog bus and HostStateChanged', () async {
      const rootId = 'root-delete-notify';
      final saveResponse = await translateHandlerErrors(
        handlers.handleSaveFullSequence(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequence-management/save-full'),
            body: jsonEncode({
              'sequence': {
                'schemaVersion': SequenceFileService.currentSchemaVersion,
                'version': '2.0',
                'name': 'To Delete',
                'description': '',
                'rootNodeId': rootId,
                'isTemplate': false,
                'createdAt': DateTime(2026, 1, 1).toIso8601String(),
                'modifiedAt': DateTime(2026, 1, 2).toIso8601String(),
                'nodes': {
                  rootId: {
                    'id': rootId,
                    'nodeType': 'instructionSet',
                    'name': 'Sequence',
                    'parentId': null,
                    'childIds': <String>[],
                    'orderIndex': 0,
                    'isEnabled': true,
                  },
                },
              },
              'isTemplate': false,
            }),
            headers: {'Content-Type': 'application/json'},
          ),
        ),
      );
      final saveBody = jsonDecode(await saveResponse.readAsString()) as Map;
      final sequenceId = saveBody['id'] as int;

      final published = <NightshadeEvent>[];
      container.read(hostMutationEventHubProvider).wsBroadcast = published.add;

      final deleteResponse = await translateHandlerErrors(
        handlers.handleDeleteSequence(
          Request(
            'DELETE',
            Uri.parse('http://localhost/api/sequence-management/$sequenceId'),
          ),
          sequenceId.toString(),
        ),
      );
      expect(deleteResponse.statusCode, HttpStatus.ok);
      expect(published, hasLength(1));
      expect(published.single.eventType, hostStateChangedEventType);
      expect(published.single.data['entityId'], sequenceId.toString());
      expect(published.single.data['action'], HostMutationAction.deleted);
    });

    test('list-full returns persisted sequences', () async {
      const rootId = 'root-list-full';
      await translateHandlerErrors(
        handlers.handleSaveFullSequence(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequence-management/save-full'),
            body: jsonEncode({
              'sequence': {
                'schemaVersion': SequenceFileService.currentSchemaVersion,
                'version': '2.0',
                'name': 'List Full Entry',
                'description': '',
                'rootNodeId': rootId,
                'isTemplate': false,
                'createdAt': DateTime(2026, 1, 1).toIso8601String(),
                'modifiedAt': DateTime(2026, 1, 2).toIso8601String(),
                'nodes': {
                  rootId: {
                    'id': rootId,
                    'nodeType': 'instructionSet',
                    'name': 'Sequence',
                    'parentId': null,
                    'childIds': <String>[],
                    'orderIndex': 0,
                    'isEnabled': true,
                  },
                },
              },
              'isTemplate': false,
            }),
            headers: {'Content-Type': 'application/json'},
          ),
        ),
      );

      final listResponse = await translateHandlerErrors(
        handlers.handleListFullSequences(
          Request(
            'GET',
            Uri.parse('http://localhost/api/sequence-management/list-full'),
          ),
        ),
      );
      expect(listResponse.statusCode, HttpStatus.ok);
      final body = jsonDecode(await listResponse.readAsString()) as Map;
      final sequences = body['sequences'] as List;
      expect(sequences, isNotEmpty);
      expect(
        sequences.cast<Map>().any((m) => m['name'] == 'List Full Entry'),
        isTrue,
      );
    });
  });
}
