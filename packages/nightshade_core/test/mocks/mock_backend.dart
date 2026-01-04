import 'dart:async';
import 'dart:typed_data';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/imaging/imaging_models.dart';
import 'package:nightshade_core/src/models/equipment_profile.dart';

/// Mock implementation of NightshadeBackend for testing
class MockBackend extends Mock implements NightshadeBackend {}

/// Test fixtures and helper data for common test scenarios
class TestFixtures {
  /// Default camera device ID
  static const String cameraId = 'test-camera-1';

  /// Default mount device ID
  static const String mountId = 'test-mount-1';

  /// Default focuser device ID
  static const String focuserId = 'test-focuser-1';

  /// Default filter wheel device ID
  static const String filterWheelId = 'test-filterwheel-1';

  /// Default dome device ID
  static const String domeId = 'test-dome-1';

  /// Default weather device ID
  static const String weatherId = 'test-weather-1';

  /// Default safety monitor device ID
  static const String safetyMonitorId = 'test-safety-1';

  /// Sample image statistics
  static const ImageStats sampleImageStats = ImageStats(
    mean: 1500.0,
    median: 1450.0,
    stdDev: 250.0,
    min: 100.0,
    max: 65535.0,
    mad: 200.0,
    snr: 6.0,
    starCount: 125,
    hfr: 2.5,
    fwhm: 3.2,
  );

  /// Sample exposure settings
  static const ExposureSettings sampleExposureSettings = ExposureSettings(
    exposureTime: 120.0,
    gain: 100,
    offset: 50,
    binningX: 1,
    binningY: 1,
    frameType: FrameType.light,
  );

  /// Sample equipment profile
  static EquipmentProfile sampleProfile() {
    return EquipmentProfile(
      id: 'test-profile-1',
      name: 'Test Equipment Profile',
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterWheelId: filterWheelId,
      rotatorId: null,
      domeId: null,
      weatherId: null,
      coverCalibratorId: null,
      isActive: true,
      updatedAt: DateTime(2024, 1, 1),
    );
  }

  /// Sample 16-bit grayscale image data (100x100 pixels)
  static Uint16List sampleImageData() {
    final data = Uint16List(100 * 100);
    // Create a simple gradient pattern
    for (int y = 0; y < 100; y++) {
      for (int x = 0; x < 100; x++) {
        final index = y * 100 + x;
        // Create a gradient from 1000 to 2000 ADU
        data[index] = 1000 + ((x + y) * 5);
      }
    }
    return data;
  }

  /// Sample filter names
  static const List<String> sampleFilterNames = [
    'Luminance',
    'Red',
    'Green',
    'Blue',
    'Ha',
    'OIII',
    'SII',
  ];

  /// Creates a mock backend with default successful responses
  static MockBackend createMockBackendWithDefaults() {
    final backend = MockBackend();

    // Setup default successful connection responses
    when(() => backend.connectDevice(any(), any())).thenAnswer((_) async {});
    when(() => backend.disconnectDevice(any(), any())).thenAnswer((_) async {});

    // Setup default event stream (empty stream)
    when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
    when(() => backend.polarAlignmentEvents).thenAnswer((_) => const Stream.empty());

    return backend;
  }

  /// Creates a mock backend that simulates connection failures
  static MockBackend createMockBackendWithConnectionFailure() {
    final backend = MockBackend();

    // All connection attempts fail
    when(() => backend.connectDevice(any(), any()))
        .thenThrow(Exception('Failed to connect to device'));

    when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
    when(() => backend.polarAlignmentEvents).thenAnswer((_) => const Stream.empty());

    return backend;
  }

  /// Creates a mock backend that simulates timeout errors
  static MockBackend createMockBackendWithTimeout() {
    final backend = MockBackend();

    // All operations timeout
    when(() => backend.connectDevice(any(), any()))
        .thenThrow(Exception('Connection timeout'));

    when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
    when(() => backend.polarAlignmentEvents).thenAnswer((_) => const Stream.empty());

    return backend;
  }
}

/// Register mocktail fallback values for testing
void registerMocktailFallbackValues() {
  registerFallbackValue(FrameType.light);
  registerFallbackValue(DeviceType.camera);
  registerFallbackValue(DriverType.simulator);
  registerFallbackValue(const ExposureSettings(
    exposureTime: 1.0,
    gain: 0,
    offset: 0,
    binningX: 1,
    binningY: 1,
    frameType: FrameType.light,
  ));
  registerFallbackValue(DeviceInfo(
    id: 'fallback',
    name: 'Fallback',
    deviceType: DeviceType.camera,
    driverType: DriverType.simulator,
    description: '',
    driverVersion: '1.0',
  ));
}
