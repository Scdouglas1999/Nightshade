import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/session_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionHandlers', () {
    late ProviderContainer container;
    late SessionHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SessionHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('unsupported export format returns JSON bad request', () async {
      final response = await translateHandlerErrors(
        handlers.handleExportSession(
          Request(
            'GET',
            Uri.parse('http://localhost/api/sessions/1/export/pdf'),
          ),
          '1',
          'pdf',
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Unsupported export format');
      expect(body['supportedFormats'], ['json', 'csv', 'html']);
    });

    test(
      'start polar alignment malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleStartPolarAlignment(
            Request(
              'POST',
              Uri.parse('http://localhost/api/polar-alignment/start'),
              body: jsonEncode({}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );

    test('thumbnail invalid image ID returns JSON internal error', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetImageThumbnail(
          Request(
            'GET',
            Uri.parse('http://localhost/api/images/nope/thumbnail'),
          ),
          'nope',
        ),
      );

      expect(
        response.statusCode,
        anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });

  // P0-5 — HTTP Range support for /api/images/{id}/download.
  //
  // We spin up an in-memory Drift DB, write a real FITS-like file to a
  // tempdir, register the row, then exercise the handler with various
  // Range header shapes. The handler streams via `file.openRead(start,
  // end+1)` so the response body covers exactly the requested byte
  // slice; we drain the body to verify the bytes are correct.
  group('SessionHandlers /api/images/{id}/download (P0-5 Range)', () {
    late ProviderContainer container;
    late SessionHandlers handlers;
    late NightshadeDatabase db;
    late Directory tempDir;
    late File testFile;
    late int imageId;
    late int fileLength;

    // Deterministic payload — 100 incrementing bytes 0,1,2,...,99 so we
    // can spot-check sliced ranges by index.
    final payload = List<int>.generate(100, (i) => i % 256);

    setUp(() async {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = SessionHandlers(container);

      tempDir = await Directory.systemTemp.createTemp('nightshade_range_test_');
      testFile = File('${tempDir.path}${Platform.pathSeparator}test.fits');
      await testFile.writeAsBytes(payload);
      fileLength = await testFile.length();

      imageId = await db.imagesDao.createImage(
        CapturedImagesCompanion.insert(
          filePath: testFile.path,
          fileName: 'test.fits',
          fileFormat: const Value('fits'),
          fileSize: Value(fileLength),
          frameType: const Value('light'),
          exposureDuration: 60.0,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Tempdir cleanup is best-effort; failure shouldn't fail the test.
      }
    });

    Future<Response> hitDownload({Map<String, String>? headers}) {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/images/$imageId/download'),
        headers: headers,
      );
      return translateHandlerErrors(
        handlers.handleDownloadImage(request, imageId.toString()),
      );
    }

    test('200 full download advertises accept-ranges and etag', () async {
      final response = await hitDownload();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['content-length'], fileLength.toString());
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload);
    });

    test('206 partial with explicit range bytes=10-19', () async {
      final response = await hitDownload(headers: {'range': 'bytes=10-19'});

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['content-range'], 'bytes 10-19/$fileLength');
      expect(response.headers['content-length'], '10');
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload.sublist(10, 20));
    });

    test('206 with open-ended range bytes=50-', () async {
      final response = await hitDownload(headers: {'range': 'bytes=50-'});

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers['content-range'],
        'bytes 50-${fileLength - 1}/$fileLength',
      );
      expect(response.headers['content-length'], (fileLength - 50).toString());
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload.sublist(50));
    });

    test('206 with suffix range bytes=-25 returns last 25 bytes', () async {
      final response = await hitDownload(headers: {'range': 'bytes=-25'});

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers['content-range'],
        'bytes ${fileLength - 25}-${fileLength - 1}/$fileLength',
      );
      expect(response.headers['content-length'], '25');
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload.sublist(fileLength - 25));
    });

    test('416 when range start exceeds file size', () async {
      final response = await hitDownload(
        headers: {'range': 'bytes=10000-20000'},
      );

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(response.headers['content-range'], 'bytes */$fileLength');
    });

    test('416 for malformed range header (non-bytes unit)', () async {
      final response = await hitDownload(headers: {'range': 'lines=0-10'});

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    });

    test('416 for malformed range header (no dash)', () async {
      final response = await hitDownload(headers: {'range': 'bytes=10'});

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    });

    test('416 for multi-range request', () async {
      final response = await hitDownload(headers: {'range': 'bytes=0-9,20-29'});

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    });

    test('200 (not 206) when If-Range etag mismatches', () async {
      // First grab the real etag so we can deliberately send a different
      // one and verify the server falls back to a full body.
      final probe = await hitDownload();
      final realEtag = probe.headers['etag']!;
      final fakeEtag = realEtag.replaceFirst('"', '"X');
      expect(fakeEtag, isNot(realEtag));
      await probe.read().drain();

      final response = await hitDownload(
        headers: {'range': 'bytes=10-19', 'if-range': fakeEtag},
      );

      // Mismatched If-Range → server MUST return the full 200 body.
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['accept-ranges'], 'bytes');
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload);
    });

    test('206 honours If-Range when etag matches', () async {
      // Pull the real etag, then send it back with a valid Range.
      final probe = await hitDownload();
      final realEtag = probe.headers['etag']!;
      await probe.read().drain();

      final response = await hitDownload(
        headers: {'range': 'bytes=0-9', 'if-range': realEtag},
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers['content-range'], 'bytes 0-9/$fileLength');
      final body = await response.read().expand((c) => c).toList();
      expect(body, payload.sublist(0, 10));
    });

    test('404 when DB row missing', () async {
      final response = await translateHandlerErrors(
        handlers.handleDownloadImage(
          Request(
            'GET',
            Uri.parse('http://localhost/api/images/999999/download'),
          ),
          '999999',
        ),
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('404 when file on disk is missing', () async {
      // Delete the on-disk file but leave the row.
      await testFile.delete();
      final response = await hitDownload();
      expect(response.statusCode, HttpStatus.notFound);
    });
  });
}
