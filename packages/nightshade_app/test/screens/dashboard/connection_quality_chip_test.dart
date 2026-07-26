import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/connection_quality_chip.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('quality stream failure is never labeled Local', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionQualityProvider.overrideWith(
            (ref) => Stream<ConnectionQuality>.error(
              StateError('quality unavailable'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: ConnectionQualityChip(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Local'), findsNothing);
  });
}
