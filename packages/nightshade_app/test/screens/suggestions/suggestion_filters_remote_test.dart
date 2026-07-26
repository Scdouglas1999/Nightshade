import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/suggestions/widgets/suggestion_filters.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' show Target;
import 'package:nightshade_ui/nightshade_ui.dart';

Target _target({
  required int id,
  required String name,
  required String objectType,
}) {
  final now = DateTime.utc(2026, 7, 13);
  return Target(
    id: id,
    name: name,
    objectType: objectType,
    ra: 0,
    dec: 0,
    minAltitude: 20,
    priority: 1,
    totalPlannedSubs: 0,
    capturedSubs: 0,
    totalIntegrationSecs: 0,
    goalIntegrationSecs: 0,
    createdAt: now,
    updatedAt: now,
    isFavorite: false,
  );
}

void main() {
  testWidgets('object type chips use the host-aware target provider',
      (tester) async {
    final hostTargets = [
      _target(id: 1, name: 'M31', objectType: 'galaxy'),
      _target(id: 2, name: 'M42', objectType: 'emission_nebula'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allDbTargetsProvider.overrideWith(
            (ref) => Stream.value(hostTargets),
          ),
          availableConstellationsProvider.overrideWith((ref) => const []),
          availableMagnitudeRangeProvider.overrideWith((ref) => null),
          availableSizeRangeProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SuggestionFilters(showAsSheet: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Object Types'), findsOneWidget);
    expect(find.text('Galaxy'), findsOneWidget);
    expect(find.text('Emission Nebula'), findsOneWidget);
  });
}
