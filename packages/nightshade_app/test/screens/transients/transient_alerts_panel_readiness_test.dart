import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/suggestions/widgets/transient_alerts_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';

class _Dao extends Mock implements SettingsDao {}

class _Logger extends Mock implements LoggingService {}

class _Science extends ScienceSettingsNotifier {
  _Science(this.configured);
  final bool configured;

  @override
  Future<ScienceSettings> build() async => ScienceSettings(
        tnsBotId: configured ? 42 : 0,
        tnsBotName: configured ? 'bot' : '',
      );
}

TransientAlert _alert() => TransientAlert(
      id: 'sn-2026abc',
      name: 'SN 2026abc',
      type: TransientType.supernova,
      raHours: 12,
      decDegrees: 20,
      magnitude: 14.2,
      discoveryTime: DateTime.utc(2026, 8, 1),
      lastUpdated: DateTime.utc(2026, 8, 2),
      source: TransientSource.tns,
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool configured,
  bool remote = false,
  bool initiallyExpanded = false,
  Set<TransientSource> enabledSources = const {TransientSource.tns},
  Stream<List<TransientAlert>>? alerts,
}) async {
  final secrets = SecretsStore(InMemorySecureKeyValueStore());
  if (configured) await secrets.write(SecretField.tnsApiKey, 'key');
  final dao = _Dao();
  when(() => dao.getSetting(any())).thenAnswer((_) async => null);
  when(() => dao.getAllSettings()).thenAnswer(
    (_) async => enabledSources.contains(TransientSource.tns)
        ? const {}
        : {
            'transient_alert_enabled_sources': jsonEncode(
                enabledSources.map((source) => source.name).toList()),
          },
  );
  when(() => dao.setSetting(any(), any())).thenAnswer((_) async {});
  final logger = _Logger();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secretsStoreProvider.overrideWithValue(secrets),
        isRemoteModeProvider.overrideWithValue(remote),
        scienceSettingsProvider.overrideWith(() => _Science(configured)),
        transientAlertSettingsProvider
            .overrideWith((ref) => TransientAlertSettingsNotifier(
                  settingsDao: dao,
                  logger: logger,
                )..state = TransientAlertSettings(
                    enabledSources: enabledSources,
                  )),
        transientAlertStatesProvider.overrideWith(
          (ref) => TransientAlertStatesNotifier(
            settingsDao: dao,
            logger: logger,
          ),
        ),
        activeTransientAlertsProvider.overrideWith(
          (ref) =>
              alerts ??
              Stream<List<TransientAlert>>.error(
                StateError('TNS request failed'),
              ),
        ),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: TransientAlertsPanel(initiallyExpanded: initiallyExpanded),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('missing credentials dominate a fetch error in compact state',
      (tester) async {
    await _pump(tester, configured: false);
    expect(find.text('Setup needed for live TNS alerts'), findsOneWidget);
    expect(find.textContaining('TNS request failed'), findsNothing);
    expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);
  });

  testWidgets('configured fetch errors are sanitized and visibly red',
      (tester) async {
    await _pump(tester, configured: true);
    expect(find.textContaining('Fetch failed:'), findsOneWidget);
    expect(find.textContaining('Bad state:'), findsNothing);
    expect(find.textContaining('TNS request failed'), findsOneWidget);
  });

  testWidgets('configured success shows a truthful compact summary and details',
      (tester) async {
    await _pump(
      tester,
      configured: true,
      alerts: Stream.value([_alert()]),
    );
    expect(find.text('1 alert · SN 2026abc, mag 14.2'), findsOneWidget);
    expect(find.text('SN 2026abc'), findsNothing);

    await tester.tap(find.byTooltip('Expand alerts'));
    await tester.pump();
    expect(find.text('SN 2026abc'), findsOneWidget);
    expect(find.textContaining('No transient alerts'), findsNothing);
  });

  testWidgets('manual-only mode does not claim TNS setup', (tester) async {
    await _pump(
      tester,
      configured: false,
      enabledSources: {TransientSource.manual},
      alerts: Stream.value(const <TransientAlert>[]),
    );
    expect(find.text('No active alerts'), findsOneWidget);
    expect(find.textContaining('Setup needed'), findsNothing);

    await tester.tap(find.byTooltip('Expand alerts'));
    await tester.pump();
    expect(find.text('No transient alerts'), findsOneWidget);
    expect(find.textContaining('not configured'), findsNothing);
  });

  testWidgets('remote empty state does not require local credentials',
      (tester) async {
    await _pump(
      tester,
      configured: false,
      remote: true,
      alerts: Stream.value(const <TransientAlert>[]),
    );
    expect(find.text('No active alerts'), findsOneWidget);
    expect(find.textContaining('Setup needed'), findsNothing);
  });

  testWidgets('remote fetch failure remains a visible operational error',
      (tester) async {
    await _pump(
      tester,
      configured: false,
      remote: true,
      alerts: Stream<List<TransientAlert>>.error(
        StateError('remote transient service unavailable'),
      ),
    );
    expect(find.textContaining('Fetch failed:'), findsOneWidget);
    expect(find.textContaining('Bad state:'), findsNothing);
    expect(find.textContaining('remote transient service unavailable'),
        findsOneWidget);
  });
}
