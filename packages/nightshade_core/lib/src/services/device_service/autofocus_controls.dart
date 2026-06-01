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
}
