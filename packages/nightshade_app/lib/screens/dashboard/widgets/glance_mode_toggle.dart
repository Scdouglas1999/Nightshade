import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../widgets/touch_target_floor.dart';

/// Command-bar toggle for glance mode — bumps the dashboard's secondary-status
/// type up so the run can be read from across the room.
///
/// Drives [glanceModeProvider]; surfaces that have opted in (via
/// [NightshadeTypography.glanceStyle]) respond immediately and the choice
/// persists across restarts. Renders an icon-only button that fills/tints when
/// active so its on/off state is obvious at a glance (fittingly).
class GlanceModeToggle extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  /// Smaller hit target / icon for the compact (mobile) command bar.
  final bool compact;

  const GlanceModeToggle({
    super.key,
    required this.colors,
    this.compact = false,
  });

  @override
  ConsumerState<GlanceModeToggle> createState() => _GlanceModeToggleState();
}

class _GlanceModeToggleState extends ConsumerState<GlanceModeToggle> {
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(glanceModeProvider.notifier).toggle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the Glance mode setting.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(glanceModeProvider);
    final size = widget.compact ? 36.0 : 40.0;
    final color = enabled ? widget.colors.primary : widget.colors.textSecondary;

    return Tooltip(
      message: enabled ? 'Glance mode: on' : 'Glance mode: off',
      child: Semantics(
        button: true,
        // `toggled` alone publishes CHECKABLE but never ENABLED, so the working
        // toggle advertised itself as permanently dimmed ("Glance mode
        // [off,DISABLED]") and a screen reader would skip it. The enabled state
        // is the real one: only the in-flight save disables the tap.
        enabled: !_saving,
        toggled: enabled,
        label: 'Glance mode',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _toggle,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            // The PAINTED chip stays 36/40dp, but the tappable box is floored at
            // the Android 48dp minimum. Measured at 36.0x36.0 on every phone
            // width before this — the same visual-size-is-the-hit-size mistake
            // Material's own IconButton avoids by padding a 24dp icon out to 48.
            child: TouchTargetFloor(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: enabled
                      ? widget.colors.primary.withValues(alpha: 0.12)
                      : null,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  border: Border.all(
                    color:
                        enabled ? widget.colors.primary : widget.colors.border,
                  ),
                ),
                child: _saving
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.colors.primary,
                        ),
                      )
                    : Icon(
                        enabled ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: widget.compact ? 16 : 18,
                        color: color,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
