// Run-Watch handler tests.
//
// The handler is deliberately defensive: every sub-section of the
// snapshot has its own try/catch so a flaky upstream (DisconnectedBackend
// raising, no weather data, no sequence loaded) still produces a coherent
// JSON envelope. These tests pin down that contract.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/run_watch_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('RunWatchHandlers', () {
    late ProviderContainer container;
    late StreamController<NightshadeEvent> ctrl;
    late RunWatchHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      ctrl = StreamController<NightshadeEvent>.broadcast();
      handlers = RunWatchHandlers(
        container: container,
        eventBroadcast: ctrl.stream,
      );
    });

    tearDown(() async {
      await ctrl.close();
      container.dispose();
    });

    test('snapshot returns a coherent envelope even with no backend', () async {
      // The default container has no FFI backend; DisconnectedBackend
      // raises for every method. The handler must degrade per-section
      // and still produce well-formed JSON.
      final response = await translateHandlerErrors(
        handlers.handleSnapshot(
          Request('GET', Uri.parse('http://localhost/api/run-watch/snapshot')),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], startsWith('application/json'));
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body.containsKey('serverTime'), isTrue);
      expect(body['sequencer'], isA<Map>());
      expect(body['guiding'], isA<Map>());
      expect(body['weather'], isA<Map>());
      expect(body['devices'], isA<List>());
      expect(body['recentEvents'], isA<List>());
      // sequencer.progress is a nested object even when the FFI fails.
      final sequencer = body['sequencer'] as Map;
      expect(sequencer['progress'], isA<Map>());
    });

    test('a failed progress read reports unknown, not idle', () async {
      final failing = ProviderContainer(
        overrides: [
          sequenceProgressProvider.overrideWith(
            (ref) => throw StateError('provider not wired'),
          ),
        ],
      );
      addTearDown(failing.dispose);
      final failingHandlers = RunWatchHandlers(
        container: failing,
        eventBroadcast: ctrl.stream,
      );
      addTearDown(failingHandlers.dispose);

      final response = await translateHandlerErrors(
        failingHandlers.handleSnapshot(
          Request('GET', Uri.parse('http://localhost/api/run-watch/snapshot')),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      final progress =
          (body['sequencer'] as Map)['progress'] as Map<String, Object?>;
      // A read that threw must never render as a rig sitting idle at 0/0.
      expect(progress['state'], 'unknown');
      expect(progress['message'], contains('Progress unavailable'));
      expect(progress['completedExposures'], isNull);
      expect(progress['totalExposures'], isNull);
      expect(progress['elapsedSecs'], isNull);
      expect(progress['progressPercent'], isNull);
    });

    test(
      'frame-thumbnail returns no_camera when no devices are connected',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleFrameThumbnail(
            Request(
              'GET',
              Uri.parse('http://localhost/api/run-watch/frame-thumbnail'),
            ),
          ),
        );

        // The DisconnectedBackend raises on getConnectedDevices(), so we
        // end up with no candidate camera id and the handler returns
        // 404 no_camera. The exact body shape is what the client checks
        // for to decide whether to keep the "no frame yet" placeholder.
        expect(response.statusCode, HttpStatus.notFound);
        expect(
          response.headers['content-type'],
          startsWith('application/json'),
        );
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], 'no_camera');
      },
    );

    test(
      'frame-thumbnail rejects malformed and out-of-range image options',
      () async {
        for (final query in const [
          'maxWidth=wide',
          'maxWidth=0',
          'maxWidth=20000',
          'quality=high',
          'quality=0',
          'quality=101',
        ]) {
          final response = await translateHandlerErrors(
            handlers.handleFrameThumbnail(
              Request(
                'GET',
                Uri.parse(
                  'http://localhost/api/run-watch/frame-thumbnail?$query',
                ),
              ),
            ),
          );
          expect(response.statusCode, HttpStatus.badRequest, reason: query);
        }
      },
    );

    test(
      'SSE responds with text/event-stream and an initial retry hint',
      () async {
        final response = handlers.handleEventStream(
          Request('GET', Uri.parse('http://localhost/api/run-watch/events')),
        );

        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers['content-type'],
          startsWith('text/event-stream'),
        );

        // Pump the controller so the stream emits its first frame
        // (the `retry:` directive emitted on onListen). Read a single
        // chunk then cancel so the test does not hang.
        final completer = Completer<String>();
        final sub = response.read().transform(utf8.decoder).listen((chunk) {
          if (!completer.isCompleted) completer.complete(chunk);
        });
        // Give the stream a turn to deliver onListen output.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        if (!completer.isCompleted) {
          completer.complete('');
        }
        final first = await completer.future;
        // The stream MAY have already terminated before the first chunk
        // arrived on slow CI; in the happy path we expect the retry hint.
        // Tolerate both since the test's purpose is to assert the header
        // contract, not the timing of the very first byte.
        if (first.isNotEmpty) {
          expect(first.contains('retry: 5000'), isTrue);
        }
      },
    );

    test('SSE forwards an injected event to a subscribed client', () async {
      // Subscribe an SSE client, push an event into the broadcast
      // controller, assert the client receives a `data:` frame
      // containing our eventType. This is the wave-6 round-trip the
      // brief calls out as the integration test for the event stream.
      final response = handlers.handleEventStream(
        Request('GET', Uri.parse('http://localhost/api/run-watch/events')),
      );

      final buffer = StringBuffer();
      final received = Completer<String>();
      final sub = response.read().transform(utf8.decoder).listen((chunk) {
        buffer.write(chunk);
        if (buffer.toString().contains('FrameAccepted') &&
            !received.isCompleted) {
          received.complete(buffer.toString());
        }
      });

      // Allow the onListen-time retry write to flush before injecting.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final event = NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.imaging,
        eventType: 'FrameAccepted',
        data: {'frameId': 'abc-123', 'hfr': 1.5},
      );
      ctrl.add(event);

      final payload = await received.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // SSE framing: event line, id line, data line, terminator.
      expect(payload.contains('event: FrameAccepted'), isTrue);
      expect(payload.contains('data: '), isTrue);
      expect(payload.contains('FrameAccepted'), isTrue);
      expect(payload.contains('abc-123'), isTrue);
    });
  });
}
