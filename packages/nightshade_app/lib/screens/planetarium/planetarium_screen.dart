import 'dart:async';
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
import '../../utils/add_target_header_helper.dart';
import 'widgets/filter_sidebar.dart';
import 'widgets/top_overlay.dart';
import 'widgets/bottom_info_bar.dart';
import 'widgets/view_controls.dart';
import 'widgets/slew_controls.dart';
import 'widgets/search_header.dart';
import 'widgets/sidebar_tabs.dart';
import 'widgets/object_info_popup.dart';
import 'widgets/mobile_widgets.dart';
import 'providers/device_orientation_provider.dart';
import '../../services/mount_command_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/planetarium_keys.dart';
import '../imaging/centering_dialog.dart';
import '../../widgets/contextual_tour_prompt.dart';

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

  void _performInitialSync() {
    if (_initialSyncDone) return;
    _initialSyncDone = true;

    // Initial mount sync
    final mountState = ref.read(mountStateProvider);
    final mountNotifier = ref.read(mountPositionProvider.notifier);
    if (mountState.connectionState == DeviceConnectionState.connected) {
      MountTrackingStatus status;
      if (mountState.isSlewing) {
        status = MountTrackingStatus.slewing;
      } else if (mountState.isParked) {
        status = MountTrackingStatus.parked;
      } else if (mountState.isTracking) {
        status = MountTrackingStatus.tracking;
      } else {
        status = MountTrackingStatus.stopped;
      }
      mountNotifier.updatePosition(
        raHours: mountState.ra,
        decDegrees: mountState.dec,
        status: status,
        isConnected: true,
      );
    }

    // Initial rotator sync
    final rotatorState = ref.read(rotatorStateProvider);
    if (rotatorState.connectionState == DeviceConnectionState.connected &&
        rotatorState.position != null) {
      ref
          .read(equipmentFOVProvider.notifier)
          .setRotation(rotatorState.position!);
    }
  }

  void _handleObjectTapped(CelestialObject? object,
      CelestialCoordinate coordinates, Offset screenPosition) {
    // If in slew mode, handle slew instead of normal tap behavior
    if (_slewMode) {
      _handleSlewToCoordinates(coordinates, objectName: object?.name);
      return;
    }

    // Update selected object provider
    if (object != null) {
      ref.read(selectedObjectProvider.notifier).selectObject(object);
    } else {
      ref.read(selectedObjectProvider.notifier).clearSelection();
    }

    // Only show popup if an object was found
    if (object != null) {
      final renderBox =
          _skyViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        // Convert to global position for proper popup placement
        final globalPosition = renderBox.localToGlobal(screenPosition);
        setState(() {
          _showPopup = true;
          _popupPosition = globalPosition;
          _popupObject = object;
          _popupCoordinates = coordinates;
        });
      }
    } else {
      _dismissPopup();
    }
  }

  void _dismissPopup() {
    if (_showPopup) {
      setState(() {
        _showPopup = false;
        _popupObject = null;
        _popupCoordinates = null;
      });
    }
  }

  Future<void> _exportFinderChart(BuildContext _) async {
    final viewState = ref.read(skyViewStateProvider);
    final renderConfig = ref.read(skyRenderConfigProvider);
    final location = ref.read(observerLocationProvider);
    final time = ref.read(observationTimeProvider);
    final stars = ref.read(fovFilteredStarsProvider).valueOrNull ?? [];
    final dsos = ref.read(fovFilteredDsosProvider).valueOrNull ?? [];
    final constellations = ref.read(constellationDataProvider);
    final selectedState = ref.read(selectedObjectProvider);
    final sunPos = ref.read(sunPositionProvider);
    final moonPos = ref.read(moonPositionProvider);
    final moonInfo = ref.read(moonInfoProvider);
    final planets = ref.read(planetPositionsProvider);
    final milkyWayPoints = ref.read(milkyWayPointsProvider);

    // Determine object info from popup or selection
    String? objectName;
    String? objectType;
    double? objectMagnitude;
    String? objectSize;
    final obj = _popupObject ?? selectedState.object;
    if (obj != null) {
      if (obj is DeepSkyObject) {
        final (displayName, _) = getDsoDisplayInfo(obj);
        objectName = displayName;
        objectType = obj.type.displayName;
        objectMagnitude = obj.magnitude;
        objectSize = obj.sizeString;
      } else {
        objectName = obj.name;
        objectMagnitude = obj.magnitude;
        if (obj is Star) {
          objectType =
              obj.spectralType != null ? 'Star (${obj.spectralType})' : 'Star';
        }
      }
    }

    final suggestedName = FinderChartService.suggestedFilename(
      objectName: objectName,
    );

    final saveLocation = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF files', extensions: ['pdf']),
      ],
    );

    if (saveLocation == null) return;

    try {
      await FinderChartService.generateChart(
        outputPath: saveLocation.path,
        viewState: viewState,
        renderConfig: renderConfig,
        stars: stars,
        dsos: dsos,
        constellations: constellations,
        observationTime: time.time,
        latitude: location.latitude,
        longitude: location.longitude,
        chartConfig: FinderChartConfig(
          printMode: false,
          chartResolution: 2048,
          objectName: objectName,
          objectType: objectType,
          objectMagnitude: objectMagnitude,
          objectSize: objectSize,
          includeDetailsPage: objectName != null,
        ),
        selectedObject: selectedState.coordinates,
        sunPosition: sunPos,
        moonPosition: (moonPos.$1, moonPos.$2, moonInfo.illumination),
        planets: planets,
        milkyWayPoints: milkyWayPoints,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finder chart saved to ${saveLocation.path}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export chart: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _sendToFraming() {
    if (_popupObject == null) return;

    final obj = _popupObject!;
    final coords = _popupCoordinates ?? obj.coordinates;

    // Set the framing target
    ref.read(framingProvider.notifier).setTargetCoordinates(
          coords.ra,
          coords.dec,
          name: obj.name,
        );

    // Navigate to framing screen
    try {
      context.goNamed('framing');
    } catch (e) {
      // Router might not be available, ignore
    }

    _dismissPopup();
  }

  Future<void> _addToSequencer() async {
    if (_popupObject == null) return;

    final obj = _popupObject!;
    final coords = _popupCoordinates ?? obj.coordinates;

    final added = await addTargetHeaderWithPrompt(
      context: context,
      ref: ref,
      targetNode: TargetHeaderNode(
        targetName: obj.name,
        raHours: coords.ra,
        decDegrees: coords.dec,
      ),
    );

    if (added && mounted) {
      context.showSuccessSnackBar('Added ${obj.name} to sequence');
    }
    if (mounted) _dismissPopup();
  }

  Future<void> _handleSlewToTarget() async {
    if (_popupObject == null) return;

    final obj = _popupObject!;
    final coords = _popupCoordinates ?? obj.coordinates;

    await ref.read(mountCommandServiceProvider).slewTo(coords.ra, coords.dec);

    _dismissPopup();
  }

  Future<void> _handleSlewAndCenter(
      CelestialCoordinate coords, String objectName) async {
    // First slew to approximate position
    final mountService = ref.read(mountCommandServiceProvider);
    final result =
        await mountService.slewTo(coords.ra, coords.dec, showFeedback: false);

    if (!result.isSuccess) {
      return;
    }

    _dismissPopup();

    // Show centering dialog
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => CenteringDialog(
          targetRa: coords.ra,
          targetDec: coords.dec,
          targetName: objectName,
        ),
      );
    }
  }

  Future<void> _handleSlewCenterRotate(
      CelestialCoordinate coords, String objectName) async {
    // First slew to approximate position
    final mountService = ref.read(mountCommandServiceProvider);
    final slewResult =
        await mountService.slewTo(coords.ra, coords.dec, showFeedback: false);

    if (!slewResult.isSuccess) {
      return;
    }

    _dismissPopup();

    // Show centering dialog and wait for completion
    CenteringResult? centeringResult;
    if (mounted) {
      centeringResult = await showDialog<CenteringResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => CenteringDialog(
          targetRa: coords.ra,
          targetDec: coords.dec,
          targetName: objectName,
        ),
      );
    }

    // If centering failed or was cancelled, don't rotate
    if (centeringResult == null || !centeringResult.success) {
      if (mounted && centeringResult != null) {
        context.showWarningSnackBar('Centering failed - rotation skipped');
      }
      return;
    }

    if (mounted) {
      context.showInfoSnackBar('Centered on $objectName');
    }
  }

  Future<void> _handleSlewToCoordinates(CelestialCoordinate coords,
      {String? objectName}) async {
    final mountService = ref.read(mountCommandServiceProvider);
    if (!mountService.isConnected) {
      if (mounted) {
        context.showWarningSnackBar('Mount not connected');
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Slew'),
        content: Text(
          objectName != null
              ? 'Slew mount to $objectName?\n\nRA: ${coords.ra.toStringAsFixed(4)}h\nDec: ${coords.dec.toStringAsFixed(4)}\u00b0'
              : 'Slew mount to coordinates?\n\nRA: ${coords.ra.toStringAsFixed(4)}h\nDec: ${coords.dec.toStringAsFixed(4)}\u00b0',
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            label: 'Slew',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await mountService.slewTo(coords.ra, coords.dec);
  }

  void _toggleSlewMode() {
    setState(() {
      _slewMode = !_slewMode;
    });
    if (_slewMode) {
      context.showInfoSnackBar('Slew mode enabled - tap on sky to slew mount');
    }
  }

  Future<void> _handleStopSlew() async {
    final mountState = ref.read(mountStateProvider);
    if (mountState.connectionState != DeviceConnectionState.connected) {
      if (mounted) {
        context.showWarningSnackBar('Mount not connected');
      }
      return;
    }

    if (!mountState.isSlewing) {
      if (mounted) {
        context.showInfoSnackBar('Mount is not slewing');
      }
      return;
    }

    await ref.read(mountCommandServiceProvider).abortSlew();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _panView(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _panView(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _panView(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _panView(1, 0);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.keyR) {
      _resetView();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyG) {
      ref.read(skyRenderConfigProvider.notifier).toggleGrid();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyC) {
      ref.read(skyRenderConfigProvider.notifier).toggleConstellationLines();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyE) {
      ref.read(skyRenderConfigProvider.notifier).toggleEcliptic();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyN) {
      ref.read(observationTimeProvider.notifier).setRealTime(true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      final timeState = ref.read(observationTimeProvider);
      if (timeState.isRealTime) {
        // Pause: switch to frozen time
        ref.read(observationTimeProvider.notifier).setSpeedMultiplier(0);
      } else if (timeState.speedMultiplier == 0) {
        // Resume: switch back to real-time
        ref.read(observationTimeProvider.notifier).setRealTime(true);
      } else {
        // Currently fast-forwarding: pause
        ref.read(observationTimeProvider.notifier).setSpeedMultiplier(0);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyM) {
      ref.read(showMinimapProvider.notifier).state =
          !ref.read(showMinimapProvider);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyF) {
      setState(() => _showFOV = !_showFOV);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_showHelpOverlay) {
        setState(() => _showHelpOverlay = false);
        return KeyEventResult.handled;
      }
      _dismissPopup();
      ref.read(selectedObjectProvider.notifier).clearSelection();
      return KeyEventResult.handled;
    }

    if ((key == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.logicalKeysPressed
                .contains(LogicalKeyboardKey.shiftLeft)) ||
        (key == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.logicalKeysPressed
                .contains(LogicalKeyboardKey.shiftRight)) ||
        key == LogicalKeyboardKey.question) {
      setState(() => _showHelpOverlay = !_showHelpOverlay);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _panView(double dx, double dy) {
    final viewState = ref.read(skyViewStateProvider);
    final panAmount = viewState.fieldOfView / 20;
    ref.read(skyViewStateProvider.notifier).setCenter(
          viewState.centerRA + dx * panAmount / 15,
          (viewState.centerDec + dy * panAmount).clamp(-90.0, 90.0),
        );
  }

  void _zoomIn() {
    final viewState = ref.read(skyViewStateProvider);
    ref.read(skyViewStateProvider.notifier).setFieldOfView(
          (viewState.fieldOfView * 0.8).clamp(1.0, 120.0),
        );
  }

  void _zoomOut() {
    final viewState = ref.read(skyViewStateProvider);
    ref.read(skyViewStateProvider.notifier).setFieldOfView(
          (viewState.fieldOfView * 1.25).clamp(1.0, 120.0),
        );
  }

  void _resetView() {
    ref.read(skyViewStateProvider.notifier).setCenter(0, 0);
    ref.read(skyViewStateProvider.notifier).setFieldOfView(60);
  }

  void _showFilterBottomSheet(BuildContext context) {
    // Tokenized colors so Red Night theme keeps its red wash across mobile
    // filter sheets — audit §4.15.
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceOverlay,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final config = ref.watch(skyRenderConfigProvider);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Stars'),
                    value: config.showStars,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .toggleStars(),
                  ),
                  SwitchListTile(
                    title: const Text('Planets'),
                    value: config.showPlanets,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .togglePlanets(),
                  ),
                  SwitchListTile(
                    title: const Text('Deep Sky'),
                    value: config.showDSOs,
                    onChanged: (_) =>
                        ref.read(skyRenderConfigProvider.notifier).toggleDSOs(),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Grid'),
                    value: config.showCoordinateGrid,
                    onChanged: (_) =>
                        ref.read(skyRenderConfigProvider.notifier).toggleGrid(),
                  ),
                  SwitchListTile(
                    title: const Text('Constellations'),
                    value: config.showConstellationLines,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .toggleConstellationLines(),
                  ),
                  SwitchListTile(
                    title: const Text('Ground'),
                    value: ref.watch(showGroundPlaneProvider),
                    onChanged: (v) =>
                        ref.read(showGroundPlaneProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reset',
          child: Row(
            children: [
              Icon(LucideIcons.home, size: 16),
              SizedBox(width: 8),
              Text('Reset View'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'grid',
          child: Row(
            children: [
              Icon(LucideIcons.grid, size: 16),
              SizedBox(width: 8),
              Text('Toggle Grid'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'constellations',
          child: Row(
            children: [
              Icon(LucideIcons.activity, size: 16),
              SizedBox(width: 8),
              Text('Toggle Constellations'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'fov',
          child: Row(
            children: [
              Icon(LucideIcons.frame, size: 16),
              SizedBox(width: 8),
              Text('Toggle FOV Overlay'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'reset':
          _resetView();
          break;
        case 'grid':
          ref.read(skyRenderConfigProvider.notifier).toggleGrid();
          break;
        case 'constellations':
          ref.read(skyRenderConfigProvider.notifier).toggleConstellationLines();
          break;
        case 'fov':
          setState(() => _showFOV = !_showFOV);
          break;
      }
    });
  }

  static const double _mobileBreakpoint = 700;

  void _showObjectInfoBottomSheet(
      BuildContext context, NightshadeColors colors) {
    final selectedObject = ref.read(selectedObjectProvider);
    if (selectedObject.object == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: MobileObjectInfoContent(
                  colors: colors,
                  scrollController: scrollController,
                  selectedObject: selectedObject,
                  onSendToFraming: _sendToFraming,
                  onAddToSequencer: _addToSequencer,
                  onSlewToTarget: _handleSlewToTarget,
                  onSlewAndCenter: () {
                    final coords = selectedObject.coordinates;
                    if (coords != null && selectedObject.object != null) {
                      _handleSlewAndCenter(coords, selectedObject.object!.name);
                    }
                  },
                  hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                      DeviceConnectionState.connected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileSearchDialog(BuildContext context, NightshadeColors colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: colors.border),
          ),
          child: MobileSearchSheet(
            colors: colors,
            scrollController: scrollController,
            onObjectSelected: (obj) {
              ref.read(selectedObjectProvider.notifier).selectObject(obj);
              ref.read(skyViewStateProvider.notifier).lookAt(obj.coordinates);
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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

    return ContextualTourPrompt(
      screenId: 'planetarium',
      tourCategory: TutorialCategory.planetariumTour,
      title: 'Planetarium Tour',
      description: 'Learn how to navigate the sky and find targets.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTapDown: (details) {
            if (_showPopup) {
              final popupRect = Rect.fromCenter(
                center: _popupPosition,
                width: 320,
                height: 280,
              );
              if (!popupRect.contains(details.globalPosition)) {
                _dismissPopup();
              }
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < _mobileBreakpoint;
              if (isMobile) {
                return _buildMobileLayout(context, colors, selectedObject);
              }
              return _buildDesktopLayout(context, colors, selectedObject);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, NightshadeColors colors,
      SelectedObjectState selectedObject) {
    final sizing = AdaptiveSizing.of(context);

    return Stack(
      key: _skyViewKey,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, details.globalPosition),
            child: Consumer(
              builder: (context, ref, _) {
                final observedIds =
                    ref.watch(observedCatalogIdsProvider).valueOrNull ?? {};
                final listedIds =
                    ref.watch(listedCatalogIdsProvider).valueOrNull ?? {};
                final bortleClass = ref.watch(bortleClassProvider);
                final horizonProfile = ref.watch(horizonProfileProvider);
                return InteractiveSkyView(
                  key: PlanetariumTutorialKeys.skyView,
                  showFOV: _showFOV,
                  onObjectTapped: _handleObjectTapped,
                  observedObjectIds: observedIds,
                  listedObjectIds: listedIds,
                  bortleClass: bortleClass,
                  horizonAltitudes: horizonProfile.isFlat
                      ? null
                      : List<double>.generate(
                          360,
                          (az) =>
                              horizonProfile.altitudeAtAzimuth(az.toDouble())),
                );
              },
            ),
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: MobileTopOverlay(colors: colors),
        ),

        Positioned(
          top: 70,
          left: 12,
          child: MobileViewControls(
            colors: colors,
            showFOV: _showFOV,
            onToggleFOV: () => setState(() => _showFOV = !_showFOV),
          ),
        ),

        Positioned(
          top: 200,
          left: 12,
          child: MobileSlewControls(
            colors: colors,
            slewMode: _slewMode,
            onToggleSlewMode: _toggleSlewMode,
            onStopSlew: _handleStopSlew,
          ),
        ),

        Positioned(
          left: sizing.edgePadding,
          bottom: 90 + sizing.edgePadding,
          child: Consumer(
            builder: (context, ref, _) {
              final showCompass = ref.watch(showCompassHudProvider);
              if (!showCompass) return const SizedBox.shrink();

              final (az, alt) = ref.watch(viewCenterAltAzProvider);
              return CompassHud(
                azimuth: az,
                altitude: alt,
                size: 60,
                showAltitude: false,
              );
            },
          ),
        ),

        Positioned(
          right: sizing.edgePadding,
          bottom: 200 + sizing.edgePadding,
          child: Consumer(
            builder: (context, ref, _) {
              final showMinimap = ref.watch(showMinimapProvider);
              if (!showMinimap) return const SizedBox.shrink();

              final (az, alt) = ref.watch(viewCenterAltAzProvider);
              final viewState = ref.watch(skyViewStateProvider);

              return SkyMinimap(
                azimuth: az,
                altitude: alt,
                fieldOfView: viewState.fieldOfView,
                rotation: viewState.rotation,
                size: 80,
                onTap: (tapAz, tapAlt) {
                  final location = ref.read(observerLocationProvider);
                  final time = ref.read(observationTimeProvider);
                  final lst = AstronomyCalculations.localSiderealTime(
                      time.time, location.longitude);

                  final (ra, dec) =
                      AstronomyCalculations.horizontalToEquatorial(
                    altDeg: tapAlt,
                    azDeg: tapAz,
                    latitudeDeg: location.latitude,
                    lstHours: lst,
                  );

                  ref
                      .read(skyViewStateProvider.notifier)
                      .setCenter(ra / 15, dec);
                },
              );
            },
          ),
        ),

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: MobileBottomInfoBar(colors: colors),
        ),

        Positioned(
          bottom: 50,
          left: 12,
          child: TimeControlPanel(
            backgroundColor: colors.surface.withValues(alpha: 0.9),
            textColor: colors.textPrimary,
            accentColor: colors.accent,
            compact: true,
          ),
        ),

        Positioned(
          right: 12,
          bottom: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                key: PlanetariumTutorialKeys.search,
                heroTag: 'search_fab',
                backgroundColor: colors.surface.withValues(alpha: 0.9),
                onPressed: () => _showMobileSearchDialog(context, colors),
                child: Icon(LucideIcons.search,
                    size: 20, color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                key: PlanetariumTutorialKeys.filterBtn,
                heroTag: 'filter_fab',
                backgroundColor: colors.surface.withValues(alpha: 0.9),
                onPressed: () => _showFilterBottomSheet(context),
                child: Icon(LucideIcons.slidersHorizontal,
                    size: 20, color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              if (selectedObject.object != null)
                FloatingActionButton(
                  heroTag: 'info_fab',
                  backgroundColor: colors.primary,
                  onPressed: () => _showObjectInfoBottomSheet(context, colors),
                  child: const Icon(LucideIcons.info,
                      size: 24, color: Colors.white),
                ),
            ],
          ),
        ),

        // MobileSelectedObjectHud removed: the ObjectInfoPopup (shown on click)
        // provides the same information plus detailed coordinates, alt/az,
        // and multiple action buttons. Having both caused duplicate cards.

        if (_showPopup && _popupObject != null)
          ObjectInfoPopup(
            colors: colors,
            object: _popupObject!,
            coordinates: _popupCoordinates ?? _popupObject!.coordinates,
            selectedObjectState: selectedObject,
            position: _popupPosition,
            onDismiss: _dismissPopup,
            onSendToFraming: _sendToFraming,
            onAddToSequencer: _addToSequencer,
            onSlewToTarget: _handleSlewToTarget,
            onSlewAndCenter: () => _handleSlewAndCenter(
              _popupCoordinates ?? _popupObject!.coordinates,
              _popupObject!.name,
            ),
            onSlewCenterRotate: () => _handleSlewCenterRotate(
              _popupCoordinates ?? _popupObject!.coordinates,
              _popupObject!.name,
            ),
            onExportChart: () => _exportFinderChart(context),
            hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                DeviceConnectionState.connected,
          ),

        if (_showHelpOverlay)
          _KeyboardShortcutsOverlay(
            onDismiss: () => setState(() => _showHelpOverlay = false),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, NightshadeColors colors,
      SelectedObjectState selectedObject) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              child: Stack(
                key: _skyViewKey,
                children: [
                  GestureDetector(
                    onSecondaryTapUp: (details) =>
                        _showContextMenu(context, details.globalPosition),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final observedIds =
                            ref.watch(observedCatalogIdsProvider).valueOrNull ??
                                {};
                        final bortleClass = ref.watch(bortleClassProvider);
                        final horizonProfile =
                            ref.watch(horizonProfileProvider);
                        return InteractiveSkyView(
                          key: PlanetariumTutorialKeys.skyView,
                          showFOV: _showFOV,
                          onObjectTapped: _handleObjectTapped,
                          observedObjectIds: observedIds,
                          bortleClass: bortleClass,
                          horizonAltitudes: horizonProfile.isFlat
                              ? null
                              : List<double>.generate(
                                  360,
                                  (az) => horizonProfile
                                      .altitudeAtAzimuth(az.toDouble())),
                        );
                      },
                    ),
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      width: double.infinity,
                      child: TopOverlay(colors: colors),
                    ),
                  ),

                  if (kDebugMode)
                    Positioned(
                      top: 60,
                      right: 16,
                      child: Consumer(
                        builder: (context, ref, _) {
                          final monitor = ref.watch(performanceMonitorProvider);
                          final refreshRate =
                              ref.watch(displayRefreshRateProvider);
                          final fps = monitor.estimatedFps;
                          final cappedFps =
                              fps > refreshRate ? refreshRate : fps;
                          final buildMs = monitor.averageBuildTime;
                          final rasterMs = monitor.averageRasterTime;

                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'FPS ${cappedFps.toStringAsFixed(1)} / ${refreshRate.toStringAsFixed(0)}Hz',
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'UI ${buildMs.toStringAsFixed(1)}ms  GPU ${rasterMs.toStringAsFixed(1)}ms',
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      width: double.infinity,
                      child: BottomInfoBar(colors: colors),
                    ),
                  ),

                  Positioned(
                    top: 60,
                    left: 16,
                    child: ViewControls(
                      colors: colors,
                      showFOV: _showFOV,
                      onToggleFOV: () => setState(() => _showFOV = !_showFOV),
                    ),
                  ),

                  Positioned(
                    top: 220,
                    left: 16,
                    child: SlewControls(
                      colors: colors,
                      slewMode: _slewMode,
                      onToggleSlewMode: _toggleSlewMode,
                      onStopSlew: _handleStopSlew,
                    ),
                  ),

                  // SelectedObjectHud removed: the ObjectInfoPopup (shown on click)
                  // provides the same information plus detailed coordinates, alt/az,
                  // and multiple action buttons. Having both caused duplicate cards.

                  Positioned(
                    left: AdaptiveSizing.of(context).edgePadding,
                    bottom: AdaptiveSizing.of(context).edgePadding,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final showCompass = ref.watch(showCompassHudProvider);
                        if (!showCompass) {
                          return const SizedBox.shrink();
                        }

                        final sizing = AdaptiveSizing.of(context);
                        final (az, alt) = ref.watch(viewCenterAltAzProvider);
                        return CompassHud(
                          azimuth: az,
                          altitude: alt,
                          size: sizing.compassSize,
                          showAltitude: !sizing.useCondensedHud,
                        );
                      },
                    ),
                  ),

                  Positioned(
                    right: AdaptiveSizing.of(context).edgePadding,
                    bottom: AdaptiveSizing.of(context).edgePadding,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final showMinimap = ref.watch(showMinimapProvider);
                        if (!showMinimap) {
                          return const SizedBox.shrink();
                        }

                        final sizing = AdaptiveSizing.of(context);
                        final (az, alt) = ref.watch(viewCenterAltAzProvider);
                        final viewState = ref.watch(skyViewStateProvider);

                        return SkyMinimap(
                          azimuth: az,
                          altitude: alt,
                          fieldOfView: viewState.fieldOfView,
                          rotation: viewState.rotation,
                          size: sizing.minimapSize,
                          onTap: (tapAz, tapAlt) {
                            final location = ref.read(observerLocationProvider);
                            final time = ref.read(observationTimeProvider);
                            final lst = AstronomyCalculations.localSiderealTime(
                                time.time, location.longitude);

                            final (ra, dec) =
                                AstronomyCalculations.horizontalToEquatorial(
                              altDeg: tapAlt,
                              azDeg: tapAz,
                              latitudeDeg: location.latitude,
                              lstHours: lst,
                            );

                            ref
                                .read(skyViewStateProvider.notifier)
                                .setCenter(ra / 15, dec);
                          },
                        );
                      },
                    ),
                  ),

                  Positioned(
                    bottom: 110,
                    left: 16,
                    child: TimeControlPanel(
                      backgroundColor: colors.surface.withValues(alpha: 0.9),
                      textColor: colors.textPrimary,
                      accentColor: colors.accent,
                      compact: false,
                    ),
                  ),

                  Positioned(
                    top: 60,
                    right: 0,
                    bottom: 0,
                    child: FilterSidebar(
                      isExpanded: _filterSidebarExpanded,
                      onToggle: () => setState(() =>
                          _filterSidebarExpanded = !_filterSidebarExpanded),
                    ),
                  ),
                ],
              ),
            ),
            ResizablePanel(
              initialWidth: 340,
              minWidth: 250,
              maxWidth: 500,
              side: ResizeSide.left,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(left: BorderSide(color: colors.border)),
                ),
                child: Column(
                  children: [
                    SearchHeader(
                      colors: colors,
                      controller: _searchController,
                      onSearch: (query) {
                        ref.read(objectSearchProvider.notifier).search(query);
                      },
                    ),
                    Expanded(
                      child: DefaultTabController(
                        length: 5,
                        child: Column(
                          children: [
                            SidebarTabs(colors: colors),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  TonightTab(colors: colors),
                                  CatalogTab(colors: colors),
                                  ListsTab(colors: colors),
                                  SearchResultsTab(colors: colors),
                                  InfoTab(
                                      colors: colors,
                                      selectedObject: selectedObject),
                                ],
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
          ],
        ),
        if (_showPopup && _popupObject != null)
          ObjectInfoPopup(
            colors: colors,
            object: _popupObject!,
            coordinates: _popupCoordinates ?? _popupObject!.coordinates,
            selectedObjectState: selectedObject,
            position: _popupPosition,
            onDismiss: _dismissPopup,
            onSendToFraming: _sendToFraming,
            onAddToSequencer: _addToSequencer,
            onSlewToTarget: _handleSlewToTarget,
            onSlewAndCenter: () => _handleSlewAndCenter(
              _popupCoordinates ?? _popupObject!.coordinates,
              _popupObject!.name,
            ),
            onSlewCenterRotate: () => _handleSlewCenterRotate(
              _popupCoordinates ?? _popupObject!.coordinates,
              _popupObject!.name,
            ),
            onExportChart: () => _exportFinderChart(context),
            hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                DeviceConnectionState.connected,
          ),
        if (_showHelpOverlay)
          _KeyboardShortcutsOverlay(
            onDismiss: () => setState(() => _showHelpOverlay = false),
          ),
      ],
    );
  }
}

/// Help overlay showing all keyboard shortcuts
class _KeyboardShortcutsOverlay extends StatelessWidget {
  final VoidCallback onDismiss;

  const _KeyboardShortcutsOverlay({required this.onDismiss});

  void _consumeTap() {
    // Inner overlay absorbs taps so the outer scrim alone dismisses.
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: GestureDetector(
            onTap: _consumeTap,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Keyboard Shortcuts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x,
                            size: 18, color: Colors.white54),
                        onPressed: onDismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _ShortcutSection(title: 'Navigation', shortcuts: [
                    ('Arrow Keys', 'Pan view'),
                    ('+ / -', 'Zoom in / out'),
                    ('H', 'Home (reset view)'),
                  ]),
                  const SizedBox(height: 12),
                  const _ShortcutSection(title: 'Overlays', shortcuts: [
                    ('G', 'Toggle coordinate grid'),
                    ('C', 'Toggle constellation lines'),
                    ('E', 'Toggle ecliptic'),
                    ('F', 'Toggle FOV overlay'),
                    ('M', 'Toggle mini-map'),
                  ]),
                  const SizedBox(height: 12),
                  const _ShortcutSection(title: 'Time', shortcuts: [
                    ('N', 'Jump to now (real-time)'),
                    ('Space', 'Play / Pause time'),
                  ]),
                  const SizedBox(height: 12),
                  const _ShortcutSection(title: 'Other', shortcuts: [
                    ('Escape', 'Deselect / close overlay'),
                    ('?', 'Show this help'),
                  ]),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Press Escape or ? to close',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
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

class _ShortcutSection extends StatelessWidget {
  final String title;
  final List<(String, String)> shortcuts;

  const _ShortcutSection({required this.title, required this.shortcuts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF00E676),
          ),
        ),
        const SizedBox(height: 6),
        ...shortcuts.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        s.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
