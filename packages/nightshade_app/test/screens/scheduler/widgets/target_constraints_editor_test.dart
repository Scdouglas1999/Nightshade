// Widget tests for the wizard-mode "Add constraint" flow on the per-target
// constraints editor. Verifies:
//   * Step 1 renders four constraint-type cards (timeWindow, moon,
//     customHorizon, scheduledWindow).
//   * Picking "Time window" advances Step 2 with the 22:00–02:00 default.
//   * Saving on Step 3 persists the constraint via TargetConstraintService.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/scheduler/widgets/target_constraints_editor.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as ndb;
import 'package:nightshade_ui/nightshade_ui.dart';

Future<int> _insertTargetWithId(
    ndb.NightshadeDatabase db, int id, String name) async {
  // Force the id so the wizard test's hard-coded targetId matches the
  // FK referenced by target_constraints.target_id.
  return await db.into(db.targets).insert(
        ndb.TargetsCompanion(
          id: Value(id),
          name: Value(name),
          ra: const Value(0.0),
          dec: const Value(0.0),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ndb.NightshadeDatabase database;

  setUp(() {
    database = ndb.NightshadeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Widget host({required Widget child}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('wizard Step 1 renders the four constraint-type cards',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _insertTargetWithId(database, 99, 'NGC 7000');

    await tester.pumpWidget(host(
      child: const TargetConstraintsEditor(
        targetId: 99,
        targetName: 'NGC 7000',
      ),
    ));
    await tester.pumpAndSettle();

    final addBtn = find.byKey(const ValueKey('add-constraint-wizard-button'));
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(find.text('What kind of constraint?'), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-kind-timeWindow')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-kind-moon')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-kind-horizon')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-kind-scheduledWindow')),
        findsOneWidget);
    expect(find.text('Time window'), findsOneWidget);
    expect(find.text('Moon avoidance'), findsOneWidget);
    expect(find.text('Custom horizon'), findsOneWidget);
    expect(find.text('Scheduled window'), findsOneWidget);
  });

  testWidgets(
      'picking "Time window" advances Step 2 with the 22:00 – 02:00 default',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _insertTargetWithId(database, 99, 'NGC 7000');

    await tester.pumpWidget(host(
      child: const TargetConstraintsEditor(
        targetId: 99,
        targetName: 'NGC 7000',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-constraint-wizard-button')));
    await tester.pumpAndSettle();

    // Select the time-window card.
    await tester.tap(find.byKey(const ValueKey('wizard-kind-timeWindow')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();

    // Step 2 shows the default times.
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);
  });

  testWidgets(
      'saving the wizard persists the constraint via TargetConstraintService',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database),
    ]);
    addTearDown(container.dispose);
    await _insertTargetWithId(database, 77, 'M42');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TargetConstraintsEditor(
              targetId: 77,
              targetName: 'M42',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-constraint-wizard-button')));
    await tester.pumpAndSettle();

    // Pick "Moon avoidance" (simpler than horizon — no profile prerequisite).
    await tester.tap(find.byKey(const ValueKey('wizard-kind-moon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();

    // Step 2 — keep the 30 % default.
    expect(find.textContaining('30 %'), findsAtLeastNWidgets(1));
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();

    // Step 3 — review + save.
    expect(find.text('Review and save'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wizard-save')));
    await tester.pumpAndSettle();

    // Now read the database directly and assert the constraint exists.
    final svc = container.read(targetConstraintServiceProvider);
    final rows = await svc.listForTarget(77);
    expect(rows.length, 1);
    expect(rows.first.kind, TargetConstraintKind.moonIlluminationMax);
    expect(rows.first.moonIlluminationMax, closeTo(0.30, 1e-6));
  });

  testWidgets(
      'saving a scheduledWindow constraint via the wizard writes the '
      'absolute UTC range to the database', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database),
    ]);
    addTearDown(container.dispose);
    await _insertTargetWithId(database, 55, 'NGC 891');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TargetConstraintsEditor(
              targetId: 55,
              targetName: 'NGC 891',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-constraint-wizard-button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('wizard-kind-scheduledWindow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    // Step 2 — accept defaults.
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wizard-save')));
    await tester.pumpAndSettle();

    final svc = container.read(targetConstraintServiceProvider);
    final rows = await svc.listForTarget(55);
    expect(rows.length, 1);
    expect(rows.first.kind, TargetConstraintKind.scheduledWindow);
    expect(rows.first.scheduledWindow, isNotNull);
    expect(rows.first.scheduledWindow!.priorityBoost, closeTo(0.5, 1e-6));
    expect(
      rows.first.scheduledWindow!.endUtc
          .isAfter(rows.first.scheduledWindow!.startUtc),
      isTrue,
    );
  });
}
