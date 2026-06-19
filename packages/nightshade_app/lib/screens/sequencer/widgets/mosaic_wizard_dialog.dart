// Mosaic Wizard, powered by the planetarium's mosaic planner.
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
// The generated `MosaicConfig` shape is identical to the one produced
// by the earlier text-only wizard, so the executor and resume logic
// don't change.
//
// The mosaic-resume banner remains at the top of the dialog — see
// `_buildResumeBanner` below.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium;
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:go_router/go_router.dart';

import '../../../utils/snackbar_helper.dart';
import 'mosaic_wizard_dialog/mosaic_project_creation_controller.dart';
part 'mosaic_wizard_dialog/config_controls.dart';
part 'mosaic_wizard_dialog/panel_position.dart';
part 'mosaic_wizard_dialog/visual_planner.dart';
part 'mosaic_wizard_dialog/painters.dart';

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

  /// Multi-filter plan. When [_multiFilterEnabled] is false (the default,
  /// simple path) the wizard images each panel with the Smart-Night
  /// single-filter recommendation exactly as before. When the user enables it,
  /// every panel is imaged through each entry of [_filterRows] in order, and
  /// the built sequence + time/exposure estimates use that per-filter plan.
  bool _multiFilterEnabled = false;

  /// The per-filter exposure plan, edited in the Filters card. Seeded lazily on
  /// first enable from the active profile's filters (or a single "Light" row)
  /// so the user starts from something sensible rather than an empty list.
  final List<_MosaicFilterRow> _filterRows = <_MosaicFilterRow>[];

  /// Grid cells the user has disabled by tapping, keyed by (row, col) rather
  /// than flat index. Keying by position means a grid resize drops only the
  /// cells that genuinely no longer exist (row/col out of range) instead of
  /// silently re-pointing a flat index at a different physical panel. The
  /// canonical recipe still generates every panel; disabled cells are skipped
  /// when the sequence is built. This lets users drop the corner panel that
  /// intersects with a tree without rebuilding the grid.
  final Set<({int row, int col})> _disabledPanels = <({int row, int col})>{};

  /// Holds the resumable checkpoint info when an interrupted mosaic
  /// sequence is detected. `null` while loading and when no mosaic
  /// checkpoint exists.
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
      final backend = ref.read(sequencerBackendProvider);
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
    try {
      // Route through the SequenceExecutor provider — it re-seeds the
      // runtime config from current settings and issues the
      // sequencerStart() that actually begins execution. Calling the
      // backend's resumeFromCheckpoint() directly only prepares the
      // native tree and leaves the executor idle.
      await ref.read(sequenceExecutorProvider).resumeFromCheckpoint();
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
    final backend = ref.read(sequencerBackendProvider);
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

  /// Memoised spherical panel geometry (centre/row/col, WITHOUT the
  /// disabled overlay). Recomputed only when a geometry input changes, since
  /// [build] runs [_calculatePanels] on every frame and the planner does real
  /// spherical trig per panel.
  List<_PanelPosition>? _cachedGeometry;
  String? _cachedGeometryKey;

  /// Compute panel positions for the visual planner.
  ///
  /// Delegates to the planetarium's `MosaicPlanner.generateRectangularMosaic`
  /// for the actual spherical geometry — that ensures the on-screen
  /// preview matches the framing-view's mosaic overlay (the
  /// planetarium uses the same planner to render its own mosaic
  /// preview). The wizard then maps those panels into the local
  /// `_PanelPosition` shape and overlays the user's enable/disable
  /// toggles.
  ///
  /// The geometry is memoised on its inputs; the disabled-state overlay is a
  /// cheap per-call post-map (it can change every tap without recomputing the
  /// trig) so it stays outside the cache.
  List<_PanelPosition> _calculatePanels() {
    final key = '$_centerRa|$_centerDec|$_panelWidthArcmin|'
        '$_panelHeightArcmin|$_overlapPercent|$_rotation|'
        '$_panelsVertical|$_panelsHorizontal';
    var geometry = _cachedGeometry;
    if (geometry == null || _cachedGeometryKey != key) {
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
      geometry = plan.panels
          .map((p) => _PanelPosition(
                ra: p.center.ra,
                dec: p.center.dec,
                index: p.index,
                row: p.row,
                col: p.column,
                enabled: true,
              ))
          .toList();
      _cachedGeometry = geometry;
      _cachedGeometryKey = key;
    }

    // Cheap disabled overlay — recomputed each call without touching the trig.
    return geometry
        .map((p) => _PanelPosition(
              ra: p.ra,
              dec: p.dec,
              index: p.index,
              row: p.row,
              col: p.col,
              enabled: !_disabledPanels.contains((row: p.row, col: p.col)),
            ))
        .toList();
  }

  /// Number of panels that will actually be captured (grid minus disabled
  /// cells that still exist in the current grid).
  int get _activePanelCount =>
      _panelsHorizontal * _panelsVertical - _disabledPanels.length;

  /// Lazily seed [_filterRows] the first time the user switches to the
  /// multi-filter path, so they start from the rig's actual filters (or a
  /// single "Light" row when no filter wheel is configured) instead of an
  /// empty list. The seed exposure/count come from the same Smart-Night
  /// recommendation the simple path already uses, so flipping the switch never
  /// silently changes the plan until the user edits a row.
  void _seedFilterRowsIfNeeded() {
    if (_filterRows.isNotEmpty) return;
    final exposure = mosaicWizardExposureSettingsForContext(
      ref.read(smartNightExposureContextProvider).valueOrNull,
    );
    final filters = ref.read(profileFiltersProvider);
    if (filters.isEmpty) {
      _filterRows.add(_MosaicFilterRow(
        filterName: exposure.filterName ?? 'Light',
        exposureSeconds: exposure.exposureSeconds,
        count: exposure.exposuresPerPanel,
      ));
    } else {
      for (final name in filters) {
        _filterRows.add(_MosaicFilterRow(
          filterName: name,
          exposureSeconds: exposure.exposureSeconds,
          count: exposure.exposuresPerPanel,
        ));
      }
    }
  }

  /// The exposure plan the built sequence and previews use.
  ///
  /// Returns the legacy single-filter Smart-Night settings on the simple path,
  /// or a [MosaicExposureSettings.multiFilter] plan built from [_filterRows]
  /// (filtered to enabled rows) when the multi-filter path is active. Falls
  /// back to the single-filter settings if multi-filter is on but no row is
  /// enabled, so callers always get a usable plan.
  MosaicExposureSettings _effectiveExposure(MosaicExposureSettings single) {
    if (!_multiFilterEnabled) return single;
    final enabled = _filterRows.where((r) => r.enabled).toList();
    if (enabled.isEmpty) return single;
    return MosaicExposureSettings.multiFilter(
      filters: enabled
          .map((r) => MosaicFilterExposure(
                exposureSeconds: r.exposureSeconds,
                exposuresPerPanel: r.count,
                filterName: r.filterName,
              ))
          .toList(),
    );
  }

  /// Total exposure seconds imaged per panel across every resolved filter.
  double _exposureSecsPerPanel(MosaicExposureSettings exposure) {
    var total = 0.0;
    for (final f in exposure.resolvedFilters) {
      total += f.exposureSeconds * f.exposuresPerPanel;
    }
    return total;
  }

  /// Total subs captured per panel across every resolved filter.
  int _exposuresPerPanel(MosaicExposureSettings exposure) {
    var total = 0;
    for (final f in exposure.resolvedFilters) {
      total += f.exposuresPerPanel;
    }
    return total;
  }

  // Per-panel overhead model. These reflect the [MosaicSequenceOptions] the
  // generator actually emits in [_createSequence] (centerAfterSlew: true,
  // autofocusPerPanel: false) so the preview's estimate agrees with the built
  // sequence instead of using one opaque 60 s lump.
  static const double _slewSecsPerPanel = 30.0;
  static const double _centerSecsPerPanel = 30.0; // plate-solve + recenter
  static const double _autofocusSecsPerPanel = 60.0;

  double _perPanelOverheadSecs({
    required bool centerAfterSlew,
    required bool autofocusPerPanel,
  }) {
    var overhead = _slewSecsPerPanel;
    if (centerAfterSlew) overhead += _centerSecsPerPanel;
    if (autofocusPerPanel) overhead += _autofocusSecsPerPanel;
    return overhead;
  }

  double _calculateTotalTime(double exposureSecsPerPanel) {
    // Mirror the options used by _createSequence so preview == built sequence.
    final overheadPerPanel = _perPanelOverheadSecs(
      centerAfterSlew: true,
      autofocusPerPanel: false,
    );
    return _activePanelCount * (exposureSecsPerPanel + overheadPerPanel);
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
    final exposure = _effectiveExposure(
      mosaicWizardExposureSettingsForContext(
        ref.read(smartNightExposureContextProvider).valueOrNull,
      ),
    );

    final options = MosaicSequenceOptions(
      serpentineOrdering: true,
      centerAfterSlew: true,
      autofocusPerPanel: false,
      // W1 altitude gate: default each panel's minAltitude to the Smart Night
      // floor so every panel TargetHeader carries a `start_when AltitudeAbove`
      // wait (serialized as `min_altitude`) — matching the headless mosaic
      // path. STRENGTHENS the no-daylight/altitude gate for wizard-built
      // mosaics; never weakens the existing Dart Sun gate (W1) or W5.
      minAltitude: const SmartNightSettings().minAltitudeDeg,
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
      context.showSuccessSnackBar(
          'Generated mosaic with $_activePanelCount panels');
    }
  }

  /// The mosaic's display name, shared by the "load into sequencer" path and
  /// the durable-project path so a saved project and its capture sequence line
  /// up by name.
  String get _mosaicName =>
      'Mosaic ${_centerRa.toStringAsFixed(2)}h ${_centerDec.toStringAsFixed(1)}°';

  /// Snapshot the wizard's current on-screen design into the value object the
  /// persist controller consumes. Nothing is recomputed — these are the same
  /// centre/grid/overlap/rotation/FOV the visual planner is drawing right now.
  MosaicProjectDesign _currentDesign() => MosaicProjectDesign(
        name: _mosaicName,
        centerRaHours: _centerRa,
        centerDecDegrees: _centerDec,
        rows: _panelsVertical,
        cols: _panelsHorizontal,
        overlapPercent: _overlapPercent,
        positionAngleDeg: _rotation,
        panelWidthArcmin: _panelWidthArcmin,
        panelHeightArcmin: _panelHeightArcmin,
      );

  /// Persist the current design as a durable [MosaicProject] and route to the
  /// project screen (`/mosaic/:id`).
  ///
  /// This is the primary "Create mosaic project" action: it validates the grid
  /// the same way the "Generate Mosaic" (load-into-sequencer) path does, then
  /// hands the design to [MosaicProjectCreationController] (which forwards it to
  /// the committed `mosaicProjectServiceProvider.createProject`). The
  /// load-into-sequencer path is untouched and still available.
  Future<void> _createMosaicProject() async {
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
      _showWarningsDialog(validation, () => unawaited(_persistProject()));
      return;
    }
    await _persistProject();
  }

  Future<void> _persistProject() async {
    final controller = MosaicProjectCreationController(
      ref.read(mosaicProjectServiceProvider),
    );
    try {
      final projectId = await controller.createProject(_currentDesign());
      if (!mounted) return;
      Navigator.of(context).pop();
      unawaited(context.push('/mosaic/$projectId'));
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not create mosaic project: $e');
      }
    }
  }

  /// Find the set of node IDs that correspond to user-disabled panels
  /// in the visual planner. MosaicService labels its per-panel
  /// TargetHeaders with MosaicPanelInfo carrying row/column, so we walk the
  /// generated node map and match disabled cells by (row, col) — the same
  /// position key the visual planner uses — so a grid resize can never
  /// re-point a stale flat index at the wrong physical panel.
  Set<String> _disabledTargetSubtreeIds(
    Map<String, SequenceNode> nodes,
    SequenceNode rootNode,
  ) {
    if (_disabledPanels.isEmpty) return const {};

    final disabled = <String>{};
    for (final node in nodes.values) {
      if (node is TargetHeaderNode) {
        final panel = node.mosaicPanel;
        if (panel != null &&
            _disabledPanels.contains((row: panel.row, col: panel.column))) {
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
                            Icon(NightshadeIcons.error,
                                color: colors.error, size: 20),
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
          icon: NightshadeIcons.warning,
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
                        Icon(NightshadeIcons.warning,
                            color: colors.warning, size: 20),
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
    final smartExposure = mosaicWizardExposureSettingsForContext(
      ref.watch(smartNightExposureContextProvider).valueOrNull,
    );
    final exposure = _effectiveExposure(smartExposure);
    final exposureSecsPerPanel = _exposureSecsPerPanel(exposure);
    final exposuresPerPanel = _exposuresPerPanel(exposure);

    return NightshadeDialog(
      title: 'Mosaic Wizard',
      icon: NightshadeIcons.grid,
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
        // Secondary path, unchanged: expand the grid into the live sequencer's
        // capture tree (no durable project row). Tooltip disambiguates the two
        // near-identical primary actions for the user, not just in code.
        Tooltip(
          message: 'Add these panels to the current sequence now',
          child: NightshadeButton(
            key: const ValueKey('mosaic_generate_sequence_btn'),
            onPressed: _generateMosaic,
            icon: NightshadeIcons.add,
            label: 'Load into Sequencer',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
          ),
        ),
        // Primary path: persist the design as a durable mosaic project and open
        // the project screen (/mosaic/:id).
        Tooltip(
          message: 'Save a reusable project and track its progress',
          child: NightshadeButton(
            key: const ValueKey('mosaic_create_project_btn'),
            onPressed: () => unawaited(_createMosaicProject()),
            icon: NightshadeIcons.layoutGrid,
            label: 'Create mosaic project',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
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
                        // Drop disabled cells whose row/col no longer exist in
                        // the resized grid (semantically correct — that
                        // physical panel is gone). Surviving cells keep their
                        // disabled state because they are keyed by position.
                        _disabledPanels.removeWhere((cell) =>
                            cell.row >= _panelsVertical ||
                            cell.col >= _panelsHorizontal);
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _StatsCard(
                    colors: colors,
                    activePanels: _activePanelCount,
                    gridLabel: '$_panelsHorizontal×$_panelsVertical',
                    panelArcminLabel:
                        '${(_panelWidthArcmin / 60).toStringAsFixed(2)}° × ${(_panelHeightArcmin / 60).toStringAsFixed(2)}°',
                    overlapLabel: '${_overlapPercent.toStringAsFixed(0)}%',
                    filterCount:
                        exposure.isMultiFilter ? exposure.filters!.length : 1,
                    exposureSecsPerPanel: exposureSecsPerPanel,
                    exposuresPerPanel: exposuresPerPanel,
                    estTimeHours:
                        _calculateTotalTime(exposureSecsPerPanel) / 3600,
                    totalExposures: _activePanelCount * exposuresPerPanel,
                  ),
                  const SizedBox(height: 16),
                  _FilterPlanCard(
                    colors: colors,
                    enabled: _multiFilterEnabled,
                    rows: _filterRows,
                    onToggle: (on) {
                      setState(() {
                        _multiFilterEnabled = on;
                        if (on) _seedFilterRowsIfNeeded();
                      });
                    },
                    onChanged: () => setState(() {}),
                    onAddRow: () {
                      setState(() {
                        _filterRows.add(_MosaicFilterRow(
                          filterName: 'Filter ${_filterRows.length + 1}',
                          exposureSeconds: smartExposure.exposureSeconds,
                          count: smartExposure.exposuresPerPanel,
                        ));
                      });
                    },
                    onRemoveRow: (row) {
                      setState(() => _filterRows.remove(row));
                    },
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
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                onPanelToggle: (panel) {
                  final cell = (row: panel.row, col: panel.col);
                  setState(() {
                    if (_disabledPanels.contains(cell)) {
                      _disabledPanels.remove(cell);
                    } else {
                      _disabledPanels.add(cell);
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        borderAlpha: 0.4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.undo, color: colors.warning, size: 20),
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
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                onPressed: _resumeInterruptedMosaic,
                icon: NightshadeIcons.play,
                label: 'Resume',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
              ),
              NightshadeButton(
                onPressed: _discardMosaicCheckpoint,
                icon: NightshadeIcons.delete,
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
