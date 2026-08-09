import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// Phd2GuidingState (and its displayName extension) are owned by nightshade_core.
// This UI-only extension layers on the icon mapping that's specific to widgets.
extension Phd2GuidingStateIcon on Phd2GuidingState {
  IconData get icon {
    switch (this) {
      case Phd2GuidingState.disconnected:
        return LucideIcons.cloudOff;
      case Phd2GuidingState.stopped:
        return LucideIcons.square;
      case Phd2GuidingState.looping:
        return LucideIcons.refreshCw;
      case Phd2GuidingState.calibrating:
        return LucideIcons.settings;
      case Phd2GuidingState.guiding:
        return LucideIcons.crosshair;
      case Phd2GuidingState.paused:
        return LucideIcons.pause;
      case Phd2GuidingState.settling:
        return LucideIcons.timer;
      case Phd2GuidingState.lostLock:
        return LucideIcons.alertTriangle;
      case Phd2GuidingState.unknown:
        return LucideIcons.helpCircle;
    }
  }
}

/// Panel containing main guiding controls
class GuideControlsPanel extends StatefulWidget {
  /// Key of the "more content below" fade + chevron affordance. Present only
  /// while the control list is taller than its slot.
  static const Key moreBelowKey = ValueKey('guideControlsMoreBelow');

  /// Current guiding state
  final Phd2GuidingState state;

  /// Whether PHD2 is connected
  final bool isConnected;

  /// Callbacks for main controls.
  ///
  /// These are async on purpose: each issues a real hardware command. The panel
  /// awaits them with its own busy/error handling (see [_runAction]) so a tap
  /// stays busy until the command is accepted or fails, a second tap cannot
  /// duplicate the native call, and a thrown error is surfaced instead of
  /// escaping as an unhandled Future.
  final Future<void> Function()? onStartGuiding;
  final Future<void> Function()? onStopGuiding;
  final Future<void> Function()? onPauseGuiding;
  final Future<void> Function()? onResumeGuiding;
  final Future<void> Function()? onLoop;
  final Future<void> Function()? onFindStar;
  final Future<void> Function()? onDeselectStar;

  /// Dither controls
  final double ditherAmount;
  final bool ditherRaOnly;
  final void Function(double)? onDitherAmountChanged;
  final void Function(bool)? onDitherRaOnlyChanged;
  final Future<void> Function()? onDither;

  /// Settle parameters
  final double settlePixels;
  final double settleTime;
  final double settleTimeout;
  final void Function(double)? onSettlePixelsChanged;
  final void Function(double)? onSettleTimeChanged;
  final void Function(double)? onSettleTimeoutChanged;

  const GuideControlsPanel({
    super.key,
    required this.state,
    required this.isConnected,
    this.onStartGuiding,
    this.onStopGuiding,
    this.onPauseGuiding,
    this.onResumeGuiding,
    this.onLoop,
    this.onFindStar,
    this.onDeselectStar,
    this.ditherAmount = 5.0,
    this.ditherRaOnly = false,
    this.onDitherAmountChanged,
    this.onDitherRaOnlyChanged,
    this.onDither,
    this.settlePixels = 1.5,
    this.settleTime = 10.0,
    this.settleTimeout = 60.0,
    this.onSettlePixelsChanged,
    this.onSettleTimeChanged,
    this.onSettleTimeoutChanged,
  });

  @override
  State<GuideControlsPanel> createState() => _GuideControlsPanelState();
}

class _GuideControlsPanelState extends State<GuideControlsPanel> {
  bool _settleExpanded = false;

  /// Scroll state for the overflow affordance. [_hasMoreBelow] drives the fade
  /// + chevron, [_isScrolled] keeps the scrollbar thumb visible once the user
  /// has reached the bottom so the region still reads as scrollable.
  final ScrollController _scrollController = ScrollController();
  bool _hasMoreBelow = false;
  bool _isScrolled = false;

  /// Recompute the overflow flags from live scroll metrics. Driven by both
  /// `ScrollNotification` (user scrolled) and `ScrollMetricsNotification`
  /// (content or viewport changed size without a scroll), so expanding the
  /// Settle Settings section updates the affordance immediately.
  void _updateOverflow(ScrollMetrics metrics) {
    final hasMoreBelow = metrics.extentAfter > 4;
    final isScrolled = metrics.extentBefore > 4;
    if (hasMoreBelow == _hasMoreBelow && isScrolled == _isScrolled) return;
    // Metrics notifications arrive during layout/paint; defer the rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hasMoreBelow == _hasMoreBelow && isScrolled == _isScrolled) return;
      setState(() {
        _hasMoreBelow = hasMoreBelow;
        _isScrolled = isScrolled;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Two busy lanes mirroring the controller's command gate so a Stop can
  /// always pre-empt a settling Start (the safe abort direction) while a
  /// duplicate of either is swallowed. [_positiveInFlight] holds the id of the
  /// running start/pause/resume/loop/dither/star action; [_stopInFlight] tracks
  /// the Stop lane independently. The active button shows a spinner; a command
  /// stays busy until it is accepted or fails, so a double-tap cannot fire a
  /// second native call.
  String? _positiveInFlight;
  bool _stopInFlight = false;

  /// Last command error, surfaced inline (dismissible) instead of escaping as
  /// an unhandled Future or silently reverting the button to an idle look.
  String? _errorText;

  bool get _positiveBusy => _positiveInFlight != null || _stopInFlight;

  /// Await [action] with local busy + error handling. Stop rides its own lane
  /// (can run even while a positive command is in flight); everything else is
  /// serialised behind the positive lane. No-ops when the action is
  /// unavailable or the relevant lane is already occupied.
  Future<void> _runAction(String id, Future<void> Function()? action) async {
    if (action == null) return;
    final isStop = id == 'stop';
    if (isStop) {
      if (_stopInFlight) return;
    } else if (_positiveBusy) {
      return;
    }
    setState(() {
      if (isStop) {
        _stopInFlight = true;
      } else {
        _positiveInFlight = id;
      }
      _errorText = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _errorText = _messageFor(e));
    } finally {
      if (mounted) {
        setState(() {
          if (isStop) {
            _stopInFlight = false;
          } else {
            _positiveInFlight = null;
          }
        });
      }
    }
  }

  String _messageFor(Object error) {
    if (error is StateError) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  Color _getStateColor(NightshadeColors colors) {
    switch (widget.state) {
      case Phd2GuidingState.disconnected:
      case Phd2GuidingState.stopped:
        return colors.textMuted;
      case Phd2GuidingState.looping:
        return colors.warning;
      case Phd2GuidingState.calibrating:
        return colors.warning;
      case Phd2GuidingState.guiding:
        return colors.success;
      case Phd2GuidingState.paused:
        return colors.info;
      case Phd2GuidingState.settling:
        return colors.info;
      case Phd2GuidingState.lostLock:
        return colors.error;
      case Phd2GuidingState.unknown:
        return colors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusHeader(colors),
          Expanded(
            // At common laptop heights (e.g. a 1000 px-tall window) the panel
            // is taller than its slot, and the only hint that Settle Settings
            // existed was a few pixels of a card edge at the bottom margin —
            // the control that governs post-dither settle was effectively
            // invisible. Keep the scrollbar thumb permanently visible and fade
            // the clipped edge so hidden content announces itself.
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      _updateOverflow(notification.metrics);
                      return false;
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        _updateOverflow(notification.metrics);
                        return false;
                      },
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: _hasMoreBelow || _isScrolled,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorText != null) ...[
                                _buildErrorBanner(colors, _errorText!),
                                const SizedBox(height: 16),
                              ],
                              _buildMainControls(colors),
                              const SizedBox(height: 20),
                              _buildStarSelection(colors),
                              const SizedBox(height: 20),
                              _buildDitherControls(colors),
                              const SizedBox(height: 16),
                              _buildSettleSettings(colors),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_hasMoreBelow)
                  Positioned(
                    key: GuideControlsPanel.moreBelowKey,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.surface.withValues(alpha: 0.0),
                              colors.surface,
                            ],
                          ),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(NightshadeColors colors) {
    final stateColor = _getStateColor(colors);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact layout for narrow panels
        final isCompact = constraints.maxWidth < 280;
        final iconSize = isCompact ? 14.0 : 16.0;
        final iconPadding = isCompact ? 4.0 : 6.0;
        final fontSize = isCompact ? 12.0 : 14.0;
        final horizontalPadding = isCompact ? 10.0 : 16.0;

        return Container(
          padding:
              EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(widget.state.icon, color: stateColor, size: iconSize),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.state.displayName,
                  style: TextStyle(
                    color: stateColor,
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isConnected ? colors.success : colors.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainControls(NightshadeColors colors) {
    // All enable/label decisions flow from the shared capability layer so the
    // desktop and mobile controls (which share this widget) can never disagree
    // about what is legal. In particular: paused / calibrating / settling /
    // lost-lock / unknown are all "busy" phases whose primary action is Stop —
    // an enabled Start is NEVER offered there.
    final state = widget.state;
    final connected = widget.isConnected;
    final canStart = connected && state.canStart;
    final canStop = connected && state.canStop;

    // Primary button: Stop whenever the session is live/uncertain, Start only
    // from a genuinely idle-but-connected state, disabled otherwise.
    final primaryIsStop = canStop;
    final String primaryId = primaryIsStop ? 'stop' : 'start';
    final Future<void> Function()? primaryAction = primaryIsStop
        ? (canStop ? widget.onStopGuiding : null)
        : (canStart ? widget.onStartGuiding : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Guiding Controls', LucideIcons.target, colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                id: primaryId,
                icon: primaryIsStop ? LucideIcons.square : LucideIcons.play,
                label: primaryIsStop ? 'Stop' : 'Start',
                color: primaryIsStop ? colors.error : colors.success,
                colors: colors,
                onPressed: primaryAction,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildControlButton(
                id: state.canResume ? 'resume' : 'pause',
                icon: state.canResume ? LucideIcons.play : LucideIcons.pause,
                label: state.canResume ? 'Resume' : 'Pause',
                color: colors.warning,
                colors: colors,
                onPressed: connected
                    ? (state.canResume
                        ? widget.onResumeGuiding
                        : (state.canPause ? widget.onPauseGuiding : null))
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildControlButton(
          id: 'loop',
          icon: LucideIcons.refreshCw,
          label: 'Loop Exposures',
          color: colors.info,
          colors: colors,
          onPressed: connected && state.canLoop ? widget.onLoop : null,
        ),
      ],
    );
  }

  Widget _buildErrorBanner(NightshadeColors colors, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _errorText = null),
            behavior: HitTestBehavior.opaque,
            child: Icon(LucideIcons.x, size: 16, color: colors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildStarSelection(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Star Selection', LucideIcons.star, colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                id: 'findStar',
                icon: LucideIcons.search,
                label: 'Auto Select',
                color: colors.primary,
                colors: colors,
                onPressed: widget.isConnected ? widget.onFindStar : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildControlButton(
                id: 'deselectStar',
                icon: LucideIcons.x,
                label: 'Deselect',
                color: colors.textSecondary,
                colors: colors,
                isOutline: true,
                onPressed: widget.isConnected ? widget.onDeselectStar : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDitherControls(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Dither', LucideIcons.shuffle, colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Amount:',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.surfaceAlt,
                  thumbColor: colors.primary,
                  overlayColor: colors.primary.withValues(alpha: 0.2),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: widget.ditherAmount,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  onChanged: widget.onDitherAmountChanged,
                ),
              ),
            ),
            Container(
              width: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.ditherAmount.toStringAsFixed(0),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Wrap checkbox with GestureDetector for larger touch target (44px minimum)
            GestureDetector(
              onTap: () =>
                  widget.onDitherRaOnlyChanged?.call(!widget.ditherRaOnly),
              behavior: HitTestBehavior.opaque,
              child: Container(
                // 44px minimum touch target, but visually compact
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: widget.ditherRaOnly,
                        onChanged: (value) =>
                            widget.onDitherRaOnlyChanged?.call(value ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: colors.border),
                        activeColor: colors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'RA Only',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _buildControlButton(
                id: 'dither',
                icon: LucideIcons.shuffle,
                label: 'Dither Now',
                color: colors.accent,
                colors: colors,
                small: true,
                onPressed: widget.state.canDither ? widget.onDither : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettleSettings(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _settleExpanded = !_settleExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.settings2,
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Settle Settings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _settleExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _buildSettingRow('Pixels', widget.settlePixels, 0.5, 5.0,
                    widget.onSettlePixelsChanged, colors),
                const SizedBox(height: 8),
                _buildSettingRow('Time (s)', widget.settleTime, 5, 60,
                    widget.onSettleTimeChanged, colors),
                const SizedBox(height: 8),
                _buildSettingRow('Timeout (s)', widget.settleTimeout, 30, 180,
                    widget.onSettleTimeoutChanged, colors),
              ],
            ),
          ),
          crossFadeState: _settleExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildSettingRow(String label, double value, double min, double max,
      void Function(double)? onChanged, NightshadeColors colors) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: colors.primary.withValues(alpha: 0.7),
              inactiveTrackColor: colors.surfaceHover,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, NightshadeColors colors) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required String id,
    required IconData icon,
    required String label,
    required Color color,
    required NightshadeColors colors,
    Future<void> Function()? onPressed,
    bool isOutline = false,
    bool small = false,
  }) {
    // Stop rides its own lane so it stays tappable to abort a settling Start;
    // every other action is locked while any command is in flight so no second
    // native call can be issued until the current one settles.
    final isStop = id == 'stop';
    final isThisBusy = isStop ? _stopInFlight : _positiveInFlight == id;
    final laneBusy = isStop ? _stopInFlight : _positiveBusy;
    final isDisabled = onPressed == null || laneBusy;

    // These are the controls that start and stop guiding, so they must publish
    // a button role and their enabled state. Without this wrapper the bare
    // Material > InkWell reached assistive tech as an unnamed generic node
    // ("panel: Start") that never carried DISABLED, so a screen-reader user was
    // never told Start was unavailable while PHD2 was disconnected. The tap
    // action is republished here because excludeSemantics drops the InkWell's
    // own gesture semantics along with the duplicate label node.
    return Semantics(
      container: true,
      button: true,
      enabled: !isDisabled,
      label: label,
      onTap: isDisabled ? null : () => _runAction(id, onPressed),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : () => _runAction(id, onPressed),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            // Ensure minimum 44px touch target height for accessibility
            constraints: BoxConstraints(minHeight: small ? 40 : 44),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: small ? 10 : 12,
                vertical: small ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: isOutline
                    ? Colors.transparent
                    : (isDisabled
                        ? colors.surfaceAlt
                        : color.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDisabled
                      ? colors.border
                      : (isOutline
                          ? colors.border
                          : color.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (isThisBusy)
                    SizedBox(
                      width: small ? 14 : 16,
                      height: small ? 14 : 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: small ? 14 : 16,
                      color: isDisabled ? colors.textMuted : color,
                    ),
                  SizedBox(width: small ? 6 : 8),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: small ? 11 : 12,
                        fontWeight: FontWeight.w500,
                        color: isDisabled ? colors.textMuted : color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
