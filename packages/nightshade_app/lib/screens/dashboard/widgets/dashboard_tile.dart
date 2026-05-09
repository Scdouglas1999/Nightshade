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
  });

  @override
  Widget build(BuildContext context) {
    // Hero treatment: premium shadows and accent glow for live preview
    final List<BoxShadow> shadow;
    if (isHero) {
      shadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: colors.primary.withValues(alpha: 0.1),
          blurRadius: 16,
          spreadRadius: -2,
        ),
      ];
    } else if (cardVariant == CardVariant.elevated) {
      shadow = NightshadeTokens.elevationLevel1to2;
    } else if (cardVariant == CardVariant.subtle) {
      shadow = [];
    } else {
      shadow = NightshadeTokens.elevationLevel1;
    }

    // Border with hero accent and edit mode highlight
    final borderColor = isDropTarget
        ? colors.primary.withValues(alpha: 0.7)
        : isEditing
            ? colors.primary.withValues(alpha: 0.3)
            : isHero
                ? colors.primary.withValues(alpha: 0.2)
                : colors.border;

    return Stack(
      children: [
        // Card container with visual hierarchy
        AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(
              color: borderColor,
              width: isDropTarget ? 2 : (isHero ? 1.5 : 1),
            ),
            boxShadow: shadow,
          ),
          child: ClipRRect(
            borderRadius: NightshadeTokens.borderRadiusMd,
            child: IgnorePointer(
              ignoring: isEditing,
              child: child,
            ),
          ),
        ),

        // Hero glow effect (top edge accent)
        if (isHero)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.6),
                    colors.accent.withValues(alpha: 0.3),
                    colors.primary.withValues(alpha: 0.1),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
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
                _EditIconButton(
                  icon: LucideIcons.maximize2,
                  tooltip: 'Resize (${size.label})',
                  onTap: onResize,
                ),
                // Touch areas now adjacent at 40px each
                _EditIconButton(
                  icon: LucideIcons.eyeOff,
                  tooltip: 'Hide tile',
                  onTap: onHide,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Edit mode icon button with expanded touch target (40x40px) for field use.
class _EditIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _EditIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Tooltip(
      message: tooltip,
      // Expanded touch target: 40x40px for easier tapping
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Center(
              // Visual element stays compact at 26x26px
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle indicator shown on tiles in edit mode.
///
/// Provides visual affordance that tiles can be long-pressed and dragged.
class _DragHandleIndicator extends StatelessWidget {
  final NightshadeColors colors;

  const _DragHandleIndicator({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        LucideIcons.gripVertical,
        size: 14,
        color: colors.primary.withValues(alpha: 0.8),
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
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class DashboardLayoutError extends StatelessWidget {
  final Object error;
  final VoidCallback onReset;
  final String title;
  final String buttonLabel;

  const DashboardLayoutError({
    super.key,
    required this.error,
    required this.onReset,
    this.title = 'Dashboard Layout Error',
    this.buttonLabel = 'Reset Layout',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return DashboardGlassCardInline(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: colors.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: buttonLabel,
              icon: LucideIcons.refreshCw,
              variant: ButtonVariant.outline,
              size: ButtonSize.medium,
              onPressed: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline glass card used by DashboardLayoutError (avoids circular import with glass_card.dart)
class DashboardGlassCardInline extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final EdgeInsets padding;

  const DashboardGlassCardInline({
    super.key,
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
