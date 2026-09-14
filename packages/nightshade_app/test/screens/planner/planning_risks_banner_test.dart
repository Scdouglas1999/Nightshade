import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planner/widgets/planning_risks_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The profile the owner reported the defect from: an ASI1600MM-Cool with no
/// sensor fields filled in and no camera connected.
const _ownersProfile = EquipmentProfileModel(
  name: 'Backyard rig',
  cameraId: 'ASI1600MM-Cool',
  cameraName: 'ASI1600MM-Cool',
  focalLength: 500,
  aperture: 100,
  defaultGain: 139,
  filterNames: ['L'],
);

const _unknownCameraProfile = EquipmentProfileModel(
  name: 'Mystery rig',
  cameraId: 'Acme SkyCam 9000',
  cameraName: 'Acme SkyCam 9000',
  focalLength: 500,
  aperture: 100,
  filterNames: ['L'],
);

Future<void> _pump(
  WidgetTester tester, {
  required List<String> riskFactors,
  EquipmentProfileModel? profile,
  Widget? child,
}) async {
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeEquipmentProfileProvider.overrideWithValue(profile),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: child ?? PlanningRisksBanner(riskFactors: riskFactors),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlanningRisksBanner', () {
    testWidgets('a non-sensor risk is said as the scorer said it', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: _ownersProfile,
        riskFactors: const [
          'Moon separation is tight; gradients or contrast loss are more '
              'likely.',
        ],
      );
      expect(
        find.textContaining('Moon separation is tight'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('planner_sensor_specs_banner')),
          findsNothing);
    });

    testWidgets(
        'several sensor caveats collapse into one banner that names '
        'the camera', (tester) async {
      await _pump(
        tester,
        profile: _unknownCameraProfile,
        riskFactors: [
          for (final field in [
            SensorSpecField.readNoise,
            SensorSpecField.fullWell,
            SensorSpecField.qePeak,
          ])
            sensorSpecCaveat(
              field: field,
              cameraLabel: 'Acme SkyCam 9000',
              estimate: 'an estimate',
            ),
        ],
      );

      expect(
        find.byKey(const ValueKey('planner_sensor_specs_banner')),
        findsOneWidget,
      );
      // ONE banner, and it names the camera it could not identify.
      expect(find.byType(NightshadeBanner), findsOneWidget);
      expect(
        find.textContaining('Acme SkyCam 9000'),
        findsWidgets,
      );
      // Geometry came off nothing either, so every field is listed.
      expect(find.textContaining('pixel size'), findsWidgets);
      // And the one action that fixes it is offered.
      expect(find.text('Enter camera specs'), findsOneWidget);
    });

    testWidgets(
        'a non-sensor risk rides on the sensor banner rather than '
        'becoming a second one', (tester) async {
      await _pump(
        tester,
        profile: _unknownCameraProfile,
        riskFactors: [
          sensorSpecCaveat(
            field: SensorSpecField.readNoise,
            cameraLabel: 'Acme SkyCam 9000',
            estimate: 'an estimate',
          ),
          'Usable imaging window is short.',
        ],
      );
      expect(find.byType(NightshadeBanner), findsOneWidget);
      expect(
        find.textContaining('Usable imaging window is short.'),
        findsOneWidget,
      );
    });

    testWidgets('a profile with no camera says that, not "specs unknown"', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: null,
        riskFactors: [
          sensorSpecCaveat(
            field: SensorSpecField.pixelSize,
            cameraLabel: 'this camera',
            estimate: 'an estimate',
          ),
        ],
      );
      expect(
        find.textContaining('This profile has no camera'),
        findsOneWidget,
      );
    });

    testWidgets('a malformed override is reported as its own problem', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: _ownersProfile,
        riskFactors: const [unreadableSensorOverridesCaveat],
      );
      // It is a sensor caveat, so it collapses into the sensor banner rather
      // than printing beside one.
      expect(find.byType(NightshadeBanner), findsOneWidget);
    });
  });

  group('CameraSensorSpecsRow', () {
    testWidgets('states the resolved values and where they came from', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: _ownersProfile,
        riskFactors: const [],
        child: const CameraSensorSpecsRow(),
      );

      // This is the answer to the owner's report: the Plan screen states the
      // ASI1600MM's published figures instead of calling them unknown.
      expect(
        find.text(
          '3.8 µm · 4656 × 3520 · 1.2 e⁻ read noise · 20,000 e⁻ well · 60% QE',
        ),
        findsOneWidget,
      );
      expect(find.text('Published specs'), findsOneWidget);
    });

    testWidgets('says nothing when nothing resolved', (tester) async {
      await _pump(
        tester,
        profile: _unknownCameraProfile,
        riskFactors: const [],
        child: const CameraSensorSpecsRow(),
      );
      expect(find.byType(ListRow), findsNothing);
    });

    testWidgets('says nothing when there is no camera at all', (tester) async {
      await _pump(
        tester,
        profile: null,
        riskFactors: const [],
        child: const CameraSensorSpecsRow(),
      );
      expect(find.byType(ListRow), findsNothing);
    });
  });
}
