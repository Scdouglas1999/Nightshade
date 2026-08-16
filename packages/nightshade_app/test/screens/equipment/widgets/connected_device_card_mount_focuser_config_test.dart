// Widget tests for the ConnectedDevicecard mount + focuser "Configuration"
// dialogs' truthful validation/save behavior.
//
// Coercing malformed numeric input via `parse(...) ?? old` reports success
// while silently keeping the prior value, and sequential per-field writes land
// half a change. Both dialogs therefore validate before touching persistence
// (minutes 0..120; coefficient finite; backlash 0..10000), save through ONE
// batched AppSettingsNotifier call, and close only after the write resolves —
// showing an inline error and staying open otherwise.
//
// The harness wires a real in-memory settings store (via mockDatabase), so a
// save round-trips to `appSettingsProvider` state; "did zero work" is asserted
// as "state unchanged AND dialog still open", and a successful save as "state
// updated AND dialog closed".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/widgets/connected_device_card.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../harness/harness.dart';

class _FailingSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async {
    throw StateError('settings database unavailable');
  }
}

Future<HarnessHandle> _pump(
    WidgetTester tester, ConnectedDeviceType type) async {
  final handle = await pumpAppScreen(
    tester,
    ConnectedDeviceCard(type: type),
    settle: false,
  );
  // Resolve the settings provider so the dialog reads real values and post-save
  // state reads are deterministic.
  await handle.container.read(appSettingsProvider.future);
  await tester.pump();
  return handle;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _waitForDialogToClose(
  WidgetTester tester,
  String title,
) async {
  for (var i = 0; i < 30 && find.text(title).evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mount Configuration', () {
    testWidgets('settings failure does not open a default-valued editor',
        (tester) async {
      await pumpAppScreen(
        tester,
        const ConnectedDeviceCard(type: ConnectedDeviceType.mount),
        extraOverrides: [
          appSettingsProvider.overrideWith(_FailingSettingsNotifier.new),
        ],
        settle: false,
      );

      await _openDialog(tester);

      expect(find.text('Mount Configuration'), findsNothing);
      expect(
          find.textContaining('Could not load mount settings'), findsOneWidget);
    });

    testWidgets('malformed minutes does zero work and stays open',
        (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.mount);
      final before = handle.container
          .read(appSettingsProvider)
          .requireValue
          .meridianFlipMinutes;

      await _openDialog(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await _tapSave(tester);

      expect(find.text('Mount Configuration'), findsOneWidget,
          reason: 'a malformed value must leave the dialog open');
      expect(
        handle.container
            .read(appSettingsProvider)
            .requireValue
            .meridianFlipMinutes,
        before,
        reason: 'a malformed value must not persist anything',
      );
    });

    testWidgets('out-of-range minutes (121) is rejected and stays open',
        (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.mount);
      final before = handle.container
          .read(appSettingsProvider)
          .requireValue
          .meridianFlipMinutes;

      await _openDialog(tester);
      await tester.enterText(find.byType(TextField), '121');
      await _tapSave(tester);

      expect(find.text('Mount Configuration'), findsOneWidget);
      expect(
        handle.container
            .read(appSettingsProvider)
            .requireValue
            .meridianFlipMinutes,
        before,
      );
    });

    testWidgets('boundary minutes 120 saves and closes', (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.mount);

      await _openDialog(tester);
      await tester.enterText(find.byType(TextField), '120');
      await _tapSave(tester);
      await _waitForDialogToClose(tester, 'Mount Configuration');

      expect(find.text('Mount Configuration'), findsNothing,
          reason: 'a valid save must close the dialog');
      expect(
        handle.container
            .read(appSettingsProvider)
            .requireValue
            .meridianFlipMinutes,
        120,
      );
    });

    testWidgets('boundary minutes 0 saves and closes', (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.mount);

      await _openDialog(tester);
      await tester.enterText(find.byType(TextField), '0');
      await _tapSave(tester);
      await _waitForDialogToClose(tester, 'Mount Configuration');

      expect(find.text('Mount Configuration'), findsNothing);
      expect(
        handle.container
            .read(appSettingsProvider)
            .requireValue
            .meridianFlipMinutes,
        0,
      );
    });
  });

  group('Focuser Configuration', () {
    // Field order in the dialog: [0] coefficient, [1] backlash.
    Finder coeffField() => find.byType(TextField).at(0);
    Finder backlashField() => find.byType(TextField).at(1);

    testWidgets('settings failure does not open a default-valued editor',
        (tester) async {
      await pumpAppScreen(
        tester,
        const ConnectedDeviceCard(type: ConnectedDeviceType.focuser),
        extraOverrides: [
          appSettingsProvider.overrideWith(_FailingSettingsNotifier.new),
        ],
        settle: false,
      );

      await _openDialog(tester);

      expect(find.text('Focuser Configuration'), findsNothing);
      expect(
        find.textContaining('Could not load focuser settings'),
        findsOneWidget,
      );
    });

    testWidgets('malformed coefficient does zero work and stays open',
        (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.focuser);
      final before = handle.container
          .read(appSettingsProvider)
          .requireValue
          .tempCoefficient;

      await _openDialog(tester);
      await tester.enterText(coeffField(), 'abc');
      await _tapSave(tester);

      expect(find.text('Focuser Configuration'), findsOneWidget);
      expect(
        handle.container.read(appSettingsProvider).requireValue.tempCoefficient,
        before,
      );
    });

    testWidgets('NaN coefficient is rejected and stays open', (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.focuser);
      final before = handle.container
          .read(appSettingsProvider)
          .requireValue
          .tempCoefficient;

      await _openDialog(tester);
      await tester.enterText(coeffField(), 'NaN');
      await _tapSave(tester);

      expect(find.text('Focuser Configuration'), findsOneWidget);
      expect(
        handle.container.read(appSettingsProvider).requireValue.tempCoefficient,
        before,
      );
    });

    testWidgets('Infinity coefficient is rejected and stays open',
        (tester) async {
      await _pump(tester, ConnectedDeviceType.focuser);

      await _openDialog(tester);
      await tester.enterText(coeffField(), 'Infinity');
      await _tapSave(tester);

      expect(find.text('Focuser Configuration'), findsOneWidget);
    });

    testWidgets('out-of-range backlash (10001) is rejected and stays open',
        (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.focuser);
      final before = handle.container
          .read(appSettingsProvider)
          .requireValue
          .backlashCompensation;

      await _openDialog(tester);
      await tester.enterText(coeffField(), '2.0');
      await tester.enterText(backlashField(), '10001');
      await _tapSave(tester);

      expect(find.text('Focuser Configuration'), findsOneWidget);
      expect(
        handle.container
            .read(appSettingsProvider)
            .requireValue
            .backlashCompensation,
        before,
      );
    });

    testWidgets('boundary values (coeff 0, backlash 10000) save and close',
        (tester) async {
      final handle = await _pump(tester, ConnectedDeviceType.focuser);

      await _openDialog(tester);
      await tester.enterText(coeffField(), '0');
      await tester.enterText(backlashField(), '10000');
      await _tapSave(tester);
      await _waitForDialogToClose(tester, 'Focuser Configuration');

      expect(find.text('Focuser Configuration'), findsNothing);
      final state = handle.container.read(appSettingsProvider).requireValue;
      expect(state.tempCoefficient, 0);
      expect(state.backlashCompensation, 10000);
    });
  });
}
