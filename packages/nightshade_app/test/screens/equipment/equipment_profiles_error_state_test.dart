import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/equipment_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _FailingProfilesNotifier extends EquipmentProfilesNotifier {
  @override
  Future<EquipmentProfilesState> build() async {
    throw StateError('profile database unavailable');
  }
}

class _PendingProfilesNotifier extends EquipmentProfilesNotifier {
  @override
  Future<EquipmentProfilesState> build() =>
      Completer<EquipmentProfilesState>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile failure is not rendered as first-time onboarding',
      (tester) async {
    await pumpAppScreen(
      tester,
      const EquipmentScreen(),
      extraOverrides: [
        equipmentProfilesProvider.overrideWith(_FailingProfilesNotifier.new),
      ],
      settle: false,
    );
    await tester.pump();

    expect(find.text('Could not load equipment profiles'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Start Setup'), findsNothing);
  });

  testWidgets('profile loading is not rendered as first-time onboarding',
      (tester) async {
    await pumpAppScreen(
      tester,
      const EquipmentScreen(),
      extraOverrides: [
        equipmentProfilesProvider.overrideWith(_PendingProfilesNotifier.new),
      ],
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Start Setup'), findsNothing);
  });
}
