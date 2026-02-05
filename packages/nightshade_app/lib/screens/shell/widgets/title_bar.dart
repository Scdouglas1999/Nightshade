import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/transient_alert_badge.dart';

// Conditional import for window_manager (desktop only)
import 'title_bar_stub.dart'
    if (dart.library.io) 'title_bar_desktop.dart' as window_impl;

class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return GestureDetector(
      onPanStart: window_impl.onTitleBarPanStart,
      onDoubleTap: window_impl.onTitleBarDoubleTap,
      child: Container(
        height: 40,
        color: colors.surface,
        child: Row(
          children: [
            const SizedBox(width: 16),

            // Logo and app name
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors.primary, colors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'NIGHTSHADE',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Transient Alert Badge - shows count of new alerts
            Builder(
              builder: (context) => TransientAlertBadge(
                showDropdown: true,
                onTap: () {
                  try {
                    context.go('/transients');
                  } catch (e) {
                    debugPrint('[TitleBar] Could not navigate to transients: $e');
                  }
                },
              ),
            ),

            const SizedBox(width: 8),

            // Profile button - navigates to Settings > Equipment Profiles
            Builder(
              builder: (context) => _TitleBarButton(
                icon: LucideIcons.user,
                tooltip: 'Equipment Profiles',
                onPressed: () {
                  try {
                    // Equipment Profiles is in Settings (category index 4)
                    context.go('/settings');
                  } catch (e) {
                    // Fallback for when router is not available
                    debugPrint('[TitleBar] Could not navigate to settings: $e');
                  }
                },
              ),
            ),

            // Settings button
            Builder(
              builder: (context) => _TitleBarButton(
                icon: LucideIcons.settings,
                tooltip: 'Settings',
                onPressed: () {
                  try {
                    context.go('/settings');
                  } catch (e) {
                    // Router might not be available yet
                  }
                },
              ),
            ),

            const SizedBox(width: 8),

            // Window controls (desktop only)
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
              _WindowControls(colors: colors),
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
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 16,
          color: colors.textSecondary,
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

class _WindowControls extends StatelessWidget {
  final NightshadeColors colors;

  const _WindowControls({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: LucideIcons.minus,
          onPressed: window_impl.minimizeWindow,
          hoverColor: colors.surfaceHover,
        ),
        _WindowButton(
          icon: LucideIcons.square,
          onPressed: window_impl.toggleMaximizeWindow,
          hoverColor: colors.surfaceHover,
        ),
        const _WindowButton(
          icon: LucideIcons.x,
          onPressed: window_impl.closeWindow,
          hoverColor: Colors.red,
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final bool isClose;

  const _WindowButton({
    required this.icon,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 14,
            color: _isHovered && widget.isClose
                ? Colors.white
                : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}



