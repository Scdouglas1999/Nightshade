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
import '../../../utils/authority_bound_dialog.dart';
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

/// Where the wizard's panel size came from.
enum _PanelSizeSource {
  /// Neither the rig nor the user has supplied one — the wizard must not
  /// quote a panel size or build anything from it.
  unknown,

  /// Derived from the active profile's focal length + the connected camera's
  /// sensor geometry (the same inputs the framing box uses).
  measured,

  /// Typed into the Advanced section by the user.
  user,
}

MosaicExposureSettings mosaicWizardExposureSettingsForContext(
  SmartNightExposureContext? exposureContext,
) =>
    smartNightMosaicExposureSettings(exposureContext);

class _MosaicWizardDialogState extends ConsumerState<MosaicWizardDialog> {
  late double _centerRa;
  late double _centerDec;

  /// One panel = one camera field. These are seeded from the rig in
  /// [initState] and are only a PLACEHOLDER until then: 60' × 40' is not
  /// anyone's camera, it was just the field initialiser, and the wizard used
  /// to quote it as "Panel size: 1.00° × 0.67°" and plan the whole mosaic
  /// from it on a machine with no equipment profile at all. [_panelSizeSource]
  /// records where the numbers came from so the UI can say "unknown" and the
  /// build actions can refuse, instead of inventing a field of view — the
  /// same rule the framing dialog already follows.
  double _panelWidthArcmin = 60.0;
  double _panelHeightArcmin = 40.0;
  _PanelSizeSource _panelSizeSource = _PanelSizeSource.unknown;

  bool get _panelSizeKnown => _panelSizeSource != _PanelSizeSource.unknown;
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
  bool _isCreatingProject = false;
  String? _checkpointAction;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _authorityGeneration = 0;

  bool get _isBusy => _isCreatingProject || _checkpointAction != null;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _authorityGeneration++;
        closeAuthorityBoundDialog(context);
      },
    );
    _centerRa = widget.initialRa ?? 0.0;
    _centerDec = widget.initialDec ?? 0.0;
    // Seed the panel size from the rig: focal length (profile) + sensor
    // geometry (connected camera). `fieldOfView` is null unless BOTH are
    // known, which is exactly when we must admit we don't know.
    final fov = ref.read(opticalConfigProvider)?.fieldOfView;
    if (fov != null && fov.$1 > 0 && fov.$2 > 0) {
      _panelWidthArcmin = fov.$1 * 60.0;
      _panelHeightArcmin = fov.$2 * 60.0;
      _panelSizeSource = _PanelSizeSource.measured;
    }
    // Start the checkpoint probe AFTER the first frame, never inline in
    // initState. Its error path calls `context.showErrorSnackBar`, which reads
    // an inherited Theme — and when the backend throws before the first `await`
    // suspension (a disconnected/erroring backend does exactly that), that
    // catch runs while initState is still on the stack, tripping
    // "dependOnInheritedWidgetOfExactType() was called before
    // initState() completed" and taking the whole dialog down instead of
    // showing a snackbar. The probe only decides whether to show a resume
    // banner, so a frame's delay costs nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_probeForInterruptedMosaic());
    });
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  bool _isCurrentAuthority(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _authorityGeneration &&
      identical(ref.read(backendProvider), backend);

  Future<void> _probeForInterruptedMosaic() async {
    final authority = ref.read(backendProvider);
    final generation = _authorityGeneration;
    try {
      final backend = ref.read(sequencerBackendProvider);
      final hasCheckpoint = await backend.hasCheckpoint();
      if (!_isCurrentAuthority(authority, generation)) return;
      if (!hasCheckpoint) return;
      final info = await backend.getCheckpointInfo();
      if (!_isCurrentAuthority(authority, generation)) return;
      final isMosaic = info != null &&
          info.canResume &&
          info.sequenceName.startsWith('Mosaic ');
      if (isMosaic) {
        setState(() => _resumableMosaicCheckpoint = info);
      }
    } catch (e) {
      if (mounted && _isCurrentAuthority(authority, generation)) {
        context.showErrorSnackBar(
          'Could not check for interrupted mosaic: $e',
        );
      }
    }
  }

  Future<void> _resumeInterruptedMosaic() async {
    if (_checkpointAction != null) return;
    setState(() => _checkpointAction = 'resume');
    try {
      // Route through the SequenceExecutor provider — it re-seeds the
      // runtime config from current settings and issues the
      // sequencerStart() that actually begins execution. Calling the
      // backend's resumeFromCheckpoint() directly only prepares the
      // native tree and leaves the executor idle.
      await ref.read(sequenceExecutorProvider).resumeFromCheckpoint();
      if (mounted) {
        setState(() => _checkpointAction = null);
        Navigator.of(context).pop();
        context.showSuccessSnackBar('Resuming mosaic from checkpoint…');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkpointAction = null);
        context.showErrorSnackBar('Failed to resume mosaic: $e');
      }
    }
  }

  Future<void> _discardMosaicCheckpoint() async {
    if (_checkpointAction != null) return;
    setState(() => _checkpointAction = 'discard');
    final backend = ref.read(sequencerBackendProvider);
    try {
      await backend.discardCheckpoint();
      if (mounted) {
        setState(() {
          _checkpointAction = null;
          _resumableMosaicCheckpoint = null;
        });
        context.showSuccessSnackBar('Mosaic checkpoint discarded.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkpointAction = null);
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

    final disabledChildIds = _disabledTargetSubtreeIds(nodes, rootNode);
    final enabledNodes = Map<String, SequenceNode>.fromEntries(
      nodes.entries.where((entry) => !disabledChildIds.contains(entry.key)),
    );

    try {
      if (ref.read(currentSequenceProvider) == null) {
        sequenceNotifier.createSequence(name: 'New Mosaic Sequence');
      }
      final currentRootId = ref.read(currentSequenceProvider)?.rootNodeId;
      if (currentRootId == null) {
        throw StateError('The current sequence has no root node');
      }

      // MosaicService emits a complete graph whose descendants are inserted
      // before their parents in map order. Merge the graph atomically instead
      // of replaying addNode in that order (which attached children to the
      // current root and duplicated panel headers).
      sequenceNotifier.mergeTemplateNodes(
        templateNodes: enabledNodes,
        templateRootId: rootNode.id,
        targetId: currentRootId,
      );
    } on SequenceLockedException catch (error) {
      context.showErrorSnackBar(error.message);
      return;
    } catch (error) {
      context.showErrorSnackBar('Could not load mosaic: $error');
      return;
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
        disabledCells: {..._disabledPanels},
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
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend || backend is DisconnectedBackend) {
      _showMosaicProjectHostOnlyMessage();
      return;
    }
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
    if (_isCreatingProject) return;
    final authority = ref.read(backendProvider);
    if (authority is NetworkBackend || authority is DisconnectedBackend) {
      _showMosaicProjectHostOnlyMessage();
      return;
    }
    setState(() => _isCreatingProject = true);
    final controller = MosaicProjectCreationController(
      ref.read(mosaicProjectServiceProvider),
    );
    try {
      final projectId = await controller.createProject(_currentDesign());
      if (!mounted) return;
      if (!identical(ref.read(backendProvider), authority)) {
        setState(() => _isCreatingProject = false);
        return;
      }
      setState(() => _isCreatingProject = false);
      Navigator.of(context).pop();
      unawaited(context.push('/mosaic/$projectId'));
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingProject = false);
        context.showErrorSnackBar('Could not create mosaic project: $e');
      }
    }
  }

  void _showMosaicProjectHostOnlyMessage() {
    context.showInfoSnackBar(
      'Create durable mosaic projects on the imaging host. You can still load '
      'this mosaic into the host sequencer from here.',
    );
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
    final backend = ref.watch(backendProvider);
    final isRemote = backend is NetworkBackend;
    final isDisconnected = backend is DisconnectedBackend;
    final canCreateProject = !isRemote && !isDisconnected;
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
      closeEnabled: !_isBusy,
      width: 960,
      height: 720,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        NightshadeButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        // Secondary path, unchanged: expand the grid into the live sequencer's
        // capture tree (no durable project row). Tooltip disambiguates the two
        // near-identical primary actions for the user, not just in code.
        Tooltip(
          message: _panelSizeKnown
              ? 'Add these panels to the current sequence now'
              : 'Panel size unknown — set a focal length and connect the '
                  'camera, or enter it under Advanced',
          child: NightshadeButton(
            key: const ValueKey('mosaic_generate_sequence_btn'),
            onPressed: _isBusy || !_panelSizeKnown ? null : _generateMosaic,
            icon: NightshadeIcons.add,
            label: 'Load into Sequencer',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
          ),
        ),
        // Primary path: persist the design as a durable mosaic project and open
        // the project screen (/mosaic/:id).
        Tooltip(
          message: isRemote
              ? 'Durable mosaic projects are managed on the imaging host'
              : isDisconnected
                  ? 'Connect to an imaging host before creating a durable project'
                  : !_panelSizeKnown
                      ? 'Panel size unknown — set a focal length and connect '
                          'the camera, or enter it under Advanced'
                      : 'Save a reusable project and track its progress',
          child: NightshadeButton(
            key: const ValueKey('mosaic_create_project_btn'),
            onPressed: _isBusy || !canCreateProject || !_panelSizeKnown
                ? null
                : () => unawaited(_createMosaicProject()),
            icon: NightshadeIcons.layoutGrid,
            label: isRemote
                ? 'Create on imaging host'
                : isDisconnected
                    ? 'Connect to create project'
                    : 'Create mosaic project',
            isLoading: _isCreatingProject,
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
                  if (!_panelSizeKnown) ...[
                    _buildUnknownPanelSizeBanner(colors),
                    const SizedBox(height: 20),
                  ],
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
                    panelArcminLabel: _panelSizeKnown
                        ? '${(_panelWidthArcmin / 60).toStringAsFixed(2)}° × ${(_panelHeightArcmin / 60).toStringAsFixed(2)}°'
                        : 'unknown',
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
                        // An explicit panel size is a legitimate answer to
                        // "what field does one panel cover?" — it just has to
                        // come from the user rather than from a field
                        // initialiser nobody chose.
                        if (panelWidthArcmin != null ||
                            panelHeightArcmin != null) {
                          _panelSizeSource = _PanelSizeSource.user;
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

  /// Shown while the panel size is neither measured from the rig nor supplied
  /// by the user. Wording mirrors the framing dialog, which already refuses to
  /// guess a field of view, so the two surfaces tell the same story.
  Widget _buildUnknownPanelSizeBanner(NightshadeColors colors) {
    final config = ref.watch(opticalConfigProvider);
    final reason = config == null ||
            config.focalLength == null ||
            config.focalLength! <= 0
        ? 'No equipment profile with a focal length — set one in Settings to '
            'size a panel.'
        : 'No camera connected, so the sensor size is unknown. Connect the '
            'camera, or enter the panel size under Advanced.';
    return Container(
      key: const ValueKey('mosaic_unknown_panel_size_banner'),
      padding: const EdgeInsets.all(16),
      decoration: NightshadeDecorations.iconChip(
        colors.warning,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        borderAlpha: 0.4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(NightshadeIcons.warning, color: colors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel size unknown',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$reason A mosaic cannot be planned until one panel\'s field '
                  'is known.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13,
                  ),
                ),
              ],
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
                onPressed:
                    _checkpointAction == null ? _resumeInterruptedMosaic : null,
                icon: NightshadeIcons.play,
                label: 'Resume',
                isLoading: _checkpointAction == 'resume',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
              ),
              NightshadeButton(
                onPressed:
                    _checkpointAction == null ? _discardMosaicCheckpoint : null,
                icon: NightshadeIcons.delete,
                label: 'Start Over',
                isLoading: _checkpointAction == 'discard',
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
