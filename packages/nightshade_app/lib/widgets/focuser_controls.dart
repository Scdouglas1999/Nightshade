import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../utils/snackbar_helper.dart';

/// Reusable widget for focuser movement controls and autofocus.
///
/// This eliminates duplicate focuser button implementations across screens.
/// Use this widget instead of implementing custom _FocusButton or _MoveButton classes.
class FocuserControls extends ConsumerStatefulWidget {
  /// Whether to use compact sizing for the controls.
  final bool compact;

  /// Whether to show the autofocus button.
  final bool showAutofocus;

  /// Callback invoked when autofocus completes successfully.
  final VoidCallback? onAutofocusComplete;

  const FocuserControls({
    super.key,
    this.compact = false,
    this.showAutofocus = true,
    this.onAutofocusComplete,
  });

  @override
  ConsumerState<FocuserControls> createState() => _FocuserControlsState();
}

class _FocuserControlsState extends ConsumerState<FocuserControls> {
  bool _isRunningAutofocus = false;

  FocuserState? get _focuserState => ref.watch(focuserStateProvider);
  bool get _isConnected => _focuserState?.connectionState == DeviceConnectionState.connected;

  Future<void> _moveRelative(int steps) async {
    try {
      await ref.read(deviceServiceProvider).moveFocuserRelative(steps);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to move focuser: $e');
    }
  }

  Future<void> _halt() async {
    try {
      await ref.read(deviceServiceProvider).haltFocuser();
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to halt focuser: $e');
    }
  }

  Future<void> _runAutofocus() async {
    setState(() => _isRunningAutofocus = true);
    ref.read(sessionStateProvider.notifier).setAutofocusing(true);
    try {
      final settings = ref.read(focusSettingsProvider);
      final result = await ref.read(deviceServiceProvider).runAutofocus(
        exposureTime: settings.exposureTime,
        stepSize: settings.afStepSize,
        stepsOut: settings.stepsOut,
        method: settings.method,
        binning: 1,
      );
      ref.read(autofocusResultProvider.notifier).state = result;
      if (mounted) {
        context.showSuccessSnackBar(
          'Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}'
        );
        widget.onAutofocusComplete?.call();
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Autofocus failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isRunningAutofocus = false);
        ref.read(sessionStateProvider.notifier).setAutofocusing(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final focusSettings = ref.watch(focusSettingsProvider);
    final stepSize = focusSettings.stepSize;
    final buttonSize = widget.compact ? 32.0 : 40.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MoveButton(
              icon: LucideIcons.chevronsLeft,
              size: buttonSize,
              onPressed: _isConnected ? () => _moveRelative(-stepSize * 10) : null,
            ),
            const SizedBox(width: 4),
            _MoveButton(
              icon: LucideIcons.chevronLeft,
              size: buttonSize,
              onPressed: _isConnected ? () => _moveRelative(-stepSize) : null,
            ),
            const SizedBox(width: 4),
            _MoveButton(
              icon: LucideIcons.octagon,
              size: buttonSize,
              color: colors.error,
              onPressed: _isConnected ? _halt : null,
            ),
            const SizedBox(width: 4),
            _MoveButton(
              icon: LucideIcons.chevronRight,
              size: buttonSize,
              onPressed: _isConnected ? () => _moveRelative(stepSize) : null,
            ),
            const SizedBox(width: 4),
            _MoveButton(
              icon: LucideIcons.chevronsRight,
              size: buttonSize,
              onPressed: _isConnected ? () => _moveRelative(stepSize * 10) : null,
            ),
          ],
        ),
        if (widget.showAutofocus) ...[
          const SizedBox(height: 8),
          NightshadeButton(
            label: _isRunningAutofocus ? 'Running...' : 'Run Autofocus',
            icon: _isRunningAutofocus ? LucideIcons.loader2 : LucideIcons.focus,
            size: widget.compact ? ButtonSize.small : ButtonSize.medium,
            onPressed: (_isConnected && !_isRunningAutofocus) ? _runAutofocus : null,
          ),
        ],
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final Color? color;

  const _MoveButton({
    required this.icon,
    required this.size,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.5,
            color: onPressed != null ? (color ?? colors.textPrimary) : colors.textMuted,
          ),
        ),
      ),
    );
  }
}
