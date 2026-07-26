import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/analytics_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('AnalyticsHandlers', () {
    late ProviderContainer container;
    late AnalyticsHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = AnalyticsHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('invalid session ID returns JSON internal error', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetSessionById(
          Request('GET', Uri.parse('http://localhost/api/sessions/not-an-id')),
          'not-an-id',
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

    test(
      'update session malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleUpdateSession(
            Request(
              'PUT',
              Uri.parse('http://localhost/api/sessions/1'),
              body: '{',
            ),
            '1',
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

    test('invalid target statistics ID returns JSON internal error', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetTargetStatistics(
          Request(
            'GET',
            Uri.parse('http://localhost/api/analytics/target/not-an-id'),
          ),
          'not-an-id',
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

    test(
      'recent-session limit rejects supplied-invalid values before DB work',
      () async {
        final guarded = ProviderContainer(
          overrides: [
            databaseProvider.overrideWith(
              (ref) => throw StateError('database must not be resolved'),
            ),
          ],
        );
        addTearDown(guarded.dispose);
        final guardedHandlers = AnalyticsHandlers(guarded);

        for (final raw in ['abc', '0', '-1', '1001', '1.5']) {
          final response = await translateHandlerErrors(
            guardedHandlers.handleGetRecentSessions(
              Request(
                'GET',
                Uri.parse(
                  'http://localhost/api/sessions/recent?limit='
                  '${Uri.encodeQueryComponent(raw)}',
                ),
              ),
            ),
          );
          expect(response.statusCode, HttpStatus.badRequest, reason: raw);
          final body = jsonDecode(await response.readAsString()) as Map;
          expect(body['field'], 'limit', reason: raw);
        }
      },
    );

    test('summary and integration endpoints honor their date range', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final rangedContainer = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(rangedContainer.dispose);
      final rangedHandlers = AnalyticsHandlers(rangedContainer);

      Future<void> seed(
        DateTime startTime, {
        required int exposures,
        required double integrationSeconds,
      }) {
        return database
            .into(database.imagingSessions)
            .insert(
              ImagingSessionsCompanion.insert(
                startTime: startTime,
                totalExposures: Value(exposures),
                totalIntegrationSecs: Value(integrationSeconds),
              ),
            )
            .then((_) {});
      }

      await seed(
        DateTime.utc(2026, 6, 15),
        exposures: 10,
        integrationSeconds: 3600,
      );
      await seed(
        DateTime.utc(2026, 7, 15),
        exposures: 20,
        integrationSeconds: 7200,
      );
      await seed(
        DateTime.utc(2026, 8, 15),
        exposures: 30,
        integrationSeconds: 10800,
      );

      final summaryResponse = await rangedHandlers.handleGetAnalyticsSummary(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/analytics/summary?'
            'startDate=2026-07-01T00%3A00%3A00Z&'
            'endDate=2026-07-31T23%3A59%3A59Z',
          ),
        ),
      );
      final summaryBody =
          jsonDecode(await summaryResponse.readAsString()) as Map;
      final summary = summaryBody['summary'] as Map;
      expect(summary['totalSessions'], 1);
      expect(summary['sessionsInRange'], 1);
      expect(summary['totalExposures'], 20);
      expect(summary['totalIntegrationHours'], 2.0);

      // Older companion builds send epoch milliseconds. A one-sided range is
      // still a real range and must not silently become an all-time total.
      final startEpoch = DateTime.utc(2026, 7, 1).millisecondsSinceEpoch;
      final integrationResponse = await rangedHandlers
          .handleGetTotalIntegrationTime(
            Request(
              'GET',
              Uri.parse(
                'http://localhost/api/analytics/integration-time?'
                'startDate=$startEpoch',
              ),
            ),
          );
      final integration =
          jsonDecode(await integrationResponse.readAsString()) as Map;
      expect(integration['totalIntegrationSecs'], 18000.0);
      expect(integration['totalIntegrationHours'], 5.0);
    });

    test('analytics rejects a reversed date range before DB work', () async {
      final guarded = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith(
            (ref) => throw StateError('database must not be resolved'),
          ),
        ],
      );
      addTearDown(guarded.dispose);
      final guardedHandlers = AnalyticsHandlers(guarded);

      final response = await translateHandlerErrors(
        guardedHandlers.handleGetAnalyticsSummary(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/analytics/summary?'
              'startDate=2026-08-01&endDate=2026-07-01',
            ),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['field'], 'startDate|endDate');
    });

    test('session stats retain the persisted HFR without image rows', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final testContainer = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(testContainer.dispose);
      final testHandlers = AnalyticsHandlers(testContainer);

      final sessionId = await database
          .into(database.imagingSessions)
          .insert(
            ImagingSessionsCompanion.insert(
              startTime: DateTime.utc(2026, 7, 24),
              totalExposures: const Value(2),
              avgHfr: const Value(2.2),
            ),
          );

      final response = await testHandlers.handleGetSessionStats(
        Request(
          'GET',
          Uri.parse('http://localhost/api/sessions/$sessionId/stats'),
        ),
        '$sessionId',
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect((body['stats'] as Map)['avgHfr'], 2.2);
    });

    test('session creation rejects empty and unknown payloads', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final testContainer = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(testContainer.dispose);
      final testHandlers = AnalyticsHandlers(testContainer);

      for (final payload in const [
        <String, Object?>{},
        <String, Object?>{'unexpected': true},
        <String, Object?>{'name': '   '},
      ]) {
        final response = await translateHandlerErrors(
          testHandlers.handleCreateSession(
            Request(
              'POST',
              Uri.parse('http://localhost/api/sessions'),
              body: jsonEncode(payload),
            ),
          ),
        );
        expect(response.statusCode, HttpStatus.badRequest, reason: '$payload');
      }
      expect(await database.sessionsDao.getAllSessions(), isEmpty);
    });

    test('only one imaging session can be active at a time', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final testContainer = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(testContainer.dispose);
      final testHandlers = AnalyticsHandlers(testContainer);

      Future<Response> create(String name) => translateHandlerErrors(
        testHandlers.handleCreateSession(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sessions'),
            body: jsonEncode({'name': name}),
          ),
        ),
      );

      final first = await create('First');
      expect(first.statusCode, HttpStatus.ok);
      final firstId =
          (jsonDecode(await first.readAsString()) as Map)['id'] as int;

      final second = await create('Second');
      expect(second.statusCode, HttpStatus.conflict);
      final body = jsonDecode(await second.readAsString()) as Map;
      expect(body['error'], 'active_session_exists');
      expect(body['activeSessionId'], firstId);
      expect(await database.sessionsDao.getActiveSessions(), hasLength(1));
    });
  });
}
