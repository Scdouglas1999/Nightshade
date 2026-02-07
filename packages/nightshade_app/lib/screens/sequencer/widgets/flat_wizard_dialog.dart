import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';

enum FlatPanelLocation { dawnSky, duskSky, flatPanel }

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
  FlatPanelLocation _panelLocation = FlatPanelLocation.duskSky;
  String? _selectedFilter = _kFallbackFilters.first;

  bool _isCalculating = false;
  double? _calculatedExposure;
  double? _measuredAdu;
  String? _errorMessage;
  String? _calculationStatus;

  Future<void> _calculateExposure() async {
    if (_selectedFilter == null || _selectedFilter!.isEmpty) {
      setState(() {
        _errorMessage = 'Select a filter before calibration.';
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

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
      _calculationStatus = null;
      _calculatedExposure = null;
      _measuredAdu = null;
    });

    try {
      final flatService = ref.read(flatWizardServiceProvider);
      final result = await flatService.calibrateFilter(
        deviceId: cameraState.deviceId!,
        filter: _selectedFilter!,
        targetAdu: _targetAdu.toDouble(),
        tolerance: _tolerancePercent,
        minExposure: _minExposure,
        maxExposure: _maxExposure,
        onProgress: (iteration, exposure, adu) {
          if (!mounted) {
            return;
          }
          setState(() {
            _calculationStatus =
                'Iteration $iteration: ${exposure.toStringAsFixed(3)}s, ADU ${adu.toStringAsFixed(0)}';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (result.success) {
          _calculatedExposure = result.exposure;
          _measuredAdu = result.adu;
          _calculationStatus = 'Calibration complete';
        } else {
          _errorMessage = result.errorMessage ??
              'Calibration did not converge within limits.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
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
    if (_calculatedExposure == null || _selectedFilter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Run calibration successfully first.')),
      );
      return;
    }

    final cameraState = ref.read(cameraStateProvider);
    final flatService = ref.read(flatWizardServiceProvider);
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    final nodes = flatService.generateFlatSequence(
      calibrations: [
        FlatResult(
          filter: _selectedFilter!,
          exposure: _calculatedExposure!,
          adu: _measuredAdu ?? _targetAdu.toDouble(),
          success: true,
        ),
      ],
      framesPerFilter: 25,
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
    final colors = theme.extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 700,
          preferredHeight: 600,
          minWidth: 500,
          minHeight: 450,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wb_sunny, color: colors.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Flat Frame Wizard',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Stepper
              Expanded(
                child: Stepper(
                  currentStep: _currentStep,
                  onStepContinue: () {
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
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTargetAduSlider(colors),
                          const SizedBox(height: 24),
                          _buildPanelLocationSelector(colors),
                          const SizedBox(height: 24),
                          _buildFilterSelector(colors),
                          const SizedBox(height: 24),
                          _buildExposureLimits(colors),
                        ],
                      ),
                    ),

                    // Step 2: Auto-Calculate
                    Step(
                      title: const Text('Calculate Exposure'),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1
                          ? StepState.complete
                          : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_calculatedExposure == null)
                            Column(
                              children: [
                                Text(
                                  'Click "Calculate" to automatically determine the optimal exposure time.',
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                NightshadeButton(
                                  onPressed: _isCalculating
                                      ? null
                                      : _calculateExposure,
                                  icon: Icons.calculate,
                                  label: _isCalculating
                                      ? 'Calculating...'
                                      : 'Calculate',
                                  variant: ButtonVariant.primary,
                                  isLoading: _isCalculating,
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colors.success),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: colors.success, size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Optimal Exposure Time',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_calculatedExposure!.toStringAsFixed(3)}s',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                      color: colors.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Target ADU: $_targetAdu +/- ${(_targetAdu * _tolerancePercent / 100).toStringAsFixed(0)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (_measuredAdu != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Measured ADU: ${_measuredAdu!.toStringAsFixed(0)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
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
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildReviewRow(
                                'Filter:', _selectedFilter ?? 'All'),
                            _buildReviewRow(
                                'Panel Location:', _panelLocationName()),
                            _buildReviewRow('Target ADU:', '$_targetAdu'),
                            _buildReviewRow(
                                'Exposure Time:',
                                _calculatedExposure != null
                                    ? '${_calculatedExposure!.toStringAsFixed(3)}s'
                                    : 'Not calculated'),
                            _buildReviewRow('Frame Count:', '25'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildPanelLocationSelector(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Location'),
        const SizedBox(height: 8),
        SegmentedButton<FlatPanelLocation>(
          segments: const [
            ButtonSegment(
              value: FlatPanelLocation.dawnSky,
              label: Text('Dawn Sky'),
              icon: Icon(Icons.wb_twilight),
            ),
            ButtonSegment(
              value: FlatPanelLocation.duskSky,
              label: Text('Dusk Sky'),
              icon: Icon(Icons.wb_sunny),
            ),
            ButtonSegment(
              value: FlatPanelLocation.flatPanel,
              label: Text('Flat Panel'),
              icon: Icon(Icons.lightbulb),
            ),
          ],
          selected: {_panelLocation},
          onSelectionChanged: (Set<FlatPanelLocation> selection) {
            setState(() => _panelLocation = selection.first);
          },
        ),
      ],
    );
  }

  Widget _buildFilterSelector(NightshadeColors colors) {
    // Get filters from active profile, falling back to generic list
    final profileFilters = ref.watch(profileFiltersProvider);
    final availableFilters =
        profileFilters.isNotEmpty ? profileFilters : _kFallbackFilters;
    final effectiveSelected = availableFilters.contains(_selectedFilter)
        ? _selectedFilter
        : (availableFilters.isNotEmpty ? availableFilters.first : null);

    if (effectiveSelected != _selectedFilter && effectiveSelected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedFilter = effectiveSelected;
          });
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filter'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: effectiveSelected,
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border)),
          ),
          items: [
            ...availableFilters
                .map((f) => DropdownMenuItem(value: f, child: Text(f))),
          ],
          onChanged: (v) => setState(() => _selectedFilter = v),
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
                    fontSize: 11,
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

  String _panelLocationName() {
    switch (_panelLocation) {
      case FlatPanelLocation.dawnSky:
        return 'Dawn Sky';
      case FlatPanelLocation.duskSky:
        return 'Dusk Sky';
      case FlatPanelLocation.flatPanel:
        return 'Flat Panel';
    }
  }
}
