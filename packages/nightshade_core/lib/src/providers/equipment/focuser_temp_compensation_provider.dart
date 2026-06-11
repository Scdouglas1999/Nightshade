import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/equipment/equipment_models.dart';
import '../../models/sequence/sequence_models.dart';
import '../../services/device_service.dart';
import '../../services/logging_service.dart';
import '../sequence/sequence_progress.dart';
import '../settings_provider.dart';
import 'focuser_state_provider.dart';

/// Why: many focusers drift with temperature — a 10 degC overnight change
/// is enough to push a typical refractor 100+ steps out of focus. Users
/// configure a coefficient (steps per degC) in
/// Equipment → Settings → Focuser; this provider applies that coefficient
/// continuously while the focuser is connected so the operator does not
/// have to refocus manually every few hours.
/// WIRE-UP item #7.
///
/// Sign convention (MUST match the executor-authoritative Rust
/// `execute_temperature_compensation` in
/// `native/nightshade_native/sequencer/src/temperature_compensation.rs`):
/// the Rust side computes
/// `new_position = current_position + (temp_now - baseline) * coefficient`.
/// This Dart provider uses the IDENTICAL formula
/// (`target = baseline_position + delta`). Historically this provider
/// subtracted the delta, which inverted the move direction relative to the
/// Rust instruction — the two compensators then fought each other (one
/// moving the focuser the wrong way). They now agree exactly: a given
/// coefficient produces the same physical move on both sides. With the
/// typical negative coefficient (default -12 steps/°C), a falling
/// temperature (negative delta) yields a positive step delta and drives the
/// focuser outward, which is the correct direction for most refractors as
/// the tube contracts.
///
/// Authority while a sequence runs: the Rust `temperature_compensation`
/// instruction is the in-sequence authority. To avoid double-compensation
/// (two controllers issuing focuser moves off the same temperature drift),
/// this continuous Dart provider stands down whenever the sequencer is
/// actively executing (running / paused / stopping / recovering) and only
/// drives compensation when no sequence is in flight.
///
/// State machine:
///   - When `tempCompensation` is false: no-op.
///   - When a sequence is executing: no-op (Rust instruction is authoritative).
///   - When `tempCompensation` is true and the focuser publishes its first
///     temperature reading: capture the (temperature, position) baseline.
///   - On each subsequent temperature reading, compute
///     `delta = (temp_now - baseline_temp) * coefficient`. When
///     `abs(delta) >= 1` step, move the focuser to
///     `baseline_position + delta`.
///   - After a successful move, advance the baseline to the new
///     (temperature, position) pair so future deltas are computed against
///     the most recent applied correction.
final focuserTempCompensationProvider = Provider<FocuserTempCompensator>((ref) {
  final compensator = FocuserTempCompensator(ref);
  ref.onDispose(compensator.dispose);
  return compensator;
});

/// Internal observable for tests: holds the most recent baseline so unit
/// tests can verify the controller advanced after a move.
final focuserTempCompensationBaselineProvider =
    StateProvider<FocuserTempCompensationBaseline?>((_) => null);

class FocuserTempCompensationBaseline {
  final double temperature;
  final int position;
  final DateTime capturedAt;

  const FocuserTempCompensationBaseline({
    required this.temperature,
    required this.position,
    required this.capturedAt,
  });
}

class FocuserTempCompensator {
  final Ref _ref;
  ProviderSubscription<FocuserState>? _focuserSub;
  ProviderSubscription<AsyncValue<AppSettingsState>>? _settingsSub;
  bool _moveInFlight = false;

  FocuserTempCompensator(this._ref) {
    _focuserSub = _ref.listen<FocuserState>(
      focuserStateProvider,
      _onFocuserChanged,
      fireImmediately: false,
    );
    _settingsSub = _ref.listen<AsyncValue<AppSettingsState>>(
      appSettingsProvider,
      _onSettingsChanged,
      fireImmediately: false,
    );
  }

  void dispose() {
    _focuserSub?.close();
    _settingsSub?.close();
  }

  void _onSettingsChanged(
    AsyncValue<AppSettingsState>? previous,
    AsyncValue<AppSettingsState> next,
  ) {
    // When the user disables compensation, drop the baseline so a re-enable
    // captures a fresh reference instead of acting on stale data.
    final settings = next.valueOrNull;
    if (settings == null || !settings.tempCompensation) {
      _ref.read(focuserTempCompensationBaselineProvider.notifier).state = null;
    }
  }

  /// Whether the sequencer is actively executing. While it is, the Rust
  /// `temperature_compensation` instruction owns focuser drift correction;
  /// this continuous provider must not also issue moves (double-compensation).
  bool get _sequenceActive {
    switch (_ref.read(sequenceExecutionStateProvider)) {
      case SequenceExecutionState.running:
      case SequenceExecutionState.paused:
      case SequenceExecutionState.stopping:
      case SequenceExecutionState.recovering:
        return true;
      case SequenceExecutionState.idle:
      case SequenceExecutionState.completed:
      case SequenceExecutionState.failed:
        return false;
    }
  }

  void _onFocuserChanged(FocuserState? previous, FocuserState next) {
    final settings = _ref.read(appSettingsProvider).valueOrNull;
    if (settings == null || !settings.tempCompensation) {
      return;
    }
    if (_sequenceActive) {
      // The Rust temperature_compensation instruction is authoritative while
      // a sequence runs. Skip Dart-side compensation to avoid two controllers
      // fighting over the focuser. We deliberately keep the baseline so that
      // when the sequence ends, the next temperature tick resumes from the
      // correct reference rather than re-capturing mid-drift.
      return;
    }
    if (next.connectionState != DeviceConnectionState.connected) {
      _ref.read(focuserTempCompensationBaselineProvider.notifier).state = null;
      return;
    }
    final temperature = next.temperature;
    final position = next.position;
    if (temperature == null || position == null) {
      return;
    }

    final baselineHolder = _ref.read(
      focuserTempCompensationBaselineProvider.notifier,
    );
    final baseline = baselineHolder.state;
    if (baseline == null) {
      baselineHolder.state = FocuserTempCompensationBaseline(
        temperature: temperature,
        position: position,
        capturedAt: DateTime.now(),
      );
      return;
    }

    final coefficient = settings.tempCoefficient;
    if (coefficient == 0) {
      // Why: a zero coefficient is a valid "track temperature but do not
      // act" state. The user gets the temperature display without any
      // movement.
      return;
    }

    final deltaTemp = temperature - baseline.temperature;
    final deltaStepsDouble = deltaTemp * coefficient;
    final deltaSteps = deltaStepsDouble.round();
    if (deltaSteps.abs() < 1) {
      return;
    }
    // Sign convention matches the Rust executor exactly:
    // `new = baseline + (temp_now - baseline_temp) * coefficient`. With the
    // default negative coefficient, a temperature drop yields a positive
    // delta and moves the focuser outward. Do NOT flip this sign — the Rust
    // `temperature_compensation` instruction adds the same delta, and any
    // disagreement makes the two compensators drive the focuser in opposite
    // directions.
    final targetPosition = baseline.position + deltaSteps;
    if (targetPosition < 0) {
      // Refuse impossible commands rather than silently clamping.
      _ref
          .read(loggingServiceProvider)
          .warning(
            'Temp compensation computed negative target position '
            '($targetPosition); skipping move.',
            source: 'FocuserTempCompensator',
          );
      return;
    }

    if (_moveInFlight) {
      // A previous move is still settling; we'll re-evaluate on the next
      // temperature tick.
      return;
    }

    unawaited(_applyMove(targetPosition, temperature));
  }

  Future<void> _applyMove(int targetPosition, double newBaselineTemp) async {
    _moveInFlight = true;
    final logger = _ref.read(loggingServiceProvider);
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      if (deviceService.isAutofocusRunning) {
        logger.info(
          'Temp compensation skipped while autofocus is running.',
          source: 'FocuserTempCompensator',
        );
        return;
      }
      await deviceService.moveFocuserTo(targetPosition);
      logger.info(
        'Temp compensation moved focuser to $targetPosition '
        '(new baseline temp ${newBaselineTemp.toStringAsFixed(2)}C)',
        source: 'FocuserTempCompensator',
      );
      _ref
          .read(focuserTempCompensationBaselineProvider.notifier)
          .state = FocuserTempCompensationBaseline(
        temperature: newBaselineTemp,
        position: targetPosition,
        capturedAt: DateTime.now(),
      );
    } catch (e, st) {
      // Fail loud — silent fallbacks here would hide a focuser issue from
      // the operator. Errors propagate via the logging service and the
      // baseline is left untouched so the next temperature update can
      // retry.
      logger.error(
        'Temp compensation move failed: $e',
        source: 'FocuserTempCompensator',
        fields: {'stack': st.toString()},
      );
    } finally {
      _moveInFlight = false;
    }
  }
}
