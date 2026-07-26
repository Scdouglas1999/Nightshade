import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/auto_save_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _MockAutoSaveService extends Mock implements AutoSaveService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AutoSaveConfig());
  });

  testWidgets('rejected schedule update rolls back optimistic switch',
      (tester) async {
    final service = _MockAutoSaveService();
    const config = AutoSaveConfig();
    when(() => service.config).thenReturn(config);
    when(() => service.status).thenReturn(const AutoSaveStatus());
    when(() => service.statusStream)
        .thenAnswer((_) => const Stream<AutoSaveStatus>.empty());
    when(() => service.updateConfig(any()))
        .thenAnswer((_) async => throw StateError('disk full'));

    await pumpAppScreen(
      tester,
      const AutoSaveSettings(),
      extraOverrides: [
        autoSaveServiceProvider.overrideWithValue(service),
      ],
    );

    final sequenceSwitch = find.byType(NightshadeSwitch).first;
    expect(
      tester.widget<NightshadeSwitch>(sequenceSwitch).value,
      config.sequenceEnabled,
    );

    await tester.tap(sequenceSwitch);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();

    expect(
      tester.widget<NightshadeSwitch>(sequenceSwitch).value,
      config.sequenceEnabled,
    );
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
