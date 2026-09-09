import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../dashboard_layout.dart';

class DashboardTile extends StatelessWidget {
  final DashboardTileConfig tile;
  final double width;
  final NightshadeColors colors;
  final Widget child;
  final bool isEditing;
  final CardVariant cardVariant;
  final bool isHero;

  /// When true, the wrapped panel provides its own chrome, so the frame skips
  /// its resting border/background (see DashboardWidgetDefinition.selfChromed).
  final bool selfChromed;
  final void Function(DashboardWidgetId dragged, DashboardWidgetId target)
      onReorder;
  final void Function(DashboardWidgetId id) onResize;
  final void Function(DashboardWidgetId id, bool enabled) onToggleEnabled;

  const DashboardTile({
    super.key,
    required this.tile,
    required this.width,
    required this.colors,
    required this.child,
    required this.isEditing,
    required this.onReorder,
    required this.onResize,
    required this.onToggleEnabled,
    this.cardVariant = CardVariant.standard,
    this.isHero = false,
    this.selfChromed = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<DashboardWidgetId>(
      onWillAcceptWithDetails: (details) =>
          isEditing && details.data != tile.widgetId,
      onAcceptWithDetails: (details) {
        if (isEditing) onReorder(details.data, tile.widgetId);
      },
      builder: (context, candidateData, _) {
        final isDropTarget = candidateData.isNotEmpty;
        final frame = DashboardTileFrame(
          colors: colors,
          isEditing: isEditing,
          isDropTarget: isDropTarget,
          size: tile.size,
          cardVariant: cardVariant,
          isHero: isHero,
          selfChromed: selfChromed,
          onResize: () => onResize(tile.widgetId),
          onHide: () => onToggleEnabled(tile.widgetId, false),
          child: child,
        );

        if (!isEditing) {
          return frame;
        }

        return LongPressDraggable<DashboardWidgetId>(
          data: tile.widgetId,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: width,
              child: Opacity(
                opacity: 0.9,
                child: DashboardTileFrame(
                  colors: colors,
                  isEditing: false,
                  isDropTarget: false,
                  size: tile.size,
                  cardVariant: cardVariant,
                  isHero: isHero,
                  selfChromed: selfChromed,
                  onResize: () {},
                  onHide: () {},
                  child: child,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.4,
            child: frame,
          ),
          child: frame,
        );
      },
    );
  }
}

class DashboardTileFrame extends StatelessWidget {
  final NightshadeColors colors;
  final bool isEditing;
  final bool isDropTarget;
  final DashboardTileSize size;
  final Widget child;
  final CardVariant cardVariant;
  final bool isHero;

  /// When true, the wrapped panel provides its own border/background. The frame
  /// then draws a border only to signal an active highlight state (editing,
  /// drop-target, or hero), and is fully transparent at rest.
  final bool selfChromed;
  final VoidCallback onResize;
  final VoidCallback onHide;

  const DashboardTileFrame({
    super.key,
    required this.colors,
    required this.isEditing,
    required this.isDropTarget,
    required this.size,
    required this.child,
    required this.onResize,
    required this.onHide,
    this.cardVariant = CardVariant.standard,
    this.isHero = false,
    this.selfChromed = false,
  });

  @override
  Widget build(BuildContext context) {
    // Border with hero accent and edit mode highlight. Self-chromed panels draw
    // no resting border (their own card supplies it); they still get the
    // highlight border so editing/drop-target/hero states read correctly.
    final Color? borderColor;
    if (isDropTarget) {
      borderColor = colors.primary.withValues(alpha: 0.7);
    } else if (isEditing) {
      borderColor = colors.primary.withValues(alpha: 0.3);
    } else if (isHero) {
      borderColor = colors.primary.withValues(alpha: 0.2);
    } else {
      borderColor = selfChromed ? null : colors.border;
    }

    return Stack(
      children: [
        // Card container with visual hierarchy
        AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: borderColor == null
                ? null
                : Border.all(
                    color: borderColor,
                    width: isDropTarget ? 2 : (isHero ? 1.5 : 1),
                  ),
          ),
          child: ClipRRect(
            borderRadius: NightshadeTokens.borderRadiusMd,
            child: IgnorePointer(
              ignoring: isEditing,
              child: child,
            ),
          ),
        ),

        // Edit mode drag handle (top-left)
        if (isEditing)
          Positioned(
            top: 8,
            left: 8,
            child: _DragHandleIndicator(colors: colors),
          ),

        // Edit mode controls (top-right) - adjusted for larger touch targets
        if (isEditing)
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NightshadeIconButton(
                  icon: LucideIcons.maximize2,
                  tooltip: 'Resize (${size.label})',
                  size: IconButtonSize.sm,
                  onPressed: onResize,
                ),
                NightshadeIconButton(
                  icon: LucideIcons.eyeOff,
                  tooltip: 'Hide tile',
                  size: IconButtonSize.sm,
                  onPressed: onHide,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Edit mode icon button with expanded touch target (40x40px) for field use.
/// The grip the operator drags a tile by in Edit layout.
class _DragHandleIndicator extends StatelessWidget {
  final NightshadeColors colors;

  const _DragHandleIndicator({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceXs + 2),
      decoration: NightshadeDecorations.panelSelected(colors),
      child: Icon(
        LucideIcons.gripVertical,
        size: 14,
        color: colors.primary,
      ),
    );
  }
}

class DashboardLoading extends StatelessWidget {
  const DashboardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: NightshadeTokens.space4xl),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// The one error pattern: an [EmptyState] with ONE button (05 §12). It replaced
/// a bordered glass card with its own title row, which was a second error style
/// on a screen that already had one.
class DashboardLayoutError extends StatelessWidget {
  final Object error;
  final VoidCallback onReset;
  final String title;
  final String buttonLabel;

  const DashboardLayoutError({
    super.key,
    required this.error,
    required this.onReset,
    this.title = 'The dashboard layout could not be read',
    this.buttonLabel = 'Reset layout',
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.alertTriangle,
      title: title,
      body: '$error',
      action: NightshadeButton(
        label: buttonLabel,
        icon: LucideIcons.refreshCw,
        variant: ButtonVariant.secondary,
        size: ButtonSize.small,
        onPressed: onReset,
      ),
    );
  }
}
