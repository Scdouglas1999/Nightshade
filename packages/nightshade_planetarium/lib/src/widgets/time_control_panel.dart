import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../astronomy/astronomy_calculations.dart';
import '../providers/planetarium_providers.dart';

/// Time control panel for the planetarium
///
/// Provides controls for:
/// - Real-time toggle
/// - Time speed multiplier
/// - Jump to specific date/time
/// - Jump to tonight's astronomical dusk
class TimeControlPanel extends ConsumerStatefulWidget {
  /// Background color
  final Color? backgroundColor;

  /// Text color
  final Color? textColor;

  /// Accent color for buttons
  final Color? accentColor;

  /// Whether to show compact mode (icon-only buttons)
  final bool compact;

  const TimeControlPanel({
    super.key,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.compact = false,
  });

  @override
  ConsumerState<TimeControlPanel> createState() => _TimeControlPanelState();
}

class _TimeControlPanelState extends ConsumerState<TimeControlPanel> {
  static const List<double> _speedMultipliers = [
    -86400.0, // -1 day/sec
    -3600.0, // -1 hour/sec
    -60.0, // -1 min/sec
    1.0, // Real time
    60.0, // +1 min/sec
    3600.0, // +1 hour/sec
    86400.0, // +1 day/sec
  ];

  int _currentSpeedIndex = 3; // Start at real time (1x)

  @override
  Widget build(BuildContext context) {
    final timeState = ref.watch(observationTimeProvider);
    final twilight = ref.watch(twilightTimesProvider);

    final bgColor = widget.backgroundColor ?? const Color(0xFF1A1A2E);
    final txtColor = widget.textColor ?? Colors.white;
    final accent = widget.accentColor ?? const Color(0xFF00E676);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: txtColor.withValues(alpha: 0.1)),
      ),
      child: widget.compact
          ? _buildCompactLayout(timeState, twilight, txtColor, accent)
          : _buildFullLayout(timeState, twilight, txtColor, accent),
    );
  }

  Widget _buildCompactLayout(
    ObservationTimeState timeState,
    TwilightTimes twilight,
    Color txtColor,
    Color accent,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time display
        _buildTimeDisplay(timeState, txtColor),
        const SizedBox(width: 8),
        // Play/Pause
        _buildPlayPauseButton(timeState, accent),
        // Speed controls
        _buildSpeedButton(isForward: false, color: txtColor),
        _buildSpeedButton(isForward: true, color: txtColor),
        // Now button
        _buildNowButton(accent),
      ],
    );
  }

  Widget _buildFullLayout(
    ObservationTimeState timeState,
    TwilightTimes twilight,
    Color txtColor,
    Color accent,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date/Time row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date button
            _buildDateButton(timeState.time, txtColor),
            const SizedBox(width: 8),
            // Time display
            _buildTimeDisplay(timeState, txtColor),
            const SizedBox(width: 8),
            // Speed indicator
            _buildSpeedIndicator(txtColor),
          ],
        ),
        const SizedBox(height: 8),
        // Controls row
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Fast rewind
            _buildSpeedButton(isForward: false, large: true, color: txtColor),
            const SizedBox(width: 4),
            // Step back
            IconButton(
              icon: Icon(LucideIcons.skipBack, color: txtColor, size: 18),
              onPressed: () => _stepTime(-3600), // -1 hour
              tooltip: 'Back 1 hour',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Play/Pause
            _buildPlayPauseButton(timeState, accent, large: true),
            const SizedBox(width: 4),
            // Step forward
            IconButton(
              icon: Icon(LucideIcons.skipForward, color: txtColor, size: 18),
              onPressed: () => _stepTime(3600), // +1 hour
              tooltip: 'Forward 1 hour',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Fast forward
            _buildSpeedButton(isForward: true, large: true, color: txtColor),
          ],
        ),
        const SizedBox(height: 8),
        // Quick actions row
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNowButton(accent, expanded: false),
            const SizedBox(width: 8),
            _buildTonightButton(twilight, accent),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeDisplay(ObservationTimeState timeState, Color txtColor) {
    final timeFormat = DateFormat('HH:mm:ss');
    final displayTime = timeFormat.format(timeState.time);

    return Text(
      displayTime,
      style: TextStyle(
        color: txtColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _buildDateButton(DateTime time, Color txtColor) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return InkWell(
      onTap: () => _showDatePicker(time),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: txtColor.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendar, size: 14, color: txtColor),
            const SizedBox(width: 4),
            Text(
              dateFormat.format(time),
              style: TextStyle(color: txtColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedIndicator(Color txtColor) {
    final speed = _speedMultipliers[_currentSpeedIndex];
    String speedText;

    if (speed == 1.0) {
      speedText = '1×';
    } else if (speed.abs() >= 86400) {
      speedText = '${speed > 0 ? '+' : ''}${(speed / 86400).round()}d/s';
    } else if (speed.abs() >= 3600) {
      speedText = '${speed > 0 ? '+' : ''}${(speed / 3600).round()}h/s';
    } else if (speed.abs() >= 60) {
      speedText = '${speed > 0 ? '+' : ''}${(speed / 60).round()}m/s';
    } else {
      speedText = '${speed > 0 ? '+' : ''}${speed.round()}×';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: speed != 1.0
            ? (speed > 0 ? Colors.green : Colors.orange).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        speedText,
        style: TextStyle(
          color: speed != 1.0
              ? (speed > 0 ? Colors.green : Colors.orange)
              : txtColor.withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(
    ObservationTimeState timeState,
    Color accent, {
    bool large = false,
  }) {
    final isRealTime = timeState.isRealTime && _currentSpeedIndex == 3;

    return IconButton(
      icon: Icon(
        isRealTime ? LucideIcons.pause : LucideIcons.play,
        color: accent,
        size: large ? 24 : 18,
      ),
      onPressed: _togglePlayPause,
      tooltip: isRealTime ? 'Pause' : 'Play',
      padding: EdgeInsets.all(large ? 12 : 8),
      constraints: const BoxConstraints(),
      style: IconButton.styleFrom(
        backgroundColor: accent.withValues(alpha: 0.1),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildSpeedButton({
    required bool isForward,
    bool large = false,
    required Color color,
  }) {
    return IconButton(
      icon: Icon(
        isForward ? LucideIcons.fastForward : LucideIcons.rewind,
        color: color,
        size: large ? 20 : 16,
      ),
      onPressed: () => _changeSpeed(isForward),
      tooltip: isForward ? 'Faster' : 'Slower',
      padding: EdgeInsets.all(large ? 8 : 4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildNowButton(Color accent, {bool expanded = false}) {
    final button = TextButton.icon(
      icon: Icon(LucideIcons.clock, size: 14, color: accent),
      label: Text('NOW', style: TextStyle(color: accent, fontSize: 11)),
      onPressed: _jumpToNow,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    return expanded ? Expanded(child: button) : button;
  }

  Widget _buildTonightButton(TwilightTimes twilight, Color accent) {
    final hasDusk = twilight.astronomicalDusk != null;

    return TextButton.icon(
      icon: Icon(
        LucideIcons.moon,
        size: 14,
        color: hasDusk ? accent : accent.withValues(alpha: 0.5),
      ),
      label: Text(
        'TONIGHT',
        style: TextStyle(
          color: hasDusk ? accent : accent.withValues(alpha: 0.5),
          fontSize: 11,
        ),
      ),
      onPressed: hasDusk ? () => _jumpToTonight(twilight) : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _togglePlayPause() {
    final notifier = ref.read(observationTimeProvider.notifier);
    final currentState = ref.read(observationTimeProvider);

    if (currentState.isRealTime && _currentSpeedIndex == 3) {
      // Currently real time - pause
      notifier.setRealTime(false);
    } else {
      // Currently paused or accelerated - return to real time
      setState(() => _currentSpeedIndex = 3);
      notifier.setRealTime(true);
    }
  }

  void _changeSpeed(bool faster) {
    setState(() {
      if (faster && _currentSpeedIndex < _speedMultipliers.length - 1) {
        _currentSpeedIndex++;
      } else if (!faster && _currentSpeedIndex > 0) {
        _currentSpeedIndex--;
      }
    });

    final speed = _speedMultipliers[_currentSpeedIndex];
    ref.read(observationTimeProvider.notifier).setSpeedMultiplier(speed);
  }

  void _stepTime(int seconds) {
    final notifier = ref.read(observationTimeProvider.notifier);
    if (seconds > 0) {
      notifier.fastForward(Duration(seconds: seconds));
    } else {
      notifier.rewind(Duration(seconds: -seconds));
    }
  }

  void _jumpToNow() {
    setState(() => _currentSpeedIndex = 3);
    ref.read(observationTimeProvider.notifier).setRealTime(true);
  }

  void _jumpToTonight(TwilightTimes twilight) {
    if (twilight.astronomicalDusk != null) {
      ref.read(observationTimeProvider.notifier).setTime(twilight.astronomicalDusk!);
      ref.read(observationTimeProvider.notifier).setRealTime(false);
    }
  }

  Future<void> _showDatePicker(DateTime currentDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      // Combine picked date with current time
      final currentTime = ref.read(observationTimeProvider).time;
      final newDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        currentTime.hour,
        currentTime.minute,
        currentTime.second,
      );
      ref.read(observationTimeProvider.notifier).setTime(newDateTime);
      ref.read(observationTimeProvider.notifier).setRealTime(false);
    }
  }
}
