import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/screens/shell/shell_chrome.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'readiness_dashboard_card.dart';

/// Top-anchored floating placement for the [ReadinessDashboardCard] on the
/// dashboard.
///
/// C14 calls for surfacing the "ready to image" report on the dashboard. The
/// card itself owns all of its content and collapses to nothing when the rig
/// is fully ready ([ReadinessLevel.ready]); this wrapper only owns *placement*,
/// keeping layout concerns out of the card so it can be reused unmodified in
/// other surfaces (e.g. the equipment screen uses the underlying panel).
///
/// It sits in the dashboard [Stack] alongside `SmartNightPromptCard`. The
/// smart-night card floats bottom-centre, so this readiness overlay is anchored
/// top-centre to avoid colliding with it, with a bounded width so it reads as a
/// status card rather than stretching across an ultrawide layout. When there is
/// nothing outstanding the card returns `SizedBox.shrink`, so this overlay adds
/// no visual weight to a fully-configured dashboard.
class ReadinessDashboardOverlay extends ConsumerWidget {
  const ReadinessDashboardOverlay({super.key});

  /// Matches the smart-night prompt's desktop width so the two floating cards
  /// share a consistent footprint.
  static const double _desktopWidth = 480.0;
  static const double _horizontalMargin = NightshadeTokens.spaceLg;
  static const double _topMargin = NightshadeTokens.spaceMd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cheap top-line read: only rebuild placement when the overall level
    // changes. When ready, the card collapses, so we skip mounting it at all to
    // avoid an empty Align consuming a hit-test region over the command bar.
    final overall = ref.watch(readinessOverallProvider);
    if (overall == ReadinessLevel.ready) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        final cardWidth = isMobile
            ? constraints.maxWidth - (_horizontalMargin * 2)
            : _desktopWidth;

        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(
                top: ShellChrome.useBottomNavigation(constraints.maxWidth)
                    ? _topMargin
                    : ShellChromeMetrics.titleBarHeight + _topMargin,
                left: _horizontalMargin,
                right: _horizontalMargin,
              ),
              child: SizedBox(
                width: cardWidth,
                child: const ReadinessDashboardCard(),
              ),
            ),
          ),
        );
      },
    );
  }
}
