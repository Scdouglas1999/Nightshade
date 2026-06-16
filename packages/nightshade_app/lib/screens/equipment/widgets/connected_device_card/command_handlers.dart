part of '../connected_device_card.dart';

extension _ConnectedDeviceCommandHandlers on _ConnectedDeviceCardState {
  // ============================================================================
  // Action Handlers
  // ============================================================================

  Future<void> _handleDisconnect() async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      switch (widget.type) {
        case ConnectedDeviceType.camera:
          await deviceService.disconnectCamera();
          break;
        case ConnectedDeviceType.mount:
          await deviceService.disconnectMount();
          break;
        case ConnectedDeviceType.focuser:
          await deviceService.disconnectFocuser();
          break;
        case ConnectedDeviceType.filterWheel:
          await deviceService.disconnectFilterWheel();
          break;
        case ConnectedDeviceType.guider:
          await deviceService.disconnectGuider();
          break;
        case ConnectedDeviceType.rotator:
          await deviceService.disconnectRotator();
          break;
        case ConnectedDeviceType.dome:
          await deviceService.disconnectDome();
          break;
        case ConnectedDeviceType.weather:
          await deviceService.disconnectWeather();
          break;
        case ConnectedDeviceType.safetyMonitor:
          await deviceService.disconnectSafetyMonitor();
          break;
        case ConnectedDeviceType.coverCalibrator:
          await deviceService.disconnectCoverCalibrator();
          break;
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to disconnect: $e');
      }
    }
  }

  Future<void> _handleCoolCamera(double targetTemp) async {
    final deviceService = ref.read(deviceServiceProvider);
    // Cancel any in-progress warm-up before cooling
    deviceService.cancelWarmCamera();
    try {
      await deviceService.setCameraCooling(
          enabled: true, targetTemp: targetTemp);
      if (mounted) {
        context.showSuccessSnackBar(
            'Cooling to ${targetTemp.toStringAsFixed(0)}C');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to start cooling: $e');
      }
    }
  }

  Future<void> _showCoolingTempDialog(double currentTemp) async {
    final controller =
        TextEditingController(text: currentTemp.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final colors = NightshadeColors.of(ctx);
        return NightshadeDialog(
          title: 'Set Cooling Target',
          icon: LucideIcons.thermometer,
          width: 400,
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(ctx).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () {
                final temp = double.tryParse(controller.text);
                if (temp != null) Navigator.of(ctx).pop(temp);
              },
              label: 'Set',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Target Temperature (C)',
              labelStyle: TextStyle(color: colors.textMuted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            style: TextStyle(color: colors.textPrimary),
          ),
        );
      },
    );
    controller.dispose();
    if (result != null) {
      ref.read(cameraStateProvider.notifier).setTargetTemp(result);
    }
  }

  Future<void> _handleWarmCamera() async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.warmCamera();
      if (mounted) {
        context.showSuccessSnackBar('Gradually warming camera (2°C/min)');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to warm up: $e');
      }
    }
  }

  void _handleCancelWarm() {
    final deviceService = ref.read(deviceServiceProvider);
    deviceService.cancelWarmCamera();
    if (mounted) {
      context.showSuccessSnackBar('Warm-up cancelled');
    }
  }

  Future<void> _handleTogglePark() async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.togglePark();
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  Future<void> _handleFindHome() async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.findHome();
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  Future<void> _handleToggleTracking(bool currentlyTracking) async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.setTracking(!currentlyTracking);
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  /// Manually trigger a meridian flip now (outside the sequencer's automatic
  /// watchdog). Flips and re-points to the mount's current sky position. Useful
  /// when a remote operator is stalled at the meridian — there was previously
  /// no manual "flip now" control anywhere.
  Future<void> _handleManualMeridianFlip() async {
    final mountState = ref.read(mountStateProvider);
    final mountId = mountState.deviceId;
    final ra = mountState.ra;
    final dec = mountState.dec;
    if (mountId == null || ra == null || dec == null) {
      if (mounted) {
        context.showErrorSnackBar('Mount position unavailable for a flip');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => NightshadeDialog(
        title: 'Meridian Flip Now?',
        icon: LucideIcons.flipHorizontal,
        width: 400,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(ctx, false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Flip',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
        child: Text(
          'This slews the mount across the meridian and re-points to the '
          'current position. Guiding pauses and resumes automatically. '
          'Proceed?',
          style: TextStyle(
            color: NightshadeColors.of(ctx).textSecondary,
            fontSize: NightshadeTypography.fontSize13,
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sequencerBackendProvider).performMeridianFlip(
            mountId: mountId,
            targetName: 'Manual flip',
            targetRaHours: ra,
            targetDecDegrees: dec,
            pauseGuiding: true,
            autoCenter: true,
            refocusAfter: false,
            resumeGuiding: true,
            settleTimeSecs: 30,
          );
      if (mounted) context.showSuccessSnackBar('Meridian flip started');
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Meridian flip failed: $e');
    }
  }

  Future<void> _handleFilterChange(int position) async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.setFilterWheelPosition(position);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to change filter: $e');
      }
    }
  }

  Future<void> _handleToggleGuiding(bool currentlyGuiding) async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      if (currentlyGuiding) {
        await deviceService.stopGuiding();
        if (mounted) {
          context.showSuccessSnackBar('Guiding stopped');
        }
      } else {
        await deviceService.startGuiding();
        if (mounted) {
          context.showSuccessSnackBar('Guiding started');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Guiding operation failed: $e');
      }
    }
  }

  // ============================================================================
  // Dome Action Handlers
  // ============================================================================

  Future<void> _handleDomeShutter(ShutterStatus currentStatus) async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        if (currentStatus == ShutterStatus.open) {
          await backend.domeClose();
        } else {
          await backend.domeOpen();
        }
      } else {
        if (currentStatus == ShutterStatus.open) {
          await bridge_api.apiDomeCloseShutter(deviceId: domeState.deviceId!);
        } else {
          await bridge_api.apiDomeOpenShutter(deviceId: domeState.deviceId!);
        }
      }
      if (mounted) {
        context.showSuccessSnackBar(
          currentStatus == ShutterStatus.open
              ? 'Closing dome shutter'
              : 'Opening dome shutter',
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome shutter operation failed: $e');
      }
    }
  }

  Future<void> _handleDomePark(bool isParked) async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      if (!isParked) {
        final backend = ref.read(backendProvider);
        if (backend is NetworkBackend) {
          await backend.domePark();
        } else {
          await bridge_api.apiDomePark(deviceId: domeState.deviceId!);
        }
        if (mounted) {
          context.showSuccessSnackBar('Parking dome');
        }
      } else {
        // ASCOM domes have no explicit unpark verb; finding home releases the
        // parked state (standard ASCOM behaviour). Drive it so the "Unpark"
        // button is functional instead of a no-op hint.
        final backend = ref.read(backendProvider);
        if (backend is NetworkBackend) {
          await backend.domeHome();
        } else {
          await bridge_api.apiDomeFindHome(deviceId: domeState.deviceId!);
        }
        if (mounted) {
          context.showSuccessSnackBar('Unparking dome (homing)');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome park operation failed: $e');
      }
    }
  }

  Future<void> _handleDomeSlew(double azimuth) async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.domeSlew(azimuth);
      } else {
        await bridge_api.apiDomeSlewToAzimuth(
          deviceId: domeState.deviceId!,
          azimuth: azimuth,
        );
      }
      if (mounted) {
        context.showSuccessSnackBar(
          'Slewing dome to ${azimuth.toStringAsFixed(0)}°',
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome slew failed: $e');
      }
    }
  }

  Future<void> _handleDomeHome() async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.domeHome();
      } else {
        await bridge_api.apiDomeFindHome(deviceId: domeState.deviceId!);
      }
      if (mounted) {
        context.showSuccessSnackBar('Homing dome');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome home failed: $e');
      }
    }
  }

  Future<void> _handleDomeHalt() async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.domeHalt();
      } else {
        await bridge_api.apiDomeAbortSlew(deviceId: domeState.deviceId!);
      }
      if (mounted) {
        context.showSuccessSnackBar('Stopping dome');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome halt failed: $e');
      }
    }
  }

  /// Acknowledge an unsafe safety-monitor condition. This is a headless-server
  /// concept (the appliance records the acknowledgement and suppresses the
  /// unsafe gate for the chosen window), so it applies to remote sessions; the
  /// local desktop manages safety directly through its sequencer settings.
  Future<void> _handleSafetyAcknowledge() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      if (mounted) {
        context.showInfoSnackBar(
          'Safety acknowledgement is managed by the appliance (remote sessions).',
        );
      }
      return;
    }
    try {
      await backend.acknowledgeSafetyCondition(
        reason: 'Acknowledged from app',
      );
      if (mounted) {
        context.showSuccessSnackBar('Safety condition acknowledged');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Acknowledge failed: $e');
      }
    }
  }

  // ============================================================================
  // Cover Calibrator Action Handlers
  // ============================================================================

  Future<void> _handleCoverToggle(bool isOpen) async {
    final coverState = ref.read(coverCalibratorStateProvider);
    if (coverState.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        if (isOpen) {
          await backend.coverClose();
        } else {
          await backend.coverOpen();
        }
      } else {
        if (isOpen) {
          await bridge_api.apiCoverCalibratorCloseCover(
              deviceId: coverState.deviceId!);
        } else {
          await bridge_api.apiCoverCalibratorOpenCover(
              deviceId: coverState.deviceId!);
        }
      }
      if (mounted) {
        context.showSuccessSnackBar(isOpen ? 'Closing cover' : 'Opening cover');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Cover operation failed: $e');
      }
    }
  }

  Future<void> _handleCalibratorToggle(CoverCalibratorState state) async {
    if (state.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (state.isCalibratorOn) {
        if (backend is NetworkBackend) {
          await backend.calibratorOff();
        } else {
          await bridge_api.apiCoverCalibratorCalibratorOff(
              deviceId: state.deviceId!);
        }
        if (mounted) {
          context.showSuccessSnackBar('Calibrator light off');
        }
      } else {
        final brightness =
            state.brightness > 0 ? state.brightness : state.maxBrightness;
        if (backend is NetworkBackend) {
          await backend.calibratorOn(brightness: brightness);
        } else {
          await bridge_api.apiCoverCalibratorCalibratorOn(
              deviceId: state.deviceId!, brightness: brightness);
        }
        if (mounted) {
          context.showSuccessSnackBar(
              'Calibrator light on at brightness $brightness');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Calibrator operation failed: $e');
      }
    }
  }
}
