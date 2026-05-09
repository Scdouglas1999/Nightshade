import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A badge widget that displays the count of unacknowledged transient alerts.
///
/// Features:
/// - Bell icon with count badge overlay
/// - Pulsing animation when new alerts arrive
/// - Optional dropdown showing alert summary
/// - Handles loading/error/empty states
class TransientAlertBadge extends ConsumerStatefulWidget {
  /// Callback when the badge is tapped (if [showDropdown] is false)
  final VoidCallback? onTap;

  /// Whether to show a dropdown menu on tap instead of calling [onTap]
  final bool showDropdown;

  const TransientAlertBadge({
    super.key,
    this.onTap,
    this.showDropdown = false,
  });

  @override
  ConsumerState<TransientAlertBadge> createState() =>
      _TransientAlertBadgeState();
}

class _TransientAlertBadgeState extends ConsumerState<TransientAlertBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCountChange(int newCount) {
    if (newCount > _previousCount && newCount > 0) {
      // New alerts arrived - trigger pulse animation
      _pulseController.repeat(
        reverse: false,
        period: const Duration(milliseconds: 1200),
      );

      // Stop after 3 pulses (3.6 seconds)
      Future.delayed(const Duration(milliseconds: 3600), () {
        if (mounted) {
          _pulseController.stop();
          _pulseController.reset();
        }
      });
    }
    _previousCount = newCount;
  }

  void _showDropdownMenu(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        0,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TransientAlertDropdownContent(
            onViewAll: () {
              Navigator.of(context).pop();
              widget.onTap?.call();
            },
          ),
        ),
      ],
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final unacknowledgedCount = ref.watch(unacknowledgedAlertCountProvider);

    // Trigger pulse animation when count increases
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleCountChange(unacknowledgedCount);
    });

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (widget.showDropdown) {
            _showDropdownMenu(context);
          } else {
            widget.onTap?.call();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Base icon
              alertsAsync.when(
                data: (_) => Icon(
                  LucideIcons.bell,
                  size: 20,
                  color: colors.textSecondary,
                ),
                loading: () => _LoadingIcon(colors: colors),
                error: (_, __) => _ErrorIcon(colors: colors),
              ),

              // Badge overlay
              if (unacknowledgedCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      );
                    },
                    child: _CountBadge(
                      count: unacknowledgedCount,
                      colors: colors,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading state icon with subtle animation
class _LoadingIcon extends StatelessWidget {
  final NightshadeColors colors;

  const _LoadingIcon({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Icon(
          LucideIcons.bell,
          size: 20,
          color: colors.textMuted,
        ),
        Positioned(
          right: 0,
          top: 0,
          child: SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Error state icon with orange indicator
class _ErrorIcon extends StatelessWidget {
  final NightshadeColors colors;

  const _ErrorIcon({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Icon(
          LucideIcons.bell,
          size: 20,
          color: colors.textSecondary,
        ),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.warning,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.surface,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Count badge showing the number of unacknowledged alerts
class _CountBadge extends StatelessWidget {
  final int count;
  final NightshadeColors colors;

  const _CountBadge({
    required this.count,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = count > 9 ? '9+' : count.toString();
    final onError = Theme.of(context).colorScheme.onError;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.surface,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.error.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            color: onError,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Dropdown content showing alert summary
class _TransientAlertDropdownContent extends ConsumerWidget {
  final VoidCallback onViewAll;

  const _TransientAlertDropdownContent({
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final states = ref.watch(transientAlertStatesProvider);

    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.radio,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transient Alerts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),

          // Alert list
          alertsAsync.when(
            data: (alerts) => _buildAlertList(context, alerts, states, colors),
            loading: () => _buildLoadingState(colors),
            error: (error, _) => _buildErrorState(error, colors),
          ),

          // Footer
          Divider(height: 1, color: colors.border),
          InkWell(
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View all alerts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.arrowRight,
                    size: 14,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertList(
    BuildContext context,
    List<TransientAlert> alerts,
    Map<String, TransientAlertState> states,
    NightshadeColors colors,
  ) {
    if (alerts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              LucideIcons.bellOff,
              size: 32,
              color: colors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              'No active alerts',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Show first 5 alerts
    final displayedAlerts = alerts.take(5).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: displayedAlerts.map((alert) {
        final alertState = states[alert.id];
        final isNew =
            alertState == null || alertState == TransientAlertState.newAlert;

        return _AlertListItem(
          alert: alert,
          isNew: isNew,
          colors: colors,
        );
      }).toList(),
    );
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading alerts...',
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(
            LucideIcons.alertTriangle,
            size: 24,
            color: colors.warning,
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to load alerts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Individual alert item in the dropdown list
class _AlertListItem extends StatelessWidget {
  final TransientAlert alert;
  final bool isNew;
  final NightshadeColors colors;

  const _AlertListItem({
    required this.alert,
    required this.isNew,
    required this.colors,
  });

  IconData _getTypeIcon() {
    switch (alert.type) {
      case TransientType.nova:
        return LucideIcons.star;
      case TransientType.supernova:
        return LucideIcons.sparkles;
      case TransientType.cataclysmic:
        return LucideIcons.zap;
      case TransientType.comet:
        return LucideIcons.orbit;
      case TransientType.asteroid:
        return LucideIcons.circle;
      case TransientType.variableStar:
        return LucideIcons.sunDim;
      case TransientType.gammaRayBurst:
        return LucideIcons.flame;
      case TransientType.other:
        return LucideIcons.helpCircle;
    }
  }

  Color _getTypeColor() {
    switch (alert.type) {
      case TransientType.nova:
      case TransientType.supernova:
        return colors.error;
      case TransientType.cataclysmic:
      case TransientType.gammaRayBurst:
        return colors.warning;
      case TransientType.comet:
      case TransientType.asteroid:
        return colors.info;
      case TransientType.variableStar:
        return colors.accent;
      case TransientType.other:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color:
            isNew ? colors.primary.withValues(alpha: 0.05) : Colors.transparent,
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _getTypeColor().withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Icon(
                _getTypeIcon(),
                size: 14,
                color: _getTypeColor(),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name and type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTypeName(alert.type),
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // Magnitude
          if (alert.magnitude != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'mag ${alert.magnitude!.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],

          // New badge
          if (isNew) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'NEW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: onPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTypeName(TransientType type) {
    switch (type) {
      case TransientType.nova:
        return 'Nova';
      case TransientType.supernova:
        return 'Supernova';
      case TransientType.cataclysmic:
        return 'Cataclysmic Variable';
      case TransientType.comet:
        return 'Comet';
      case TransientType.asteroid:
        return 'Asteroid';
      case TransientType.variableStar:
        return 'Variable Star';
      case TransientType.gammaRayBurst:
        return 'Gamma-Ray Burst';
      case TransientType.other:
        return 'Other';
    }
  }
}
