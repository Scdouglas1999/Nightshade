// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// The node-type badge shown in property-panel headers. The form primitives
// (text/number/toggle/dropdown inputs, property-field wrapper, quick-time and
// destructive-action buttons) now live in the public `node_property_widgets.dart`
// library — the panel imports them directly, so the formerly-duplicated private
// copies that lived here have been removed in favour of a single source of truth.
part of '../node_properties_panel.dart';

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
      case 'layers':
        return LucideIcons.layers;
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
      default:
        return LucideIcons.box;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Icon(_getIcon(), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.nodeType,
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
                Text(
                  node.category.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
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
