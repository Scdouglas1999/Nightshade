import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/focuser_controls.dart';
import '../widgets/focus_model_panel.dart';

class FocusTab extends ConsumerStatefulWidget {
  const FocusTab({super.key});

  @override
  ConsumerState<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends ConsumerState<FocusTab> {
  // UI-only local state (transient, doesn't need to persist)
  bool _isRunningAf = false;
  String? _afStatus;
  double? _pendingSliderPosition;
  final TextEditingController _goToPositionController = TextEditingController();

  @override
  void dispose() {
    _goToPositionController.dispose();
    super.dispose();
  }

  Future<void> _moveTo(int position) async {
    try {
      await ref.read(deviceServiceProvider).moveFocuserTo(position);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to move to position: $e');
    }
  }

  Future<void> _runAutofocus() async {
    setState(() {
      _isRunningAf = true;
      _afStatus = 'Running...';
    });

    // Notify session state and overlay that AF is starting
    ref.read(sessionStateProvider.notifier).setAutofocusing(true);
    ref.read(autofocusOverlayProvider.notifier).onAutofocusStarted();

    try {
      final settings = ref.read(focusSettingsProvider);
      final result = await ref.read(deviceServiceProvider).runAutofocus(
            exposureTime: settings.exposureTime,
            stepSize: settings.afStepSize,
            stepsOut: settings.stepsOut,
            method: settings.method,
            binning: 1,
          );

      // Store result in provider for display
      ref.read(autofocusResultProvider.notifier).state = result;

      // Notify overlay of completion
      ref.read(autofocusOverlayProvider.notifier).onAutofocusCompleted(result);

      if (mounted) {
        setState(() {
          _afStatus = 'Complete. HFR: ${result.bestHfr.toStringAsFixed(2)}';
        });
        context.showSuccessSnackBar(
            'Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}');
      }
    } catch (e) {
      // Notify overlay of failure
      ref.read(autofocusOverlayProvider.notifier).onAutofocusFailed('$e');

      if (mounted) {
        setState(() {
          _afStatus = 'Failed';
        });
        context.showErrorSnackBar('Autofocus failed: $e');
      }
    } finally {
      ref.read(sessionStateProvider.notifier).setAutofocusing(false);
      if (mounted) {
        setState(() {
          _isRunningAf = false;
        });
      }
    }
  }

  void _showAutofocusDetails(BuildContext context, dynamic afResult) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final focusData = afResult.focusData as List;
    final settings = ref.read(focusSettingsProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(LucideIcons.focus, color: colors.accent),
            const SizedBox(width: 8),
            Text('Autofocus Results',
                style: TextStyle(color: colors.textPrimary)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                    'Best Position', '${afResult.bestPosition} steps', colors),
                _buildDetailRow('Best HFR',
                    '${afResult.bestHfr.toStringAsFixed(3)} px', colors),
                _buildDetailRow('Data Points', '${focusData.length}', colors),
                _buildDetailRow('Method', settings.method, colors),
                _buildDetailRow(
                    'Step Size', '${settings.afStepSize} steps', colors),
                const SizedBox(height: 16),
                Text('Focus Curve Data',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: focusData.length,
                    itemBuilder: (context, index) {
                      final point = focusData[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pos: ${point.position}',
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 12)),
                            Text('HFR: ${point.hfr.toStringAsFixed(3)}',
                                style: TextStyle(
                                    color: colors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textMuted)),
          Text(value,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _showMeasureOffsetsDialog() async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final filterWheelState = ref.read(filterWheelStateProvider);
    final filterOffsetState = ref.read(filterOffsetProvider);

    // Check if filter wheel is connected
    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      context.showWarningSnackBar(
          'Filter wheel must be connected to measure offsets.');
      return;
    }

    // Check if focuser is connected
    final focuserState = ref.read(focuserStateProvider);
    if (focuserState.connectionState != DeviceConnectionState.connected) {
      context
          .showWarningSnackBar('Focuser must be connected to measure offsets.');
      return;
    }

    final filters = filterWheelState.filterNames;
    if (filters.isEmpty) {
      context.showWarningSnackBar('No filters available in filter wheel.');
      return;
    }

    // Determine reference filter - use existing or default to first filter
    final referenceFilter = filterOffsetState.referenceFilter ?? filters.first;

    // Show the measurement dialog
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _FilterOffsetMeasurementDialog(
        colors: colors,
        filters: filters,
        referenceFilter: referenceFilter,
        deviceService: ref.read(deviceServiceProvider),
        backend: ref.read(backendProvider),
        filterWheelDeviceId: filterWheelState.deviceId!,
        focusSettings: ref.read(focusSettingsProvider),
        onComplete: (Map<String, int> offsets) async {
          // Save all measured offsets
          final notifier = ref.read(filterOffsetProvider.notifier);

          // Set reference filter if not already set
          if (filterOffsetState.referenceFilter == null) {
            await notifier.setReferenceFilter(referenceFilter);
          }

          // Save each offset
          for (final entry in offsets.entries) {
            await notifier.setFilterOffset(entry.key, entry.value);
          }

          if (!mounted) return;
          context.showSuccessSnackBar(
              'Filter offsets measured and saved for ${offsets.length} filters.');
        },
      ),
    );
  }

  /// Build a simple focus curve visualization using CustomPaint
  Widget _buildFocusCurve(dynamic afResult, NightshadeColors colors) {
    final focusData = afResult.focusData as List;
    if (focusData.isEmpty) {
      return Center(
        child: Text('No data', style: TextStyle(color: colors.textMuted)),
      );
    }

    return CustomPaint(
      painter: _FocusCurvePainter(
        focusData: focusData,
        bestPosition: afResult.bestPosition as int,
        accentColor: colors.accent,
        gridColor: colors.border,
        textColor: colors.textMuted,
      ),
      size: Size.infinite,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final focuserState = ref.watch(focuserStateProvider);
    // Watch focus settings from provider (persists across navigation)
    final focusSettings = ref.watch(focusSettingsProvider);
    final isConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final position = focuserState.position ?? 0;
    final maxPosition =
        (focuserState.maxPosition != null && focuserState.maxPosition! > 0)
            ? focuserState.maxPosition!
            : 50000;
    final temperature = focuserState.temperature;
    final temperatureText =
        temperature != null ? '${temperature.toStringAsFixed(1)}°C' : '---';
    final isMoving = focuserState.isMoving;
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        children: [
          // Focuser control bar
          NightshadeCard(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Focuser Control',
                    style: TextStyle(
                      fontSize: isMobile ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                  // Position and temperature - wrap on mobile
                  isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Position: ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                AnimatedValue(
                                  value: '$position',
                                  style: ValueAnimationStyle.flash,
                                  textStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                if (isMoving)
                                  Text(
                                    'MOVING',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colors.warning,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Temperature: ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                AnimatedValue(
                                  value: temperatureText,
                                  style: ValueAnimationStyle.directional,
                                  textStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Text(
                              'Position: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            AnimatedValue(
                              value: '$position',
                              style: ValueAnimationStyle.flash,
                              textStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              'Temperature: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            AnimatedValue(
                              value: temperatureText,
                              style: ValueAnimationStyle.directional,
                              textStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (isMoving)
                              Text(
                                'MOVING',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colors.warning,
                                ),
                              ),
                          ],
                        ),
                  const SizedBox(height: 12),
                  // Movement buttons - using shared FocuserControls widget
                  const FocuserControls(
                    compact: true,
                    showAutofocus: false,
                  ),
                  const SizedBox(height: 12),
                  // Position slider
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colors.primary,
                      inactiveTrackColor: colors.surfaceAlt,
                      thumbColor: colors.primary,
                    ),
                    child: Slider(
                      value: (_pendingSliderPosition ?? position.toDouble())
                          .clamp(0.0, maxPosition.toDouble()),
                      min: 0,
                      max: maxPosition.toDouble(),
                      onChanged: isConnected
                          ? (value) {
                              setState(() {
                                _pendingSliderPosition = value;
                              });
                            }
                          : null,
                      onChangeEnd: isConnected
                          ? (value) async {
                              await _moveTo(value.toInt());
                              if (!mounted) return;
                              setState(() {
                                _pendingSliderPosition = null;
                              });
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Go To Position input and Step size chips row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Go To Position
                      SizedBox(
                        width: isMobile ? 140 : 180,
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _goToPositionController,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Position',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: colors.textMuted,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide:
                                          BorderSide(color: colors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide:
                                          BorderSide(color: colors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide:
                                          BorderSide(color: colors.primary),
                                    ),
                                    filled: true,
                                    fillColor: colors.surfaceAlt,
                                  ),
                                  onSubmitted: isConnected
                                      ? (value) {
                                          final pos = int.tryParse(value);
                                          if (pos != null) {
                                            _moveTo(pos);
                                            _goToPositionController.clear();
                                          }
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              height: 32,
                              child: NightshadeButton(
                                label: 'Go',
                                size: ButtonSize.small,
                                variant: ButtonVariant.outline,
                                onPressed: isConnected
                                    ? () {
                                        final pos = int.tryParse(
                                            _goToPositionController.text);
                                        if (pos != null) {
                                          _moveTo(pos);
                                          _goToPositionController.clear();
                                        }
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Step size chips
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Step Size:',
                              style: TextStyle(
                                  fontSize: 12, color: colors.textSecondary),
                            ),
                            _StepChip(
                              label: '10',
                              isSelected: focusSettings.stepSize == 10,
                              onTap: () => ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(focusSettings.copyWith(stepSize: 10)),
                            ),
                            _StepChip(
                              label: '100',
                              isSelected: focusSettings.stepSize == 100,
                              onTap: () => ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(focusSettings.copyWith(stepSize: 100)),
                            ),
                            _StepChip(
                              label: '1000',
                              isSelected: focusSettings.stepSize == 1000,
                              onTap: () => ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(
                                    focusSettings.copyWith(stepSize: 1000),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: isMobile ? 16 : 24),

          // Autofocus and graph - responsive layout
          isMobile
              ? _buildMobileAutofocusSection(colors, focusSettings, isConnected)
              : _buildDesktopAutofocusSection(
                  colors, focusSettings, isConnected),

          SizedBox(height: isMobile ? 16 : 24),

          // Temperature compensation model
          const FocusModelPanel(),

          SizedBox(height: isMobile ? 16 : 24),

          // Filter offsets
          _buildFilterOffsetsSection(colors),
        ],
      ),
    );
  }

  /// Builds autofocus section for mobile (stacked vertically)
  Widget _buildMobileAutofocusSection(
    NightshadeColors colors,
    FocusSettings focusSettings,
    bool isConnected,
  ) {
    return Column(
      children: [
        // Autofocus settings card
        NightshadeCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autofocus',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _MobileSettingRow(
                  label: 'Method',
                  child: NightshadeDropdown(
                    value: focusSettings.method,
                    items: const ['V-Curve', 'Hyperbolic', 'Parabolic'],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(focusSettingsProvider.notifier)
                            .update(focusSettings.copyWith(method: value));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MobileSettingRow(
                        label: 'Exposure',
                        child: NightshadeTextField(
                          initialValue: focusSettings.exposureTime.toString(),
                          suffix: 's',
                          onChanged: (value) {
                            final v = double.tryParse(value);
                            if (v != null) {
                              ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(
                                      focusSettings.copyWith(exposureTime: v));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MobileSettingRow(
                        label: 'Step Size',
                        child: NightshadeTextField(
                          initialValue: focusSettings.afStepSize.toString(),
                          onChanged: (value) {
                            final v = int.tryParse(value);
                            if (v != null) {
                              ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(
                                      focusSettings.copyWith(afStepSize: v));
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MobileSettingRow(
                        label: 'Steps Out',
                        child: NightshadeTextField(
                          initialValue: focusSettings.stepsOut.toString(),
                          onChanged: (value) {
                            final v = int.tryParse(value);
                            if (v != null) {
                              ref
                                  .read(focusSettingsProvider.notifier)
                                  .update(
                                      focusSettings.copyWith(stepsOut: v));
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_afStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _afStatus!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _afStatus!.contains('Failed')
                            ? colors.error
                            : colors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: NightshadeButton(
                    label: _isRunningAf ? 'Running...' : 'Run Autofocus',
                    icon: _isRunningAf ? LucideIcons.loader : LucideIcons.play,
                    onPressed:
                        (isConnected && !_isRunningAf) ? _runAutofocus : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Last autofocus run card
        NightshadeCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Builder(
              builder: (context) {
                final afResult = ref.watch(autofocusResultProvider);
                final hasResult = afResult != null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Autofocus Run',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: hasResult && afResult.focusData.isNotEmpty
                          ? _buildFocusCurve(afResult, colors)
                          : Center(
                              child: Text(
                                hasResult
                                    ? 'No curve data'
                                    : 'No autofocus run yet',
                                style: TextStyle(
                                    fontSize: 10, color: colors.textMuted),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _InfoRow(
                                label: 'Best Position',
                                value: hasResult
                                    ? afResult.bestPosition.toString()
                                    : '---',
                              ),
                              _InfoRow(
                                label: 'Best HFR',
                                value: hasResult
                                    ? afResult.bestHfr.toStringAsFixed(2)
                                    : '---',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _InfoRow(
                                label: 'Method',
                                value: hasResult ? afResult.method : '---',
                              ),
                              _InfoRow(
                                label: 'Data Points',
                                value: hasResult
                                    ? afResult.focusData.length.toString()
                                    : '---',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    NightshadeButton(
                      label: 'View Details',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: hasResult
                          ? () => _showAutofocusDetails(context, afResult)
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Builds autofocus section for desktop (side-by-side)
  Widget _buildDesktopAutofocusSection(
    NightshadeColors colors,
    FocusSettings focusSettings,
    bool isConnected,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Autofocus settings
        Expanded(
          child: NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Autofocus',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingRow(
                    label: 'Method',
                    child: NightshadeDropdown(
                      value: focusSettings.method,
                      items: const ['V-Curve', 'Hyperbolic', 'Parabolic'],
                      onChanged: (value) {
                        if (value != null) {
                          ref
                              .read(focusSettingsProvider.notifier)
                              .update(focusSettings.copyWith(method: value));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingRow(
                    label: 'Exposure Time',
                    child: NightshadeTextField(
                      initialValue: focusSettings.exposureTime.toString(),
                      suffix: 's',
                      onChanged: (value) {
                        final v = double.tryParse(value);
                        if (v != null) {
                          ref
                              .read(focusSettingsProvider.notifier)
                              .update(
                                  focusSettings.copyWith(exposureTime: v));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingRow(
                    label: 'Step Size',
                    child: NightshadeTextField(
                      initialValue: focusSettings.afStepSize.toString(),
                      suffix: 'steps',
                      onChanged: (value) {
                        final v = int.tryParse(value);
                        if (v != null) {
                          ref
                              .read(focusSettingsProvider.notifier)
                              .update(focusSettings.copyWith(afStepSize: v));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingRow(
                    label: 'Steps Out',
                    child: NightshadeTextField(
                      initialValue: focusSettings.stepsOut.toString(),
                      onChanged: (value) {
                        final v = int.tryParse(value);
                        if (v != null) {
                          ref
                              .read(focusSettingsProvider.notifier)
                              .update(focusSettings.copyWith(stepsOut: v));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_afStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _afStatus!,
                        style: TextStyle(
                          color: _afStatus!.contains('Failed')
                              ? colors.error
                              : colors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      label: _isRunningAf ? 'Running...' : 'Run Autofocus',
                      icon:
                          _isRunningAf ? LucideIcons.loader : LucideIcons.play,
                      size: ButtonSize.large,
                      onPressed:
                          (isConnected && !_isRunningAf) ? _runAutofocus : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 24),

        // Last autofocus run
        Expanded(
          child: NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  final afResult = ref.watch(autofocusResultProvider);
                  final hasResult = afResult != null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Autofocus Run',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: hasResult && afResult.focusData.isNotEmpty
                            ? _buildFocusCurve(afResult, colors)
                            : Center(
                                child: Text(
                                  hasResult
                                      ? 'No curve data'
                                      : 'No autofocus run yet',
                                  style: TextStyle(
                                      fontSize: 10, color: colors.textMuted),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        label: 'Best Position',
                        value: hasResult
                            ? afResult.bestPosition.toString()
                            : '---',
                      ),
                      _InfoRow(
                        label: 'Best HFR',
                        value: hasResult
                            ? afResult.bestHfr.toStringAsFixed(2)
                            : '---',
                      ),
                      _InfoRow(
                        label: 'Temp at Focus',
                        value: hasResult && afResult.temperature != null
                            ? '${afResult.temperature!.toStringAsFixed(1)}°C'
                            : '---',
                      ),
                      _InfoRow(
                        label: 'Method',
                        value: hasResult ? afResult.method : '---',
                      ),
                      _InfoRow(
                        label: 'Data Points',
                        value: hasResult
                            ? afResult.focusData.length.toString()
                            : '---',
                      ),
                      const SizedBox(height: 12),
                      NightshadeButton(
                        label: 'View Details',
                        variant: ButtonVariant.outline,
                        size: ButtonSize.small,
                        onPressed: hasResult
                            ? () => _showAutofocusDetails(context, afResult)
                            : null,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the filter offsets section (shared between mobile and desktop)
  Widget _buildFilterOffsetsSection(NightshadeColors colors) {
    final isMobile = Responsive.isMobile(context);
    final filterOffsetState = ref.watch(filterOffsetProvider);
    final availableFilters = ref.watch(availableFiltersProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final isFilterWheelConnected =
        filterWheelState.connectionState == DeviceConnectionState.connected;

    return NightshadeCard(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - responsive layout
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filter Offsets',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (filterOffsetState.referenceFilter != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Reference: ${filterOffsetState.referenceFilter}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: NightshadeButton(
                              label: 'Clear All',
                              size: ButtonSize.small,
                              variant: ButtonVariant.outline,
                              onPressed: isFilterWheelConnected
                                  ? () async {
                                      await ref
                                          .read(filterOffsetProvider.notifier)
                                          .clearAllOffsets();
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: NightshadeButton(
                              label: 'Measure',
                              size: ButtonSize.small,
                              variant: ButtonVariant.outline,
                              onPressed: isFilterWheelConnected
                                  ? _showMeasureOffsetsDialog
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Offsets',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          if (filterOffsetState.referenceFilter != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'Reference: ${filterOffsetState.referenceFilter}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          NightshadeButton(
                            label: 'Clear All',
                            size: ButtonSize.small,
                            variant: ButtonVariant.outline,
                            onPressed: isFilterWheelConnected
                                ? () async {
                                    await ref
                                        .read(filterOffsetProvider.notifier)
                                        .clearAllOffsets();
                                  }
                                : null,
                          ),
                          const SizedBox(width: 8),
                          NightshadeButton(
                            label: 'Measure Offsets',
                            size: ButtonSize.small,
                            variant: ButtonVariant.outline,
                            onPressed: isFilterWheelConnected
                                ? _showMeasureOffsetsDialog
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 16),
            if (!isFilterWheelConnected)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Connect a filter wheel to manage filter offsets',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (availableFilters.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No filters detected',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ),
              )
            else
              Wrap(
                spacing: isMobile ? 8 : 12,
                runSpacing: isMobile ? 8 : 12,
                children: availableFilters.map((filterName) {
                  final offset = filterOffsetState.offsets[filterName] ?? 0;
                  final isReference =
                      filterName == filterOffsetState.referenceFilter;

                  return _FilterOffsetControl(
                    name: filterName,
                    offset: offset,
                    isReference: isReference,
                    onIncrease: () async {
                      await ref
                          .read(filterOffsetProvider.notifier)
                          .adjustFilterOffset(filterName, 10);
                    },
                    onDecrease: () async {
                      await ref
                          .read(filterOffsetProvider.notifier)
                          .adjustFilterOffset(filterName, -10);
                    },
                    onSetReference: () async {
                      await ref
                          .read(filterOffsetProvider.notifier)
                          .setReferenceFilter(filterName);
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StepChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Compact setting row for mobile layouts (label above, widget below)
class _MobileSettingRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _MobileSettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterOffsetControl extends StatelessWidget {
  final String name;
  final int offset;
  final bool isReference;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onSetReference;

  const _FilterOffsetControl({
    required this.name,
    required this.offset,
    required this.isReference,
    required this.onIncrease,
    required this.onDecrease,
    required this.onSetReference,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final offsetText =
        offset == 0 ? '0' : (offset > 0 ? '+$offset' : '$offset');

    return Container(
      width: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReference
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isReference ? colors.primary : colors.border,
          width: isReference ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isReference ? colors.primary : colors.textPrimary,
                ),
              ),
              if (isReference)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'REF',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: colors.surface,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: onSetReference,
                  child: Icon(
                    LucideIcons.star,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            offsetText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isReference ? colors.primary : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallButton(
                icon: LucideIcons.minus,
                onPressed: isReference ? null : onDecrease,
                colors: colors,
              ),
              const SizedBox(width: 8),
              _SmallButton(
                icon: LucideIcons.plus,
                onPressed: isReference ? null : onIncrease,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final NightshadeColors colors;

  const _SmallButton({
    required this.icon,
    required this.onPressed,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Use minimum 36x36 touch target for better accessibility
    return Material(
      color: onPressed != null ? colors.surface : colors.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null ? colors.textSecondary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// CustomPainter for rendering the autofocus V-curve
class _FocusCurvePainter extends CustomPainter {
  final List focusData;
  final int bestPosition;
  final Color accentColor;
  final Color gridColor;
  final Color textColor;

  _FocusCurvePainter({
    required this.focusData,
    required this.bestPosition,
    required this.accentColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (focusData.isEmpty) return;

    const padding = EdgeInsets.fromLTRB(40, 10, 10, 25);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    // Extract data points
    final points = focusData.map((p) {
      return (position: p.position as int, hfr: p.hfr as double);
    }).toList();

    // Find min/max for scaling
    final minPos =
        points.map((p) => p.position).reduce((a, b) => a < b ? a : b);
    final maxPos =
        points.map((p) => p.position).reduce((a, b) => a > b ? a : b);
    final minHfr = points.map((p) => p.hfr).reduce((a, b) => a < b ? a : b);
    final maxHfr = points.map((p) => p.hfr).reduce((a, b) => a > b ? a : b);

    // Add some padding to the HFR range
    final hfrPadding = (maxHfr - minHfr) * 0.1;
    final displayMinHfr = (minHfr - hfrPadding).clamp(0, double.infinity);
    final displayMaxHfr = maxHfr + hfrPadding;

    // Guard against zero ranges (all values equal)
    final posRange = (maxPos - minPos).toDouble();
    final hfrRange = displayMaxHfr - displayMinHfr;
    if (posRange == 0 || hfrRange == 0) {
      // Draw a single point in the center when all values are identical
      final centerX = chartArea.center.dx;
      final centerY = chartArea.center.dy;
      final pointPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), 5, pointPaint);
      return;
    }

    // Draw grid
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Horizontal grid lines
    for (var i = 0; i <= 4; i++) {
      final y = chartArea.top + (chartArea.height * i / 4);
      canvas.drawLine(
        Offset(chartArea.left, y),
        Offset(chartArea.right, y),
        gridPaint,
      );
    }

    // Draw the curve
    if (points.length > 1) {
      final linePaint = Paint()
        ..color = accentColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        final x = chartArea.left +
            (p.position - minPos) / posRange * chartArea.width;
        final y = chartArea.bottom -
            (p.hfr - displayMinHfr) /
                hfrRange *
                chartArea.height;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Draw data points
    final pointPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    for (final p in points) {
      final x = chartArea.left +
          (p.position - minPos) / posRange * chartArea.width;
      final y = chartArea.bottom -
          (p.hfr - displayMinHfr) /
              hfrRange *
              chartArea.height;

      final isMinimum = p.position == bestPosition;
      canvas.drawCircle(Offset(x, y), isMinimum ? 5 : 3, pointPaint);

      // Draw larger ring around minimum point
      if (isMinimum) {
        final ringPaint = Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(x, y), 8, ringPaint);
      }
    }

    // Draw axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Y-axis label (HFR)
    textPainter.text = TextSpan(
      text: 'HFR',
      style: TextStyle(color: textColor, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, chartArea.top));

    // X-axis label (Position)
    textPainter.text = TextSpan(
      text: 'Position',
      style: TextStyle(color: textColor, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(chartArea.center.dx - textPainter.width / 2, size.height - 12),
    );
  }

  @override
  bool shouldRepaint(covariant _FocusCurvePainter oldDelegate) {
    return focusData != oldDelegate.focusData ||
        bestPosition != oldDelegate.bestPosition;
  }
}

/// Dialog for automated filter offset measurement
class _FilterOffsetMeasurementDialog extends StatefulWidget {
  final NightshadeColors colors;
  final List<String> filters;
  final String referenceFilter;
  final DeviceService deviceService;
  final NightshadeBackend backend;
  final String filterWheelDeviceId;
  final FocusSettings focusSettings;
  final void Function(Map<String, int> offsets) onComplete;

  const _FilterOffsetMeasurementDialog({
    required this.colors,
    required this.filters,
    required this.referenceFilter,
    required this.deviceService,
    required this.backend,
    required this.filterWheelDeviceId,
    required this.focusSettings,
    required this.onComplete,
  });

  @override
  State<_FilterOffsetMeasurementDialog> createState() =>
      _FilterOffsetMeasurementDialogState();
}

class _FilterOffsetMeasurementDialogState
    extends State<_FilterOffsetMeasurementDialog> {
  bool _isRunning = false;
  bool _isCancelled = false;
  String _status = 'Ready to measure';
  String? _currentFilter;
  int _completedFilters = 0;
  int? _referencePosition;
  final Map<String, int> _measuredOffsets = {};
  final Map<String, int> _measuredPositions = {};
  /// Per-filter individual run results for multi-iteration averaging
  final Map<String, List<int>> _perFilterRunPositions = {};
  String? _errorMessage;
  /// Number of AF runs per filter (for averaging accuracy)
  int _iterationsPerFilter = 3;

  /// Run autofocus N times for a given filter and return the averaged best position.
  Future<int> _runAveragedAutofocus(String filterLabel) async {
    final positions = <int>[];

    for (var iter = 1; iter <= _iterationsPerFilter; iter++) {
      if (_isCancelled || !mounted) {
        throw Exception('Cancelled');
      }

      if (mounted) {
        setState(() {
          _status = '$filterLabel: AF run $iter/$_iterationsPerFilter';
        });
      }

      final result = await widget.deviceService.runAutofocus(
        exposureTime: widget.focusSettings.exposureTime,
        stepSize: widget.focusSettings.afStepSize,
        stepsOut: widget.focusSettings.stepsOut,
        method: widget.focusSettings.method,
        binning: 1,
      );
      positions.add(result.bestPosition);
    }

    // Store individual run positions for display
    _perFilterRunPositions[filterLabel] = List.unmodifiable(positions);

    // Return the averaged position (rounded to nearest int)
    final sum = positions.reduce((a, b) => a + b);
    return (sum / positions.length).round();
  }

  Future<void> _startMeasurement() async {
    setState(() {
      _isRunning = true;
      _isCancelled = false;
      _status = 'Starting measurement...';
      _measuredOffsets.clear();
      _measuredPositions.clear();
      _perFilterRunPositions.clear();
      _completedFilters = 0;
      _referencePosition = null;
      _errorMessage = null;
    });

    try {
      // First, measure the reference filter
      final refIndex = widget.filters.indexOf(widget.referenceFilter);
      if (refIndex == -1) {
        throw Exception('Reference filter not found');
      }

      if (!mounted) return;
      setState(() {
        _currentFilter = widget.referenceFilter;
        _status = 'Changing to reference filter: ${widget.referenceFilter}';
      });

      // Change to reference filter
      await widget.backend
          .filterWheelSetPosition(widget.filterWheelDeviceId, refIndex);

      // Wait for filter change to complete
      await _waitForFilterChange();

      if (_isCancelled || !mounted) return;

      // Run averaged autofocus on reference filter
      final refAvgPosition =
          await _runAveragedAutofocus(widget.referenceFilter);

      _referencePosition = refAvgPosition;
      _measuredPositions[widget.referenceFilter] = refAvgPosition;
      _measuredOffsets[widget.referenceFilter] = 0; // Reference is always 0

      if (!mounted) return;
      setState(() {
        _completedFilters = 1;
        _status = 'Reference position: $refAvgPosition'
            '${_iterationsPerFilter > 1 ? ' (avg of $_iterationsPerFilter runs)' : ''}';
      });

      if (_isCancelled) return;

      // Measure each other filter
      for (var i = 0; i < widget.filters.length; i++) {
        if (_isCancelled || !mounted) return;

        final filterName = widget.filters[i];
        if (filterName == widget.referenceFilter) continue;

        if (!mounted) return;
        setState(() {
          _currentFilter = filterName;
          _status = 'Changing to filter: $filterName';
        });

        // Change filter
        await widget.backend
            .filterWheelSetPosition(widget.filterWheelDeviceId, i);

        // Wait for filter change
        await _waitForFilterChange();

        if (_isCancelled || !mounted) return;

        // Run averaged autofocus
        final avgPosition = await _runAveragedAutofocus(filterName);

        // Calculate offset from reference
        final offset = avgPosition - _referencePosition!;
        _measuredPositions[filterName] = avgPosition;
        _measuredOffsets[filterName] = offset;

        if (!mounted) return;
        setState(() {
          _completedFilters++;
          _status =
              '$filterName: position $avgPosition (offset: ${offset > 0 ? '+$offset' : offset})';
        });
      }

      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _status = 'Measurement complete!';
      });

      // Call completion callback
      widget.onComplete(_measuredOffsets);
    } catch (e) {
      if (!mounted) return;
      if (_isCancelled) {
        setState(() {
          _isRunning = false;
          _status = 'Cancelled';
        });
      } else {
        setState(() {
          _isRunning = false;
          _errorMessage = e.toString();
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _waitForFilterChange() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (_isCancelled) return;
      try {
        final status = await widget.backend
            .getFilterWheelStatus(widget.filterWheelDeviceId);
        if (!status.moving && status.position >= 0) {
          return;
        }
      } catch (_) {
        // Continue polling through transient read errors.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('Timed out waiting for filter wheel to finish changing.');
  }

  void _cancel() {
    setState(() {
      _isCancelled = true;
      _isRunning = false;
      _status = 'Cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalFilters = widget.filters.length;
    final progress = totalFilters > 0 ? _completedFilters / totalFilters : 0.0;

    return AlertDialog(
      backgroundColor: widget.colors.surface,
      title: Row(
        children: [
          Icon(LucideIcons.focus, color: widget.colors.accent),
          const SizedBox(width: 8),
          Text(
            'Measure Filter Offsets',
            style: TextStyle(color: widget.colors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reference filter info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.border),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.star,
                      size: 16, color: widget.colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Reference Filter: ',
                    style: TextStyle(color: widget.colors.textSecondary),
                  ),
                  Text(
                    widget.referenceFilter,
                    style: TextStyle(
                      color: widget.colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Iterations per filter setting
            if (!_isRunning && _completedFilters == 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.colors.border),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.repeat,
                        size: 16, color: widget.colors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'AF runs per filter: ',
                      style: TextStyle(color: widget.colors.textSecondary),
                    ),
                    const Spacer(),
                    ...([1, 2, 3, 5].map((n) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _iterationsPerFilter = n),
                            child: Container(
                              width: 32,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _iterationsPerFilter == n
                                    ? widget.colors.primary
                                        .withValues(alpha: 0.2)
                                    : widget.colors.surface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _iterationsPerFilter == n
                                      ? widget.colors.primary
                                      : widget.colors.border,
                                ),
                              ),
                              child: Text(
                                '$n',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _iterationsPerFilter == n
                                      ? widget.colors.primary
                                      : widget.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ))),
                  ],
                ),
              ),

            if (!_isRunning && _completedFilters == 0)
              const SizedBox(height: 12),

            // Filters to measure
            Text(
              'Filters to measure:',
              style: TextStyle(
                color: widget.colors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.filters.map((filter) {
                final isReference = filter == widget.referenceFilter;
                final isMeasured = _measuredOffsets.containsKey(filter);
                final isCurrent = filter == _currentFilter && _isRunning;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? widget.colors.primary.withValues(alpha: 0.2)
                        : isReference
                            ? widget.colors.primary.withValues(alpha: 0.1)
                            : widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isCurrent
                          ? widget.colors.primary
                          : isReference
                              ? widget.colors.primary
                              : isMeasured
                                  ? widget.colors.success
                                  : widget.colors.border,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrent)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(widget.colors.primary),
                            ),
                          ),
                        )
                      else if (isMeasured)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            LucideIcons.check,
                            size: 12,
                            color: widget.colors.success,
                          ),
                        ),
                      Text(
                        filter,
                        style: TextStyle(
                          color: isReference
                              ? widget.colors.primary
                              : widget.colors.textPrimary,
                          fontWeight:
                              isReference ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                      if (isMeasured && _measuredOffsets[filter] != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            _measuredOffsets[filter] == 0
                                ? '(ref)'
                                : '(${_measuredOffsets[filter]! > 0 ? '+' : ''}${_measuredOffsets[filter]})',
                            style: TextStyle(
                              color: widget.colors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Progress
            if (_isRunning || _completedFilters > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: widget.colors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(widget.colors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$_completedFilters / $totalFilters',
                    style: TextStyle(
                      color: widget.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorMessage != null
                    ? widget.colors.error.withValues(alpha: 0.1)
                    : widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (_isRunning)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(widget.colors.primary),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _errorMessage != null
                            ? widget.colors.error
                            : widget.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Results table
            if (_measuredPositions.isNotEmpty && !_isRunning) ...[
              const SizedBox(height: 16),
              Text(
                _iterationsPerFilter > 1
                    ? 'Results (averaged from $_iterationsPerFilter runs):'
                    : 'Results:',
                style: TextStyle(
                  color: widget.colors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: widget.colors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _measuredPositions.entries.map((entry) {
                    final offset = _measuredOffsets[entry.key] ?? 0;
                    final isRef = entry.key == widget.referenceFilter;
                    final runPositions =
                        _perFilterRunPositions[entry.key] ?? [];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color:
                                  widget.colors.border.withValues(alpha: 0.5)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        color: isRef
                                            ? widget.colors.primary
                                            : widget.colors.textPrimary,
                                        fontWeight: isRef
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    if (isRef) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: widget.colors.primary,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          'REF',
                                          style: TextStyle(
                                            color: widget.colors.surface,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _iterationsPerFilter > 1
                                      ? 'Avg: ${entry.value}'
                                      : 'Pos: ${entry.value}',
                                  style: TextStyle(
                                    color: widget.colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  isRef
                                      ? '--'
                                      : (offset > 0
                                          ? '+$offset'
                                          : '$offset'),
                                  style: TextStyle(
                                    color: isRef
                                        ? widget.colors.textMuted
                                        : widget.colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          // Show individual run positions if multiple iterations
                          if (_iterationsPerFilter > 1 &&
                              runPositions.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Runs: ${runPositions.join(', ')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.colors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isRunning)
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label:
                _completedFilters == widget.filters.length ? 'Done' : 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        if (_isRunning)
          NightshadeButton(
            onPressed: _cancel,
            label: 'Cancel',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        if (!_isRunning && _completedFilters < widget.filters.length)
          NightshadeButton(
            label: 'Start Measurement',
            onPressed: _startMeasurement,
            variant: ButtonVariant.primary,
          ),
      ],
    );
  }
}
