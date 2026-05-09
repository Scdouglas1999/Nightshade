import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/focuser_controls.dart';
import 'panel_widgets.dart';

class FocusPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const FocusPanel({super.key, required this.colors});

  @override
  ConsumerState<FocusPanel> createState() => _FocusPanelState();
}

class _FocusPanelState extends ConsumerState<FocusPanel> {
  // UI-only transient state (doesn't need to persist)
  bool _isRunningAutofocus = false;

  Future<void> _goToPosition(int position) async {
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.moveFocuserTo(position);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Focuser error: $e');
    }
  }

  void _showGoToPositionDialog() {
    final focuserState = ref.read(focuserStateProvider);
    final maxPosition = focuserState.maxPosition ?? 50000;
    final currentPosition = focuserState.position ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        final controller =
            TextEditingController(text: currentPosition.toString());
        return AlertDialog(
          title: const Text('Go To Position'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter position (0 - $maxPosition):'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Position',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            GradientDialogButton(
              onPressed: () {
                final position = int.tryParse(controller.text);
                if (position != null &&
                    position >= 0 &&
                    position <= maxPosition) {
                  Navigator.of(context).pop();
                  _goToPosition(position);
                } else {
                  context.showWarningSnackBar(
                      'Invalid position. Must be between 0 and $maxPosition');
                }
              },
              color: Theme.of(context).extension<NightshadeColors>()!.primary,
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
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
            'Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Autofocus failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRunningAutofocus = false);
        ref.read(sessionStateProvider.notifier).setAutofocusing(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final focuserState = ref.watch(focuserStateProvider);
    final focusSettings = ref.watch(focusSettingsProvider);
    final isConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final currentPosition = focuserState.position ?? 0;
    final maxPosition = focuserState.maxPosition ?? 50000;
    final temperature = focuserState.temperature;
    final isMoving = focuserState.isMoving;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No focuser connected',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Manual Focus Section
          PanelSection(
            title: 'Manual Focus',
            colors: widget.colors,
            child: Column(
              children: [
                // Position display
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Position',
                        style: TextStyle(
                            fontSize: 12, color: widget.colors.textSecondary)),
                    Row(
                      children: [
                        Text(
                          isConnected ? '$currentPosition' : '---',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          isConnected ? ' / $maxPosition' : '',
                          style: TextStyle(
                              fontSize: 12, color: widget.colors.textMuted),
                        ),
                        if (isMoving)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.colors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (temperature != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Temperature',
                            style: TextStyle(
                                fontSize: 12,
                                color: widget.colors.textSecondary)),
                        Text(
                          '${temperature.toStringAsFixed(1)}°C',
                          style: TextStyle(
                              fontSize: 12, color: widget.colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Movement buttons - using shared FocuserControls widget
                const FocuserControls(
                  compact: true,
                  showAutofocus: false,
                ),
                const SizedBox(height: 12),

                // Step size selector
                Row(
                  children: [
                    Text('Step Size:',
                        style: TextStyle(
                            fontSize: 11, color: widget.colors.textSecondary)),
                    const SizedBox(width: 8),
                    ...[10, 50, 100, 500].map((step) {
                      final isSelected = focusSettings.stepSize == step;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => ref
                              .read(focusSettingsProvider.notifier)
                              .update(focusSettings.copyWith(stepSize: step)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.colors.primary.withValues(alpha: 0.2)
                                  : widget.colors.background,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? widget.colors.primary
                                    : widget.colors.border,
                              ),
                            ),
                            child: Text(
                              '$step',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? widget.colors.primary
                                    : widget.colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),

                // Go to position button
                SizedBox(
                  width: double.infinity,
                  child: SmallButton(
                    label: 'Go To Position...',
                    icon: LucideIcons.move,
                    colors: widget.colors,
                    isEnabled: isConnected && !isMoving,
                    onTap: _showGoToPositionDialog,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Autofocus Section
          PanelSection(
            title: 'Autofocus',
            colors: widget.colors,
            child: Column(
              children: [
                DropdownRow(
                  label: 'Method',
                  value: focusSettings.method,
                  items: const ['V-Curve', 'Hyperbolic', 'Parabolic'],
                  colors: widget.colors,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(focusSettingsProvider.notifier)
                          .update(focusSettings.copyWith(method: value));
                    }
                  },
                ),
                const SizedBox(height: 12),
                InputRowEditable(
                  label: 'Step Size',
                  value: '${focusSettings.afStepSize}',
                  suffix: 'steps',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref
                          .read(focusSettingsProvider.notifier)
                          .update(focusSettings.copyWith(afStepSize: parsed));
                    }
                  },
                ),
                const SizedBox(height: 12),
                InputRowEditable(
                  label: 'Steps Out',
                  value: '${focusSettings.stepsOut}',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref
                          .read(focusSettingsProvider.notifier)
                          .update(focusSettings.copyWith(stepsOut: parsed));
                    }
                  },
                ),
                const SizedBox(height: 12),
                InputRowEditable(
                  label: 'Exposure',
                  value: focusSettings.exposureTime.toStringAsFixed(1),
                  suffix: 'sec',
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref
                          .read(focusSettingsProvider.notifier)
                          .update(focusSettings.copyWith(exposureTime: parsed));
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SmallButton(
                    label: _isRunningAutofocus ? 'Running...' : 'Run Autofocus',
                    icon: _isRunningAutofocus
                        ? LucideIcons.loader2
                        : LucideIcons.focus,
                    colors: widget.colors,
                    isEnabled: isConnected && !_isRunningAutofocus,
                    onTap: _runAutofocus,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
