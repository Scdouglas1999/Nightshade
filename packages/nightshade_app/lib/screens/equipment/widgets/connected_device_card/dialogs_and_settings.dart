part of '../connected_device_card.dart';

extension _ConnectedDeviceDialogsAndSettings on _ConnectedDeviceCardState {
  // ============================================================================
  // Dialogs
  // ============================================================================

  void _showMoveDialog(BuildContext context) async {
    final focuserState = ref.read(focuserStateProvider);
    final reportedMax = focuserState.maxPosition;
    final maxPosition =
        reportedMax != null && reportedMax > 0 ? reportedMax : null;
    var positionText = focuserState.position?.toString() ?? '0';
    var isMoving = false;
    var isHalting = false;
    String? errorText;
    final pageContext = context;

    await _showEquipmentDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final colors = NightshadeColors.of(dialogContext);
          Future<void> haltMove() async {
            if (!isMoving || isHalting) return;
            setState(() {
              isHalting = true;
              errorText = null;
            });
            try {
              await ref.read(deviceServiceProvider).haltFocuser();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (pageContext.mounted) {
                pageContext.showInfoSnackBar('Focuser halted');
              }
            } catch (e) {
              if (!dialogContext.mounted) return;
              setState(() {
                isHalting = false;
                errorText = 'Failed to halt focuser: $e';
              });
            }
          }

          return PopScope(
            canPop: !isMoving,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && isMoving) {
                unawaited(haltMove());
              }
            },
            child: NightshadeDialog(
              title: 'Move Focuser',
              icon: LucideIcons.focus,
              width: 400,
              actions: [
                if (!isMoving)
                  NightshadeButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  )
                else
                  NightshadeButton(
                    onPressed: isHalting ? null : haltMove,
                    label: isHalting ? 'Stopping...' : 'Stop',
                    isLoading: isHalting,
                    variant: ButtonVariant.destructive,
                    size: ButtonSize.small,
                  ),
                NightshadeButton(
                  onPressed: isMoving
                      ? null
                      : () async {
                          if (isMoving) return;
                          final position = int.tryParse(positionText.trim());
                          if (position == null) {
                            setState(() => errorText =
                                'Enter a whole-number focuser position.');
                            return;
                          }
                          if (position < 0) {
                            setState(() =>
                                errorText = 'Position cannot be negative.');
                            return;
                          }
                          if (maxPosition != null && position > maxPosition) {
                            setState(() => errorText =
                                'Position must be between 0 and $maxPosition.');
                            return;
                          }

                          setState(() {
                            errorText = null;
                            isMoving = true;
                          });
                          try {
                            await ref
                                .read(deviceServiceProvider)
                                .moveFocuserTo(position);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                'Focuser moved to $position',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setState(() {
                              isMoving = false;
                              errorText = 'Failed to move focuser: $e';
                            });
                          }
                        },
                  label: isMoving ? 'Moving...' : 'Move',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maxPosition == null
                        ? 'Enter a target position of 0 or greater. '
                            'The driver did not report a maximum.'
                        : 'Enter target position (0 - $maxPosition):',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: positionText,
                    onChanged: (value) => positionText = value,
                    enabled: !isMoving,
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
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: colors.error,
                        fontSize: NightshadeTypography.fontSize13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRotateDialog(BuildContext context) async {
    final rotatorState = ref.read(rotatorStateProvider);
    var angleText = rotatorState.position?.toStringAsFixed(1) ?? '0.0';

    // Resolve the rotator's valid absolute-angle range from its reported
    // capabilities (mirrors rotator_panel.dart). Fall back to a full 0..360
    // turn when the driver does not advertise bounds, and treat an inverted
    // or degenerate range (min >= max) as missing data — also 0..360.
    RotatorCapabilities? caps;
    final rotatorId = rotatorState.deviceId;
    if (rotatorId != null && rotatorId.isNotEmpty) {
      try {
        caps = await ref.read(
          equipmentRotatorCapabilitiesProvider(rotatorId).future,
        );
      } catch (_) {
        // Unknown bounds fall back to the full mechanical turn below.
      }
    }
    if (!context.mounted) {
      return;
    }
    final rawMin = caps?.minAngleDeg ?? 0.0;
    final rawMax = caps?.maxAngleDeg ?? 360.0;
    final hasValidRange = rawMin.isFinite && rawMax.isFinite && rawMin < rawMax;
    final minAngle = hasValidRange ? rawMin : 0.0;
    final maxAngle = hasValidRange ? rawMax : 360.0;
    final canHalt = caps?.canHalt == true;
    String formatBound(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    var isRotating = false;
    var isHalting = false;
    String? errorText;
    final pageContext = context;

    await _showEquipmentDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final dialogColors = NightshadeColors.of(dialogContext);
          Future<void> haltRotation() async {
            if (!isRotating || isHalting || !canHalt) return;
            setState(() {
              isHalting = true;
              errorText = null;
            });
            try {
              await ref.read(deviceServiceProvider).haltRotator();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (pageContext.mounted) {
                pageContext.showInfoSnackBar('Rotator halted');
              }
            } catch (e) {
              if (!dialogContext.mounted) return;
              setState(() {
                isHalting = false;
                errorText = 'Failed to halt rotator: $e';
              });
            }
          }

          return PopScope(
            canPop: !isRotating,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && isRotating && canHalt) {
                unawaited(haltRotation());
              }
            },
            child: NightshadeDialog(
              title: 'Rotate To Angle',
              icon: LucideIcons.rotateCcw,
              width: 400,
              actions: [
                if (!isRotating)
                  NightshadeButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  )
                else if (canHalt)
                  NightshadeButton(
                    onPressed: isHalting ? null : haltRotation,
                    label: isHalting ? 'Stopping...' : 'Stop',
                    isLoading: isHalting,
                    variant: ButtonVariant.destructive,
                    size: ButtonSize.small,
                  ),
                NightshadeButton(
                  onPressed: isRotating
                      ? null
                      : () async {
                          if (isRotating) return;
                          final angle = double.tryParse(angleText.trim());
                          if (angle == null || !angle.isFinite) {
                            setState(() =>
                                errorText = 'Enter a finite angle in degrees.');
                            return;
                          }
                          if (angle < minAngle || angle > maxAngle) {
                            setState(() => errorText = 'Angle must be between '
                                '${formatBound(minAngle)} and '
                                '${formatBound(maxAngle)} degrees.');
                            return;
                          }

                          setState(() {
                            errorText = null;
                            isRotating = true;
                          });
                          try {
                            await ref
                                .read(deviceServiceProvider)
                                .moveRotatorTo(angle);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                'Rotated to ${angle.toStringAsFixed(1)} degrees',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setState(() {
                              isRotating = false;
                              errorText = 'Failed to rotate: $e';
                            });
                          }
                        },
                  label: isRotating ? 'Rotating...' : 'Rotate',
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter target angle (${formatBound(minAngle)} - '
                    '${formatBound(maxAngle)} degrees):',
                    style: TextStyle(
                      color: dialogColors.textSecondary,
                      fontSize: NightshadeTypography.fontSize13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: angleText,
                    onChanged: (value) => angleText = value,
                    enabled: !isRotating,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: dialogColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Angle',
                      suffixText: 'degrees',
                      suffixStyle: TextStyle(color: dialogColors.textMuted),
                      hintStyle: TextStyle(color: dialogColors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: dialogColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: dialogColors.primary),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: dialogColors.error,
                        fontSize: NightshadeTypography.fontSize13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDomeSlewDialog(BuildContext context) async {
    final domeState = ref.read(domeStateProvider);
    var azimuthText = domeState.azimuth?.toStringAsFixed(0) ?? '0';
    var isSending = false;
    String? errorText;
    final pageContext = context;

    await _showEquipmentDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final colors = NightshadeColors.of(dialogContext);
          return PopScope(
            canPop: !isSending,
            child: NightshadeDialog(
              title: 'Slew Dome To Azimuth',
              icon: LucideIcons.navigation,
              width: 400,
              actions: [
                NightshadeButton(
                  onPressed:
                      isSending ? null : () => Navigator.pop(dialogContext),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          if (isSending) return;
                          final azimuth = double.tryParse(azimuthText.trim());
                          if (azimuth == null || !azimuth.isFinite) {
                            setState(() => errorText =
                                'Enter a finite azimuth in degrees.');
                            return;
                          }
                          if (azimuth < 0 || azimuth > 360) {
                            setState(() => errorText =
                                'Azimuth must be between 0 and 360 degrees.');
                            return;
                          }
                          final deviceId = domeState.deviceId;
                          if (deviceId == null || deviceId.isEmpty) {
                            setState(() =>
                                errorText = 'No dome is currently connected.');
                            return;
                          }

                          setState(() {
                            errorText = null;
                            isSending = true;
                          });
                          try {
                            await ref
                                .read(backendProvider)
                                .domeSlewToAzimuth(deviceId, azimuth);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                'Dome slew command sent for '
                                '${azimuth.toStringAsFixed(1)} degrees',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setState(() {
                              isSending = false;
                              errorText = 'Dome slew failed: $e';
                            });
                          }
                        },
                  label: isSending ? 'Sending...' : 'Slew',
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
                      fontSize: NightshadeTypography.fontSize13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: azimuthText,
                    onChanged: (value) => azimuthText = value,
                    enabled: !isSending,
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
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: colors.error,
                        fontSize: NightshadeTypography.fontSize13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Canonical meridian-flip warning-window bounds, mirroring
  // MeridianFlipSettings.validate (0..120 minutes). Kept as a named constant so
  // the field hint, validation, and tests reference one source of truth.
  static const int _minFlipMinutes = 0;
  static const int _maxFlipMinutes = 120;

  void _showMountSettingsDialog() async {
    late final AppSettingsState settings;
    try {
      settings = await ref.read(appSettingsProvider.future);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not load mount settings: $e');
      }
      return;
    }
    if (!mounted) return;

    bool enableFlip = settings.enableMeridianFlip;
    var flipMinutesText = settings.meridianFlipMinutes.toString();
    // Capture the State's context up front: the Save handler is async and the
    // success snackbar must not use the dialog's (popped) context after the
    // await.
    final pageContext = context;
    bool isSaving = false;
    String? errorText;

    await _showEquipmentDialog(
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          // Re-entrancy guard: the disabled state only takes
                          // effect on the next rebuild, so a rapid double-tap
                          // could otherwise re-enter before setState lands.
                          if (isSaving) return;
                          final raw = flipMinutesText.trim();
                          final minutes = int.tryParse(raw);
                          if (minutes == null) {
                            setState(() =>
                                errorText = 'Enter a whole number of minutes.');
                            return;
                          }
                          if (minutes < _minFlipMinutes ||
                              minutes > _maxFlipMinutes) {
                            setState(() => errorText =
                                'Minutes must be between $_minFlipMinutes '
                                    'and $_maxFlipMinutes.');
                            return;
                          }
                          setState(() {
                            errorText = null;
                            isSaving = true;
                          });
                          try {
                            await ref
                                .read(appSettingsProvider.notifier)
                                .setMeridianFlipConfig(
                                  enableFlip: enableFlip,
                                  minutes: minutes,
                                );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                  'Mount settings updated');
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() {
                              isSaving = false;
                              errorText = 'Failed to save: $e';
                            });
                          }
                        },
                  label: isSaving ? 'Saving...' : 'Save',
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
                        onChanged: isSaving
                            ? null
                            : (val) {
                                setState(() {
                                  enableFlip = val;
                                });
                              },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: flipMinutesText,
                    onChanged: (value) => flipMinutesText = value,
                    enabled: !isSaving,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText:
                          'Meridian Flip Minutes ($_minFlipMinutes - $_maxFlipMinutes)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                          color: colors.error,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ],
                ],
              ),
            );
          });
        });
  }

  // Canonical backlash-compensation bounds, mirroring the autofocus backlash
  // IN/OUT fields and the driver step limit (0..10000 steps). The coefficient
  // is only required to be finite: it is legitimately negative (default -12
  // steps/°C) and zero is the documented "track but do not move" state, so no
  // narrow range is imposed.
  static const int _minBacklashSteps = 0;
  static const int _maxBacklashSteps = 10000;

  void _showFocuserSettingsDialog() async {
    late final AppSettingsState settings;
    try {
      settings = await ref.read(appSettingsProvider.future);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not load focuser settings: $e');
      }
      return;
    }
    if (!mounted) return;

    bool tempComp = settings.tempCompensation;
    var coefficientText = settings.tempCoefficient.toString();
    var backlashText = settings.backlashCompensation.toString();
    final pageContext = context;
    bool isSaving = false;
    String? errorText;

    await _showEquipmentDialog(
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (isSaving) return;
                          final coeff = double.tryParse(coefficientText.trim());
                          if (coeff == null || !coeff.isFinite) {
                            setState(() => errorText =
                                'Temp coefficient must be a finite number.');
                            return;
                          }
                          final backlash = int.tryParse(backlashText.trim());
                          if (backlash == null) {
                            setState(() => errorText =
                                'Backlash must be a whole number of steps.');
                            return;
                          }
                          if (backlash < _minBacklashSteps ||
                              backlash > _maxBacklashSteps) {
                            setState(() => errorText =
                                'Backlash must be between $_minBacklashSteps '
                                    'and $_maxBacklashSteps steps.');
                            return;
                          }
                          setState(() {
                            errorText = null;
                            isSaving = true;
                          });
                          try {
                            await ref
                                .read(appSettingsProvider.notifier)
                                .setFocuserCompensationConfig(
                                  tempCompensation: tempComp,
                                  tempCoefficient: coeff,
                                  backlashCompensation: backlash,
                                );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                  'Focuser settings updated');
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() {
                              isSaving = false;
                              errorText = 'Failed to save: $e';
                            });
                          }
                        },
                  label: isSaving ? 'Saving...' : 'Save',
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
                      Expanded(
                        child: Text(
                          'Temperature Compensation',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                      Switch(
                        value: tempComp,
                        onChanged: isSaving
                            ? null
                            : (val) {
                                setState(() {
                                  tempComp = val;
                                });
                              },
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: coefficientText,
                    onChanged: (value) => coefficientText = value,
                    enabled: !isSaving,
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
                  TextFormField(
                    initialValue: backlashText,
                    onChanged: (value) => backlashText = value,
                    enabled: !isSaving,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText:
                          'Backlash Compensation ($_minBacklashSteps - $_maxBacklashSteps steps)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                          color: colors.error,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ],
                ],
              ),
            );
          });
        });
  }

  void _showRotatorSettingsDialog() async {
    final rotatorState = ref.read(rotatorStateProvider);
    final originalReversed = rotatorState.isReversed;
    bool reversed = rotatorState.isReversed;
    bool isSaving = false;
    final pageContext = context;

    // Only expose the reverse toggle when the driver advertises reverse support
    // (IRotatorV3 CanReverse / Alpaca canreverse). Await the capability query:
    // reading valueOrNull synchronously disabled a supported rotator whenever
    // the dialog was opened before the async probe happened to finish.
    var canReverse = false;
    final deviceId = rotatorState.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        final caps = await ref.read(
          equipmentRotatorCapabilitiesProvider(deviceId).future,
        );
        canReverse = caps?.canReverse ?? false;
      } catch (_) {
        canReverse = false;
      }
    }
    if (!mounted) return;

    await _showEquipmentDialog(
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (reversed == originalReversed) {
                            Navigator.pop(context);
                            return;
                          }
                          setState(() => isSaving = true);
                          try {
                            await ref
                                .read(deviceServiceProvider)
                                .setRotatorReversed(reversed);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                'Rotator settings updated',
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() => isSaving = false);
                            context.showErrorSnackBar(
                              'Failed to set reverse direction: $e',
                            );
                          }
                        },
                  label: isSaving ? 'Saving...' : 'Save',
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
                        onChanged: canReverse && !isSaving
                            ? (val) => setState(() => reversed = val)
                            : null,
                        activeThumbColor: colors.primary,
                      ),
                    ],
                  ),
                  if (!canReverse) ...[
                    const SizedBox(height: 8),
                    Text(
                      'This rotator does not report reverse-direction support.',
                      style: TextStyle(
                          color: colors.textMuted,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ],
                ],
              ),
            );
          });
        });
  }

  void _showDomeSettingsDialog() async {
    final domeState = ref.read(domeStateProvider);
    final originalSlaved = domeState.isSlaved;
    bool slaved = domeState.isSlaved;
    bool isSaving = false;
    // Capture the State's context up front: the Save handler is async and
    // snackbars must not use the dialog's (popped) context after the await.
    final pageContext = context;

    await _showEquipmentDialog(
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (slaved == originalSlaved) {
                            Navigator.pop(context);
                            return;
                          }
                          final deviceId = domeState.deviceId;
                          if (deviceId == null || deviceId.isEmpty) {
                            context.showErrorSnackBar('Dome is not connected');
                            return;
                          }
                          setState(() => isSaving = true);
                          try {
                            await ref
                                .read(backendProvider)
                                .domeSetSlaved(deviceId, slaved);
                            ref
                                .read(domeStateProvider.notifier)
                                .setSlaved(slaved);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                slaved
                                    ? 'Dome slaved to mount'
                                    : 'Dome unslaved',
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() => isSaving = false);
                            context.showErrorSnackBar(
                              'Dome slave failed: $e',
                            );
                          }
                        },
                  label: isSaving ? 'Saving...' : 'Save',
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
                        onChanged: isSaving
                            ? null
                            : (val) => setState(() => slaved = val),
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
    final deviceId = state.deviceId;
    if (deviceId == null ||
        state.connectionState != DeviceConnectionState.connected) {
      if (mounted) {
        context.showErrorSnackBar('Calibrator is not connected');
      }
      return;
    }
    CoverCalibratorCapabilitySnapshot? capabilities;
    try {
      capabilities = await ref.read(
        equipmentCoverCalibratorCapabilitiesProvider(deviceId).future,
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not read calibrator capabilities: $e');
      }
      return;
    }
    if (!mounted ||
        ref.read(coverCalibratorStateProvider).deviceId != deviceId) {
      return;
    }
    if (capabilities == null ||
        !capabilities.calibratorPresent ||
        capabilities.maxBrightness <= 0) {
      context.showErrorSnackBar(
        'This device does not report a controllable calibrator light.',
      );
      return;
    }
    final maxBrightness = capabilities.maxBrightness;
    final currentBrightness = capabilities.brightness ?? 0;
    var brightnessText = (currentBrightness > 0
            ? currentBrightness
            : (maxBrightness / 2).round().clamp(1, maxBrightness))
        .toString();
    final pageContext = context;
    bool isSaving = false;
    String? errorText;

    await _showEquipmentDialog(
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (isSaving) return;
                          final target = int.tryParse(brightnessText.trim());
                          if (target == null) {
                            setState(() => errorText =
                                'Brightness must be a whole number.');
                            return;
                          }
                          if (target < 0 || target > maxBrightness) {
                            setState(() =>
                                errorText = 'Brightness must be between 0 and '
                                    '$maxBrightness.');
                            return;
                          }
                          setState(() {
                            errorText = null;
                            isSaving = true;
                          });
                          try {
                            // Awaited here so the dialog stays open and busy
                            // until the driver confirms; only then does it
                            // close. A failure keeps the typed value on screen
                            // and re-enables Save for a retry.
                            await _applyCalibratorBrightness(target);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (pageContext.mounted) {
                              pageContext.showSuccessSnackBar(
                                  'Calibrator brightness updated to $target');
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() {
                              isSaving = false;
                              errorText = 'Failed to set brightness: $e';
                            });
                          }
                        },
                  label: isSaving ? 'Saving...' : 'Save',
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
                  TextFormField(
                    initialValue: brightnessText,
                    onChanged: (value) => brightnessText = value,
                    enabled: !isSaving,
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
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                          color: colors.error,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ],
                ],
              ),
            );
          });
        });
  }

  /// Apply a calibrator brightness to the hardware and mirror it into state.
  ///
  /// Throws on any failure (missing device id or a backend error) so the
  /// caller — the awaited calibrator dialog — can keep the dialog open, show
  /// the failure inline, and offer a retry. It deliberately shows NO snackbar
  /// of its own: the dialog owns the single success/failure surface, avoiding
  /// the double-snackbar the old fire-and-forget handler produced.
  Future<void> _applyCalibratorBrightness(int brightness) async {
    final deviceId = ref.read(coverCalibratorStateProvider).deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Calibrator is not connected');
    }
    final capabilities = await ref.read(
      equipmentCoverCalibratorCapabilitiesProvider(deviceId).future,
    );
    if (capabilities == null || !capabilities.calibratorPresent) {
      throw StateError('This device has no controllable calibrator light');
    }
    if (brightness < 0 || brightness > capabilities.maxBrightness) {
      throw RangeError.range(
        brightness,
        0,
        capabilities.maxBrightness,
        'brightness',
      );
    }
    final backend = ref.read(backendProvider);
    await backend.calibratorOn(deviceId, brightness);
    if (!mounted ||
        !identical(ref.read(backendProvider), backend) ||
        ref.read(coverCalibratorStateProvider).deviceId != deviceId) {
      return;
    }
    final notifier = ref.read(coverCalibratorStateProvider.notifier);
    notifier.updateBrightness(brightness);
    notifier.updateCalibratorStatus(CalibratorStatus.notReady);
    ref.invalidate(equipmentCoverCalibratorCapabilitiesProvider(deviceId));
  }
}
