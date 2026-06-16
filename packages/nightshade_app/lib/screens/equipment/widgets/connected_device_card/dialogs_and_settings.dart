part of '../connected_device_card.dart';

extension _ConnectedDeviceDialogsAndSettings on _ConnectedDeviceCardState {
  // ============================================================================
  // Dialogs
  // ============================================================================

  void _showMoveDialog(BuildContext context) async {
    final colors = NightshadeColors.of(context);
    final focuserState = ref.read(focuserStateProvider);
    final controller = TextEditingController(
      text: focuserState.position?.toString() ?? '0',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) => NightshadeDialog(
        title: 'Move Focuser',
        icon: LucideIcons.focus,
        width: 400,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final position = int.tryParse(controller.text);
              if (position != null) {
                Navigator.pop(context, position);
              }
            },
            label: 'Move',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter target position (0 - ${focuserState.maxPosition ?? 50000}):',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Position',
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      final deviceService = ref.read(deviceServiceProvider);
      try {
        await deviceService.moveFocuserTo(result);
        if (!context.mounted) return;
        context.showSuccessSnackBar('Moving focuser to $result');
      } catch (e) {
        if (!context.mounted) return;
        context.showErrorSnackBar('Failed to move focuser: $e');
      }
    }
  }

  void _showRotateDialog(BuildContext context) async {
    final colors = NightshadeColors.of(context);
    final rotatorState = ref.read(rotatorStateProvider);
    final controller = TextEditingController(
      text: rotatorState.position?.toStringAsFixed(1) ?? '0.0',
    );

    // Resolve the rotator's valid absolute-angle range from its reported
    // capabilities (mirrors rotator_panel.dart). Fall back to a full 0..360
    // turn when the driver does not advertise bounds, and treat an inverted
    // or degenerate range (min >= max) as missing data — also 0..360.
    final caps = ref
        .read(equipmentRotatorCapabilitiesProvider(
          rotatorState.deviceId ?? '',
        ))
        .valueOrNull;
    final rawMin = caps?.minAngleDeg ?? 0.0;
    final rawMax = caps?.maxAngleDeg ?? 360.0;
    final hasValidRange = rawMin < rawMax;
    final minAngle = hasValidRange ? rawMin : 0.0;
    final maxAngle = hasValidRange ? rawMax : 360.0;

    final result = await showDialog<double>(
      context: context,
      builder: (context) => NightshadeDialog(
        title: 'Rotate To Angle',
        icon: LucideIcons.rotateCcw,
        width: 400,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final angle = double.tryParse(controller.text);
              if (angle != null && angle >= minAngle && angle <= maxAngle) {
                Navigator.pop(context, angle);
              }
            },
            label: 'Rotate',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter target angle (${minAngle.toStringAsFixed(0)} - '
              '${maxAngle.toStringAsFixed(0)} degrees):',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Angle',
                suffixText: 'degrees',
                suffixStyle: TextStyle(color: colors.textMuted),
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      final backend = ref.read(deviceBackendProvider);
      final rotatorState = ref.read(rotatorStateProvider);
      if (rotatorState.deviceId != null) {
        try {
          await backend.rotatorMoveTo(rotatorState.deviceId!, result);
          if (!context.mounted) return;
          context.showSuccessSnackBar(
              'Rotating to ${result.toStringAsFixed(1)} degrees');
        } catch (e) {
          if (!context.mounted) return;
          context.showErrorSnackBar('Failed to rotate: $e');
        }
      }
    }
  }

  void _showDomeSlewDialog(BuildContext context) async {
    final colors = NightshadeColors.of(context);
    final domeState = ref.read(domeStateProvider);
    final controller = TextEditingController(
      text: domeState.azimuth?.toStringAsFixed(0) ?? '0',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => NightshadeDialog(
        title: 'Slew Dome To Azimuth',
        icon: LucideIcons.navigation,
        width: 400,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final az = double.tryParse(controller.text);
              if (az != null && az >= 0 && az <= 360) {
                Navigator.pop(context, az);
              }
            },
            label: 'Slew',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter target azimuth (0 - 360 degrees):',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Azimuth',
                suffixText: 'degrees',
                suffixStyle: TextStyle(color: colors.textMuted),
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      await _handleDomeSlew(result);
    }
  }

  void _showEditNameDialog(BuildContext context) async {
    final colors = NightshadeColors.of(context);
    final currentName = _getDeviceName();
    final controller = TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => NightshadeDialog(
        title: 'Edit Device Name',
        icon: LucideIcons.edit3,
        width: 400,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            label: 'Save',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter device name',
            hintStyle: TextStyle(color: colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        ),
      ),
    );

    if (result != null && context.mounted) {
      widget.onNameChanged?.call(result);
      context.showSuccessSnackBar('Device name updated');
    }
  }

  void _showMountSettingsDialog() async {
    final settingsAsync = ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettingsState();

    bool enableFlip = settings.enableMeridianFlip;
    final flipMinutesController =
        TextEditingController(text: settings.meridianFlipMinutes.toString());

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Mount Configuration',
              icon: LucideIcons.compass,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () async {
                    final minutes = int.tryParse(flipMinutesController.text) ??
                        settings.meridianFlipMinutes;
                    final notifier = ref.read(appSettingsProvider.notifier);
                    await notifier.setEnableMeridianFlip(enableFlip);
                    await notifier.setMeridianFlipMinutes(minutes);
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.showSuccessSnackBar('Mount settings updated');
                    }
                  },
                  label: 'Save',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Auto Meridian Flip',
                          style: TextStyle(color: colors.textPrimary)),
                      Switch(
                        value: enableFlip,
                        onChanged: (val) {
                          setState(() {
                            enableFlip = val;
                          });
                        },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: flipMinutesController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Meridian Flip Minutes',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            );
          });
        });
    flipMinutesController.dispose();
  }

  void _showFocuserSettingsDialog() async {
    final settingsAsync = ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettingsState();

    bool tempComp = settings.tempCompensation;
    final coeffController =
        TextEditingController(text: settings.tempCoefficient.toString());
    final backlashController =
        TextEditingController(text: settings.backlashCompensation.toString());

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Focuser Configuration',
              icon: LucideIcons.focus,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () async {
                    final coeff = double.tryParse(coeffController.text) ??
                        settings.tempCoefficient;
                    final backlash = int.tryParse(backlashController.text) ??
                        settings.backlashCompensation;
                    final notifier = ref.read(appSettingsProvider.notifier);
                    await notifier.setTempCompensation(tempComp);
                    await notifier.setTempCoefficient(coeff);
                    await notifier.setBacklashCompensation(backlash);
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.showSuccessSnackBar('Focuser settings updated');
                    }
                  },
                  label: 'Save',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Temperature Compensation',
                          style: TextStyle(color: colors.textPrimary)),
                      Switch(
                        value: tempComp,
                        onChanged: (val) {
                          setState(() {
                            tempComp = val;
                          });
                        },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: coeffController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Temp Coefficient (steps/C)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: backlashController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Backlash Compensation (steps)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            );
          });
        });
    coeffController.dispose();
    backlashController.dispose();
  }

  void _showRotatorSettingsDialog() async {
    final rotatorState = ref.read(rotatorStateProvider);
    bool reversed = rotatorState.isReversed;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Rotator Configuration',
              icon: LucideIcons.rotateCw,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () {
                    ref
                        .read(rotatorStateProvider.notifier)
                        .setReversed(reversed);
                    Navigator.pop(context);
                    context.showSuccessSnackBar('Rotator settings updated');
                  },
                  label: 'Save',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reverse Direction',
                          style: TextStyle(color: colors.textPrimary)),
                      Switch(
                        value: reversed,
                        onChanged: (val) {
                          setState(() {
                            reversed = val;
                          });
                        },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            );
          });
        });
  }

  void _showDomeSettingsDialog() async {
    final domeState = ref.read(domeStateProvider);
    bool slaved = domeState.isSlaved;
    // Capture the State's context up front: the Save handler is async and
    // snackbars must not use the dialog's (popped) context after the await.
    final pageContext = context;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Dome Configuration',
              icon: LucideIcons.home,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () async {
                    // Command the driver as well as updating local UI state —
                    // the toggle used to only set `domeStateProvider` and never
                    // actually slaved the dome.
                    final deviceId = domeState.deviceId;
                    Navigator.pop(context);
                    ref.read(domeStateProvider.notifier).setSlaved(slaved);
                    try {
                      final backend = ref.read(backendProvider);
                      if (backend is NetworkBackend) {
                        await backend.domeSync(slaved);
                      } else if (deviceId != null) {
                        await bridge_api.apiDomeSetSlaved(
                          deviceId: deviceId,
                          slaved: slaved,
                        );
                      }
                      if (mounted) {
                        pageContext.showSuccessSnackBar(
                          slaved ? 'Dome slaved to mount' : 'Dome unslaved',
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        pageContext.showErrorSnackBar('Dome slave failed: $e');
                      }
                    }
                  },
                  label: 'Save',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Slave to Mount (Follow Mount)',
                          style: TextStyle(color: colors.textPrimary)),
                      Switch(
                        value: slaved,
                        onChanged: (val) {
                          setState(() {
                            slaved = val;
                          });
                        },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            );
          });
        });
  }

  void _showCoverCalibratorSettingsDialog() async {
    final state = ref.read(coverCalibratorStateProvider);
    int brightness = state.brightness;
    final maxBrightness = state.maxBrightness > 0 ? state.maxBrightness : 255;
    final brightnessController =
        TextEditingController(text: brightness.toString());

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Calibrator Configuration',
              icon: LucideIcons.lamp,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () async {
                    final targetBrightness =
                        int.tryParse(brightnessController.text) ?? brightness;
                    if (targetBrightness >= 0 &&
                        targetBrightness <= maxBrightness) {
                      Navigator.pop(context);
                      await _handleCalibratorBrightness(targetBrightness);
                    } else {
                      context.showErrorSnackBar(
                          'Brightness must be between 0 and $maxBrightness');
                    }
                  },
                  label: 'Save',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calibrator Brightness (0 - $maxBrightness):',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: NightshadeTypography.fontSize13)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: brightnessController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Brightness',
                      hintStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            );
          });
        });
    brightnessController.dispose();
  }

  Future<void> _handleCalibratorBrightness(int brightness) async {
    final state = ref.read(coverCalibratorStateProvider);
    if (state.deviceId == null) return;
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.calibratorOn(brightness: brightness);
      } else {
        await bridge_api.apiCoverCalibratorCalibratorOn(
            deviceId: state.deviceId!, brightness: brightness);
      }
      ref
          .read(coverCalibratorStateProvider.notifier)
          .updateBrightness(brightness);
      if (mounted) {
        context.showSuccessSnackBar(
            'Calibrator brightness updated to $brightness');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to set brightness: $e');
      }
    }
  }
}
