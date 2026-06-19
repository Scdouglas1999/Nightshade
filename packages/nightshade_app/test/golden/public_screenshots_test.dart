@Tags(['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_app/screens/equipment/equipment_screen.dart';
import 'package:nightshade_app/screens/flat_wizard/flat_wizard_screen.dart';
import 'package:nightshade_app/screens/framing/framing_screen.dart';
import 'package:nightshade_app/screens/guiding/guiding_screen.dart';
import 'package:nightshade_app/screens/imaging/imaging_screen.dart';
import 'package:nightshade_app/screens/planetarium/planetarium_screen.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_app/screens/sequencer/sequencer_screen.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/weather/weather_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../harness/harness.dart';
import 'surface_golden_harness.dart';

const _size = Size(1600, 900);

int _gb(int value) => value * 1024 * 1024 * 1024;

final _schedulerDecision = SchedulerDecision(
  chosenTargetId: 7000,
  chosenTargetName: 'NGC 7000 - North America Nebula',
  score: 0.86,
  reasoning: const [
    'High altitude, strong Ha priority, and 4.6 hours remain before dawn.',
  ],
  scoredCandidates: const [
    TargetScore(
      targetId: 7000,
      targetName: 'NGC 7000 - North America Nebula',
      totalScore: 0.86,
      factors: [
        ScoreFactor(
          name: 'Altitude',
          value: 0.91,
          weight: 0.35,
          weighted: 0.32,
          detail: '68 deg above horizon',
        ),
        ScoreFactor(
          name: 'Priority',
          value: 0.9,
          weight: 0.3,
          weighted: 0.27,
          detail: 'project priority 5',
        ),
      ],
    ),
  ],
  evaluatedAt: DateTime(2026, 6, 18, 22, 45),
);

final _screenshotProfile = EquipmentProfileModel(
  id: 1,
  name: 'Backyard Pier',
  description: 'EQ6-R narrowband rig',
  isActive: true,
  cameraId: 'asi2600mm',
  mountId: 'eq6r',
  focuserId: 'eaf',
  filterWheelId: 'efw',
  guiderId: 'phd2',
  cameraName: 'ZWO ASI2600MM Pro',
  mountName: 'EQ6-R Pro',
  focuserName: 'ZWO EAF',
  filterWheelName: 'ZWO EFW 7x36',
  guiderName: 'PHD2',
  telescopeName: 'Esprit 100ED',
  telescopeFocalLength: 550,
  telescopeAperture: 100,
  focalLength: 550,
  aperture: 100,
  focalRatio: 5.5,
  defaultGain: 100,
  defaultOffset: 50,
  defaultCoolingTemp: -10,
  coolOnConnect: true,
  filterNames: const ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'],
  isDefault: true,
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 18),
);

final _screenshotSequence = Sequence(
  id: 'screenshot-narrowband',
  name: 'NGC 7000 Narrowband Run',
  description: 'Ha/OIII/SII sequence with autofocus and dithering.',
  createdAt: DateTime(2026, 6, 18, 21, 50),
  modifiedAt: DateTime(2026, 6, 18, 22, 35),
  estimatedDurationMins: 360,
  rootNodeId: 'nb-root',
  nodes: {
    'nb-root': InstructionSetNode(
      id: 'nb-root',
      name: 'NGC 7000 Narrowband Run',
      childIds: const ['nb-target'],
    ),
    'nb-target': TargetHeaderNode(
      id: 'nb-target',
      name: 'NGC 7000',
      targetName: 'NGC 7000 - North America Nebula',
      raHours: 20.981,
      decDegrees: 44.33,
      minAltitude: 30,
      priority: 5,
      childIds: const ['nb-cool', 'nb-focus', 'nb-loop', 'nb-warm'],
      parentId: 'nb-root',
    ),
    'nb-cool': CoolCameraNode(
      id: 'nb-cool',
      targetTemp: -10,
      parentId: 'nb-target',
      orderIndex: 0,
    ),
    'nb-focus': AutofocusNode(
      id: 'nb-focus',
      method: AutofocusMethod.vCurve,
      parentId: 'nb-target',
      orderIndex: 1,
    ),
    'nb-loop': LoopNode(
      id: 'nb-loop',
      name: 'Repeat narrowband set',
      conditionType: LoopConditionType.count,
      repeatCount: 12,
      parentId: 'nb-target',
      orderIndex: 2,
      childIds: const ['nb-ha', 'nb-oiii', 'nb-sii'],
    ),
    'nb-ha': ExposureNode(
      id: 'nb-ha',
      name: 'Ha 180s x 12',
      durationSecs: 180,
      count: 12,
      filter: 'Ha',
      gain: 100,
      binning: BinningMode.one,
      ditherEvery: 3,
      parentId: 'nb-loop',
      orderIndex: 0,
    ),
    'nb-oiii': ExposureNode(
      id: 'nb-oiii',
      name: 'OIII 180s x 12',
      durationSecs: 180,
      count: 12,
      filter: 'OIII',
      gain: 100,
      binning: BinningMode.one,
      ditherEvery: 3,
      parentId: 'nb-loop',
      orderIndex: 1,
    ),
    'nb-sii': ExposureNode(
      id: 'nb-sii',
      name: 'SII 180s x 12',
      durationSecs: 180,
      count: 12,
      filter: 'SII',
      gain: 100,
      binning: BinningMode.one,
      ditherEvery: 3,
      parentId: 'nb-loop',
      orderIndex: 2,
    ),
    'nb-warm': WarmCameraNode(
      id: 'nb-warm',
      ratePerMin: 5,
      parentId: 'nb-target',
      orderIndex: 3,
    ),
  },
);

class _ScreenshotSequence extends CurrentSequenceNotifier {
  _ScreenshotSequence(Ref ref) : super(ref: ref) {
    loadSequence(_screenshotSequence, discardUnsaved: true);
    markSaved();
  }
}

class _ScreenshotProgress extends SequenceProgressNotifier {
  _ScreenshotProgress() {
    updateState(SequenceExecutionState.running);
    setTotals(36, 6480);
    updateProgress(
      currentNodeId: 'nb-ha',
      currentNodeName: 'Ha 180s x 12',
      currentNodeStatus: NodeStatus.running,
      completedExposures: 18,
      completedIntegrationSecs: 3240,
      elapsedSecs: 11940,
      estimatedRemainingSecs: 10680,
      currentTarget: 'NGC 7000 - North America Nebula',
      currentFilter: 'Ha',
      message: 'Capturing Ha frame 7 of 12',
    );
    updateNodeStatus('nb-cool', NodeStatus.success);
    updateNodeStatus('nb-focus', NodeStatus.success);
    updateNodeStatus('nb-loop', NodeStatus.running);
    updateNodeStatus('nb-ha', NodeStatus.running);
    updateNodeStatus('nb-oiii', NodeStatus.pending);
    updateNodeStatus('nb-sii', NodeStatus.pending);
    updateNodeProgress('nb-ha', 0.58, '7 / 12 frames');
  }
}

class _ScreenshotSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState(
        theme: 'dark',
        imageOutputPath: 'D:\\Astro\\Nightshade\\Captures',
        latitude: 34.744,
        longitude: -118.057,
        elevation: 780,
        timezone: 'America/Los_Angeles',
        safetyFailMode: SafetyFailMode.failOpen,
      );
}

class _ConnectedCamera extends CameraStateNotifier {
  _ConnectedCamera(super.ref) {
    setConnecting('asi2600mm', 'ZWO ASI2600MM Pro');
    setConnected();
    setCooling(true);
    setTargetTemp(-10);
    updateTemperature(-10.2, 41);
    setExposing(true, progress: 0.62);
  }
}

class _ConnectedMount extends MountStateNotifier {
  _ConnectedMount(super.ref) {
    setConnecting('eq6r', 'EQ6-R Pro');
    setConnected();
    updatePosition(20.981, 44.33, 68.4, 122.1);
    setTracking(true);
  }
}

class _ConnectedGuider extends GuiderStateNotifier {
  _ConnectedGuider(super.ref) {
    setConnecting('phd2', 'PHD2');
    setConnected();
    setGuiding(true);
    updateRms(0.31, 0.27, 0.42);
  }
}

class _ConnectedFocuser extends FocuserStateNotifier {
  _ConnectedFocuser(super.ref) {
    setConnecting('eaf', 'ZWO EAF');
    setConnected(maxPosition: 60000, stepSize: 1, isAbsolute: true);
    updatePosition(28420);
    updateTemperature(7.4);
  }
}

class _ConnectedFilterWheel extends FilterWheelStateNotifier {
  _ConnectedFilterWheel(super.ref) {
    setConnecting('efw', 'ZWO EFW 7x36');
    setConnected(filterNames: const ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII']);
    updatePosition(4);
  }
}

class _ActiveSession extends SessionStateNotifier {
  _ActiveSession(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = SessionState(
      isActive: true,
      startTime: DateTime(2026, 6, 18, 22, 14),
      targetName: 'NGC 7000 - North America Nebula',
      targetRa: 20.981,
      targetDec: 44.33,
      totalExposures: 72,
      completedExposures: 43,
      failedExposures: 1,
      rejectedExposures: 2,
      totalIntegrationSecs: 12900,
      currentFilter: 'Ha',
      isGuiding: true,
      isCapturing: true,
      avgHfr: 2.13,
      avgGuidingRmsRa: 0.31,
      avgGuidingRmsDec: 0.27,
      dbSessionId: 42,
    );
  }
}

class _SeededFlatWizard extends FlatWizardNotifier {
  _SeededFlatWizard(super.ref) {
    final now = DateTime(2026, 6, 18, 20, 40);
    // ignore: invalid_use_of_protected_member
    state = FlatWizardState(
      mode: FlatWizardMode.batch,
      globalSettings: const FlatWizardGlobalSettings(
        histogramTarget: 50,
        tolerancePercent: 8,
        minExposure: 0.01,
        maxExposure: 12,
        frameCount: 30,
        gain: 100,
        binning: 1,
        savePath: 'D:\\Astro\\Calibration\\Flats',
      ),
      filterSettings: const [
        FlatFilterSettings(
          filterName: 'L',
          filterPosition: 0,
          calibratedExposure: 0.72,
          capturedCount: 30,
          currentAdu: 32740,
          status: FilterCalibrationStatus.complete,
        ),
        FlatFilterSettings(
          filterName: 'R',
          filterPosition: 1,
          calibratedExposure: 1.14,
          capturedCount: 30,
          currentAdu: 32310,
          status: FilterCalibrationStatus.complete,
        ),
        FlatFilterSettings(
          filterName: 'Ha',
          filterPosition: 4,
          calibratedExposure: 3.8,
          capturedCount: 12,
          currentAdu: 33180,
          status: FilterCalibrationStatus.capturing,
        ),
      ],
      currentFilterIndex: 2,
      currentFrameIndex: 12,
      isCapturing: true,
      isExposing: true,
      exposureStartTime: now,
      currentExposureDuration: 3.8,
      aduHistory: [
        for (var i = 0; i < 12; i++)
          AduMeasurement(
            exposure: 2.8 + i * 0.08,
            adu: 29000 + i * 340,
            timestamp: now.add(Duration(seconds: i * 8)),
          ),
      ],
      skyBrightnessHistory: [
        for (var i = 0; i < 8; i++)
          SkyBrightnessMeasurement(
            adu: 24000 + i * 270,
            exposureUsed: 3.5,
            timestamp: now.add(Duration(minutes: i)),
          ),
      ],
      skyAduRate: 41.5,
      statusMessage: 'Capturing Ha flats: frame 12 of 30',
      showHistogramOverlay: true,
    );
  }
}

final _sharedOverrides = <Override>[
  appSettingsProvider.overrideWith(_ScreenshotSettings.new),
  activeEquipmentProfileProvider.overrideWithValue(_screenshotProfile),
  sortedProfilesProvider.overrideWithValue([_screenshotProfile]),
  equipmentProfileListProvider.overrideWithValue([_screenshotProfile]),
  selectedEquipmentProfileIdProvider
      .overrideWith((ref) => _screenshotProfile.id),
  smartNightExposureContextProvider.overrideWith((ref) async => null),
  currentSequenceProvider.overrideWith((ref) => _ScreenshotSequence(ref)),
  selectedNodeIdProvider.overrideWith((ref) => 'nb-ha'),
  sequenceExecutionStateProvider.overrideWith(
    (ref) => SequenceExecutionState.running,
  ),
  sequenceProgressProvider.overrideWith((ref) => _ScreenshotProgress()),
  schedulerPreviewDecisionProvider.overrideWith((ref) async {
    return _schedulerDecision;
  }),
  captureDirDiskSpaceProvider.overrideWith((ref) async* {
    yield DiskSpaceInfo(
      path: 'D:\\Astro\\Nightshade\\Captures',
      totalBytes: _gb(2000),
      freeBytes: _gb(640),
      sampledAt: DateTime(2026, 6, 18, 22, 30),
    );
  }),
  sequenceDiskProjectionProvider.overrideWith((ref) async {
    return SequenceDiskProjectionSnapshot(
      projection: DiskSpaceProjection(
        freeBytes: _gb(640),
        totalBytes: _gb(2000),
        projectedBytes: _gb(48),
        severity: DiskSpaceSeverity.info,
        headline: '640 GB free; tonight\'s run will use ~48 GB',
        detail: '592 GB will remain after the sequence completes.',
      ),
      capturePathConfigured: true,
    );
  }),
  cameraStateProvider.overrideWith((ref) => _ConnectedCamera(ref)),
  mountStateProvider.overrideWith((ref) => _ConnectedMount(ref)),
  guiderStateProvider.overrideWith((ref) => _ConnectedGuider(ref)),
  focuserStateProvider.overrideWith((ref) => _ConnectedFocuser(ref)),
  filterWheelStateProvider.overrideWith((ref) => _ConnectedFilterWheel(ref)),
  sessionStateProvider.overrideWith((ref) => _ActiveSession(ref)),
  flatWizardProvider.overrideWith((ref) => _SeededFlatWizard(ref)),
  weatherStatusProvider.overrideWithValue(
    WeatherStatus(
      currentLevel: AlertLevel.clear,
      radarFrames: [
        for (var i = 0; i < 6; i++)
          RadarFrame(
            timestamp: DateTime(2026, 6, 18, 22, i * 10),
            tileUrlTemplate: '',
            north: 35.5,
            south: 34.0,
            east: -117.0,
            west: -119.2,
            opacity: 0.25 + i * 0.08,
            intensityGrid: [
              for (var r = 0; r < 8; r++)
                [for (var c = 0; c < 10; c++) ((r + c + i) % 7) / 7],
            ],
          ),
      ],
      currentFrameIndex: 4,
      lastUpdate: DateTime(2026, 6, 18, 22, 45),
    ),
  ),
  weatherSettingsProvider.overrideWithValue(
    WeatherSettings.defaultSettings.copyWith(autoParkEnabled: false),
  ),
];

Future<void> _capture(
  WidgetTester tester, {
  required Widget screen,
  required String fileName,
  List<Override> overrides = const [],
}) async {
  await SurfaceGoldenHarness.ensureFonts();

  final boundaryKey = GlobalKey();
  final handle = await pumpAppScreen(
    tester,
    RepaintBoundary(
      key: boundaryKey,
      child: SizedBox.fromSize(size: _size, child: screen),
    ),
    size: _size,
    theme: NightshadeTheme.dark,
    settle: false,
    registerTearDown: false,
    extraOverrides: [..._sharedOverrides, ...overrides],
  );

  try {
    // Let async providers draw their real loaded states, but stay below the
    // contextual-tour prompt delay so screenshots are not covered by onboarding.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final out = File(
      '${SurfaceGoldenHarness.repoRoot().path}/assets/screenshots/$fileName',
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw StateError('PNG encode failed for $fileName');
        }
        out.writeAsBytesSync(bytes.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });

    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), greaterThan(16 * 1024));
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    handle.container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('refresh public screenshots from real app screens',
      (tester) async {
    await _capture(
      tester,
      screen: const DashboardScreen(),
      fileName: 'desktop-dashboard.png',
    );
    await _capture(
      tester,
      screen: const SequencerScreen(),
      fileName: 'sequencer.png',
    );
    await _capture(
      tester,
      screen: const ImagingScreen(),
      fileName: 'imaging.png',
    );
    await _capture(
      tester,
      screen: const EquipmentScreen(),
      fileName: 'equipment.png',
    );
    await _capture(
      tester,
      screen: const PlanetariumScreen(),
      fileName: 'planetarium.png',
    );
    await _capture(
      tester,
      screen: const PlannerScreen(),
      fileName: 'plan-tonight.png',
    );
    await _capture(
      tester,
      screen: const FramingScreen(),
      fileName: 'framing.png',
    );
    await _capture(
      tester,
      screen: const GuidingScreen(),
      fileName: 'guiding.png',
    );
    await _capture(
      tester,
      screen: const WeatherScreen(),
      fileName: 'weather.png',
    );
    await _capture(
      tester,
      screen: const AnalyticsScreen(initialTab: AnalyticsTab.science),
      fileName: 'analytics.png',
    );
    await _capture(
      tester,
      screen: const FlatWizardScreen(),
      fileName: 'flat-wizard.png',
    );
    await _capture(
      tester,
      screen: const SettingsScreen(initialSection: 'equipment-profiles'),
      fileName: 'settings-equipment-profiles.png',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
