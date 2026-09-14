import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shell_navigation.dart';
import 'title_bar.dart' show commandPaletteShortcutLabel;

/// Where "Open the manual" goes.
///
/// There is no per-screen manual in this project — the documentation is the
/// repository — so the item is named for what it actually opens rather than
/// promising a page per screen. 05 §11 asks for "Open the manual for
/// <screen>"; the honest version is recorded in reports/observatory/w1.
const String kManualUrl = 'https://github.com/Scdouglas1999/Nightshade';

/// The top bar's help button (05 §11).
///
/// This is what replaced ten per-screen tour nudges. The tours themselves are
/// unchanged and still run through `TutorialOverlay`; what changed is that the
/// operator asks for one instead of being interrupted by an offer of one.
class ShellHelpButton extends ConsumerWidget {
  const ShellHelpButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (buttonContext) => NightshadeIconButton(
        icon: LucideIcons.helpCircle,
        tooltip: 'Help for this screen',
        tooltipPosition: NightshadeTooltipPosition.bottom,
        onPressed: () => _open(buttonContext, ref),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final box = context.findRenderObject()! as RenderBox;

    // Anchored under the button's trailing edge, which is where a popover
    // belongs relative to the control that opened it. The anchor is a
    // menu-wide box ending at that edge, so the popover's right side lines up
    // with the button's right side instead of hanging off it.
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final position = menuPositionFromRect(
      context,
      Rect.fromLTWH(
        bottomRight.dx - _menuWidth,
        bottomRight.dy + NightshadeTokens.spaceXs,
        _menuWidth,
        0,
      ),
    );

    final screen = _currentScreen(context);
    showMenu<_HelpAction>(
      context: context,
      position: position,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        side: BorderSide(color: colors.border),
      ),
      constraints: const BoxConstraints(minWidth: _menuWidth),
      items: [
        _item(
          colors,
          value: _HelpAction.tour,
          icon: LucideIcons.compass,
          label: 'Tour this screen',
          enabled: screen.tour != null,
        ),
        _item(
          colors,
          value: _HelpAction.shortcuts,
          icon: LucideIcons.keyboard,
          label: 'Keyboard shortcuts',
        ),
        _item(
          colors,
          value: _HelpAction.manual,
          icon: LucideIcons.bookOpen,
          label: 'Open the manual',
        ),
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      switch (action) {
        case _HelpAction.tour:
          final tour = screen.tour;
          if (tour == null) return;
          ref.read(tutorialProvider.notifier).startTutorial(tour);
        case _HelpAction.shortcuts:
          showShellShortcuts(context);
        case _HelpAction.manual:
          launchUrl(
            Uri.parse(kManualUrl),
            mode: LaunchMode.externalApplication,
          ).catchError((Object e) {
            developer.log(
              '[ShellHelp] Could not open the manual: $e',
              name: 'ShellHelp',
              level: 900,
              error: e,
            );
            return false;
          });
      }
    });
  }

  static const double _menuWidth = 220.0;

  PopupMenuItem<_HelpAction> _item(
    NightshadeColors colors, {
    required _HelpAction value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<_HelpAction>(
      value: value,
      enabled: enabled,
      height: NightshadeTokens.buttonHeight,
      child: Row(
        children: [
          Icon(
            icon,
            size: NightshadeTokens.iconSm,
            color: enabled
                ? colors.textMuted
                : colors.textMuted.withValues(
                    alpha: NightshadeTokens.opacityDisabled,
                  ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Text(
            label,
            style: NightshadeTypography.bodySm.copyWith(
              color: enabled
                  ? colors.textPrimary
                  : colors.textMuted.withValues(
                      alpha: NightshadeTokens.opacityDisabled,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The screen the operator is looking at, and the tour that covers it.
  _HelpScreen _currentScreen(BuildContext context) {
    final location = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .lastOrNull
        ?.matchedLocation;
    final path = (location ?? '/dashboard').split('?').first;
    for (final entry in _tours.entries) {
      if (ShellNavigation.locationIsUnder(path, entry.key)) {
        return _HelpScreen(path, entry.value);
      }
    }
    return _HelpScreen(path, null);
  }
}

/// Which deep tour covers which route.
///
/// Only the routes that HAVE a tour appear; the rest get a disabled "Tour this
/// screen", because a menu item that silently does nothing is worse than one
/// that says it has nothing to offer.
const Map<String, TutorialCategory> _tours = {
  '/dashboard': TutorialCategory.dashboardTour,
  '/equipment': TutorialCategory.equipmentTour,
  '/imaging': TutorialCategory.imagingTour,
  '/guiding': TutorialCategory.guidingTour,
  '/sequencer': TutorialCategory.sequencerTour,
  '/planetarium': TutorialCategory.planetariumTour,
  '/framing': TutorialCategory.framingTour,
  '/analytics': TutorialCategory.analyticsTour,
  '/flat-wizard': TutorialCategory.flatWizardTour,
  '/weather': TutorialCategory.weatherTour,
  '/settings': TutorialCategory.settingsTour,
  '/polar-alignment': TutorialCategory.polarAlignmentTour,
};

class _HelpScreen {
  final String route;
  final TutorialCategory? tour;
  const _HelpScreen(this.route, this.tour);
}

enum _HelpAction { tour, shortcuts, manual }

/// The app-wide keyboard shortcuts.
///
/// Only the bindings the SHELL owns are listed. Screens that carry their own
/// (the Sequencer's editing keys) keep their own cheat sheet on the screen
/// that honours them, because a global list of keys that only work somewhere
/// else is a list of things that do not work.
void showShellShortcuts(BuildContext context) {
  final colors = NightshadeColors.of(context);
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        decoration: NightshadeDecorations.dialog(colors),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keyboard shortcuts',
              style: NightshadeTypography.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            _ShortcutRow(
              keys: commandPaletteShortcutLabel,
              description: 'Open the command palette',
              colors: colors,
            ),
            _ShortcutRow(
              keys: 'Esc',
              description: 'Close the palette, a dialog or a full-screen view',
              colors: colors,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              'Screens with their own shortcuts list them where they work — '
              'the Sequencer keeps its editing keys behind the keyboard icon '
              'in its tab strip.',
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Align(
              alignment: Alignment.centerRight,
              child: NightshadeButton(
                onPressed: () => Navigator.of(context).pop(),
                label: 'Close',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String description;
  final NightshadeColors colors;

  const _ShortcutRow({
    required this.keys,
    required this.description,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: NightshadeTokens.borderRadiusXs,
              border: Border.all(color: colors.border),
            ),
            child: Text(
              keys,
              style: NightshadeTypography.monoCaption.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              description,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
