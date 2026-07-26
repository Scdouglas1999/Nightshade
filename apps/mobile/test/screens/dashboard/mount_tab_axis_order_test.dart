import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/mount_tab.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('park action is single-flight across rapid taps', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final backend = _MockDeviceBackend();
    final service = _MockDeviceService();
    final parkGate = Completer<void>();
    when(() => service.parkMount()).thenAnswer((_) => parkGate.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceBackendProvider.overrideWithValue(backend),
          deviceServiceProvider.overrideWithValue(service),
          mountStateProvider.overrideWith(_ConnectedMountNotifier.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: MountTab()),
        ),
      ),
    );

    final park = find.text('Park');
    await tester.ensureVisible(park);
    await tester.tap(park);
    await tester.pump();
    await tester.tap(find.text('Parking…'));
    await tester.pump();

    verify(() => service.parkMount()).called(1);
    parkGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('tracking cannot be enabled while the mount is parked', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final backend = _MockDeviceBackend();
    final service = _MockDeviceService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceBackendProvider.overrideWithValue(backend),
          deviceServiceProvider.overrideWithValue(service),
          mountStateProvider.overrideWith(_ParkedMountNotifier.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: MountTab()),
        ),
      ),
    );

    final tracking = find.text('Tracking off');
    await tester.ensureVisible(tracking);
    await tester.tap(tracking);
    await tester.pump();

    verifyNever(() => service.setMountTracking(any()));
  });

  testWidgets('STOP aborts a live slew before this tab has moved an axis', (
    tester,
  ) async {
    final backend = _MockDeviceBackend();
    when(
      () => backend.mountMoveAxis(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(() => backend.mountAbort(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceBackendProvider.overrideWithValue(backend),
          mountStateProvider.overrideWith(_ConnectedMountNotifier.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: MountTab()),
        ),
      ),
    );

    await tester.tap(find.text('STOP'));
    await tester.pumpAndSettle();

    verify(() => backend.mountMoveAxis('mount-1', 0, 0.0)).called(1);
    verify(() => backend.mountMoveAxis('mount-1', 1, 0.0)).called(1);
    verify(() => backend.mountAbort('mount-1')).called(1);
  });

  testWidgets('held axis stops when a connection rebuild removes the d-pad', (
    tester,
  ) async {
    final backend = _MockDeviceBackend();
    final rates = <double>[];
    late _ConnectedMountNotifier notifier;
    when(() => backend.mountMoveAxis(any(), any(), any())).thenAnswer((
      call,
    ) async {
      rates.add(call.positionalArguments[2] as double);
    });
    when(() => backend.mountAbort(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceBackendProvider.overrideWithValue(backend),
          mountStateProvider.overrideWith((ref) {
            notifier = _ConnectedMountNotifier(ref);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: MountTab()),
        ),
      ),
    );

    await tester.startGesture(tester.getCenter(find.text('North')));
    await tester.pump();
    expect(rates, [2.0]);

    notifier.markDisconnected();
    await tester.pump();
    await tester.pump();

    expect(find.text('Mount not connected'), findsOneWidget);
    expect(rates, [2.0, 0.0]);
  });

  testWidgets('axis stop is ordered and aborts if the start remains hung', (
    tester,
  ) async {
    final backend = _MockDeviceBackend();
    final startGate = Completer<void>();
    final rates = <double>[];
    when(() => backend.mountMoveAxis(any(), any(), any())).thenAnswer((
      invocation,
    ) async {
      final rate = invocation.positionalArguments[2] as double;
      rates.add(rate);
      if (rate != 0) await startGate.future;
    });
    when(() => backend.mountAbort(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceBackendProvider.overrideWithValue(backend),
          mountStateProvider.overrideWith(_ConnectedMountNotifier.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: MountTab()),
        ),
      ),
    );

    final north = find.text('North');
    expect(north, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(north));
    await tester.pump();
    expect(rates, [2.0]);

    await gesture.up();
    await tester.pump();
    expect(rates, [
      2.0,
    ], reason: 'release must queue behind the unresolved start command');

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    verify(() => backend.mountAbort('mount-1')).called(1);
    expect(rates, [2.0]);

    startGate.complete();
    await tester.pump();
    await tester.pump();
    expect(rates, [2.0, 0.0]);
  });
}

class _MockDeviceBackend extends Mock implements DeviceBackend {}

class _MockDeviceService extends Mock implements DeviceService {}

class _ConnectedMountNotifier extends MountStateNotifier {
  _ConnectedMountNotifier(super.ref) {
    state = const MountState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'mount-1',
      deviceName: 'Test Mount',
      isParked: false,
    );
  }

  void markDisconnected() {
    state = const MountState(
      connectionState: DeviceConnectionState.disconnected,
      deviceId: 'mount-1',
      deviceName: 'Test Mount',
      isParked: false,
    );
  }
}

class _ParkedMountNotifier extends MountStateNotifier {
  _ParkedMountNotifier(super.ref) {
    state = const MountState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'mount-1',
      deviceName: 'Test Mount',
      isParked: true,
    );
  }
}
