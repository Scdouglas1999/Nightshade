import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

enum FlatPanelLocation { dawnSky, duskSky, flatPanel }

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
  String? _selectedFilter;
  
  bool _isCalculating = false;
  double? _calculatedExposure;
  List<String> _availableFilters = [];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  void _loadFilters() {
    // Load filters from filter wheel or use defaults
    setState(() {
      _availableFilters = ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];
    });
  }

  Future<void> _calculateExposure() async {
    setState(() => _isCalculating = true);
    
    // Simulate exposure calculation
    // In production, this would take a test exposure and adjust
    await Future.delayed(const Duration(seconds: 2));
    
    setState(() {
      _calculatedExposure = 2.5; // Placeholder
      _isCalculating = false;
    });
  }

  void _generateFlatSequence() {
    // Generate flat frame sequence and add to sequencer
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        height: 600,
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
                        ElevatedButton(
                          onPressed: details.onStepContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_currentStep == 2 ? 'Generate' : 'Continue'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
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
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
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
                              ElevatedButton.icon(
                                onPressed: _isCalculating ? null : _calculateExposure,
                                icon: _isCalculating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.calculate),
                                label: Text(_isCalculating ? 'Calculating...' : 'Calculate'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                ),
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
                                Icon(Icons.check_circle, color: colors.success, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Optimal Exposure Time',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_calculatedExposure!.toStringAsFixed(3)}s',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color: colors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Target ADU: $_targetAdu ± ${(_targetAdu * _tolerancePercent / 100).toStringAsFixed(0)}',
                                  style: theme.textTheme.bodySmall,
                                ),
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
                          _buildReviewRow('Filter:', _selectedFilter ?? 'All'),
                          _buildReviewRow('Panel Location:', _panelLocationName()),
                          _buildReviewRow('Target ADU:', '$_targetAdu'),
                          _buildReviewRow('Exposure Time:', 
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filter (optional)'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedFilter,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
            hintText: 'All filters',
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('All filters')),
            ..._availableFilters.map((f) => DropdownMenuItem(value: f, child: Text(f))),
          ],
          onChanged: (v) => setState(() => _selectedFilter = v),
        ),
      ],
    );
  }

  Widget _buildExposureLimits(NightshadeColors colors) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: _minExposure.toString()),
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
          child: TextField(
            controller: TextEditingController(text: _maxExposure.toString()),
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
