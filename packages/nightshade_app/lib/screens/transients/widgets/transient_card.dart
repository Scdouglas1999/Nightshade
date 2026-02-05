import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Card widget displaying a transient alert with its details and actions.
///
/// Shows:
/// - Type icon and alert name
/// - Coordinates (RA/Dec)
/// - Magnitude and brightness indicator
/// - Discovery info (source, time)
/// - State badge (New, Queued, Observed, Dismissed)
/// - Action buttons (Queue, View in Framing, Dismiss)
class TransientCard extends StatefulWidget {
  final TransientAlert alert;
  final TransientAlertState? state;
  final VoidCallback onQueue;
  final VoidCallback onViewInFraming;
  final VoidCallback onDismiss;

  const TransientCard({
    super.key,
    required this.alert,
    required this.state,
    required this.onQueue,
    required this.onViewInFraming,
    required this.onDismiss,
  });

  @override
  State<TransientCard> createState() => _TransientCardState();
}

class _TransientCardState extends State<TransientCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final effectiveState = widget.state ?? TransientAlertState.newAlert;

    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: NightshadeTokens.durationNormal,
        curve: NightshadeTokens.curveStandard,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(
            color: _getBorderColor(colors, effectiveState),
            width: effectiveState == TransientAlertState.newAlert ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main card content
            Padding(
              padding: NightshadeTokens.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  _buildHeader(colors, effectiveState),

                  const SizedBox(height: NightshadeTokens.spaceMd),

                  // Coordinates and magnitude
                  _buildInfoRow(colors),

                  // Expanded details
                  if (_isExpanded) ...[
                    const SizedBox(height: NightshadeTokens.spaceMd),
                    _buildExpandedDetails(colors),
                  ],

                  const SizedBox(height: NightshadeTokens.spaceMd),

                  // Actions row
                  _buildActionsRow(colors, effectiveState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors, TransientAlertState effectiveState) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type icon
        Container(
          padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
          decoration: BoxDecoration(
            color: _getTypeColor(colors).withValues(alpha: 0.1),
            borderRadius: NightshadeTokens.borderRadiusMd,
          ),
          child: Icon(
            _getTypeIcon(),
            size: NightshadeTokens.iconMd,
            color: _getTypeColor(colors),
          ),
        ),

        const SizedBox(width: NightshadeTokens.spaceMd),

        // Name and type
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.alert.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Row(
                children: [
                  Text(
                    _getTypeLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (widget.alert.classification != null) ...[
                    Text(
                      ' - ${widget.alert.classification}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // State badge
        _StateBadge(state: effectiveState, colors: colors),
      ],
    );
  }

  Widget _buildInfoRow(NightshadeColors colors) {
    return Row(
      children: [
        // Coordinates
        Expanded(
          child: Row(
            children: [
              Icon(
                LucideIcons.crosshair,
                size: NightshadeTokens.iconXs,
                color: colors.textMuted,
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Flexible(
                child: Text(
                  '${_formatRA(widget.alert.raHours)}  ${_formatDec(widget.alert.decDegrees)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Magnitude
        if (widget.alert.magnitude != null) ...[
          const SizedBox(width: NightshadeTokens.spaceMd),
          _MagnitudeIndicator(
            magnitude: widget.alert.magnitude!,
            colors: colors,
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedDetails(NightshadeColors colors) {
    return Container(
      padding: NightshadeTokens.paddingMd,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discovery info
          _DetailRow(
            icon: LucideIcons.search,
            label: 'Source',
            value: _getSourceLabel(widget.alert.source),
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _DetailRow(
            icon: LucideIcons.clock,
            label: 'Discovered',
            value: _formatDateTime(widget.alert.discoveryTime),
            colors: colors,
          ),
          if (widget.alert.peakMagnitude != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            _DetailRow(
              icon: LucideIcons.trendingUp,
              label: 'Peak Magnitude',
              value: 'mag ${widget.alert.peakMagnitude!.toStringAsFixed(1)}',
              colors: colors,
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceSm),
          _DetailRow(
            icon: LucideIcons.refreshCw,
            label: 'Last Updated',
            value: _formatDateTime(widget.alert.lastUpdated),
            colors: colors,
          ),
          if (widget.alert.notes != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            _DetailRow(
              icon: LucideIcons.fileText,
              label: 'Notes',
              value: widget.alert.notes!,
              colors: colors,
              isMultiLine: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsRow(NightshadeColors colors, TransientAlertState effectiveState) {
    final isQueued = effectiveState == TransientAlertState.queued;
    final isDismissed = effectiveState == TransientAlertState.dismissed;
    final isObserved = effectiveState == TransientAlertState.observed;

    return Row(
      children: [
        // Queue button
        if (!isQueued && !isObserved)
          Expanded(
            child: NightshadeButton(
              label: 'Queue',
              icon: LucideIcons.plus,
              size: ButtonSize.small,
              variant: ButtonVariant.primary,
              onPressed: widget.onQueue,
            ),
          )
        else if (isQueued)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NightshadeTokens.spaceMd,
                vertical: NightshadeTokens.spaceSm,
              ),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.1),
                borderRadius: NightshadeTokens.borderRadiusSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.clock,
                    size: NightshadeTokens.iconSm,
                    color: colors.warning,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Text(
                    'Queued',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.warning,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (isObserved)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NightshadeTokens.spaceMd,
                vertical: NightshadeTokens.spaceSm,
              ),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.1),
                borderRadius: NightshadeTokens.borderRadiusSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.check,
                    size: NightshadeTokens.iconSm,
                    color: colors.success,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Text(
                    'Observed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.success,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(width: NightshadeTokens.spaceSm),

        // View in Framing button
        Expanded(
          child: NightshadeButton(
            label: 'Framing',
            icon: LucideIcons.frame,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: widget.onViewInFraming,
          ),
        ),

        const SizedBox(width: NightshadeTokens.spaceSm),

        // Dismiss button
        if (!isDismissed && !isObserved)
          IconButton(
            icon: Icon(
              LucideIcons.x,
              size: NightshadeTokens.iconMd,
              color: colors.textMuted,
            ),
            onPressed: widget.onDismiss,
            tooltip: 'Dismiss',
            style: IconButton.styleFrom(
              backgroundColor: colors.surfaceAlt,
              shape: RoundedRectangleBorder(
                borderRadius: NightshadeTokens.borderRadiusSm,
              ),
            ),
          ),
      ],
    );
  }

  Color _getBorderColor(NightshadeColors colors, TransientAlertState state) {
    switch (state) {
      case TransientAlertState.newAlert:
        return colors.info;
      case TransientAlertState.queued:
        return colors.warning;
      case TransientAlertState.observed:
        return colors.success;
      case TransientAlertState.acknowledged:
      case TransientAlertState.dismissed:
        return colors.border;
    }
  }

  IconData _getTypeIcon() {
    switch (widget.alert.type) {
      case TransientType.nova:
        return LucideIcons.star;
      case TransientType.supernova:
        return LucideIcons.sparkles;
      case TransientType.comet:
        return LucideIcons.orbit;
      case TransientType.cataclysmic:
        return LucideIcons.zap;
      case TransientType.asteroid:
        return LucideIcons.circle;
      case TransientType.variableStar:
        return LucideIcons.activity;
      case TransientType.gammaRayBurst:
        return LucideIcons.flame;
      case TransientType.other:
        return LucideIcons.helpCircle;
    }
  }

  Color _getTypeColor(NightshadeColors colors) {
    switch (widget.alert.type) {
      case TransientType.nova:
        return colors.warning;
      case TransientType.supernova:
        return colors.error;
      case TransientType.comet:
        return colors.info;
      case TransientType.cataclysmic:
        return colors.accent;
      case TransientType.asteroid:
        return colors.textSecondary;
      case TransientType.variableStar:
        return colors.success;
      case TransientType.gammaRayBurst:
        return colors.error;
      case TransientType.other:
        return colors.textMuted;
    }
  }

  String _getTypeLabel() {
    switch (widget.alert.type) {
      case TransientType.nova:
        return 'Nova';
      case TransientType.supernova:
        return 'Supernova';
      case TransientType.comet:
        return 'Comet';
      case TransientType.cataclysmic:
        return 'Cataclysmic Variable';
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

  String _getSourceLabel(TransientSource source) {
    switch (source) {
      case TransientSource.aavso:
        return 'AAVSO';
      case TransientSource.tns:
        return 'Transient Name Server';
      case TransientSource.mpec:
        return 'Minor Planet Electronic Circulars';
      case TransientSource.cbat:
        return 'Central Bureau for Astronomical Telegrams';
      case TransientSource.manual:
        return 'Manual Entry';
    }
  }

  /// Format RA in hours to "XXh XXm XXs" format.
  String _formatRA(double raHours) {
    final totalSeconds = raHours * 3600;
    final hours = (totalSeconds / 3600).floor();
    final minutes = ((totalSeconds % 3600) / 60).floor();
    final seconds = (totalSeconds % 60).floor();
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  /// Format Dec in degrees to "+/-XX deg XX' XX''" format.
  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final minutesDecimal = (absDec - degrees) * 60;
    final minutes = minutesDecimal.floor();
    final seconds = ((minutesDecimal - minutes) * 60).floor();
    return "$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}' ${seconds.toString().padLeft(2, '0')}\"";
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 7) {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

/// Badge showing the current state of the alert.
class _StateBadge extends StatelessWidget {
  final TransientAlertState state;
  final NightshadeColors colors;

  const _StateBadge({
    required this.state,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = _getStateInfo();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: NightshadeTokens.borderRadiusFull,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  (String, Color) _getStateInfo() {
    switch (state) {
      case TransientAlertState.newAlert:
        return ('New', colors.info);
      case TransientAlertState.acknowledged:
        return ('Seen', colors.textSecondary);
      case TransientAlertState.queued:
        return ('Queued', colors.warning);
      case TransientAlertState.observed:
        return ('Observed', colors.success);
      case TransientAlertState.dismissed:
        return ('Dismissed', colors.textMuted);
    }
  }
}

/// Magnitude indicator with brightness color coding.
class _MagnitudeIndicator extends StatelessWidget {
  final double magnitude;
  final NightshadeColors colors;

  const _MagnitudeIndicator({
    required this.magnitude,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = _getBrightnessInfo();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.sun,
            size: NightshadeTokens.iconXs,
            color: color,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            'mag ${magnitude.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceXs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: NightshadeTokens.borderRadiusXs,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _getBrightnessInfo() {
    if (magnitude <= 6.0) {
      return ('NAKED EYE', colors.success);
    } else if (magnitude <= 10.0) {
      return ('BINOCULAR', colors.info);
    } else if (magnitude <= 14.0) {
      return ('SMALL SCOPE', colors.warning);
    } else {
      return ('FAINT', colors.textMuted);
    }
  }
}

/// Row for displaying a detail item in the expanded view.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isMultiLine;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.isMultiLine = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isMultiLine) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: NightshadeTokens.iconXs, color: colors.textMuted),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Padding(
            padding: const EdgeInsets.only(left: NightshadeTokens.spaceLg),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(icon, size: NightshadeTokens.iconXs, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
