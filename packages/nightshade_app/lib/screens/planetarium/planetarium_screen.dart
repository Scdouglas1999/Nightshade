import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../services/finder_chart_service.dart';
import '../../utils/plan_tonight_sequencer_helper.dart';
import 'widgets/filter_sidebar.dart';
import 'widgets/top_overlay.dart';
import 'widgets/bottom_info_bar.dart';
import 'widgets/view_controls.dart';
import 'widgets/slew_controls.dart';
import 'widgets/search_header.dart';
import 'widgets/sidebar_tabs.dart';
import 'widgets/object_info_popup.dart';
import 'widgets/mobile_widgets.dart';
import 'widgets/mobile_overlay_layout.dart';
import 'providers/device_orientation_provider.dart';
import '../../services/mount_command_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/planetarium_keys.dart';
import 'widgets/full_screen_sky_view.dart';
import '../imaging/centering_dialog.dart';
import '../../widgets/contextual_tour_prompt.dart';

part 'planetarium_screen/actions.dart';
part 'planetarium_screen/layouts.dart';
part 'planetarium_screen/local_widgets.dart';

/// Get display name and catalog tag for a DSO
/// Returns (displayName, catalogTag)
(String, String) getDsoDisplayInfo(DeepSkyObject dso) {
  // If it's a Messier object, use Messier number as name
  if (dso.isMessier) {
    final messierNum = dso.messierNumber;
    if (messierNum != null) {
      return (messierNum, 'M');
    }
  }

  // For non-Messier objects, use NGC/IC designation as name
  final ngcIc = dso.ngcIcDesignation;
  if (ngcIc != null) {
    if (ngcIc.startsWith('NGC')) {
      return (ngcIc, 'NGC');
    } else if (ngcIc.startsWith('IC')) {
      return (ngcIc, 'IC');
    }
  }

  // Fallback to id and extract catalog prefix
  if (dso.id.startsWith('NGC')) {
    return (dso.id, 'NGC');
  } else if (dso.id.startsWith('IC')) {
    return (dso.id, 'IC');
  } else if (dso.id.startsWith('M')) {
    return (dso.id, 'M');
  }

  // Last resort: use name and id
  return (dso.name, dso.id);
}

class PlanetariumScreen extends ConsumerStatefulWidget {
  const PlanetariumScreen({super.key});

  @override
  ConsumerState<PlanetariumScreen> createState() => _PlanetariumScreenState();
}

class _PlanetariumScreenState extends ConsumerState<PlanetariumScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();

  // Popup state
  bool _showPopup = false;
  Offset _popupPosition = Offset.zero;
  CelestialObject? _popupObject;
  CelestialCoordinate? _popupCoordinates;
  final GlobalKey _skyViewKey = GlobalKey();

  // Slew mode state
  bool _slewMode = false;

  // FOV overlay state
  bool _showFOV = false;

  // Track if initial sync has been done
  bool _initialSyncDone = false;

  // Filter sidebar state
  bool _filterSidebarExpanded = false;

  // Help overlay state
  bool _showHelpOverlay = false;

  // Gyroscope mount sync debounce timer
  Timer? _mountSyncDebounce;
  double? _lastSyncRA;
  double? _lastSyncDec;

  void _update(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    // Do initial sync after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _performInitialSync();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mountSyncDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final selectedObject = ref.watch(selectedObjectProvider);

    // Sync mount state from equipment provider to planetarium mount position provider
    ref.listen<MountState>(mountStateProvider, (previous, next) {
      final mountNotifier = ref.read(mountPositionProvider.notifier);
      if (next.connectionState == DeviceConnectionState.connected) {
        MountTrackingStatus status;
        if (next.isSlewing) {
          status = MountTrackingStatus.slewing;
        } else if (next.isParked) {
          status = MountTrackingStatus.parked;
        } else if (next.isTracking) {
          status = MountTrackingStatus.tracking;
        } else {
          status = MountTrackingStatus.stopped;
        }

        mountNotifier.updatePosition(
          raHours: next.ra,
          decDegrees: next.dec,
          status: status,
          isConnected: true,
        );
      } else {
        mountNotifier.setDisconnected();
      }
    });

    // Sync rotator position to equipment FOV rotation
    ref.listen<RotatorState>(rotatorStateProvider, (previous, next) {
      if (next.connectionState == DeviceConnectionState.connected &&
          next.position != null) {
        ref.read(equipmentFOVProvider.notifier).setRotation(next.position!);
      }
    });

    // Gyroscope sky aiming: update sky view center from device orientation,
    // and optionally send debounced slew commands to the remote mount.
    ref.listen<DeviceOrientationState>(deviceOrientationProvider,
        (previous, next) {
      if (!ref.read(gyroscopeAimingEnabledProvider)) return;
      if (!next.isActive) return;

      final location = ref.read(observerLocationProvider);
      final time = ref.read(observationTimeProvider);
      final result = deviceOrientationToRaDec(
        orientation: next,
        location: location,
        time: time,
      );
      if (result == null) return;

      final (raHours, decDeg) = result;

      // Always update local sky view immediately
      ref.read(skyViewStateProvider.notifier).setCenter(raHours, decDeg);

      // If mount sync is enabled, debounce slew commands (2s after user stops moving)
      if (ref.read(gyroscopeMountSyncProvider)) {
        _lastSyncRA = raHours;
        _lastSyncDec = decDeg;
        _mountSyncDebounce?.cancel();
        _mountSyncDebounce = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          final ra = _lastSyncRA;
          final dec = _lastSyncDec;
          if (ra == null || dec == null) return;

          final mountService = ref.read(mountCommandServiceProvider);
          if (!mountService.isConnected) return;

          mountService.slewTo(ra, dec, showFeedback: false);
        });
      }
    });

    final nightVision = ref.watch(nightVisionModeProvider);

    return ContextualTourPrompt(
      screenId: 'planetarium',
      tourCategory: TutorialCategory.planetariumTour,
      title: 'Planetarium Tour',
      description: 'Learn how to navigate the sky and find targets.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: _NightVisionFilter(
        enabled: nightVision,
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            onTapDown: (details) {
              if (_showPopup) {
                final popupRect = resolveObjectInfoPopupLayout(
                  context,
                  _popupPosition,
                ).rect;
                if (!popupRect.contains(details.globalPosition)) {
                  _dismissPopup();
                }
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Phone tier: the full-bleed sky canvas with floating,
                // orientation-aware overlays. Tablets/desktop keep the
                // resizable sidebar split, which already clamps its panel widths
                // down to a 600 px window. Use device-class detection so a phone
                // in LANDSCAPE (wide viewport) still gets the overlay layout
                // rather than the desktop sidebar; a narrow desktop window
                // (width < 600) also collapses to it.
                final isPhone = Responsive.isPhone(context) ||
                    BreakpointTokens.isPhone(constraints.maxWidth);
                if (isPhone) {
                  return _buildMobileLayout(context, colors, selectedObject);
                }
                return _buildDesktopLayout(context, colors, selectedObject);
              },
            ),
          ),
        ),
      ),
    );
  }
}
