import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_core/src/models/weather/weather_models.dart';
import 'package:nightshade_core/src/services/weather/providers/rainviewer_radar_provider.dart';

void main() {
  group('RainViewerRadarProvider', () {
    late RainViewerRadarProvider provider;

    // Sample API response mimicking RainViewer structure
    final sampleApiResponse = {
      'version': '2.0',
      'generated': 1234567890,
      'host': 'https://tilecache.rainviewer.com',
      'radar': {
        'past': [
          {
            'time': 1234567200,
            'path': '/v2/radar/1234567200/256/{z}/{x}/{y}/2/1_1.png'
          },
          {
            'time': 1234567800,
            'path': '/v2/radar/1234567800/256/{z}/{x}/{y}/2/1_1.png'
          },
          {
            'time': 1234568400,
            'path': '/v2/radar/1234568400/256/{z}/{x}/{y}/2/1_1.png'
          },
        ],
        'nowcast': [
          {
            'time': 1234569000,
            'path': '/v2/radar/1234569000/256/{z}/{x}/{y}/2/1_1.png'
          },
          {
            'time': 1234569600,
            'path': '/v2/radar/1234569600/256/{z}/{x}/{y}/2/1_1.png'
          },
        ],
      },
    };

    setUp(() {
      // Provider is created fresh for each test
    });

    tearDown(() {
      provider.dispose();
    });

    test('provider metadata is correct', () {
      provider = RainViewerRadarProvider();

      expect(provider.name, equals('RainViewer'));
      expect(provider.providerType, equals(RadarProviderType.rainviewer));
      expect(provider.coverageBounds.north, equals(90.0));
      expect(provider.coverageBounds.south, equals(-90.0));
      expect(provider.coverageBounds.east, equals(180.0));
      expect(provider.coverageBounds.west, equals(-180.0));
    });

    test('coversLocation returns true for any location (global coverage)', () {
      provider = RainViewerRadarProvider();

      // Test various locations around the world
      expect(provider.coversLocation(40.7128, -74.0060), isTrue); // New York
      expect(provider.coversLocation(51.5074, -0.1278), isTrue); // London
      expect(provider.coversLocation(-33.8688, 151.2093), isTrue); // Sydney
      expect(provider.coversLocation(35.6762, 139.6503), isTrue); // Tokyo
      expect(provider.coversLocation(0, 0), isTrue); // Null Island
      expect(provider.coversLocation(90, 180), isTrue); // Extreme corners
      expect(provider.coversLocation(-90, -180), isTrue);
    });

    test('getAvailableTimeRange returns correct durations', () {
      provider = RainViewerRadarProvider();

      final (history, forecast) = provider.getAvailableTimeRange();

      expect(history, equals(const Duration(hours: 2)));
      expect(forecast, equals(const Duration(minutes: 30)));
    });

    test('buildTileUrl replaces placeholders correctly', () {
      provider = RainViewerRadarProvider();

      final frame = RadarFrame(
        timestamp: DateTime.now(),
        tileUrlTemplate:
            'https://tilecache.rainviewer.com/v2/radar/1234567890/256/{z}/{x}/{y}/2/1_1.png',
        north: 90.0,
        south: -90.0,
        east: 180.0,
        west: -180.0,
      );

      final url = provider.buildTileUrl(frame, 8, 123, 456);

      expect(
        url,
        equals(
          'https://tilecache.rainviewer.com/v2/radar/1234567890/256/8/123/456/2/1_1.png',
        ),
      );
    });

    test('fetchRadarFrames parses successful API response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(json.encode(sampleApiResponse), 200);
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.frames.length, equals(5)); // 3 past + 2 nowcast

      // Check historical frames
      final pastFrames = result.frames.where((f) => !f.isForecast).toList();
      expect(pastFrames.length, equals(3));
      expect(pastFrames[0].opacity, equals(1.0));
      expect(
        pastFrames[0].tileUrlTemplate,
        equals(
          'https://tilecache.rainviewer.com/v2/radar/1234567200/256/{z}/{x}/{y}/2/1_1.png',
        ),
      );

      // Check nowcast frames
      final nowcastFrames = result.frames.where((f) => f.isForecast).toList();
      expect(nowcastFrames.length, equals(2));
      expect(nowcastFrames[0].opacity, equals(0.85));
      expect(nowcastFrames[0].isForecast, isTrue);

      // Verify frames are sorted by timestamp
      for (int i = 0; i < result.frames.length - 1; i++) {
        expect(
          result.frames[i].timestamp.isBefore(result.frames[i + 1].timestamp) ||
              result.frames[i]
                  .timestamp
                  .isAtSameMomentAs(result.frames[i + 1].timestamp),
          isTrue,
        );
      }

      // Verify global bounds on all frames
      for (final frame in result.frames) {
        expect(frame.north, equals(90.0));
        expect(frame.south, equals(-90.0));
        expect(frame.east, equals(180.0));
        expect(frame.west, equals(-180.0));
      }
    });

    test('fetchRadarFrames handles HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('404'));
      expect(result.frames, isEmpty);
    });

    test('fetchRadarFrames handles malformed JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{ invalid json', 200);
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('parse'));
      expect(result.frames, isEmpty);
    });

    test('fetchRadarFrames handles missing radar data', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'version': '2.0',
            'generated': 1234567890,
            'host': 'https://tilecache.rainviewer.com',
            // Missing 'radar' field
          }),
          200,
        );
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('missing radar data'));
    });

    test('fetchRadarFrames handles empty radar data', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'version': '2.0',
            'generated': 1234567890,
            'host': 'https://tilecache.rainviewer.com',
            'radar': {
              'past': [],
              'nowcast': [],
            },
          }),
          200,
        );
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('no radar frames'));
    });

    test('fetchRadarFrames handles network exception', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Network unreachable');
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('Network error'));
    });

    test('fetchRadarFrames handles missing timestamps gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'version': '2.0',
            'generated': 1234567890,
            'host': 'https://tilecache.rainviewer.com',
            'radar': {
              'past': [
                {
                  'time': 1234567200,
                  'path': '/v2/radar/1234567200/256/{z}/{x}/{y}/2/1_1.png'
                },
                {
                  // Missing 'time' field - should be skipped
                  'path': '/v2/radar/1234567800/256/{z}/{x}/{y}/2/1_1.png'
                },
                {
                  'time': 1234568400,
                  // Missing 'path' field - should be skipped
                },
              ],
              'nowcast': [],
            },
          }),
          200,
        );
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isTrue);
      expect(result.frames.length, equals(1)); // Only one valid frame
    });

    test('dispose closes HTTP client', () {
      provider = RainViewerRadarProvider();

      // Should not throw
      expect(() => provider.dispose(), returnsNormally);
    });

    test('timestamp conversion from Unix seconds is correct', () async {
      final mockClient = MockClient((request) async {
        return http.Response(json.encode(sampleApiResponse), 200);
      });

      provider = RainViewerRadarProvider(httpClient: mockClient);

      final result = await provider.fetchRadarFrames(
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(result.isSuccess, isTrue);

      // Check that first frame's timestamp matches expected conversion
      final firstFrame = result.frames.first;
      final expectedTimestamp =
          DateTime.fromMillisecondsSinceEpoch(1234567200 * 1000);
      expect(firstFrame.timestamp, equals(expectedTimestamp));
    });
  });
}
