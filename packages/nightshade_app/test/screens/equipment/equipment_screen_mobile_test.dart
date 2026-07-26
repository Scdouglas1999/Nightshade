import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/equipment_screen.dart';
import 'package:nightshade_app/screens/equipment/widgets/discovery_panel.dart';
import 'package:nightshade_app/screens/equipment/widgets/equipment_health_panel.dart';
import 'package:nightshade_app/screens/equipment/widgets/profile_sidebar.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

Future<void> _drainFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The three standard phone sizes (portrait) the mobile-responsive standard
/// requires every reworked screen to verify, plus their landscape rotations.
const _phoneSizes = <(String, Size)>[
  ('small 360x640', Size(360, 640)),
  ('modern 390x844', Size(390, 844)),
  ('large 430x932', Size(430, 932)),
];

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

  // ---------------------------------------------------------------------------
  // Phone-tier layout / overflow guard, all three sizes, both orientations.
  //
  // Portrait phones (<600 wide) collapse the inline ProfileSidebar to a sheet.
  // A rotated phone can exceed the 600/768 width thresholds (e.g. 844 wide), in
  // which case the screen legitimately shows the side-by-side desktop layout —
  // still no overflow, just more room. So the universal guards are: no overflow
  // at any size/orientation, and the profile (primary surface) is reachable;
  // the sidebar-collapse assertion only applies under the phone width.
  // ---------------------------------------------------------------------------
  for (final (label, portrait) in _phoneSizes) {
    final landscape = Size(portrait.height, portrait.width);

    for (final (orientation, size) in <(String, Size)>[
      ('portrait', portrait),
      ('landscape', landscape),
    ]) {
      testWidgets('equipment has no overflow at $label $orientation',
          (tester) async {
        final handle = await pumpAppScreen(
          tester,
          const EquipmentScreen(),
          size: size,
          settle: false,
        );

        final dao = handle.container.read(equipmentProfilesDaoProvider);
        await dao.createProfile(
          EquipmentProfilesCompanion.insert(name: 'Phone Layout Profile'),
        );
        await _drainFrames(tester);

        // No RenderFlex overflow exception was thrown during layout/paint.
        expect(tester.takeException(), isNull);
        // The profile name (the primary header surface) is rendered. A wide
        // landscape phone may show it twice (header + inline sidebar), so use
        // findsWidgets — the guard is "reachable", not "exactly one".
        expect(find.text('Phone Layout Profile'), findsWidgets);
        // Under the phone width the inline desktop sidebar collapses to a sheet.
        if (size.width < 600) {
          expect(find.byType(ProfileSidebar), findsNothing);
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Regression: the phone supporting panels must SCROLL WITH the device cards.
  //
  // They used to be pinned Column siblings above the card list. Collapsed, that
  // chrome pinned ~330dp above the cards on a 411x914dp phone and clipped the
  // first device card through its own readouts. EXPANDED, the readiness
  // checklist overflowed the column by 108px and evicted every device card AND
  // the discovery scanner off-screen, with no scroll to bring them back. The
  // existing "no overflow" cases above all run with the checklist COLLAPSED
  // (its default), which is exactly why they never caught it.
  // ---------------------------------------------------------------------------
  for (final (label, portrait) in _phoneSizes) {
    testWidgets('equipment supporting panels scroll with the cards at $label',
        (tester) async {
      final handle = await pumpAppScreen(
        tester,
        const EquipmentScreen(),
        size: portrait,
        settle: false,
      );

      final dao = handle.container.read(equipmentProfilesDaoProvider);
      await dao.createProfile(
        EquipmentProfilesCompanion.insert(name: 'Scroll Chrome Profile'),
      );
      await _drainFrames(tester);
      expect(tester.takeException(), isNull);

      // The health panel — the first of the supporting panels — must sit inside
      // a Scrollable. Pinned as a Column sibling it had no Scrollable ancestor.
      expect(
        find.ancestor(
          of: find.byType(EquipmentHealthPanel),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
        reason: 'supporting panels are pinned again instead of scrolling',
      );

      // Expanding the readiness checklist must not overflow the column. The
      // bar's label tracks the readiness verdict, so accept either wording.
      for (final label in const ['Ready to image', 'Not ready']) {
        final bar = find.text(label).hitTestable();
        if (bar.evaluate().isEmpty) continue;
        await tester.tap(bar.first);
        await _drainFrames(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'expanding the readiness checklist overflowed the layout',
        );
        break;
      }
    });
  }

  // Regression: on a SHORT viewport the Discovery scanner must stop pinning
  // itself. Pinned, it left the card list ~66dp on a 360x640dp phone and was
  // itself squeezed under its own content, overflowing by 8px. Below the
  // threshold it scrolls with the cards instead, which can never overflow.
  for (final (label, size) in const <(String, Size)>[
    ('short 360x560', Size(360, 560)),
    ('very short 360x480', Size(360, 480)),
    ('compact 360x640', Size(360, 640)),
  ]) {
    testWidgets('equipment does not overflow on a short viewport at $label',
        (tester) async {
      final handle = await pumpAppScreen(
        tester,
        const EquipmentScreen(),
        size: size,
        settle: false,
      );

      final dao = handle.container.read(equipmentProfilesDaoProvider);
      await dao.createProfile(
        EquipmentProfilesCompanion.insert(name: 'Short Viewport Profile'),
      );
      await _drainFrames(tester);
      expect(tester.takeException(), isNull);

      // The scanner stays reachable however it was laid out.
      expect(find.byType(DiscoveryPanel), findsOneWidget);

      // And expanding the readiness checklist on top of that still must not
      // overflow — this is the worst case the screen has to survive.
      for (final barLabel in const ['Ready to image', 'Not ready']) {
        final bar = find.text(barLabel).hitTestable();
        if (bar.evaluate().isEmpty) continue;
        await tester.tap(bar.first);
        await _drainFrames(tester);
        expect(tester.takeException(), isNull);
        break;
      }
    });
  }

  testWidgets('equipment rotates portrait→landscape without clipping',
      (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const EquipmentScreen(),
      size: const Size(390, 844),
      settle: false,
    );

    final dao = handle.container.read(equipmentProfilesDaoProvider);
    await dao.createProfile(
      EquipmentProfilesCompanion.insert(name: 'Rotate Profile'),
    );
    await _drainFrames(tester);
    expect(tester.takeException(), isNull);
    // Portrait phone: sidebar collapsed.
    expect(find.byType(ProfileSidebar), findsNothing);

    // Rotate in place to a narrow-but-wide landscape (still < 600 tall, and
    // here we keep width < 600 by using a compact-phone landscape so the phone
    // layout — not the desktop sidebar — is what we rotate into).
    tester.view.physicalSize = const Size(640, 360);
    await _drainFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Rotate Profile'), findsOneWidget);
  });
}
