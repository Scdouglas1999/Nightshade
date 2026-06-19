import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Command-bar toggle for glance mode — bumps the dashboard's secondary-status
/// type up so the run can be read from across the room.
///
/// Drives [glanceModeProvider]; surfaces that have opted in (via
/// [NightshadeTypography.glanceStyle]) respond immediately and the choice
/// persists across restarts. Renders an icon-only button that fills/tints when
/// active so its on/off state is obvious at a glance (fittingly).
class GlanceModeToggle extends ConsumerWidget {
  final NightshadeColors colors;

  /// Smaller hit target / icon for the compact (mobile) command bar.
  final bool compact;

  const GlanceModeToggle({
    super.key,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(glanceModeProvider);
    final size = compact ? 36.0 : 40.0;
    final color = enabled ? colors.primary : colors.textSecondary;

    return Tooltip(
      message: enabled ? 'Glance mode: on' : 'Glance mode: off',
      child: Semantics(
        button: true,
        toggled: enabled,
        label: 'Glance mode',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ref.read(glanceModeProvider.notifier).toggle(),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: enabled ? colors.primary.withValues(alpha: 0.12) : null,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(
                  color: enabled ? colors.primary : colors.border,
                ),
              ),
              child: Icon(
                enabled ? LucideIcons.eye : LucideIcons.eyeOff,
                size: compact ? 16 : 18,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
