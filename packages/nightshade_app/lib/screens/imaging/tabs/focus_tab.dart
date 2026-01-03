import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

class FocusTab extends ConsumerStatefulWidget {
  const FocusTab({super.key});

  @override
  ConsumerState<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends ConsumerState<FocusTab> {
  // UI-only local state (transient, doesn't need to persist)
  bool _isRunningAf = false;
  String? _afStatus;

  Future<void> _moveIn(int steps) async {
    try {
      await ref.read(deviceServiceProvider).moveFocuserRelative(-steps);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move in: $e')),
        );
      }
    }
  }

  Future<void> _moveOut(int steps) async {
    try {
      await ref.read(deviceServiceProvider).moveFocuserRelative(steps);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move out: $e')),
        );
      }
    }
  }

  Future<void> _moveTo(int position) async {
    try {
      await ref.read(deviceServiceProvider).moveFocuserTo(position);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move to position: $e')),
        );
      }
    }
  }

  Future<void> _haltFocuser() async {
    try {
      // DeviceService doesn't have a convenience haltFocuser method,
      // so we'll move to current position to stop
      final focuserState = ref.read(focuserStateProvider);
      if (focuserState.position != null) {
        await ref.read(deviceServiceProvider).moveFocuserTo(focuserState.position!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to halt: $e')),
        );
      }
    }
  }

  Future<void> _runAutofocus() async {
    setState(() {
      _isRunningAf = true;
      _afStatus = 'Running...';
    });

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

      if (mounted) {
        setState(() {
          _afStatus = 'Complete. HFR: ${result.bestHfr.toStringAsFixed(2)}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _afStatus = 'Failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Autofocus failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
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
            Text('Autofocus Results', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Best Position', '${afResult.bestPosition} steps', colors),
                _buildDetailRow('Best HFR', '${afResult.bestHfr.toStringAsFixed(3)} px', colors),
                _buildDetailRow('Data Points', '${focusData.length}', colors),
                _buildDetailRow('Method', settings.method, colors),
                _buildDetailRow('Step Size', '${settings.afStepSize} steps', colors),
                const SizedBox(height: 16),
                Text('Focus Curve Data', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pos: ${point.position}', style: TextStyle(color: colors.textMuted, fontSize: 12)),
                            Text('HFR: ${point.hfr.toStringAsFixed(3)}', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: colors.accent)),
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
          Text(value, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _showMeasureOffsetsDialog(BuildContext context) async {
    // TODO: Implement automated filter offset measurement
    // This would:
    // 1. Run autofocus on reference filter
    // 2. For each filter, change filter and run autofocus
    // 3. Calculate offset from reference filter
    // 4. Save offsets automatically

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Automated filter offset measurement coming soon! Use +/- buttons to set offsets manually.'),
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
    final isConnected = focuserState.connectionState == DeviceConnectionState.connected;
    final position = focuserState.position ?? 0;
    final maxPosition = (focuserState.maxPosition != null && focuserState.maxPosition! > 0)
        ? focuserState.maxPosition!
        : 50000;
    final temperature = focuserState.temperature ?? 0.0;
    final isMoving = focuserState.isMoving;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Focuser control bar
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Focuser Control',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Position: $position',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        'Temperature: ${temperature.toStringAsFixed(1)}°C',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
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
                  Row(
                    children: [
                      _FocusButton(
                        icon: LucideIcons.chevronsLeft,
                        onPressed: isConnected ? () => _moveIn(focusSettings.stepSize * 10) : null,
                      ),
                      const SizedBox(width: 4),
                      _FocusButton(
                        icon: LucideIcons.chevronLeft,
                        onPressed: isConnected ? () => _moveIn(focusSettings.stepSize) : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: colors.primary,
                            inactiveTrackColor: colors.surfaceAlt,
                            thumbColor: colors.primary,
                          ),
                          child: Slider(
                            value: position.toDouble().clamp(0.0, maxPosition.toDouble()),
                            min: 0,
                            max: maxPosition.toDouble(),
                            onChanged: isConnected ? (value) => _moveTo(value.toInt()) : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FocusButton(
                        icon: LucideIcons.chevronRight,
                        onPressed: isConnected ? () => _moveOut(focusSettings.stepSize) : null,
                      ),
                      const SizedBox(width: 4),
                      _FocusButton(
                        icon: LucideIcons.chevronsRight,
                        onPressed: isConnected ? () => _moveOut(focusSettings.stepSize * 10) : null,
                      ),
                      const SizedBox(width: 8),
                      _FocusButton(
                        icon: LucideIcons.octagon, 
                        color: colors.error,
                        onPressed: isConnected ? _haltFocuser : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Step Size:',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      _StepChip(
                        label: '10',
                        isSelected: focusSettings.stepSize == 10,
                        onTap: () => ref.read(focusSettingsProvider.notifier).state =
                            focusSettings.copyWith(stepSize: 10),
                      ),
                      const SizedBox(width: 8),
                      _StepChip(
                        label: '100',
                        isSelected: focusSettings.stepSize == 100,
                        onTap: () => ref.read(focusSettingsProvider.notifier).state =
                            focusSettings.copyWith(stepSize: 100),
                      ),
                      const SizedBox(width: 8),
                      _StepChip(
                        label: '1000',
                        isSelected: focusSettings.stepSize == 1000,
                        onTap: () => ref.read(focusSettingsProvider.notifier).state =
                            focusSettings.copyWith(stepSize: 1000),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Autofocus and graph row
          Row(
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
                                ref.read(focusSettingsProvider.notifier).state =
                                    focusSettings.copyWith(method: value);
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
                                ref.read(focusSettingsProvider.notifier).state =
                                    focusSettings.copyWith(exposureTime: v);
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
                                ref.read(focusSettingsProvider.notifier).state =
                                    focusSettings.copyWith(afStepSize: v);
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
                                ref.read(focusSettingsProvider.notifier).state =
                                    focusSettings.copyWith(stepsOut: v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SettingRow(
                          label: 'Exposures/Point',
                          child: NightshadeTextField(
                            initialValue: focusSettings.exposuresPerPoint.toString(),
                            onChanged: (value) {
                              final v = int.tryParse(value);
                              if (v != null) {
                                ref.read(focusSettingsProvider.notifier).state =
                                    focusSettings.copyWith(exposuresPerPoint: v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            NightshadeCheckbox(value: true, onChanged: (v) {}),
                            const SizedBox(width: 8),
                            Text(
                              'Use filter offsets',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            NightshadeCheckbox(value: true, onChanged: (v) {}),
                            const SizedBox(width: 8),
                            Text(
                              'Auto-select star',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_afStatus != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _afStatus!,
                              style: TextStyle(
                                color: _afStatus!.contains('Failed') ? colors.error : colors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: NightshadeButton(
                            label: _isRunningAf ? 'Running...' : 'Run Autofocus',
                            icon: _isRunningAf ? LucideIcons.loader : LucideIcons.play,
                            size: ButtonSize.large,
                            onPressed: (isConnected && !_isRunningAf) ? _runAutofocus : null,
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
                                        hasResult ? 'No curve data' : 'No autofocus run yet',
                                        style: TextStyle(fontSize: 10, color: colors.textMuted),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              label: 'Best Position',
                              value: hasResult ? afResult.bestPosition.toString() : '---',
                            ),
                            _InfoRow(
                              label: 'Best HFR',
                              value: hasResult ? afResult.bestHfr.toStringAsFixed(2) : '---',
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
                              value: hasResult ? afResult.focusData.length.toString() : '---',
                            ),
                            const SizedBox(height: 12),
                            NightshadeButton(
                              label: 'View Details',
                              variant: ButtonVariant.outline,
                              size: ButtonSize.small,
                              onPressed: hasResult ? () => _showAutofocusDetails(context, afResult) : null,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Filter offsets
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  final filterOffsetState = ref.watch(filterOffsetProvider);
                  final availableFilters = ref.watch(availableFiltersProvider);
                  final filterWheelState = ref.watch(filterWheelStateProvider);
                  final isFilterWheelConnected = filterWheelState.connectionState == DeviceConnectionState.connected;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                        await ref.read(filterOffsetProvider.notifier).clearAllOffsets();
                                      }
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              NightshadeButton(
                                label: 'Measure Offsets',
                                size: ButtonSize.small,
                                variant: ButtonVariant.outline,
                                onPressed: isFilterWheelConnected ? () => _showMeasureOffsetsDialog(context) : null,
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
                          spacing: 12,
                          runSpacing: 12,
                          children: availableFilters.map((filterName) {
                            final offset = filterOffsetState.offsets[filterName] ?? 0;
                            final isReference = filterName == filterOffsetState.referenceFilter;

                            return _FilterOffsetControl(
                              name: filterName,
                              offset: offset,
                              isReference: isReference,
                              onIncrease: () async {
                                await ref.read(filterOffsetProvider.notifier).adjustFilterOffset(filterName, 10);
                              },
                              onDecrease: () async {
                                await ref.read(filterOffsetProvider.notifier).adjustFilterOffset(filterName, -10);
                              },
                              onSetReference: () async {
                                await ref.read(filterOffsetProvider.notifier).setReferenceFilter(filterName);
                              },
                            );
                          }).toList(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const _FocusButton({required this.icon, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: color ?? colors.textSecondary),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StepChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
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
    final offsetText = offset == 0 ? '0' : (offset > 0 ? '+$offset' : '$offset');

    return Container(
      width: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReference ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    return Material(
      color: onPressed != null ? colors.surface : colors.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 14,
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
    final minPos = points.map((p) => p.position).reduce((a, b) => a < b ? a : b);
    final maxPos = points.map((p) => p.position).reduce((a, b) => a > b ? a : b);
    final minHfr = points.map((p) => p.hfr).reduce((a, b) => a < b ? a : b);
    final maxHfr = points.map((p) => p.hfr).reduce((a, b) => a > b ? a : b);

    // Add some padding to the HFR range
    final hfrPadding = (maxHfr - minHfr) * 0.1;
    final displayMinHfr = (minHfr - hfrPadding).clamp(0, double.infinity);
    final displayMaxHfr = maxHfr + hfrPadding;

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
            (p.position - minPos) / (maxPos - minPos) * chartArea.width;
        final y = chartArea.bottom -
            (p.hfr - displayMinHfr) / (displayMaxHfr - displayMinHfr) * chartArea.height;

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
          (p.position - minPos) / (maxPos - minPos) * chartArea.width;
      final y = chartArea.bottom -
          (p.hfr - displayMinHfr) / (displayMaxHfr - displayMinHfr) * chartArea.height;

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
