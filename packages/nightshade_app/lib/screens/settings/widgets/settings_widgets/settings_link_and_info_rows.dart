part of '../settings_widgets.dart';

class SettingsLinkButton extends StatefulWidget {
  final IconData icon;

  final String label;

  final VoidCallback onTap;

  final bool compact;

  const SettingsLinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<SettingsLinkButton> createState() => _SettingsLinkButtonState();
}

class _SettingsLinkButtonState extends State<SettingsLinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final horizontalPad =
        widget.compact ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg;

    final verticalPad = widget.compact ? NightshadeTokens.spaceSm : 10.0;

    final iconSize =
        widget.compact ? NightshadeTokens.iconXs : NightshadeTokens.iconSm;

    final labelStyle = widget.compact
        ? NightshadeTypography.captionSm
        : NightshadeTypography.caption;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPad, vertical: verticalPad),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceAlt : colors.background,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: iconSize,
                color: colors.textSecondary,
              ),
              SizedBox(
                  width: widget.compact
                      ? NightshadeTokens.radiusSm
                      : NightshadeTokens.spaceSm),
              Text(
                widget.label,
                style: labelStyle.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label-value pair row for the About screen.

class SettingsInfoRow extends StatelessWidget {
  final String label;

  final String value;

  const SettingsInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: NightshadeTypography.monoSm
                  .copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact slider widget for settings.

///

/// Relies on theme [SliderThemeData] from [NightshadeTheme] for track/thumb

/// styling; only adds fixed width and value label for [SettingRow] layout.
