import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../widgets/tutorial_keys/planetarium_keys.dart';

/// Slew control buttons
class SlewControls extends ConsumerWidget {
  final NightshadeColors colors;
  final bool slewMode;
  final VoidCallback onToggleSlewMode;
  final VoidCallback onStopSlew;

  const SlewControls({
    super.key,
    required this.colors,
    required this.slewMode,
    required this.onToggleSlewMode,
    required this.onStopSlew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mountState = ref.watch(mountStateProvider);
    final isConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final isSlewing = mountState.isSlewing;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: slewMode
            ? Border.all(color: const Color(0xFFFF9800), width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slew mode toggle
          Tooltip(
            message: slewMode ? 'Disable slew mode' : 'Enable slew mode',
            child: SlewControlButton(
              key: PlanetariumTutorialKeys.slewBtn,
              icon: LucideIcons.move,
              isActive: slewMode,
              isEnabled: isConnected,
              onTap: isConnected ? onToggleSlewMode : null,
            ),
          ),
          const SizedBox(height: 8),
          // Stop slew button
          Tooltip(
            message: 'Stop slew',
            child: SlewControlButton(
              icon: LucideIcons.octagon,
              isActive: false,
              isEnabled: isConnected && isSlewing,
              isDestructive: true,
              onTap: isConnected && isSlewing ? onStopSlew : null,
            ),
          ),
          if (slewMode) ...[
            const SizedBox(height: 8),
            const Text(
              'SLEW',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF9800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SlewControlButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final bool isEnabled;
  final bool isDestructive;
  final VoidCallback? onTap;

  const SlewControlButton({
    super.key,
    required this.icon,
    required this.isActive,
    required this.isEnabled,
    this.isDestructive = false,
    this.onTap,
  });

  @override
  State<SlewControlButton> createState() => _SlewControlButtonState();
}

class _SlewControlButtonState extends State<SlewControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive
        ? const Color(0xFFE53935)
        : widget.isActive
            ? const Color(0xFFFF9800)
            : Colors.white70;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFFFF9800).withValues(alpha: 0.2)
                : _isHovered && widget.isEnabled
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: widget.isEnabled ? color : Colors.white24,
          ),
        ),
      ),
    );
  }
}
