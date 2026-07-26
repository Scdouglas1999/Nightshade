import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Wraps the phone shell's bottom chrome (status bar + bottom navigation) with
/// an **always-visible grabber handle** so the operator can hide or reveal it
/// at any time — tap the handle, or swipe it up/down. When hidden the content
/// above reclaims the full height; only the slim handle remains.
class ImmersiveBottomChrome extends StatelessWidget {
  final bool visible;
  final Widget child;

  /// Toggle hide/show (sticky — see ImmersiveChromeController).
  final VoidCallback onToggle;

  const ImmersiveBottomChrome({
    super.key,
    required this.visible,
    required this.child,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Always-on handle: tap to toggle, or swipe up/down. The chevron points
        // the way it will move (down = will hide, up = will reveal).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          onVerticalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -80 && !visible) {
              onToggle(); // swipe up reveals
            } else if (v > 80 && visible) {
              onToggle(); // swipe down hides
            }
          },
          // Hidden state gets a taller, clearly-labelled handle: with the
          // whole nav bar gone this IS the navigation affordance, and the
          // original 18px muted line + 13px chevron read as screen debris —
          // live-device testing showed operators simply got stranded.
          // Visible state keeps the original slim, subtle grabber.
          child: visible
              ? Container(
                  width: double.infinity,
                  height: 18,
                  color: colors.surface,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                          color: colors.textMuted.withValues(alpha: 0.5),
                          borderRadius: NightshadeTokens.borderRadiusInline2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        NightshadeIcons.chevronDown,
                        size: 13,
                        color: colors.textMuted.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                )
              // The bottom system inset (gesture home indicator / nav bar) is
              // normally supplied by NightshadeBottomNavigation's own SafeArea.
              // Hiding the chrome removes that widget, so the reveal handle must
              // carry the inset itself — otherwise it renders *underneath* the
              // gesture bar, which strikes through the 'Menu' label and hands the
              // operator's swipe to the system instead of the app.
              : Container(
                  width: double.infinity,
                  color: colors.surface,
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            NightshadeIcons.chevronUp,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Menu',
                            style: NightshadeTypography.captionSm.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        // Collapsible chrome.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: visible
              ? child
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}
