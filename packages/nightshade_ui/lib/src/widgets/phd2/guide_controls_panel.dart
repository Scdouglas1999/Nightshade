import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/nightshade_colors.dart';

/// PHD2 guiding state
enum Phd2GuidingState {
  disconnected,
  stopped,
  looping,
  calibrating,
  guiding,
  paused,
  settling,
  lostLock,
}

extension Phd2GuidingStateExtension on Phd2GuidingState {
  String get displayName {
    switch (this) {
      case Phd2GuidingState.disconnected:
        return 'Disconnected';
      case Phd2GuidingState.stopped:
        return 'Stopped';
      case Phd2GuidingState.looping:
        return 'Looping';
      case Phd2GuidingState.calibrating:
        return 'Calibrating';
      case Phd2GuidingState.guiding:
        return 'Guiding';
      case Phd2GuidingState.paused:
        return 'Paused';
      case Phd2GuidingState.settling:
        return 'Settling';
      case Phd2GuidingState.lostLock:
        return 'Lost Lock';
    }
  }

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
    }
  }
}

/// Panel containing main guiding controls
class GuideControlsPanel extends StatefulWidget {
  /// Current guiding state
  final Phd2GuidingState state;

  /// Whether PHD2 is connected
  final bool isConnected;

  /// Callbacks for main controls
  final VoidCallback? onStartGuiding;
  final VoidCallback? onStopGuiding;
  final VoidCallback? onPauseGuiding;
  final VoidCallback? onResumeGuiding;
  final VoidCallback? onLoop;
  final VoidCallback? onFindStar;
  final VoidCallback? onDeselectStar;

  /// Dither controls
  final double ditherAmount;
  final bool ditherRaOnly;
  final void Function(double)? onDitherAmountChanged;
  final void Function(bool)? onDitherRaOnlyChanged;
  final VoidCallback? onDither;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusHeader(colors),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.state.icon, color: stateColor, size: iconSize),
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
                  boxShadow: [
                    BoxShadow(
                      color: (widget.isConnected ? colors.success : colors.error)
                          .withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainControls(NightshadeColors colors) {
    final isGuiding = widget.state == Phd2GuidingState.guiding;
    final isPaused = widget.state == Phd2GuidingState.paused;
    final isLooping = widget.state == Phd2GuidingState.looping;
    final isStopped = widget.state == Phd2GuidingState.stopped ||
        widget.state == Phd2GuidingState.disconnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Guiding Controls', LucideIcons.target, colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                icon: isGuiding || isLooping ? LucideIcons.square : LucideIcons.play,
                label: isGuiding || isLooping ? 'Stop' : 'Start',
                color: isGuiding || isLooping ? colors.error : colors.success,
                colors: colors,
                onPressed: widget.isConnected
                    ? (isGuiding || isLooping ? widget.onStopGuiding : widget.onStartGuiding)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildControlButton(
                icon: isPaused ? LucideIcons.play : LucideIcons.pause,
                label: isPaused ? 'Resume' : 'Pause',
                color: colors.warning,
                colors: colors,
                onPressed: isGuiding || isPaused
                    ? (isPaused ? widget.onResumeGuiding : widget.onPauseGuiding)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildControlButton(
          icon: LucideIcons.refreshCw,
          label: 'Loop Exposures',
          color: colors.info,
          colors: colors,
          onPressed: isStopped && widget.isConnected ? widget.onLoop : null,
        ),
      ],
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
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                '${widget.ditherAmount.toStringAsFixed(0)}',
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
              onTap: () => widget.onDitherRaOnlyChanged?.call(!widget.ditherRaOnly),
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
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _buildControlButton(
              icon: LucideIcons.shuffle,
              label: 'Dither Now',
              color: colors.accent,
              colors: colors,
              small: true,
              onPressed: widget.state == Phd2GuidingState.guiding ? widget.onDither : null,
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
                Text(
                  'Settle Settings',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
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
                _buildSettingRow('Pixels', widget.settlePixels, 0.5, 5.0, widget.onSettlePixelsChanged, colors),
                const SizedBox(height: 8),
                _buildSettingRow('Time (s)', widget.settleTime, 5, 60, widget.onSettleTimeChanged, colors),
                const SizedBox(height: 8),
                _buildSettingRow('Timeout (s)', widget.settleTimeout, 30, 180, widget.onSettleTimeoutChanged, colors),
              ],
            ),
          ),
          crossFadeState: _settleExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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

  Widget _buildSectionHeader(String title, IconData icon, NightshadeColors colors) {
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
    required IconData icon,
    required String label,
    required Color color,
    required NightshadeColors colors,
    VoidCallback? onPressed,
    bool isOutline = false,
    bool small = false,
  }) {
    final isDisabled = onPressed == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
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
                  : (isDisabled ? colors.surfaceAlt : color.withValues(alpha: 0.15)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDisabled
                    ? colors.border
                    : (isOutline ? colors.border : color.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  icon,
                  size: small ? 14 : 16,
                  color: isDisabled ? colors.textMuted : color,
                ),
                SizedBox(width: small ? 6 : 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    color: isDisabled ? colors.textMuted : color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
