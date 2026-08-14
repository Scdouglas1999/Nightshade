import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The A11Y-STATE contract for every shared interactive component.
///
/// AT-SPI derives "disabled" from the ABSENCE of the enabled flag, and Flutter
/// publishes that flag only when a widget passes `enabled:` explicitly. So a
/// control that merely carries a tap action — a bare `InkWell`, a
/// `GestureDetector`, Material's own dropdown — reaches a screen reader as an
/// inert, disabled panel while it works perfectly for a mouse. Eight separate
/// GUI clusters filed that same defect against different screens (IMG-6,
/// SEQ-10, EQP-4, SET-6/19, SKY-17, SCI-36, COL2-9/12/18, CON-47), which is
/// why it is pinned here at the components rather than per screen.
///
/// [assertOperableNodes] walks the whole semantics tree, so it also catches the
/// second half of the family: a widget that publishes TWO nodes, one named and
/// one operable, leaving assistive tech with no node that is both.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(body: Center(child: child)),
  );

  /// Every node that can be activated must declare a role and its enabled
  /// state; every node that declares a role must be operable.
  void assertOperableNodes(WidgetTester tester, {required String what}) {
    final root =
        tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
    final failures = <String>[];

    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      final isRole =
          data.hasFlag(SemanticsFlag.isButton) ||
          data.hasFlag(SemanticsFlag.hasCheckedState) ||
          data.hasFlag(SemanticsFlag.hasToggledState) ||
          data.hasFlag(SemanticsFlag.isSlider) ||
          data.hasFlag(SemanticsFlag.isTextField);
      final tappable = data.hasAction(SemanticsAction.tap);
      if (isRole || tappable) {
        if (!data.hasFlag(SemanticsFlag.hasEnabledState)) {
          failures.add('"${data.label}" has no enabled state');
        }
        if (tappable && !isRole) {
          failures.add('"${data.label}" is tappable but declares no role');
        }
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    expect(failures, isEmpty, reason: '$what: ${failures.join('; ')}');
  }

  SemanticsNode nodeOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder);

  group('declares role and enabled state', () {
    final cases = <String, Widget>{
      'NightshadeButton': NightshadeButton(label: 'Start', onPressed: () {}),
      'NightshadeChip': NightshadeChip(label: 'Ha', onTap: () {}),
      'NightshadeCard': NightshadeCard(onTap: () {}, child: const Text('Card')),
      'NightshadeCheckbox': NightshadeCheckbox(value: true, onChanged: (_) {}),
      'NightshadeSwitch': NightshadeSwitch(value: true, onChanged: (_) {}),
      'NightshadeSwitchRow': NightshadeSwitchRow(
        label: 'Regulated cooling',
        value: true,
        onChanged: (_) {},
      ),
      'NightshadeTextField': const NightshadeTextField(label: 'Name'),
      'NightshadeStepper': NightshadeStepper(value: 3, onChanged: (_) {}),
      'StatusPill': StatusPill(
        icon: LucideIcons.thermometer,
        label: 'Sensor Temp',
        value: '-10.0°C',
        onTap: () {},
      ),
      'SubTabButton': SubTabButton(
        label: 'Overview',
        isSelected: true,
        onTap: () {},
      ),
      'NavItem': NavItem(
        icon: LucideIcons.home,
        label: 'Dashboard',
        description: 'Tonight at a glance',
        isSelected: true,
        isExpanded: true,
        onTap: () {},
      ),
      'ScienceInfoButton': const ScienceInfoButton(
        title: 'Optical diagnostics',
        body: 'What the numbers mean.',
      ),
      'AccessibleIconButton': AccessibleIconButton(
        icon: LucideIcons.bell,
        label: 'Alerts',
        onPressed: () {},
      ),
      'NightshadeAlert': NightshadeAlert(
        message: 'Cooler is warming',
        onDismiss: () {},
      ),
    };

    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(entry.value));
        await tester.pump();
        assertOperableNodes(tester, what: entry.key);
        handle.dispose();
      });
    }

    testWidgets('AdaptiveTabBar', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 600,
            child: AdaptiveTabBar(
              tabs: const [
                AdaptiveTab(label: 'Session', icon: LucideIcons.play),
                AdaptiveTab(label: 'History', icon: LucideIcons.history),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      assertOperableNodes(tester, what: 'AdaptiveTabBar');
      handle.dispose();
    });
  });

  group('NightshadeDropdown', () {
    testWidgets('the closed control is one enabled button node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          NightshadeDropdown(
            value: 'Light',
            items: const ['Light', 'Dark', 'Flat'],
            onChanged: (_) {},
          ),
        ),
      );

      assertOperableNodes(tester, what: 'NightshadeDropdown closed');
      final node = nodeOf(tester, find.byType(DropdownButton<String>));
      final data = node.getSemanticsData();
      expect(data.label, 'Light');
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
      // The closed control shows the chosen item; it must not inherit that
      // item's selected state and announce itself as a menu entry.
      expect(data.hasFlag(SemanticsFlag.hasSelectedState), isFalse);
      handle.dispose();
    });

    testWidgets('a disabled control says so instead of staying silent', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const NightshadeDropdown(value: 'Light', items: ['Light', 'Dark']),
        ),
      );

      final data = nodeOf(
        tester,
        find.byType(DropdownButton<String>),
      ).getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(data.hasFlag(SemanticsFlag.isEnabled), isFalse);
      handle.dispose();
    });

    testWidgets('every menu entry is enabled and marks the chosen one', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          NightshadeDropdown(
            value: 'Dark',
            items: const ['Light', 'Dark', 'Red night'],
            onChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byType(NightshadeDropdown));
      await tester.pumpAndSettle();

      final entries = <String, SemanticsData>{};
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.hasFlag(SemanticsFlag.hasSelectedState)) {
          entries[data.label] = data;
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

      expect(entries.keys, containsAll(['Light', 'Dark', 'Red night']));
      for (final entry in entries.entries) {
        expect(
          entry.value.hasFlag(SemanticsFlag.isEnabled),
          isTrue,
          reason: '${entry.key} is live but announces itself as disabled',
        );
        expect(
          entry.value.hasFlag(SemanticsFlag.isSelected),
          entry.key == 'Dark',
          reason: '${entry.key} reports the wrong selected state',
        );
        // NEW-C4: a live tree dump of the open Theme / Frame Type / sort menus
        // showed three bare `button:` entries and nothing marking the current
        // one. AT-SPI's SELECTED is not what a menu consumer reads; CHECKED is,
        // and it is the state a radio-style menu is meant to publish.
        expect(
          entry.value.hasFlag(SemanticsFlag.hasCheckedState),
          isTrue,
          reason:
              '${entry.key} offers no checked state, so nothing in the '
              'menu says which option is in force',
        );
        expect(
          entry.value.hasFlag(SemanticsFlag.isChecked),
          entry.key == 'Dark',
          reason: '${entry.key} reports the wrong checked state',
        );
      }
      handle.dispose();
    });
  });

  group('state is carried, not just painted', () {
    testWidgets('a selectable chip announces its selection', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(NightshadeChip(label: 'Failed', selected: true, onTap: () {})),
      );
      expect(
        nodeOf(
          tester,
          find.byType(NightshadeChip),
        ).getSemanticsData().hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('a switch row names the setting it toggles', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          NightshadeSwitchRow(
            label: 'Start cooling when the camera connects',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );
      final data = nodeOf(
        tester,
        find.byType(NightshadeSwitch),
      ).getSemanticsData();
      expect(data.label, 'Start cooling when the camera connects');
      expect(data.hasFlag(SemanticsFlag.isToggled), isTrue);
      handle.dispose();
    });

    testWidgets('a labelled field carries its label on the field node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const NightshadeTextField(label: 'Step size')),
      );
      expect(
        nodeOf(tester, find.byType(TextFormField)).getSemanticsData().label,
        'Step size',
      );
      handle.dispose();
    });

    testWidgets('an icon button is one node that is both named and operable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await tester.pumpWidget(
        host(
          AccessibleIconButton(
            icon: LucideIcons.settings,
            label: 'Settings',
            onPressed: () => pressed++,
          ),
        ),
      );

      final node = nodeOf(tester, find.byType(AccessibleIconButton));
      final data = node.getSemanticsData();
      expect(data.label, 'Settings');
      expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      expect(pressed, 1);
      handle.dispose();
    });
  });
}
