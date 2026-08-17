// The sequence timeline's twilight overlay painted its three band hues raw —
// Material light blue for civil, Material blue for nautical and
// `NightshadeChartColors.twilightAstro()` (seriesIndigo) for astronomical —
// both behind the timeline bar and in the legend beneath it. Red night is a
// WAVELENGTH constraint, so those bands washed solid blue across a screen whose
// every other pixel was red, undoing the dark adaptation the mode exists to
// protect. Band hue is chart data, so it goes through
// `NightshadeChartColors.forTheme` like any other series.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_timeline.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/mock_database.dart' show inMemoryDatabaseOverride;

/// Fraction of the emitted channel energy carried by red.
double _redShare(Color c) {
  final total = c.r + c.g + c.b;
  return total == 0 ? 1.0 : c.r / total;
}

void _expectRedNightSafe(Color c, String what) {
  expect(c.g, lessThanOrEqualTo(c.r),
      reason: '$what emits more green than red');
  expect(c.b, lessThanOrEqualTo(c.r), reason: '$what emits more blue than red');
  expect(_redShare(c), greaterThan(0.5),
      reason: '$what does not keep red dominant');
}

/// A rig with a real location, so the timeline computes twilight at all: the
/// overlay is suppressed outright at lat/lon 0,0.
class _LocatedSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState(
        latitude: 40.02,
        longitude: -105.27,
      );
}

/// One exposure long enough to span a whole day, anchored at local midnight, so
/// every twilight boundary of that date falls inside the timeline window and
/// all three bands render.
Sequence _dayLongSequence() {
  final exposure = ExposureNode(
    name: 'All night',
    durationSecs: 86400,
    count: 1,
    ditherEvery: null,
  );
  final root = InstructionSetNode(name: 'Root', childIds: [exposure.id]);
  return Sequence.create(
    name: 'Twilight band test',
    rootNodeId: root.id,
    nodes: {
      root.id: root,
      exposure.id: exposure.copyWith(parentId: root.id),
    },
  );
}

/// Every solid colour the timeline actually hands to a [Container].
List<Color> _paintedColors(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.color)
    .whereType<Color>()
    .toList(growable: false);

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required ThemeData theme,
  required NightshadeColors colors,
}) async {
  final editor = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  editor.state = _dayLongSequence();
  final container = ProviderContainer(
    overrides: [
      inMemoryDatabaseOverride(),
      currentSequenceProvider.overrideWith((_) => editor),
      appSettingsProvider.overrideWith(_LocatedSettings.new),
      sequencerOverheadConfigProvider.overrideWithValue(
        const SequenceOverheadConfig(downloadOverheadPerExposureSecs: 0),
      ),
    ],
  );
  addTearDown(container.dispose);

  final midnight = DateTime(2026, 7, 14);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SequenceTimeline(
            colors: colors,
            startTime: midnight,
          ),
        ),
      ),
    ),
  );
  await container.read(appSettingsProvider.future);
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .physicalSize = const Size(1400, 1200);
    TestWidgetsFlutterBinding
        .instance.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
  });

  testWidgets('red night draws all three twilight bands from the remap',
      (tester) async {
    await _pumpTimeline(
      tester,
      theme: NightshadeTheme.redNight,
      colors: NightshadeColors.redNight,
    );

    final painted = _paintedColors(tester);
    for (final entry in <String, Color>{
      'civil': namedCivilTwilightBand,
      'nautical': namedNauticalTwilightBand,
      'astro': namedAstroTwilightBand,
    }.entries) {
      final resolved = NightshadeChartColors.forTheme(
          entry.value, NightshadeColors.redNight);
      expect(
        painted,
        contains(resolved),
        reason: 'the ${entry.key} twilight band is not drawn from forTheme',
      );
      expect(
        painted,
        isNot(contains(entry.value)),
        reason: 'the ${entry.key} band still paints its named hue raw',
      );
      _expectRedNightSafe(resolved, '${entry.key} twilight band');
    }
  });

  testWidgets('dark keeps the named band hues exactly', (tester) async {
    await _pumpTimeline(
      tester,
      theme: NightshadeTheme.dark,
      colors: NightshadeColors.dark,
    );

    final painted = _paintedColors(tester);
    for (final named in [
      namedCivilTwilightBand,
      namedNauticalTwilightBand,
      namedAstroTwilightBand,
    ]) {
      expect(painted, contains(named),
          reason: 'the remap must be the identity outside red night');
    }
  });
}
