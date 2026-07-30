import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/slew_dropdown_button.dart';
import '../../../widgets/tutorial_keys/planetarium_keys.dart';
import '../planetarium_screen.dart';

// NOTE (design tokens): the `Colors.white*` text/icons and `Colors.black*`
// scrim/shadow in this floating object popup are canvas-absolute HUD colors
// drawn over the planetarium sky. The planetarium is wrapped in
// `_NightVisionFilter` (luminance→red conversion for dark adaptation), so these
// are intentionally NOT mapped to the theme-relative semantic palette. Themed
// chrome (icon tint, magnitude chip) already uses `widget.colors.*`.
import 'observation_log_dialog.dart';

part 'object_info_popup/supporting_widgets.dart';

/// Resolved size and position for [ObjectInfoPopup] at a global [anchor].
class ObjectInfoPopupLayout {
  final double width;
  final double height;
  final double left;
  final double top;
  final bool showAbove;

  const ObjectInfoPopupLayout({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.showAbove,
  });

  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

ObjectInfoPopupLayout resolveObjectInfoPopupLayout(
  BuildContext context,
  Offset anchor,
) {
  final screenSize = MediaQuery.sizeOf(context);
  const padding = 16.0;
  // 340 rather than 300: the action stack has to fit 'Log Observation',
  // 'Target Queue' and 'Sequence' without ellipsizing them, and a truncated
  // control label ('Sequ...') is not a legible control.
  final popupWidth = Responsive.previewOverlayMaxWidth(
    screenSize.width,
    maxAbsolute: 340,
  ).clamp(260.0, 340.0);
  final popupHeight =
      math.min(460.0, screenSize.height * 0.6).clamp(300.0, 460.0);

  var left = anchor.dx - popupWidth / 2;
  var top = anchor.dy + 20;

  // Both popup extents carry their own floor (240 wide, 280 tall), so a
  // viewport smaller than that floor plus two margins would invert these
  // bounds and throw. Pin to the near margin and let the far edge clip.
  final maxLeft = math.max(padding, screenSize.width - popupWidth - padding);
  final maxTop = math.max(padding, screenSize.height - popupHeight - padding);

  left = left.clamp(padding, maxLeft);

  if (top + popupHeight > screenSize.height - padding) {
    top = anchor.dy - popupHeight - 20;
  }
  top = top.clamp(padding, maxTop);

  return ObjectInfoPopupLayout(
    width: popupWidth,
    height: popupHeight,
    left: left,
    top: top,
    showAbove: top < anchor.dy,
  );
}

class ObjectInfoPopup extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final CelestialObject object;
  final CelestialCoordinate coordinates;
  final Offset position;
  final VoidCallback onDismiss;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToSequencer;

  /// Queue this object in the shared target queue (the sequencer Builder's
  /// Target Queue panel renders the same provider).
  final VoidCallback onAddToQueue;
  final VoidCallback onSlewToTarget;
  final VoidCallback onSlewAndCenter;
  final VoidCallback onSlewCenterRotate;
  final VoidCallback? onExportChart;
  final bool hasRotator;

  const ObjectInfoPopup({
    super.key,
    required this.colors,
    required this.object,
    required this.coordinates,
    required this.position,
    required this.onDismiss,
    required this.onSendToFraming,
    required this.onAddToSequencer,
    required this.onAddToQueue,
    required this.onSlewToTarget,
    required this.onSlewAndCenter,
    required this.onSlewCenterRotate,
    this.onExportChart,
    required this.hasRotator,
  });

  @override
  ConsumerState<ObjectInfoPopup> createState() => _ObjectInfoPopupState();
}

class _ObjectInfoPopupState extends ConsumerState<ObjectInfoPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  void _consumeTap() {
    // Popup body absorbs taps so sky-map clicks do not pass through.
  }
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = resolveObjectInfoPopupLayout(context, widget.position);

    return Positioned(
      left: layout.left,
      top: layout.top,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              alignment: layout.showAbove
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _consumeTap,
            child: Container(
              key: PlanetariumTutorialKeys.objectPopup,
              width: layout.width,
              constraints: BoxConstraints(maxHeight: layout.height),
              decoration: BoxDecoration(
                color: widget.colors.surfaceOverlay.withValues(alpha: 0.95),
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(
                  color: widget.colors.border,
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
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      _buildHeader(),

                      // Divider
                      Container(
                        height: 1,
                        color: widget.colors.border.withValues(alpha: 0.5),
                      ),

                      // Content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildObjectDetails(),
                              const SizedBox(height: 16),
                              _buildCoordinates(),
                              if (ref.watch(selectedObjectAltAzProvider) !=
                                  null) ...[
                                const SizedBox(height: 12),
                                _buildAltAz(),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Divider
                      Container(
                        height: 1,
                        color: widget.colors.border.withValues(alpha: 0.5),
                      ),

                      // Action buttons
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final obj = widget.object;
    IconData icon;
    Color iconColor;

    if (obj is Star) {
      icon = NightshadeIcons.star;
      iconColor = widget.colors.warning;
    } else if (obj is DeepSkyObject) {
      final dso = obj;
      if (dso.type.isGalaxy) {
        icon = NightshadeIcons.circle;
        iconColor = widget.colors.info;
      } else if (dso.type.isNebula) {
        icon = NightshadeIcons.cloud;
        iconColor = widget.colors.error;
      } else if (dso.type.isCluster) {
        icon = NightshadeIcons.sparkle;
        iconColor = widget.colors.warning;
      } else {
        icon = NightshadeIcons.target;
        iconColor = widget.colors.primary;
      }
    } else {
      icon = NightshadeIcons.target;
      iconColor = widget.colors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obj is DeepSkyObject ? getDsoDisplayInfo(obj).$1 : obj.name,
                  style: const TextStyle(
                    fontSize: NightshadeTypography.fontSize16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.colors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline4),
                      ),
                      child: Text(
                        obj is DeepSkyObject
                            ? getDsoDisplayInfo(obj).$2
                            : obj.id,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.primary,
                        ),
                      ),
                    ),
                    if (obj.magnitude != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'mag ${obj.magnitude!.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Export chart button
          if (widget.onExportChart != null) ...[
            GestureDetector(
              onTap: widget.onExportChart,
              child: Tooltip(
                message: 'Export finder chart',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
                  ),
                  child: const Icon(LucideIcons.fileDown,
                      size: 14, color: Colors.white60),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Close button
          GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
              child: const Icon(NightshadeIcons.close,
                  size: 14, color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectDetails() {
    final obj = widget.object;
    String typeLabel = 'Object';

    if (obj is Star) {
      typeLabel = 'Star';
      if (obj.spectralType != null) {
        typeLabel = 'Star (${obj.spectralType})';
      }
    } else if (obj is DeepSkyObject) {
      typeLabel = obj.type.displayName;
    }

    return Row(
      children: [
        PopupInfoChip(
          label: 'Type',
          value: typeLabel,
          colors: widget.colors,
        ),
        const SizedBox(width: 8),
        if (obj is DeepSkyObject && obj.sizeString != null)
          PopupInfoChip(
            label: 'Size',
            value: obj.sizeString!,
            colors: widget.colors,
          ),
      ],
    );
  }

  Widget _buildCoordinates() {
    final coords = widget.coordinates;

    // Format RA
    final raH = coords.ra.floor();
    final raM = ((coords.ra - raH) * 60).floor();
    final raS = (((coords.ra - raH) * 60 - raM) * 60).toStringAsFixed(1);
    final raStr = '${raH}h ${raM}m ${raS}s';

    // Format Dec
    final sign = coords.dec >= 0 ? '+' : '-';
    final decD = coords.dec.abs().floor();
    final decM = ((coords.dec.abs() - decD) * 60).floor();
    final decS =
        (((coords.dec.abs() - decD) * 60 - decM) * 60).toStringAsFixed(0);
    final decStr = "$sign$decD\u00b0 $decM' $decS\"";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinates',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: PopupCoordRow(
                label: 'RA',
                value: raStr,
                colors: widget.colors,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PopupCoordRow(
                label: 'Dec',
                value: decStr,
                colors: widget.colors,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAltAz() {
    final altAz = ref.watch(selectedObjectAltAzProvider)!;
    final alt = altAz.$1;
    final az = altAz.$2;

    // The badge used to grade on altitude alone, so at 11:52 local — with the
    // app's own dashboard reading "Dark in 10h 36m" — a target 63 deg up got a
    // green "Excellent" pill while the Sun was also 63 deg up. Sky brightness
    // outranks altitude: an unobservable target must not be badged green.
    final grade = gradeObservability(
      altitudeDeg: alt,
      sunAltitudeDeg: ref.watch(sunAltitudeProvider),
    );
    final statusText = grade.label;
    final altColor = switch (grade) {
      ObservabilityGrade.excellent => widget.colors.success,
      ObservabilityGrade.good ||
      ObservabilityGrade.low ||
      ObservabilityGrade.twilight =>
        widget.colors.warning,
      ObservabilityGrade.belowHorizon ||
      ObservabilityGrade.daylight =>
        widget.colors.error,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Position',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: altColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                border: Border.all(color: altColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    alt > 0
                        ? NightshadeIcons.arrowUp
                        : NightshadeIcons.arrowDown,
                    size: 12,
                    color: altColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${alt.toStringAsFixed(1)}\u00b0',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      fontWeight: FontWeight.w600,
                      color: altColor,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Az ${az.toStringAsFixed(1)}\u00b0',
              style: const TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: Colors.white60,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: altColor.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w500,
                  color: altColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddToListDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _AddToListDialog(
        object: widget.object,
        coordinates: widget.coordinates,
      ),
    );
  }

  Widget _buildActions() {
    // At most two actions per row. Three-up crammed 'Framing' and 'Sequence'
    // into ~87 px each inside a 300 px popup, which rendered them as 'Frami…'
    // and 'Sequ…' — and 'Sequ…' at 2am is genuinely ambiguous. Slew keeps its
    // own row because it carries a dropdown caret as well as a label.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SlewPopupMenuButton(
            colors: widget.colors,
            onSlew: widget.onSlewToTarget,
            onSlewAndCenter: widget.onSlewAndCenter,
            onSlewCenterRotate: widget.onSlewCenterRotate,
            showRotateOption: widget.hasRotator,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PopupActionButton(
                  key: PlanetariumTutorialKeys.sendFraming,
                  icon: NightshadeIcons.frame,
                  label: 'Framing',
                  colors: widget.colors,
                  onTap: widget.onSendToFraming,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupActionButton(
                  key: PlanetariumTutorialKeys.addSequence,
                  icon: LucideIcons.listPlus,
                  label: 'Sequence',
                  colors: widget.colors,
                  isPrimary: true,
                  onTap: widget.onAddToSequencer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 'Log Observation' is the longest label in the popup, so it takes a
          // full row rather than half of one.
          PopupActionButton(
            icon: NightshadeIcons.book,
            label: 'Log Observation',
            colors: widget.colors,
            onTap: () async {
              final saved = await showDialog<bool>(
                context: context,
                builder: (context) => ObservationLogDialog(
                  object: widget.object,
                  coordinates: widget.coordinates,
                  altAz: ref.read(selectedObjectAltAzProvider),
                ),
              );
              if (saved == true && mounted) {
                context.showSuccessSnackBar('Logged ${widget.object.name}');
              }
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PopupActionButton(
                  icon: LucideIcons.listPlus,
                  label: 'Add to List',
                  colors: widget.colors,
                  onTap: () {
                    _showAddToListDialog(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupActionButton(
                  key: const ValueKey('popup_add_to_target_queue'),
                  icon: LucideIcons.listChecks,
                  label: 'Target Queue',
                  colors: widget.colors,
                  onTap: widget.onAddToQueue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
