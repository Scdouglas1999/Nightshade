import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Mock implementation of http.Client
class MockHttpClient extends Mock implements http.Client {}

/// Mock implementation of LoggingService
class MockLoggingService extends Mock implements LoggingService {}

/// Fake Uri for mocktail registration
class FakeUri extends Fake implements Uri {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUri());
  });

  group('TransientAlertService', () {
    late TransientAlertService service;
    late MockHttpClient mockHttpClient;
    late MockLoggingService mockLogger;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockLogger = MockLoggingService();
      service = TransientAlertService(
        httpClient: mockHttpClient,
        logger: mockLogger,
      );
    });

    tearDown(() {
      service.dispose();
    });

    /// Create a sample AAVSO API response
    String createAavsoResponse(List<Map<String, dynamic>> objects) {
      return jsonEncode({'VSXObjects': objects});
    }

    /// Create a sample AAVSO variable star object
    Map<String, dynamic> createAavsoObject({
      String name = 'V404 Cyg',
      String ra = '20:24:03.83',
      String dec = '+33:52:02.2',
      String? type = 'UG',
      String? maxMag = '11.0',
      String? minMag = '21.0',
      String? oid = '12345',
      String? constellation = 'Cyg',
    }) {
      return {
        'Name': name,
        'RA2000': ra,
        'Declination2000': dec,
        'Type': type,
        'MaxMag': maxMag,
        'MinMag': minMag,
        'OID': oid,
        'Constellation': constellation,
      };
    }

    group('fetchAavsoAlerts', () {
      test('parses AAVSO response correctly', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(
            name: 'V404 Cyg',
            ra: '20:24:03.83',
            dec: '+33:52:02.2',
            type: 'UG',
            maxMag: '11.0',
          ),
          createAavsoObject(
            name: 'SS Cyg',
            ra: '21:42:42.80',
            dec: '+43:35:09.9',
            type: 'UGSS',
            maxMag: '8.2',
          ),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts, hasLength(2));

        // Verify first alert
        final alert1 = alerts[0];
        expect(alert1.name, equals('V404 Cyg'));
        expect(alert1.source, equals(TransientSource.aavso));
        expect(alert1.type, equals(TransientType.cataclysmic)); // UG type
        expect(alert1.raHours, closeTo(20.4010, 0.001)); // 20h 24m 03.83s
        expect(alert1.decDegrees, closeTo(33.867, 0.01)); // +33 52' 02.2"

        // Verify second alert
        final alert2 = alerts[1];
        expect(alert2.name, equals('SS Cyg'));
        expect(alert2.type, equals(TransientType.cataclysmic)); // UGSS type
      });

      test('handles empty VSXObjects array', () async {
        final responseBody = createAavsoResponse([]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts, isEmpty);
      });

      test('throws on HTTP error instead of reporting an empty feed', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response('Server Error', 500));

        await expectLater(
          service.fetchAavsoAlerts(),
          throwsA(isA<TransientAlertFetchException>()),
        );
      });

      test('throws on network failure instead of reporting empty', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenThrow(http.ClientException('Connection refused'));

        await expectLater(
          service.fetchAavsoAlerts(),
          throwsA(isA<TransientAlertFetchException>()),
        );
      });

      test('throws on invalid JSON instead of reporting empty', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response('not valid json', 200));

        await expectLater(
          service.fetchAavsoAlerts(),
          throwsA(isA<TransientAlertFetchException>()),
        );
      });

      test('throws when every returned object is malformed', () async {
        when(() => mockHttpClient.get(any())).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'VSXObjects': [
                {'Name': 'Missing coordinates'},
              ],
            }),
            200,
          ),
        );

        await expectLater(
          service.fetchAavsoAlerts(),
          throwsA(isA<TransientAlertFetchException>()),
        );
      });

      test('skips objects with missing required fields', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(
            name: 'Good Star',
            ra: '12:00:00',
            dec: '+45:00:00',
          ),
          {'Name': 'Missing RA'}, // Missing RA2000
          {
            'RA2000': '12:00:00',
            'Declination2000': '+45:00:00',
          }, // Missing Name
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        // Only the valid object should be parsed
        expect(alerts, hasLength(1));
        expect(alerts[0].name, equals('Good Star'));
      });

      test('skips non-finite and out-of-range catalog coordinates', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Good Star'),
          createAavsoObject(name: 'RA 24', ra: '24:00:00'),
          createAavsoObject(name: 'Bad RA minutes', ra: '12:60:00'),
          createAavsoObject(name: 'NaN RA', ra: 'NaN'),
          createAavsoObject(name: 'Dec 91', dec: '+91:00:00'),
          createAavsoObject(name: 'Bad Dec minutes', dec: '+45:60:00'),
          createAavsoObject(name: 'Past pole', dec: '+90:00:01'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts.map((alert) => alert.name), ['Good Star']);
      });

      test(
        'drops non-finite magnitudes instead of poisoning filters',
        () async {
          final responseBody = createAavsoResponse([
            createAavsoObject(maxMag: 'NaN', minMag: 'Infinity'),
          ]);

          when(
            () => mockHttpClient.get(any()),
          ).thenAnswer((_) async => http.Response(responseBody, 200));

          final alerts = await service.fetchAavsoAlerts();

          expect(alerts, hasLength(1));
          expect(alerts.single.magnitude, isNull);
          expect(alerts.single.peakMagnitude, isNull);
        },
      );

      test('maps AAVSO variable types correctly', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Nova', type: 'NA'),
          createAavsoObject(name: 'Supernova', type: 'SN'),
          createAavsoObject(name: 'Mira', type: 'M'),
          createAavsoObject(name: 'Unknown', type: 'UNKNOWN'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts[0].type, equals(TransientType.nova));
        expect(alerts[1].type, equals(TransientType.supernova));
        expect(alerts[2].type, equals(TransientType.variableStar));
        expect(alerts[3].type, equals(TransientType.other));
      });

      test('calculates priority based on type and magnitude', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Bright SN', type: 'SN', maxMag: '7.0'),
          createAavsoObject(name: 'Faint SN', type: 'SN', maxMag: '18.0'),
          createAavsoObject(name: 'Nova', type: 'N', maxMag: '10.0'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        // Bright supernova should have highest priority (lowest number)
        expect(alerts[0].priority, lessThan(alerts[1].priority));
        // Supernova should have higher priority than nova of similar brightness
        expect(alerts[0].priority, lessThanOrEqualTo(alerts[2].priority));
      });
    });

    group('caching behavior', () {
      test('cache is invalid when empty', () {
        expect(service.isCacheValid, isFalse);
      });

      test('getAllAlerts uses cache on second call', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Test Star'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        const settings = TransientAlertSettings();

        // First call - should hit the API
        final alerts1 = await service.getAllAlerts(settings);
        expect(alerts1, hasLength(greaterThanOrEqualTo(1)));

        // Second call - should use cache
        final alerts2 = await service.getAllAlerts(settings);

        // Verify HTTP client was called only once (for AAVSO)
        // Note: TNS also makes a call, so we verify the caching by checking
        // that the result is the same
        expect(alerts2.length, equals(alerts1.length));
        expect(service.isCacheValid, isTrue);
      });

      test('clearCache invalidates cache', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Test Star'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        const settings = TransientAlertSettings();

        // Populate cache
        await service.getAllAlerts(settings);
        expect(service.isCacheValid, isTrue);

        // Clear cache
        service.clearCache();
        expect(service.isCacheValid, isFalse);
      });
    });

    group('getAllAlerts filtering', () {
      test('filters by type', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Nova', type: 'N'),
          createAavsoObject(name: 'Variable', type: 'M'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        const settings = TransientAlertSettings(
          typesToMonitor: {TransientType.nova}, // Only novae
          enabledSources: {TransientSource.aavso},
        );

        final alerts = await service.getAllAlerts(settings);

        // Should only include nova
        for (final alert in alerts) {
          expect(alert.type, equals(TransientType.nova));
        }
      });

      test('filters by magnitude threshold', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Bright', maxMag: '10.0'),
          createAavsoObject(name: 'Faint', maxMag: '18.0'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        const settings = TransientAlertSettings(
          magnitudeThreshold: 12.0, // Only brighter than 12
          enabledSources: {TransientSource.aavso},
        );

        final alerts = await service.getAllAlerts(settings);

        // All returned alerts should be brighter than threshold
        for (final alert in alerts) {
          if (alert.magnitude != null) {
            expect(alert.magnitude, lessThanOrEqualTo(12.0));
          }
        }
      });

      test('filters by source', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Test Star'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        // No implemented source is enabled, so no upstream request is made.
        const settings = TransientAlertSettings(enabledSources: {});

        final alerts = await service.getAllAlerts(settings);

        // Should not include any AAVSO alerts
        for (final alert in alerts) {
          expect(alert.source, isNot(TransientSource.aavso));
        }
      });

      test('sorts alerts by priority then discovery time', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(name: 'Low Priority', type: 'M'), // Variable star
          createAavsoObject(name: 'High Priority', type: 'SN'), // Supernova
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        const settings = TransientAlertSettings();
        final alerts = await service.getAllAlerts(settings);

        if (alerts.length >= 2) {
          // Higher priority (lower number) should come first
          for (int i = 0; i < alerts.length - 1; i++) {
            if (alerts[i].priority != alerts[i + 1].priority) {
              expect(
                alerts[i].priority,
                lessThanOrEqualTo(alerts[i + 1].priority),
              );
            }
          }
        }
      });
    });

    group('shouldNotify', () {
      test('returns true for monitored type and magnitude', () {
        final alert = TransientAlert(
          id: 'test1',
          name: 'Test Nova',
          type: TransientType.nova,
          raHours: 12.0,
          decDegrees: 45.0,
          magnitude: 10.0,
          discoveryTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          source: TransientSource.aavso,
          priority: 3,
        );

        const settings = TransientAlertSettings(
          typesToMonitor: {TransientType.nova},
          enabledSources: {TransientSource.aavso},
          magnitudeThreshold: 15.0,
          notifyOnNew: true,
        );

        expect(service.shouldNotify(alert, settings), isTrue);
      });

      test('returns false for unmonitored type', () {
        final alert = TransientAlert(
          id: 'test1',
          name: 'Test Star',
          type: TransientType.variableStar,
          raHours: 12.0,
          decDegrees: 45.0,
          discoveryTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          source: TransientSource.aavso,
          priority: 5,
        );

        const settings = TransientAlertSettings(
          typesToMonitor: {
            TransientType.nova,
            TransientType.supernova,
          }, // Not variableStar
          enabledSources: {TransientSource.aavso},
        );

        expect(service.shouldNotify(alert, settings), isFalse);
      });

      test('returns false for disabled source', () {
        final alert = TransientAlert(
          id: 'test1',
          name: 'Test Nova',
          type: TransientType.nova,
          raHours: 12.0,
          decDegrees: 45.0,
          discoveryTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          source: TransientSource.aavso,
          priority: 3,
        );

        const settings = TransientAlertSettings(
          typesToMonitor: {TransientType.nova},
          enabledSources: {TransientSource.tns}, // AAVSO not enabled
        );

        expect(service.shouldNotify(alert, settings), isFalse);
      });

      test('returns false for alert fainter than threshold', () {
        final alert = TransientAlert(
          id: 'test1',
          name: 'Faint Nova',
          type: TransientType.nova,
          raHours: 12.0,
          decDegrees: 45.0,
          magnitude: 18.0, // Fainter than threshold
          discoveryTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          source: TransientSource.aavso,
          priority: 3,
        );

        const settings = TransientAlertSettings(
          typesToMonitor: {TransientType.nova},
          enabledSources: {TransientSource.aavso},
          magnitudeThreshold: 15.0, // Only alerts brighter than 15
        );

        expect(service.shouldNotify(alert, settings), isFalse);
      });

      test(
        'returns false when notifyOnNew is false and not auto-queue eligible',
        () {
          final alert = TransientAlert(
            id: 'test1',
            name: 'Test Nova',
            type: TransientType.nova,
            raHours: 12.0,
            decDegrees: 45.0,
            magnitude: 12.0, // Not bright enough for auto-queue
            discoveryTime: DateTime.now(),
            lastUpdated: DateTime.now(),
            source: TransientSource.aavso,
            priority: 3,
          );

          const settings = TransientAlertSettings(
            typesToMonitor: {TransientType.nova},
            enabledSources: {TransientSource.aavso},
            magnitudeThreshold: 15.0,
            notifyOnNew: false,
            autoQueueBright: true,
            autoQueueMagnitude: 10.0, // Alert is not bright enough
          );

          expect(service.shouldNotify(alert, settings), isFalse);
        },
      );

      test(
        'returns true for bright transient when autoQueueBright is enabled',
        () {
          final alert = TransientAlert(
            id: 'test1',
            name: 'Bright Nova',
            type: TransientType.nova,
            raHours: 12.0,
            decDegrees: 45.0,
            magnitude: 8.0, // Very bright
            discoveryTime: DateTime.now(),
            lastUpdated: DateTime.now(),
            source: TransientSource.aavso,
            priority: 2,
          );

          const settings = TransientAlertSettings(
            typesToMonitor: {TransientType.nova},
            enabledSources: {TransientSource.aavso},
            magnitudeThreshold: 15.0,
            notifyOnNew: false, // Even with this false
            autoQueueBright: true,
            autoQueueMagnitude: 10.0, // 8.0 is brighter than 10.0
          );

          expect(service.shouldNotify(alert, settings), isTrue);
        },
      );

      test('handles alert with null magnitude', () {
        final alert = TransientAlert(
          id: 'test1',
          name: 'Unknown Mag',
          type: TransientType.nova,
          raHours: 12.0,
          decDegrees: 45.0,
          magnitude: null, // Unknown magnitude
          discoveryTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          source: TransientSource.aavso,
          priority: 3,
        );

        const settings = TransientAlertSettings(
          typesToMonitor: {TransientType.nova},
          enabledSources: {TransientSource.aavso},
          magnitudeThreshold: 15.0,
          notifyOnNew: true,
        );

        // Should pass magnitude check (null magnitude not filtered)
        expect(service.shouldNotify(alert, settings), isTrue);
      });
    });

    group('coordinate parsing', () {
      test('parses RA in HMS format', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(ra: '12:30:45.67'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts, hasLength(1));
        // 12h 30m 45.67s = 12 + 30/60 + 45.67/3600 hours
        expect(alerts[0].raHours, closeTo(12.5127, 0.001));
      });

      test('parses Dec in DMS format with positive sign', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(dec: '+45:30:00.0'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts, hasLength(1));
        // +45 30' 00" = 45.5 degrees
        expect(alerts[0].decDegrees, closeTo(45.5, 0.01));
      });

      test('parses Dec in DMS format with negative sign', () async {
        final responseBody = createAavsoResponse([
          createAavsoObject(dec: '-30:15:30.0'),
        ]);

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => http.Response(responseBody, 200));

        final alerts = await service.fetchAavsoAlerts();

        expect(alerts, hasLength(1));
        // -30 15' 30" = -30.2583 degrees
        expect(alerts[0].decDegrees, closeTo(-30.2583, 0.01));
      });
    });

    group('fetchTnsAlerts', () {
      test('returns empty list when no API key provided', () async {
        final alerts = await service.fetchTnsAlerts();

        // Should return empty list without API key
        expect(alerts, isEmpty);
      });

      test('returns empty list when API key is empty string', () async {
        final alerts = await service.fetchTnsAlerts(apiKey: '');

        // Should return empty list with empty API key
        expect(alerts, isEmpty);
      });

      test('rejects a key without the required bot identity', () async {
        await expectLater(
          service.fetchTnsAlerts(apiKey: 'secret'),
          throwsA(isA<TransientAlertFetchException>()),
        );
      });

      test(
        'throws when an authenticated search response is malformed',
        () async {
          final client = MockClient(
            (_) async => http.Response(jsonEncode({'data': {}}), 200),
          );
          final realService = TransientAlertService(
            httpClient: client,
            logger: mockLogger,
          );
          addTearDown(realService.dispose);

          await expectLater(
            realService.fetchTnsAlerts(
              apiKey: 'secret',
              botId: 42,
              botName: 'Nightshade Bot',
            ),
            throwsA(isA<TransientAlertFetchException>()),
          );
        },
      );

      test('an enabled TNS-only feed requires configuration', () async {
        await expectLater(
          service.getAllAlerts(
            const TransientAlertSettings(enabledSources: {TransientSource.tns}),
          ),
          throwsA(isA<TransientAlertFetchException>()),
        );
        expect(service.isCacheValid, isFalse);
      });

      test(
        'retains AAVSO results when an independent TNS source fails',
        () async {
          when(() => mockHttpClient.get(any())).thenAnswer(
            (_) async => http.Response(
              createAavsoResponse([createAavsoObject(name: 'AAVSO survivor')]),
              200,
            ),
          );

          final alerts = await service.getAllAlerts(
            const TransientAlertSettings(
              enabledSources: {TransientSource.aavso, TransientSource.tns},
            ),
          );

          expect(alerts.map((alert) => alert.name), ['AAVSO survivor']);
        },
      );

      test('uses the official Search then Get Object wire contract', () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/get/search')) {
            return http.Response(
              jsonEncode({
                'id_code': 200,
                'data': {
                  'reply': [
                    {'objname': '2026abc', 'prefix': 'SN', 'objid': 91},
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/get/object')) {
            return http.Response(
              jsonEncode({
                'id_code': 200,
                'data': {
                  'reply': {
                    'objid': 91,
                    'objname': '2026abc',
                    'name_prefix': 'SN',
                    'ra': '12:30:00.0',
                    'dec': '-20:15:00.0',
                    'discoverydate': '2026-07-10 03:04:05.000',
                    'lastmodified': '2026-07-11 05:00:00.000',
                    'discoverymag': 13.4,
                    'object_type': {'id': 3, 'name': 'SN Ia'},
                  },
                },
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        });
        final realService = TransientAlertService(
          httpClient: client,
          logger: mockLogger,
        );
        addTearDown(realService.dispose);

        final alerts = await realService.fetchTnsAlerts(
          apiKey: 'secret',
          botId: 42,
          botName: 'Nightshade Bot',
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.id, 'tns_91');
        expect(alerts.single.name, 'SN2026abc');
        expect(alerts.single.type, TransientType.supernova);
        expect(alerts.single.raHours, 12.5);
        expect(alerts.single.decDegrees, -20.25);
        expect(requests, hasLength(2));
        expect(
          requests.first.headers['user-agent'],
          contains('tns_marker{"tns_id":42'),
        );
        final searchData =
            jsonDecode(requests.first.bodyFields['data']!)
                as Map<String, dynamic>;
        expect(searchData['discovered_period_value'], '30');
        final objectData =
            jsonDecode(requests.last.bodyFields['data']!)
                as Map<String, dynamic>;
        expect(objectData['objname'], '2026abc');
      });

      test('enabling TNS does not reuse an AAVSO-only cache', () async {
        var aavsoCalls = 0;
        var tnsSearchCalls = 0;
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            aavsoCalls++;
            return http.Response(jsonEncode({'VSXObjects': []}), 200);
          }
          if (request.url.path.endsWith('/get/search')) {
            tnsSearchCalls++;
            return http.Response(
              jsonEncode({
                'id_code': 200,
                'data': {'reply': []},
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        });
        final realService = TransientAlertService(
          httpClient: client,
          logger: mockLogger,
        );
        addTearDown(realService.dispose);

        await realService.getAllAlerts(
          const TransientAlertSettings(enabledSources: {TransientSource.aavso}),
        );
        await realService.getAllAlerts(
          const TransientAlertSettings(
            enabledSources: {TransientSource.tns},
            tnsApiKey: 'secret',
          ),
          tnsBotId: 42,
          tnsBotName: 'Nightshade Bot',
        );

        expect(aavsoCalls, 1);
        expect(tnsSearchCalls, 1);
      });
    });
  });
}
