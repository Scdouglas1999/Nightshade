/// Dual-rig / multi-camera synchronized imaging — Riverpod wiring.
///
/// Surfaces the secondary (piggyback) capture rig to the UI:
///   * [secondaryRigConfigProvider] holds the user's editable config (camera
///     selection, exposure, dither-coordination policy);
///   * [secondaryRigControllerProvider] arms / stops the rig via the FRB
///     bindings;
///   * [secondaryRigStatusProvider] polls live status (frame counts, whether
///     the secondary is parked for a primary dither) for the status card +
///     headless monitoring.
///
/// v1 scope: same mount (piggyback), secondary has no own guiding/dither,
/// plate-solving, or autofocus. See the Rust `dual_rig` module for the full
/// non-goals list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;

/// In-flight-exposure policy when the primary announces a dither.
enum SecondaryDitherPolicy {
  /// Let a short in-flight sub finish (if within max-wait), else abort it.
  completeIfShort,

  /// Always abort the in-flight secondary sub immediately.
  abortImmediately;

  String get wire => switch (this) {
    SecondaryDitherPolicy.completeIfShort => 'complete_if_short',
    SecondaryDitherPolicy.abortImmediately => 'abort_immediately',
  };

  String get label => switch (this) {
    SecondaryDitherPolicy.completeIfShort => 'Finish short subs',
    SecondaryDitherPolicy.abortImmediately => 'Abort immediately',
  };
}

/// User-editable secondary-rig configuration. Immutable; mutate via copyWith on
/// the [SecondaryRigConfigNotifier].
class SecondaryRigConfig {
  final String? cameraId;
  final double exposureSecs;
  final int? gain;
  final int? offset;
  final int binX;
  final int binY;

  /// null => run until the primary sequence ends.
  final int? frameCount;
  final String? filterName;
  final double? targetTempC;
  final String rigLabel;
  final double ditherMaxWaitSecs;
  final SecondaryDitherPolicy ditherPolicy;

  const SecondaryRigConfig({
    this.cameraId,
    this.exposureSecs = 60.0,
    this.gain,
    this.offset,
    this.binX = 1,
    this.binY = 1,
    this.frameCount,
    this.filterName,
    this.targetTempC,
    this.rigLabel = 'Secondary',
    this.ditherMaxWaitSecs = 30.0,
    this.ditherPolicy = SecondaryDitherPolicy.completeIfShort,
  });

  bool get isValid =>
      cameraId != null && cameraId!.trim().isNotEmpty && exposureSecs > 0;

  SecondaryRigConfig copyWith({
    String? cameraId,
    double? exposureSecs,
    int? gain,
    int? offset,
    int? binX,
    int? binY,
    int? frameCount,
    bool clearFrameCount = false,
    String? filterName,
    double? targetTempC,
    String? rigLabel,
    double? ditherMaxWaitSecs,
    SecondaryDitherPolicy? ditherPolicy,
  }) {
    return SecondaryRigConfig(
      cameraId: cameraId ?? this.cameraId,
      exposureSecs: exposureSecs ?? this.exposureSecs,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      binX: binX ?? this.binX,
      binY: binY ?? this.binY,
      frameCount: clearFrameCount ? null : (frameCount ?? this.frameCount),
      filterName: filterName ?? this.filterName,
      targetTempC: targetTempC ?? this.targetTempC,
      rigLabel: rigLabel ?? this.rigLabel,
      ditherMaxWaitSecs: ditherMaxWaitSecs ?? this.ditherMaxWaitSecs,
      ditherPolicy: ditherPolicy ?? this.ditherPolicy,
    );
  }
}

/// Holds the editable secondary-rig config.
class SecondaryRigConfigNotifier extends StateNotifier<SecondaryRigConfig> {
  SecondaryRigConfigNotifier() : super(const SecondaryRigConfig());

  void setCamera(String? cameraId) =>
      state = state.copyWith(cameraId: cameraId);
  void setExposure(double secs) => state = state.copyWith(exposureSecs: secs);
  void setGain(int? gain) => state = state.copyWith(gain: gain);
  void setBinning(int x, int y) => state = state.copyWith(binX: x, binY: y);
  void setFrameCount(int? count) => count == null
      ? state = state.copyWith(clearFrameCount: true)
      : state = state.copyWith(frameCount: count);
  void setFilterName(String? name) => state = state.copyWith(filterName: name);
  void setTargetTemp(double? t) => state = state.copyWith(targetTempC: t);
  void setRigLabel(String label) => state = state.copyWith(rigLabel: label);
  void setDitherMaxWait(double secs) =>
      state = state.copyWith(ditherMaxWaitSecs: secs);
  void setDitherPolicy(SecondaryDitherPolicy p) =>
      state = state.copyWith(ditherPolicy: p);
}

final secondaryRigConfigProvider =
    StateNotifierProvider<SecondaryRigConfigNotifier, SecondaryRigConfig>(
      (ref) => SecondaryRigConfigNotifier(),
    );

/// Metadata the primary supplies so secondary frames inherit target identity +
/// save location. Provide the active target name + save base when arming so the
/// secondary's subs are co-located with the primary's.
class SecondaryRigStartContext {
  final String? saveBasePath;
  final String? targetName;
  final double? targetRaHours;
  final double? targetDecDegrees;
  final String? observerName;
  final double? siteLatitudeDeg;
  final double? siteLongitudeDeg;
  final double? siteElevationM;

  const SecondaryRigStartContext({
    this.saveBasePath,
    this.targetName,
    this.targetRaHours,
    this.targetDecDegrees,
    this.observerName,
    this.siteLatitudeDeg,
    this.siteLongitudeDeg,
    this.siteElevationM,
  });
}

/// Controller that arms / stops the secondary rig through the FRB bindings.
class SecondaryRigController {
  const SecondaryRigController(this._ref);
  final Ref _ref;

  /// Arm + start the secondary capture loop. Arm BEFORE starting the primary
  /// sequence so the dither barrier is installed when the executor starts.
  Future<void> start(SecondaryRigStartContext context) async {
    final config = _ref.read(secondaryRigConfigProvider);
    if (!config.isValid) {
      throw StateError(
        'Secondary rig needs a camera and a positive exposure before starting.',
      );
    }
    await bridge_api.apiSecondaryRigStart(
      config: bridge_api.SecondaryRigConfigApi(
        cameraId: config.cameraId!,
        exposureSecs: config.exposureSecs,
        gain: config.gain,
        offset: config.offset,
        binX: config.binX,
        binY: config.binY,
        frameCount: config.frameCount,
        filterName: config.filterName,
        targetTempC: config.targetTempC,
        rigLabel: config.rigLabel,
        ditherMaxWaitSecs: config.ditherMaxWaitSecs,
        inFlightPolicy: config.ditherPolicy.wire,
        saveBasePath: context.saveBasePath,
        targetName: context.targetName,
        targetRaHours: context.targetRaHours,
        targetDecDegrees: context.targetDecDegrees,
        observerName: context.observerName,
        siteLatitudeDeg: context.siteLatitudeDeg,
        siteLongitudeDeg: context.siteLongitudeDeg,
        siteElevationM: context.siteElevationM,
      ),
    );
  }

  Future<void> stop() => bridge_api.apiSecondaryRigStop();

  Future<bool> isArmed() => bridge_api.apiSecondaryRigIsArmed();
}

final secondaryRigControllerProvider = Provider<SecondaryRigController>(
  (ref) => SecondaryRigController(ref),
);

/// Polls live secondary-rig status. Returns null when the rig is not armed.
/// Polls every 2s while watched; UI rebuilds on each tick.
final secondaryRigStatusProvider =
    StreamProvider.autoDispose<bridge_api.SecondaryRigStatusApi?>((ref) async* {
      while (true) {
        bridge_api.SecondaryRigStatusApi status;
        try {
          status = await bridge_api.apiSecondaryRigGetStatus();
        } catch (_) {
          yield null;
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        yield status.armed ? status : null;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    });
