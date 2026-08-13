import 'package:flutter/material.dart';

import '_design_showcase_primitives.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show ObjectType, DriverType;

import '../components/nightshade_alert.dart';
import '../components/nightshade_button.dart';
import '../components/nightshade_card.dart';
import '../components/nightshade_checkbox.dart';
import '../components/nightshade_progress_bar.dart';
import '../components/nightshade_switch.dart';
import '../components/nightshade_text_field.dart';
import '../components/screen_header.dart';
import '../components/status_dot.dart';
import '../components/status_pill.dart';
import '../components/sub_tab_button.dart';
import '../theme/annotation_type_colors.dart';
import '../theme/backend_protocol_colors.dart';
import '../theme/nightshade_chart_colors.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

part 'design_reference_board/palette_sections.dart';
part 'design_reference_board/typography_section.dart';
part 'design_reference_board/component_sections.dart';
part 'design_reference_board/board_primitives.dart';

/// A single, fully-static reference board that renders the entire Nightshade
/// design language on one canvas: the semantic palette, the chart / annotation /
/// backend domain palettes, the complete named typography scale (every style
/// labelled with its name + spec), and a representative pass over the component
/// library (cards, buttons, inputs, pills, dots, progress, alerts, headers).
///
/// Unlike [NightshadeDesignSystemGallery] this board is intentionally
/// stateless and interaction-free so it produces a deterministic frame — it is
/// the source widget for the committed golden-screenshot reference images under
/// `docs/design/goldens/`. Render it inside a themed [MaterialApp] and the whole
/// board re-skins from the active [NightshadeColors] extension, so the same
/// widget yields the light/dark board and the red-night board.
class NightshadeDesignReferenceBoard extends StatelessWidget {
  const NightshadeDesignReferenceBoard({super.key, this.themeLabel});

  /// Human label for the theme this board is rendered under (e.g. "Dark",
  /// "Red Night"). Shown in the board header so a captured PNG is
  /// self-identifying.
  final String? themeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Material(
      color: colors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boardHeader(colors),
                const SizedBox(height: NightshadeTokens.space2xl),
                _twoColumn(
                  left: _SemanticPaletteSection(colors: colors),
                  right: _DomainPaletteSection(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                ShowcaseSection.boxed(
                  title: 'Typography scale',
                  child: _TypographyScale(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                _twoColumn(
                  left: _ComponentsSection(colors: colors),
                  right: _StatusAndFeedbackSection(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                ShowcaseSection.boxed(
                  title: 'Layout primitives',
                  child: _LayoutPrimitivesSection(colors: colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardHeader(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Nightshade Design Language',
              style: NightshadeTypography.h1.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            if (themeLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NightshadeTokens.spaceMd,
                    vertical: NightshadeTokens.spaceXs,
                  ),
                  decoration: NightshadeDecorations.emphasisSurface(
                    colors.primary,
                    borderRadius: NightshadeTokens.borderRadiusSm,
                  ),
                  child: Text(
                    themeLabel!.toUpperCase(),
                    style: NightshadeTypography.overline.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Precision-instrument visual baseline — semantic palette, domain '
          'colors, full type scale, and the component library on one canvas.',
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _twoColumn({required Widget left, required Widget right}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: NightshadeTokens.space2xl),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: NightshadeTokens.space2xl),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
