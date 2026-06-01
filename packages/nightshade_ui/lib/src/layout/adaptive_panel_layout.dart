import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../tokens/breakpoint_tokens.dart';

/// How [AdaptivePanelLayout] collapses its secondary panel(s) on a phone.
enum PhonePanelStrategy {
  /// Secondary content lives in a bottom sheet toggled by a handle/button
  /// overlaid on the primary region. The primary region keeps the full screen.
  bottomSheet,

  /// A segmented control switches the whole region between the primary view
  /// and the secondary view (controls).
  segmented,
}

/// Side that the secondary panel sits on in the desktop / tablet split.
enum PanelSide { start, end }

/// One collapsible secondary panel.
@immutable
class AdaptivePanel {
  /// Short title shown on the segmented control / sheet handle / tab.
  final String title;

  /// The panel body.
  final Widget child;

  /// Optional icon for the segmented control / sheet handle.
  final IconData? icon;

  const AdaptivePanel({required this.title, required this.child, this.icon});
}

/// The desktop-resizable / tablet-fixed / phone-collapsing replacement for the
/// old `ResizablePanel` split.
///
/// * **Desktop** (`w >= 1024`): [primary] beside the [secondary] panel(s) with
///   a draggable divider — equivalent to today's `ResizablePanel` so screens do
///   not regress.
/// * **Tablet** (`600 <= w < 1024`): fixed-ratio columns (no drag handle).
/// * **Phone portrait** (`w < 600`): the secondary panel(s) collapse per
///   [phoneStrategy] — a toggled bottom sheet, or a segmented switch between
///   primary and secondary.
/// * **Phone landscape**: if width allows ([landscapeSplitMinWidth]) it shows a
///   fixed side-by-side split (image/canvas left, controls right); otherwise it
///   falls back to the phone-portrait collapse.
///
/// Pass one or two panels in [secondary]. With two panels on desktop they
/// stack vertically inside the side column; on phone they become two segments /
/// two sheet sections.
///
/// ```dart
/// AdaptivePanelLayout(
///   primary: ImageViewer(),
///   secondary: [AdaptivePanel(title: 'Controls', icon: Icons.tune, child: Controls())],
///   phoneStrategy: PhonePanelStrategy.bottomSheet,
///   initialPanelWidth: 320,
/// )
/// ```
class AdaptivePanelLayout extends StatefulWidget {
  /// The dominant region (image / canvas / main content).
  final Widget primary;

  /// One or two collapsible side panels.
  final List<AdaptivePanel> secondary;

  /// Phone collapse strategy (default: [PhonePanelStrategy.bottomSheet]).
  final PhonePanelStrategy phoneStrategy;

  /// Which side the secondary column sits on for the desktop/tablet split.
  final PanelSide panelSide;

  /// Initial / desktop width of the secondary column in logical pixels.
  final double initialPanelWidth;

  /// Minimum drag width (desktop).
  final double minPanelWidth;

  /// Maximum drag width (desktop).
  final double maxPanelWidth;

  /// Fraction of width given to the secondary column on tablet (fixed).
  final double tabletPanelFraction;

  /// Minimum total width before phone *landscape* uses a side-by-side split
  /// instead of collapsing. Defaults to 560.
  final double landscapeSplitMinWidth;

  /// Label for the primary segment in [PhonePanelStrategy.segmented].
  final String primarySegmentLabel;

  /// Optional icon for the primary segment.
  final IconData? primarySegmentIcon;

  /// Called when the panel is resized on desktop (final width).
  final ValueChanged<double>? onPanelWidthChanged;

  const AdaptivePanelLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.phoneStrategy = PhonePanelStrategy.bottomSheet,
    this.panelSide = PanelSide.end,
    this.initialPanelWidth = 320,
    this.minPanelWidth = 240,
    this.maxPanelWidth = 560,
    this.tabletPanelFraction = 0.38,
    this.landscapeSplitMinWidth = 560,
    this.primarySegmentLabel = 'View',
    this.primarySegmentIcon,
    this.onPanelWidthChanged,
  }) : assert(secondary.length >= 1 && secondary.length <= 2,
            'AdaptivePanelLayout takes one or two secondary panels');

  @override
  State<AdaptivePanelLayout> createState() => _AdaptivePanelLayoutState();
}

class _AdaptivePanelLayoutState extends State<AdaptivePanelLayout> {
  late double _panelWidth = widget.initialPanelWidth;

  // Phone state.
  bool _sheetOpen = false;
  int _segment = 0; // 0 = primary, 1.. = secondary panels.

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isLandscape = w > h;

        if (BreakpointTokens.isPhone(w)) {
          // Phone landscape with enough width: a fixed side-by-side split.
          if (isLandscape && w >= widget.landscapeSplitMinWidth) {
            return _buildFixedSplit(
              context,
              panelWidth: (w * 0.42).clamp(220.0, 360.0),
            );
          }
          return _buildPhoneCollapsed(context);
        }

        if (BreakpointTokens.isAtLeastDesktop(w)) {
          // Desktop: resizable split.
          return _buildResizableSplit(context, available: w);
        }

        // Tablet: fixed-ratio split.
        final panelWidth =
            (w * widget.tabletPanelFraction).clamp(220.0, 420.0);
        return _buildFixedSplit(context, panelWidth: panelWidth);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop / tablet splits
  // ---------------------------------------------------------------------------

  Widget _secondaryColumn() {
    final children = <Widget>[];
    for (var i = 0; i < widget.secondary.length; i++) {
      if (i > 0) {
        children.add(const SizedBox(height: NightshadeTokens.spaceSm));
      }
      children.add(Expanded(child: widget.secondary[i].child));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _buildFixedSplit(BuildContext context, {required double panelWidth}) {
    final colors = context.nightshadeColors;
    final divider = Container(width: 1, color: colors.border);
    final panel = SizedBox(width: panelWidth, child: _secondaryColumn());
    final primary = Expanded(child: widget.primary);

    return Row(
      children: widget.panelSide == PanelSide.start
          ? [panel, divider, primary]
          : [primary, divider, panel],
    );
  }

  Widget _buildResizableSplit(BuildContext context,
      {required double available}) {
    final colors = context.nightshadeColors;
    // Clamp the live width to what fits, leaving room for the primary region.
    final maxForPanel =
        (available - 240).clamp(widget.minPanelWidth, widget.maxPanelWidth);
    final width = _panelWidth.clamp(widget.minPanelWidth, maxForPanel);

    final handle = _ResizeHandle(
      side: widget.panelSide,
      color: colors.border.withValues(alpha: 0.35),
      activeColor: colors.borderHighlight,
      onDelta: (dx) {
        setState(() {
          // Dragging the divider toward the panel shrinks it.
          final delta = widget.panelSide == PanelSide.end ? -dx : dx;
          _panelWidth =
              (width + delta).clamp(widget.minPanelWidth, maxForPanel);
        });
        widget.onPanelWidthChanged?.call(_panelWidth);
      },
    );

    final panel = SizedBox(width: width, child: _secondaryColumn());
    final primary = Expanded(child: widget.primary);

    return Row(
      children: widget.panelSide == PanelSide.start
          ? [panel, handle, primary]
          : [primary, handle, panel],
    );
  }

  // ---------------------------------------------------------------------------
  // Phone collapse
  // ---------------------------------------------------------------------------

  Widget _buildPhoneCollapsed(BuildContext context) {
    switch (widget.phoneStrategy) {
      case PhonePanelStrategy.bottomSheet:
        return _buildPhoneSheet(context);
      case PhonePanelStrategy.segmented:
        return _buildPhoneSegmented(context);
    }
  }

  Widget _buildPhoneSheet(BuildContext context) {
    final colors = context.nightshadeColors;
    return Stack(
      children: [
        Positioned.fill(child: widget.primary),
        // Toggle handle pinned to the bottom edge.
        if (!_sheetOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _SheetHandleButton(
                label: widget.secondary.first.title,
                icon: widget.secondary.first.icon,
                onTap: () => setState(() => _sheetOpen = true),
              ),
            ),
          ),
        // The sheet itself.
        if (_sheetOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _sheetOpen = false),
              child: ColoredBox(
                color: colors.background.withValues(alpha: 0.55),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: _PhoneSheet(
                      panels: widget.secondary,
                      onClose: () => setState(() => _sheetOpen = false),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneSegmented(BuildContext context) {
    final segments = <_SegmentSpec>[
      _SegmentSpec(
        label: widget.primarySegmentLabel,
        icon: widget.primarySegmentIcon,
      ),
      for (final p in widget.secondary)
        _SegmentSpec(label: p.title, icon: p.icon),
    ];
    final selected = _segment.clamp(0, segments.length - 1);

    final Widget body = selected == 0
        ? widget.primary
        : widget.secondary[selected - 1].child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
          child: _SegmentedControl(
            segments: segments,
            selectedIndex: selected,
            onSelected: (i) => setState(() => _segment = i),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// =============================================================================
// Resize handle (desktop)
// =============================================================================

class _ResizeHandle extends StatefulWidget {
  final PanelSide side;
  final Color color;
  final Color activeColor;
  final ValueChanged<double> onDelta;

  const _ResizeHandle({
    required this.side,
    required this.color,
    required this.activeColor,
    required this.onDelta,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _drag = true),
        onHorizontalDragEnd: (_) => setState(() => _drag = false),
        onHorizontalDragUpdate: (d) => widget.onDelta(d.delta.dx),
        child: Container(
          width: 10,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 2,
              height: double.infinity,
              color: _drag || _hover ? widget.activeColor : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Phone bottom sheet
// =============================================================================

class _SheetHandleButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _SheetHandleButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: Material(
        color: colors.surfaceElevated,
        borderRadius: NightshadeTokens.borderRadiusLg,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: NightshadeTokens.borderRadiusLg,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: NightshadeTokens.borderRadiusLg,
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceLg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon ?? Icons.keyboard_arrow_up,
                    size: 18, color: colors.primary),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.labelLg
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneSheet extends StatelessWidget {
  final List<AdaptivePanel> panels;
  final VoidCallback onClose;

  const _PhoneSheet({required this.panels, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NightshadeTokens.radiusXl),
        ),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle.
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  vertical: NightshadeTokens.spaceSm,
                ),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NightshadeTokens.spaceLg,
                  0,
                  NightshadeTokens.spaceLg,
                  NightshadeTokens.spaceLg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < panels.length; i++) ...[
                      if (i > 0)
                        const SizedBox(height: NightshadeTokens.spaceLg),
                      if (panels.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: NightshadeTokens.spaceSm,
                          ),
                          child: Text(
                            panels[i].title.toUpperCase(),
                            style: NightshadeTypography.overline
                                .copyWith(color: colors.textMuted),
                          ),
                        ),
                      panels[i].child,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Segmented control (phone)
// =============================================================================

class _SegmentSpec {
  final String label;
  final IconData? icon;
  const _SegmentSpec({required this.label, this.icon});
}

class _SegmentedControl extends StatelessWidget {
  final List<_SegmentSpec> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SegmentedControl({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              child: _SegmentButton(
                spec: segments[i],
                isSelected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final _SegmentSpec spec;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.spec,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final fg = isSelected ? colors.onPrimary : colors.textSecondary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: spec.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: NightshadeTokens.borderRadiusSm,
          child: AnimatedContainer(
            duration: NightshadeTokens.durationQuick,
            curve: NightshadeTokens.curveSnappy,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? colors.primary : Colors.transparent,
              borderRadius: NightshadeTokens.borderRadiusSm,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (spec.icon != null) ...[
                  Icon(spec.icon, size: 15, color: fg),
                  const SizedBox(width: NightshadeTokens.spaceXs + 2),
                ],
                Flexible(
                  child: Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.labelSm.copyWith(
                      color: fg,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
