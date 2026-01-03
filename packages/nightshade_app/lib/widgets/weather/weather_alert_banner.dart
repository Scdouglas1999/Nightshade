import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Global weather alert banner that appears at the top of the app
/// when weather conditions reach warning or critical levels.
///
/// Features:
/// - Animated entrance/exit
/// - Color-coded by severity (warning = orange, critical = red)
/// - Shows alert message and ETA if available
/// - Snooze button for temporary dismissal
/// - Tap to navigate to weather screen
class WeatherAlertBanner extends ConsumerStatefulWidget {
  const WeatherAlertBanner({super.key});

  @override
  ConsumerState<WeatherAlertBanner> createState() => _WeatherAlertBannerState();
}

class _WeatherAlertBannerState extends ConsumerState<WeatherAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final safetyState = ref.watch(weatherSafetyProvider);
    final alertLevel = safetyState.currentAlertLevel;
    final status = safetyState.status;

    // Only show banner for warning or critical levels when not snoozed
    final shouldShow = (alertLevel == AlertLevel.warning ||
            alertLevel == AlertLevel.critical) &&
        status != WeatherSafetyStatus.snoozed;

    // Animate in/out
    if (shouldShow) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        if (_animationController.isDismissed) {
          return const SizedBox.shrink();
        }

        return ClipRect(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
                      .animate(_animationController),
              child: _BannerContent(
                colors: colors,
                alertLevel: alertLevel,
                actions: safetyState.actions,
                onSnooze: () {
                  ref
                      .read(weatherSafetyProvider.notifier)
                      .snooze(const Duration(minutes: 15));
                },
                onTap: () => context.go('/weather'),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The actual banner content
class _BannerContent extends StatelessWidget {
  final NightshadeColors colors;
  final AlertLevel alertLevel;
  final WeatherSafetyActions actions;
  final VoidCallback onSnooze;
  final VoidCallback onTap;

  const _BannerContent({
    required this.colors,
    required this.alertLevel,
    required this.actions,
    required this.onSnooze,
    required this.onTap,
  });

  Color _getBackgroundColor() {
    switch (alertLevel) {
      case AlertLevel.warning:
        return const Color(0xFFFF9800); // Orange
      case AlertLevel.critical:
        return colors.error;
      default:
        return colors.warning;
    }
  }

  IconData _getIcon() {
    switch (alertLevel) {
      case AlertLevel.warning:
        return LucideIcons.alertTriangle;
      case AlertLevel.critical:
        return LucideIcons.alertOctagon;
      default:
        return LucideIcons.cloud;
    }
  }

  String _getTitle() {
    switch (alertLevel) {
      case AlertLevel.warning:
        return 'Weather Warning';
      case AlertLevel.critical:
        return 'Weather Critical';
      default:
        return 'Weather Alert';
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _getBackgroundColor();
    final icon = _getIcon();
    final title = _getTitle();
    final message = actions.reason ?? 'Adverse weather conditions detected';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              backgroundColor,
              backgroundColor.withOpacity(0.85),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsing icon for critical alerts
            if (alertLevel == AlertLevel.critical)
              _PulsingIcon(icon: icon)
            else
              Icon(
                icon,
                size: 20,
                color: Colors.white,
              ),

            const SizedBox(width: 12),

            // Title and message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Snooze button
            _SnoozeButton(
              onPressed: onSnooze,
            ),

            const SizedBox(width: 8),

            // Navigate arrow
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: Colors.white.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing icon for critical alerts
class _PulsingIcon extends StatefulWidget {
  final IconData icon;

  const _PulsingIcon({required this.icon});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Icon(
            widget.icon,
            size: 20,
            color: Colors.white.withOpacity(_animation.value),
          ),
        );
      },
    );
  }
}

/// Snooze button
class _SnoozeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SnoozeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.bellOff,
                size: 12,
                color: Colors.white.withOpacity(0.9),
              ),
              const SizedBox(width: 4),
              Text(
                'Snooze',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
