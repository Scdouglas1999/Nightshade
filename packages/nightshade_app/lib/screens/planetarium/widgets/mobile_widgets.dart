import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:intl/intl.dart';
import '../../../utils/coordinate_format_utils.dart';
import '../../../widgets/tutorial_keys/planetarium_keys.dart';
import '../planetarium_screen.dart';
import '../providers/device_orientation_provider.dart';

/// Compact top overlay for mobile screens
/// Adapts layout for very narrow screens (below 360px)
class MobileTopOverlay extends ConsumerWidget {
  final NightshadeColors colors;

  const MobileTopOverlay({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = ref.watch(observationTimeProvider);
    final lst = ref.watch(localSiderealTimeProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isVeryNarrow = screenWidth < 360;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Time chip (compact)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  DateFormat('HH:mm').format(time.time),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Only show LST on screens wide enough
            if (!isVeryNarrow) ...[
              const SizedBox(width: 8),
              // LST chip
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'LST ${_formatHours(lst)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const Spacer(),
            // Quick toggle buttons
            MobileToggleButton(
              icon: LucideIcons.grid,
              isActive: ref.watch(skyRenderConfigProvider).showCoordinateGrid,
              onTap: ref.read(skyRenderConfigProvider.notifier).toggleGrid,
            ),
            MobileToggleButton(
              icon: LucideIcons.activity,
              isActive:
                  ref.watch(skyRenderConfigProvider).showConstellationLines,
              onTap: ref
                  .read(skyRenderConfigProvider.notifier)
                  .toggleConstellationLines,
            ),
          ],
        ),
      ),
    );
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

/// Compact toggle button for mobile top bar
/// Minimum 44px touch target per accessibility guidelines
class MobileToggleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const MobileToggleButton({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44, // Minimum touch target
        height: 44, // Minimum touch target
        alignment: Alignment.center,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Compact view controls for mobile
class MobileViewControls extends ConsumerWidget {
  final NightshadeColors colors;
  final bool showFOV;
  final VoidCallback onToggleFOV;

  const MobileViewControls({
    super.key,
    required this.colors,
    required this.showFOV,
    required this.onToggleFOV,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(skyViewStateProvider);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MobileControlButton(
            icon: LucideIcons.plus,
            onTap: ref.read(skyViewStateProvider.notifier).zoomIn,
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              viewState.fieldOfView.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white70,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          MobileControlButton(
            icon: LucideIcons.minus,
            onTap: ref.read(skyViewStateProvider.notifier).zoomOut,
          ),
          Container(
            height: 1,
            width: 20,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.white24,
          ),
          MobileControlButton(
            icon: LucideIcons.home,
            onTap: () {
              ref.read(skyViewStateProvider.notifier).setCenter(0, 0);
              ref.read(skyViewStateProvider.notifier).setFieldOfView(60);
            },
          ),
          const SizedBox(height: 4),
          MobileControlButton(
            key: PlanetariumTutorialKeys.fovToggle,
            icon: LucideIcons.frame,
            isActive: showFOV,
            onTap: onToggleFOV,
          ),
          // Gyroscope aim button - only on mobile platforms
          if (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android) ...[
            Container(
              height: 1,
              width: 20,
              margin: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.white24,
            ),
            Consumer(
              builder: (context, ref, _) {
                final isEnabled = ref.watch(gyroscopeAimingEnabledProvider);
                final orientation = ref.watch(deviceOrientationProvider);
                final mountSyncActive = ref.watch(gyroscopeMountSyncProvider);
                final mountConnected =
                    ref.watch(mountStateProvider).connectionState ==
                        DeviceConnectionState.connected;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gyroscope aim toggle
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _handleGyroscopeToggle(context, ref),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: isEnabled
                                ? const Color(0xFF2196F3).withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: isEnabled
                                ? Border.all(
                                    color: const Color(0xFF2196F3), width: 1)
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                LucideIcons.compass,
                                size: 14,
                                color: isEnabled
                                    ? const Color(0xFF2196F3)
                                    : Colors.white70,
                              ),
                              // Compass accuracy indicator dot
                              if (isEnabled && orientation.isActive)
                                Positioned(
                                  bottom: 1,
                                  right: 1,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _accuracyColor(
                                          orientation.compassAccuracy),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Sync Mount toggle - only visible when gyroscope is active
                    // and a mount is connected via NetworkBackend
                    if (isEnabled && mountConnected) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          ref.read(gyroscopeMountSyncProvider.notifier).state =
                              !mountSyncActive;
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: mountSyncActive
                                  ? const Color(0xFFFF9800)
                                      .withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: mountSyncActive
                                  ? Border.all(
                                      color: const Color(0xFFFF9800), width: 1)
                                  : null,
                            ),
                            child: Icon(
                              LucideIcons.star,
                              size: 14,
                              color: mountSyncActive
                                  ? const Color(0xFFFF9800)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _handleGyroscopeToggle(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.read(gyroscopeAimingEnabledProvider);

    if (!isEnabled) {
      // Turning on: check if calibration has been acknowledged this session
      final calibrated = ref.read(compassCalibrationAcknowledgedProvider);
      if (!calibrated) {
        _showCalibrationDialog(context, ref);
        return;
      }
    } else {
      // Turning off: also disable mount sync
      ref.read(gyroscopeMountSyncProvider.notifier).state = false;
    }

    ref.read(gyroscopeAimingEnabledProvider.notifier).state = !isEnabled;
  }

  void _showCalibrationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const CompassCalibrationDialog(),
    ).then((result) {
      if (result == true) {
        ref.read(compassCalibrationAcknowledgedProvider.notifier).state = true;
        ref.read(gyroscopeAimingEnabledProvider.notifier).state = true;
      }
    });
  }

  static Color _accuracyColor(CompassAccuracy accuracy) {
    switch (accuracy) {
      case CompassAccuracy.high:
        return const Color(0xFF00E676);
      case CompassAccuracy.medium:
        return const Color(0xFFFFEB3B);
      case CompassAccuracy.low:
        return const Color(0xFFFF9800);
      case CompassAccuracy.unreliable:
        return const Color(0xFFE53935);
      case CompassAccuracy.unknown:
        return const Color(0xFF9E9E9E);
    }
  }
}

/// Compact slew controls for mobile
class MobileSlewControls extends ConsumerWidget {
  final NightshadeColors colors;
  final bool slewMode;
  final VoidCallback onToggleSlewMode;
  final VoidCallback onStopSlew;

  const MobileSlewControls({
    super.key,
    required this.colors,
    required this.slewMode,
    required this.onToggleSlewMode,
    required this.onStopSlew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mountState = ref.watch(mountStateProvider);
    final isConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final isSlewing = mountState.isSlewing;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: slewMode
            ? Border.all(color: const Color(0xFFFF9800), width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MobileControlButton(
            key: PlanetariumTutorialKeys.slewBtn,
            icon: LucideIcons.move,
            isActive: slewMode,
            isEnabled: isConnected,
            onTap: isConnected ? onToggleSlewMode : null,
            activeColor: const Color(0xFFFF9800),
          ),
          const SizedBox(height: 4),
          MobileControlButton(
            icon: LucideIcons.octagon,
            isEnabled: isConnected && isSlewing,
            onTap: isConnected && isSlewing ? onStopSlew : null,
            activeColor: const Color(0xFFE53935),
          ),
        ],
      ),
    );
  }
}

/// Compact control button for mobile view/slew controls
/// Uses 44px touch target with smaller visual appearance
class MobileControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final bool isEnabled;
  final Color? activeColor;

  const MobileControlButton({
    super.key,
    required this.icon,
    this.onTap,
    this.isActive = false,
    this.isEnabled = true,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? (activeColor ?? const Color(0xFF00E676)) : Colors.white70;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 36, // Larger touch target
        height: 36, // Larger touch target
        alignment: Alignment.center,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isEnabled ? color : Colors.white24,
          ),
        ),
      ),
    );
  }
}

/// Compact bottom info bar for mobile
/// Uses FittedBox to handle narrow screen overflow gracefully
class MobileBottomInfoBar extends ConsumerWidget {
  final NightshadeColors colors;

  const MobileBottomInfoBar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(skyViewStateProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RA ${CoordinateFormatUtils.formatRACompact(viewState.centerRA)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Dec ${CoordinateFormatUtils.formatDecCompact(viewState.centerDec)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'FOV ${CoordinateFormatUtils.formatFOVCompact(viewState.fieldOfView)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact selected object HUD for mobile (tap to expand)
class MobileSelectedObjectHud extends StatelessWidget {
  final NightshadeColors colors;
  final SelectedObjectState selectedObject;
  final VoidCallback onTap;

  const MobileSelectedObjectHud({
    super.key,
    required this.colors,
    required this.selectedObject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final obj = selectedObject.object;
    if (obj == null) return const SizedBox.shrink();

    String displayName;
    String catalogTag;
    if (obj is DeepSkyObject) {
      final info = getDsoDisplayInfo(obj);
      displayName = info.$1;
      catalogTag = info.$2;
    } else {
      displayName = obj.name;
      catalogTag = obj is Star ? 'STAR' : obj.id;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                catalogTag,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile object info bottom sheet content
class MobileObjectInfoContent extends ConsumerWidget {
  final NightshadeColors colors;
  final ScrollController scrollController;
  final SelectedObjectState selectedObject;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToSequencer;
  final VoidCallback onSlewToTarget;
  final VoidCallback onSlewAndCenter;
  final bool hasRotator;

  const MobileObjectInfoContent({
    super.key,
    required this.colors,
    required this.scrollController,
    required this.selectedObject,
    required this.onSendToFraming,
    required this.onAddToSequencer,
    required this.onSlewToTarget,
    required this.onSlewAndCenter,
    required this.hasRotator,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obj = selectedObject.object;
    if (obj == null) {
      return Center(
        child: Text(
          'No object selected',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }

    String displayName;
    String catalogTag;
    String typeName;
    if (obj is DeepSkyObject) {
      final info = getDsoDisplayInfo(obj);
      displayName = info.$1;
      catalogTag = info.$2;
      typeName = obj.type.displayName;
    } else if (obj is Star) {
      displayName = obj.name;
      catalogTag = 'STAR';
      typeName =
          obj.spectralType != null ? 'Star (${obj.spectralType})' : 'Star';
    } else {
      displayName = obj.name;
      catalogTag = obj.id;
      typeName = 'Object';
    }

    final coords = selectedObject.coordinates;
    final altAz = selectedObject.currentAltAz;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                catalogTag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    typeName,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (obj.magnitude != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'mag ${obj.magnitude!.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 20),

        // Coordinates
        if (coords != null)
          MobileInfoCard(
            title: 'Coordinates',
            colors: colors,
            child: Row(
              children: [
                Expanded(
                  child: MobileInfoRow(
                    label: 'RA',
                    value: CoordinateFormatUtils.formatRA(coords.ra),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: MobileInfoRow(
                    label: 'Dec',
                    value: CoordinateFormatUtils.formatDec(coords.dec),
                    colors: colors,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Current position
        if (altAz != null)
          MobileInfoCard(
            title: 'Current Position',
            colors: colors,
            child: Row(
              children: [
                Expanded(
                  child: MobileInfoRow(
                    label: 'Altitude',
                    value: altAz.$1.toStringAsFixed(1),
                    colors: colors,
                    valueColor: altAz.$1 > 30
                        ? colors.success
                        : altAz.$1 > 0
                            ? colors.warning
                            : colors.error,
                  ),
                ),
                Expanded(
                  child: MobileInfoRow(
                    label: 'Azimuth',
                    value: altAz.$2.toStringAsFixed(1),
                    colors: colors,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (altAz.$1 > 30
                            ? colors.success
                            : altAz.$1 > 0
                                ? colors.warning
                                : colors.error)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    altAz.$1 > 30
                        ? 'Excellent'
                        : altAz.$1 > 15
                            ? 'Good'
                            : altAz.$1 > 0
                                ? 'Low'
                                : 'Below',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: altAz.$1 > 30
                          ? colors.success
                          : altAz.$1 > 0
                              ? colors.warning
                              : colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: MobileActionButton(
                icon: LucideIcons.crosshair,
                label: 'Slew',
                colors: colors,
                onTap: () {
                  Navigator.of(context).pop();
                  onSlewToTarget();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MobileActionButton(
                icon: LucideIcons.target,
                label: 'Center',
                colors: colors,
                onTap: () {
                  Navigator.of(context).pop();
                  onSlewAndCenter();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MobileActionButton(
                icon: LucideIcons.frame,
                label: 'Framing',
                colors: colors,
                onTap: () {
                  Navigator.of(context).pop();
                  onSendToFraming();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MobileActionButton(
                icon: LucideIcons.listPlus,
                label: 'Add to Sequence',
                colors: colors,
                isPrimary: true,
                onTap: () {
                  Navigator.of(context).pop();
                  onAddToSequencer();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Mobile info card container
class MobileInfoCard extends StatelessWidget {
  final String title;
  final NightshadeColors colors;
  final Widget child;

  const MobileInfoCard({
    super.key,
    required this.title,
    required this.colors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Mobile info row
class MobileInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;

  const MobileInfoRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Mobile action button
class MobileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isPrimary;
  final VoidCallback onTap;

  const MobileActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? LinearGradient(
                  colors: [
                    colors.primary,
                    colors.primary.withValues(alpha: 0.8)
                  ],
                )
              : null,
          color: isPrimary ? null : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isPrimary ? Colors.white : colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile search bottom sheet
class MobileSearchSheet extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ScrollController scrollController;
  final ValueChanged<CelestialObject> onObjectSelected;

  const MobileSearchSheet({
    super.key,
    required this.colors,
    required this.scrollController,
    required this.onObjectSelected,
  });

  @override
  ConsumerState<MobileSearchSheet> createState() => _MobileSearchSheetState();
}

class _MobileSearchSheetState extends ConsumerState<MobileSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    if (value.length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        ref.read(objectSearchProvider.notifier).search(value);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(objectSearchProvider);

    return Column(
      children: [
        // Search input
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: widget.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search objects (M42, Orion, etc.)',
              hintStyle:
                  TextStyle(fontSize: 14, color: widget.colors.textMuted),
              prefixIcon: Icon(LucideIcons.search,
                  size: 18, color: widget.colors.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(LucideIcons.x,
                          size: 18, color: widget.colors.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(objectSearchProvider.notifier).clear();
                      },
                    )
                  : null,
              filled: true,
              fillColor: widget.colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.colors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
        ),

        // Results
        Expanded(
          child: _buildResults(searchState),
        ),
      ],
    );
  }

  Widget _buildResults(ObjectSearchState searchState) {
    if (_searchController.text.isEmpty) {
      // Show quick picks when no search
      return _buildQuickPicks();
    }

    if (searchState.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.searchX, size: 48, color: widget.colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(color: widget.colors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // MobileSearchResultTile: 36 icon + 12*2 padding + 8 bottom margin = 68.
      itemExtent: 68,
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final obj = searchState.results[index];
        return MobileSearchResultTile(
          object: obj,
          colors: widget.colors,
          onTap: () => widget.onObjectSelected(obj),
        );
      },
    );
  }

  Widget _buildQuickPicks() {
    final bestTargets = ref.watch(bestTargetsProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(
          'Best Targets Tonight',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        bestTargets.when(
          data: (targets) {
            if (targets.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No targets above 30 tonight',
                    style: TextStyle(color: widget.colors.textMuted),
                  ),
                ),
              );
            }
            return Column(
              children: targets.take(10).map((item) {
                final (dso, _) = item;
                return MobileSearchResultTile(
                  object: dso,
                  colors: widget.colors,
                  onTap: () => widget.onObjectSelected(dso),
                );
              }).toList(),
            );
          },
          // Shimmer tile column instead of a spinner so the search panel
          // doesn't visibly shrink while suggestions stream in.
          loading: () => Column(
            children: List.generate(
              5,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ShimmerLoading(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: widget.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          error: (e, _) => Center(
            child:
                Text('Error: $e', style: TextStyle(color: widget.colors.error)),
          ),
        ),
      ],
    );
  }
}

/// Mobile search result tile
class MobileSearchResultTile extends StatelessWidget {
  final CelestialObject object;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const MobileSearchResultTile({
    super.key,
    required this.object,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String displayName;
    String catalogTag;
    String typeName;

    if (object is DeepSkyObject) {
      final info = getDsoDisplayInfo(object as DeepSkyObject);
      displayName = info.$1;
      catalogTag = info.$2;
      typeName = (object as DeepSkyObject).type.displayName;
    } else if (object is Star) {
      displayName = object.name;
      catalogTag = 'STAR';
      typeName = 'Star';
    } else {
      displayName = object.name;
      catalogTag = object.id;
      typeName = 'Object';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                catalogTag,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    typeName,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (object.magnitude != null)
              Text(
                'mag ${object.magnitude!.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compass calibration dialog shown on first gyroscope activation.
/// Instructs the user to perform the figure-8 calibration gesture.
class CompassCalibrationDialog extends StatelessWidget {
  const CompassCalibrationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // Tokenized surface so this dialog respects Red Night theme — audit §4.15.
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return AlertDialog(
      backgroundColor: colors.surfaceOverlay,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: const Row(
        children: [
          Icon(LucideIcons.compass, color: Color(0xFF2196F3), size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Compass Calibration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For accurate sky aiming, calibrate your compass by moving your device in a figure-8 pattern several times.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF2196F3).withValues(alpha: 0.3),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips for best results:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2196F3),
                  ),
                ),
                SizedBox(height: 8),
                _CalibrationTip(
                    text: 'Move away from metal objects and magnets'),
                _CalibrationTip(
                    text: 'Remove phone cases with magnetic clasps'),
                _CalibrationTip(text: 'Rotate device slowly in all three axes'),
                _CalibrationTip(
                    text:
                        'A colored dot shows accuracy: green = good, red = poor'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Accuracy of a few degrees is typical for phone compasses. This mode is best for quick sky orientation, not precision pointing.',
            style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.3),
          ),
        ],
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(false),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
        ),
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(true),
          label: 'Enable Sky Aiming',
        ),
      ],
    );
  }
}

class _CalibrationTip extends StatelessWidget {
  final String text;

  const _CalibrationTip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(LucideIcons.check, size: 12, color: Color(0xFF2196F3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
