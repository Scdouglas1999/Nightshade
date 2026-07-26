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
  ProviderSubscription<DeviceService>? _serviceSubscription;

  @override
  void initState() {
    super.initState();
    _serviceSubscription = ref.listenManual<DeviceService>(
      deviceServiceProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        if (_isRunningAutofocus && mounted) {
          setState(() => _isRunningAutofocus = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _serviceSubscription?.close();
    super.dispose();
  }

  void _showGoToPositionDialog() {
    final focuserState = ref.read(focuserStateProvider);
    showDialog<void>(
      context: context,
      builder: (_) => GoToPositionDialog(
        initialPosition: focuserState.position ?? 0,
        // Null when the driver hasn't reported a travel limit; the dialog must
        // validate against the real max only when it is actually known rather
        // than fabricating a ceiling.
        maxPosition: focuserState.maxPosition,
        onSubmit: (position) =>
            ref.read(deviceServiceProvider).moveFocuserTo(position),
        // Awaited hardware stop, invoked when the user aborts a move that is
        // already in flight so the dialog never walks away from a driving
        // focuser.
        onHalt: () => ref.read(deviceServiceProvider).haltFocuser(),
      ),
    );
  }

  Future<void> _runAutofocus() async {
    if (_isRunningAutofocus ||
        ref.read(deviceServiceProvider).isAutofocusRunning) {
      return;
    }
    final service = ref.read(deviceServiceProvider);
    setState(() => _isRunningAutofocus = true);

    try {
      final settings = ref.read(focusSettingsProvider);
      final result = await service.runAutofocus(
        exposureTime: settings.exposureTime,
        stepSize: settings.afStepSize,
        stepsOut: settings.stepsOut,
        method: settings.method,
        binning: 1,
        useSettingsDefaults: false,
      );

      if (mounted && _isCurrentService(service)) {
        context.showSuccessSnackBar(
            'Autofocus complete! Position: ${result.bestPosition}, HFR: ${result.bestHfr.toStringAsFixed(2)}');
      }
    } on AutofocusCancelledException {
      if (mounted && _isCurrentService(service)) {
        context.showInfoSnackBar('Autofocus cancelled');
      }
    } catch (e) {
      if (mounted && _isCurrentService(service)) {
        context.showErrorSnackBar('Autofocus failed: $e');
      }
    } finally {
      if (_isCurrentService(service)) {
        setState(() => _isRunningAutofocus = false);
      }
    }
  }

  bool _isCurrentService(DeviceService service) =>
      mounted && identical(ref.read(deviceServiceProvider), service);

  @override
  Widget build(BuildContext context) {
    final focuserState = ref.watch(focuserStateProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final sessionState = ref.watch(sessionStateProvider);
    final focusSettings = ref.watch(focusSettingsProvider);
    final isConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final currentPosition = focuserState.position ?? 0;
    final rawMaxPosition = focuserState.maxPosition;
    // A driver may not report a travel ceiling (null) or may report a bogus
    // negative one; treat both as "unknown" and show an honest marker rather
    // than inventing a limit the hardware never claimed.
    final hasKnownMax = rawMaxPosition != null && rawMaxPosition > 0;
    final positionSuffix = !isConnected
        ? ''
        : hasKnownMax
            ? ' / $rawMaxPosition'
            : ' / —';
    final temperature = focuserState.temperature;
    final isMoving = focuserState.isMoving;
    final autofocusRunning = sessionState.isAutofocusing || _isRunningAutofocus;
    final cameraConnected =
        cameraState.connectionState == DeviceConnectionState.connected;

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
              decoration: NightshadeDecorations.emphasisSurface(
                widget.colors.warning,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No focuser connected',
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: widget.colors.warning),
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
                            fontSize: NightshadeTypography.fontSize12,
                            color: widget.colors.textSecondary)),
                    Row(
                      children: [
                        Text(
                          isConnected ? '$currentPosition' : '---',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize18,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          positionSuffix,
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: widget.colors.textMuted),
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
                                fontSize: NightshadeTypography.fontSize12,
                                color: widget.colors.textSecondary)),
                        Text(
                          '${temperature.toStringAsFixed(1)}°C',
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: widget.colors.textPrimary),
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
                            fontSize: NightshadeTypography.fontSize11,
                            color: widget.colors.textSecondary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [10, 50, 100, 500].map((step) {
                            final isSelected = focusSettings.stepSize == step;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => ref
                                    .read(focusSettingsProvider.notifier)
                                    .update(
                                        focusSettings.copyWith(stepSize: step)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: isSelected
                                      ? NightshadeDecorations.selectedSurface(
                                          widget.colors.primary,
                                          borderRadius: BorderRadius.circular(
                                              NightshadeTokens.radiusInline4),
                                          fillAlpha: 0.15,
                                        )
                                      : BoxDecoration(
                                          color: widget.colors.background,
                                          borderRadius: BorderRadius.circular(
                                              NightshadeTokens.radiusInline4),
                                          border: Border.all(
                                            color: widget.colors.border,
                                          ),
                                        ),
                                  child: Text(
                                    '$step',
                                    style: TextStyle(
                                      fontSize: NightshadeTypography.fontSize10,
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
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Go to position button
                SizedBox(
                  width: double.infinity,
                  child: SmallButton(
                    label: 'Go To Position...',
                    icon: NightshadeIcons.move,
                    colors: widget.colors,
                    isEnabled: isConnected &&
                        focuserState.isAbsolute &&
                        !isMoving &&
                        !autofocusRunning,
                    onTap: _showGoToPositionDialog,
                  ),
                ),
                if (isConnected && !focuserState.isAbsolute)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Absolute positioning is not supported by this focuser.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: widget.colors.textMuted,
                      ),
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
                    label: autofocusRunning ? 'Running...' : 'Run Autofocus',
                    icon: autofocusRunning
                        ? NightshadeIcons.loading
                        : NightshadeIcons.focuser,
                    colors: widget.colors,
                    isEnabled: isConnected &&
                        cameraConnected &&
                        !isMoving &&
                        !autofocusRunning,
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

/// Modal for sending the focuser to an absolute position.
///
/// Owns its own [TextEditingController] and in-flight state so the move can be
/// awaited without losing the typed value. Cancellation is truthful:
///  * before the move is submitted, Cancel simply backs out and never touches
///    the focuser;
///  * once a move is in flight the only way out is to actually stop the
///    hardware — the action row swaps Cancel for a Stop button that awaits
///    [onHalt], and back/Escape/barrier dismissal is routed to the same halt
///    rather than silently abandoning a driving focuser;
///  * a failure of either the move or the halt keeps the dialog open with an
///    inline, retryable error, and the route is dismissed only after the move
///    succeeds or the halt actually completes.
class GoToPositionDialog extends StatefulWidget {
  /// Value the field starts on — usually the focuser's current position.
  final int initialPosition;

  /// Upper travel limit, or null when the driver hasn't reported one. A
  /// non-positive value from a broken/unknown driver is treated the same as
  /// null. When the
  /// max is unknown the dialog validates only the lower bound instead of
  /// inventing a ceiling.
  final int? maxPosition;

  /// Performs the move. Resolves on success; throwing keeps the dialog open.
  final Future<void> Function(int position) onSubmit;

  /// Halts the focuser. Awaited when the user aborts an in-flight move so the
  /// dialog never closes while the hardware is still driving; throwing keeps
  /// the dialog open with a retryable error.
  final Future<void> Function() onHalt;

  const GoToPositionDialog({
    super.key,
    required this.initialPosition,
    required this.maxPosition,
    required this.onSubmit,
    required this.onHalt,
  });

  @override
  State<GoToPositionDialog> createState() => _GoToPositionDialogState();
}

class _GoToPositionDialogState extends State<GoToPositionDialog> {
  late final TextEditingController _controller;
  bool _submitting = false;
  bool _halting = false;
  bool _dismissed = false;
  String? _errorText;
  String? _haltError;

  /// True while either the move or the halt is still resolving. Both the pop
  /// guard and the control layout key off this so nothing dismisses or
  /// re-submits mid-command.
  bool get _inFlight => _submitting || _halting;

  /// A real, positive ceiling actually reported by the driver, or null.
  int? get _knownMax {
    final max = widget.maxPosition;
    return (max != null && max > 0) ? max : null;
  }

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialPosition.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _rangeHint =>
      _knownMax != null ? '0 - $_knownMax' : '0 or greater';

  /// Pops the route at most once. The move and halt futures can resolve in
  /// either order (or after the widget is gone); this guard keeps them from
  /// double-popping or popping after dispose.
  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    // Guard against a second submit while a command is already in flight.
    if (_inFlight) return;

    final position = int.tryParse(_controller.text.trim());
    if (position == null) {
      setState(() => _errorText = 'Enter a whole number.');
      return;
    }
    if (position < 0) {
      setState(() => _errorText = 'Position must be 0 or greater.');
      return;
    }
    final max = _knownMax;
    if (max != null && position > max) {
      setState(() => _errorText = 'Position must be between 0 and $max.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await widget.onSubmit(position);
      if (!mounted) return;
      // If the user asked to stop mid-move, let the halt path own dismissal so
      // the two futures never both pop.
      if (_halting) {
        setState(() => _submitting = false);
        return;
      }
      _dismiss();
    } catch (e) {
      if (!mounted) return;
      // Keep the dialog and the typed value so the user can retry. A halt in
      // flight owns the visible error, so don't clobber it here.
      setState(() {
        _submitting = false;
        if (!_halting) _errorText = 'Move failed: $e';
      });
    }
  }

  /// Awaits a real hardware halt, then dismisses. Kept separate from the
  /// pre-move Cancel so an ordinary back-out never issues a stop command.
  Future<void> _halt() async {
    // Duplicate-guard so repeated Stop taps (or barrier gestures) issue a
    // single halt.
    if (_halting) return;
    setState(() {
      _halting = true;
      _haltError = null;
    });

    try {
      await widget.onHalt();
      if (!mounted) return;
      _dismiss();
    } catch (e) {
      if (!mounted) return;
      // Stop failed — stay open with a retryable error rather than closing on
      // a focuser that may still be moving.
      setState(() {
        _halting = false;
        _haltError = 'Stop failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While a command is in flight the route must not be abandoned silently;
      // back/Escape/barrier are intercepted below and turned into a real halt.
      canPop: !_inFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // A move is running and the OS/back/barrier tried to close us. Don't
        // walk away from a driving focuser — convert the gesture into a real
        // halt, which dismisses only once the hardware actually stops.
        if (_submitting && !_halting) _halt();
      },
      child: AlertDialog(
        title: const Text('Go To Position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NightshadeTextField(
              label: 'Position',
              hint: _rangeHint,
              controller: _controller,
              keyboardType: TextInputType.number,
              enabled: !_inFlight,
              errorText: _errorText,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_haltError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _haltError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          if (!_inFlight)
            NightshadeButton(
              // Pre-move backout: no hardware command, just leave.
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            )
          else
            NightshadeButton(
              // Truthful abort: awaits the real halt before closing, with its
              // own busy state and duplicate guard.
              onPressed: _halting ? null : _halt,
              isLoading: _halting,
              label: _halting ? 'Stopping...' : 'Stop',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
            ),
          NightshadeButton(
            onPressed: _inFlight ? null : _submit,
            isLoading: _submitting,
            label: _submitting ? 'Moving...' : 'Go',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}
