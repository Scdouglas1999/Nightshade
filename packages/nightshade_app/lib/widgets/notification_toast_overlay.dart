import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Overlay widget that displays toast notifications from [uiNotificationProvider].
///
/// Features:
/// - Positioned at bottom-right on desktop, bottom-center on mobile
/// - Auto-dismiss with configurable duration
/// - Stacking (max 3 visible at a time)
/// - Click to dismiss
/// - Color-coded by severity (info=blue, success=green, warning=amber, error=red)
/// - Animated entrance/exit
class NotificationToastOverlay extends ConsumerStatefulWidget {
  const NotificationToastOverlay({super.key});

  @override
  ConsumerState<NotificationToastOverlay> createState() =>
      _NotificationToastOverlayState();
}

class _NotificationToastOverlayState
    extends ConsumerState<NotificationToastOverlay> {
  final Map<String, Timer> _dismissTimers = {};
  final Set<String> _dismissingIds = {};

  static const int _maxVisibleToasts = 3;

  @override
  void dispose() {
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _scheduleDismiss(UiNotification notification) {
    if (_dismissTimers.containsKey(notification.id)) return;

    final duration = notification.duration ?? const Duration(seconds: 4);
    _dismissTimers[notification.id] = Timer(duration, () {
      _dismiss(notification.id);
    });
  }

  void _dismiss(String id) {
    if (_dismissingIds.contains(id)) return;

    setState(() {
      _dismissingIds.add(id);
    });

    // Allow exit animation to complete before removing
    Future.delayed(const Duration(milliseconds: 300), () {
      _dismissTimers[id]?.cancel();
      _dismissTimers.remove(id);
      ref.read(uiNotificationProvider.notifier).dismiss(id);
      if (mounted) {
        setState(() {
          _dismissingIds.remove(id);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(uiNotificationProvider);

    // Take only the most recent notifications up to max
    final visibleNotifications = notifications.length > _maxVisibleToasts
        ? notifications.sublist(notifications.length - _maxVisibleToasts)
        : notifications;

    // Schedule dismiss timers for new notifications
    for (final notification in visibleNotifications) {
      if (!_dismissTimers.containsKey(notification.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleDismiss(notification);
        });
      }
    }

    if (visibleNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 56, // Above status bar
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visibleNotifications.map((notification) {
          return _NotificationToast(
            key: ValueKey(notification.id),
            notification: notification,
            isDismissing: _dismissingIds.contains(notification.id),
            onDismiss: () => _dismiss(notification.id),
          );
        }).toList(),
      ),
    );
  }
}

class _NotificationToast extends StatefulWidget {
  final UiNotification notification;
  final bool isDismissing;
  final VoidCallback onDismiss;

  const _NotificationToast({
    super.key,
    required this.notification,
    required this.isDismissing,
    required this.onDismiss,
  });

  @override
  State<_NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _NotificationToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDismissing && !oldWidget.isDismissing) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getIcon() {
    switch (widget.notification.level) {
      case UiNotificationLevel.info:
        return LucideIcons.info;
      case UiNotificationLevel.success:
        return LucideIcons.checkCircle;
      case UiNotificationLevel.warning:
        return LucideIcons.alertTriangle;
      case UiNotificationLevel.error:
        return LucideIcons.xCircle;
    }
  }

  Color _getColor(NightshadeColors colors) {
    switch (widget.notification.level) {
      case UiNotificationLevel.info:
        return colors.info;
      case UiNotificationLevel.success:
        return colors.success;
      case UiNotificationLevel.warning:
        return colors.warning;
      case UiNotificationLevel.error:
        return colors.error;
    }
  }

  Color _getBackgroundColor(NightshadeColors colors) {
    final baseColor = _getColor(colors);
    return Color.lerp(colors.surface, baseColor, 0.15)!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final accentColor = _getColor(colors);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_slideAnimation.value, 0),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onDismiss,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 360,
                minWidth: 280,
              ),
              decoration: BoxDecoration(
                color: _getBackgroundColor(colors),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Accent bar
                    Container(
                      width: 4,
                      constraints: const BoxConstraints(minHeight: 48),
                      color: accentColor,
                    ),
                    // Content
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getIcon(),
                              color: accentColor,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.notification.title != null) ...[
                                    Text(
                                      widget.notification.title!,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  Text(
                                    widget.notification.message,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 11,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Dismiss button
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: widget.onDismiss,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    LucideIcons.x,
                                    color: colors.textMuted,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
