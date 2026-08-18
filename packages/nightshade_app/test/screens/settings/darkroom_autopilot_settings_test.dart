// The dawn Darkroom autopilot's settings surface.
//
// `darkroom.auto_draft` shipped as a raw `app_settings` row with no widget, no
// API and absent-means-on, and Settings said nothing about the Darkroom at all
// — "darkroom", "draft", "recipe" and "auto draft" each returned "No settings
// match your search". A single D1 night on that unmentioned default wrote 4
// recipes, 4 draft JPEGs, 4 sidecars, a night report, 9 delivered files and a
// morning notification. These tests pin the surface that now answers for it:
// where it lives, what it says, and that the switch writes the row the pass
// reads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/localization/nightshade_localizations.dart';
import 'package:nightshade_app/screens/session_review/auto_integration_service.dart';
import 'package:nightshade_app/screens/settings/settings_catalog.dart';
import 'package:nightshade_app/screens/settings/widgets/darkroom_autopilot_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_database.dart';
import '../../harness/pump_app_screen.dart';

void main() {
  Future<List<SettingsGroupDef>> catalog(WidgetTester tester) async {
    late List<SettingsGroupDef> groups;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NightshadeLocalizations.localizationsDelegates,
        supportedLocales: NightshadeLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            groups = buildSettingsGroups(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return groups;
  }

  testWidgets('the dawn autopilot sits beside Delivery in Automation', (
    tester,
  ) async {
    final groups = await catalog(tester);
    final owning = groups.firstWhere(
      (g) => g.sections.any((s) => s.key == 'darkroom'),
      orElse: () => throw StateError(
        'no settings group renders the darkroom section: '
        '${groups.map((g) => g.title).toList()}',
      ),
    );
    expect(owning.title, 'Automation & Safety');

    // Adjacent, not merely co-grouped: the pass composes what Delivery
    // carries, and a reader who finds one has found the other.
    final keys = owning.sections.map((s) => s.key).toList();
    expect(
      (keys.indexOf('delivery') - keys.indexOf('darkroom')).abs(),
      1,
      reason: 'order was $keys',
    );
  });

  test('the locale-independent group lookup agrees with the catalog', () {
    // `groupTitleForKey` reads `_structuralGroups`, a separate list from the
    // one `buildSettingsGroups` builds; a section added to only one of them
    // has a sidebar entry and no breadcrumb, or the reverse.
    expect(groupTitleForKey('darkroom'), 'Automation & Safety');
    expect(resolveSectionKey('darkroom'), 'darkroom');
  });

  testWidgets('the page names the whole chain, not just the draft', (
    tester,
  ) async {
    final db = mockDatabase();
    addTearDown(db.close);
    await pumpAppScreen(
      tester,
      const DarkroomAutopilotSettings(),
      database: db,
    );

    // The row that governs it.
    expect(find.text('Draft, deliver and report at dawn'), findsOneWidget);
    // Every link of the chain is named in the copy — the defect being fixed is
    // a switch that described half of what it does.
    final subtitle = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    for (final claim in [
      'first-draft',
      'draft render',
      'night report',
      'delivery destination',
      'notification',
    ]) {
      expect(subtitle.toLowerCase(), contains(claim.toLowerCase()),
          reason: '"$claim" is part of what this setting governs');
    }

    // And the neighbours that can silence it, with the one that can silence it
    // completely stating its own live state.
    expect(
      find.text('Auto-integrate has to be on for any of this to run'),
      findsOneWidget,
    );
    expect(
      find.text('The morning message rides the sequence-complete alerts'),
      findsOneWidget,
    );
    expect(
      find.textContaining('It is currently off.'),
      findsOneWidget,
      reason: 'the dependency is only useful beside what it currently says',
    );
  });

  testWidgets('the switch shows on for a row nobody has written', (
    tester,
  ) async {
    // Absent means ON — the pass reads the same absence the same way
    // (`isDarkroomAutoDraftEnabled`), so a switch showing "off" here would be
    // describing a night that is about to draft itself.
    final db = mockDatabase();
    addTearDown(db.close);
    final handle = await pumpAppScreen(
      tester,
      const DarkroomAutopilotSettings(),
      database: db,
    );
    await tester.pumpAndSettle();

    expect(
      await SettingsDao(db).getSetting(kDarkroomAutoDraftSettingKey),
      isNull,
      reason: 'the case is a row that was never written',
    );
    final control = tester.widget<NightshadeSwitch>(
      find.byKey(const ValueKey('darkroom-auto-draft-switch')),
    );
    expect(control.value, isTrue);
    expect(
      handle.container.read(darkroomAutoDraftEnabledProvider).valueOrNull,
      isTrue,
    );
  });

  testWidgets('turning it off writes the value the pass reads', (
    tester,
  ) async {
    final db = mockDatabase();
    addTearDown(db.close);
    await pumpAppScreen(
      tester,
      const DarkroomAutopilotSettings(),
      database: db,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('darkroom-auto-draft-switch')),
    );
    await tester.pumpAndSettle();

    // `_runDarkroom` skips only on the literal string 'false'.
    expect(
      await SettingsDao(db).getSetting(kDarkroomAutoDraftSettingKey),
      'false',
    );
    expect(
      tester
          .widget<NightshadeSwitch>(
            find.byKey(const ValueKey('darkroom-auto-draft-switch')),
          )
          .value,
      isFalse,
    );

    await tester.tap(
      find.byKey(const ValueKey('darkroom-auto-draft-switch')),
    );
    await tester.pumpAndSettle();
    expect(
      await SettingsDao(db).getSetting(kDarkroomAutoDraftSettingKey),
      'true',
    );
  });

  // The gate is the client ROLE, not the live connection — the same gate
  // Delivery and the Darkroom editor read. `darkroom.auto_draft` is a row in
  // whichever profile database this process opened, and the dawn pass reads
  // the one on the machine that integrated the masters.
  group('the dawn pass belongs to the machine that owns the masters', () {
    Future<void> pumpAs(
      WidgetTester tester, {
      required bool launchedAsClient,
      required bool connected,
      required NightshadeDatabase db,
    }) async {
      await pumpAppScreen(
        tester,
        const DarkroomAutopilotSettings(),
        database: db,
        extraOverrides: [
          remoteClientLaunchProvider.overrideWithValue(launchedAsClient),
          isRemoteModeProvider.overrideWithValue(connected),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a connected client is told where the switch lives', (
      tester,
    ) async {
      final db = mockDatabase();
      addTearDown(db.close);
      await pumpAs(
        tester,
        launchedAsClient: false,
        connected: true,
        db: db,
      );

      expect(
        find.text('The dawn pass runs on the imaging host'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('darkroom-auto-draft-switch')),
        findsNothing,
      );
    });

    testWidgets(
      'a client that has not reached its rig yet is still that rig\'s client',
      (tester) async {
        // The launch flags said `--remote-host`; the handshake has not landed
        // (or it has dropped), so the connection-shaped gate reads false. On
        // that gate the page offered a live switch, and one click wrote
        // `darkroom.auto_draft=false` here while the rig kept drafting,
        // delivering and notifying at dawn.
        final db = mockDatabase();
        addTearDown(db.close);
        await pumpAs(
          tester,
          launchedAsClient: true,
          connected: false,
          db: db,
        );

        expect(
          find.text('The dawn pass runs on the imaging host'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('darkroom-auto-draft-switch')),
          findsNothing,
          reason: 'a switch here writes a row no dawn job will ever read',
        );
        expect(
          await SettingsDao(db).getSetting(kDarkroomAutoDraftSettingKey),
          isNull,
        );
      },
    );

    testWidgets('a host launch keeps its own switch', (tester) async {
      final db = mockDatabase();
      addTearDown(db.close);
      await pumpAs(
        tester,
        launchedAsClient: false,
        connected: false,
        db: db,
      );

      expect(
        find.text('The dawn pass runs on the imaging host'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('darkroom-auto-draft-switch')),
        findsOneWidget,
      );
    });
  });

  testWidgets('the dependency row carries the page\'s own density', (
    tester,
  ) async {
    // Hardcoded `isMobile: false` put desktop padding, icon size and title
    // ramp on one row inside a phone-width section whose siblings were at
    // phone density.
    final db = mockDatabase();
    addTearDown(db.close);
    await pumpAppScreen(
      tester,
      const DarkroomAutopilotSettings(isMobile: true),
      database: db,
      size: const Size(430, 900),
    );
    await tester.pumpAndSettle();

    bool densityOf(String title) => tester
        .widgetList<SettingRow>(find.byType(SettingRow))
        .firstWhere((row) => row.title == title)
        .isMobile;

    expect(densityOf('Auto-integrate has to be on for any of this to run'),
        isTrue);
    expect(
      densityOf('Delivery destinations decide what leaves the rig'),
      isTrue,
      reason: 'the sibling it is misaligned against',
    );
  });

  testWidgets('the dependency row states its neighbour\'s state once', (
    tester,
  ) async {
    // `SettingRow` merges its title, subtitle and trailing into one node, so
    // the colour-coded echo beside the sentence was read out a second time,
    // as a bare "off" with nothing to bind it to.
    final db = mockDatabase();
    addTearDown(db.close);
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      const DarkroomAutopilotSettings(),
      database: db,
    );
    await tester.pumpAndSettle();

    final label = tester
        .getSemantics(
          find.text('Auto-integrate has to be on for any of this to run'),
        )
        .label
        .trim();

    expect(label, contains('It is currently off.'));
    expect(
      label,
      endsWith('Settings › Image Grading › Post-session integration.'),
      reason: 'the sentence carries the state; the visual echo must not '
          'publish a second, unbound copy of it',
    );
    // The echo is still on screen for the eye scanning the column.
    expect(find.text('off'), findsOneWidget);
    semantics.dispose();
  });
}
