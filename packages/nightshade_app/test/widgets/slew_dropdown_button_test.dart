import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/models/command_action_result.dart';
import 'package:nightshade_app/services/mount_command_service.dart';
import 'package:nightshade_app/widgets/slew_dropdown_button.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../harness/harness.dart';

class _ConnectedMountNotifier extends MountStateNotifier {
  _ConnectedMountNotifier(super.ref) {
    state = const MountState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'mount-1',
      deviceName: 'Test Mount',
    );
  }
}

class _SwitchableBackendNotifier extends BackendNotifier {
  _SwitchableBackendNotifier(super.ref, NightshadeBackend backend) {
    // ignore: invalid_use_of_protected_member
    state = backend;
  }

  void replaceBackend(NightshadeBackend backend) => state = backend;
}

class _ControlledMountService extends MountCommandService {
  _ControlledMountService(super.ref);

  final result = Completer<CommandActionResult>();
  int calls = 0;

  @override
  Future<CommandActionResult> slewTo(
    double ra,
    double dec, {
    bool showFeedback = true,
  }) {
    calls++;
    return result.future;
  }
}

Widget _harness({required bool mountConnected}) {
  return ProviderScope(
    overrides: [
      if (mountConnected)
        mountStateProvider.overrideWith((ref) {
          final notifier = MountStateNotifier(ref);
          notifier.setConnecting('test-mount');
          notifier.setConnected();
          return notifier;
        }),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 220,
          child: SlewDropdownButton(ra: 12, dec: 30),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('connected popup trigger paints as enabled and opens its menu',
      (tester) async {
    await tester.pumpWidget(_harness(mountConnected: true));

    final visualButton = tester.widget<NightshadeButton>(
      find.byType(NightshadeButton),
    );
    expect(visualButton.onPressed, isNotNull);

    await tester.tap(find.byType(SlewDropdownButton));
    await tester.pumpAndSettle();

    expect(find.text('Slew & Center'), findsOneWidget);
  });

  testWidgets('disconnected popup trigger paints as disabled', (tester) async {
    await tester.pumpWidget(_harness(mountConnected: false));

    final visualButton = tester.widget<NightshadeButton>(
      find.byType(NightshadeButton),
    );
    final popup = tester.widget<PopupMenuButton<SlewMode>>(
      find.byType(PopupMenuButton<SlewMode>),
    );
    expect(visualButton.onPressed, isNull);
    expect(popup.enabled, isFalse);
  });

  testWidgets('slew is single-flight and old-host completion is discarded',
      (tester) async {
    final backendA = mockBackend();
    final backendB = mockBackend();
    late _SwitchableBackendNotifier backendNotifier;
    late _ControlledMountService serviceA;
    late _ControlledMountService serviceB;

    await pumpAppScreen(
      tester,
      const SizedBox(
        width: 220,
        child: SlewDropdownButton(ra: 12, dec: 30),
      ),
      backend: backendA,
      extraOverrides: [
        backendProvider.overrideWith(
          (ref) => backendNotifier = _SwitchableBackendNotifier(ref, backendA),
        ),
        mountStateProvider.overrideWith(_ConnectedMountNotifier.new),
        mountCommandServiceProvider.overrideWith((ref) {
          final backend = ref.watch(backendProvider);
          final service = _ControlledMountService(ref);
          if (identical(backend, backendA)) {
            serviceA = service;
          } else {
            serviceB = service;
          }
          return service;
        }),
      ],
    );

    await tester.tap(find.byType(SlewDropdownButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slew').last);
    await tester.pump();
    expect(find.text('Working...'), findsOneWidget);
    expect(serviceA.calls, 1);

    backendNotifier.replaceBackend(backendB);
    await tester.pump();
    expect(
      find.widgetWithText(NightshadeButton, 'Slew'),
      findsOneWidget,
    );

    serviceA.result.complete(
      const CommandActionResult.success(message: 'Old host slew complete'),
    );
    await tester.pump();
    expect(find.text('Old host slew complete'), findsNothing);

    await tester.tap(find.byType(SlewDropdownButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slew').last);
    await tester.pump();
    expect(serviceB.calls, 1);
    serviceB.result.complete(CommandActionResult.ok);
    await tester.pump();
  });
}
