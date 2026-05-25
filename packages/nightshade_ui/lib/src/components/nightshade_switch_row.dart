import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import 'nightshade_switch.dart';
import 'nightshade_tooltip.dart';

/// Label + [NightshadeSwitch] row for settings and imaging panels.
///
/// Use [expanded: true] (default) for full-width rows: label left, switch right.
/// Use [expanded: false] for compact inline toolbars.
///
/// Does not include a leading icon — for icon + title + subtitle rows in the
/// settings app, compose [SettingRow] with [SettingsSwitch] as the trailing
/// widget instead.
class NightshadeSwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool compact;
  final bool expanded;
  final TextStyle? labelStyle;
  final TextStyle? subtitleStyle;

  const NightshadeSwitchRow({
    super.key,
    required this.label,
    this.subtitle,
    this.tooltip,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.compact = false,
    this.expanded = true,
    this.labelStyle,
    this.subtitleStyle,
  });

  bool get _switchEnabled => enabled && onChanged != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final labelWidget = _buildLabel(colors);

    final switchWidget = NightshadeSwitch(
      value: value,
      onChanged: onChanged,
      enabled: _switchEnabled,
      compact: compact,
    );

    if (!expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          labelWidget,
          SizedBox(width: compact ? NightshadeTokens.spaceXs : NightshadeTokens.spaceSm),
          switchWidget,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: labelWidget),
        const SizedBox(width: NightshadeTokens.spaceMd),
        switchWidget,
      ],
    );
  }

  Widget _buildLabel(NightshadeColors colors) {
    final effectiveLabelStyle = labelStyle ??
        NightshadeTypography.bodySm.copyWith(
          color: colors.textSecondary,
          fontSize: compact ? 12 : null,
        );
    final effectiveSubtitleStyle = subtitleStyle ??
        NightshadeTypography.caption.copyWith(color: colors.textMuted);

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, style: effectiveLabelStyle),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: NightshadeTokens.spaceXs),
          NightshadeTooltip(
            message: tooltip!,
            position: NightshadeTooltipPosition.top,
            child: Icon(
              LucideIcons.helpCircle,
              size: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );

    if (subtitle == null) {
      return titleRow;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleRow,
        const SizedBox(height: 2),
        Text(subtitle!, style: effectiveSubtitleStyle),
      ],
    );
  }
}
