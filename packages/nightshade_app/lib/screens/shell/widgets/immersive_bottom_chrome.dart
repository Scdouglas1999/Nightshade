import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Wraps the phone shell's bottom chrome (status bar + bottom navigation) and
/// collapses it to a slim reveal grabber when [visible] is false, animating the
/// height so the content above reclaims the space.
///
/// When collapsed, a small centered handle hints that chrome is hidden; tapping
/// it or swiping up brings the chrome back ([onReveal]). (The shell also reveals
/// on any interaction via a pointer listener, so this is a discoverability aid
/// as much as a control.)
class ImmersiveBottomChrome extends StatelessWidget {
  final bool visible;
  final Widget child;
  final VoidCallback onReveal;

  const ImmersiveBottomChrome({
    super.key,
    required this.visible,
    required this.child,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: visible
          ? child
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReveal,
              onVerticalDragUpdate: (details) {
                if ((details.primaryDelta ?? 0) < -1.5) onReveal();
              },
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 16,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textMuted.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
