import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/equipment_screen.dart';
import 'package:nightshade_app/screens/equipment/widgets/profile_sidebar.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

Future<void> _drainFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('mobile layout hides inline profile sidebar', (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const EquipmentScreen(),
      size: const Size(390, 844),
      settle: false,
    );

    final dao = handle.container.read(equipmentProfilesDaoProvider);
    await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: 'Mobile Test Profile',
      ),
    );
    await _drainFrames(tester);

    expect(find.byType(ProfileSidebar), findsNothing);
    expect(find.text('Mobile Test Profile'), findsOneWidget);
  });

  testWidgets('tapping profile header opens profile sheet on mobile',
      (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const EquipmentScreen(),
      size: const Size(390, 844),
      settle: false,
    );

    final dao = handle.container.read(equipmentProfilesDaoProvider);
    await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: 'Sheet Profile',
      ),
    );
    await _drainFrames(tester);

    await tester.tap(find.text('Sheet Profile'));
    await _drainFrames(tester);

    expect(find.byType(ProfileSidebar), findsOneWidget);
  });
}
