import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(AdaptiveTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 480.0;
    final collapseLabels = widget.collapseLabelsWhenTight && compact;

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
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
            if (tab.icon != null)
              Icon(tab.icon, size: 16, color: foreground),
            if (tab.icon != null && showLabel)
              const SizedBox(width: NightshadeTokens.spaceSm),
            if (showLabel)
              Text(
                tab.label,
                style: NightshadeTypography.labelSm.copyWith(
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
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
