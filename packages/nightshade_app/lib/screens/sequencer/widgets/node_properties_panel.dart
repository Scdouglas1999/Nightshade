import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'instruction_node_properties.dart';
import 'logic_node_properties.dart';
import 'node_property_widgets.dart';
import 'node_timing_section.dart';
import 'sequence_tree_shortcuts.dart';
import 'target_node_properties.dart';

class NodePropertiesPanel extends ConsumerStatefulWidget {
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
  ConsumerState<NodePropertiesPanel> createState() =>
      _NodePropertiesPanelState();
}

class _NodePropertiesPanelState extends ConsumerState<NodePropertiesPanel> {
  /// Focus scope owned by the panel so the tree's Enter-key shortcut can
  /// hand focus over here. We listen to the provider tick in build() and
  /// call [FocusScopeNode.requestFocus] when it changes; Flutter then
  /// drives focus to the first focusable descendant (usually the first
  /// text field in the editor).
  final FocusScopeNode _scopeNode =
      FocusScopeNode(debugLabel: 'sequence-properties-panel');

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  // Convenience getters so the existing builder methods (kept verbatim
  // below) keep reading `colors`, `onClose`, etc. without `widget.`.
  NightshadeColors get colors => widget.colors;
  ScrollController? get scrollController => widget.scrollController;
  bool get isMobileSheet => widget.isMobileSheet;
  VoidCallback? get onClose => widget.onClose;
  VoidCallback? get onCollapse => widget.onCollapse;

  @override
  Widget build(BuildContext context) {
    final selectedNode = ref.watch(selectedNodeProvider);

    // Tree -> Enter -> jump focus into this panel. The provider is a
    // monotonic tick; we don't care about the value, only that it
    // changed. `ref.listen` is the right primitive for one-shot side
    // effects in build (versus ref.watch which would also rebuild).
    ref.listen<int>(propertiesPanelFocusRequestProvider, (prev, next) {
      if (prev == next) return;
      if (!mounted) return;
      // Defer to next frame so freshly-mounted property editors are in
      // the tree before we request focus on them.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scopeNode.requestFocus();
      });
    });

    final content = isMobileSheet
        ? _buildMobileSheetContent(context, ref, selectedNode)
        : _buildDesktopSidebarContent(context, ref, selectedNode);

    return FocusScope(
      node: _scopeNode,
      child: content,
    );
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
    return EmptyState(
      icon: LucideIcons.mousePointer,
      title: 'Select a node',
      body: 'Choose a sequence step to edit its properties.',
      padding: EdgeInsets.all(
        isMobile ? 24 : Responsive.spacing(context, 18),
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
    // Trust-patch §B: the entire property editor is read-only while a
    // sequence is Running / Paused / Stopping. We surface the lock as a
    // banner at the top and wrap the form in an AbsorbPointer + Opacity
    // so every inner field and the Delete button are visibly disabled.
    // The notifier still throws SequenceLockedException as a last line
    // of defense.
    final canEdit = ref.watch(canEditSequenceProvider);

    final body = SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.all(editorPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!canEdit) ...[
            _SequenceLockedBanner(colors: colors),
            const SizedBox(height: 16),
          ],

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
                      node.copyWith(comment: value.isEmpty ? null : value),
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
              onPressed: canEdit
                  ? () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .removeNode(node.id);
                      ref.read(selectedNodeIdProvider.notifier).state = null;
                    }
                  : null,
            ),
          ),
        ],
      ),
    );

    // When the sequence is locked, the form fields themselves stay visible
    // (so the user can read current values) but are completely inert. The
    // banner inside `body` already explains *why* — no need for a tooltip
    // overlay on top.
    if (!canEdit) {
      return MouseRegion(
        cursor: SystemMouseCursors.forbidden,
        child: AbsorbPointer(
          absorbing: true,
          child: Opacity(
            opacity: 0.55,
            child: body,
          ),
        ),
      );
    }
    return body;
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
      FilterChangeNode n => FilterChangeProperties(colors: colors, node: n),
      DelayNode n => DelayProperties(colors: colors, node: n),
      DitherNode n => DitherProperties(colors: colors, node: n),
      WarmCameraNode n => WarmCameraProperties(colors: colors, node: n),
      RotatorNode n => RotatorProperties(colors: colors, node: n),
      SlewNode n => SlewProperties(colors: colors, node: n),
      WaitTimeNode n => WaitTimeProperties(colors: colors, node: n),
      ConditionalNode n => ConditionalProperties(colors: colors, node: n),
      ParallelNode n => ParallelProperties(colors: colors, node: n),
      RecoveryNode n => RecoveryProperties(colors: colors, node: n),
      NotificationNode n => NotificationProperties(colors: colors, node: n),
      ScriptNode n => ScriptProperties(colors: colors, node: n),
      StartGuidingNode n => StartGuidingProperties(colors: colors, node: n),
      StopGuidingNode _ => SimpleInstructionInfo(colors: colors, node: node),
      ParkNode _ => SimpleInstructionInfo(colors: colors, node: node),
      UnparkNode _ => SimpleInstructionInfo(colors: colors, node: node),
      MeridianFlipNode n => MeridianFlipProperties(colors: colors, node: n),
      OpenDomeNode _ => DomeProperties(colors: colors, node: node),
      CloseDomeNode _ => DomeProperties(colors: colors, node: node),
      ParkDomeNode _ => DomeProperties(colors: colors, node: node),
      PolarAlignmentNode n => PolarAlignmentProperties(colors: colors, node: n),
      OpenCoverNode n => OpenCoverProperties(colors: colors, node: n),
      CloseCoverNode n => CloseCoverProperties(colors: colors, node: n),
      CalibratorOnNode n => CalibratorOnProperties(colors: colors, node: n),
      CalibratorOffNode n => CalibratorOffProperties(colors: colors, node: n),
      InstructionSetNode n => InstructionSetInfo(colors: colors, node: n),
      // `SequenceNode` is sealed — the switch above covers every subtype.
      // Adding a new subtype will produce a compile-time error here.
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

/// Banner shown at the top of the property editor when
/// [canEditSequenceProvider] is false. Mirrors the toolbar's "Sequence
/// Running" indicator language so users build a single mental model:
/// running = locked.
class _SequenceLockedBanner extends StatelessWidget {
  final NightshadeColors colors;

  const _SequenceLockedBanner({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.lock, size: 14, color: colors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing is locked while the sequence is running. '
              'Stop the sequence to make changes.',
              style: TextStyle(
                fontSize: 11,
                color: colors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
