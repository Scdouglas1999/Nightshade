// Three defects found on the Manage Pairing page during the 2026-08-13 drive.
//
// WD-N4 (and the SET-18 residual): the pairing credential is the ONE element
// the page does not expose to accessibility. The live tree gave
// "Enter this code on your device:" and "Expires in 04:55" with nothing in
// between — the code itself is a SelectableText, which publishes its text as a
// semantic value rather than a name — so a screen-reader user is told a code
// exists and never told what it is. The QR is an image; this text was the only
// non-visual path to pairing a phone.
//
// WD-N5: the green "<name> paired" banner survived revoking that very device —
// the page read "WaveD Test Phone paired" above "No paired devices".
//
// WD-N6: with exactly one device paired the confirmation read
// "Revoke access for all 1 paired devices?".

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/pairing_screen.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

import '../../harness/harness.dart';

/// Every accessible NAME published anywhere in the tree.
List<String> _semanticLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

Future<PairingNotifier> _pumpPairing(
  WidgetTester tester,
  PairingDatabase database,
) async {
  late PairingNotifier notifier;
  await pumpAppScreen(
    tester,
    const PairingScreen(),
    size: const Size(900, 1400),
    settle: false,
    extraOverrides: [
      pairingProvider.overrideWith((ref) {
        notifier = PairingNotifier.withDatabase(database);
        return notifier;
      }),
    ],
  );
  await tester.pump();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WD-N4 — the pairing code is readable by a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => database.close());

    final notifier = await _pumpPairing(tester, database);
    await tester.runAsync(notifier.startPairing);
    await tester.pump();

    final code = notifier.state.pairingCode!;
    expect(find.text(code), findsOneWidget, reason: 'it is on screen');
    expect(
      _semanticLabels(tester).where((l) => l.contains(code)),
      isNotEmpty,
      reason: 'the credential must have an accessible name, not only a value',
    );
    handle.dispose();
  });

  testWidgets('WD-N5 — revoking the device takes its banner with it',
      (tester) async {
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => database.close());

    final notifier = await _pumpPairing(tester, database);
    await tester.runAsync(notifier.startPairing);
    await tester.pump();

    await tester.runAsync(
      () => TokenManager(database).verifyPairing(
        pairingCode: notifier.state.pairingCode!,
        deviceId: 'waved-test-phone',
        deviceName: 'WaveD Test Phone',
        deviceType: 'android',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1300)),
    );
    await tester.pump();
    expect(find.text('WaveD Test Phone paired'), findsOneWidget);

    await tester.runAsync(notifier.revokeAll);
    await tester.pump();

    expect(
      find.text('WaveD Test Phone paired'),
      findsNothing,
      reason: 'the page cannot say a device is paired beside "No paired '
          'devices"',
    );
    expect(find.text('No paired devices'), findsOneWidget);
  });

  testWidgets('WD-N6 — one device is not "all 1 paired devices"',
      (tester) async {
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    await database.addPairedDevice(
      deviceId: 'phone-one',
      deviceName: 'WaveD Test Phone',
      sessionToken: 'ab' * 32,
      deviceType: 'android',
    );
    addTearDown(() async => database.close());

    final notifier = await _pumpPairing(tester, database);
    expect(await tester.runAsync(notifier.loadPairedDevices), isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke All'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('all 1 paired devices'), findsNothing);
    expect(find.textContaining('WaveD Test Phone'), findsWidgets);
    // The action behind it is unchanged — revoking every row — and is covered
    // by pairing_revoke_all_test.dart; what is under test here is the sentence
    // the operator has to agree to.
    expect(find.text('Revoke Access'), findsOneWidget);
  });

  testWidgets('the plural form survives for a real "all"', (tester) async {
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    for (final id in const ['one', 'two', 'three']) {
      await database.addPairedDevice(
        deviceId: id,
        deviceName: 'Phone $id',
        sessionToken: id.padRight(64, '0'),
        deviceType: 'android',
      );
    }
    addTearDown(() async => database.close());

    final notifier = await _pumpPairing(tester, database);
    expect(await tester.runAsync(notifier.loadPairedDevices), isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all 3 paired devices'), findsOneWidget);
  });
}
