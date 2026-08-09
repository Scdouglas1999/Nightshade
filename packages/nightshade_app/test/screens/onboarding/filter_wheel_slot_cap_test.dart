// The onboarding filter editor must not invent slots the wheel does not have.
//
// Live finding: after picking the Simulated Filter Wheel the step listed its
// real seven positions and "Add slot" happily created an eighth, pre-filled
// "Filter 8". The only cap was a hardcoded 12, never the count the driver had
// just reported — so onboarding could persist a profile whose filter list the
// hardware can never reach.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/filter_wheel_step.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Draft standing in for "the user picked the seven-position sim wheel".
class _PickedWheelNotifier extends OnboardingNotifier {
  _PickedWheelNotifier(super.ref, List<String> names) {
    // ignore: invalid_use_of_protected_member
    state = OnboardingDraft(
      currentStep: OnboardingStep.filterWheel,
      filterWheelId: 'sim_filter_wheel_1',
      filterWheelName: 'Simulated Filter Wheel',
      filterNames: names,
    );
  }
}

/// A wheel notifier parked in a fixed state — connected and reporting
/// [slots] positions, or left disconnected when [slots] is empty.
class _StubWheel extends FilterWheelStateNotifier {
  _StubWheel(super.ref, List<String> slots) {
    if (slots.isEmpty) return;
    // ignore: invalid_use_of_protected_member
    state = FilterWheelState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'sim_filter_wheel_1',
      deviceName: 'Simulated Filter Wheel',
      filterNames: slots,
    );
  }
}

const _sevenSlots = <String>['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];

Future<void> _pump(
  WidgetTester tester, {
  required List<String> draftNames,
  required List<String> wheelSlots,
}) async {
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 1800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        onboardingDraftProvider
            .overrideWith((ref) => _PickedWheelNotifier(ref, draftNames)),
        filterWheelStateProvider
            .overrideWith((ref) => _StubWheel(ref, wheelSlots)),
        // The real wheel notifier listens to the active profile; without this
        // the listen opens a drift query stream over the scratch database and
        // the widget test tears down with pending timers.
        activeProfileProvider.overrideWith((ref) => Stream.value(null)),
        allProfilesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: OnboardingFilterWheelStep()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

NightshadeButton _addSlotButton(WidgetTester tester) =>
    tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Add slot'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Add slot is dead once every wheel position is listed',
      (tester) async {
    await _pump(
      tester,
      draftNames: _sevenSlots,
      wheelSlots: _sevenSlots,
    );

    expect(find.widgetWithText(TextField, 'SII'), findsOneWidget);
    expect(
      _addSlotButton(tester).onPressed,
      isNull,
      reason: 'a 7-position wheel has no slot 8 to hold "Filter 8"',
    );
    expect(
      find.text('All 7 positions on this wheel are listed.'),
      findsOneWidget,
      reason: 'a disabled button with no explanation reads as a bug',
    );
  });

  testWidgets('Add slot still works below the wheel position count',
      (tester) async {
    await _pump(
      tester,
      draftNames: const ['L', 'R', 'G'],
      wheelSlots: _sevenSlots,
    );

    expect(_addSlotButton(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Add slot'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Filter 4'), findsOneWidget);
  });

  testWidgets('with no wheel reading the generic cap still applies',
      (tester) async {
    // Twelve names, wheel not connected: nothing reported the real count, so
    // the editor keeps the generic profile-wide bound rather than fabricating
    // one from the hardware.
    await _pump(
      tester,
      draftNames: List<String>.generate(12, (i) => 'F${i + 1}'),
      wheelSlots: const <String>[],
    );

    expect(_addSlotButton(tester).onPressed, isNull);
    expect(find.textContaining('positions on this wheel'), findsNothing);
  });

  testWidgets('removing a middle slot asks first, removing the last does not',
      (tester) async {
    await _pump(
      tester,
      draftNames: const ['L', 'R', 'G'],
      wheelSlots: _sevenSlots,
    );

    final deleteButtons = find.byIcon(NightshadeIcons.delete);
    expect(deleteButtons, findsNWidgets(3));

    // Middle row: renumbers everything below it, so it must be confirmed.
    await tester.tap(deleteButtons.at(0));
    await tester.pumpAndSettle();
    expect(find.text('Remove this slot?'), findsOneWidget);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'L'), findsOneWidget);

    // Last row: cannot renumber anything, so it stays a single click.
    await tester.tap(find.byIcon(NightshadeIcons.delete).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Remove this slot?'), findsNothing);
    expect(find.widgetWithText(TextField, 'G'), findsNothing);
  });
}
