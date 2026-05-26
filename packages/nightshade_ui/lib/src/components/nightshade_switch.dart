import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import 'nightshade_switch_style.dart';

/// Canonical Nightshade toggle control — the visual switch only.
///
/// Use when you need a bare toggle with no label (e.g. table cell, toolbar).
/// For a label + switch row, prefer [NightshadeSwitchRow].
/// For settings rows with icon + debounced persistence, use app-layer
/// [SettingsSwitch] inside [SettingRow].
///
/// Prefer this over Material [Switch]. Theme [SwitchThemeData] is defined only
/// in [NightshadeSwitchStyle.switchThemeData] as a fallback for legacy Material
/// widgets.
class NightshadeSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool compact;

  const NightshadeSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  @override
  State<NightshadeSwitch> createState() => _NightshadeSwitchState();
}

class _NightshadeSwitchState extends State<NightshadeSwitch> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nightshadeColors;
    final isEnabled = widget.enabled && widget.onChanged != null;

    final trackWidth = widget.compact
        ? NightshadeSwitchStyle.compactTrackWidth
        : NightshadeSwitchStyle.trackWidth;
    final trackHeight = widget.compact
        ? NightshadeSwitchStyle.compactTrackHeight
        : NightshadeSwitchStyle.trackHeight;
    final thumbSize = widget.compact
        ? NightshadeSwitchStyle.compactThumbSize
        : NightshadeSwitchStyle.thumbSize;

    final trackColor = NightshadeSwitchStyle.trackColor(
      colors,
      selected: widget.value,
      hovered: _isHovered && isEnabled,
    );
    final trackBorder = NightshadeSwitchStyle.trackBorderColor(
      colors,
      selected: widget.value,
    );
    final thumbColor = NightshadeSwitchStyle.thumbColor(
      theme,
      colors,
      selected: widget.value,
      enabled: isEnabled,
    );

    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isEnabled ? () => widget.onChanged!(!widget.value) : null,
        child: Opacity(
          opacity: isEnabled ? 1.0 : NightshadeTokens.opacityDisabled,
          child: AnimatedContainer(
            duration: NightshadeTokens.durationNormal,
            curve: NightshadeTokens.curvePrecise,
            width: trackWidth,
            height: trackHeight,
            padding: const EdgeInsets.all(NightshadeSwitchStyle.trackPadding),
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: trackBorder),
            ),
            child: AnimatedAlign(
              duration: NightshadeTokens.durationNormal,
              curve: NightshadeTokens.curvePrecise,
              alignment:
                  widget.value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  color: thumbColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
