import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sequence/sequence_models.dart';
import '../profiles_provider.dart';
import 'sequencer_defaults.dart';

/// Map a profile's integer binning (1..4) to the [BinningMode] enum used by the
/// palette's default factories. Falls back to 1x1 for any unexpected value
/// because the palette must always produce a runnable default.
BinningMode _binningModeFromInt(int binning) {
  switch (binning) {
    case 1:
      return BinningMode.one;
    case 2:
      return BinningMode.two;
    case 3:
      return BinningMode.three;
    case 4:
      return BinningMode.four;
    default:
      return BinningMode.one;
  }
}

/// Available node types for the palette
final nodePaletteProvider = Provider<List<NodePaletteCategory>>((ref) {
  final defaults = ref.watch(sequencerDefaultsProvider);
  final profile = ref.watch(activeEquipmentProfileProvider);

  // Use profile defaults as fallback when sequencer defaults are not set
  final effectiveGain = defaults.exposureGain ?? profile?.defaultGain;
  final effectiveOffset = defaults.exposureOffset ?? profile?.defaultOffset;
  final effectiveBinning = defaults.exposureBinning != BinningMode.one
      ? defaults.exposureBinning
      : _binningModeFromInt(profile?.defaultBinX ?? 1);
  final effectiveFilter =
      defaults.exposureFilter ?? profile?.filterNames.firstOrNull;

  return [
    NodePaletteCategory(
      name: 'Target',
      icon: 'target',
      items: [
        NodePaletteItem(
          name: 'Target',
          icon: 'target',
          description: 'Root node containing imaging instructions for a target',
          createNode: () => TargetHeaderNode(
            targetName: 'New Target',
            raHours: 0,
            decDegrees: 0,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Imaging',
      icon: 'camera',
      items: [
        NodePaletteItem(
          name: 'Take Exposures',
          icon: 'camera',
          description: 'Capture images with specified settings',
          createNode: () => ExposureNode(
            durationSecs: defaults.exposureDuration,
            count: defaults.exposureCount,
            filter: effectiveFilter,
            gain: effectiveGain,
            offset: effectiveOffset,
            binning: effectiveBinning,
            ditherEvery: defaults.exposureDitherEvery,
          ),
        ),
        NodePaletteItem(
          name: 'Change Filter',
          icon: 'circle',
          description: 'Change the filter wheel position',
          createNode: () => FilterChangeNode(
            filterName: effectiveFilter ?? 'L',
          ),
        ),
        NodePaletteItem(
          name: 'Dither',
          icon: 'shuffle',
          description: 'Dither the guiding for better results',
          createNode: () => DitherNode(
            pixels: defaults.ditherPixels,
            settleTime: defaults.ditherSettleTime,
            settlePixels: defaults.ditherSettlePixels,
            settleTimeout: defaults.ditherSettleTimeout,
            raOnly: defaults.ditherRaOnly,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Guiding',
      icon: 'crosshair',
      items: [
        NodePaletteItem(
          name: 'Start Guiding',
          icon: 'crosshair',
          description: 'Start PHD2 guiding and wait for settle',
          createNode: () => StartGuidingNode(
            settlePixels: defaults.ditherSettlePixels,
            settleTime: defaults.ditherSettleTime,
          ),
        ),
        NodePaletteItem(
          name: 'Stop Guiding',
          icon: 'x-circle',
          description: 'Stop PHD2 guiding',
          createNode: () => StopGuidingNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Mount',
      icon: 'compass',
      items: [
        NodePaletteItem(
          name: 'Slew to Target',
          icon: 'compass',
          description: 'Slew mount to target coordinates',
          createNode: () => SlewNode(),
        ),
        NodePaletteItem(
          name: 'Center Target',
          icon: 'crosshair',
          description: 'Plate solve and center on target',
          createNode: () => CenterNode(),
        ),
        NodePaletteItem(
          name: 'Park Mount',
          icon: 'parking-circle',
          description: 'Park the mount',
          createNode: () => ParkNode(),
        ),
        NodePaletteItem(
          name: 'Unpark Mount',
          icon: 'unlock',
          description: 'Unpark the mount',
          createNode: () => UnparkNode(),
        ),
        NodePaletteItem(
          name: 'Meridian Flip',
          icon: 'refresh-cw',
          description: 'Perform meridian flip',
          createNode: () => MeridianFlipNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Dome',
      icon: 'home',
      items: [
        NodePaletteItem(
          name: 'Open Dome',
          icon: 'home',
          description: 'Open dome shutter',
          createNode: () => OpenDomeNode(),
        ),
        NodePaletteItem(
          name: 'Close Dome',
          icon: 'home',
          description: 'Close dome shutter',
          createNode: () => CloseDomeNode(),
        ),
        NodePaletteItem(
          name: 'Park Dome',
          icon: 'parking-circle',
          description: 'Park the dome',
          createNode: () => ParkDomeNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Flat Panel',
      icon: 'lightbulb',
      items: [
        NodePaletteItem(
          name: 'Open Cover',
          icon: 'door-open',
          description: 'Open dust cover / flat panel lid',
          createNode: () => OpenCoverNode(),
        ),
        NodePaletteItem(
          name: 'Close Cover',
          icon: 'door-closed',
          description: 'Close dust cover / flat panel lid',
          createNode: () => CloseCoverNode(),
        ),
        NodePaletteItem(
          name: 'Calibrator On',
          icon: 'lightbulb',
          description: 'Turn on flat panel at brightness',
          createNode: () => CalibratorOnNode(),
        ),
        NodePaletteItem(
          name: 'Calibrator Off',
          icon: 'lightbulb-off',
          description: 'Turn off flat panel light',
          createNode: () => CalibratorOffNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Focus',
      icon: 'focus',
      items: [
        NodePaletteItem(
          name: 'Autofocus',
          icon: 'focus',
          description: 'Run autofocus routine',
          createNode: () => AutofocusNode(
            stepSize: defaults.autofocusStepSize,
            stepsOut: defaults.autofocusStepsOut,
            exposureDuration: defaults.autofocusExposureDuration,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Camera',
      icon: 'aperture',
      items: [
        NodePaletteItem(
          name: 'Cool Camera',
          icon: 'snowflake',
          description: 'Cool camera to target temperature',
          createNode: () => CoolCameraNode(),
        ),
        NodePaletteItem(
          name: 'Warm Camera',
          icon: 'flame',
          description: 'Warm camera at controlled rate',
          createNode: () => WarmCameraNode(),
        ),
        NodePaletteItem(
          name: 'Move Rotator',
          icon: 'rotate-cw',
          description: 'Move rotator to angle',
          createNode: () => RotatorNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Logic',
      icon: 'workflow',
      items: [
        NodePaletteItem(
          name: 'Instruction Set',
          icon: 'list',
          description: 'Group instructions sequentially (no loop)',
          createNode: () => InstructionSetNode(),
        ),
        NodePaletteItem(
          name: 'Loop',
          icon: 'repeat',
          description: 'Repeat instructions',
          createNode: () => LoopNode(),
        ),
        NodePaletteItem(
          name: 'Conditional',
          icon: 'git-merge',
          description: 'Execute if condition is met',
          createNode: () => ConditionalNode(),
        ),
        NodePaletteItem(
          name: 'Parallel',
          icon: 'git-branch',
          description: 'Execute instructions in parallel',
          createNode: () => ParallelNode(),
        ),
        NodePaletteItem(
          name: 'Recovery',
          icon: 'shield-check',
          description: 'Handle errors with recovery logic',
          createNode: () => RecoveryNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Timing',
      icon: 'clock',
      items: [
        NodePaletteItem(
          name: 'Wait for Time',
          icon: 'clock',
          description: 'Wait until specific time',
          createNode: () => WaitTimeNode(),
        ),
        NodePaletteItem(
          name: 'Delay',
          icon: 'timer',
          description: 'Wait for duration',
          createNode: () => DelayNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Utilities',
      icon: 'wrench',
      items: [
        NodePaletteItem(
          name: 'Notification',
          icon: 'bell',
          description: 'Send notification',
          createNode: () => NotificationNode(),
        ),
        NodePaletteItem(
          name: 'Run Script',
          icon: 'code',
          description: 'Execute custom script',
          createNode: () => ScriptNode(),
        ),
      ],
    ),
  ];
});

class NodePaletteCategory {
  final String name;
  final String icon;
  final List<NodePaletteItem> items;

  NodePaletteCategory({
    required this.name,
    required this.icon,
    required this.items,
  });
}

class NodePaletteItem {
  final String name;
  final String icon;
  final String description;
  final SequenceNode Function() createNode;
  final List<SequenceNode> Function()? createChildren;

  NodePaletteItem({
    required this.name,
    required this.icon,
    required this.description,
    required this.createNode,
    this.createChildren,
  });
}
