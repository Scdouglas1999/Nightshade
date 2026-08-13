import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../../../widgets/remote_connection_indicator.dart';
import '../../../widgets/transient_alert_badge.dart';
import '../../../widgets/tutorial_overlay.dart' show TutorialKeys;
import '../shell_chrome.dart';

// Conditional import for window_manager (desktop only)
import 'title_bar_stub.dart' if (dart.library.io) 'title_bar_desktop.dart'
    as window_impl;

/// Makes [child] behave as window chrome: drag to move the frameless window,
/// double-tap to toggle maximize.
///
/// Public because the shell renders a second, compact bar below the
/// side-nav breakpoint (`_MobileSettingsBar`). That bar is still the desktop
/// window's only title bar — `TitleBarStyle.hidden` means the OS draws no
/// decorations at any width — so it needs the same move/maximize affordances.
/// No-ops on mobile via the conditional `title_bar_stub` import.
class WindowDragArea extends StatelessWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: window_impl.onTitleBarPanStart,
      onDoubleTap: window_impl.onTitleBarDoubleTap,
      child: child,
    );
  }
}

class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return WindowDragArea(
      child: Container(
        height: ShellChromeMetrics.titleBarHeight,
        color: colors.surface,
        child: Row(
          children: [
            const SizedBox(width: NightshadeTokens.spaceLg),

            // Logo and app name
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    NightshadeIcons.sparkle,
                    size: 14,
                    color: onPrimary,
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceSm + 2),
                Text(
                  'NIGHTSHADE',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Persistent remote connection indicator.
            // Tap opens the details sheet with the "Reconnect now" button
            // so the operator can force an immediate retry without
            // waiting for the exponential-backoff timer.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: RemoteConnectionIndicator(compact: true),
            ),

            // Transient Alert Badge - shows count of new alerts
            Builder(
              builder: (context) => TransientAlertBadge(
                showDropdown: true,
                onTap: () {
                  try {
                    context.go('/transients');
                  } catch (e) {
                    developer.log(
                        '[TitleBar] Could not navigate to transients: $e',
                        name: 'TitleBar',
                        level: 900,
                        error: e);
                  }
                },
              ),
            ),

            const SizedBox(width: NightshadeTokens.spaceSm),

            // Profile button - navigates to Settings > Equipment Profiles
            Builder(
              builder: (context) => _TitleBarButton(
                icon: NightshadeIcons.user,
                tooltip: context.l10n.text('settingsEquipmentProfiles'),
                onPressed: () {
                  try {
                    // Deep-link to the Equipment Profiles section so this
                    // shortcut opens where it says, not the generic root.
                    context.go('/settings?section=equipment-profiles');
                  } catch (e) {
                    // Fallback for when router is not available
                    developer.log(
                        '[TitleBar] Could not navigate to settings: $e',
                        name: 'TitleBar',
                        level: 900,
                        error: e);
                  }
                },
              ),
            ),

            // Settings button — keyed for the onboarding overlay so the
            // first-launch tour can spotlight where Plate Solving lives.
            Builder(
              builder: (context) => _TitleBarButton(
                key: TutorialKeys.navSettings,
                icon: NightshadeIcons.settings,
                tooltip: context.l10n.text('settingsTitle'),
                onPressed: () {
                  try {
                    context.go('/settings');
                  } catch (e) {
                    // Router might not be available yet
                  }
                },
              ),
            ),

            const SizedBox(width: NightshadeTokens.spaceSm),

            // Window controls (desktop only)
            if (ShellChrome.isDesktopWindow) WindowControls(colors: colors),
          ],
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TitleBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Named and typed for assistive tech. An InkWell contributes a tap ACTION
    // but no role and no name, and a Tooltip contributes a tooltip rather than
    // a label — so the whole icon group, the Settings gear included, was absent
    // from the accessibility tree, which made Settings unreachable without
    // sight of the four unlabelled glyphs.
    final button = Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: NightshadeTokens.borderRadiusInline4,
        child: Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
          child: Icon(
            icon,
            size: NightshadeTokens.iconSm,
            color: colors.textSecondary,
          ),
        ),
      ),
    );

    // Only show tooltip if Overlay is available
    if (Overlay.maybeOf(context) != null) {
      return Tooltip(
        message: tooltip,
        child: button,
      );
    }
    return button;
  }
}

/// Minimize / maximize / close caption buttons for the frameless desktop
/// window. Public so every desktop shell layout can render them — see
/// [WindowDragArea].
class WindowControls extends StatelessWidget {
  final NightshadeColors colors;

  const WindowControls({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: NightshadeIcons.remove,
          label: 'Minimize',
          onPressed: window_impl.minimizeWindow,
          hoverColor: colors.surfaceHover,
        ),
        _WindowButton(
          icon: NightshadeIcons.stop,
          label: 'Maximize',
          onPressed: window_impl.toggleMaximizeWindow,
          hoverColor: colors.surfaceHover,
        ),
        _WindowButton(
          icon: NightshadeIcons.close,
          label: 'Close window',
          onPressed: window_impl.closeWindow,
          hoverColor: colors.error,
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color hoverColor;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.hoverColor,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final onError = Theme.of(context).colorScheme.onError;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: ShellChromeMetrics.windowControlWidth,
            height: ShellChromeMetrics.windowControlHeight,
            color: _isHovered ? widget.hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color:
                  _isHovered && widget.isClose ? onError : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
