// Wave 5 Agent 1 — Mosaic Wizard powered by the planetarium's mosaic
// planner.
//
// The visual planner draws a grid of camera-FOV-shaped panels over a
// stylised sky background. The user can:
//   * drag the centre of the mosaic to reposition it
//   * use +/- buttons (or the "Advanced" panel) to change the grid
//     dimensions
//   * drag a slider to set rotation; the on-screen grid follows the
//     drag in real time
//   * click any panel to disable / re-enable it (useful when a corner
//     is occluded by trees in the user's view)
//
// The generated `MosaicConfig` shape is identical to the pre-Wave-5
// wizard, so the executor and resume logic don't change.
//
// The Wave 4 Mosaic-Resume banner remains at the top of the dialog —
// see `_buildResumeBanner` below.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

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

MosaicExposureSettings mosaicWizardExposureSettingsForContext(
  SmartNightExposureContext? exposureContext,
) =>
    smartNightMosaicExposureSettings(exposureContext);

class _MosaicWizardDialogState extends ConsumerState<MosaicWizardDialog> {
  late double _centerRa;
  late double _centerDec;
  double _panelWidthArcmin = 60.0;
  double _panelHeightArcmin = 40.0;
  double _overlapPercent = 10.0;
  double _rotation = 0.0;
  int _panelsHorizontal = 3;
  int _panelsVertical = 3;
  bool _advancedExpanded = false;

  /// Indices of panels the user has disabled by tapping. The
  /// canonical recipe (3x3) still generates 9 panels but disabled
  /// entries are skipped when the sequence is built. This lets users
  /// drop the corner panel that intersects with a tree without
  /// rebuilding the grid.
  final Set<int> _disabledPanels = <int>{};

  /// Wave 4 Mosaic-Resume: holds the resumable checkpoint info when an
  /// interrupted mosaic sequence is detected. `null` while loading and
  /// when no mosaic checkpoint exists.
  CheckpointInfo? _resumableMosaicCheckpoint;

  @override
  void initState() {
    super.initState();
    _centerRa = widget.initialRa ?? 0.0;
    _centerDec = widget.initialDec ?? 0.0;
    _probeForInterruptedMosaic();
  }

  Future<void> _probeForInterruptedMosaic() async {
    try {
      final backend = ref.read(backendProvider);
      final hasCheckpoint = await backend.hasCheckpoint();
      if (!hasCheckpoint) return;
      final info = await backend.getCheckpointInfo();
      if (!mounted) return;
      final isMosaic = info != null &&
          info.canResume &&
          info.sequenceName.startsWith('Mosaic ');
      if (isMosaic) {
        setState(() => _resumableMosaicCheckpoint = info);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Could not check for interrupted mosaic: $e',
        );
      }
    }
  }

  Future<void> _resumeInterruptedMosaic() async {
    final backend = ref.read(backendProvider);
    try {
      await backend.resumeFromCheckpoint();
      if (mounted) {
        Navigator.of(context).pop();
        context.showSuccessSnackBar('Resuming mosaic from checkpoint…');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to resume mosaic: $e');
      }
    }
  }

  Future<void> _discardMosaicCheckpoint() async {
    final backend = ref.read(backendProvider);
    try {
      await backend.discardCheckpoint();
      if (mounted) {
        setState(() => _resumableMosaicCheckpoint = null);
        context.showSuccessSnackBar('Mosaic checkpoint discarded.');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to discard checkpoint: $e');
      }
    }
  }

  /// Compute panel positions for the visual planner.
  ///
  /// Delegates to the planetarium's `MosaicPlanner.generateRectangularMosaic`
  /// for the actual spherical geometry — that ensures the on-screen
  /// preview matches the framing-view's mosaic overlay (the
  /// planetarium uses the same planner to render its own mosaic
  /// preview). The wizard then maps those panels into the local
  /// `_PanelPosition` shape and overlays the user's enable/disable
  /// toggles.
  List<_PanelPosition> _calculatePanels() {
    final overlapFraction = _overlapPercent / 100.0;
    final panelFovWidthDeg = _panelWidthArcmin / 60.0;
    final panelFovHeightDeg = _panelHeightArcmin / 60.0;

    final plan = planetarium.MosaicPlanner.generateRectangularMosaic(
      center: planetarium.CelestialCoordinate(
        ra: _centerRa,
        dec: _centerDec,
      ),
      rows: _panelsVertical,
      columns: _panelsHorizontal,
      panelFovWidth: panelFovWidthDeg,
      panelFovHeight: panelFovHeightDeg,
      overlap: planetarium.MosaicOverlap(
        horizontal: overlapFraction,
        vertical: overlapFraction,
      ),
      rotation: _rotation,
    );

    return plan.panels
        .map((p) => _PanelPosition(
              ra: p.center.ra,
              dec: p.center.dec,
              index: p.index,
              row: p.row,
              col: p.column,
              enabled: !_disabledPanels.contains(p.index),
            ))
        .toList();
  }

  double _calculateTotalTime(double exposureSecs, int exposuresPerPanel) {
    final activePanels =
        _panelsHorizontal * _panelsVertical - _disabledPanels.length;
    final timePerPanel = exposureSecs * exposuresPerPanel;
    const overheadPerPanel = 60.0;
    return activePanels * (timePerPanel + overheadPerPanel);
  }

  void _generateMosaic() {
    const mosaicService = MosaicService();

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

    final validation = mosaicService.validateMosaic(config);
    if (!validation.isValid) {
      _showValidationDialog(validation);
      return;
    }

    if (validation.hasWarnings) {
      _showWarningsDialog(validation, () {
        _createSequence(mosaicService, config);
      });
      return;
    }

    _createSequence(mosaicService, config);
  }

  void _createSequence(MosaicService mosaicService, MosaicConfig config) {
    final exposure = mosaicWizardExposureSettingsForContext(
      ref.read(smartNightExposureContextProvider).valueOrNull,
    );

    const options = MosaicSequenceOptions(
      serpentineOrdering: true,
      centerAfterSlew: true,
      autofocusPerPanel: false,
    );

    final nodes = mosaicService.createMosaicSequence(
      mosaicName:
          'Mosaic ${_centerRa.toStringAsFixed(2)}h ${_centerDec.toStringAsFixed(1)}°',
      config: config,
      exposure: exposure,
      options: options,
    );

    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    final rootNode = nodes.values.firstWhere(
      (node) => node is InstructionSetNode && node.parentId == null,
    );

    if (ref.read(currentSequenceProvider) == null) {
      sequenceNotifier.createSequence(name: 'New Mosaic Sequence');
    }

    final disabledChildIds = _disabledTargetSubtreeIds(nodes, rootNode);

    for (final node in nodes.values) {
      if (disabledChildIds.contains(node.id)) continue;

      if (node.id != rootNode.id) {
        sequenceNotifier.addNode(node, parentId: node.parentId);
      } else {
        final currentSeq = ref.read(currentSequenceProvider);
        if (currentSeq != null) {
          for (final childId in rootNode.childIds) {
            if (disabledChildIds.contains(childId)) continue;
            final child = nodes[childId];
            if (child != null) {
              sequenceNotifier.addNode(child, parentId: currentSeq.rootNodeId);
            }
          }
        }
      }
    }

    Navigator.of(context).pop();

    if (mounted) {
      final activePanels = config.totalPanels - _disabledPanels.length;
      context.showSuccessSnackBar('Generated mosaic with $activePanels panels');
    }
  }

  /// Find the set of node IDs that correspond to user-disabled panels
  /// in the visual planner. MosaicService labels its per-panel
  /// TargetHeaders deterministically via MosaicPanelInfo.panelIndex
  /// (0-based, row-major), so we walk the generated node map and
  /// match by panelIndex.
  Set<String> _disabledTargetSubtreeIds(
    Map<String, SequenceNode> nodes,
    SequenceNode rootNode,
  ) {
    if (_disabledPanels.isEmpty) return const {};

    final disabled = <String>{};
    for (final node in nodes.values) {
      if (node is TargetHeaderNode) {
        final panelIndex = node.mosaicPanel?.panelIndex;
        if (panelIndex != null && _disabledPanels.contains(panelIndex)) {
          disabled.add(node.id);
          _collectDescendants(nodes, node.id, disabled);
        }
      }
    }
    return disabled;
  }

  void _collectDescendants(
    Map<String, SequenceNode> nodes,
    String parentId,
    Set<String> sink,
  ) {
    final parent = nodes[parentId];
    if (parent == null) return;
    for (final childId in parent.childIds) {
      if (sink.add(childId)) {
        _collectDescendants(nodes, childId, sink);
      }
    }
  }

  void _showValidationDialog(MosaicValidation validation) {
    showDialog(
      context: context,
      builder: (context) {
        final colors = NightshadeColors.of(context);
        return AlertDialog(
          title: const Text('Invalid Mosaic Configuration'),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              context,
              designMaxWidth: 480,
              designMaxHeight: 400,
            ),
            child: SingleChildScrollView(
              child: Column(
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
                            Icon(Icons.error, color: colors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(error)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'OK',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
          ],
        );
      },
    );
  }

  void _showWarningsDialog(
      MosaicValidation validation, VoidCallback onProceed) {
    showDialog(
      context: context,
      builder: (context) {
        final colors = NightshadeColors.of(context);
        return NightshadeDialog(
          title: 'Mosaic Warnings',
          icon: Icons.warning_amber,
          width: 480,
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () {
                Navigator.of(context).pop();
                onProceed();
              },
              label: 'Proceed',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
          child: Column(
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
                        Icon(Icons.warning, color: colors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(warning)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              const Text('Do you want to proceed anyway?'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final panels = _calculatePanels();
    final exposure = mosaicWizardExposureSettingsForContext(
      ref.watch(smartNightExposureContextProvider).valueOrNull,
    );

    return NightshadeDialog(
      title: 'Mosaic Wizard',
      icon: Icons.grid_on,
      width: 960,
      height: 720,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: _generateMosaic,
          icon: Icons.add,
          label: 'Generate Mosaic',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
      child: Row(
        children: [
          SizedBox(
            width: AdaptiveDialogConstraints.clampPanelWidth(
              context,
              designWidth: 340,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_resumableMosaicCheckpoint != null) ...[
                    _buildResumeBanner(_resumableMosaicCheckpoint!, colors),
                    const SizedBox(height: 20),
                  ],
                  _GridSizer(
                    colors: colors,
                    rows: _panelsVertical,
                    cols: _panelsHorizontal,
                    overlapPercent: _overlapPercent,
                    rotation: _rotation,
                    onChange: ({
                      int? rows,
                      int? cols,
                      double? overlap,
                      double? rotation,
                    }) {
                      setState(() {
                        if (rows != null) _panelsVertical = rows;
                        if (cols != null) _panelsHorizontal = cols;
                        if (overlap != null) _overlapPercent = overlap;
                        if (rotation != null) _rotation = rotation;
                        _disabledPanels.removeWhere(
                            (i) => i >= _panelsHorizontal * _panelsVertical);
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _StatsCard(
                    colors: colors,
                    activePanels: _panelsHorizontal * _panelsVertical -
                        _disabledPanels.length,
                    gridLabel: '$_panelsHorizontal×$_panelsVertical',
                    panelArcminLabel:
                        '${(_panelWidthArcmin / 60).toStringAsFixed(2)}° × ${(_panelHeightArcmin / 60).toStringAsFixed(2)}°',
                    overlapLabel: '${_overlapPercent.toStringAsFixed(0)}%',
                    exposureSeconds: exposure.exposureSeconds,
                    exposuresPerPanel: exposure.exposuresPerPanel,
                    estTimeHours: _calculateTotalTime(
                          exposure.exposureSeconds,
                          exposure.exposuresPerPanel,
                        ) /
                        3600,
                    totalExposures: (_panelsHorizontal * _panelsVertical -
                            _disabledPanels.length) *
                        exposure.exposuresPerPanel,
                  ),
                  const SizedBox(height: 16),
                  _AdvancedPanel(
                    colors: colors,
                    expanded: _advancedExpanded,
                    centerRa: _centerRa,
                    centerDec: _centerDec,
                    panelWidthArcmin: _panelWidthArcmin,
                    panelHeightArcmin: _panelHeightArcmin,
                    onToggle: () =>
                        setState(() => _advancedExpanded = !_advancedExpanded),
                    onChanged: ({
                      double? centerRa,
                      double? centerDec,
                      double? panelWidthArcmin,
                      double? panelHeightArcmin,
                    }) {
                      setState(() {
                        if (centerRa != null) _centerRa = centerRa;
                        if (centerDec != null) _centerDec = centerDec;
                        if (panelWidthArcmin != null) {
                          _panelWidthArcmin = panelWidthArcmin;
                        }
                        if (panelHeightArcmin != null) {
                          _panelHeightArcmin = panelHeightArcmin;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _VisualMosaicPlanner(
                key: const ValueKey('mosaic_visual_planner'),
                colors: colors,
                centerRa: _centerRa,
                centerDec: _centerDec,
                panels: panels,
                panelWidthArcmin: _panelWidthArcmin,
                panelHeightArcmin: _panelHeightArcmin,
                rotation: _rotation,
                onPanelToggle: (idx) {
                  setState(() {
                    if (_disabledPanels.contains(idx)) {
                      _disabledPanels.remove(idx);
                    } else {
                      _disabledPanels.add(idx);
                    }
                  });
                },
                onDragCenter: (dRaHours, dDecDeg) {
                  setState(() {
                    _centerRa = (_centerRa + dRaHours) % 24.0;
                    if (_centerRa < 0) _centerRa += 24;
                    _centerDec = (_centerDec + dDecDeg).clamp(-90.0, 90.0);
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeBanner(CheckpointInfo info, NightshadeColors colors) {
    final ageMinutes = info.ageSeconds ~/ 60;
    final ageStr = ageMinutes < 60
        ? '${ageMinutes}m ago'
        : '${ageMinutes ~/ 60}h ${ageMinutes % 60}m ago';
    final integrationMins = (info.completedIntegrationSecs / 60).round();
    return Container(
      key: const ValueKey('mosaic_resume_banner'),
      padding: const EdgeInsets.all(16),
      decoration: NightshadeDecorations.iconChip(
        colors.warning,
        borderRadius: BorderRadius.circular(8),
        borderAlpha: 0.4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay_circle_filled, color: colors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resume previous mosaic?',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${info.sequenceName}" was interrupted $ageStr. '
            '${info.completedExposures} frames captured (${integrationMins}m '
            'integration). Resuming picks up at the next unfinished panel.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                onPressed: _resumeInterruptedMosaic,
                icon: Icons.play_arrow,
                label: 'Resume',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
              ),
              NightshadeButton(
                onPressed: _discardMosaicCheckpoint,
                icon: Icons.delete_outline,
                label: 'Start Over',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Configuration widgets
// ============================================================================

class _GridSizer extends StatelessWidget {
  final NightshadeColors colors;
  final int rows;
  final int cols;
  final double overlapPercent;
  final double rotation;
  final void Function({
    int? rows,
    int? cols,
    double? overlap,
    double? rotation,
  }) onChange;

  const _GridSizer({
    required this.colors,
    required this.rows,
    required this.cols,
    required this.overlapPercent,
    required this.rotation,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grid', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _IntStepper(
                  colors: colors,
                  label: 'Columns',
                  value: cols,
                  min: 1,
                  max: 10,
                  onChanged: (v) => onChange(cols: v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IntStepper(
                  colors: colors,
                  label: 'Rows',
                  value: rows,
                  min: 1,
                  max: 10,
                  onChanged: (v) => onChange(rows: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SliderRow(
            colors: colors,
            label: 'Overlap',
            value: overlapPercent,
            min: 0,
            max: 50,
            suffix: '%',
            onChanged: (v) => onChange(overlap: v),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            colors: colors,
            label: 'Rotation',
            value: rotation,
            min: -180,
            max: 180,
            suffix: '°',
            onChanged: (v) => onChange(rotation: v),
          ),
        ],
      ),
    );
  }
}

class _IntStepper extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _IntStepper({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary)),
        const SizedBox(height: 4),
        Row(
          children: [
            _StepperButton(
              colors: colors,
              icon: LucideIcons.minus,
              enabled: value > min,
              onTap: () => onChanged(value - 1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            _StepperButton(
              colors: colors,
              icon: LucideIcons.plus,
              enabled: value < max,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.colors,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
            color: enabled ? colors.surfaceAlt : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? colors.textPrimary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: colors.textSecondary)),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(0)}$suffix',
              style: TextStyle(
                  fontSize: 12,
                  color: colors.primary,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final NightshadeColors colors;
  final int activePanels;
  final String gridLabel;
  final String panelArcminLabel;
  final String overlapLabel;
  final double exposureSeconds;
  final int exposuresPerPanel;
  final double estTimeHours;
  final int totalExposures;

  const _StatsCard({
    required this.colors,
    required this.activePanels,
    required this.gridLabel,
    required this.panelArcminLabel,
    required this.overlapLabel,
    required this.exposureSeconds,
    required this.exposuresPerPanel,
    required this.estTimeHours,
    required this.totalExposures,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan summary', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _row('Active panels:', '$activePanels'),
          _row('Grid:', gridLabel),
          _row('Panel size:', panelArcminLabel),
          _row('Overlap:', overlapLabel),
          const Divider(height: 16),
          _row(
              'Est. time (${exposureSeconds.toStringAsFixed(0)}s x $exposuresPerPanel):',
              '${estTimeHours.toStringAsFixed(1)} h',
              highlight: true),
          _row('Total exposures:', '$totalExposures'),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              )),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 14 : 12,
              color: highlight ? colors.accent : colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  final NightshadeColors colors;
  final bool expanded;
  final double centerRa;
  final double centerDec;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final VoidCallback onToggle;
  final void Function({
    double? centerRa,
    double? centerDec,
    double? panelWidthArcmin,
    double? panelHeightArcmin,
  }) onChanged;

  const _AdvancedPanel({
    required this.colors,
    required this.expanded,
    required this.centerRa,
    required this.centerDec,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(LucideIcons.sliders, size: 14, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Advanced (numerical)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        )),
                  ),
                  Icon(
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  _NumberField(
                    colors: colors,
                    label: 'Center RA (hours)',
                    value: centerRa,
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (v) => onChanged(centerRa: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Center Dec (degrees)',
                    value: centerDec,
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (v) => onChanged(centerDec: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Panel width (arcmin)',
                    value: panelWidthArcmin,
                    min: 1,
                    max: 360,
                    decimals: 1,
                    onChanged: (v) => onChanged(panelWidthArcmin: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Panel height (arcmin)',
                    value: panelHeightArcmin,
                    min: 1,
                    max: 360,
                    decimals: 1,
                    onChanged: (v) => onChanged(panelHeightArcmin: v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final NightshadeColors colors;
  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(
        text: widget.value.toStringAsFixed(widget.decimals));
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    final external = widget.value.toStringAsFixed(widget.decimals);
    final current = double.tryParse(_ctl.text);
    if (current == null || (current - widget.value).abs() > 1e-3) {
      _ctl.text = external;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: OutlineInputBorder(
            borderSide: BorderSide(color: widget.colors.border)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

// ============================================================================
// Visual planner — interactive sky view with FOV panels
// ============================================================================

class _PanelPosition {
  final double ra;
  final double dec;
  final int index;
  final int row;
  final int col;
  final bool enabled;

  _PanelPosition({
    required this.ra,
    required this.dec,
    required this.index,
    required this.row,
    required this.col,
    required this.enabled,
  });
}

class _VisualMosaicPlanner extends StatefulWidget {
  final NightshadeColors colors;
  final double centerRa;
  final double centerDec;
  final List<_PanelPosition> panels;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final double rotation;
  final ValueChanged<int> onPanelToggle;

  /// Drag callback: (deltaRaHours, deltaDecDegrees).
  final void Function(double dRaHours, double dDecDeg) onDragCenter;

  const _VisualMosaicPlanner({
    super.key,
    required this.colors,
    required this.centerRa,
    required this.centerDec,
    required this.panels,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.rotation,
    required this.onPanelToggle,
    required this.onDragCenter,
  });

  @override
  State<_VisualMosaicPlanner> createState() => _VisualMosaicPlannerState();
}

class _VisualMosaicPlannerState extends State<_VisualMosaicPlanner> {
  double _zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final basePxPerDeg = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            ) /
            8.0;
        final pxPerDeg = basePxPerDeg * _zoom;

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _StarFieldPainter(),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _RaDecGridPainter(
                  pxPerDeg: pxPerDeg,
                ),
              ),
            ),
            Positioned.fill(
              child: _PanelLayer(
                colors: widget.colors,
                centerRa: widget.centerRa,
                centerDec: widget.centerDec,
                panels: widget.panels,
                panelWidthArcmin: widget.panelWidthArcmin,
                panelHeightArcmin: widget.panelHeightArcmin,
                rotation: widget.rotation,
                pxPerDeg: pxPerDeg,
                onPanelToggle: widget.onPanelToggle,
                onDragCenter: widget.onDragCenter,
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _CoordHud(
                ra: widget.centerRa,
                dec: widget.centerDec,
                rotation: widget.rotation,
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: _ZoomControls(
                zoom: _zoom,
                onZoomIn: () =>
                    setState(() => _zoom = (_zoom * 1.4).clamp(0.25, 4.0)),
                onZoomOut: () =>
                    setState(() => _zoom = (_zoom / 1.4).clamp(0.25, 4.0)),
                onReset: () => setState(() => _zoom = 1.0),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: _Legend(colors: widget.colors),
            ),
          ],
        );
      },
    );
  }
}

class _CoordHud extends StatelessWidget {
  final double ra;
  final double dec;
  final double rotation;

  const _CoordHud({
    required this.ra,
    required this.dec,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'RA ${ra.toStringAsFixed(3)}h   Dec ${dec.toStringAsFixed(2)}°   '
        'Rot ${rotation.toStringAsFixed(0)}°',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final NightshadeColors colors;
  const _Legend({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.move, size: 11, color: colors.primary),
          const SizedBox(width: 4),
          const Text('Drag centre',
              style: TextStyle(color: Colors.white70, fontSize: 10)),
          const SizedBox(width: 12),
          Icon(LucideIcons.mousePointerClick, size: 11, color: colors.accent),
          const SizedBox(width: 4),
          const Text('Tap panel to toggle',
              style: TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            onPressed: onZoomIn,
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          Text('${(zoom * 100).round()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 9)),
          IconButton(
            icon: const Icon(Icons.remove, size: 14),
            onPressed: onZoomOut,
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, size: 14),
            onPressed: onReset,
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}

class _PanelLayer extends StatelessWidget {
  final NightshadeColors colors;
  final double centerRa;
  final double centerDec;
  final List<_PanelPosition> panels;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final double rotation;
  final double pxPerDeg;
  final ValueChanged<int> onPanelToggle;
  final void Function(double dRaHours, double dDecDeg) onDragCenter;

  const _PanelLayer({
    required this.colors,
    required this.centerRa,
    required this.centerDec,
    required this.panels,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.rotation,
    required this.pxPerDeg,
    required this.onPanelToggle,
    required this.onDragCenter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final centerPx = Offset(
        constraints.maxWidth / 2,
        constraints.maxHeight / 2,
      );

      return GestureDetector(
        onPanUpdate: (details) {
          final dxDeg = details.delta.dx / pxPerDeg;
          final dyDeg = details.delta.dy / pxPerDeg;
          final decRad = centerDec * math.pi / 180.0;
          final cosDec =
              math.cos(decRad).abs() < 0.001 ? 0.001 : math.cos(decRad);
          // Dragging right moves the visible sky right, i.e. the
          // mosaic centre shifts to lower RA. dy follows screen
          // coordinates (down = negative dec).
          final dRaHours = -dxDeg / 15.0 / cosDec;
          final dDecDeg = dyDeg;
          onDragCenter(dRaHours, dDecDeg);
        },
        child: Stack(
          children: [
            for (final p in panels) _panelWidget(p, centerPx),
            Positioned(
              left: centerPx.dx - 6,
              top: centerPx.dy - 6,
              child: IgnorePointer(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textPrimary, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _panelWidget(_PanelPosition p, Offset centerPx) {
    final dRaDeg = (p.ra - centerRa) * 15;
    final dDecDeg = p.dec - centerDec;
    final decRad = centerDec * math.pi / 180.0;
    final cosDec = math.cos(decRad);
    final dxDeg = dRaDeg * cosDec;
    final dyDeg = -dDecDeg;

    final panelCenterPx = centerPx +
        Offset(
          dxDeg * pxPerDeg,
          dyDeg * pxPerDeg,
        );
    final pxWidth = (panelWidthArcmin / 60.0) * pxPerDeg;
    final pxHeight = (panelHeightArcmin / 60.0) * pxPerDeg;

    return Positioned(
      left: panelCenterPx.dx - pxWidth / 2,
      top: panelCenterPx.dy - pxHeight / 2,
      child: Transform.rotate(
        angle: rotation * math.pi / 180.0,
        child: GestureDetector(
          onTap: () => onPanelToggle(p.index),
          child: Container(
            width: pxWidth,
            height: pxHeight,
            decoration: BoxDecoration(
              color: p.enabled
                  ? colors.primary.withValues(alpha: 0.18)
                  : Colors.grey.withValues(alpha: 0.05),
              border: Border.all(
                color: p.enabled
                    ? colors.primary
                    : Colors.grey.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                '${p.index + 1}',
                style: TextStyle(
                  fontSize: math.max(10, pxWidth * 0.12),
                  color: p.enabled ? colors.textPrimary : Colors.white24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Painters
// ============================================================================

class _StarFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint();
    for (var i = 0; i < 200; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final brightness = rng.nextDouble() * 0.4 + 0.1;
      final radius = rng.nextDouble() * 1.2 + 0.3;
      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => false;
}

class _RaDecGridPainter extends CustomPainter {
  final double pxPerDeg;

  _RaDecGridPainter({required this.pxPerDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var d = 1.0; d * pxPerDeg < size.width; d += 1.0) {
      canvas.drawLine(Offset(cx - d * pxPerDeg, 0),
          Offset(cx - d * pxPerDeg, size.height), paint);
      canvas.drawLine(Offset(cx + d * pxPerDeg, 0),
          Offset(cx + d * pxPerDeg, size.height), paint);
    }
    for (var d = 1.0; d * pxPerDeg < size.height; d += 1.0) {
      canvas.drawLine(Offset(0, cy - d * pxPerDeg),
          Offset(size.width, cy - d * pxPerDeg), paint);
      canvas.drawLine(Offset(0, cy + d * pxPerDeg),
          Offset(size.width, cy + d * pxPerDeg), paint);
    }
    paint.color = Colors.white.withValues(alpha: 0.18);
    paint.strokeWidth = 1.0;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
  }

  @override
  bool shouldRepaint(covariant _RaDecGridPainter oldDelegate) =>
      oldDelegate.pxPerDeg != pxPerDeg;
}
