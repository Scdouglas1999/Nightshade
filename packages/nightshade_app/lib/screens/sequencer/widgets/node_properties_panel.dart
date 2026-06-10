import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';
import 'delete_node_confirmation.dart';
import 'live_stacking_properties.dart';
import 'meridian_flip_edit_helper.dart';
import 'node_property_widgets.dart';
import 'smart_exposure_properties.dart';
import 'target_node_properties.dart';
import 'target_scheduler_properties.dart';


// ---------------------------------------------------------------------------
// File split: the per-node property widgets, input primitives, dispatcher,
// and timing section live in `node_properties_panel_parts/`. The public
// `NodePropertiesPanel` widget stays in this file. Parts share the same
// library scope so private symbols (_NodeEditor, _TextInput, etc.) cross
// files without needing to be promoted.
// ---------------------------------------------------------------------------

part 'node_properties_panel_parts/_input_primitives.dart';
part 'node_properties_panel_parts/_node_editor.dart';
part 'node_properties_panel_parts/_exposure_rich.dart';
part 'node_properties_panel_parts/_adaptive_exposure_section.dart';
part 'node_properties_panel_parts/_capture_properties.dart';
part 'node_properties_panel_parts/_capture_rich.dart';
part 'node_properties_panel_parts/_guiding_properties.dart';
part 'node_properties_panel_parts/_motion_rich.dart';
part 'node_properties_panel_parts/_flow_properties.dart';
part 'node_properties_panel_parts/_misc_properties.dart';
part 'node_properties_panel_parts/_plugin_properties.dart';
part 'node_properties_panel_parts/_timing_section.dart';

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
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
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
                  fontSize: NightshadeTypography.fontSize18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.settings2,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Properties',
                    style: NightshadeTypography.labelStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: onCollapse,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          LucideIcons.panelRightClose,
                          size: 16,
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
