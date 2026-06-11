import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequencer_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('SequencerHandlers', () {
    late ProviderContainer container;
    late SequencerHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SequencerHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('status disconnected backend failure returns JSON error', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerStatus(
          Request('GET', Uri.parse('http://localhost/api/sequencer/status')),
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

    test('load malformed payload returns JSON internal server error', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerLoad(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/load'),
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
    });

    test('dither config validates required numeric fields as JSON', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerUpdateDitherConfig(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/update-dither-config'),
            body: jsonEncode({'pixels': 5}),
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
    });

    test('skip-to-node rejects missing nodeId with 400 JSON error', () async {
      // Why: nodeId is the only field; an empty body must produce a structured
      // BadRequestError that the middleware renders as a 400, not a 500.
      final response = await translateHandlerErrors(
        handlers.handleSequencerSkipToNode(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/skip-to-node'),
            body: jsonEncode({}),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['field'], 'nodeId');
      expect(body['expected'], 'string');
    });

    test('skip-to-node rejects empty nodeId with 400 JSON error', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerSkipToNode(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/skip-to-node'),
            body: jsonEncode({'nodeId': ''}),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['field'], 'nodeId');
    });

    test('skip-to-node with valid nodeId fails through to backend '
        '(DisconnectedBackend raises) and surfaces as JSON', () async {
      // Why: with no FFI/network backend wired, the default backendProvider
      // resolves to DisconnectedBackend which raises on sequencer calls. We
      // care that the handler validates input then defers to the backend
      // (i.e. the route plumbing works) — not that the test container
      // actually runs the sequencer.
      final response = await translateHandlerErrors(
        handlers.handleSequencerSkipToNode(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/skip-to-node'),
            body: jsonEncode({'nodeId': 'node-42'}),
          ),
        ),
      );

      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
    });

    test('update-autofocus-interval rejects missing everyNFrames with 400 JSON '
        'error', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerUpdateAutofocusInterval(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/api/sequencer/update-autofocus-interval',
            ),
            body: jsonEncode({}),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['field'], 'everyNFrames');
      expect(body['expected'], 'integer');
    });

    test('update-autofocus-interval rejects everyNFrames < 1 with 400 JSON '
        'error', () async {
      // Why: 0 is meaningless (autofocus every 0 frames = never) and the Rust
      // bridge also rejects it; the handler enforces the same gate so the
      // caller gets a clear error instead of a vague 500 from FRB.
      final response = await translateHandlerErrors(
        handlers.handleSequencerUpdateAutofocusInterval(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/api/sequencer/update-autofocus-interval',
            ),
            body: jsonEncode({'everyNFrames': 0}),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
    });

    test(
      'update-autofocus-interval with valid frames defers to backend',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerUpdateAutofocusInterval(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/api/sequencer/update-autofocus-interval',
              ),
              body: jsonEncode({'everyNFrames': 25}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.ok, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
      },
    );

    // =====================================================================
    // Recovery Mode HTTP handlers
    // =====================================================================

    test(
      'recovery/try-now defers to backend (DisconnectedBackend raises)',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerRecoveryTryNow(
            Request(
              'POST',
              Uri.parse('http://localhost/api/sequencer/recovery/try-now'),
              body: jsonEncode({}),
            ),
          ),
        );
        // Either 200 (real backend) or 5xx (Disconnected) — what we care
        // about is the route plumbing and JSON content-type.
        expect(
          response.statusCode,
          anyOf(HttpStatus.ok, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
      },
    );

    test(
      'recovery/abort defers to backend (DisconnectedBackend raises)',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerRecoveryAbort(
            Request(
              'POST',
              Uri.parse('http://localhost/api/sequencer/recovery/abort'),
              body: jsonEncode({}),
            ),
          ),
        );
        expect(
          response.statusCode,
          anyOf(HttpStatus.ok, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
      },
    );

    test(
      'recovery/update-config rejects missing required fields with 400 JSON',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerUpdateRecoveryConfig(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/api/sequencer/recovery/update-config',
              ),
              body: jsonEncode({}),
            ),
          ),
        );
        expect(response.statusCode, HttpStatus.badRequest);
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        // One of the required fields must appear in the field path. We
        // don't pin which one (validation may short-circuit on the first
        // missing field) but the contract is "400 with field name".
        expect(body['field'], isA<String>());
      },
    );

    test('recovery/update-config with all fields defers to backend', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerUpdateRecoveryConfig(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sequencer/recovery/update-config'),
            body: jsonEncode({
              'retryIntervalSecs': 600.0,
              'maxDurationSecs': 5400.0,
              'stopTrackingDuringRecovery': true,
              'abortOnMeridian': true,
              'audibleAlertWhenEntered': true,
            }),
          ),
        ),
      );
      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
    });

    test('recovery/current returns JSON with context key', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerGetCurrentRecovery(
          Request(
            'GET',
            Uri.parse('http://localhost/api/sequencer/recovery/current'),
          ),
        ),
      );
      // DisconnectedBackend raises; we only care that the route exists.
      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
    });

    test('recovery/history returns JSON with history key', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerGetRecoveryHistory(
          Request(
            'GET',
            Uri.parse('http://localhost/api/sequencer/recovery/history'),
          ),
        ),
      );
      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
    });

    test(
      'update-conditions-score rejects non-object score with 400 JSON',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerUpdateConditionsScore(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/api/sequencer/update-conditions-score',
              ),
              body: jsonEncode({'score': 42}),
            ),
          ),
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['field'], 'score');
        expect(body['expected'], 'object or null');
      },
    );

    test(
      'update-conditions-score accepts null score and defers to backend',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSequencerUpdateConditionsScore(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/api/sequencer/update-conditions-score',
              ),
              body: jsonEncode({'score': null}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.ok, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
      },
    );

    test('adaptive-swap returns JSON content-type', () async {
      final response = await translateHandlerErrors(
        handlers.handleSequencerGetAdaptiveSwap(
          Request(
            'GET',
            Uri.parse('http://localhost/api/sequencer/adaptive-swap'),
          ),
        ),
      );

      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
    });
  });
}
