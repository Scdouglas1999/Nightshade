part of '../device_service.dart';

extension _DeviceServiceAutofocusControls on DeviceService {
  /// Run autofocus routine
  ///
  /// When [useSettingsDefaults] is true (the default), the persisted autofocus
  /// settings from [appSettingsProvider] are used. The explicit parameters serve
  /// as overrides only when [useSettingsDefaults] is false.
  ///
  /// If `afDisableGuidingDuringAf` is enabled in settings, guiding is
  /// paused before the AF run and resumed afterwards.
  Future<AutofocusResult> _runAutofocus({
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    bool useSettingsDefaults = true,
  }) async {
    if (_isAutofocusRunning) {
      throw Exception(
          'Autofocus is already running. Wait for it to complete before starting another.');
    }
    _isAutofocusRunning = true;

    final focuserDeviceId = await _getFocuserDeviceId();
    if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    // Use the connected camera's device ID
    final cameraDeviceId = await _getCameraDeviceId();
    if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
      throw Exception('No camera connected');
    }

    // Resolve effective AF parameters from settings or explicit values
    final appSettings = _ref.read(appSettingsProvider).valueOrNull;

    final double effectiveExposureTime;
    final int effectiveStepSize;
    final int effectiveStepsOut;
    final String effectiveMethod;
    final int effectiveBinning;
    final String effectiveCurveFitting;
    final int effectiveNumberOfAttempts;
    final int effectiveExposuresPerPoint;
    final double effectiveRSquaredThreshold;
    final double effectiveOuterCropRatio;
    final double effectiveInnerCropRatio;
    final int effectiveUseBrightestNStars;
    final int effectiveFocuserSettleTimeMs;
    final String effectiveBacklashCompMethod;
    final int effectiveBacklashIn;
    final int effectiveBacklashOut;
    final bool disableGuidingDuringAf;

    if (useSettingsDefaults && appSettings == null) {
      // Settings not yet loaded from DB — don't silently fall back to hardcoded
      // defaults because the user's persisted configuration would be ignored.
      throw Exception(
          'Cannot run autofocus with settings defaults: AppSettings not yet loaded. '
          'Wait for the app to finish initializing before running autofocus.');
    }

    if (useSettingsDefaults && appSettings != null) {
      effectiveExposureTime = appSettings.afExposureTime;
      effectiveStepSize = appSettings.afStepSize;
      effectiveStepsOut = appSettings.afInitialOffsetSteps;
      effectiveMethod = appSettings.afMethod;
      effectiveBinning = appSettings.afBinning;
      effectiveCurveFitting = appSettings.afCurveFitting;
      effectiveNumberOfAttempts = appSettings.afNumberOfAttempts;
      effectiveExposuresPerPoint = appSettings.afExposuresPerPoint;
      effectiveRSquaredThreshold = appSettings.afRSquaredThreshold;
      effectiveOuterCropRatio = appSettings.afOuterCropRatio;
      effectiveInnerCropRatio = appSettings.afInnerCropRatio;
      effectiveUseBrightestNStars = appSettings.afUseBrightestNStars;
      effectiveFocuserSettleTimeMs = appSettings.afFocuserSettleTimeMs;
      effectiveBacklashCompMethod = appSettings.afBacklashCompMethod;
      effectiveBacklashIn = appSettings.afBacklashIn;
      effectiveBacklashOut = appSettings.afBacklashOut;
      disableGuidingDuringAf = appSettings.afDisableGuidingDuringAf;
    } else {
      effectiveExposureTime = exposureTime;
      effectiveStepSize = stepSize;
      effectiveStepsOut = stepsOut;
      effectiveMethod = method;
      effectiveBinning = binning;
      effectiveCurveFitting = 'Hyperbolic';
      effectiveNumberOfAttempts = 1;
      effectiveExposuresPerPoint = 1;
      effectiveRSquaredThreshold = 0.7;
      effectiveOuterCropRatio = 1.0;
      effectiveInnerCropRatio = 0.0;
      effectiveUseBrightestNStars = 0;
      effectiveFocuserSettleTimeMs = 500;
      effectiveBacklashCompMethod = 'Overshoot';
      effectiveBacklashIn = 350;
      effectiveBacklashOut = 0;
      disableGuidingDuringAf = false;
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.autofocus,
      description: 'Running autofocus ($effectiveMethod)',
      currentStep: 'Initializing...',
      canCancel: true,
    );

    // Predictive-AF consultation (Wave 8 wire-up). Before running the real
    // sweep, ask the persisted per-filter model what it would predict for the
    // current temperature/filter. We log the decision and capture the
    // predicted position so that — once the sweep converges — we can feed the
    // model the prediction-vs-actual error for drift tracking. We never let
    // the prediction REPLACE the Dart sweep here: this path is the explicit
    // full-sweep request (manual focus tab / Dart-driven AF), so the user
    // asked for a real measurement. The prediction is advisory + training
    // input only.
    final predictiveContext = await _consultPredictiveAf(
      method: effectiveMethod,
    );

    // Pause guiding if configured and guiding is active
    final guiderState = _ref.read(guiderStateProvider);
    final wasGuiding = disableGuidingDuringAf && guiderState.isGuiding;
    if (wasGuiding) {
      try {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.info(
          'Pausing guiding for autofocus run',
          source: 'DeviceService',
        );
        await stopGuiding();
      } catch (e) {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.warning(
          'Failed to pause guiding before autofocus: $e',
          source: 'DeviceService',
        );
      }
    }

    try {
      final result = await _backend.autofocusStart(
        deviceId: focuserDeviceId,
        cameraId: cameraDeviceId,
        exposureTime: effectiveExposureTime,
        stepSize: effectiveStepSize,
        stepsOut: effectiveStepsOut,
        method: effectiveMethod,
        binning: effectiveBinning,
        curveFitting: effectiveCurveFitting,
        numberOfAttempts: effectiveNumberOfAttempts,
        exposuresPerPoint: effectiveExposuresPerPoint,
        rSquaredThreshold: effectiveRSquaredThreshold,
        outerCropRatio: effectiveOuterCropRatio,
        innerCropRatio: effectiveInnerCropRatio,
        useBrightestNStars: effectiveUseBrightestNStars,
        focuserSettleTimeMs: effectiveFocuserSettleTimeMs,
        backlashCompMethod: effectiveBacklashCompMethod,
        backlashIn: effectiveBacklashIn,
        backlashOut: effectiveBacklashOut,
      );

      // Smart notification for autofocus completion
      final hfrText = result.bestHfr.toStringAsFixed(2);
      _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
            message: 'Autofocus complete (HFR: $hfrText)',
            relevantScreens: [
              AppScreen.imaging,
              AppScreen.equipment,
              AppScreen.sequencer
            ],
            title: 'Autofocus',
          );

      // Feed the persisted predictive-AF model (Wave 8 wire-up): record this
      // converged outcome as a training sample and, if we made a prediction
      // before the sweep, record the prediction-vs-actual error for drift
      // tracking. Failures here are logged but never abort the AF run — the
      // user already has their focus result.
      await _recordPredictiveAfOutcome(
        context: predictiveContext,
        result: result,
      );

      return result;
    } finally {
      _isAutofocusRunning = false;
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.autofocus);

      // Resume guiding if it was paused
      if (wasGuiding) {
        try {
          final loggingService = _ref.read(loggingServiceProvider);
          loggingService.info(
            'Resuming guiding after autofocus run',
            source: 'DeviceService',
          );
          await startGuiding();
        } catch (e) {
          final loggingService = _ref.read(loggingServiceProvider);
          loggingService.warning(
            'Failed to resume guiding after autofocus: $e',
            source: 'DeviceService',
          );
        }
      }
    }
  }

  /// Resolve the temperature to associate with a predictive-AF sample/decision.
  /// Prefers the temperature the AF backend captured during the sweep (most
  /// accurate, taken at measurement time); otherwise falls back to the
  /// focuser's currently-reported temperature. Returns `null` when neither is
  /// available — the predictive model is temperature-keyed, so we must not
  /// fabricate a reading.
  double? _resolvePredictiveAfTemperature(double? backendTemperature) {
    if (backendTemperature != null) {
      return backendTemperature;
    }
    return _ref.read(focuserStateProvider).temperature;
  }

  /// Consult the persisted predictive-AF model before a real sweep. This is
  /// advisory: we record the decision (for logging + later drift tracking) but
  /// always proceed with the requested full sweep. Returns the context needed
  /// to feed [recordPredictionVsActual] after the sweep, or `null` when the
  /// model cannot be consulted (no filter, no temperature, etc.).
  Future<_PredictiveAfContext?> _consultPredictiveAf({
    required String method,
  }) async {
    final temperature = _resolvePredictiveAfTemperature(null);
    final filterName = _ref.read(filterWheelStateProvider).currentFilterName;
    final profileId = _activeProfile?.id;

    // Without a filter name or a temperature, the model is not keyed/usable.
    // We still want to TRAIN on the outcome (recordAutofocusOutcome handles a
    // missing filter via a sentinel), but we can only meaningfully PREDICT
    // when both are present.
    if (filterName == null || temperature == null) {
      return _PredictiveAfContext(
        profileId: profileId,
        filterName: filterName,
        predictedPosition: null,
      );
    }

    final service = _ref.read(predictiveAfServiceProvider);
    try {
      final decision = await service.evaluateForFilter(
        equipmentProfileId: profileId,
        filterName: filterName,
        temperatureCelsius: temperature,
      );
      final logger = _ref.read(loggingServiceProvider);
      logger.info(
        'Predictive-AF pre-sweep decision for "$filterName" '
        '($method, ${temperature.toStringAsFixed(2)}C): '
        '${decision.runtimeType} '
        '(predicted=${decision.targetPosition}, '
        'confidence=${decision.confidence?.toStringAsFixed(3) ?? "n/a"})',
        source: 'DeviceService',
      );
      return _PredictiveAfContext(
        profileId: profileId,
        filterName: filterName,
        predictedPosition: decision.targetPosition,
      );
    } catch (e) {
      // Advisory-only: a model read failure must not block the real sweep.
      _ref.read(loggingServiceProvider).warning(
            'Predictive-AF consultation failed (continuing with real sweep): $e',
            source: 'DeviceService',
          );
      return _PredictiveAfContext(
        profileId: profileId,
        filterName: filterName,
        predictedPosition: null,
      );
    }
  }

  /// Record a converged autofocus outcome into the persisted predictive-AF
  /// model, and (when a pre-sweep prediction exists) record the
  /// prediction-vs-actual error so drift detection can surface re-train
  /// prompts. Never throws into the AF run.
  Future<void> _recordPredictiveAfOutcome({
    required _PredictiveAfContext? context,
    required AutofocusResult result,
  }) async {
    if (context == null) {
      return;
    }
    final temperature = _resolvePredictiveAfTemperature(result.temperature);
    final logger = _ref.read(loggingServiceProvider);

    if (context.filterName == null) {
      logger.info(
        'Predictive-AF: skipping training (no active filter to key the '
        'model). Position=${result.bestPosition}, HFR='
        '${result.bestHfr.toStringAsFixed(2)}.',
        source: 'DeviceService',
      );
      return;
    }
    if (temperature == null) {
      logger.info(
        'Predictive-AF: skipping training for "${context.filterName}" — no '
        'temperature available (focuser reports none). The model is '
        'temperature-keyed; refusing to fabricate a reading.',
        source: 'DeviceService',
      );
      return;
    }

    final service = _ref.read(predictiveAfServiceProvider);
    try {
      await service.recordAutofocusOutcome(
        equipmentProfileId: context.profileId,
        filterName: context.filterName!,
        temperatureCelsius: temperature,
        focusPosition: result.bestPosition,
        hfr: result.bestHfr,
      );
      logger.info(
        'Predictive-AF: recorded outcome for "${context.filterName}" '
        '(pos=${result.bestPosition}, HFR=${result.bestHfr.toStringAsFixed(2)}, '
        '${temperature.toStringAsFixed(2)}C).',
        source: 'DeviceService',
      );

      final predicted = context.predictedPosition;
      if (predicted != null) {
        final status = await service.recordPredictionVsActual(
          equipmentProfileId: context.profileId,
          filterName: context.filterName!,
          predictedPosition: predicted,
          actualPosition: result.bestPosition,
        );
        logger.info(
          'Predictive-AF: drift status for "${context.filterName}" = '
          '${status.runtimeType} (predicted=$predicted, '
          'actual=${result.bestPosition}).',
          source: 'DeviceService',
        );
      }
    } catch (e) {
      logger.warning(
        'Predictive-AF: failed to record outcome for "${context.filterName}": $e',
        source: 'DeviceService',
      );
    }
  }
}

/// Carries predictive-AF state across the real autofocus sweep so the
/// pre-sweep prediction can be reconciled with the converged result.
class _PredictiveAfContext {
  final int? profileId;
  final String? filterName;
  final int? predictedPosition;

  const _PredictiveAfContext({
    required this.profileId,
    required this.filterName,
    required this.predictedPosition,
  });
}
