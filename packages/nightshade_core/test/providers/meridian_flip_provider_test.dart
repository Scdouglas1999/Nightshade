// Tests for audit-handoff §1.2: meridian flip subsystem wire-up.
//
// Covers:
//   1. Global -> per-node merge in the sequence executor's MeridianFlipConfig
//      builder (useGlobalDefaults true pulls from settings; copyWith of any
//      meridian field clears the flag for sticky overrides).
//   2. Standalone monitor lifecycle: toggling
//      `standaloneMonitoringEnabled` starts/stops the watcher and the
//      evaluator only fires when conditions are met.
//   3. Disconnect guard: mount disconnect during a flip transitions
//      `flipExecutionStateProvider` to `aborted` with the documented error.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/equipment/equipment_models.dart';
import 'package:nightshade_core/src/providers/equipment/mount_state_provider.dart';
import 'package:nightshade_core/src/providers/meridian_flip_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart'
    show sequenceExecutionStateProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeridianFlipNode useGlobalDefaults', () {
    test('copyWith of any meridian field clears useGlobalDefaults', () {
      final fresh = MeridianFlipNode();
      expect(fresh.useGlobalDefaults, isTrue);

      // Why: touching any meridian field is a sticky user override.
      final edited = fresh.copyWith(maxRetries: 7);
      expect(edited.maxRetries, 7);
      expect(edited.useGlobalDefaults, isFalse,
          reason:
              'copyWith on a meridian field must flip useGlobalDefaults to false');
    });

    test('structural copyWith (name/parent) preserves useGlobalDefaults', () {
      final fresh = MeridianFlipNode();
      final renamed = fresh.copyWith(name: 'My Flip', parentId: 'root');
      expect(renamed.useGlobalDefaults, isTrue,
          reason:
              'structural changes that do not alter flip behavior must not flip the flag');
    });

    test('explicit useGlobalDefaults: arg wins over auto-detect', () {
      final fresh = MeridianFlipNode();
      // Even though maxRetries is being touched, the explicit flag wins.
      final pinned =
          fresh.copyWith(maxRetries: 9, useGlobalDefaults: true);
      expect(pinned.useGlobalDefaults, isTrue);
    });
  });

  group('Sequence executor MeridianFlipConfig wiring', () {
    late NightshadeDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
        'updating globalMeridianFlipSettings.maxRetries flows into the effective settings used by the executor',
        () async {
      final notifier =
          container.read(globalMeridianFlipSettingsProvider.notifier);
      await notifier.setMaxRetries(5);

      final settings =
          container.read(effectiveMeridianFlipSettingsProvider);
      expect(settings.maxRetries, 5);

      // Why (audit-handoff §1.2): the executor's `_buildMeridianFlipConfig`
      // reads `effectiveMeridianFlipSettingsProvider` whenever a node has
      // `useGlobalDefaults: true`. Verifying the upstream propagation here
      // exercises the same provider chain without needing to spin up the
      // backend FFI surface.
      final freshNode = MeridianFlipNode();
      expect(freshNode.useGlobalDefaults, isTrue);

      // Per-node override path: when a user edits the node, the override
      // wins over the global setting.
      final overriddenNode = freshNode.copyWith(maxRetries: 1);
      expect(overriddenNode.useGlobalDefaults, isFalse);
      expect(overriddenNode.maxRetries, 1);
    });

    test('failure action and trigger method round-trip through the global notifier',
        () async {
      final notifier =
          container.read(globalMeridianFlipSettingsProvider.notifier);

      await notifier.setFailureAction(FlipFailureAction.abortAndPark);
      await notifier.setTriggerMethod(MeridianTriggerMethod.hourAngleThreshold);

      final settings =
          container.read(effectiveMeridianFlipSettingsProvider);
      expect(settings.failureAction, FlipFailureAction.abortAndPark);
      expect(
          settings.triggerMethod, MeridianTriggerMethod.hourAngleThreshold);
    });
  });

  group('MeridianFlipStandaloneMonitor', () {
    late NightshadeDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    ProviderContainer makeContainer({
      required MountState mount,
      double longitude = -75.0,
      double latitude = 40.0,
    }) {
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mountStateProvider.overrideWith((ref) {
            final n = MountStateNotifier(ref);
            n.state = mount;
            return n;
          }),
          // Why: override appSettings with a real location so the monitor
          // doesn't refuse to compute HA from a 0,0 default.
          appSettingsProvider.overrideWith(() {
            return _StubAppSettingsNotifier(
              AppSettingsState(
                latitude: latitude,
                longitude: longitude,
              ),
            );
          }),
        ],
      );
    }

    test(
        'inactive when standaloneMonitoringEnabled is false, even with trigger conditions met',
        () async {
      container = makeContainer(
        mount: const MountState(
          connectionState: DeviceConnectionState.connected,
          isTracking: true,
          isParked: false,
          ra: 0.0,
        ),
      );

      await container.read(appSettingsProvider.future);

      final monitor =
          container.read(meridianFlipStandaloneMonitorProvider.notifier);
      final decision = monitor.evaluateOnce();
      expect(decision, MeridianMonitorDecision.inactive);
    });

    test(
        'returns sequenceRunning when execution state is running and toggle is on',
        () async {
      container = makeContainer(
        mount: const MountState(
          connectionState: DeviceConnectionState.connected,
          isTracking: true,
          isParked: false,
          ra: 6.0,
        ),
      );
      await container.read(appSettingsProvider.future);
      await container
          .read(globalMeridianFlipSettingsProvider.notifier)
          .setStandaloneMonitoringEnabled(true);
      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;

      final monitor =
          container.read(meridianFlipStandaloneMonitorProvider.notifier);
      expect(
          monitor.evaluateOnce(), MeridianMonitorDecision.sequenceRunning);
    });

    test(
        'inactive when mount is disconnected even with monitoring enabled',
        () async {
      container = makeContainer(
        mount: const MountState(
          connectionState: DeviceConnectionState.disconnected,
        ),
      );
      await container.read(appSettingsProvider.future);
      await container
          .read(globalMeridianFlipSettingsProvider.notifier)
          .setStandaloneMonitoringEnabled(true);

      final monitor =
          container.read(meridianFlipStandaloneMonitorProvider.notifier);
      expect(monitor.evaluateOnce(), MeridianMonitorDecision.inactive);
    });

    test(
        'fires when mount HA crosses threshold and emits alert state',
        () async {
      // Why: pick an RA such that with a known longitude+time HA is past
      // the threshold. Easier: choose RA = LST - desired_HA. Compute LST
      // explicitly so the test is deterministic.
      final now = DateTime.now().toUtc();
      final lst = computeLocalSiderealTimeHours(now, -75.0);
      // Target an HA of +0.5 hours (past meridian) — well above the default
      // 5 min (0.083 h) trigger.
      final ra = (lst - 0.5) % 24.0;

      container = makeContainer(
        mount: MountState(
          connectionState: DeviceConnectionState.connected,
          isTracking: true,
          isParked: false,
          ra: ra,
          sideOfPier: 'west',
        ),
      );
      await container.read(appSettingsProvider.future);
      await container
          .read(globalMeridianFlipSettingsProvider.notifier)
          .setStandaloneMonitoringEnabled(true);

      // Defaults: trigger = minutesPastMeridian, threshold = 5 min.
      final monitor =
          container.read(meridianFlipStandaloneMonitorProvider.notifier);
      final decision = monitor.evaluateOnce();
      expect(decision, MeridianMonitorDecision.triggered);

      // Why: the alert path must update the UI's flip-execution state so
      // the operator sees something happened.
      final flipState = container.read(flipExecutionStateProvider);
      expect(flipState, FlipExecutionState.executing);

      // A second evaluation immediately after should respect the cooldown.
      final second = monitor.evaluateOnce();
      expect(second, MeridianMonitorDecision.cooldown);
    });
  });

  group('MeridianFlipDisconnectGuard', () {
    late NightshadeDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
        'transitions executing -> aborted on mount disconnect with documented error',
        () async {
      // Why: the guard's listen only fires on a *change* in mount state. The
      // initial default MountState is already disconnected, so we must first
      // transition the notifier to connected so the subsequent disconnect
      // delta produces a notification.
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.state = const MountState(
        connectionState: DeviceConnectionState.connected,
        deviceId: 'mount-1',
      );

      // Activate the guard.
      container.read(meridianFlipDisconnectGuardProvider);

      // Simulate an in-flight flip by setting state to executing.
      container.read(flipExecutionStateProvider.notifier).state =
          FlipExecutionState.executing;
      container.read(flipCurrentStepProvider.notifier).state =
          FlipStep.slewingToTarget;
      container.read(flipProgressProvider.notifier).state = 42;
      container.read(flipCurrentAttemptProvider.notifier).state = 1;

      // Now disconnect; the listener should see the connected->disconnected
      // delta and run the abort path.
      mountNotifier.state = const MountState(
        connectionState: DeviceConnectionState.disconnected,
      );

      // Allow the ref.listen tick to flush.
      await Future<void>.delayed(Duration.zero);

      expect(container.read(flipExecutionStateProvider),
          FlipExecutionState.aborted);
      expect(container.read(flipCurrentStepProvider), isNull);
      expect(container.read(flipProgressProvider), 0);
      expect(container.read(flipCurrentAttemptProvider), 0);
      expect(container.read(flipLastErrorProvider),
          'Meridian flip aborted: mount disconnected');
    });
  });
}

/// Why: appSettingsProvider is an AsyncNotifierProvider so the test needs a
/// stub that returns a synchronous state. Using the public `overrideWith`
/// requires an AsyncNotifier subclass.
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._seed);

  final AppSettingsState _seed;

  @override
  Future<AppSettingsState> build() async => _seed;
}
