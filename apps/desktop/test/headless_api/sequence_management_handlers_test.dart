import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequence_management_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('SequenceManagementHandlers', () {
    late ProviderContainer container;
    late SequenceManagementHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SequenceManagementHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('invalid sequence ID returns JSON internal error', () async {
      final response = await handlers.handleGetSequenceById(
        Request(
          'GET',
          Uri.parse('http://localhost/api/sequence-management/not-an-id'),
        ),
        'not-an-id',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('create sequence malformed payload returns JSON internal error',
        () async {
      final response = await handlers.handleCreateSequence(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequence-management'),
          body: jsonEncode({}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('set node enabled malformed payload returns JSON internal error',
        () async {
      final response = await handlers.handleSetNodeEnabled(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequence-management/nodes/1/enabled'),
          body: jsonEncode({}),
        ),
        '1',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
