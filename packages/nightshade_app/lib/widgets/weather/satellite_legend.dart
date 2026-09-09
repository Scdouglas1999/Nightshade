import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The infrared-satellite colour scale: white is a cold, high, thick cloud
/// top; grey is lower or thinner cloud; dark is clear sky over warm ground.
///
/// It carries no container of its own — the compact form rides inside the
/// radar control bar's glass, and the full form inside a panel — so the tone
/// ladder is the caller's to set.
class SatelliteLegend extends StatelessWidget {
  /// Whether to show in compact horizontal mode
  final bool compact;

  const SatelliteLegend({
    super.key,
    this.compact = false,
  });

  /// Width of the compact gradient bar.
  static const double _compactBarWidth = 92;

  /// Height of the compact gradient bar.
  static const double _compactBarHeight = 10;

  /// Height of the full gradient bar.
  static const double _fullBarHeight = 20;

  /// The infrared ramp. These are IMAGE-DATA colours — they describe the
  /// satellite's own greyscale, not app chrome — so they are literals by
  /// necessity and are exempt from the palette (03 §1, "chart / image-data
  /// colours").
  static const _compactRamp = LinearGradient(
    colors: [
      Color(0xFF0D0D18), // clear sky
      Color(0xFF1A1A2E),
      Color(0xFF3A3A50),
      Color(0xFF6A6A82),
      Color(0xFFA0A0B8),
      Color(0xFFD0D0E0),
      Color(0xFFFFFFFF), // thick, high cloud
    ],
    stops: [0.0, 0.1, 0.25, 0.45, 0.65, 0.85, 1.0],
  );

  static const _fullRamp = LinearGradient(
    colors: [
      Color(0xFF0D0D18),
      Color(0xFF1A1A2E),
      Color(0xFF3A3A50),
      Color(0xFF5A5A72),
      Color(0xFF7A7A92),
      Color(0xFF9A9AB2),
      Color(0xFFBABAD2),
      Color(0xFFDADAF0),
      Color(0xFFFFFFFF),
    ],
    stops: [0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return compact ? _compactLegend(colors) : _fullLegend(colors);
  }

  Widget _compactLegend(NightshadeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _compactBarWidth,
          height: _compactBarHeight,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusXs,
            gradient: _compactRamp,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'Clear',
          style: NightshadeTypography.monoCaption.copyWith(
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Icon(
          LucideIcons.arrowRight,
          size: NightshadeTokens.iconXs,
          color: colors.textMuted,
        ),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Text(
          'Cloudy',
          style: NightshadeTypography.monoCaption.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _fullLegend(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Infrared satellite',
          style: NightshadeTypography.sectionTitle.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Container(
          height: _fullBarHeight,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusXs,
            gradient: _fullRamp,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _LegendLabel(text: 'Clear', color: colors.textMuted),
            _LegendLabel(text: 'Thin cloud', color: colors.textMuted),
            _LegendLabel(text: 'Thick cloud', color: colors.textMuted),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Text(
          'Brighter is a colder cloud top, so a higher and thicker cloud. '
          'Use the contrast slider to bring it out.',
          style: NightshadeTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LegendLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _LegendLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: NightshadeTypography.monoCaption.copyWith(color: color),
    );
  }
}
