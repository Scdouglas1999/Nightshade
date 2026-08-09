part of '../settings_widgets.dart';

class SettingsSection extends StatelessWidget {
  final String title;

  final List<Widget> children;

  final bool isMobile;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A search result can name this HEADING as well as a row: the
        // generated index cannot tell a `SettingsSection(title:)` from a
        // `SettingRow(title:)`, so "Dithering", "Meridian Flip" and
        // "Notification Events" are all offered as tappable results. Without
        // this the heading results opened the page at the top and marked
        // nothing — the dead end the row results exist to end.
        _HighlightedRow(
          active: SettingsRowHighlight.targets(context, title: title),
          child: Text(
            title,
            style: (isMobile
                    ? NightshadeTypography.label
                    : NightshadeTypography.h5)
                .copyWith(color: colors.textPrimary),
          ),
        ),
        SizedBox(
            height:
                isMobile ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg),
        NightshadeCard(
          variant: CardVariant.subtle,
          borderRadius: isMobile ? 10 : NightshadeTokens.radiusLg,
          child: Column(
            children: children,
          ),
        ),
        SizedBox(height: isMobile ? NightshadeTokens.spaceXl : 28),
      ],
    );
  }
}

/// The row a settings search asked to be shown, published to every
/// [SettingRow] under the detail pane.
///
/// Search used to hand back a section name and nothing else: typing "Alpaca"
/// opened a long Connection page at the top with no indication of where the
/// match was, even though the index knew exactly which row title had matched.
class SettingsRowHighlight extends InheritedWidget {
  const SettingsRowHighlight({
    super.key,
    required this.rowTitle,
    required super.child,
  });

  /// Title of the row to reveal, or null when nothing is being sought.
  final String? rowTitle;

  static String? titleOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsRowHighlight>()
      ?.rowTitle;

  /// Is the row described by [title]/[subtitle] the one being sought?
  ///
  /// The subtitle counts because the generated search index cannot tell a
  /// `title:` from a `subtitle:` (its pattern has no left word boundary), so a
  /// short subtitle can legitimately be the term the operator recognised and
  /// tapped. Matching only on the title would open the page and then mark
  /// nothing, which is the state this whole mechanism exists to end.
  static bool targets(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) {
    final sought = titleOf(context);
    if (sought == null) return false;
    return sought == title || sought == subtitle;
  }

  @override
  bool updateShouldNotify(SettingsRowHighlight oldWidget) =>
      oldWidget.rowTitle != rowTitle;
}

/// Scrolls its row into view and tints it while it is the search target.
class _HighlightedRow extends StatefulWidget {
  const _HighlightedRow({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_HighlightedRow> createState() => _HighlightedRowState();
}

class _HighlightedRowState extends State<_HighlightedRow> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _reveal();
  }

  @override
  void didUpdateWidget(covariant _HighlightedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reveal();
  }

  /// After the frame that placed this row: the enclosing scroll view does not
  /// exist yet during build, and a settings page mounted by a search result is
  /// laid out in the same frame the target is chosen in.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      color: widget.active
          ? colors.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      child: widget.child,
    );
  }
}

/// A single row in a settings section with an icon, title, optional subtitle, and trailing widget.

class SettingRow extends StatelessWidget {
  final IconData icon;

  final Color? iconColor;

  final String title;

  final String? subtitle;

  final Widget trailing;

  final bool isLast;

  final bool isMobile;

  /// If true, stack the trailing widget below the title on mobile

  final bool stackOnMobile;

  /// Optional field-level help. When supplied, a [helpAffordance] icon is
  /// rendered to the right of the [title] showing the rich tooltip from
  /// [helpFor]. Use only for genuinely non-obvious settings (the same bar as
  /// the imaging-panel rows); leave null for self-evident rows.
  final FieldHelpId? helpId;

  const SettingRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.isLast = false,
    this.isMobile = false,
    this.stackOnMobile = false,
    this.helpId,
  });

  /// The title text plus an optional trailing help affordance. Extracted so
  /// the row and stacked layouts share one definition of "how the title +
  /// help icon look".
  Widget _buildTitle(BuildContext context, NightshadeColors colors) {
    final titleText = Text(
      title,
      style:
          (isMobile ? NightshadeTypography.labelSm : NightshadeTypography.label)
              .copyWith(color: colors.textPrimary),
    );
    final id = helpId;
    if (id == null) {
      return titleText;
    }
    final copy = helpFor(id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: titleText),
        const SizedBox(width: NightshadeTokens.spaceXs),
        helpAffordance(
          context,
          title: copy.title,
          body: copy.body,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final shouldStack = isMobile && stackOnMobile;

    final horizontalPadding = isMobile ? 12.0 : NightshadeTokens.spaceLg;

    final verticalPadding = isMobile ? 12.0 : 14.0;

    final iconSize = isMobile ? 32.0 : 36.0;

    final iconInnerSize = isMobile ? 14.0 : NightshadeTokens.iconSm;

    // The row's title and its trailing control are ONE thing to a screen
    // reader.
    //
    // Without this the switch is a correctly-toggled but ANONYMOUS node:
    // measured on the running app, Settings > General exposed three toggle
    // buttons reading "off/ON/ON" with empty names, so assistive technology
    // could report that something was on without being able to say which
    // setting it was. Merging binds each control to the label beside it.
    return MergeSemantics(
      child: _HighlightedRow(
        active: SettingsRowHighlight.targets(
          context,
          title: title,
          subtitle: subtitle,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding, vertical: verticalPadding),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom:
                        BorderSide(color: colors.border.withValues(alpha: 0.5)),
                  ),
          ),
          child: shouldStack
              ? _buildStackedLayout(context, colors, iconSize, iconInnerSize)
              : _buildRowLayout(context, colors, iconSize, iconInnerSize),
        ),
      ),
    );
  }

  Widget _buildRowLayout(BuildContext context, NightshadeColors colors,
      double iconSize, double iconInnerSize) {
    return Row(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusMd,
          ),
          child: Icon(icon,
              size: iconInnerSize, color: iconColor ?? colors.textSecondary),
        ),
        SizedBox(width: isMobile ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(context, colors),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: NightshadeTypography.captionSm.copyWith(
                    fontSize: isMobile
                        ? NightshadeTypography.fontSize10
                        : NightshadeTypography.fontSize11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Flexible (loose) bounds the trailing slot to the space the title's
        // Expanded leaves free. Finite controls (dropdowns, switches) keep their
        // intrinsic size; a content-sized [Wrap] trailing (e.g. the Integrations
        // plugin row's pill + Configure + switch cluster) gets a finite width to
        // wrap within instead of demanding unbounded width and overflowing.
        //
        // Align pins the control to the card's right edge. Without it the
        // control sat at the LEFT of its flexible half — i.e. at the row's
        // horizontal midpoint — which looks correct at ~1600px only by
        // coincidence and stranded every control mid-screen with ~2100px of
        // empty card beside it on an ultrawide monitor (audit 2026-07-29).
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    );
  }

  Widget _buildStackedLayout(BuildContext context, NightshadeColors colors,
      double iconSize, double iconInnerSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusMd,
              ),
              child: Icon(icon,
                  size: iconInnerSize,
                  color: iconColor ?? colors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(context, colors),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: NightshadeTypography.captionSm.copyWith(
                          fontSize: NightshadeTypography.fontSize10,
                          color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.only(left: iconSize + 10),
          child: trailing,
        ),
      ],
    );
  }
}

/// Debounced toggle for settings rows backed by [SettingRow].

///

/// Use inside [SettingRow.trailing] when the row already supplies icon, title,

/// and subtitle. Wraps [NightshadeSwitch] with a 300 ms debounce so rapid

/// toggles coalesce to the final value before persisting.

///

/// For a self-contained label + switch row (no icon column), use

/// [NightshadeSwitchRow] instead. For a bare toggle with no label (toolbar,

/// table cell), use [NightshadeSwitch] directly.
