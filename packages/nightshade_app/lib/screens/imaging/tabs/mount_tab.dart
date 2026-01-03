import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show MountStatus;
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import 'package:nightshade_core/nightshade_core.dart' show equipmentProfilesDaoProvider, slewCoordinatesProvider, CoordinateParser;
import '../centering_dialog.dart';

class MountTab extends ConsumerStatefulWidget {
  const MountTab({super.key});

  @override
  ConsumerState<MountTab> createState() => _MountTabState();
}

class _MountTabState extends ConsumerState<MountTab> {
  Timer? _statusTimer;
  MountStatus? _status;
  final bool _isLoading = false;
  String? _error;
  String? _deviceId;

  // Slew target inputs - initialized from provider in initState
  late final TextEditingController _raController;
  late final TextEditingController _decController;

  @override
  void initState() {
    super.initState();
    // Initialize controllers from provider state synchronously
    final coords = ref.read(slewCoordinatesProvider);
    _raController = TextEditingController(text: coords.raText);
    _decController = TextEditingController(text: coords.decText);

    // Add listeners to sync changes back to provider (persists across tab switches)
    _raController.addListener(_syncRaToProvider);
    _decController.addListener(_syncDecToProvider);

    _loadDeviceId();
    _startPolling();
  }

  void _syncRaToProvider() {
    final currentCoords = ref.read(slewCoordinatesProvider);
    if (currentCoords.raText != _raController.text) {
      ref.read(slewCoordinatesProvider.notifier).state =
          currentCoords.copyWith(raText: _raController.text);
    }
  }

  void _syncDecToProvider() {
    final currentCoords = ref.read(slewCoordinatesProvider);
    if (currentCoords.decText != _decController.text) {
      ref.read(slewCoordinatesProvider.notifier).state =
          currentCoords.copyWith(decText: _decController.text);
    }
  }

  Future<void> _loadDeviceId() async {
    final profilesDao = ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    if (mounted && activeProfile?.mountId != null) {
      setState(() {
        _deviceId = activeProfile!.mountId;
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _raController.removeListener(_syncRaToProvider);
    _decController.removeListener(_syncDecToProvider);
    _raController.dispose();
    _decController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchStatus();
    });
    _fetchStatus(); // Initial fetch
  }

  Future<void> _fetchStatus() async {
    if (_deviceId == null) return;
    try {
      final status = await bridge_api.apiGetMountStatus(deviceId: _deviceId!);
      if (mounted) {
        setState(() {
          _status = status as MountStatus?;
          _error = null;
        });
      }
    } catch (e) {
      // Don't spam errors on poll, just store last error if needed or log
      // setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleTracking(bool enabled) async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    try {
      await bridge_api.apiMountSetTracking(deviceId: _deviceId!, enabled: enabled ? 1 : 0);
      _fetchStatus();
    } catch (e) {
      _showError("Failed to set tracking: $e");
    }
  }

  Future<void> _abortSlew() async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    try {
      await bridge_api.mountAbort(deviceId: _deviceId!);
      _fetchStatus();
    } catch (e) {
      _showError("Failed to abort: $e");
    }
  }

  Future<void> _park() async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    try {
      await bridge_api.apiMountPark(deviceId: _deviceId!);
      _fetchStatus();
    } catch (e) {
      _showError("Failed to park: $e");
    }
  }

  Future<void> _unpark() async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    try {
      await bridge_api.apiMountUnpark(deviceId: _deviceId!);
      _fetchStatus();
    } catch (e) {
      _showError("Failed to unpark: $e");
    }
  }

  Future<void> _slew() async {
    if (_deviceId == null) {
      _showError("No mount connected. Please check equipment profile.");
      debugPrint('[MountTab] Slew failed: _deviceId is null');
      return;
    }
    // Parse RA/Dec using CoordinateParser which supports HMS/DMS formats
    final ra = CoordinateParser.parseRa(_raController.text);
    final dec = CoordinateParser.parseDec(_decController.text);
    if (ra == null || dec == null) {
      _showError("Invalid coordinates. Supported formats: decimal, HH:MM:SS, DD:MM:SS");
      debugPrint('[MountTab] Slew failed: Invalid coordinates (ra=$ra, dec=$dec) from "${_raController.text}", "${_decController.text}"');
      return;
    }
    try {
      debugPrint('[MountTab] Slewing to RA=$ra, Dec=$dec using deviceId=$_deviceId');
      await bridge_api.apiMountSlewToCoordinates(deviceId: _deviceId!, ra: ra, dec: dec);
      debugPrint('[MountTab] Slew command sent successfully');
    } catch (e, stack) {
      _showError("Slew failed: $e");
      debugPrint('[MountTab] Slew failed with error: $e\n$stack');
    }
  }

  Future<void> _sync() async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    // Parse RA/Dec using CoordinateParser which supports HMS/DMS formats
    final ra = CoordinateParser.parseRa(_raController.text);
    final dec = CoordinateParser.parseDec(_decController.text);
    if (ra == null || dec == null) {
      _showError("Invalid coordinates. Supported formats: decimal, HH:MM:SS, DD:MM:SS");
      return;
    }
    try {
      await bridge_api.apiMountSyncToCoordinates(deviceId: _deviceId!, ra: ra, dec: dec);
    } catch (e) {
      _showError("Sync failed: $e");
    }
  }

  Future<void> _pulseGuide(String direction) async {
    if (_deviceId == null) {
      _showError("No mount connected");
      return;
    }
    try {
      await bridge_api.apiMountPulseGuide(deviceId: _deviceId!, direction: direction, durationMs: 500);
    } catch (e) {
      _showError("Pulse guide failed: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Status Card
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mount Status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (_status != null)
                        _StatusBadge(
                          label: _status!.slewing ? 'SLEWING' : (_status!.tracking ? 'TRACKING' : 'STOPPED'),
                          color: _status!.slewing 
                              ? colors.warning 
                              : (_status!.tracking ? colors.success : colors.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _InfoRow(label: 'RA', value: _status?.rightAscension.toStringAsFixed(4) ?? '--')),
                      const SizedBox(width: 16),
                      Expanded(child: _InfoRow(label: 'Dec', value: _status?.declination.toStringAsFixed(4) ?? '--')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _InfoRow(label: 'Alt', value: _status?.altitude.toStringAsFixed(2) ?? '--')),
                      const SizedBox(width: 16),
                      Expanded(child: _InfoRow(label: 'Az', value: _status?.azimuth.toStringAsFixed(2) ?? '--')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _InfoRow(label: 'Pier', value: _status?.sideOfPier.toString().split('.').last ?? '--')),
                      const SizedBox(width: 16),
                      Expanded(child: _InfoRow(label: 'LST', value: _status?.siderealTime.toStringAsFixed(4) ?? '--')),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Control Actions
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeButton(
                          label: _status?.parked == true ? 'Unpark' : 'Park',
                          icon: LucideIcons.parkingSquare,
                          variant: ButtonVariant.outline,
                          onPressed: _status?.parked == true ? _unpark : _park,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: _status?.tracking == true ? 'Stop Track' : 'Start Track',
                          icon: LucideIcons.activity,
                          variant: _status?.tracking == true ? ButtonVariant.outline : ButtonVariant.primary,
                          onPressed: () => _toggleTracking(!(_status?.tracking ?? false)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      label: 'ABORT SLEW',
                      icon: LucideIcons.octagon,
                      variant: ButtonVariant.primary,
                      onPressed: _abortSlew,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Alignment
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alignment',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      label: 'Three-Point Polar Alignment',
                      icon: LucideIcons.compass,
                      variant: ButtonVariant.outline,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            backgroundColor: colors.surface,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
                              child: const PolarAlignmentWizard(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Slew/Sync
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GoTo / Sync',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeTextField(
                          hint: 'RA (Hours)',
                          initialValue: _raController.text,
                          onChanged: (value) {
                            _raController.text = value;
                            ref.read(slewCoordinatesProvider.notifier).state =
                                ref.read(slewCoordinatesProvider).copyWith(raText: value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeTextField(
                          hint: 'Dec (Deg)',
                          initialValue: _decController.text,
                          onChanged: (value) {
                            _decController.text = value;
                            ref.read(slewCoordinatesProvider.notifier).state =
                                ref.read(slewCoordinatesProvider).copyWith(decText: value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeButton(
                          label: 'Slew',
                          icon: LucideIcons.move,
                          onPressed: _slew,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: 'Sync',
                          icon: LucideIcons.refreshCw,
                          variant: ButtonVariant.outline,
                          onPressed: _sync,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      label: 'Center Target',
                      icon: LucideIcons.target,
                      variant: ButtonVariant.primary,
                      onPressed: () {
                        // Parse using CoordinateParser for HMS/DMS support
                        final ra = CoordinateParser.parseRa(_raController.text);
                        final dec = CoordinateParser.parseDec(_decController.text);
                        showDialog(
                          context: context,
                          builder: (context) => CenteringDialog(
                            targetRa: ra,
                            targetDec: dec,
                            targetName: 'Manual Coordinates',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Pulse Guide
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pulse Guide',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        _PulseButton(icon: LucideIcons.chevronUp, label: "N", onPressed: () => _pulseGuide("North")),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PulseButton(icon: LucideIcons.chevronLeft, label: "W", onPressed: () => _pulseGuide("West")),
                            const SizedBox(width: 48),
                            _PulseButton(icon: LucideIcons.chevronRight, label: "E", onPressed: () => _pulseGuide("East")),
                          ],
                        ),
                        _PulseButton(icon: LucideIcons.chevronDown, label: "S", onPressed: () => _pulseGuide("South")),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textPrimary)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _PulseButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PulseButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Column(
      children: [
        Material(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(icon, color: colors.primary),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: colors.textSecondary)),
      ],
    );
  }
}
