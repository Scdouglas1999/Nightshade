// Component C8 (attribution half) — the HiPS survey attribution badge.
//
// CDS and the survey publishers ask HiPS clients to display the survey's
// `obs_copyright` credit whenever its imagery is shown (it is part of the data
// licence, e.g. the STScI Digitized Sky Survey acknowledgement that must
// accompany any DSS-derived image). This badge renders that credit, parsed from
// the survey `properties` document into [HipsProperties.obsCopyright] /
// [HipsProperties.creator], in the design system's quiet on-canvas chrome style
// — and only while HiPS imagery is actually visible.
//
// It is a small, pure presentation widget: it takes the resolved
// [HipsProperties] (or `null` when none is resolved) and whether the layer is
// currently showing imagery, and renders the credit pill or nothing. It owns no
// fetch logic and no provider reads, so it composes cleanly into the framing
// `Stack` next to the tile layer and is trivially testable.
//
// When the survey publishes an [HipsProperties.obsCopyrightUrl] the badge is
// tappable and opens it in the external browser (the canonical
// attribution-page link), matching how the settings screens launch external
// URLs. When no URL is published the badge is non-interactive text.

import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
// HipsProperties is the parsed survey metadata carrying the attribution fields.
// It is exported from nightshade_core's public barrel, but the framing widgets
// import the core src models directly (matching the painters' convention), so
// it is imported via the barrel here where it is public.
import 'package:nightshade_core/nightshade_core.dart' show HipsProperties;
import 'package:url_launcher/url_launcher.dart';

/// A quiet on-canvas pill crediting the HiPS survey whose imagery is currently
/// displayed, shown only while [visible] is true and [properties] carries an
/// attribution.
///
/// Renders [HipsProperties.obsCopyright] when present, else falls back to the
/// publisher [HipsProperties.creator]; if neither is published the badge renders
/// nothing (an empty [SizedBox]) rather than inventing a credit. When
/// [HipsProperties.obsCopyrightUrl] is present the pill is tappable and opens it
/// externally.
class HipsAttributionBadge extends StatelessWidget {
  /// The resolved survey metadata, or `null` when no HiPS survey is resolved.
  final HipsProperties? properties;

  /// Whether HiPS imagery is currently visible. The credit is only shown while
  /// the imagery it credits is on screen (the licence requirement), so the
  /// screen passes its "layer active and has imagery" condition here.
  final bool visible;

  const HipsAttributionBadge({
    super.key,
    required this.properties,
    required this.visible,
  });

  /// The credit text to display: the survey copyright, else the creator, else
  /// `null` when nothing is published.
  String? get _creditText {
    final props = properties;
    if (props == null) return null;
    final copyright = props.obsCopyright;
    if (copyright != null && copyright.isNotEmpty) return copyright;
    final creator = props.creator;
    if (creator != null && creator.isNotEmpty) return creator;
    return null;
  }

  Future<void> _openAttributionUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // External browser, matching the about/settings screens' link handling.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final credit = _creditText;
    if (!visible || credit == null) {
      return const SizedBox.shrink();
    }

    final colors = context.nightshadeColors;
    final url = properties?.obsCopyrightUrl;
    final hasUrl = url != null && url.isNotEmpty;

    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHoverBorder),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(
          color:
              colors.border.withValues(alpha: NightshadeTokens.opacitySubtle),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            NightshadeIcons.info,
            size: NightshadeTokens.iconXs,
            color: colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          // Constrain the credit so a long copyright string wraps/ellipsizes
          // rather than overflowing the canvas chrome.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              credit,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NightshadeTypography.overline.copyWith(
                color: hasUrl ? colors.textSecondary : colors.textMuted,
                decoration: hasUrl ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );

    if (!hasUrl) return pill;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openAttributionUrl(url),
        child: Tooltip(
          message: url,
          child: pill,
        ),
      ),
    );
  }
}
