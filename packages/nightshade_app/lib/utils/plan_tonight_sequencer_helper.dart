import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:uuid/uuid.dart';

/// Build a multi-filter Smart Night sequence for a Plan Tonight target.
Future<SingleTargetSequenceResult> buildPlanTonightTargetSequence({
  required WidgetRef ref,
  required TargetSuggestion target,
  required SessionOptimizationPlan plan,
  bool includeSessionPreamble = false,
}) async {
  return _buildPlanTonightTargetSequenceCore(
    ref: ref,
    target: target,
    includeSessionPreamble: includeSessionPreamble,
  );
}

/// Build a multi-filter sequence from a target suggestion without an optimizer
/// plan (planetarium / annotation paths). Uses default Smart Night budget and
/// tonight's dark window.
Future<SingleTargetSequenceResult>
    buildPlanTonightTargetSequenceFromSuggestion({
  required WidgetRef ref,
  required TargetSuggestion target,
  bool includeSessionPreamble = false,
}) async {
  return _buildPlanTonightTargetSequenceCore(
    ref: ref,
    target: target,
    includeSessionPreamble: includeSessionPreamble,
  );
}

/// Build a multi-filter sequence from the currently framed target.
///
/// This is the Framing screen counterpart to
/// [buildPlanTonightTargetSequenceFromSuggestion]. It preserves the framing
/// rotation on the emitted [TargetHeaderNode] so "frame first, sequence
/// second" does not lose the user's composition.
Future<SingleTargetSequenceResult> buildPlanTonightTargetSequenceFromFraming({
  required WidgetRef ref,
  required FramingTarget target,
  TargetSuggestion? sourceSuggestion,
  double? rotationDegrees,
  bool includeSessionPreamble = false,
}) async {
  final suggestion = sourceSuggestion == null
      ? await framingTargetSuggestion(ref: ref, target: target)
      : sourceSuggestion.copyWith(
          targetName: target.name,
          catalogId: target.catalogId ?? sourceSuggestion.catalogId,
          raHours: target.raHours,
          decDegrees: target.decDegrees,
          objectType: target.type?.displayName ?? sourceSuggestion.objectType,
          magnitude: target.magnitude ?? sourceSuggestion.magnitude,
          sizeArcmin: target.sizeArcmin ?? sourceSuggestion.sizeArcmin,
          constellation: target.constellation ?? sourceSuggestion.constellation,
        );
  final result = await buildPlanTonightTargetSequenceFromSuggestion(
    ref: ref,
    target: suggestion,
    includeSessionPreamble: includeSessionPreamble,
  );
  return _withFramingRotation(result, rotationDegrees);
}

Future<SingleTargetSequenceResult> _buildPlanTonightTargetSequenceCore({
  required WidgetRef ref,
  required TargetSuggestion target,
  double? integrationBudgetHours,
  bool includeSessionPreamble = false,
}) async {
  final profile = ref.read(activeEquipmentProfileProvider);
  if (profile == null) {
    throw const SmartNightBuildException(
      'No equipment profile selected — configure a profile before building '
      'a sequence.',
    );
  }

  final filters = ref.read(effectiveFiltersProvider);
  if (filters.isEmpty) {
    throw const SmartNightBuildException(
      'No filters configured on the equipment profile or connected filter '
      'wheel.',
    );
  }

  final settings = await ref.read(appSettingsProvider.future);
  final exposureContext =
      await ref.read(smartNightExposureContextProvider.future);

  final window = SmartNightService(
    suggestionService: ref.read(targetSuggestionServiceProvider),
    logging: ref.read(loggingServiceProvider),
  ).calculateWindow(
    latitudeDeg: settings.latitude,
    longitudeDeg: settings.longitude,
  );

  final integrationGoals =
      await ref.read(integrationGoalServiceProvider).progressForTarget(
            target.targetId,
          );

  final smartNightSettings = SmartNightSettings(
    defaultIntegrationBudgetHours: integrationBudgetHours ??
        const SmartNightSettings().defaultIntegrationBudgetHours,
    targetSnr: settings.smartNightTargetSnr,
    subExposureCeilingSecs: settings.smartNightSubExposureCeilingSecs,
    subExposureFloorSecs: settings.smartNightSubExposureFloorSecs,
    coolDownTargetC: profile.defaultCoolingTemp ?? -10.0,
    hasCoverCalibrator: profile.coverCalibratorId != null &&
        profile.coverCalibratorId!.trim().isNotEmpty,
  );

  return SmartNightService(
    suggestionService: ref.read(targetSuggestionServiceProvider),
    logging: ref.read(loggingServiceProvider),
  ).buildSingleTargetSequence(
    profile: profile,
    suggestion: target,
    windowStart: window.start,
    windowEnd: window.end,
    availableFilters: filters,
    exposureContext: exposureContext,
    settings: smartNightSettings,
    integrationBudgetHours: integrationBudgetHours,
    integrationGoalProgress: integrationGoals,
    includeSessionPreamble: includeSessionPreamble,
  );
}

/// Build a [TargetSuggestion] from a framed target.
Future<TargetSuggestion> framingTargetSuggestion({
  required WidgetRef ref,
  required FramingTarget target,
}) {
  return catalogTargetSuggestion(
    ref: ref,
    targetName: target.name,
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    catalogId: target.catalogId,
    objectType: target.type?.displayName,
    magnitude: target.magnitude,
    sizeArcmin: target.sizeArcmin,
    constellation: target.constellation,
  );
}

/// Build a [TargetSuggestion] from catalog / planetarium object coordinates.
Future<TargetSuggestion> catalogTargetSuggestion({
  required WidgetRef ref,
  required String targetName,
  required double raHours,
  required double decDegrees,
  String? catalogId,
  String? objectType,
  double? magnitude,
  double? sizeArcmin,
  String? constellation,
  ObjectVisibility? visibility,
}) async {
  final settings = await ref.read(appSettingsProvider.future);
  if (settings.latitude == 0.0 && settings.longitude == 0.0) {
    throw const SmartNightBuildException(
      'No observer location set — configure latitude and longitude in Settings '
      'before building a sequence from the sky chart.',
    );
  }

  final window = SmartNightService(
    suggestionService: ref.read(targetSuggestionServiceProvider),
    logging: ref.read(loggingServiceProvider),
  ).calculateWindow(
    latitudeDeg: settings.latitude,
    longitudeDeg: settings.longitude,
  );

  final objectVisibility = visibility ??
      AstronomyCalculations.calculateObjectVisibility(
        raDeg: raHours * 15.0,
        decDeg: decDegrees,
        date: window.start,
        latitudeDeg: settings.latitude,
        longitudeDeg: settings.longitude,
        minAltitude: const SmartNightSettings().minAltitudeDeg,
      );

  final altAz = AstronomyCalculations.objectAltAz(
    raDeg: raHours * 15.0,
    decDeg: decDegrees,
    dt: window.start,
    latitudeDeg: settings.latitude,
    longitudeDeg: settings.longitude,
  );

  final (moonRa, moonDec, _) = AstronomyCalculations.moonPosition(window.start);
  final moonDistance = AstronomyCalculations.angularSeparation(
    ra1Deg: raHours * 15.0,
    dec1Deg: decDegrees,
    ra2Deg: moonRa,
    dec2Deg: moonDec,
  );

  final hoursAbove = objectVisibility.durationAboveHorizon?.inMinutes != null
      ? objectVisibility.durationAboveHorizon!.inMinutes / 60.0
      : null;

  // Ensure a host/local library row exists so integration goals and progress
  // use a stable numeric id (not a synthetic hash fallback).
  final libraryTarget =
      await ref.read(targetLibraryServiceProvider).ensureCatalogTarget(
            targetName: targetName,
            raHours: raHours,
            decDegrees: decDegrees,
            catalogId: catalogId,
            objectType: objectType,
            magnitude: magnitude,
            sizeArcmin: sizeArcmin,
            constellation: constellation,
          );
  final targetId = libraryTarget.id;

  return TargetSuggestion(
    targetId: targetId,
    targetName: targetName,
    catalogId: catalogId,
    raHours: raHours,
    decDegrees: decDegrees,
    totalScore: 70,
    objectType: objectType,
    magnitude: magnitude,
    sizeArcmin: sizeArcmin,
    constellation: constellation,
    visibility: TargetVisibilityInfo(
      currentAltitude: altAz.$1,
      currentAzimuth: altAz.$2,
      transitAltitude: objectVisibility.transitAltitude,
      riseTime: objectVisibility.riseTime,
      transitTime: objectVisibility.transitTime,
      setTime: objectVisibility.setTime,
      isCircumpolar: objectVisibility.isCircumpolar,
      neverRises: objectVisibility.neverRises,
      airmass: AstronomyCalculations.airmass(altAz.$1),
      moonDistance: moonDistance,
      peakAltitude: objectVisibility.transitAltitude ?? altAz.$1,
      peakAltitudeTime: objectVisibility.transitTime,
      hoursAboveMinAlt: hoursAbove,
    ),
  );
}

/// Build and load a Plan Tonight multi-filter sequence into the editor.
Future<bool> addPlanTonightTargetToSequencer({
  required BuildContext context,
  required WidgetRef ref,
  required TargetSuggestion target,
  bool replaceSequence = false,
  bool includeSessionPreamble = false,
}) async {
  try {
    final built = await buildPlanTonightTargetSequenceFromSuggestion(
      ref: ref,
      target: target,
      includeSessionPreamble: includeSessionPreamble,
    );
    if (!context.mounted) return false;
    return loadPlanTonightSequenceIntoEditor(
      context: context,
      ref: ref,
      result: built,
      replaceSequence: replaceSequence,
    );
  } on SmartNightBuildException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  }
}

/// Build and load a framed target using the central Smart Night exposure math.
///
/// When the framing screen has mosaic mode enabled with a generated panel
/// grid (`FramingState.mosaicEnabled` && `mosaicPanels.isNotEmpty`), this
/// dispatches to [_addFramedMosaicToSequencer] instead of the single-target
/// path. That ensures a 2x3 (or any) mosaic designed in the framing screen
/// reaches the sequencer as a mosaic — previously only the central target
/// was sequenced and the panels were silently dropped.
///
/// Mosaic + Smart Night per-panel multi-filter composition is a tracked
/// feature, not a quick fix: it needs a multi-filter mosaic exposure model
/// (MosaicExposureSettings carrying a per-filter plan list) plus
/// MosaicService.createMosaicSequence emitting per-panel multi-filter capture
/// subtrees — a nightshade_core model/service change coordinated with the
/// engine owner (audit item #16 / modelChangeRequests). Until then the mosaic
/// path here uses the Smart Night-derived single-filter exposure
/// recommendation per panel via [smartNightMosaicExposureSettings], matching
/// the existing `MosaicWizardDialog` behaviour.
Future<bool> addFramedTargetToSequencer({
  required BuildContext context,
  required WidgetRef ref,
  required FramingTarget target,
  TargetSuggestion? sourceSuggestion,
  double? rotationDegrees,
  bool replaceSequence = false,
  bool includeSessionPreamble = false,
}) async {
  final framingState = ref.read(framingProvider);

  // Mosaic dispatch — only when the user has actually generated panels.
  if (framingState.mosaicEnabled && framingState.mosaicPanels.isNotEmpty) {
    return _addFramedMosaicToSequencer(
      context: context,
      ref: ref,
      framingState: framingState,
      target: target,
      rotationDegrees: rotationDegrees,
      replaceSequence: replaceSequence,
    );
  }

  try {
    final built = await buildPlanTonightTargetSequenceFromFraming(
      ref: ref,
      target: target,
      sourceSuggestion: sourceSuggestion,
      rotationDegrees: rotationDegrees,
      includeSessionPreamble: includeSessionPreamble,
    );
    if (!context.mounted) return false;
    return loadPlanTonightSequenceIntoEditor(
      context: context,
      ref: ref,
      result: built,
      replaceSequence: replaceSequence,
    );
  } on SmartNightBuildException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  }
}

/// Resolve the per-panel FOV in arcminutes from framing state.
///
/// Custom equipment is the most authoritative source. When the user has
/// configured custom equipment in the framing screen we use its computed
/// FOV directly. Otherwise we fall back to the active equipment profile
/// via `framingFOVProvider`. The preview FOV (`previewFovDegrees`) is
/// explicitly NOT used: it controls how much sky context the survey
/// preview shows, not the actual sensor footprint.
Future<({double widthArcmin, double heightArcmin})?> _resolvePanelFovArcmin({
  required WidgetRef ref,
  required FramingState framingState,
}) async {
  if (framingState.useCustomEquipment && framingState.customEquipment != null) {
    final eq = framingState.customEquipment!;
    return (
      widthArcmin: eq.fovWidthDeg * 60.0,
      heightArcmin: eq.fovHeightDeg * 60.0,
    );
  }

  final result = await ref.read(framingFOVProvider.future);
  final eq = result.equipment;
  if (eq == null) return null;
  return (
    widthArcmin: eq.fovWidthDeg * 60.0,
    heightArcmin: eq.fovHeightDeg * 60.0,
  );
}

/// Build a [MosaicConfig] from framing-screen state for the sequencer.
///
/// Pure function — does not touch riverpod or context. Tests can hit this
/// directly to verify the framing-UI knobs (columns/rows/overlap%) map to
/// the service-layer geometry (panelWidthArcmin/panelHeightArcmin/...).
MosaicConfig buildFramingMosaicConfig({
  required FramingTarget target,
  required FramingState framingState,
  required double panelWidthArcmin,
  required double panelHeightArcmin,
  double? rotationOverrideDegrees,
}) {
  final framingMosaicConfig = framingState.mosaicConfig;
  return MosaicConfig(
    centerRa: target.raHours,
    centerDec: target.decDegrees,
    panelWidthArcmin: panelWidthArcmin,
    panelHeightArcmin: panelHeightArcmin,
    overlapPercent: framingMosaicConfig.overlapPercent,
    rotation: rotationOverrideDegrees ?? framingState.rotation,
    panelsHorizontal: framingMosaicConfig.columns,
    panelsVertical: framingMosaicConfig.rows,
  );
}

/// Construct the mosaic name that the framing → sequencer handoff uses for
/// a given target. Exposed for tests + diagnostic UIs.
String framingMosaicNameFor(FramingTarget target) {
  return target.name.isNotEmpty
      ? '${target.name} Mosaic'
      : 'Mosaic ${target.raHours.toStringAsFixed(2)}h '
          '${target.decDegrees.toStringAsFixed(1)}°';
}

/// Build a mosaic [Sequence] from the framing screen's mosaic configuration
/// and load it into the editor.
///
/// Reuses [MosaicService.createMosaicSequence] — the same code path the
/// in-sequencer Mosaic Wizard uses — so per-panel `TargetHeaderNode`
/// metadata (mosaic name + panel index/row/col/total) flows into FITS
/// headers identically across both entry points.
Future<bool> _addFramedMosaicToSequencer({
  required BuildContext context,
  required WidgetRef ref,
  required FramingState framingState,
  required FramingTarget target,
  double? rotationDegrees,
  bool replaceSequence = false,
}) async {
  final fov = await _resolvePanelFovArcmin(
    ref: ref,
    framingState: framingState,
  );
  if (!context.mounted) return false;
  if (fov == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cannot build mosaic: equipment FOV is unavailable. Configure a '
          'camera + focal length in your active profile (or use custom '
          'equipment in framing) and try again.',
        ),
      ),
    );
    return false;
  }

  final config = buildFramingMosaicConfig(
    target: target,
    framingState: framingState,
    panelWidthArcmin: fov.widthArcmin,
    panelHeightArcmin: fov.heightArcmin,
    rotationOverrideDegrees: rotationDegrees,
  );

  const mosaicService = MosaicService();
  final validation = mosaicService.validateMosaic(config);
  if (!validation.isValid) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mosaic configuration invalid: ${validation.errors.join("; ")}',
        ),
      ),
    );
    return false;
  }

  final exposureContext =
      ref.read(smartNightExposureContextProvider).valueOrNull;
  final exposure = smartNightMosaicExposureSettings(exposureContext);

  final options = MosaicSequenceOptions(
    serpentineOrdering: framingState.mosaicConfig.serpentine,
    centerAfterSlew: true,
    autofocusPerPanel: false,
    // W1 no-daylight/altitude gate: default each panel's minAltitude to the
    // Smart Night floor so every panel TargetHeader carries a
    // `start_when AltitudeAbove` wait (serialized as `min_altitude`). Without
    // this the headless mosaic path gated on altitude but the framing →
    // sequencer path did not, so a panel could start imaging while still below
    // the horizon floor. STRENGTHENS the gate; it never weakens the Dart Sun
    // gate (W1) or the W5 weather gate.
    minAltitude: const SmartNightSettings().minAltitudeDeg,
  );

  final mosaicName = framingMosaicNameFor(target);

  final nodes = mosaicService.createMosaicSequence(
    mosaicName: mosaicName,
    config: config,
    exposure: exposure,
    options: options,
  );

  return _loadMosaicNodesIntoEditor(
    context: context,
    ref: ref,
    mosaicName: mosaicName,
    nodes: nodes,
    replaceSequence: replaceSequence,
  );
}

/// Wrap a mosaic node graph into the current sequence (or replace it).
Future<bool> _loadMosaicNodesIntoEditor({
  required BuildContext context,
  required WidgetRef ref,
  required String mosaicName,
  required Map<String, SequenceNode> nodes,
  required bool replaceSequence,
}) async {
  final notifier = ref.read(currentSequenceProvider.notifier);

  // The mosaic node graph has a single InstructionSetNode at its root
  // whose children are the per-panel TargetHeaderNodes.
  final rootNode = nodes.values.firstWhere(
    (n) => n is InstructionSetNode && n.parentId == null,
    orElse: () => throw StateError(
      'MosaicService.createMosaicSequence did not produce a root '
      'InstructionSetNode — refusing to load a malformed mosaic into the '
      'sequencer.',
    ),
  );

  Future<bool> loadReplacing() async {
    try {
      final sequence = Sequence.create(
        name: mosaicName,
        nodes: nodes,
        rootNodeId: rootNode.id,
      );
      notifier.loadSequence(sequence, discardUnsaved: true);
      return true;
    } on SequenceLockedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return false;
    }
  }

  if (replaceSequence || ref.read(currentSequenceProvider) == null) {
    return loadReplacing();
  }

  // Append: add each top-level target group under the current sequence's
  // root, then descend each subtree. Mirrors MosaicWizardDialog.
  try {
    final currentSeq = ref.read(currentSequenceProvider);
    if (currentSeq == null) {
      return loadReplacing();
    }
    final parentForChildren = currentSeq.rootNodeId;
    if (parentForChildren == null) {
      return loadReplacing();
    }
    for (final node in nodes.values) {
      if (node.id == rootNode.id) {
        // Re-parent the panel target headers under the current root.
        for (final childId in rootNode.childIds) {
          final child = nodes[childId];
          if (child != null) {
            notifier.addNode(child, parentId: parentForChildren);
          }
        }
      } else if (node.parentId != rootNode.id) {
        // Internal panel children — added under their original parent IDs.
        notifier.addNode(node, parentId: node.parentId);
      }
    }
    return true;
  } on NoActiveSequenceException {
    return loadReplacing();
  } on SequenceLockedException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  }
}

String dsoTypeLabel(DsoType type) => type.displayName;

/// Extract optional catalog metadata from any [CelestialObject].
({
  String? catalogId,
  String? objectType,
  double? sizeArcmin,
  String? constellation
}) celestialObjectMetadata(CelestialObject object) {
  if (object is DeepSkyObject) {
    return (
      catalogId:
          object.catalogIds.isNotEmpty ? object.catalogIds.first : object.name,
      objectType: dsoTypeLabel(object.type),
      sizeArcmin: object.sizeArcMin,
      constellation: object.constellation,
    );
  }
  if (object is Star) {
    return (
      catalogId:
          object.catalogIds.isNotEmpty ? object.catalogIds.first : object.name,
      objectType: 'Star',
      sizeArcmin: null,
      constellation: object.constellation,
    );
  }
  return (
    catalogId: object.name,
    objectType: null,
    sizeArcmin: null,
    constellation: null,
  );
}

String annotationObjectTypeLabel(ObjectType type) {
  switch (type) {
    case ObjectType.galaxy:
      return 'Galaxy';
    case ObjectType.nebula:
      return 'Nebula';
    case ObjectType.planetaryNebula:
      return 'Planetary Nebula';
    case ObjectType.starCluster:
      return 'Open Cluster';
    case ObjectType.star:
      return 'Star';
    case ObjectType.doubleStar:
      return 'Double Star';
    case ObjectType.asterism:
      return 'Asterism';
    case ObjectType.unknown:
      return 'Deep Sky Object';
  }
}

SingleTargetSequenceResult _withFramingRotation(
  SingleTargetSequenceResult result,
  double? rotationDegrees,
) {
  if (rotationDegrees == null) return result;
  final targetHeader =
      result.sequence.nodes.values.whereType<TargetHeaderNode>().firstOrNull;
  if (targetHeader == null) return result;

  final nodes = Map<String, SequenceNode>.from(result.sequence.nodes);
  nodes[targetHeader.id] = targetHeader.copyWith(rotation: rotationDegrees);
  return SingleTargetSequenceResult(
    sequence: result.sequence.copyWith(nodes: nodes),
    strategy: result.strategy,
    filterPlans: result.filterPlans,
    plannedTarget: result.plannedTarget,
  );
}

/// Load a built Plan Tonight sequence into the editor.
///
/// When [replaceSequence] is true the entire editor sequence is replaced
/// (planner "Review in Sequencer"). When false the target sub-tree is
/// appended to the current sequence (dashboard "Add to Sequencer").
Future<bool> loadPlanTonightSequenceIntoEditor({
  required BuildContext context,
  required WidgetRef ref,
  required SingleTargetSequenceResult result,
  required bool replaceSequence,
}) async {
  final notifier = ref.read(currentSequenceProvider.notifier);
  final templateHeader =
      result.sequence.nodes.values.whereType<TargetHeaderNode>().firstOrNull;
  if (templateHeader == null) return false;

  Future<bool> loadReplacing() async {
    try {
      notifier.loadSequence(result.sequence, discardUnsaved: true);
      return true;
    } on SequenceLockedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return false;
    }
  }

  if (replaceSequence || ref.read(currentSequenceProvider) == null) {
    return loadReplacing();
  }

  final newHeaderId = const Uuid().v4();
  final newHeader = templateHeader.copyWith(
    id: newHeaderId,
    childIds: const [],
  );

  try {
    notifier.addTargetHeader(newHeader);
    notifier.mergeTemplateNodes(
      templateNodes: result.sequence.nodes,
      templateRootId: templateHeader.id,
      targetId: newHeaderId,
    );
    return true;
  } on NoActiveSequenceException {
    return loadReplacing();
  } on SequenceLockedException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  }
}

String planTonightSequenceSummary(SingleTargetSequenceResult result) {
  final filters = result.filterPlans.map((p) => p.filterName).join(', ');
  final totalFrames = result.filterPlans.fold<int>(
    0,
    (sum, plan) => sum + plan.count,
  );
  return '$filters ($totalFrames frames)';
}
