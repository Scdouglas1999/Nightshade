import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'device_card.dart';

class MountControlPanel extends ConsumerStatefulWidget {
  final MountState mountState;
  final AsyncValue<List<DeviceInfo>> availableMounts;
  final NightshadeColors colors;

  const MountControlPanel({
    super.key,
    required this.mountState,
    required this.availableMounts,
    required this.colors,
  });

  @override
  ConsumerState<MountControlPanel> createState() => _MountControlPanelState();
}

enum _CoordMode { equatorial, horizontal }

class _MountControlPanelState extends ConsumerState<MountControlPanel> {
  String? _selectedDeviceId;
  bool _isSolving = false;
  bool _isFindingHome = false;
  _CoordMode _coordMode = _CoordMode.equatorial;
  final _raController = TextEditingController();
  final _decController = TextEditingController();
  final _altController = TextEditingController();
  final _azController = TextEditingController();

  bool get _isConnected =>
      widget.mountState.connectionState == DeviceConnectionState.connected;

  @override
  void dispose() {
    _raController.dispose();
    _decController.dispose();
    _altController.dispose();
    _azController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusDetails = <String>[];
    if (_isConnected && widget.mountState.ra != null) {
      statusDetails.add('RA: ${widget.mountState.ra!.toStringAsFixed(2)}h');
      statusDetails.add('Dec: ${widget.mountState.dec!.toStringAsFixed(1)}°');
    } else {
      statusDetails.addAll(['RA: ---', 'Dec: ---']);
    }

    return Column(
      children: [
        DeviceCard(
          title: 'Mount',
          deviceType: DeviceType.mount,
          isConnected: _isConnected,
          selectedDevice: _selectedDeviceId,
          availableDevices:
              widget.availableMounts.valueOrNull?.map((d) => d.id).toList() ??
                  [],
          onDeviceSelected: (id) => setState(() => _selectedDeviceId = id),
          onConnect: _handleConnect,
          onDisconnect: _handleDisconnect,
          statusWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getStatusLabel(),
                style: TextStyle(
                  color: _isConnected
                      ? widget.colors.success
                      : widget.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              ...statusDetails.map((detail) => Text(detail)),
            ],
          ),
        ),
        if (_isConnected) ...[
          const SizedBox(height: 16),
          _buildControls(),
        ],
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Controls',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: widget.mountState.isParked ? 'Unpark' : 'Park',
                  icon: LucideIcons.parkingSquare,
                  variant: ButtonVariant.outline,
                  onPressed: () async {
                    final result = await ref
                        .read(mountCommandServiceProvider)
                        .togglePark();
                    if (!mounted) return;
                    context.showCommandActionResult(result);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NightshadeButton(
                  label: widget.mountState.isTracking ? 'Stop Track' : 'Track',
                  icon: LucideIcons.activity,
                  variant: widget.mountState.isTracking
                      ? ButtonVariant.primary
                      : ButtonVariant.outline,
                  onPressed: () async {
                    final result = await ref
                        .read(mountCommandServiceProvider)
                        .toggleTracking();
                    if (!mounted) return;
                    context.showCommandActionResult(result);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NightshadeButton(
                  label: 'Home',
                  icon: LucideIcons.home,
                  variant: ButtonVariant.outline,
                  isLoading: _isFindingHome,
                  onPressed: _isFindingHome ? null : _handleFindHome,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSlewSection(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: _isSolving ? 'Solving...' : 'Plate Solve & Sync',
              icon: _isSolving ? null : LucideIcons.target,
              variant: ButtonVariant.primary,
              isLoading: _isSolving,
              onPressed: _isSolving ? null : _handlePlateSolveAndSync,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Slew To',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: widget.colors.textSecondary,
              ),
            ),
            const Spacer(),
            SegmentedButton<_CoordMode>(
              segments: const [
                ButtonSegment(
                  value: _CoordMode.equatorial,
                  label: Text('RA/Dec'),
                ),
                ButtonSegment(
                  value: _CoordMode.horizontal,
                  label: Text('Alt/Az'),
                ),
              ],
              selected: {_coordMode},
              onSelectionChanged: (modes) {
                setState(() => _coordMode = modes.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_coordMode == _CoordMode.equatorial) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _raController,
                  decoration: InputDecoration(
                    labelText: 'RA (hours)',
                    hintText: '12.345',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: widget.colors.textSecondary),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _decController,
                  decoration: InputDecoration(
                    labelText: 'Dec (deg)',
                    hintText: '+45.67',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: widget.colors.textSecondary),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _altController,
                  decoration: InputDecoration(
                    labelText: 'Alt (deg)',
                    hintText: '45.0',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: widget.colors.textSecondary),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _azController,
                  decoration: InputDecoration(
                    labelText: 'Az (deg)',
                    hintText: '180.0',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: widget.colors.textSecondary),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: NightshadeButton(
            label: 'Slew',
            icon: LucideIcons.navigation,
            variant: ButtonVariant.primary,
            onPressed: widget.mountState.isSlewing ? null : _handleSlew,
          ),
        ),
      ],
    );
  }

  String _getStatusLabel() {
    if (widget.mountState.isSlewing) return 'Slewing';
    if (widget.mountState.isParked) return 'Parked';
    if (widget.mountState.isTracking) return 'Tracking';
    if (_isConnected) return 'Ready';
    return 'Idle';
  }

  Future<void> _handleFindHome() async {
    setState(() => _isFindingHome = true);
    try {
      final result = await ref.read(mountCommandServiceProvider).findHome();
      if (mounted) {
        context.showCommandActionResult(result);
      }
    } finally {
      if (mounted) setState(() => _isFindingHome = false);
    }
  }

  Future<void> _handleSlew() async {
    if (_coordMode == _CoordMode.equatorial) {
      final ra = double.tryParse(_raController.text);
      final dec = double.tryParse(_decController.text);
      if (ra == null || dec == null) {
        context.showErrorSnackBar('Enter valid RA (hours) and Dec (degrees)');
        return;
      }
      final result =
          await ref.read(mountCommandServiceProvider).slewTo(ra, dec);
      if (mounted) context.showCommandActionResult(result);
    } else {
      final alt = double.tryParse(_altController.text);
      final az = double.tryParse(_azController.text);
      if (alt == null || az == null) {
        context.showErrorSnackBar('Enter valid Altitude and Azimuth (degrees)');
        return;
      }
      final result =
          await ref.read(mountCommandServiceProvider).slewToAltAz(alt, az);
      if (mounted) context.showCommandActionResult(result);
    }
  }

  Future<void> _handleConnect() async {
    if (_selectedDeviceId == null) return;

    try {
      await ref.read(deviceServiceProvider).connectMount(_selectedDeviceId!);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to connect: $e');
      }
    }
  }

  Future<void> _handleDisconnect() async {
    await ref.read(deviceServiceProvider).disconnectMount();
  }

  Future<void> _handlePlateSolveAndSync() async {
    setState(() => _isSolving = true);

    try {
      // 1. Capture Image
      final imagingService = ref.read(imagingServiceProvider);
      // Use user-configured settings with short exposure for plate solving
      final userSettings = ref.read(exposureSettingsProvider);
      final settings = ExposureSettings(
        exposureTime: 2.0, // 2 seconds for quick solve
        gain: userSettings.gain,
        offset: userSettings.offset,
        binningX: userSettings.binningX > 0 ? userSettings.binningX : 2,
        binningY: userSettings.binningY > 0 ? userSettings.binningY : 2,
        frameType: FrameType.light,
      );

      final image = await imagingService.captureImage(
        settings: settings,
        targetName: 'Plate Solve',
      );

      if (image == null || image.filePath == null) {
        throw Exception('Failed to capture image');
      }

      // 2. Plate Solve
      final plateSolveService = ref.read(plateSolveServiceProvider);
      // PlateSolveService tries backend.plateSolve() first (works for both local and remote)
      // Only falls back to local solver if backend fails

      // Get ASTAP path from app settings for local fallback
      final appSettings = ref.read(appSettingsProvider).value;
      final executablePath =
          await PlateSolverUtils.findAstapExecutable(appSettings?.astapPath);

      final result =
          (widget.mountState.ra != null && widget.mountState.dec != null)
              ? await plateSolveService.solve(
                  image.filePath!,
                  PlateSolverConfig(
                    type: PlateSolverType.astap,
                    hintRa: widget.mountState.ra,
                    hintDec: widget.mountState.dec,
                    searchRadius: 10.0, // 10 degrees search
                    // Provide path for local fallback - backend is tried first
                    executablePath: executablePath ?? '',
                  ),
                )
              : await plateSolveService.solve(
                  image.filePath!,
                  PlateSolverConfig(
                    type: PlateSolverType.astap,
                    // Provide path for local fallback - backend is tried first
                    executablePath: executablePath ?? '',
                    searchRadius: 180.0, // Blind solve
                  ),
                );

      if (!result.success) {
        throw Exception('Plate solving failed: ${result.error}');
      }

      // 3. Sync Mount and show typed feedback in UI layer.
      final syncResult = await ref
          .read(mountCommandServiceProvider)
          .sync(result.ra, result.dec);
      if (mounted) {
        context.showCommandActionResult(syncResult);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSolving = false);
    }
  }
}
