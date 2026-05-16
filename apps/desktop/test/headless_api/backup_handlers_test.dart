import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/backup_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('BackupHandlers', () {
    late ProviderContainer container;
    late BackupHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = BackupHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('create backup malformed payload returns JSON internal error',
        () async {
      final response = await translateHandlerErrors(handlers.handleCreateBackup(
        Request(
          'POST',
          Uri.parse('http://localhost/api/backup/create'),
          body: '{',
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('upload restore oversized content length returns JSON too large',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleUploadRestoreBackup(
        Request(
          'POST',
          Uri.parse('http://localhost/api/backup/upload-restore'),
          headers: {'content-length': '${257 * 1024 * 1024}'},
        ),
      ));

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Backup upload is too large');
      expect(body['maxBytes'], 256 * 1024 * 1024);
    });

    test('upload restore invalid filename returns JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleUploadRestoreBackup(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/backup/upload-restore?fileName=bad.exe',
          ),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'Invalid backup filename. Use a .nsbackup or .json filename.',
      );
    });
  });
}
