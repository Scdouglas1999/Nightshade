import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_icons.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// One tab in an [AdaptiveTabBar].
@immutable
class AdaptiveTab {
  /// Visible label. On very narrow viewports it may be hidden in favour of the
  /// [icon] (see [AdaptiveTabBar.collapseLabelsWhenTight]).
  final String label;

  /// Optional leading icon. Recommended so the tab stays meaningful when the
  /// label collapses on a compact phone.
  final IconData? icon;

  /// Optional accessibility / tooltip override. Falls back to [label].
  final String? semanticLabel;

  /// Optional key forwarded to the rendered tab button (e.g. tutorial keys).
  final Key? buttonKey;

  const AdaptiveTab({
    required this.label,
    this.icon,
    this.semanticLabel,
    this.buttonKey,
  });
}

/// A horizontal tab control that never overflows.
///
/// Tabs lay out left-to-right. When they do not fit the available width the bar
/// becomes **horizontally scrollable** instead of throwing a `RenderFlex`
/// overflow; the selected tab is kept on screen. The visual style matches
/// [SubTabButton] so this is a near drop-in for the hand-rolled tab rows in
/// analytics / planner / guiding.
///
/// ```dart
/// AdaptiveTabBar(
///   tabs: const [
///     AdaptiveTab(label: 'Session', icon: LucideIcons.activity),
///     AdaptiveTab(label: 'History', icon: LucideIcons.history),
///   ],
///   selectedIndex: _tab,
///   onSelected: (i) => setState(() => _tab = i),
/// )
/// ```
class AdaptiveTabBar extends StatefulWidget {
  /// The tabs, in display order.
  final List<AdaptiveTab> tabs;

  /// Index of the currently selected tab.
  final int selectedIndex;

  /// Called with the tapped tab's index.
  final ValueChanged<int> onSelected;

  /// When true (default) and the viewport is a compact phone, tabs that have an
  /// [AdaptiveTab.icon] drop their text label to save width (the label remains
  /// available as a tooltip / semantics). Tabs without an icon keep their text.
  final bool collapseLabelsWhenTight;

  /// Optional trailing widgets pinned after the tabs (e.g. an overflow action).
  /// They scroll with the tabs.
  final List<Widget> trailing;

  /// Horizontal inset before the first tab and after the last trailing widget.
  final double horizontalPadding;

  const AdaptiveTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.collapseLabelsWhenTight = true,
    this.trailing = const [],
    this.horizontalPadding = NightshadeTokens.spaceLg,
  });

  @override
  State<AdaptiveTabBar> createState() => _AdaptiveTabBarState();
}

class _AdaptiveTabBarState extends State<AdaptiveTabBar> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _tabKeys = [];

  /// Whether there are tabs hidden past each edge. Drives the fade + chevron
  /// affordance: without it, a strip that clips (e.g. six labelled planner tabs
  /// at a 900px window) looked exactly like a strip that fits, so two tabs were
  /// effectively invisible to a desktop user.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    _scrollController.addListener(_updateEdgeAffordances);
  }

  void _updateEdgeAffordances() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // A hair of tolerance: sub-pixel layout leaves ~0.001px of extent that
    // would otherwise flicker the affordance on and off.
    final left = position.pixels > position.minScrollExtent + 0.5;
    final right = position.pixels < position.maxScrollExtent - 0.5;
    if (left == _canScrollLeft && right == _canScrollRight) return;
    setState(() {
      _canScrollLeft = left;
      _canScrollRight = right;
    });
  }

  /// Scroll by roughly one tab-group so a click on the chevron makes visible
  /// progress without skipping past a tab.
  void _nudge(double direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + direction * 160.0).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: NightshadeTokens.durationQuick,
      curve: NightshadeTokens.curveSnappy,
    );
  }

  /// A plain vertical mouse wheel over a horizontal strip does nothing in
  /// Flutter by default, and mouse DRAG is excluded from `dragDevices`, so on
  /// desktop the only way to reach a clipped tab was shift+scroll — which
  /// nothing on screen advertised. Translate vertical wheel deltas into
  /// horizontal scrolling. Horizontal deltas are left alone: the Scrollable
  /// already consumes those, and handling them here would double-scroll.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dx != 0 || event.scrollDelta.dy == 0) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _scrollController.jumpTo(target);
  }

  @override
  void didUpdateWidget(AdaptiveTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSelectedVisible(),
      );
    }
  }

  void _syncKeys() {
    if (_tabKeys.length == widget.tabs.length) return;
    _tabKeys
      ..clear()
      ..addAll(List.generate(widget.tabs.length, (_) => GlobalKey()));
  }

  void _ensureSelectedVisible() {
    if (!mounted || !_scrollController.hasClients) return;
    final index = widget.selectedIndex;
    if (index < 0 || index >= _tabKeys.length) return;
    final keyContext = _tabKeys[index].currentContext;
    if (keyContext == null) return;
    Scrollable.ensureVisible(
      keyContext,
      alignment: 0.5,
      duration: NightshadeTokens.durationQuick,
      curve: NightshadeTokens.curveSnappy,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateEdgeAffordances);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // This bar frequently lives inside a split pane. MediaQuery reports
        // the whole window, which made a 320px side panel render the wide
        // labelled variant on a landscape phone and pushed later tabs
        // offscreen. Respond to the space the bar actually receives.
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final collapseLabels =
            widget.collapseLabelsWhenTight && availableWidth < 480.0;

        // Recheck after layout so the affordance is right on the very first
        // frame (the controller has no clients until then).
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateEdgeAffordances(),
        );

        final strip = Listener(
          onPointerSignal: _handlePointerSignal,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.tabs.length; i++)
                    _AdaptiveTabButton(
                      key: _tabKeys.length > i ? _tabKeys[i] : null,
                      buttonKey: widget.tabs[i].buttonKey,
                      tab: widget.tabs[i],
                      isSelected: i == widget.selectedIndex,
                      hideLabel: collapseLabels && widget.tabs[i].icon != null,
                      onTap: () => widget.onSelected(i),
                    ),
                  ...widget.trailing,
                ],
              ),
            ),
          ),
        );

        if (!_canScrollLeft && !_canScrollRight) return strip;

        // WD-SCI-N4: the chevrons used to be `Positioned` over the strip in a
        // Stack, so at 900 px the right chevron painted ON TOP of the Science
        // tab and it rendered as `S › ce`; after a nudge the left one covered
        // History (`Hi ‹ y`) and the right clipped Diagnostics. A hint that
        // eats the label it is hinting about is worse than no hint. Laying
        // them out beside the strip reserves the width instead of borrowing
        // it, so no glyph is ever painted over.
        //
        // Stable by construction: showing a chevron narrows the viewport,
        // which can only make the strip MORE scrollable; hiding one at an end
        // widens it and clamps the offset to the (smaller) new extent, which
        // leaves that edge still at its stop.
        return Row(
          children: [
            if (_canScrollLeft)
              _EdgeAffordance(onTap: () => _nudge(-1), isLeading: true),
            Expanded(child: strip),
            if (_canScrollRight)
              _EdgeAffordance(onTap: () => _nudge(1), isLeading: false),
          ],
        );
      },
    );
  }
}

/// Android's minimum touch-target edge, in logical pixels.
///
/// Named rather than inlined so the reason survives: this is the number
/// `mobile_tap_target_test` enforces, and the edge affordance failed it.
const double _kMinTapTarget = 48.0;

/// Chevron button shown over an edge that has more tabs behind it.
///
/// A tinted chip rather than a gradient fade on purpose: hosts put this bar on
/// `surface` (sequencer, flat wizard, guiding) *and* on `surfaceAlt` (planner,
/// analytics, science), so any fade colour hard-coded here would show as a band
/// of the wrong shade on half of them. A bordered chip reads as a control on
/// either background.
class _EdgeAffordance extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLeading;

  const _EdgeAffordance({required this.onTap, required this.isLeading});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    // Laid out beside the strip (not positioned over it) — see the Row in
    // `_AdaptiveTabBarState.build`. The tap target keeps its full width so the
    // 48 dp minimum still holds.
    // The TAP TARGET and the CHIP are deliberately different sizes.
    //
    // The chip stays 24x30 — it is a hint beside the strip, and growing it
    // visually would waste width the tabs need. But the interactive area was
    // the same 24x30, which is well under the 48 dp Android minimum and failed
    // `mobile_tap_target_test` on a 360x640 phone ("analytics @ small 360x640
    // has 1 tap target(s) under 48.0dp: 24.0x30.0"). Undersized targets are a
    // real touch failure, not a lint: this one sits at the very edge of the
    // screen, where thumbs are least accurate.
    //
    // So the InkWell fills [_kMinTapTarget] of width with the chip centred
    // inside it as pure decoration.
    return ConstrainedBox(
      // Width AND height: laid out in a Row the affordance no longer inherits
      // the strip's height from a `Positioned`, and a 48x30 target fails the
      // Android 48 dp rule (`mobile_tap_target_test`).
      constraints: const BoxConstraints(
        minWidth: _kMinTapTarget,
        maxWidth: _kMinTapTarget,
        minHeight: _kMinTapTarget,
      ),
      child: Semantics(
        button: true,
        // `Semantics` only publishes SemanticsFlag.isEnabled when `enabled` is
        // given. A button declared without it carries no enabled flag at all,
        // and AT-SPI reads the absence as "not sensitive" — so assistive tech
        // announces a live control as disabled. See the note on the tab button
        // below, where this was measured.
        enabled: true,
        label: isLeading ? 'Scroll tabs left' : 'Scroll tabs right',
        child: Tooltip(
          message: 'More tabs',
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: _kMinTapTarget,
              // Height is unconstrained on purpose: the Row stretches this to
              // the strip's full height, so the target grows with the bar
              // instead of being pinned to 30.
              child: Center(
                child: Material(
                  color: colors.surfaceHover,
                  shape: RoundedRectangleBorder(
                    borderRadius: NightshadeTokens.borderRadiusMd,
                    side: BorderSide(color: colors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 24,
                    height: 30,
                    child: Center(
                      child: Icon(
                        isLeading
                            ? NightshadeIcons.chevronLeft
                            : NightshadeIcons.chevronRight,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveTabButton extends StatefulWidget {
  final AdaptiveTab tab;
  final bool isSelected;
  final bool hideLabel;
  final VoidCallback onTap;
  final Key? buttonKey;

  const _AdaptiveTabButton({
    super.key,
    required this.tab,
    required this.isSelected,
    required this.hideLabel,
    required this.onTap,
    this.buttonKey,
  });

  @override
  State<_AdaptiveTabButton> createState() => _AdaptiveTabButtonState();
}

class _AdaptiveTabButtonState extends State<_AdaptiveTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final tab = widget.tab;

    final backgroundColor = widget.isSelected
        ? Color.alphaBlend(
            colors.primary.withValues(alpha: 0.06),
            colors.surfaceAlt,
          )
        : _isHovered
        ? colors.surfaceHover
        : Colors.transparent;

    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.45)
        : _isHovered
        ? colors.borderHighlight.withValues(alpha: 0.85)
        : Colors.transparent;

    final foreground = widget.isSelected
        ? colors.primary
        : _isHovered
        ? colors.textPrimary
        : colors.textSecondary;

    final showLabel = !widget.hideLabel;

    Widget content = ConstrainedBox(
      // Generous min height keeps the touch target honest on phone.
      constraints: const BoxConstraints(minHeight: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd + 2,
          vertical: NightshadeTokens.spaceSm - 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.icon != null) Icon(tab.icon, size: 16, color: foreground),
            if (tab.icon != null && showLabel)
              const SizedBox(width: NightshadeTokens.spaceSm),
            if (showLabel)
              Text(
                tab.label,
                style: NightshadeTypography.labelSm.copyWith(
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: foreground,
                ),
              ),
          ],
        ),
      ),
    );

    if (!showLabel) {
      content = Tooltip(message: tab.label, child: content);
    }

    return Semantics(
      button: true,
      // Measured on the running app during the GUI drive 2026-08-09: the
      // sequencer's four tabs came off the accessibility tree as
      // `Builder [DISABLED]`, `Templates [DISABLED]`, `Sequences [DISABLED]`,
      // `History [DISABLED]` — every one of them live and clickable. Fifteen
      // controls on that one screen carried the same false flag.
      //
      // `Semantics` publishes SemanticsFlag.isEnabled ONLY when `enabled` is
      // passed; `button: true` alone leaves the flag unset, and AT-SPI treats
      // an interactive node with no enabled/sensitive state as disabled. The
      // `onTap` is non-nullable on this button, so the control is always live.
      enabled: true,
      selected: widget.isSelected,
      label: tab.semanticLabel ?? tab.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          key: widget.buttonKey,
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          margin: const EdgeInsets.only(top: 4, bottom: 4, right: 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: borderColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              hoverColor: Colors.transparent,
              highlightColor: colors.primary.withValues(alpha: 0.06),
              splashColor: colors.primary.withValues(alpha: 0.06),
              borderRadius: NightshadeTokens.borderRadiusMd,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
