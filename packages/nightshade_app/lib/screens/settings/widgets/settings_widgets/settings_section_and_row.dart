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
        Text(
          title,
          style:
              (isMobile ? NightshadeTypography.label : NightshadeTypography.h5)
                  .copyWith(color: colors.textPrimary),
        ),
        SizedBox(
            height:
                isMobile ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(
                isMobile ? 10 : NightshadeTokens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: children,
          ),
        ),
        SizedBox(height: isMobile ? NightshadeTokens.spaceXl : 28),
      ],
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

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: verticalPadding),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
              ),
      ),
      child: shouldStack
          ? _buildStackedLayout(context, colors, iconSize, iconInnerSize)
          : _buildRowLayout(context, colors, iconSize, iconInnerSize),
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
                    fontSize: isMobile ? NightshadeTypography.fontSize10 : NightshadeTypography.fontSize11,
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
        Flexible(child: trailing),
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
                      style: NightshadeTypography.captionSm
                          .copyWith(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
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
