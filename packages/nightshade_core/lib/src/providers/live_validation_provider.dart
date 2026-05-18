import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'equipment_provider.dart';
// sequence_provider.dart re-exports sequence/sequence_validation.dart, so the
// unified ValidationResult / ValidationIssue types are reachable through that
// single import. Don't add a direct import of sequence_validation.dart — the
// analyzer flags it as `unnecessary_import` and we want one canonical path.
import 'sequence_provider.dart';
import 'settings_provider.dart';

// =============================================================================
// LIVE VALIDATION PROVIDER
// =============================================================================
//
// Watches the current sequence + equipment state and runs the synchronous
// portion of the unified validation engine ([SequenceValidatorService.validateSync])
// on a 500ms debounce.
//
// We deliberately do NOT run the async disk-space check here — it would
// fire on every keystroke. The pre-flight dialog runs the full async stack
// via [SequenceValidatorService.validate].
//
// The state exposed below ([LiveValidationState]) wraps a [ValidationResult]
// and adds a debounce-aware `isValidating` flag for UI spinners.

/// Aggregated live validation state for tree-border colouring and the
/// header counts.
class LiveValidationState {
  final ValidationResult result;
  final bool isValidating;

  const LiveValidationState({
    required this.result,
    this.isValidating = false,
  });

  factory LiveValidationState.empty() => LiveValidationState(
        result: ValidationResult.empty(),
      );

  List<ValidationIssue> get issues => result.issues;
  Map<String, List<ValidationIssue>> get issuesByNodeId =>
      result.issuesByNodeId;
  int get errorCount => result.errorCount;
  int get warningCount => result.warningCount;
  int get infoCount => result.infoCount;
  int get totalCount => result.totalCount;
  bool get hasErrors => result.hasErrors;
  bool get hasWarnings => result.hasWarnings;

  /// Worst severity (error > warning > info) for a specific node.
  ValidationSeverity? worstSeverityForNode(String nodeId) =>
      result.worstSeverityForNode(nodeId);
}

/// Provider that runs live validation on the current sequence, debounced 500ms.
///
/// Watches:
/// - currentSequenceProvider (sequence structure changes)
/// - filterWheelStateProvider (connected filters)
/// - guiderStateProvider (guider connection)
/// - rotatorStateProvider (rotator connection)
/// - mountStateProvider (mount connection)
/// - cameraStateProvider (camera connection)
/// - focuserStateProvider (focuser connection)
final liveValidationProvider =
    StateNotifierProvider<LiveValidationNotifier, LiveValidationState>((ref) {
  return LiveValidationNotifier(ref);
});

class LiveValidationNotifier extends StateNotifier<LiveValidationState> {
  final Ref _ref;
  Timer? _debounceTimer;

  LiveValidationNotifier(this._ref) : super(LiveValidationState.empty()) {
    // Watch sequence changes
    _ref.listen(currentSequenceProvider, (_, __) {
      _scheduleValidation();
    });

    // Watch equipment state changes that affect validation
    _ref.listen(filterWheelStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(guiderStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(rotatorStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(mountStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(cameraStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(focuserStateProvider, (_, __) {
      _scheduleValidation();
    });

    // Settings changes (image output path, etc.) influence validation too.
    _ref.listen(appSettingsProvider, (_, __) {
      _scheduleValidation();
    });

    // Run initial validation
    _scheduleValidation();
  }

  void _scheduleValidation() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _runValidation();
      }
    });
  }

  void _runValidation() {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) {
      if (mounted) {
        state = LiveValidationState.empty();
      }
      return;
    }

    if (mounted) {
      state = LiveValidationState(
        result: state.result,
        isValidating: true,
      );
    }

    // We don't grab the provider here because the notifier is itself a
    // long-lived StateNotifier and the provider is autoDispose. Build the
    // service inline using the same default rule sets — the autoDispose
    // version exists so screen-scoped consumers can construct one without
    // dragging in the world.
    final service = SequenceValidatorService(
      ref: _ref,
      syncRules: defaultSequenceValidators,
      refAwareRules: defaultRefAwareSequenceValidators,
      asyncRules: const [],
    );
    final result = service.validateSync(sequence);

    if (mounted) {
      state = LiveValidationState(result: result);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
