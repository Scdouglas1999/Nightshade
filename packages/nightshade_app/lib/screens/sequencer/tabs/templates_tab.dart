import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../sequencer_screen.dart';
import 'package:nightshade_app/utils/snackbar_helper.dart';
import '../widgets/quick_start_wizard_dialog.dart';

/// Provider for templates list - loads from database with built-in fallbacks
final sequenceTemplatesProvider = FutureProvider<List<Sequence>>((ref) async {
  final repository = ref.watch(sequenceRepositoryProvider);

  // Load templates from database
  final dbTemplates = await repository.loadAllTemplates();

  // If no templates exist, return built-in templates
  if (dbTemplates.isEmpty) {
    return _getBuiltInTemplates();
  }

  return dbTemplates;
});

/// Built-in templates for first-time users
List<Sequence> _getBuiltInTemplates() {
  return [
    // Beginner templates first for discoverability
    Sequence(
      id: 'template-first-light',
      name: 'First Light',
      description:
          'Simple sequence for absolute beginners - just point and shoot',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 35)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 35)),
      nodes: _createFirstLightNodes(),
      rootNodeId: 'fl-root',
    ),
    Sequence(
      id: 'template-osc',
      name: 'One-Shot Color (OSC)',
      description: 'For color cameras without filter wheels',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 33)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 33)),
      nodes: _createOscNodes(),
      rootNodeId: 'osc-root',
    ),
    Sequence(
      id: 'template-quick-capture',
      name: 'Quick Capture',
      description: 'Simple sequence for quick test shots',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 31)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 31)),
      nodes: _createQuickCaptureNodes(),
      rootNodeId: 'quick-root',
    ),
    Sequence(
      id: 'template-dso-beginner',
      name: 'DSO Beginner',
      description:
          'Beginner-friendly sequence with comprehensive safety checks',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 29)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 29)),
      nodes: _createBeginnerTemplateNodes(),
      rootNodeId: 'beginner-root',
    ),
    // Intermediate templates
    Sequence(
      id: 'template-basic-lrgb',
      name: 'Basic LRGB Sequence',
      description:
          'Standard LRGB imaging sequence with autofocus and dithering',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 27)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 27)),
      nodes: _createLrgbTemplateNodes(),
      rootNodeId: 'lrgb-root',
    ),
    Sequence(
      id: 'template-narrowband',
      name: 'Narrowband (SHO)',
      description:
          'Hubble Palette narrowband imaging with SII, Ha, and OIII filters',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 25)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 25)),
      nodes: _createNarrowbandTemplateNodes(),
      rootNodeId: 'nb-root',
    ),
    Sequence(
      id: 'template-mosaic-panel',
      name: 'Mosaic Panel',
      description: 'Template for a single mosaic panel with multiple filters',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 23)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 23)),
      nodes: _createMosaicTemplateNodes(),
      rootNodeId: 'mosaic-root',
    ),
    // Intermediate-tier templates with condition-aware features
    Sequence(
      id: 'template-ha-oiii',
      name: 'Ha-OIII Bicolor',
      description: 'Two-filter narrowband imaging with guiding and dithering',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 19)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 19)),
      nodes: _createHaOiiiNodes(),
      rootNodeId: 'haoiii-root',
    ),
    Sequence(
      id: 'template-sho',
      name: 'SHO Hubble Palette',
      description:
          'Full Hubble Palette narrowband with weather safety conditional',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 17)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 17)),
      nodes: _createShoNodes(),
      rootNodeId: 'sho-root',
    ),
    Sequence(
      id: 'template-lrgb-ha',
      name: 'LRGB + Ha Enhanced',
      description: 'Broadband imaging with hydrogen-alpha enhancement layer',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 15)),
      nodes: _createLrgbHaNodes(),
      rootNodeId: 'lrgbha-root',
    ),
    Sequence(
      id: 'template-multi-target',
      name: 'Multi-Target Night',
      description: 'Image multiple targets with altitude-based switching',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 13)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 13)),
      nodes: _createMultiTargetNodes(),
      rootNodeId: 'multi-root',
    ),
    // Specialized templates
    Sequence(
      id: 'template-planetary',
      name: 'Planetary Capture',
      description: 'High frame rate lucky imaging for planets and moon',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 11)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 11)),
      nodes: _createPlanetaryNodes(),
      rootNodeId: 'planet-root',
    ),
    // Advanced templates with complex logic
    Sequence(
      id: 'template-unattended',
      name: 'Unattended All-Night',
      description:
          'Fully automated dusk-to-dawn imaging with weather and HFR recovery',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 9)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 9)),
      nodes: _createUnattendedNodes(),
      rootNodeId: 'unattended-root',
    ),
    Sequence(
      id: 'template-mosaic',
      name: 'Mosaic Multi-Panel',
      description: 'Large field mosaic with per-panel centering',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 8)),
      nodes: _createMosaicMultiPanelNodes(),
      rootNodeId: 'mosaic-mp-root',
    ),
    Sequence(
      id: 'template-comet',
      name: 'Comet/Asteroid Tracking',
      description: 'Moving target imaging with periodic re-centering',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 7)),
      nodes: _createCometNodes(),
      rootNodeId: 'comet-root',
    ),
    Sequence(
      id: 'template-solar',
      name: 'Solar Ha',
      description: 'Daytime solar imaging with frequent autofocus',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 6)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 6)),
      nodes: _createSolarNodes(),
      rootNodeId: 'solar-root',
    ),
    Sequence(
      id: 'template-lunar',
      name: 'Lunar Surface',
      description: 'High-resolution lunar imaging with lucky imaging bursts',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 5)),
      nodes: _createLunarNodes(),
      rootNodeId: 'lunar-root',
    ),
    Sequence(
      id: 'template-remote',
      name: 'Remote Observatory',
      description: 'Full remote operation with safety monitors',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 4)),
      nodes: _createRemoteObservatoryNodes(),
      rootNodeId: 'remote-root',
    ),
  ];
}

Map<String, SequenceNode> _createLrgbTemplateNodes() {
  const rootId = 'lrgb-root';
  const coolId = 'lrgb-cool';
  const focusId = 'lrgb-focus';
  const loopId = 'lrgb-loop';
  const lId = 'lrgb-l';
  const rId = 'lrgb-r';
  const gId = 'lrgb-g';
  const bId = 'lrgb-b';
  const warmId = 'lrgb-warm';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'LRGB Sequence',
      childIds: const [coolId, focusId, loopId, warmId],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: LoopConditionType.forever,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [lId, rId, gId, bId],
    ),
    lId: ExposureNode(
        id: lId,
        name: 'Luminance',
        durationSecs: 120,
        count: 1,
        filter: 'L',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 0),
    rId: ExposureNode(
        id: rId,
        name: 'Red',
        durationSecs: 120,
        count: 1,
        filter: 'R',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 1),
    gId: ExposureNode(
        id: gId,
        name: 'Green',
        durationSecs: 120,
        count: 1,
        filter: 'G',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 2),
    bId: ExposureNode(
        id: bId,
        name: 'Blue',
        durationSecs: 120,
        count: 1,
        filter: 'B',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 3),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
  };
}

Map<String, SequenceNode> _createNarrowbandTemplateNodes() {
  const rootId = 'nb-root';
  const coolId = 'nb-cool';
  const focusId = 'nb-focus';
  const loopId = 'nb-loop';
  const haId = 'nb-ha';
  const oiiiId = 'nb-oiii';
  const siiId = 'nb-sii';
  const warmId = 'nb-warm';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Narrowband Sequence',
      childIds: const [coolId, focusId, loopId, warmId],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -15, parentId: rootId, orderIndex: 0),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Narrowband Loop',
      conditionType: LoopConditionType.forever,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [haId, oiiiId, siiId],
    ),
    haId: ExposureNode(
        id: haId,
        name: 'H-alpha',
        durationSecs: 180,
        count: 1,
        filter: 'Ha',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 0),
    oiiiId: ExposureNode(
        id: oiiiId,
        name: 'OIII',
        durationSecs: 180,
        count: 1,
        filter: 'OIII',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 1),
    siiId: ExposureNode(
        id: siiId,
        name: 'SII',
        durationSecs: 180,
        count: 1,
        filter: 'SII',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 2),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
  };
}

Map<String, SequenceNode> _createMosaicTemplateNodes() {
  const rootId = 'mosaic-root';
  const slewId = 'mosaic-slew';
  const centerId = 'mosaic-center';
  const focusId = 'mosaic-focus';
  const loopId = 'mosaic-loop';
  const lId = 'mosaic-l';
  const haId = 'mosaic-ha';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Mosaic Panel',
      childIds: const [slewId, centerId, focusId, loopId],
    ),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Panel', parentId: rootId, orderIndex: 0),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 1),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 2),
    loopId: LoopNode(
      id: loopId,
      name: 'Panel Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: rootId,
      orderIndex: 3,
      childIds: const [lId, haId],
    ),
    lId: ExposureNode(
        id: lId,
        name: 'Luminance',
        durationSecs: 300,
        count: 1,
        filter: 'L',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 0),
    haId: ExposureNode(
        id: haId,
        name: 'H-alpha',
        durationSecs: 300,
        count: 1,
        filter: 'Ha',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 1),
  };
}

Map<String, SequenceNode> _createQuickCaptureNodes() {
  const rootId = 'quick-root';
  const expId = 'quick-exp';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Quick Capture',
      childIds: const [expId],
    ),
    expId: ExposureNode(
        id: expId,
        name: 'Test Shot',
        durationSecs: 10,
        count: 5,
        filter: 'L',
        binning: BinningMode.one,
        parentId: rootId,
        orderIndex: 0),
  };
}

Map<String, SequenceNode> _createBeginnerTemplateNodes() {
  const rootId = 'beginner-root';
  const coolId = 'beginner-cool';
  const slewId = 'beginner-slew';
  const centerId = 'beginner-center';
  const focusId = 'beginner-focus';
  const loopId = 'beginner-loop';
  const lId = 'beginner-l';
  const ditherAfter = 'beginner-dither';
  const warmId = 'beginner-warm';
  const parkId = 'beginner-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Beginner DSO Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        loopId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 3),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 20,
      parentId: rootId,
      orderIndex: 4,
      childIds: const [lId, ditherAfter],
    ),
    lId: ExposureNode(
        id: lId,
        name: 'Luminance',
        durationSecs: 120,
        count: 1,
        filter: 'L',
        binning: BinningMode.one,
        parentId: loopId,
        orderIndex: 0),
    ditherAfter: DitherNode(
        id: ditherAfter,
        name: 'Dither',
        pixels: 5.0,
        settleTime: 30,
        parentId: loopId,
        orderIndex: 1),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 5),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 6),
  };
}

/// First Light template - absolute beginner, point and shoot
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (temp: -10)
/// ├── Slew
/// ├── Loop (count: 20)
/// │   └── TakeExposure (30s, no filter change)
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createFirstLightNodes() {
  const rootId = 'fl-root';
  const coolId = 'fl-cool';
  const slewId = 'fl-slew';
  const loopId = 'fl-loop';
  const expId = 'fl-exp';
  const warmId = 'fl-warm';
  const parkId = 'fl-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'First Light Sequence',
      childIds: const [coolId, slewId, loopId, warmId, parkId],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 20,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [expId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Light Frame',
      durationSecs: 30,
      count: 1,
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 4),
  };
}

/// One-Shot Color (OSC) template - for color cameras without filter wheels
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (temp: -10)
/// ├── Slew
/// ├── CenterTarget (plate solve)
/// ├── Autofocus
/// ├── StartGuiding
/// ├── Loop (whileDark)
/// │   ├── TakeExposure (120s)
/// │   └── Dither (5px)
/// ├── StopGuiding
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createOscNodes() {
  const rootId = 'osc-root';
  const coolId = 'osc-cool';
  const slewId = 'osc-slew';
  const centerId = 'osc-center';
  const focusId = 'osc-focus';
  const startGuideId = 'osc-startguide';
  const loopId = 'osc-loop';
  const expId = 'osc-exp';
  const ditherId = 'osc-dither';
  const stopGuideId = 'osc-stopguide';
  const warmId = 'osc-warm';
  const parkId = 'osc-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'OSC Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: rootId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: rootId,
      orderIndex: 5,
      childIds: const [expId, ditherId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Light Frame',
      durationSecs: 120,
      count: 1,
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 1,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId, name: 'Stop Guiding', parentId: rootId, orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 8),
  };
}

/// Ha-OIII Bicolor template - two-filter narrowband imaging
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (-15°C for narrowband)
/// ├── Slew
/// ├── CenterTarget
/// ├── Autofocus
/// ├── StartGuiding
/// ├── Loop (whileDark)
/// │   ├── TakeExposure (Ha, 180s)
/// │   ├── TakeExposure (OIII, 180s)
/// │   └── Dither
/// ├── StopGuiding
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createHaOiiiNodes() {
  const rootId = 'haoiii-root';
  const coolId = 'haoiii-cool';
  const slewId = 'haoiii-slew';
  const centerId = 'haoiii-center';
  const focusId = 'haoiii-focus';
  const startGuideId = 'haoiii-startguide';
  const loopId = 'haoiii-loop';
  const haId = 'haoiii-ha';
  const oiiiId = 'haoiii-oiii';
  const ditherId = 'haoiii-dither';
  const stopGuideId = 'haoiii-stopguide';
  const warmId = 'haoiii-warm';
  const parkId = 'haoiii-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Ha-OIII Bicolor Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -15, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: rootId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'Bicolor Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: rootId,
      orderIndex: 5,
      childIds: const [haId, oiiiId, ditherId],
    ),
    haId: ExposureNode(
      id: haId,
      name: 'H-alpha',
      durationSecs: 180,
      count: 1,
      filter: 'Ha',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    oiiiId: ExposureNode(
      id: oiiiId,
      name: 'OIII',
      durationSecs: 180,
      count: 1,
      filter: 'OIII',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 1,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 2,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId, name: 'Stop Guiding', parentId: rootId, orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 8),
  };
}

/// SHO Hubble Palette template - full Hubble Palette narrowband with weather safety
/// Structure:
/// InstructionSet (root)
/// ├── Conditional (weatherSafe)
/// │   └── InstructionSet (imaging sequence)
/// │       ├── CoolCamera (-15°C)
/// │       ├── Slew
/// │       ├── CenterTarget
/// │       ├── Autofocus
/// │       ├── StartGuiding
/// │       ├── Loop (whileDark)
/// │       │   ├── TakeExposure (SII, 300s)
/// │       │   ├── TakeExposure (Ha, 300s)
/// │       │   ├── TakeExposure (OIII, 300s)
/// │       │   └── Dither
/// │       ├── StopGuiding
/// │       ├── WarmCamera
/// │       └── Park
/// └── Park (fallback if weather unsafe)
Map<String, SequenceNode> _createShoNodes() {
  const rootId = 'sho-root';
  const weatherCondId = 'sho-weather';
  const mainSeqId = 'sho-main';
  const coolId = 'sho-cool';
  const slewId = 'sho-slew';
  const centerId = 'sho-center';
  const focusId = 'sho-focus';
  const startGuideId = 'sho-startguide';
  const loopId = 'sho-loop';
  const siiId = 'sho-sii';
  const haId = 'sho-ha';
  const oiiiId = 'sho-oiii';
  const ditherId = 'sho-dither';
  const stopGuideId = 'sho-stopguide';
  const warmId = 'sho-warm';
  const parkId = 'sho-park';
  const fallbackParkId = 'sho-fallback-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'SHO Hubble Palette Sequence',
      childIds: const [weatherCondId, fallbackParkId],
    ),
    weatherCondId: ConditionalNode(
      id: weatherCondId,
      name: 'Weather Safe Check',
      conditionType: ConditionalType.weatherSafe,
      parentId: rootId,
      orderIndex: 0,
      childIds: const [mainSeqId],
    ),
    mainSeqId: InstructionSetNode(
      id: mainSeqId,
      name: 'SHO Imaging',
      parentId: weatherCondId,
      orderIndex: 0,
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -15, parentId: mainSeqId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: mainSeqId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: mainSeqId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: mainSeqId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: mainSeqId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'SHO Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: mainSeqId,
      orderIndex: 5,
      childIds: const [siiId, haId, oiiiId, ditherId],
    ),
    siiId: ExposureNode(
      id: siiId,
      name: 'SII',
      durationSecs: 300,
      count: 1,
      filter: 'SII',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    haId: ExposureNode(
      id: haId,
      name: 'H-alpha',
      durationSecs: 300,
      count: 1,
      filter: 'Ha',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 1,
    ),
    oiiiId: ExposureNode(
      id: oiiiId,
      name: 'OIII',
      durationSecs: 300,
      count: 1,
      filter: 'OIII',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 2,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 3,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId,
        name: 'Stop Guiding',
        parentId: mainSeqId,
        orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: mainSeqId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: mainSeqId, orderIndex: 8),
    fallbackParkId: ParkNode(
        id: fallbackParkId,
        name: 'Weather Unsafe - Park',
        parentId: rootId,
        orderIndex: 1),
  };
}

/// LRGB + Ha Enhanced template - broadband with hydrogen-alpha enhancement
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (-10°C)
/// ├── Slew
/// ├── CenterTarget
/// ├── Autofocus
/// ├── StartGuiding
/// ├── Loop (whileDark)
/// │   ├── TakeExposure (L, 120s)
/// │   ├── TakeExposure (R, 120s)
/// │   ├── TakeExposure (G, 120s)
/// │   ├── TakeExposure (B, 120s)
/// │   ├── TakeExposure (Ha, 180s)
/// │   └── Dither
/// ├── StopGuiding
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createLrgbHaNodes() {
  const rootId = 'lrgbha-root';
  const coolId = 'lrgbha-cool';
  const slewId = 'lrgbha-slew';
  const centerId = 'lrgbha-center';
  const focusId = 'lrgbha-focus';
  const startGuideId = 'lrgbha-startguide';
  const loopId = 'lrgbha-loop';
  const lId = 'lrgbha-l';
  const rId = 'lrgbha-r';
  const gId = 'lrgbha-g';
  const bId = 'lrgbha-b';
  const haId = 'lrgbha-ha';
  const ditherId = 'lrgbha-dither';
  const stopGuideId = 'lrgbha-stopguide';
  const warmId = 'lrgbha-warm';
  const parkId = 'lrgbha-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'LRGB + Ha Enhanced Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: rootId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'LRGB+Ha Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: rootId,
      orderIndex: 5,
      childIds: const [lId, rId, gId, bId, haId, ditherId],
    ),
    lId: ExposureNode(
      id: lId,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    rId: ExposureNode(
      id: rId,
      name: 'Red',
      durationSecs: 120,
      count: 1,
      filter: 'R',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 1,
    ),
    gId: ExposureNode(
      id: gId,
      name: 'Green',
      durationSecs: 120,
      count: 1,
      filter: 'G',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 2,
    ),
    bId: ExposureNode(
      id: bId,
      name: 'Blue',
      durationSecs: 120,
      count: 1,
      filter: 'B',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 3,
    ),
    haId: ExposureNode(
      id: haId,
      name: 'H-alpha Enhancement',
      durationSecs: 180,
      count: 1,
      filter: 'Ha',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 4,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 5,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId, name: 'Stop Guiding', parentId: rootId, orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 8),
  };
}

/// Multi-Target Night template - image multiple targets with altitude switching
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (-10°C)
/// ├── Target 1 InstructionSet
/// │   ├── Conditional (altitudeAbove: 30°)
/// │   │   └── InstructionSet
/// │   │       ├── Slew
/// │   │       ├── CenterTarget
/// │   │       ├── Autofocus
/// │   │       ├── StartGuiding
/// │   │       ├── Loop (count: 10)
/// │   │       │   ├── TakeExposure (L, 120s)
/// │   │       │   └── Dither
/// │   │       └── StopGuiding
/// ├── Target 2 InstructionSet (same structure)
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createMultiTargetNodes() {
  const rootId = 'multi-root';
  const coolId = 'multi-cool';

  // Target 1 nodes
  const target1CondId = 'multi-t1-cond';
  const target1SeqId = 'multi-t1-seq';
  const slew1Id = 'multi-t1-slew';
  const center1Id = 'multi-t1-center';
  const focus1Id = 'multi-t1-focus';
  const guide1StartId = 'multi-t1-guidestart';
  const loop1Id = 'multi-t1-loop';
  const exp1Id = 'multi-t1-exp';
  const dither1Id = 'multi-t1-dither';
  const guide1StopId = 'multi-t1-guidestop';

  // Target 2 nodes
  const target2CondId = 'multi-t2-cond';
  const target2SeqId = 'multi-t2-seq';
  const slew2Id = 'multi-t2-slew';
  const center2Id = 'multi-t2-center';
  const focus2Id = 'multi-t2-focus';
  const guide2StartId = 'multi-t2-guidestart';
  const loop2Id = 'multi-t2-loop';
  const exp2Id = 'multi-t2-exp';
  const dither2Id = 'multi-t2-dither';
  const guide2StopId = 'multi-t2-guidestop';

  const warmId = 'multi-warm';
  const parkId = 'multi-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Multi-Target Night Sequence',
      childIds: const [coolId, target1CondId, target2CondId, warmId, parkId],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),

    // Target 1 with altitude conditional
    target1CondId: ConditionalNode(
      id: target1CondId,
      name: 'Target 1 Above 30 deg',
      conditionType: ConditionalType.altitudeAbove,
      thresholdValue: 30.0,
      parentId: rootId,
      orderIndex: 1,
      childIds: const [target1SeqId],
    ),
    target1SeqId: InstructionSetNode(
      id: target1SeqId,
      name: 'Target 1 Imaging',
      parentId: target1CondId,
      orderIndex: 0,
      childIds: const [
        slew1Id,
        center1Id,
        focus1Id,
        guide1StartId,
        loop1Id,
        guide1StopId
      ],
    ),
    slew1Id: SlewNode(
        id: slew1Id,
        name: 'Slew to Target 1',
        parentId: target1SeqId,
        orderIndex: 0),
    center1Id: CenterNode(
        id: center1Id,
        name: 'Center Target 1',
        parentId: target1SeqId,
        orderIndex: 1),
    focus1Id: AutofocusNode(
        id: focus1Id,
        method: AutofocusMethod.vCurve,
        parentId: target1SeqId,
        orderIndex: 2),
    guide1StartId: StartGuidingNode(
      id: guide1StartId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: target1SeqId,
      orderIndex: 3,
    ),
    loop1Id: LoopNode(
      id: loop1Id,
      name: 'Target 1 Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: target1SeqId,
      orderIndex: 4,
      childIds: const [exp1Id, dither1Id],
    ),
    exp1Id: ExposureNode(
      id: exp1Id,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loop1Id,
      orderIndex: 0,
    ),
    dither1Id: DitherNode(
      id: dither1Id,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loop1Id,
      orderIndex: 1,
    ),
    guide1StopId: StopGuidingNode(
        id: guide1StopId,
        name: 'Stop Guiding',
        parentId: target1SeqId,
        orderIndex: 5),

    // Target 2 with altitude conditional
    target2CondId: ConditionalNode(
      id: target2CondId,
      name: 'Target 2 Above 30 deg',
      conditionType: ConditionalType.altitudeAbove,
      thresholdValue: 30.0,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [target2SeqId],
    ),
    target2SeqId: InstructionSetNode(
      id: target2SeqId,
      name: 'Target 2 Imaging',
      parentId: target2CondId,
      orderIndex: 0,
      childIds: const [
        slew2Id,
        center2Id,
        focus2Id,
        guide2StartId,
        loop2Id,
        guide2StopId
      ],
    ),
    slew2Id: SlewNode(
        id: slew2Id,
        name: 'Slew to Target 2',
        parentId: target2SeqId,
        orderIndex: 0),
    center2Id: CenterNode(
        id: center2Id,
        name: 'Center Target 2',
        parentId: target2SeqId,
        orderIndex: 1),
    focus2Id: AutofocusNode(
        id: focus2Id,
        method: AutofocusMethod.vCurve,
        parentId: target2SeqId,
        orderIndex: 2),
    guide2StartId: StartGuidingNode(
      id: guide2StartId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: target2SeqId,
      orderIndex: 3,
    ),
    loop2Id: LoopNode(
      id: loop2Id,
      name: 'Target 2 Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: target2SeqId,
      orderIndex: 4,
      childIds: const [exp2Id, dither2Id],
    ),
    exp2Id: ExposureNode(
      id: exp2Id,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loop2Id,
      orderIndex: 0,
    ),
    dither2Id: DitherNode(
      id: dither2Id,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loop2Id,
      orderIndex: 1,
    ),
    guide2StopId: StopGuidingNode(
        id: guide2StopId,
        name: 'Stop Guiding',
        parentId: target2SeqId,
        orderIndex: 5),

    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 4),
  };
}

/// Planetary Capture template - high frame rate lucky imaging
/// Structure:
/// InstructionSet (root)
/// ├── Slew
/// ├── CenterTarget
/// ├── Loop (count: 10)
/// │   └── TakeExposure (30s, high gain: 300, video mode)
/// └── Park
Map<String, SequenceNode> _createPlanetaryNodes() {
  const rootId = 'planet-root';
  const slewId = 'planet-slew';
  const centerId = 'planet-center';
  const loopId = 'planet-loop';
  const expId = 'planet-exp';
  const parkId = 'planet-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Planetary Capture',
      childIds: const [slewId, centerId, loopId, parkId],
    ),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 0),
    centerId: CenterNode(
        id: centerId, name: 'Center Target', parentId: rootId, orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Video Capture Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [expId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Video Capture (30s)',
      durationSecs: 30,
      count: 1,
      gain: 300,
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 3),
  };
}

/// Unattended All-Night template - fully automated dusk-to-dawn imaging
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (-10°C)
/// ├── Slew
/// ├── CenterTarget
/// ├── Autofocus
/// ├── StartGuiding
/// ├── Loop (whileDark)
/// │   ├── Conditional (hfrDegraded threshold: 4.0)
/// │   │   └── Autofocus
/// │   ├── TakeExposure (L, 120s)
/// │   ├── TakeExposure (R, 120s)
/// │   ├── TakeExposure (G, 120s)
/// │   ├── TakeExposure (B, 120s)
/// │   └── Dither
/// ├── StopGuiding
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createUnattendedNodes() {
  const rootId = 'unattended-root';
  const coolId = 'unattended-cool';
  const slewId = 'unattended-slew';
  const centerId = 'unattended-center';
  const focusId = 'unattended-focus';
  const startGuideId = 'unattended-startguide';
  const loopId = 'unattended-loop';
  const recoveryId = 'unattended-recovery';
  const recoveryFocusId = 'unattended-recovery-focus';
  const lId = 'unattended-l';
  const rId = 'unattended-r';
  const gId = 'unattended-g';
  const bId = 'unattended-b';
  const ditherId = 'unattended-dither';
  const stopGuideId = 'unattended-stopguide';
  const warmId = 'unattended-warm';
  const parkId = 'unattended-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Unattended All-Night Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: rootId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: rootId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: rootId,
      orderIndex: 5,
      childIds: const [recoveryId, lId, rId, gId, bId, ditherId],
    ),
    // HFR recovery - triggers autofocus when HFR degrades above threshold
    recoveryId: RecoveryNode(
      id: recoveryId,
      name: 'HFR Recovery',
      recoveryAction: RecoveryActionType.autofocus,
      maxRetries: 3,
      triggerType: TriggerType.hfrDegraded,
      triggerThreshold: 4.0,
      parentId: loopId,
      orderIndex: 0,
      childIds: const [recoveryFocusId],
    ),
    recoveryFocusId: AutofocusNode(
      id: recoveryFocusId,
      method: AutofocusMethod.vCurve,
      parentId: recoveryId,
      orderIndex: 0,
    ),
    lId: ExposureNode(
      id: lId,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 1,
    ),
    rId: ExposureNode(
      id: rId,
      name: 'Red',
      durationSecs: 120,
      count: 1,
      filter: 'R',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 2,
    ),
    gId: ExposureNode(
      id: gId,
      name: 'Green',
      durationSecs: 120,
      count: 1,
      filter: 'G',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 3,
    ),
    bId: ExposureNode(
      id: bId,
      name: 'Blue',
      durationSecs: 120,
      count: 1,
      filter: 'B',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 4,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 5,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId, name: 'Stop Guiding', parentId: rootId, orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 8),
  };
}

/// Mosaic Multi-Panel template - large field mosaic with per-panel centering
/// Structure:
/// InstructionSet (setup)
/// ├── CoolCamera
/// └── Autofocus
///
/// Panel 1 InstructionSet
/// ├── Slew (panel 1)
/// ├── CenterTarget (tight tolerance)
/// ├── StartGuiding
/// ├── Loop (count: 10)
/// │   └── TakeExposure (L, 120s)
/// └── StopGuiding
///
/// Panel 2 InstructionSet (same structure)
/// Panel 3 InstructionSet (same structure)
///
/// InstructionSet (shutdown)
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createMosaicMultiPanelNodes() {
  const rootId = 'mosaic-mp-root';

  // Setup nodes
  const setupId = 'mosaic-mp-setup';
  const coolId = 'mosaic-mp-cool';
  const focusId = 'mosaic-mp-focus';

  // Panel 1 nodes
  const panel1Id = 'mosaic-mp-panel1';
  const slew1Id = 'mosaic-mp-slew1';
  const center1Id = 'mosaic-mp-center1';
  const guide1StartId = 'mosaic-mp-guide1-start';
  const loop1Id = 'mosaic-mp-loop1';
  const exp1Id = 'mosaic-mp-exp1';
  const guide1StopId = 'mosaic-mp-guide1-stop';

  // Panel 2 nodes
  const panel2Id = 'mosaic-mp-panel2';
  const slew2Id = 'mosaic-mp-slew2';
  const center2Id = 'mosaic-mp-center2';
  const guide2StartId = 'mosaic-mp-guide2-start';
  const loop2Id = 'mosaic-mp-loop2';
  const exp2Id = 'mosaic-mp-exp2';
  const guide2StopId = 'mosaic-mp-guide2-stop';

  // Panel 3 nodes
  const panel3Id = 'mosaic-mp-panel3';
  const slew3Id = 'mosaic-mp-slew3';
  const center3Id = 'mosaic-mp-center3';
  const guide3StartId = 'mosaic-mp-guide3-start';
  const loop3Id = 'mosaic-mp-loop3';
  const exp3Id = 'mosaic-mp-exp3';
  const guide3StopId = 'mosaic-mp-guide3-stop';

  // Shutdown nodes
  const shutdownId = 'mosaic-mp-shutdown';
  const warmId = 'mosaic-mp-warm';
  const parkId = 'mosaic-mp-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Mosaic Multi-Panel Sequence',
      childIds: const [setupId, panel1Id, panel2Id, panel3Id, shutdownId],
    ),

    // Setup section
    setupId: InstructionSetNode(
      id: setupId,
      name: 'Setup',
      parentId: rootId,
      orderIndex: 0,
      childIds: const [coolId, focusId],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: setupId, orderIndex: 0),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: setupId,
        orderIndex: 1),

    // Panel 1
    panel1Id: InstructionSetNode(
      id: panel1Id,
      name: 'Panel 1',
      parentId: rootId,
      orderIndex: 1,
      childIds: const [
        slew1Id,
        center1Id,
        guide1StartId,
        loop1Id,
        guide1StopId
      ],
    ),
    slew1Id: SlewNode(
        id: slew1Id,
        name: 'Slew to Panel 1',
        parentId: panel1Id,
        orderIndex: 0),
    center1Id: CenterNode(
        id: center1Id,
        name: 'Center Panel 1',
        accuracyArcsec: 5.0,
        parentId: panel1Id,
        orderIndex: 1),
    guide1StartId: StartGuidingNode(
      id: guide1StartId,
      name: 'Start Guiding',
      settlePixels: 1.0,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: panel1Id,
      orderIndex: 2,
    ),
    loop1Id: LoopNode(
      id: loop1Id,
      name: 'Panel 1 Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: panel1Id,
      orderIndex: 3,
      childIds: const [exp1Id],
    ),
    exp1Id: ExposureNode(
      id: exp1Id,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loop1Id,
      orderIndex: 0,
    ),
    guide1StopId: StopGuidingNode(
        id: guide1StopId,
        name: 'Stop Guiding',
        parentId: panel1Id,
        orderIndex: 4),

    // Panel 2
    panel2Id: InstructionSetNode(
      id: panel2Id,
      name: 'Panel 2',
      parentId: rootId,
      orderIndex: 2,
      childIds: const [
        slew2Id,
        center2Id,
        guide2StartId,
        loop2Id,
        guide2StopId
      ],
    ),
    slew2Id: SlewNode(
        id: slew2Id,
        name: 'Slew to Panel 2',
        parentId: panel2Id,
        orderIndex: 0),
    center2Id: CenterNode(
        id: center2Id,
        name: 'Center Panel 2',
        accuracyArcsec: 5.0,
        parentId: panel2Id,
        orderIndex: 1),
    guide2StartId: StartGuidingNode(
      id: guide2StartId,
      name: 'Start Guiding',
      settlePixels: 1.0,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: panel2Id,
      orderIndex: 2,
    ),
    loop2Id: LoopNode(
      id: loop2Id,
      name: 'Panel 2 Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: panel2Id,
      orderIndex: 3,
      childIds: const [exp2Id],
    ),
    exp2Id: ExposureNode(
      id: exp2Id,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loop2Id,
      orderIndex: 0,
    ),
    guide2StopId: StopGuidingNode(
        id: guide2StopId,
        name: 'Stop Guiding',
        parentId: panel2Id,
        orderIndex: 4),

    // Panel 3
    panel3Id: InstructionSetNode(
      id: panel3Id,
      name: 'Panel 3',
      parentId: rootId,
      orderIndex: 3,
      childIds: const [
        slew3Id,
        center3Id,
        guide3StartId,
        loop3Id,
        guide3StopId
      ],
    ),
    slew3Id: SlewNode(
        id: slew3Id,
        name: 'Slew to Panel 3',
        parentId: panel3Id,
        orderIndex: 0),
    center3Id: CenterNode(
        id: center3Id,
        name: 'Center Panel 3',
        accuracyArcsec: 5.0,
        parentId: panel3Id,
        orderIndex: 1),
    guide3StartId: StartGuidingNode(
      id: guide3StartId,
      name: 'Start Guiding',
      settlePixels: 1.0,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: panel3Id,
      orderIndex: 2,
    ),
    loop3Id: LoopNode(
      id: loop3Id,
      name: 'Panel 3 Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: panel3Id,
      orderIndex: 3,
      childIds: const [exp3Id],
    ),
    exp3Id: ExposureNode(
      id: exp3Id,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loop3Id,
      orderIndex: 0,
    ),
    guide3StopId: StopGuidingNode(
        id: guide3StopId,
        name: 'Stop Guiding',
        parentId: panel3Id,
        orderIndex: 4),

    // Shutdown section
    shutdownId: InstructionSetNode(
      id: shutdownId,
      name: 'Shutdown',
      parentId: rootId,
      orderIndex: 4,
      childIds: const [warmId, parkId],
    ),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: shutdownId, orderIndex: 0),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: shutdownId, orderIndex: 1),
  };
}

/// Comet/Asteroid Tracking template - moving target imaging with periodic re-centering
/// Structure:
/// InstructionSet (root)
/// ├── CoolCamera (-10°C)
/// ├── Slew
/// ├── CenterTarget
/// ├── StartGuiding
/// ├── Loop (whileDark)
/// │   ├── Loop (count: 10)  [Inner loop for frames between re-center]
/// │   │   └── TakeExposure (60s, no dither for moving targets)
/// │   └── CenterTarget (re-acquire moving target)
/// ├── StopGuiding
/// ├── WarmCamera
/// └── Park
Map<String, SequenceNode> _createCometNodes() {
  const rootId = 'comet-root';
  const coolId = 'comet-cool';
  const slewId = 'comet-slew';
  const centerId = 'comet-center';
  const startGuideId = 'comet-startguide';
  const outerLoopId = 'comet-outer-loop';
  const innerLoopId = 'comet-inner-loop';
  const expId = 'comet-exp';
  const recenterAfterId = 'comet-recenter';
  const stopGuideId = 'comet-stopguide';
  const warmId = 'comet-warm';
  const parkId = 'comet-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Comet/Asteroid Tracking Sequence',
      childIds: const [
        coolId,
        slewId,
        centerId,
        startGuideId,
        outerLoopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Initial Center on Target',
        parentId: rootId,
        orderIndex: 2),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: rootId,
      orderIndex: 3,
    ),
    outerLoopId: LoopNode(
      id: outerLoopId,
      name: 'Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: rootId,
      orderIndex: 4,
      childIds: const [innerLoopId, recenterAfterId],
    ),
    // Inner loop: capture 10 frames between re-centering
    innerLoopId: LoopNode(
      id: innerLoopId,
      name: 'Frame Burst (10 frames)',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: outerLoopId,
      orderIndex: 0,
      childIds: const [expId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Light Frame',
      durationSecs: 60,
      count: 1,
      binning: BinningMode.one,
      ditherEvery: 0, // No dithering for moving targets
      parentId: innerLoopId,
      orderIndex: 0,
    ),
    // Re-center on moving target after each burst
    recenterAfterId: CenterNode(
      id: recenterAfterId,
      name: 'Re-center on Moving Target',
      parentId: outerLoopId,
      orderIndex: 1,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId, name: 'Stop Guiding', parentId: rootId, orderIndex: 5),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 6),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 7),
  };
}

/// Solar Ha template - daytime solar imaging with frequent autofocus
/// Structure:
/// InstructionSet (root)
/// ├── Loop (count: 100)
/// │   ├── TakeExposure (0.01s, high gain: 400)
/// │   └── Conditional (every 10th iteration - use Recovery with filter change trigger)
/// │       └── Autofocus
/// └── Notification ("Solar session complete")
///
/// Note: For solar imaging, we use short exposures and high gain.
/// The conditional autofocus uses a temperature shift trigger as a proxy
/// for periodic refocusing since seeing conditions change rapidly.
Map<String, SequenceNode> _createSolarNodes() {
  const rootId = 'solar-root';
  const loopId = 'solar-loop';
  const expId = 'solar-exp';
  const recoveryId = 'solar-recovery';
  const recoveryFocusId = 'solar-recovery-focus';
  const notifyId = 'solar-notify';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Solar Ha Sequence',
      childIds: const [loopId, notifyId],
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'Solar Capture Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 100,
      parentId: rootId,
      orderIndex: 0,
      childIds: const [expId, recoveryId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Solar Frame',
      durationSecs: 0.01, // 10ms exposure for solar
      count: 1,
      gain: 400, // High gain for solar Ha
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    // Recovery node triggers periodic autofocus based on temperature drift
    // This serves as a proxy for "every N frames" since solar seeing changes rapidly
    recoveryId: RecoveryNode(
      id: recoveryId,
      name: 'Periodic Focus Check',
      recoveryAction: RecoveryActionType.autofocus,
      maxRetries: 1,
      triggerType: TriggerType.temperatureShift,
      triggerThreshold:
          0.5, // Trigger on small temp changes as proxy for periodic focus
      parentId: loopId,
      orderIndex: 1,
      childIds: const [recoveryFocusId],
    ),
    recoveryFocusId: AutofocusNode(
      id: recoveryFocusId,
      method: AutofocusMethod.vCurve,
      parentId: recoveryId,
      orderIndex: 0,
    ),
    notifyId: NotificationNode(
      id: notifyId,
      name: 'Session Complete',
      title: 'Solar Session Complete',
      message: 'Solar Ha imaging session has finished capturing 100 frames.',
      level: NotificationLevel.success,
      parentId: rootId,
      orderIndex: 1,
    ),
  };
}

/// Lunar Surface template - high-resolution lunar imaging with lucky imaging bursts
/// Structure:
/// InstructionSet (root)
/// ├── Slew
/// ├── CenterTarget
/// ├── Loop (count: 5)  [Multiple video bursts]
/// │   ├── TakeExposure (0.05s, video burst, high gain: 300)
/// │   └── Autofocus
/// └── Notification ("Lunar capture complete")
Map<String, SequenceNode> _createLunarNodes() {
  const rootId = 'lunar-root';
  const slewId = 'lunar-slew';
  const centerId = 'lunar-center';
  const loopId = 'lunar-loop';
  const expId = 'lunar-exp';
  const focusId = 'lunar-focus';
  const notifyId = 'lunar-notify';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Lunar Surface Sequence',
      childIds: const [slewId, centerId, loopId, notifyId],
    ),
    slewId: SlewNode(
        id: slewId,
        name: 'Slew to Lunar Target',
        parentId: rootId,
        orderIndex: 0),
    centerId: CenterNode(
        id: centerId,
        name: 'Center on Lunar Feature',
        parentId: rootId,
        orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Video Burst Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 5,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [expId, focusId],
    ),
    expId: ExposureNode(
      id: expId,
      name: 'Lunar Video Burst',
      durationSecs: 0.05, // 50ms exposures for lucky imaging
      count: 500, // 500 frames per burst (25 seconds of video)
      gain: 300,
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    focusId: AutofocusNode(
      id: focusId,
      name: 'Refocus Between Bursts',
      method: AutofocusMethod.vCurve,
      parentId: loopId,
      orderIndex: 1,
    ),
    notifyId: NotificationNode(
      id: notifyId,
      name: 'Capture Complete',
      title: 'Lunar Capture Complete',
      message:
          'Lunar surface imaging session has finished with 5 video bursts.',
      level: NotificationLevel.success,
      parentId: rootId,
      orderIndex: 3,
    ),
  };
}

/// Remote Observatory template - full remote operation with safety monitors
/// Structure:
/// InstructionSet (root)
/// ├── Conditional (weatherSafe)
/// │   └── InstructionSet (main sequence)
/// │       ├── CoolCamera
/// │       ├── Slew
/// │       ├── CenterTarget
/// │       ├── Autofocus
/// │       ├── StartGuiding
/// │       ├── Loop (whileDark)
/// │       │   ├── TakeExposure (L, 120s)
/// │       │   ├── TakeExposure (R, 120s)
/// │       │   ├── TakeExposure (G, 120s)
/// │       │   ├── TakeExposure (B, 120s)
/// │       │   └── Dither
/// │       ├── StopGuiding
/// │       ├── WarmCamera
/// │       └── Park
/// └── InstructionSet (emergency fallback - weather unsafe)
///     ├── Park
///     └── Notification ("Weather unsafe - parked")
Map<String, SequenceNode> _createRemoteObservatoryNodes() {
  const rootId = 'remote-root';

  // Weather conditional
  const weatherCondId = 'remote-weather-cond';

  // Main sequence nodes
  const mainSeqId = 'remote-main';
  const coolId = 'remote-cool';
  const slewId = 'remote-slew';
  const centerId = 'remote-center';
  const focusId = 'remote-focus';
  const startGuideId = 'remote-startguide';
  const loopId = 'remote-loop';
  const lId = 'remote-l';
  const rId = 'remote-r';
  const gId = 'remote-g';
  const bId = 'remote-b';
  const ditherId = 'remote-dither';
  const stopGuideId = 'remote-stopguide';
  const warmId = 'remote-warm';
  const parkId = 'remote-park';

  // Emergency fallback nodes
  const emergencyId = 'remote-emergency';
  const emergencyParkId = 'remote-emergency-park';
  const emergencyNotifyId = 'remote-emergency-notify';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Remote Observatory Sequence',
      childIds: const [weatherCondId, emergencyId],
    ),

    // Weather safety conditional - only proceed if weather is safe
    weatherCondId: ConditionalNode(
      id: weatherCondId,
      name: 'Weather Safe Check',
      conditionType: ConditionalType.weatherSafe,
      parentId: rootId,
      orderIndex: 0,
      childIds: const [mainSeqId],
    ),

    // Main imaging sequence (executed when weather is safe)
    mainSeqId: InstructionSetNode(
      id: mainSeqId,
      name: 'Main Imaging Sequence',
      parentId: weatherCondId,
      orderIndex: 0,
      childIds: const [
        coolId,
        slewId,
        centerId,
        focusId,
        startGuideId,
        loopId,
        stopGuideId,
        warmId,
        parkId
      ],
    ),
    coolId: CoolCameraNode(
        id: coolId, targetTemp: -10, parentId: mainSeqId, orderIndex: 0),
    slewId: SlewNode(
        id: slewId, name: 'Slew to Target', parentId: mainSeqId, orderIndex: 1),
    centerId: CenterNode(
        id: centerId,
        name: 'Plate Solve & Center',
        parentId: mainSeqId,
        orderIndex: 2),
    focusId: AutofocusNode(
        id: focusId,
        method: AutofocusMethod.vCurve,
        parentId: mainSeqId,
        orderIndex: 3),
    startGuideId: StartGuidingNode(
      id: startGuideId,
      name: 'Start Guiding',
      settlePixels: 1.5,
      settleTime: 10.0,
      settleTimeout: 60.0,
      autoSelectStar: true,
      parentId: mainSeqId,
      orderIndex: 4,
    ),
    loopId: LoopNode(
      id: loopId,
      name: 'LRGB Capture While Dark',
      conditionType: LoopConditionType.whileDark,
      parentId: mainSeqId,
      orderIndex: 5,
      childIds: const [lId, rId, gId, bId, ditherId],
    ),
    lId: ExposureNode(
      id: lId,
      name: 'Luminance',
      durationSecs: 120,
      count: 1,
      filter: 'L',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 0,
    ),
    rId: ExposureNode(
      id: rId,
      name: 'Red',
      durationSecs: 120,
      count: 1,
      filter: 'R',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 1,
    ),
    gId: ExposureNode(
      id: gId,
      name: 'Green',
      durationSecs: 120,
      count: 1,
      filter: 'G',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 2,
    ),
    bId: ExposureNode(
      id: bId,
      name: 'Blue',
      durationSecs: 120,
      count: 1,
      filter: 'B',
      binning: BinningMode.one,
      parentId: loopId,
      orderIndex: 3,
    ),
    ditherId: DitherNode(
      id: ditherId,
      name: 'Dither',
      pixels: 5.0,
      settleTime: 30,
      parentId: loopId,
      orderIndex: 4,
    ),
    stopGuideId: StopGuidingNode(
        id: stopGuideId,
        name: 'Stop Guiding',
        parentId: mainSeqId,
        orderIndex: 6),
    warmId: WarmCameraNode(
        id: warmId, ratePerMin: 5, parentId: mainSeqId, orderIndex: 7),
    parkId: ParkNode(
        id: parkId, name: 'Park Mount', parentId: mainSeqId, orderIndex: 8),

    // Emergency fallback sequence (executed when weather is NOT safe)
    // This runs as a parallel branch when the conditional fails
    emergencyId: InstructionSetNode(
      id: emergencyId,
      name: 'Emergency Shutdown',
      parentId: rootId,
      orderIndex: 1,
      childIds: const [emergencyParkId, emergencyNotifyId],
    ),
    emergencyParkId: ParkNode(
      id: emergencyParkId,
      name: 'Emergency Park',
      parentId: emergencyId,
      orderIndex: 0,
    ),
    emergencyNotifyId: NotificationNode(
      id: emergencyNotifyId,
      name: 'Weather Alert',
      title: 'Weather Unsafe - Observatory Parked',
      message:
          'Weather conditions are unsafe. The mount has been parked and the session was not started.',
      level: NotificationLevel.warning,
      parentId: emergencyId,
      orderIndex: 1,
    ),
  };
}

/// Search provider for templates
final templateSearchProvider = StateProvider<String>((ref) => '');

/// Selected template category
final templateCategoryProvider = StateProvider<String?>((ref) => null);

const _templateCategoryOptions = <MapEntry<String?, String>>[
  MapEntry<String?, String>(null, 'All'),
  MapEntry<String?, String>('beginner', 'Beginner'),
  MapEntry<String?, String>('intermediate', 'Intermediate'),
  MapEntry<String?, String>('advanced', 'Advanced'),
  MapEntry<String?, String>('specialized', 'Specialized'),
];

String _inferTemplateCategory(Sequence template) {
  final name = template.name.toLowerCase();

  if (name.contains('first light') ||
      name.contains('one-shot') ||
      name.contains('osc') ||
      name.contains('quick') ||
      name.contains('beginner')) {
    return 'beginner';
  }

  if (name.contains('unattended') ||
      name.contains('all-night') ||
      name.contains('remote observatory') ||
      name.contains('mosaic multi-panel')) {
    return 'advanced';
  }

  if (name.contains('planetary') ||
      name.contains('solar') ||
      name.contains('lunar') ||
      name.contains('comet') ||
      name.contains('asteroid')) {
    return 'specialized';
  }

  return 'intermediate';
}

class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final templatesAsync = ref.watch(sequenceTemplatesProvider);
    final searchQuery = ref.watch(templateSearchProvider);
    final category = ref.watch(templateCategoryProvider);
    final isMobile = Responsive.isMobile(context);
    final snippets = ref.watch(allSnippetsProvider);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        children: [
          // Header
          _TemplatesHeader(colors: colors),

          const SizedBox(height: 24),

          // Snippet summary card (shows count and quick access hint)
          if (!isMobile && snippets.isNotEmpty)
            _SnippetSummaryCard(colors: colors, snippetCount: snippets.length),

          if (!isMobile && snippets.isNotEmpty) const SizedBox(height: 16),

          // Content
          Expanded(
            child: templatesAsync.when(
              data: (templates) {
                var filtered = templates;

                // Apply search filter
                if (searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((t) =>
                          t.name
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()) ||
                          t.description
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()))
                      .toList();
                }

                // Apply category filter
                if (category != null && category.isNotEmpty) {
                  filtered = filtered
                      .where((template) =>
                          _inferTemplateCategory(template) == category)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return _EmptyState(
                      colors: colors, hasSearch: searchQuery.isNotEmpty);
                }

                // Adapt grid for different screen sizes
                final gridSpacing = isMobile ? 12.0 : 20.0;
                final maxExtent = isMobile ? 320.0 : 400.0;

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxExtent,
                    childAspectRatio: isMobile ? 1.2 : 1.3,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: gridSpacing,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _TemplateCard(
                      colors: colors,
                      template: filtered[index],
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 48, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load templates',
                      style: TextStyle(color: colors.textPrimary, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary card showing snippet count and quick access to snippets
class _SnippetSummaryCard extends ConsumerWidget {
  final NightshadeColors colors;
  final int snippetCount;

  const _SnippetSummaryCard({
    required this.colors,
    required this.snippetCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              LucideIcons.bookMarked,
              size: 20,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reusable Snippets',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$snippetCount snippets available. Switch to Builder tab and use the Snippets panel (Ctrl+T) to add them.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            colors: colors,
            icon: LucideIcons.arrowRight,
            label: 'Go to Builder',
            onPressed: () {
              // Switch to Builder tab and show snippets
              ref.read(sequencerTabProvider.notifier).state = 0;
              ref.read(snippetPaletteVisibleProvider.notifier).state = true;
            },
          ),
        ],
      ),
    );
  }
}

class _TemplatesHeader extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _TemplatesHeader({required this.colors});

  @override
  ConsumerState<_TemplatesHeader> createState() => _TemplatesHeaderState();
}

class _TemplatesHeaderState extends ConsumerState<_TemplatesHeader> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 600;

    if (isMobile || isNarrow) {
      return _buildMobileHeader();
    }
    return _buildDesktopHeader();
  }

  Widget _buildMobileHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row with save button
        Row(
          children: [
            Expanded(
              child: Text(
                'Templates',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: widget.colors.textPrimary,
                ),
              ),
            ),
            // Quick-start wizard
            NightshadeButton(
              label: 'Wizard',
              icon: LucideIcons.wand2,
              size: ButtonSize.small,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const QuickStartWizardDialog(),
                );
              },
            ),
            const SizedBox(width: 8),
            // Save current as template button
            NightshadeButton(
              label: 'Save',
              icon: LucideIcons.save,
              size: ButtonSize.small,
              onPressed: () => _showSaveTemplateDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search field - full width on mobile
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search,
                  size: 16, color: widget.colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    ref.read(templateSearchProvider.notifier).state = value;
                  },
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search templates...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: widget.colors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    ref.read(templateSearchProvider.notifier).state = '';
                  },
                  child: Icon(LucideIcons.x,
                      size: 16, color: widget.colors.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _CategoryFilterChips(colors: widget.colors),
      ],
    );
  }

  Widget _buildDesktopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Title
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sequence Templates',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Start with a template or save your sequences for reuse',
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Search - flexible width based on available space
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 250),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search,
                          size: 16, color: widget.colors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            ref.read(templateSearchProvider.notifier).state =
                                value;
                          },
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: widget.colors.textMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            ref.read(templateSearchProvider.notifier).state =
                                '';
                          },
                          child: Icon(LucideIcons.x,
                              size: 16, color: widget.colors.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Quick-start wizard button
            _ActionButton(
              colors: widget.colors,
              icon: LucideIcons.wand2,
              label: 'Quick-Start Wizard',
              isPrimary: false,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const QuickStartWizardDialog(),
                );
              },
            ),

            const SizedBox(width: 8),

            // Save current as template button
            _ActionButton(
              colors: widget.colors,
              icon: LucideIcons.save,
              label: 'Save as Template',
              isPrimary: true,
              onPressed: () => _showSaveTemplateDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CategoryFilterChips(colors: widget.colors),
      ],
    );
  }

  void _showSaveTemplateDialog(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);
    if (currentSequence == null) {
      context.showErrorSnackBar('No sequence to save as template');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _SaveTemplateDialog(
        colors: widget.colors,
        sequence: currentSequence,
      ),
    );
  }
}

class _CategoryFilterChips extends ConsumerWidget {
  final NightshadeColors colors;

  const _CategoryFilterChips({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(templateCategoryProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _templateCategoryOptions.map((option) {
          final value = option.key;
          final label = option.value;
          final selected = value == null
              ? selectedCategory == null
              : selectedCategory == value;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              label: Text(label),
              onSelected: (_) {
                ref.read(templateCategoryProvider.notifier).state = value;
              },
              selectedColor: colors.primary.withValues(alpha: 0.16),
              backgroundColor: colors.surfaceAlt,
              side: BorderSide(
                color: selected ? colors.primary : colors.border,
              ),
              labelStyle: TextStyle(
                color: selected ? colors.primary : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              checkmarkColor: colors.primary,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? _isHovered
                    ? widget.colors.primary.withValues(alpha: 0.9)
                    : widget.colors.primary
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(color: widget.colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color:
                    widget.isPrimary ? onPrimary : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? onPrimary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence template;

  const _TemplateCard({
    required this.colors,
    required this.template,
  });

  @override
  ConsumerState<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends ConsumerState<_TemplateCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  IconData _getTemplateIcon() {
    final name = widget.template.name.toLowerCase();
    // Beginner templates
    if (name.contains('first light')) return LucideIcons.sparkles;
    if (name.contains('osc') || name.contains('one-shot')) {
      return LucideIcons.camera;
    }
    if (name.contains('quick')) return LucideIcons.zap;
    if (name.contains('beginner')) return LucideIcons.graduationCap;
    // Intermediate templates
    if (name.contains('ha-oiii') || name.contains('bicolor')) {
      return LucideIcons.contrast;
    }
    if (name.contains('sho') || name.contains('hubble')) {
      return LucideIcons.waves;
    }
    if (name.contains('lrgb')) return LucideIcons.palette;
    if (name.contains('narrowband')) return LucideIcons.waves;
    if (name.contains('multi-target')) return LucideIcons.list;
    if (name.contains('mosaic')) return LucideIcons.layoutGrid;
    // Specialized templates
    if (name.contains('planetary')) return LucideIcons.orbit;
    if (name.contains('unattended') || name.contains('all-night')) {
      return LucideIcons.moon;
    }
    if (name.contains('comet') || name.contains('asteroid')) {
      return LucideIcons.move;
    }
    if (name.contains('solar')) return LucideIcons.sun;
    if (name.contains('lunar')) return LucideIcons.moonStar;
    if (name.contains('remote') || name.contains('observatory')) {
      return LucideIcons.radio;
    }
    return LucideIcons.fileStack;
  }

  Color _getTemplateColor() {
    final name = widget.template.name.toLowerCase();
    // Beginner templates - green/info
    if (name.contains('first light')) return widget.colors.success;
    if (name.contains('osc') || name.contains('one-shot')) {
      return widget.colors.info;
    }
    if (name.contains('quick')) return widget.colors.success;
    if (name.contains('beginner')) return widget.colors.info;
    // Intermediate templates - primary/accent
    if (name.contains('ha-oiii') || name.contains('bicolor')) {
      return widget.colors.accent;
    }
    if (name.contains('sho') || name.contains('hubble')) {
      return widget.colors.accent;
    }
    if (name.contains('lrgb')) return widget.colors.primary;
    if (name.contains('narrowband')) return widget.colors.accent;
    if (name.contains('multi-target')) return widget.colors.primary;
    if (name.contains('mosaic')) return widget.colors.warning;
    // Specialized templates - warning
    if (name.contains('planetary')) return widget.colors.warning;
    if (name.contains('unattended') || name.contains('all-night')) {
      return widget.colors.warning;
    }
    if (name.contains('comet') || name.contains('asteroid')) {
      return widget.colors.warning;
    }
    if (name.contains('solar')) return widget.colors.warning;
    if (name.contains('lunar')) return widget.colors.warning;
    if (name.contains('remote') || name.contains('observatory')) {
      return widget.colors.warning;
    }
    return widget.colors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    final templateColor = _getTemplateColor();

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _animController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _animController.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? templateColor.withValues(alpha: 0.6)
                  : widget.colors.border,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: templateColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: () => _useTemplate(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and actions
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: templateColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getTemplateIcon(),
                          size: 24,
                          color: templateColor,
                        ),
                      ),
                      const Spacer(),
                      if (_isHovered) ...[
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.copy,
                          tooltip: 'Duplicate',
                          onPressed: () => _duplicateTemplate(context),
                        ),
                        const SizedBox(width: 4),
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.pencil,
                          tooltip: 'Edit',
                          onPressed: () => _editTemplate(context),
                        ),
                        const SizedBox(width: 4),
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.trash2,
                          tooltip: 'Delete',
                          color: widget.colors.error,
                          onPressed: () => _deleteTemplate(context),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.template.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Description
                  Expanded(
                    child: Text(
                      widget.template.description.isEmpty
                          ? 'No description'
                          : widget.template.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Footer
                  Row(
                    children: [
                      // Stats
                      Row(
                        children: [
                          Icon(LucideIcons.layoutList,
                              size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.template.nodes.length} nodes',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          Icon(LucideIcons.calendar,
                              size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMd().format(widget.template.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Use button
                      AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: templateColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.play,
                                  size: 12, color: onPrimary),
                              const SizedBox(width: 6),
                              Text(
                                'Use',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _useTemplate(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);

    // Check if there are existing targets in the current sequence
    final existingTargets = currentSequence?.targetHeaders ?? [];

    if (existingTargets.length > 1) {
      // Multiple targets - prompt user to choose
      _showTargetSelectionDialog(context, existingTargets);
    } else if (existingTargets.length == 1) {
      // Single target - merge directly
      _applyTemplateToTarget(context, existingTargets.first);
    } else {
      // No existing targets - create a new sequence from template
      _createNewSequenceFromTemplate(context);
    }
  }

  void _showTargetSelectionDialog(
      BuildContext context, List<TargetHeaderNode> targets) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Icon(LucideIcons.target, size: 20, color: widget.colors.warning),
            const SizedBox(width: 12),
            Text(
              'Select Target',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which target should "${widget.template.name}" be added to?',
              style: TextStyle(color: widget.colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...targets.map((target) => _TargetOption(
                  colors: widget.colors,
                  target: target,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _applyTemplateToTarget(context, target);
                  },
                )),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  void _applyTemplateToTarget(BuildContext context, TargetHeaderNode target) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    sequenceNotifier.mergeTemplateNodes(
      templateNodes: widget.template.nodes,
      templateRootId: widget.template.rootNodeId,
      targetId: target.id,
    );

    // Switch to the Builder tab so user can see the result
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showSuccessSnackBar(
        'Added "${widget.template.name}" to ${target.targetName}');
  }

  void _createNewSequenceFromTemplate(BuildContext context) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    // Generate new IDs for all nodes
    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    // Clone nodes with new IDs and updated references
    for (final entry in widget.template.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId =
          oldNode.parentId != null ? idMapping[oldNode.parentId] : null;
      final newChildIds =
          oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    // Get the new root node ID
    final newRootId = widget.template.rootNodeId != null
        ? idMapping[widget.template.rootNodeId]
        : null;

    final newSequence = Sequence(
      name: '${widget.template.name} - Copy',
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    // Load the sequence
    sequenceNotifier.loadSequence(newSequence);

    // Switch to the Builder tab so user can see the loaded sequence
    ref.read(sequencerTabProvider.notifier).state = 0;

    context
        .showSuccessSnackBar('Created sequence from "${widget.template.name}"');
  }

  void _editTemplate(BuildContext context) {
    // Load the template for editing and switch to Builder tab
    // Create a copy so we don't modify the original template
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    for (final entry in widget.template.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId =
          oldNode.parentId != null ? idMapping[oldNode.parentId] : null;
      final newChildIds =
          oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    final newRootId = widget.template.rootNodeId != null
        ? idMapping[widget.template.rootNodeId]
        : null;

    final editableSequence = Sequence(
      name: widget.template.name,
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    ref.read(currentSequenceProvider.notifier).loadSequence(editableSequence);
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showInfoSnackBar('Editing "${widget.template.name}"');
  }

  Future<void> _duplicateTemplate(BuildContext context) async {
    // Check if template has a database ID
    final dbId = widget.template.databaseId;
    if (dbId != null) {
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        await repository.duplicateSequence(
            dbId, '${widget.template.name} (Copy)');

        // Refresh the templates list
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    } else {
      // Built-in template - save a copy to database
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        final newTemplate = Sequence(
          name: '${widget.template.name} (Copy)',
          description: widget.template.description,
          nodes: widget.template.nodes,
          rootNodeId: widget.template.rootNodeId,
          isTemplate: true,
        );
        await repository.saveSequence(newTemplate, isTemplate: true);

        // Refresh the templates list
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    }
  }

  void _deleteTemplate(BuildContext context) {
    // Check if this is a built-in template (no database ID)
    final dbId = widget.template.databaseId;
    if (dbId == null) {
      context.showInfoSnackBar('Built-in templates cannot be deleted');
      return;
    }

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Delete Template',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.template.name}"? This action cannot be undone.',
          style: TextStyle(color: widget.colors.textSecondary),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              try {
                final repository = ref.read(sequenceRepositoryProvider);
                await repository.deleteSequence(dbId);

                // Refresh the templates list
                ref.invalidate(sequenceTemplatesProvider);

                if (context.mounted) {
                  context
                      .showSuccessSnackBar('Deleted "${widget.template.name}"');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to delete template: $e');
                }
              }
            },
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;

  const _SmallIconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _isHovered
                  ? color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? color : widget.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;
  final bool hasSearch;

  const _EmptyState({
    required this.colors,
    this.hasSearch = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              hasSearch ? LucideIcons.searchX : LucideIcons.fileStack,
              size: 48,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            hasSearch ? 'No templates found' : 'No templates yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term'
                : 'Save your sequences as templates for easy reuse',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveTemplateDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SaveTemplateDialog({
    required this.colors,
    required this.sequence,
  });

  @override
  ConsumerState<_SaveTemplateDialog> createState() =>
      _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends ConsumerState<_SaveTemplateDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sequence.name);
    _descriptionController =
        TextEditingController(text: widget.sequence.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTemplate() async {
    if (_nameController.text.trim().isEmpty) {
      context.showErrorSnackBar('Please enter a template name');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(sequenceRepositoryProvider);

      // Create a new sequence with the template name and description
      final templateSequence = Sequence(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: widget.sequence.nodes,
        rootNodeId: widget.sequence.rootNodeId,
        isTemplate: true,
      );

      // Save to database as a template
      await repository.saveSequence(templateSequence, isTemplate: true);

      // Refresh the templates list
      ref.invalidate(sequenceTemplatesProvider);

      if (mounted) {
        Navigator.pop(context);

        context
            .showSuccessSnackBar('Template "${_nameController.text}" saved!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save template: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 450,
          preferredHeight: 500,
          minWidth: 300,
          minHeight: 400,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      LucideIcons.save,
                      size: 20,
                      color: widget.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save as Template',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Save this sequence for later reuse',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Name field
              Text(
                'Template Name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.colors.border),
                ),
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter template name',
                    hintStyle: TextStyle(
                      color: widget.colors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Description field
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.colors.border),
                ),
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe what this template is for...',
                    hintStyle: TextStyle(
                      color: widget.colors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Info about current sequence
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: widget.colors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This will save ${widget.sequence.nodes.length} nodes from the current sequence.',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  NightshadeButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                  const SizedBox(width: 12),
                  NightshadeButton(
                    label: _isSaving ? 'Saving...' : 'Save Template',
                    icon: _isSaving ? LucideIcons.loader : LucideIcons.save,
                    onPressed: _isSaving ? null : _saveTemplate,
                    size: ButtonSize.small,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A selectable target option for the target selection dialog
class _TargetOption extends StatefulWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final VoidCallback onTap;

  const _TargetOption({
    required this.colors,
    required this.target,
    required this.onTap,
  });

  @override
  State<_TargetOption> createState() => _TargetOptionState();
}

class _TargetOptionState extends State<_TargetOption> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.warning.withValues(alpha: 0.1)
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? widget.colors.warning : widget.colors.border,
              width: _isHovered ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.target,
                  size: 16,
                  color: widget.colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.target.targetName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    Text(
                      'RA: ${_formatRA(widget.target.raHours)} · Dec: ${_formatDec(widget.target.decDegrees)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: _isHovered
                    ? widget.colors.warning
                    : widget.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '';
    return '$sign${decDegrees.toStringAsFixed(1)}°';
  }
}
