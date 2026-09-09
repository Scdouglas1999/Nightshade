import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../accessible_dropdown.dart';
import '../../equipment/dialogs/profile_editor_dialog.dart';
import '../filter_source.dart';
import 'delete_node_confirmation.dart';
import 'live_stacking_properties.dart';
import 'meridian_flip_edit_helper.dart';
import 'node_property_widgets.dart';
import 'node_timing_section.dart';
import 'science_photometry_properties.dart';
import 'smart_exposure_properties.dart';
import 'target_coordinates.dart';
import 'target_node_properties.dart';
import 'target_scheduler_properties.dart';

// File split: the per-node property widgets, input primitives, dispatcher,
// and timing section live in `node_properties_panel_parts/`. The public
// `NodePropertiesPanel` widget stays in this file. Parts share the same
// library scope so private symbols (_NodeEditor, _TextInput, etc.) cross
// files without needing to be promoted.

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
part 'node_properties_panel_parts/_motion_flip_and_polar.dart';

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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline2),
            ),
          ),
        ),

        // Header with close button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceLg,
            vertical: NightshadeTokens.spaceSm,
          ),
          child: SectionTitle(
            icon: LucideIcons.sliders,
            title: selectedNode?.name ?? 'Properties',
            trailing: onClose == null
                ? null
                : NightshadeIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: onClose,
                  ),
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
    // A side panel with no strip: 300 px of content, 16 px padding, each
    // section opening with a SectionTitle (05 §15). The old 48 px "Properties"
    // header bar is gone — a panel that only ever holds one thing does not
    // need a row to say what that thing is, and the SectionTitle already names
    // the node.
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: selectedNode == null
          ? _EmptySelection(colors: colors)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NightshadeTokens.spaceLg,
                    NightshadeTokens.spaceLg,
                    NightshadeTokens.spaceLg,
                    0,
                  ),
                  child: SectionTitle(
                    icon: LucideIcons.sliders,
                    title: selectedNode.name,
                    trailing: onCollapse == null
                        ? null
                        : NightshadeIconButton(
                            icon: LucideIcons.panelRightClose,
                            tooltip: 'Collapse panel',
                            size: IconButtonSize.sm,
                            onPressed: onCollapse,
                          ),
                  ),
                ),
                Expanded(
                  child: _NodeEditor(
                    colors: colors,
                    node: selectedNode,
                  ),
                ),
                _SelectedNodeBanner(nodeId: selectedNode.id),
              ],
            ),
    );
  }
}

/// The ONE banner the properties column may show: the worst live-validation
/// issue for the selected node, pinned to the bottom (06 §Sequencer).
///
/// The mockup's banner is an "ends after astro dawn" warning. Nothing in the
/// app computes that today, and inventing the calculation would be a new
/// feature in a re-skin — so the slot carries the real per-node problem the
/// validator already found instead of a fabricated one. See
/// reports/observatory/w3-sequencer/notes.md.
class _SelectedNodeBanner extends ConsumerWidget {
  const _SelectedNodeBanner({required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(liveValidationProvider).issuesByNodeId[nodeId];
    if (issues == null || issues.isEmpty) return const SizedBox.shrink();

    // One banner per problem: the worst issue speaks for the node, and the
    // Preflight dialog in the page header lists the rest.
    final worst = issues.reduce(
      (a, b) => a.severity.index >= b.severity.index ? a : b,
    );
    final tone = switch (worst.severity) {
      ValidationSeverity.error => BannerTone.error,
      ValidationSeverity.warning => BannerTone.warning,
      ValidationSeverity.info => BannerTone.info,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        0,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceLg,
      ),
      child: NightshadeBanner(
        title: worst.title,
        message: worst.resolutionHint ?? worst.description,
        tone: tone,
      ),
    );
  }
}
