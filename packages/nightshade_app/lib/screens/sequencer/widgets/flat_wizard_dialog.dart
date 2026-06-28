import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';

/// Default filter list used when no profile is configured
const _kFallbackFilters = ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];

class FlatWizardDialog extends ConsumerStatefulWidget {
  const FlatWizardDialog({super.key});

  @override
  ConsumerState<FlatWizardDialog> createState() => _FlatWizardDialogState();
}

class _FlatWizardDialogState extends ConsumerState<FlatWizardDialog> {
  int _currentStep = 0;
  int _targetAdu = 32000;
  double _minExposure = 0.001;
  double _maxExposure = 10.0;
  final double _tolerancePercent = 5.0;
  int _framesPerFilter = 25;

  /// The filters the user wants to calibrate. Multi-select — the service's
  /// `generateFlatSequence` accepts a full list, so a single wizard run can
  /// calibrate and emit flat sub-trees for L/R/G/B/Ha/… in one pass.
  final Set<String> _selectedFilters = {_kFallbackFilters.first};

  bool _isCalculating = false;

  /// Per-filter calibration results, keyed by filter name. A filter is
  /// considered calibrated once it has a successful [FlatResult] here.
  final Map<String, FlatResult> _results = {};
  String? _errorMessage;
  String? _calculationStatus;

  /// True once every selected filter has a successful calibration result.
  bool get _allCalibrated =>
      _selectedFilters.isNotEmpty &&
      _selectedFilters.every((f) => _results[f]?.success == true);

  Future<void> _calculateExposure() async {
    if (_selectedFilters.isEmpty) {
      setState(() {
        _errorMessage = 'Select at least one filter before calibration.';
      });
      return;
    }

    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected ||
        cameraState.deviceId == null) {
      setState(() {
        _errorMessage = 'Connect a camera before calibration.';
      });
      return;
    }
    final activeProfile = ref.read(activeEquipmentProfileProvider);
    final gain = activeProfile?.defaultGain;
    final offset = activeProfile?.defaultOffset;
    if (gain == null || offset == null) {
      setState(() {
        _errorMessage =
            'Set gain and offset on the active equipment profile before calibration.';
      });
      return;
    }

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
      _calculationStatus = null;
      _results.clear();
    });

    final flatService = ref.read(flatWizardServiceProvider);
    // Calibrate each selected filter in turn, accumulating per-filter results
    // and surfacing per-filter progress.
    final ordered = _selectedFilters.toList();
    try {
      for (var i = 0; i < ordered.length; i++) {
        final filter = ordered[i];
        if (!mounted) return;
        final result = await flatService.calibrateFilter(
          deviceId: cameraState.deviceId!,
          filter: filter,
          gain: gain,
          offset: offset,
          targetAdu: _targetAdu.toDouble(),
          tolerance: _tolerancePercent,
          minExposure: _minExposure,
          maxExposure: _maxExposure,
          onProgress: (iteration, exposure, adu) {
            if (!mounted) return;
            setState(() {
              _calculationStatus =
                  '$filter (${i + 1}/${ordered.length}) — iteration $iteration: '
                  '${exposure.toStringAsFixed(3)}s, ADU ${adu.toStringAsFixed(0)}';
            });
          },
        );
        if (!mounted) return;
        setState(() {
          _results[filter] = result;
          if (!result.success) {
            _errorMessage = '$filter: ${result.errorMessage ?? 'did not '
                'converge within limits.'}';
          }
        });
      }
      if (!mounted) return;
      setState(() {
        if (_allCalibrated) {
          _calculationStatus =
              'Calibration complete for ${_results.length} filter(s)';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Calibration failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCalculating = false;
        });
      }
    }
  }

  void _generateFlatSequence() {
    final successful =
        _results.values.where((r) => r.success).toList(growable: false);
    if (successful.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Run calibration successfully first.')),
      );
      return;
    }

    final cameraState = ref.read(cameraStateProvider);
    final flatService = ref.read(flatWizardServiceProvider);
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    final nodes = flatService.generateFlatSequence(
      calibrations: successful,
      framesPerFilter: _framesPerFilter,
      gain: cameraState.gain,
      offset: cameraState.offset,
      onlySuccessful: true,
    );

    if (nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No flat nodes were generated.')),
      );
      return;
    }

    for (final node in nodes) {
      sequenceNotifier.addNode(node);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${nodes.length} flat capture node(s).')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NightshadeColors.of(context);

    // Stepper renders its own controls row, so the dialog scaffold's footer
    // slot is intentionally empty.
    return NightshadeDialog(
      title: 'Flat Frame Wizard',
      icon: NightshadeIcons.sun,
      width: 700,
      height: 600,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      child: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 1 && !_allCalibrated) {
            // Gate the Calculate → Review transition: don't let the user
            // advance to a Review that would show "Not calculated".
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Run calibration successfully first.')),
            );
            return;
          }
          if (_currentStep < 2) {
            setState(() => _currentStep++);
          } else {
            _generateFlatSequence();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            Navigator.of(context).pop();
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                NightshadeButton(
                  onPressed: details.onStepContinue,
                  label: _currentStep == 2 ? 'Generate' : 'Continue',
                  variant: ButtonVariant.primary,
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  onPressed: details.onStepCancel,
                  label: _currentStep == 0 ? 'Cancel' : 'Back',
                  variant: ButtonVariant.ghost,
                ),
              ],
            ),
          );
        },
        steps: [
          // Step 1: Configuration
          Step(
            title: const Text('Configuration'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTargetAduSlider(colors),
                const SizedBox(height: 24),
                _buildFilterSelector(colors),
                const SizedBox(height: 24),
                _buildFramesPerFilterControl(colors),
                const SizedBox(height: 24),
                _buildExposureLimits(colors),
              ],
            ),
          ),

          // Step 2: Auto-Calculate
          Step(
            title: const Text('Calculate Exposure'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Click "Calculate" to automatically determine the optimal '
                  'exposure time for each selected filter.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_calculationStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _calculationStatus!,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Per-filter result cards as calibration completes.
                for (final filter in _selectedFilters)
                  _buildFilterResultCard(colors, theme, filter),
                const SizedBox(height: 8),
                NightshadeButton(
                  onPressed: _isCalculating ? null : _calculateExposure,
                  icon: LucideIcons.calculator,
                  label: _isCalculating
                      ? 'Calculating...'
                      : (_results.isEmpty ? 'Calculate' : 'Recalculate'),
                  variant: ButtonVariant.primary,
                  isLoading: _isCalculating,
                ),
              ],
            ),
          ),

          // Step 3: Review
          Step(
            title: const Text('Review'),
            isActive: _currentStep >= 2,
            content: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReviewRow('Target ADU:', '$_targetAdu'),
                  _buildReviewRow('Frames per filter:', '$_framesPerFilter'),
                  const SizedBox(height: 8),
                  const Text('Calibrated filters',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final filter in _selectedFilters)
                    _buildReviewRow(
                      '$filter:',
                      _results[filter]?.success == true
                          ? '${_results[filter]!.exposure.toStringAsFixed(3)}s '
                              '× $_framesPerFilter'
                          : 'Not calculated',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAduSlider(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Target ADU'),
            const Spacer(),
            Text(
              '$_targetAdu',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: _targetAdu.toDouble(),
          min: 10000,
          max: 50000,
          divisions: 40,
          onChanged: (v) => setState(() => _targetAdu = v.toInt()),
          activeColor: colors.primary,
        ),
      ],
    );
  }

  Widget _buildFilterSelector(NightshadeColors colors) {
    // Get filters from active profile, falling back to generic list
    final profileFilters = ref.watch(profileFiltersProvider);
    final availableFilters =
        profileFilters.isNotEmpty ? profileFilters : _kFallbackFilters;

    // Drop any selected filter that's no longer offered (profile changed) and
    // ensure at least one stays selected.
    final stale = _selectedFilters.where((f) => !availableFilters.contains(f));
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedFilters.removeWhere((f) => !availableFilters.contains(f));
          if (_selectedFilters.isEmpty && availableFilters.isNotEmpty) {
            _selectedFilters.add(availableFilters.first);
          }
        });
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filters to calibrate'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in availableFilters)
              FilterChip(
                label: Text(f),
                selected: _selectedFilters.contains(f),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedFilters.add(f);
                    } else {
                      _selectedFilters.remove(f);
                    }
                    // Re-calibration is required after the filter set changes.
                    _results.removeWhere((key, _) => key == f && !selected);
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ProfileEditorDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.settings, size: 12, color: colors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Edit filters...',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFramesPerFilterControl(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Frames per filter'),
            const Spacer(),
            Text(
              '$_framesPerFilter',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: _framesPerFilter.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          onChanged: (v) => setState(() => _framesPerFilter = v.round()),
          activeColor: colors.primary,
        ),
      ],
    );
  }

  Widget _buildFilterResultCard(
      NightshadeColors colors, ThemeData theme, String filter) {
    final result = _results[filter];
    final isCalibrated = result?.success == true;
    final isFailed = result != null && !result.success;
    final accent = isCalibrated
        ? colors.success
        : isFailed
            ? colors.error
            : colors.border;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: accent),
      ),
      child: Row(
        children: [
          Icon(
            isCalibrated
                ? NightshadeIcons.success
                : isFailed
                    ? NightshadeIcons.error
                    : NightshadeIcons.idea,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(filter,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(
            isCalibrated
                ? '${result!.exposure.toStringAsFixed(3)}s @ '
                    '${result.adu.toStringAsFixed(0)} ADU'
                : isFailed
                    ? 'Failed'
                    : 'Pending',
            style: theme.textTheme.bodySmall?.copyWith(color: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildExposureLimits(NightshadeColors colors) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: _minExposure.toString(),
            decoration: const InputDecoration(labelText: 'Min Exposure (s)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null) setState(() => _minExposure = parsed);
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            initialValue: _maxExposure.toString(),
            decoration: const InputDecoration(labelText: 'Max Exposure (s)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null) setState(() => _maxExposure = parsed);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
