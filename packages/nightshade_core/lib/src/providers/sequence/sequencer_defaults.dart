import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sequence/sequence_models.dart' show BinningMode;
import '../database_provider.dart';

/// Provider for sequencer default settings (persisted via settings DAO)
final sequencerDefaultsProvider =
    StateNotifierProvider<SequencerDefaultsNotifier, SequencerDefaults>((ref) {
  return SequencerDefaultsNotifier(ref);
});

class SequencerDefaults {
  // Autofocus defaults
  final int autofocusStepSize;
  final int autofocusStepsOut;
  final double autofocusExposureDuration;

  /// Wave 1.5 Pack A: cadence (frames between autofocus runs) for the
  /// standard `AutofocusInterval` trigger seeded into every executor. The
  /// Rust default in `nightshade_sequencer::default_autofocus_interval_frames()`
  /// is 25, which is wildly wrong for both very-short (5 s) and very-long
  /// (5 min) subs. Exposed in Sequencer Settings so the user can match the
  /// cadence to their actual sub-exposure length.
  final int autofocusIntervalFrames;

  // Dither defaults
  final double ditherPixels;
  final double ditherSettleTime;
  final double ditherSettlePixels;
  final double ditherSettleTimeout;
  final bool ditherRaOnly;

  // Exposure defaults
  final double exposureDuration;
  final int exposureCount;
  final String? exposureFilter;
  final int? exposureGain;
  final int? exposureOffset;
  final BinningMode exposureBinning;
  final int exposureDitherEvery;

  const SequencerDefaults({
    this.autofocusStepSize = 100,
    this.autofocusStepsOut = 7,
    this.autofocusExposureDuration = 3.0,
    this.autofocusIntervalFrames = 25,
    this.ditherPixels = 5.0,
    this.ditherSettleTime = 30.0,
    this.ditherSettlePixels = 1.5,
    this.ditherSettleTimeout = 120.0,
    this.ditherRaOnly = false,
    this.exposureDuration = 60.0,
    this.exposureCount = 10,
    this.exposureFilter,
    this.exposureGain,
    this.exposureOffset,
    this.exposureBinning = BinningMode.one,
    this.exposureDitherEvery = 1,
  });

  SequencerDefaults copyWith({
    int? autofocusStepSize,
    int? autofocusStepsOut,
    double? autofocusExposureDuration,
    int? autofocusIntervalFrames,
    double? ditherPixels,
    double? ditherSettleTime,
    double? ditherSettlePixels,
    double? ditherSettleTimeout,
    bool? ditherRaOnly,
    double? exposureDuration,
    int? exposureCount,
    String? exposureFilter,
    int? exposureGain,
    int? exposureOffset,
    BinningMode? exposureBinning,
    int? exposureDitherEvery,
  }) {
    return SequencerDefaults(
      autofocusStepSize: autofocusStepSize ?? this.autofocusStepSize,
      autofocusStepsOut: autofocusStepsOut ?? this.autofocusStepsOut,
      autofocusExposureDuration:
          autofocusExposureDuration ?? this.autofocusExposureDuration,
      autofocusIntervalFrames:
          autofocusIntervalFrames ?? this.autofocusIntervalFrames,
      ditherPixels: ditherPixels ?? this.ditherPixels,
      ditherSettleTime: ditherSettleTime ?? this.ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels ?? this.ditherSettlePixels,
      ditherSettleTimeout: ditherSettleTimeout ?? this.ditherSettleTimeout,
      ditherRaOnly: ditherRaOnly ?? this.ditherRaOnly,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      exposureCount: exposureCount ?? this.exposureCount,
      exposureFilter: exposureFilter ?? this.exposureFilter,
      exposureGain: exposureGain ?? this.exposureGain,
      exposureOffset: exposureOffset ?? this.exposureOffset,
      exposureBinning: exposureBinning ?? this.exposureBinning,
      exposureDitherEvery: exposureDitherEvery ?? this.exposureDitherEvery,
    );
  }
}

class SequencerDefaultsNotifier extends StateNotifier<SequencerDefaults> {
  final Ref _ref;

  SequencerDefaultsNotifier(this._ref) : super(const SequencerDefaults()) {
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final settingsDao = _ref.read(settingsDaoProvider);

    final stepSize = int.tryParse(
            await settingsDao.getSetting('sequencer_autofocus_step_size') ??
                '100') ??
        100;
    final stepsOut = int.tryParse(
            await settingsDao.getSetting('sequencer_autofocus_steps_out') ??
                '7') ??
        7;
    final exposureDuration = double.tryParse(await settingsDao
                .getSetting('sequencer_autofocus_exposure_duration') ??
            '3.0') ??
        3.0;
    // Wave 1.5 Pack A: persisted autofocus-interval cadence.
    final autofocusIntervalFrames = int.tryParse(await settingsDao
                .getSetting('sequencer_autofocus_interval_frames') ??
            '25') ??
        25;

    final ditherPixels = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_pixels') ?? '5.0') ??
        5.0;
    final ditherSettleTime = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_time') ??
                '30.0') ??
        30.0;
    final ditherSettlePixels = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_pixels') ??
                '1.5') ??
        1.5;
    final ditherSettleTimeout = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_timeout') ??
                '120.0') ??
        120.0;
    final ditherRaOnly =
        (await settingsDao.getSetting('sequencer_dither_ra_only') ?? 'false') ==
            'true';

    final exposureDurationDefault = double.tryParse(
            await settingsDao.getSetting('sequencer_exposure_duration') ??
                '60.0') ??
        60.0;
    final exposureCount = int.tryParse(
            await settingsDao.getSetting('sequencer_exposure_count') ?? '10') ??
        10;
    final exposureFilter =
        await settingsDao.getSetting('sequencer_exposure_filter');
    final exposureGainStr =
        await settingsDao.getSetting('sequencer_exposure_gain');
    final exposureGain =
        exposureGainStr != null ? int.tryParse(exposureGainStr) : null;
    final exposureOffsetStr =
        await settingsDao.getSetting('sequencer_exposure_offset');
    final exposureOffset =
        exposureOffsetStr != null ? int.tryParse(exposureOffsetStr) : null;
    final exposureBinningStr =
        await settingsDao.getSetting('sequencer_exposure_binning') ?? 'one';
    final exposureBinning = BinningMode.values.firstWhere(
      (e) => e.name == exposureBinningStr,
      orElse: () => BinningMode.one,
    );
    final exposureDitherEvery = int.tryParse(
            await settingsDao.getSetting('sequencer_exposure_dither_every') ??
                '1') ??
        1;

    state = SequencerDefaults(
      autofocusStepSize: stepSize,
      autofocusStepsOut: stepsOut,
      autofocusExposureDuration: exposureDuration,
      autofocusIntervalFrames: autofocusIntervalFrames,
      ditherPixels: ditherPixels,
      ditherSettleTime: ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels,
      ditherSettleTimeout: ditherSettleTimeout,
      ditherRaOnly: ditherRaOnly,
      exposureDuration: exposureDurationDefault,
      exposureCount: exposureCount,
      exposureFilter: exposureFilter,
      exposureGain: exposureGain,
      exposureOffset: exposureOffset,
      exposureBinning: exposureBinning,
      exposureDitherEvery: exposureDitherEvery,
    );
  }

  Future<void> updateAutofocusDefaults({
    int? stepSize,
    int? stepsOut,
    double? exposureDuration,
    int? intervalFrames,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};

    if (stepSize != null) {
      updates['sequencer_autofocus_step_size'] = stepSize.toString();
      state = state.copyWith(autofocusStepSize: stepSize);
    }
    if (stepsOut != null) {
      updates['sequencer_autofocus_steps_out'] = stepsOut.toString();
      state = state.copyWith(autofocusStepsOut: stepsOut);
    }
    if (exposureDuration != null) {
      updates['sequencer_autofocus_exposure_duration'] =
          exposureDuration.toString();
      state = state.copyWith(autofocusExposureDuration: exposureDuration);
    }
    if (intervalFrames != null) {
      // Wave 1.5 Pack A: persist and push to the live executor so the
      // autofocus-interval trigger cadence updates without a sequence reload.
      // Validation: Rust rejects 0; clamp here as well so the UI doesn't
      // round-trip a value that the backend will refuse.
      final clamped = intervalFrames < 1 ? 1 : intervalFrames;
      updates['sequencer_autofocus_interval_frames'] = clamped.toString();
      state = state.copyWith(autofocusIntervalFrames: clamped);
    }

    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }

  Future<void> updateDitherDefaults({
    double? pixels,
    double? settleTime,
    double? settlePixels,
    double? settleTimeout,
    bool? raOnly,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};

    if (pixels != null) {
      updates['sequencer_dither_pixels'] = pixels.toString();
      state = state.copyWith(ditherPixels: pixels);
    }
    if (settleTime != null) {
      updates['sequencer_dither_settle_time'] = settleTime.toString();
      state = state.copyWith(ditherSettleTime: settleTime);
    }
    if (settlePixels != null) {
      updates['sequencer_dither_settle_pixels'] = settlePixels.toString();
      state = state.copyWith(ditherSettlePixels: settlePixels);
    }
    if (settleTimeout != null) {
      updates['sequencer_dither_settle_timeout'] = settleTimeout.toString();
      state = state.copyWith(ditherSettleTimeout: settleTimeout);
    }
    if (raOnly != null) {
      updates['sequencer_dither_ra_only'] = raOnly.toString();
      state = state.copyWith(ditherRaOnly: raOnly);
    }

    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }

  Future<void> updateExposureDefaults({
    double? duration,
    int? count,
    String? filter,
    int? gain,
    int? offset,
    BinningMode? binning,
    int? ditherEvery,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};

    if (duration != null) {
      updates['sequencer_exposure_duration'] = duration.toString();
      state = state.copyWith(exposureDuration: duration);
    }
    if (count != null) {
      updates['sequencer_exposure_count'] = count.toString();
      state = state.copyWith(exposureCount: count);
    }
    if (filter != null) {
      updates['sequencer_exposure_filter'] = filter;
      state = state.copyWith(exposureFilter: filter);
    }
    if (gain != null) {
      updates['sequencer_exposure_gain'] = gain.toString();
      state = state.copyWith(exposureGain: gain);
    }
    if (offset != null) {
      updates['sequencer_exposure_offset'] = offset.toString();
      state = state.copyWith(exposureOffset: offset);
    }
    if (binning != null) {
      updates['sequencer_exposure_binning'] = binning.name;
      state = state.copyWith(exposureBinning: binning);
    }
    if (ditherEvery != null) {
      updates['sequencer_exposure_dither_every'] = ditherEvery.toString();
      state = state.copyWith(exposureDitherEvery: ditherEvery);
    }

    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }
}
