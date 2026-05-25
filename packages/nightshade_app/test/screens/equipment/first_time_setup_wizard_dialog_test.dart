// Tests for the DEV-P2-5 first-time equipment setup wizard.
//
// Each test pumps the wizard inside the standard widget-test harness and
// overrides the providers the wizard reads (`unifiedDiscoveryProvider`,
// device-state providers, `profileServiceProvider`, `deviceServiceProvider`)
// so the dialog can be driven without touching real backends.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/equipment/dialogs/first_time_setup_wizard_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _MockProfileService extends Mock implements ProfileService {}

class _MockDeviceService extends Mock implements DeviceService {}

/// Fake unified discovery notifier that lets tests publish a fixed state
/// without actually invoking any backend. The wizard calls `discoverAll()`
/// in initState; we override it to be a no-op (we still record invocations
/// for tests that want to assert on it).
class _FakeUnifiedDiscoveryNotifier extends UnifiedDiscoveryNotifier {
  _FakeUnifiedDiscoveryNotifier(super.ref, UnifiedDiscoveryState initial) {
    // ignore: invalid_use_of_protected_member
    state = initial;
  }

  int discoverAllCalls = 0;

  @override
  Future<void> discoverAll() async {
    discoverAllCalls++;
  }

  @override
  Future<void> discoverBackend(
    DriverType backend, {
    String? host,
    int? port,
  }) async {}

  @override
  Future<void> discoverIfNeeded({
    Duration maxAge = const Duration(seconds: 30),
  }) async {}
}

UnifiedDiscoveryState _stateWithCamera(DeviceInfo camera) {
  return UnifiedDiscoveryState(
    backendStates: {
      DriverType.native: BackendDiscoveryState(
        backend: DriverType.native,
        status: DiscoveryStatus.completed,
        devices: [camera],
        completedAt: DateTime.now(),
      ),
    },
    rawDevices: [camera],
    groupedDevices: [
      UnifiedDevice(
        canonicalName: camera.name.toLowerCase(),
        displayName: camera.name,
        type: camera.deviceType,
        availableBackends: {DriverType.native: camera},
      ),
    ],
  );
}

DeviceInfo _camera({String id = 'native:cam:0', String name = 'Test Camera'}) {
  return DeviceInfo(
    id: id,
    name: name,
    deviceType: DeviceType.camera,
    driverType: DriverType.native,
    description: 'Mock camera',
    driverVersion: '1.0',
  );
}

/// Pumps the wizard inside the standard `pumpAppScreen` harness so the
/// `databaseProvider` and friends are wired the same way they are in
/// production. The wizard is mounted via a launcher button so we can capture
/// the return value of `FirstTimeSetupWizardDialog.show`.
Future<HarnessHandle> _pumpWizard(
  WidgetTester tester, {
  required UnifiedDiscoveryState initialDiscoveryState,
  required ProfileService profileService,
  required DeviceService deviceService,
  CameraStateSnapshot? cameraState,
  Completer<FirstTimeSetupResult?>? completer,
}) async {
  final overrides = <Override>[
    unifiedDiscoveryProvider.overrideWith(
      (ref) => _FakeUnifiedDiscoveryNotifier(ref, initialDiscoveryState),
    ),
    profileServiceProvider.overrideWithValue(profileService),
    deviceServiceProvider.overrideWithValue(deviceService),
    if (cameraState != null)
      cameraStateProvider.overrideWith((ref) {
        final n = CameraStateNotifier(ref);
        // ignore: invalid_use_of_protected_member
        n.state = cameraState;
        return n;
      }),
  ];

  return pumpAppScreen(
    tester,
    Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: const ValueKey('launch'),
          child: const Text('Open'),
          onPressed: () async {
            final result = await FirstTimeSetupWizardDialog.show(context);
            completer?.complete(result);
          },
        ),
      ),
    ),
    extraOverrides: overrides,
    settle: false,
  ).then((handle) async {
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return handle;
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(const EquipmentProfileModel(name: '_'));
  });

  testWidgets('renders the 3-step sequence (Scan → Select → Save)',
      (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final initial = _stateWithCamera(_camera());

    await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
    );

    expect(find.text('Step 1 of 3: Discover connected equipment'),
        findsOneWidget);
    expect(find.text('Discovered devices'), findsOneWidget);
    expect(find.text('Test Camera'), findsWidgets);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    expect(find.text('Step 2 of 3: Pick the devices to use'), findsOneWidget);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    expect(find.text('Step 3 of 3: Name and save the profile'),
        findsOneWidget);
    expect(find.widgetWithText(NightshadeButton, 'Save'), findsOneWidget);
  });

  testWidgets('cancel from scan step creates no profile', (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final initial = _stateWithCamera(_camera());
    final completer = Completer<FirstTimeSetupResult?>();

    await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
      completer: completer,
    );

    await tester.tap(find.widgetWithText(NightshadeButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await completer.future, isNull);
    verifyNever(() => profileSvc.createProfile(any()));
  });

  testWidgets('cancel from select step creates no profile', (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final initial = _stateWithCamera(_camera());
    final completer = Completer<FirstTimeSetupResult?>();

    await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
      completer: completer,
    );

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    expect(find.text('Step 2 of 3: Pick the devices to use'), findsOneWidget);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await completer.future, isNull);
    verifyNever(() => profileSvc.createProfile(any()));
  });

  testWidgets('cancel from save step creates no profile', (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final initial = _stateWithCamera(_camera());
    final completer = Completer<FirstTimeSetupResult?>();

    await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
      completer: completer,
    );

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    expect(find.text('Step 3 of 3: Name and save the profile'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await completer.future, isNull);
    verifyNever(() => profileSvc.createProfile(any()));
  });

  testWidgets('already-connected camera is pre-selected on select step',
      (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final cam = _camera(id: 'native:cam:7');
    final initial = _stateWithCamera(cam);

    await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
      cameraState: CameraStateSnapshot(
        connectionState: DeviceConnectionState.connected,
        deviceId: cam.id,
        deviceName: cam.name,
      ),
    );

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();

    final radios = tester
        .widgetList<Radio<String>>(find.byType(Radio<String>))
        .toList();
    expect(radios, isNotEmpty);
    final selected = radios.where(
      (r) => r.value == cam.id && r.groupValue == cam.id,
    );
    expect(selected, isNotEmpty,
        reason: 'expected pre-seeded camera id ${cam.id} to be selected');
  });

  testWidgets(
      'save invokes profileService.createProfile and '
      'deviceService.connectAllFromProfile', (tester) async {
    final profileSvc = _MockProfileService();
    final deviceSvc = _MockDeviceService();
    final cam = _camera();
    final initial = _stateWithCamera(cam);
    final completer = Completer<FirstTimeSetupResult?>();

    when(() => profileSvc.createProfile(any())).thenAnswer((_) async => 42);
    when(() => profileSvc.updateProfileDevices(
          any(),
          cameraId: any(named: 'cameraId'),
          mountId: any(named: 'mountId'),
          focuserId: any(named: 'focuserId'),
          filterWheelId: any(named: 'filterWheelId'),
          guiderId: any(named: 'guiderId'),
          rotatorId: any(named: 'rotatorId'),
          domeId: any(named: 'domeId'),
          weatherId: any(named: 'weatherId'),
          safetyMonitorId: any(named: 'safetyMonitorId'),
          switchId: any(named: 'switchId'),
          coverCalibratorId: any(named: 'coverCalibratorId'),
        )).thenAnswer((_) async {});
    when(() => deviceSvc.connectAllFromProfile(any()))
        .thenAnswer((_) => const Stream<DeviceConnectProgress>.empty());

    final handle = await _pumpWizard(
      tester,
      initialDiscoveryState: initial,
      profileService: profileSvc,
      deviceService: deviceSvc,
      completer: completer,
    );

    // Mocked createProfile returns id=42 without inserting a row. Seed the
    // in-memory database with a row at id=42 so the wizard's post-create
    // `dao.getProfileById(42)` returns a usable profile for the connect
    // sweep.
    final dao = handle.container.read(equipmentProfilesDaoProvider);
    await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: 'Setup Wizard',
        id: const Value(42),
      ),
    );

    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();
    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pump();

    await tester.tap(find.widgetWithText(NightshadeButton, 'Save'));
    await tester.pumpAndSettle();

    final result = await completer.future;
    expect(result, isNotNull);
    expect(result!.profileId, 42);
    expect(result.connectAttempted, isTrue);

    verify(() => profileSvc.createProfile(any())).called(1);
    verify(() => deviceSvc.connectAllFromProfile(any())).called(1);
  });
}
