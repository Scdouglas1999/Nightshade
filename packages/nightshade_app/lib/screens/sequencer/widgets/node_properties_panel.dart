import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'instruction_node_properties.dart';
import 'logic_node_properties.dart';
import 'node_property_widgets.dart';
import 'node_timing_section.dart';
import 'target_node_properties.dart';

class NodePropertiesPanel extends ConsumerWidget {
  final NightshadeColors colors;
  final ScrollController? scrollController;
  final bool isMobileSheet;
  final VoidCallback? onClose;
  final VoidCallback? onCollapse;

  const NodePropertiesPanel({
    super.key,
    required this.colors,
    this.scrollController,
    this.isMobileSheet = false,
    this.onClose,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNode = ref.watch(selectedNodeProvider);

    if (isMobileSheet) {
      return _buildMobileSheetContent(context, ref, selectedNode);
    }
    return _buildDesktopSidebarContent(context, ref, selectedNode);
  }

  Widget _buildMobileSheetContent(
      BuildContext context, WidgetRef ref, SequenceNode? selectedNode) {
    return Column(
      children: [
        // Handle bar
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header with close button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                LucideIcons.settings2,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Properties',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        Divider(color: colors.border, height: 1),

        // Content
        Expanded(
          child: selectedNode == null
              ? _EmptySelection(colors: colors, isMobile: true)
              : _NodeEditor(
                  colors: colors,
                  node: selectedNode,
                  scrollController: scrollController,
                  isMobile: true,
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarContent(
      BuildContext context, WidgetRef ref, SequenceNode? selectedNode) {
    final headerFontSize = Responsive.fontSize(context, 14);
    final headerIconSize = Responsive.iconSize(context, 16);
    final headerPadding = Responsive.spacing(context, 16);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: Responsive.spacing(context, 48),
            padding: EdgeInsets.symmetric(horizontal: headerPadding),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.settings2,
                  size: headerIconSize,
                  color: colors.textSecondary,
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: Text(
                    'Properties',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: onCollapse,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          LucideIcons.panelRightClose,
                          size: headerIconSize,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: selectedNode == null
                ? _EmptySelection(colors: colors)
                : _NodeEditor(
                    colors: colors,
                    node: selectedNode,
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const _EmptySelection({required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    final primaryFontSize = isMobile ? 16.0 : Responsive.fontSize(context, 14);
    final secondaryFontSize = isMobile ? 14.0 : Responsive.fontSize(context, 12);
    final iconSize = isMobile ? 40.0 : Responsive.iconSize(context, 32);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mousePointer,
            size: iconSize,
            color: colors.textMuted,
          ),
          SizedBox(height: isMobile ? 16 : Responsive.spacing(context, 12)),
          Text(
            'Select a node',
            style: TextStyle(
              fontSize: primaryFontSize,
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 4)),
          Text(
            'to view its properties',
            style: TextStyle(
              fontSize: secondaryFontSize,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeEditor extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final ScrollController? scrollController;
  final bool isMobile;

  const _NodeEditor({
    required this.colors,
    required this.node,
    this.scrollController,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorPadding = isMobile ? 20.0 : Responsive.spacing(context, 16);

    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.all(editorPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node type badge
          _NodeTypeBadge(colors: colors, node: node),
          const SizedBox(height: 16),

          // Name field
          NodePropertyField(
            colors: colors,
            label: 'Name',
            child: NodeTextInput(
              colors: colors,
              value: node.name,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(name: value),
                    );
              },
            ),
          ),

          // Enabled toggle
          NodePropertyField(
            colors: colors,
            label: 'Enabled',
            child: NodeToggleSwitch(
              colors: colors,
              value: node.isEnabled,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(isEnabled: value),
                    );
              },
            ),
          ),

          // Comment field
          NodePropertyField(
            colors: colors,
            label: 'Comment',
            child: NodeTextInput(
              colors: colors,
              value: node.comment ?? '',
              hint: 'Add a note...',
              maxLines: 3,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(
                          comment: value.isEmpty ? null : value),
                    );
              },
            ),
          ),

          const Divider(height: 32),

          // Type-specific properties
          _buildTypeSpecificProperties(ref),

          const SizedBox(height: 24),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: NodeDangerButton(
              colors: colors,
              label: 'Delete Node',
              icon: LucideIcons.trash2,
              onPressed: () {
                ref.read(currentSequenceProvider.notifier).removeNode(node.id);
                ref.read(selectedNodeIdProvider.notifier).state = null;
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Dispatch node type to its property panel using pattern matching.
  /// Adding a new node type requires only a single case entry here.
  static Widget _buildPropertiesForNode(
      NightshadeColors colors, SequenceNode node) {
    return switch (node) {
      ExposureNode n => ExposureProperties(colors: colors, node: n),
      TargetHeaderNode n => TargetGroupProperties(colors: colors, node: n),
      LoopNode n => LoopProperties(colors: colors, node: n),
      CenterNode n => CenterProperties(colors: colors, node: n),
      AutofocusNode n => AutofocusProperties(colors: colors, node: n),
      CoolCameraNode n => CoolCameraProperties(colors: colors, node: n),
      FilterChangeNode n =>
        FilterChangeProperties(colors: colors, node: n),
      DelayNode n => DelayProperties(colors: colors, node: n),
      DitherNode n => DitherProperties(colors: colors, node: n),
      WarmCameraNode n => WarmCameraProperties(colors: colors, node: n),
      RotatorNode n => RotatorProperties(colors: colors, node: n),
      SlewNode n => SlewProperties(colors: colors, node: n),
      WaitTimeNode n => WaitTimeProperties(colors: colors, node: n),
      ConditionalNode n =>
        ConditionalProperties(colors: colors, node: n),
      ParallelNode n => ParallelProperties(colors: colors, node: n),
      RecoveryNode n => RecoveryProperties(colors: colors, node: n),
      NotificationNode n =>
        NotificationProperties(colors: colors, node: n),
      ScriptNode n => ScriptProperties(colors: colors, node: n),
      StartGuidingNode n =>
        StartGuidingProperties(colors: colors, node: n),
      StopGuidingNode _ =>
        SimpleInstructionInfo(colors: colors, node: node),
      ParkNode _ => SimpleInstructionInfo(colors: colors, node: node),
      UnparkNode _ => SimpleInstructionInfo(colors: colors, node: node),
      MeridianFlipNode n =>
        MeridianFlipProperties(colors: colors, node: n),
      OpenDomeNode _ => DomeProperties(colors: colors, node: node),
      CloseDomeNode _ => DomeProperties(colors: colors, node: node),
      ParkDomeNode _ => DomeProperties(colors: colors, node: node),
      PolarAlignmentNode n =>
        PolarAlignmentProperties(colors: colors, node: n),
      OpenCoverNode n => OpenCoverProperties(colors: colors, node: n),
      CloseCoverNode n => CloseCoverProperties(colors: colors, node: n),
      CalibratorOnNode n =>
        CalibratorOnProperties(colors: colors, node: n),
      CalibratorOffNode n =>
        CalibratorOffProperties(colors: colors, node: n),
      InstructionSetNode n =>
        InstructionSetInfo(colors: colors, node: n),
      _ => Builder(builder: (context) => Text(
          'No additional properties',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        )),
    };
  }

  Widget _buildTypeSpecificProperties(WidgetRef ref) {
    final propertiesWidget = _buildPropertiesForNode(colors, node);

    // Add timing section for nodes with meaningful duration
    if (hasMeaningfulDuration(node)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          propertiesWidget,
          const SizedBox(height: 16),
          NodeTimingSection(colors: colors, node: node),
        ],
      );
    }

    return propertiesWidget;
  }
}

class _NodeTypeBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _NodeTypeBadge({required this.colors, required this.node});

  Color _getCategoryColor() {
    switch (node.category) {
      case NodeCategory.instruction:
        return colors.primary;
      case NodeCategory.trigger:
        return colors.warning;
      case NodeCategory.logic:
        return colors.accent;
      case NodeCategory.target:
        return colors.warning;
    }
  }

  IconData _getIcon() {
    switch (node.iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      case 'door-open':
        return LucideIcons.doorOpen;
      case 'door-closed':
        return LucideIcons.doorClosed;
      case 'lightbulb':
        return LucideIcons.lightbulb;
      case 'lightbulb-off':
        return LucideIcons.lightbulbOff;
      default:
        return LucideIcons.box;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor();
    final badgePadding = Responsive.spacing(context, 12);
    final iconBoxSize = Responsive.spacing(context, 40);
    final iconSize = Responsive.iconSize(context, 20);
    final titleFontSize = Responsive.fontSize(context, 14);
    final categoryFontSize = Responsive.fontSize(context, 11);

    return Container(
      padding: EdgeInsets.all(badgePadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getIcon(), size: iconSize, color: color),
          ),
          SizedBox(width: Responsive.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.nodeType,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  node.category.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: categoryFontSize,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
