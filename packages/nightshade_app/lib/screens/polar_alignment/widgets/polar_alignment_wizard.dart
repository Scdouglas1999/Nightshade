import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Polar Alignment Wizard
/// Guides the user through the three-point polar alignment process
class PolarAlignmentWizard extends ConsumerStatefulWidget {
  const PolarAlignmentWizard({super.key});

  @override
  ConsumerState<PolarAlignmentWizard> createState() =>
      _PolarAlignmentWizardState();
}

class _PolarAlignmentWizardState extends ConsumerState<PolarAlignmentWizard> {
  // Configuration
  double _exposureDuration = 2.0;
  int _binning = 2;
  double _rotationStep = 20.0;
  int? _gain;
  int? _offset;
  bool _startFromCurrent = true;
  bool _isNorth = true;
  bool _manualSlew = false;

  // State
  bool _isRunning = false;
  String _statusMessage = 'Ready to start';
  double? _azimuthError;
  double? _altitudeError;
  double? _totalError;

  // Stream subscription
  StreamSubscription? _eventSubscription;

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _startAlignment() async {
    setState(() {
      _isRunning = true;
      _statusMessage = 'Starting alignment...';
      _azimuthError = null;
      _altitudeError = null;
      _totalError = null;
    });

    // Create a temporary sequence with a single PolarAlignmentNode
    final node = PolarAlignmentNode(
      exposureDuration: _exposureDuration,
      binning: _binning,
      rotationStep: _rotationStep,
      gain: _gain,
      offset: _offset,
      startFromCurrent: _startFromCurrent,
      isNorth: _isNorth,
      manualSlew: _manualSlew,
    );

    final sequence = Sequence(
      name: 'Polar Alignment',
      nodes: {node.id: node},
      rootNodeId: node.id,
    );

    // Load and start sequence via provider. Polar alignment is a wizard-
    // driven flow that builds a one-shot sequence; the user already opted
    // into running it by completing the wizard, so we pass
    // `discardUnsaved: true` to skip the editor's clobber prompt.
    ref
        .read(currentSequenceProvider.notifier)
        .loadSequence(sequence, discardUnsaved: true);

    try {
      // Subscribe to events using the generated API
      _eventSubscription?.cancel();
      _eventSubscription = bridge.apiEventStream().listen(_handleEvent);

      await ref.read(sequenceExecutorProvider).start();
    } catch (e) {
      setState(() {
        _isRunning = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  void _handleEvent(bridge.NightshadeEvent event) {
    if (event.category == bridge.EventCategory.polarAlignment) {
      final payload = event.payload;
      if (payload is bridge.EventPayload_PolarAlignment) {
        final e = payload.field0;
        setState(() {
          _azimuthError = e.azimuthError;
          _altitudeError = e.altitudeError;
          _totalError = e.totalError;
          _statusMessage =
              'Adjusting... Error: ${e.totalError.toStringAsFixed(1)}\'';
        });
      }
    } else if (event.category == bridge.EventCategory.sequencer) {
      // Handle completion/failure
      final payload = event.payload;
      if (payload is bridge.EventPayload_Sequencer) {
        final seqEvent = payload.field0;
        if (seqEvent is bridge.SequencerEvent_NodeCompleted) {
          // Check if success or failure
          if (seqEvent.status == 'success') {
            setState(() {
              _isRunning = false;
              _statusMessage = 'Alignment complete!';
            });
          }
        }
      }
    }
  }

  void _stopAlignment() {
    ref.read(sequenceExecutorProvider).stop();
    setState(() {
      _isRunning = false;
      _statusMessage = 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Three-Point Polar Alignment',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (!_isRunning) ...[
                _buildConfig(),
                const SizedBox(height: 16),
                NightshadeButton(
                  label: 'Start Alignment',
                  onPressed: _startAlignment,
                  variant: ButtonVariant.primary,
                ),
              ] else ...[
                _buildStatus(),
                const SizedBox(height: 16),
                _buildErrorDisplay(),
                const SizedBox(height: 16),
                NightshadeButton(
                  label: 'Stop',
                  onPressed: _stopAlignment,
                  variant: ButtonVariant.destructive,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _exposureDuration.toString(),
                decoration: const InputDecoration(labelText: 'Exposure (s)'),
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    _exposureDuration = double.tryParse(v) ?? _exposureDuration,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                initialValue: _rotationStep.toString(),
                decoration:
                    const InputDecoration(labelText: 'Rotation Step (deg)'),
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    _rotationStep = double.tryParse(v) ?? _rotationStep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _gain?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Gain (Optional)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _gain = int.tryParse(v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                initialValue: _offset?.toString() ?? '',
                decoration:
                    const InputDecoration(labelText: 'Offset (Optional)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _offset = int.tryParse(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _binning,
          decoration: const InputDecoration(labelText: 'Binning'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1x1')),
            DropdownMenuItem(value: 2, child: Text('2x2')),
            DropdownMenuItem(value: 3, child: Text('3x3')),
            DropdownMenuItem(value: 4, child: Text('4x4')),
          ],
          onChanged: (v) => setState(() => _binning = v ?? 2),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<bool>(
          initialValue: _isNorth,
          decoration: const InputDecoration(labelText: 'Hemisphere'),
          items: const [
            DropdownMenuItem(value: true, child: Text('North')),
            DropdownMenuItem(value: false, child: Text('South')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _isNorth = v);
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Start from Current Location'),
          subtitle: const Text(
              'If disabled, mount will slew to near-pole position first'),
          value: _startFromCurrent,
          onChanged: (v) => setState(() => _startFromCurrent = v),
        ),
        SwitchListTile(
          title: const Text('Manual Slew'),
          subtitle: const Text(
              'For trackers without GoTo. You will be prompted to rotate.'),
          value: _manualSlew,
          onChanged: (v) => setState(() => _manualSlew = v),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    return Text(_statusMessage, style: Theme.of(context).textTheme.bodyLarge);
  }

  Widget _buildErrorDisplay() {
    if (_azimuthError == null || _altitudeError == null)
      return const SizedBox.shrink();

    return Column(
      children: [
        _buildErrorBar('Azimuth', _azimuthError!),
        const SizedBox(height: 8),
        _buildErrorBar('Altitude', _altitudeError!),
        const SizedBox(height: 8),
        Text('Total Error: ${_totalError?.toStringAsFixed(1)}\'',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildErrorBar(String label, double error) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final color = error.abs() < 1.0 ? colors.success : colors.error;
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: LinearProgressIndicator(
            value: (error.abs() / 10.0).clamp(0.0, 1.0), // Scale to 10 arcmin
            color: color,
            backgroundColor: colors.surfaceAlt,
          ),
        ),
        SizedBox(
            width: 60,
            child: Text('${error.toStringAsFixed(1)}\'',
                textAlign: TextAlign.end)),
      ],
    );
  }
}
