// The shell's always-visible equipment chip must describe what is ATTACHED,
// not only what the active profile assigns.
//
// The audit connected a Simulated Camera, Mount, Focuser and Filter Wheel from
// Equipment > Discovery — the app's own "This session only — not saved to your
// profile" path — and the chip read "0/0" with a popup whose entire body was
// "No devices configured", in the same frame as four green Connected rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/equipment_status_indicator.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Overrides that put the four simulated devices in the connected state the
/// discovery panel leaves them in after a session-only connect.
List<Override> _connectedDevices({
  bool camera = false,
  bool mount = false,
  bool focuser = false,
  bool filterWheel = false,
}) {
  return [
    if (camera)
      cameraStateProvider.overrideWith((ref) {
        final notifier = CameraStateNotifier(ref);
        notifier.setConnecting('sim_camera_1', 'Simulated Camera');
        notifier.setConnected();
        return notifier;
      }),
    if (mount)
      mountStateProvider.overrideWith((ref) {
        final notifier = MountStateNotifier(ref);
        notifier.setConnecting('sim_mount_1', 'Simulated Mount');
        notifier.setConnected();
        return notifier;
      }),
    if (focuser)
      focuserStateProvider.overrideWith((ref) {
        final notifier = FocuserStateNotifier(ref);
        notifier.setConnecting('sim_focuser_1', 'Simulated Focuser');
        notifier.setConnected();
        return notifier;
      }),
    if (filterWheel)
      filterWheelStateProvider.overrideWith((ref) {
        final notifier = FilterWheelStateNotifier(ref);
        notifier.setConnecting('sim_fw_1', 'Simulated Filter Wheel');
        notifier.setConnected();
        return notifier;
      }),
  ];
}

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required EquipmentProfileModel profile,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeEquipmentProfileProvider.overrideWithValue(profile),
        ...overrides,
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: EquipmentStatusIndicator(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The open popup's "Disconnect All" entry, matched by its menu value so the
/// assertion does not depend on label styling.
PopupMenuItem<String> _disconnectAllItem(WidgetTester tester) {
  return tester.widget<PopupMenuItem<String>>(
    find.byWidgetPredicate(
      (w) => w is PopupMenuItem<String> && w.value == 'disconnect',
    ),
  );
}

void main() {
  group('EquipmentStatusIndicator', () {
    testWidgets('counts session-only connections the profile does not assign',
        (tester) async {
      await _pumpIndicator(
        tester,
        // A fresh profile: nothing has been saved into any device slot.
        profile: const EquipmentProfileModel(id: 1, name: 'My Equipment'),
        overrides: _connectedDevices(
          camera: true,
          mount: true,
          focuser: true,
          filterWheel: true,
        ),
      );

      // The chip states the live count, not a "0/0" ratio over an empty
      // profile.
      expect(find.text('4 connected'), findsOneWidget);
      expect(find.text('0/0'), findsNothing);

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      // ...and the popup describes the four devices instead of claiming the
      // rig is empty.
      expect(find.text('No devices configured'), findsNothing);
      expect(find.text('Simulated Camera'), findsOneWidget);
      expect(find.text('Simulated Mount'), findsOneWidget);
      expect(find.text('Simulated Focuser'), findsOneWidget);
      expect(find.text('Simulated Filter Wheel'), findsOneWidget);
    });

    testWidgets('an empty profile with nothing attached still says so',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(id: 1, name: 'My Equipment'),
      );

      expect(find.text('0 connected'), findsOneWidget);

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      expect(find.text('No devices configured'), findsOneWidget);
    });

    testWidgets('keeps the profile ratio and reports extras separately',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(
          id: 1,
          name: 'Backyard rig',
          cameraId: 'sim_camera_1',
          cameraName: 'Profile Camera',
          mountId: 'sim_mount_1',
          mountName: 'Profile Mount',
        ),
        // Both assigned devices are up, plus a focuser connected for this
        // session only. A bare "3/2" would read as a broken counter.
        overrides: _connectedDevices(camera: true, mount: true, focuser: true),
      );

      expect(find.text('2/2 +1'), findsOneWidget);

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      expect(find.text('Simulated Focuser'), findsOneWidget);
    });

    // "Disconnect All" used to be unconditionally enabled: with nothing
    // attached it closed the menu and did nothing at all — no toast, no log
    // line, no state change — directly under a greyed "No devices configured".
    testWidgets('Disconnect All is disabled when nothing is connected',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(id: 1, name: 'My Equipment'),
      );

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      expect(_disconnectAllItem(tester).enabled, isFalse);
    });

    testWidgets('Disconnect All stays enabled for a connected device',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(id: 1, name: 'My Equipment'),
        overrides: _connectedDevices(camera: true),
      );

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      expect(_disconnectAllItem(tester).enabled, isTrue);
    });

    // The chip's own counters only tally the six profile-assignable slots. The
    // sweep behind Disconnect All also covers dome, weather, safety monitor,
    // switch and cover calibrator, so gating the item on the chip counts would
    // grey out a button that still had real work to do.
    testWidgets(
        'Disconnect All stays enabled for a device the chip does not count',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(id: 1, name: 'My Equipment'),
        overrides: [
          domeStateProvider.overrideWith((ref) {
            final notifier = DomeStateNotifier(ref);
            notifier.setConnecting('sim_dome_1', 'Simulated Dome');
            notifier.setConnected();
            return notifier;
          }),
        ],
      );

      // The chip is blind to the dome...
      expect(find.text('0 connected'), findsOneWidget);

      await tester.tap(find.byType(EquipmentStatusIndicator));
      await tester.pumpAndSettle();

      // ...but the action that would disconnect it must not be dead.
      expect(_disconnectAllItem(tester).enabled, isTrue);
    });

    testWidgets('an assigned device that is down keeps the ratio honest',
        (tester) async {
      await _pumpIndicator(
        tester,
        profile: const EquipmentProfileModel(
          id: 1,
          name: 'Backyard rig',
          cameraId: 'sim_camera_1',
          cameraName: 'Profile Camera',
          mountId: 'sim_mount_1',
          mountName: 'Profile Mount',
        ),
        overrides: _connectedDevices(camera: true),
      );

      expect(find.text('1/2'), findsOneWidget);
    });
  });
}
