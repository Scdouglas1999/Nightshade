import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'dart:math' as math;

class MosaicWizardDialog extends ConsumerStatefulWidget {
  final double? initialRa;
  final double? initialDec;
  
  const MosaicWizardDialog({
    this.initialRa,
    this.initialDec,
    super.key,
  });

  @override
  ConsumerState<MosaicWizardDialog> createState() => _MosaicWizardDialogState();
}

class _MosaicWizardDialogState extends ConsumerState<MosaicWizardDialog> {
  late double _centerRa;
  late double _centerDec;
  double _panelWidthArcmin = 60.0;
  double _panelHeightArcmin = 40.0;
  double _overlapPercent = 10.0;
  double _rotation = 0.0;
  int _panelsHorizontal = 3;
  int _panelsVertical = 3;
  
  @override
  void initState() {
    super.initState();
    _centerRa = widget.initialRa ?? 0.0;
    _centerDec = widget.initialDec ?? 0.0;
  }

  List<_MosaicPanel> _calculatePanels() {
    final panels = <_MosaicPanel>[];
    
    final overlapFactor = 1.0 - (_overlapPercent / 100.0);
    final effectiveWidth = _panelWidthArcmin * overlapFactor;
    final effectiveHeight = _panelHeightArcmin * overlapFactor;
    
    final widthDeg = effectiveWidth / 60.0;
    final heightDeg = effectiveHeight / 60.0;
    
    final centerRowOffset = (_panelsVertical - 1) / 2.0;
    final centerColOffset = (_panelsHorizontal - 1) / 2.0;
    
    var panelIndex = 0;
    
    for (var row = 0; row < _panelsVertical; row++) {
      for (var col = 0; col < _panelsHorizontal; col++) {
        final decOffset = (row - centerRowOffset) * heightDeg;
        final raOffsetDeg = (col - centerColOffset) * widthDeg;
        
        // Apply rotation
        double rotatedRaOffset, rotatedDecOffset;
        if (_rotation != 0.0) {
          final angleRad = _rotation * math.pi / 180.0;
          final cosAngle = math.cos(angleRad);
          final sinAngle = math.sin(angleRad);
          
          rotatedRaOffset = raOffsetDeg * cosAngle - decOffset * sinAngle;
          rotatedDecOffset = raOffsetDeg * sinAngle + decOffset * cosAngle;
        } else {
          rotatedRaOffset = raOffsetDeg;
          rotatedDecOffset = decOffset;
        }
        
        // Calculate final RA with declination compression
        final decRad = _centerDec * math.pi / 180.0;
        final raCorrection = math.cos(decRad).abs() > 0.001 
            ? 1.0 / math.cos(decRad)
            : 1.0;
        
        final panelDec = _centerDec + rotatedDecOffset;
        final panelRa = _centerRa + (rotatedRaOffset * raCorrection / 15.0);
        
        panels.add(_MosaicPanel(
          ra: panelRa,
          dec: panelDec,
          index: panelIndex,
          row: row,
          col: col,
        ));
        
        panelIndex++;
      }
    }
    
    return panels;
  }

  double _calculateTotalTime(double exposureSecs, int exposuresPerPanel) {
    final totalPanels = _panelsHorizontal * _panelsVertical;
    final timePerPanel = exposureSecs * exposuresPerPanel;
    const overheadPerPanel = 60.0; // Slew + center + settle
    
    return totalPanels * (timePerPanel + overheadPerPanel);
  }

  void _generateMosaic() {
    const mosaicService = MosaicService();

    // Create mosaic configuration
    final config = MosaicConfig(
      centerRa: _centerRa,
      centerDec: _centerDec,
      panelWidthArcmin: _panelWidthArcmin,
      panelHeightArcmin: _panelHeightArcmin,
      overlapPercent: _overlapPercent,
      rotation: _rotation,
      panelsHorizontal: _panelsHorizontal,
      panelsVertical: _panelsVertical,
    );

    // Validate configuration
    final validation = mosaicService.validateMosaic(config);
    if (!validation.isValid) {
      _showValidationDialog(validation);
      return;
    }

    // Show warnings if any
    if (validation.hasWarnings) {
      _showWarningsDialog(validation, () {
        _createSequence(mosaicService, config);
      });
      return;
    }

    // Create sequence directly if no warnings
    _createSequence(mosaicService, config);
  }

  void _createSequence(MosaicService mosaicService, MosaicConfig config) {
    // Create default exposure settings
    // These would typically come from a second dialog or form
    const exposure = MosaicExposureSettings(
      exposureSeconds: 60.0,
      exposuresPerPanel: 10,
      filterName: null, // Use current filter
      binning: 1,
    );

    // Create sequence options
    const options = MosaicSequenceOptions(
      serpentineOrdering: true,
      centerAfterSlew: true,
      autofocusPerPanel: false,
    );

    // Generate the sequence
    final nodes = mosaicService.createMosaicSequence(
      mosaicName: 'Mosaic ${_centerRa.toStringAsFixed(2)}h ${_centerDec.toStringAsFixed(1)}°',
      config: config,
      exposure: exposure,
      options: options,
    );

    // Add nodes to the sequence
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    // Find the root node
    final rootNode = nodes.values.firstWhere(
      (node) => node is InstructionSetNode && node.parentId == null,
    );

    // If no sequence exists, create one first
    if (ref.read(currentSequenceProvider) == null) {
      sequenceNotifier.createSequence(name: 'New Mosaic Sequence');
    }

    // Add all nodes to the sequence
    for (final node in nodes.values) {
      if (node.id != rootNode.id) {
        sequenceNotifier.addNode(node, parentId: node.parentId);
      } else {
        // Add root's children to the current sequence root
        final currentSeq = ref.read(currentSequenceProvider);
        if (currentSeq != null) {
          for (final childId in rootNode.childIds) {
            final child = nodes[childId];
            if (child != null) {
              sequenceNotifier.addNode(child, parentId: currentSeq.rootNodeId);
            }
          }
        }
      }
    }

    Navigator.of(context).pop();

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generated mosaic with ${config.totalPanels} panels'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showValidationDialog(MosaicValidation validation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid Mosaic Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please fix the following errors:'),
            const SizedBox(height: 8),
            ...validation.errors.map((error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error)),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showWarningsDialog(MosaicValidation validation, VoidCallback onProceed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mosaic Warnings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The following warnings were found:'),
            const SizedBox(height: 8),
            ...validation.warnings.map((warning) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(warning)),
                ],
              ),
            )),
            const SizedBox(height: 16),
            const Text('Do you want to proceed anyway?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onProceed();
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;
    final panels = _calculatePanels();
    final totalArea = _panelWidthArcmin * _panelsHorizontal * 
                     _panelHeightArcmin * _panelsVertical;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 700,
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
                  Icon(Icons.grid_on, color: colors.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Mosaic Wizard',
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
            
            // Content
            Expanded(
              child: Row(
                children: [
                  // Configuration Panel
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSection(
                            'Center Coordinates',
                            [
                              _buildNumberField(
                                'Right Ascension (hours)',
                                _centerRa,
                                (v) => setState(() => _centerRa = v),
                                min: 0,
                                max: 24,
                              ),
                              const SizedBox(height: 12),
                              _buildNumberField(
                                'Declination (degrees)',
                                _centerDec,
                                (v) => setState(() => _centerDec = v),
                                min: -90,
                                max: 90,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          _buildSection(
                            'Panel Size',
                            [
                              _buildNumberField(
                                'Width (arcmin)',
                                _panelWidthArcmin,
                                (v) => setState(() => _panelWidthArcmin = v),
                                min: 1,
                                max: 360,
                              ),
                              const SizedBox(height: 12),
                              _buildNumberField(
                                'Height (arcmin)',
                                _panelHeightArcmin,
                                (v) => setState(() => _panelHeightArcmin = v),
                                min: 1,
                                max: 360,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          _buildSection(
                            'Grid Configuration',
                            [
                              _buildIntField(
                                'Panels Horizontal',
                                _panelsHorizontal,
                                (v) => setState(() => _panelsHorizontal = v),
                                min: 1,
                                max: 10,
                              ),
                              const SizedBox(height: 12),
                              _buildIntField(
                                'Panels Vertical',
                                _panelsVertical,
                                (v) => setState(() => _panelsVertical = v),
                                min: 1,
                                max: 10,
                              ),
                              const SizedBox(height: 12),
                              _buildSlider(
                                'Overlap (%)',
                                _overlapPercent,
                                (v) => setState(() => _overlapPercent = v),
                                min: 0,
                                max: 50,
                              ),
                              const SizedBox(height: 12),
                              _buildSlider(
                                'Rotation (°)',
                                _rotation,
                                (v) => setState(() => _rotation = v),
                                min: -180,
                                max: 180,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Statistics
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Statistics', style: theme.textTheme.titleSmall),
                                const SizedBox(height: 12),
                                _buildStatRow('Total Panels:', '${panels.length}'),
                                _buildStatRow('Grid Size:', '$_panelsHorizontal×$_panelsVertical'),
                                _buildStatRow('Coverage Area:', '${(totalArea / 3600).toStringAsFixed(2)} sq°'),
                                _buildStatRow('Panel Size:', '${(_panelWidthArcmin / 60).toStringAsFixed(2)}° × ${(_panelHeightArcmin / 60).toStringAsFixed(2)}°'),
                                _buildStatRow('Effective Overlap:',
                                    '${(_overlapPercent * _panelWidthArcmin / 100).toStringAsFixed(1)}\' × ${(_overlapPercent * _panelHeightArcmin / 100).toStringAsFixed(1)}\''),
                                const Divider(height: 24),
                                _buildStatRow('Est. Time (60s×10):',
                                    '${(_calculateTotalTime(60, 10) / 3600).toStringAsFixed(1)}h',
                                    highlight: true),
                                _buildStatRow('Total Exposures:', '${panels.length * 10}'),
                                _buildStatRow('Total Integration:',
                                    '${(panels.length * 10 * 60 / 3600).toStringAsFixed(1)}h'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Preview Panel
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: CustomPaint(
                        painter: _MosaicPreviewPainter(
                          panels: panels,
                          panelWidthArcmin: _panelWidthArcmin,
                          panelHeightArcmin: _panelHeightArcmin,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _generateMosaic,
                    icon: const Icon(Icons.add),
                    label: const Text('Generate Mosaic'),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildNumberField(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    required double min,
    required double max,
  }) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return TextField(
      controller: TextEditingController(text: value.toStringAsFixed(2)),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null && parsed >= min && parsed <= max) {
          onChanged(parsed);
        }
      },
    );
  }

  Widget _buildIntField(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    required int min,
    required int max,
  }) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return TextField(
      controller: TextEditingController(text: value.toString()),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
      ),
      keyboardType: TextInputType.number,
      onChanged: (v) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed >= min && parsed <= max) {
          onChanged(parsed);
        }
      },
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    required double min,
    required double max,
  }) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          activeColor: colors.primary,
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              color: highlight ? colors.accent : colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MosaicPanel {
  final double ra;
  final double dec;
  final int index;
  final int row;
  final int col;

  _MosaicPanel({
    required this.ra,
    required this.dec,
    required this.index,
    required this.row,
    required this.col,
  });
}

class _MosaicPreviewPainter extends CustomPainter {
  final List<_MosaicPanel> panels;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final NightshadeColors colors;

  _MosaicPreviewPainter({
    required this.panels,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (panels.isEmpty) return;

    // Find bounds
    final raMin = panels.map((p) => p.ra).reduce(math.min);
    final raMax = panels.map((p) => p.ra).reduce(math.max);
    final decMin = panels.map((p) => p.dec).reduce(math.min);
    final decMax = panels.map((p) => p.dec).reduce(math.max);

    // Add padding
    final raRange = (raMax - raMin) * 1.2;
    final decRange = (decMax - decMin) * 1.2;
    final centerRa = (raMin + raMax) / 2;
    final centerDec = (decMin + decMax) / 2;

    // Draw each panel
    for (final panel in panels) {
      final normalizedX = (panel.ra - centerRa) / raRange + 0.5;
      final normalizedY = (panel.dec - centerDec) / decRange + 0.5;

      final x = normalizedX * size.width;
      final y = (1 - normalizedY) * size.height; // Flip Y axis

      final panelWidth = (panelWidthArcmin / 60.0 / 15.0) / raRange * size.width;
      final panelHeight = (panelHeightArcmin / 60.0) / decRange * size.height;

      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: panelWidth,
        height: panelHeight,
      );

      // Draw panel rectangle
      final paint = Paint()
        ..color = colors.primary.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);

      // Draw border
      final borderPaint = Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, borderPaint);

      // Draw panel number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${panel.index + 1}',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Draw center crosshair
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final crosshairPaint = Paint()
      ..color = colors.accent
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(centerX - 10, centerY),
      Offset(centerX + 10, centerY),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - 10),
      Offset(centerX, centerY + 10),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MosaicPreviewPainter oldDelegate) {
    return panels != oldDelegate.panels ||
           panelWidthArcmin != oldDelegate.panelWidthArcmin ||
           panelHeightArcmin != oldDelegate.panelHeightArcmin;
  }
}
