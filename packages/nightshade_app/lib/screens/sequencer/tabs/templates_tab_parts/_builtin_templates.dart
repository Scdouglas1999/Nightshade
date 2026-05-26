// Part of ../templates_tab.dart -- extracted for maintainability.
//
// All hand-built SequenceNode-tree literals that ship as first-run templates. Pure data factory; no widget code. Owns _getBuiltInTemplates() plus its _createXxxNodes() helpers.
part of '../templates_tab.dart';

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