part of '../flat_wizard_screen.dart';

class _ActionButtons extends ConsumerWidget {
  final FlatWizardMode mode;

  const _ActionButtons({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertCircle, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(fontSize: 13, color: colors.error),
                  ),
                ),
                IconButton(
                  onPressed: notifier.clearError,
                  icon: const Icon(LucideIcons.x, size: 16),
                  color: colors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (state.isCapturing)
          NightshadeButton(
            label: 'Stop Capture',
            onPressed: notifier.requestCancel,
            variant: ButtonVariant.destructive,
          )
        else
          NightshadeButton(
            key: FlatWizardTutorialKeys.startBtn,
            label:
                mode == FlatWizardMode.quick ? 'Start Capture' : 'Start Batch',
            onPressed: () => _startCapture(context, ref),
          ),
      ],
    );
  }

  Future<void> _startCapture(BuildContext context, WidgetRef ref) async {
    final state = ref.read(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    // Check if save path is set
    if (state.globalSettings.savePath == null ||
        state.globalSettings.savePath!.isEmpty) {
      final result = await SavePathDialog.show(
        context,
        currentPath: state.globalSettings.savePath,
        createDateSubfolder: state.globalSettings.createDateSubfolder,
        createFilterSubfolders: state.globalSettings.createFilterSubfolders,
      );

      if (result == null) return; // User cancelled

      notifier.updateGlobalSettings(
        state.globalSettings.copyWith(
          savePath: result.path,
          createDateSubfolder: result.createDateSubfolder,
          createFilterSubfolders: result.createFilterSubfolders,
        ),
      );
    }

    // Re-read state after potential save path update
    final currentState = ref.read(flatWizardProvider);

    // Start capture
    notifier.setCapturing(true);
    notifier.clearCancelRequest();
    notifier.clearAduHistory();
    notifier.setStatusMessage('Initializing...');

    try {
      await _runCaptureSequence(ref, currentState);
    } catch (e) {
      notifier.setErrorMessage('Capture failed: $e');
    } finally {
      notifier.setCapturing(false);
      notifier.setExposing(false);
      notifier.setStatusMessage(null);
    }
  }

  Future<void> _runCaptureSequence(WidgetRef ref, FlatWizardState state) async {
    final notifier = ref.read(flatWizardProvider.notifier);
    final cameraState = ref.read(cameraStateProvider);
    // A-12: legitimately multi-role — _runCaptureSequence drives camera
    // exposures (DeviceBackend) AND saves FITS via saveFitsFromLastCapture
    // (ImagingBackend) in one coordinated loop.
    final backend = ref.read(backendProvider);
    final flatService = ref.read(flatWizardServiceProvider);
    final db = ref.read(databaseProvider);
    final activeProfile = ref.read(activeEquipmentProfileProvider);
    final profileId = activeProfile?.id;
    final defaultGain = activeProfile?.defaultGain ?? cameraState.gain ?? 0;
    final defaultOffset =
        activeProfile?.defaultOffset ?? cameraState.offset ?? 0;
    final brightnessTracker = ref.read(skyBrightnessTrackerProvider);

    // Validate camera is connected
    if (cameraState.connectionState != DeviceConnectionState.connected ||
        cameraState.deviceId == null) {
      notifier.setErrorMessage('Camera not connected');
      return;
    }

    final cameraId = cameraState.deviceId!;

    // Build save path with optional date subfolder
    String baseSavePath = state.globalSettings.savePath!;
    if (state.globalSettings.createDateSubfolder) {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      baseSavePath = p.join(baseSavePath, dateStr);
    }

    // Ensure base directory exists
    await Directory(baseSavePath).create(recursive: true);

    // Get list of filters to process
    final filtersToProcess = _getFiltersToProcess(state);
    if (filtersToProcess.isEmpty) {
      notifier.setErrorMessage('No filters selected');
      return;
    }

    // Process each filter
    for (int filterIdx = 0; filterIdx < filtersToProcess.length; filterIdx++) {
      if (notifier.cancelRequested) {
        notifier.setStatusMessage('Cancelled');
        break;
      }

      final filterSetting = filtersToProcess[filterIdx];
      notifier.setCurrentFilterIndex(filterIdx);
      notifier.updateFilterStatus(
          filterIdx, FilterCalibrationStatus.calibrating);
      notifier.setStatusMessage('Calibrating ${filterSetting.filterName}...');

      // Move filter wheel if needed
      await _moveFilterWheel(ref, filterSetting.filterPosition);

      // Calculate target ADU from histogram percentage
      final targetAdu = FlatExposureCalculator.histogramPercentToAdu(
        filterSetting.histogramTargetOverride ??
            state.globalSettings.histogramTarget,
      ).toDouble();

      final tolerance = filterSetting.toleranceOverride ??
          state.globalSettings.tolerancePercent;
      final minExp =
          filterSetting.minExposureOverride ?? state.globalSettings.minExposure;
      final maxExp =
          filterSetting.maxExposureOverride ?? state.globalSettings.maxExposure;

      // Calibrate exposure
      FlatResult calibrationResult;
      if (state.mode == FlatWizardMode.skyFlats) {
        // Use rate-tracking calibration for sky flats
        calibrationResult = await flatService.calibrateFilterWithRateTracking(
          deviceId: cameraId,
          filter: filterSetting.filterName,
          gain: defaultGain,
          offset: defaultOffset,
          targetAdu: targetAdu,
          tolerance: tolerance,
          minExposure: minExp,
          maxExposure: maxExp,
          brightnessTracker: brightnessTracker,
          historicalExposure: filterSetting.suggestedExposure,
          onProgress: (iteration, exposure, adu, status) {
            notifier.addAduMeasurement(exposure, adu);
            notifier.updateFilterCalibration(filterIdx, exposure, adu);
            notifier.setStatusMessage(
              '${filterSetting.filterName}: $status (${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
            );
          },
        );
      } else {
        // Use standard calibration for flat panels
        calibrationResult = await flatService.calibrateFilter(
          deviceId: cameraId,
          filter: filterSetting.filterName,
          gain: defaultGain,
          offset: defaultOffset,
          targetAdu: targetAdu,
          tolerance: tolerance,
          minExposure: minExp,
          maxExposure: maxExp,
          onProgress: (iteration, exposure, adu) {
            notifier.addAduMeasurement(exposure, adu);
            notifier.updateFilterCalibration(filterIdx, exposure, adu);
            notifier.setStatusMessage(
              '${filterSetting.filterName}: Iteration $iteration (${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
            );
          },
        );
      }

      if (!calibrationResult.success) {
        notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.failed);
        notifier.setWarningMessage(
          '${filterSetting.filterName}: ${calibrationResult.errorMessage ?? "Calibration failed"}',
        );
        // Continue to next filter instead of stopping
        continue;
      }

      // Update filter with calibrated exposure
      notifier.updateFilterCalibration(
        filterIdx,
        calibrationResult.exposure,
        calibrationResult.adu,
      );
      notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.capturing);

      // Build filter-specific save path
      String filterSavePath = baseSavePath;
      if (state.globalSettings.createFilterSubfolders) {
        filterSavePath = p.join(baseSavePath, filterSetting.filterName);
        await Directory(filterSavePath).create(recursive: true);
      }

      // Capture frames
      final frameCount =
          filterSetting.frameCountOverride ?? state.globalSettings.frameCount;

      for (int frameNum = 1; frameNum <= frameCount; frameNum++) {
        if (notifier.cancelRequested) {
          notifier.setStatusMessage('Cancelled');
          break;
        }

        notifier.setCurrentFrameIndex(frameNum);
        notifier.setStatusMessage(
          '${filterSetting.filterName}: Capturing frame $frameNum/$frameCount',
        );

        // Start exposure with countdown
        notifier.setExposing(
          true,
          startTime: DateTime.now(),
          duration: calibrationResult.exposure,
        );

        // Capture frame
        try {
          await backend.cameraStartExposure(
            deviceId: cameraId,
            exposureTime: calibrationResult.exposure,
            frameType: FrameType.flat,
            gain: cameraState.gain ?? 0,
            offset: cameraState.offset ?? 0,
            binX: 1,
            binY: 1,
          );

          // Wait for exposure to complete
          await Future.delayed(
            Duration(
                milliseconds:
                    (calibrationResult.exposure * 1000 + 500).toInt()),
          );

          notifier.setExposing(false);

          // Get the captured image for preview
          final image = await backend.cameraGetLastImage(cameraId);
          if (image != null) {
            // Update preview with latest image data
            notifier.setLastImage(null, image.displayData);

            // Update ADU reading from actual capture
            notifier.addAduMeasurement(
                calibrationResult.exposure, image.stats.mean);
          }

          // Generate filename and save
          final captureTime = DateTime.now();
          final timestamp = DateFormat('yyyyMMdd_HHmmss').format(captureTime);
          final filename =
              'Flat_${filterSetting.filterName}_${timestamp}_$frameNum.fits';
          final filePath = p.join(filterSavePath, filename);

          await backend.saveFitsFromLastCapture(
            deviceId: cameraId,
            filePath: filePath,
            headerData: FitsWriteHeader(
              frameType: 'FLAT',
              filter: filterSetting.filterName,
              exposureTime: calibrationResult.exposure,
              captureTimestamp: captureTime.toIso8601String(),
              gain: cameraState.gain,
              offset: cameraState.offset,
              binX: 1,
              binY: 1,
            ),
          );

          notifier.incrementFilterCapturedCount(filterIdx);
          notifier.setLastImage(filePath, image?.displayData);
        } catch (e) {
          notifier.setExposing(false);
          notifier.setWarningMessage('Frame $frameNum failed: $e');
          // Continue to next frame
        }
      }

      if (notifier.cancelRequested) break;

      // Mark filter complete
      notifier.updateFilterStatus(filterIdx, FilterCalibrationStatus.complete);

      // Record calibration to history database
      try {
        await db.flatHistoryDao.recordCalibration(
          filterName: filterSetting.filterName,
          exposureTime: calibrationResult.exposure,
          histogramTarget: state.globalSettings.histogramTarget,
          actualAdu: calibrationResult.adu.toInt(),
          equipmentProfileId: profileId,
          skyAduRate: state.mode == FlatWizardMode.skyFlats
              ? brightnessTracker.calculateRate()
              : null,
          twilightPhase: state.mode == FlatWizardMode.skyFlats
              ? (state.twilightMode == TwilightMode.dawn ? 'dawn' : 'dusk')
              : null,
        );
      } catch (e) {
        debugPrint('[FlatWizard] Failed to record calibration to history: $e');
      }
    }

    // Final status
    if (notifier.cancelRequested) {
      final completed = filtersToProcess
          .where((f) => f.status == FilterCalibrationStatus.complete)
          .length;
      notifier.setStatusMessage('Cancelled. Completed $completed filters.');
    } else {
      notifier.setStatusMessage('Complete!');
    }
  }

  List<FlatFilterSettings> _getFiltersToProcess(FlatWizardState state) {
    if (state.mode == FlatWizardMode.quick) {
      // Quick mode: just the current filter
      if (state.filterSettings.isNotEmpty &&
          state.currentFilterIndex < state.filterSettings.length) {
        return [state.filterSettings[state.currentFilterIndex]];
      }
      return [];
    } else {
      // Batch/Sky mode: all enabled filters
      return state.filterSettings.where((f) => f.enabled).toList();
    }
  }

  Future<void> _moveFilterWheel(WidgetRef ref, int position) async {
    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.connectionState != DeviceConnectionState.connected ||
        fwState.deviceId == null) {
      return; // No filter wheel connected, skip
    }

    if (fwState.currentPosition == position) {
      return; // Already at correct position
    }

    final backend = ref.read(deviceBackendProvider);
    await backend.filterWheelSetPosition(fwState.deviceId!, position);

    // Wait for filter wheel to settle
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
