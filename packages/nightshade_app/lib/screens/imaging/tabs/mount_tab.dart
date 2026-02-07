import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        mountStateProvider,
        mountCapabilitiesProvider,
        slewCoordinatesProvider,
        CoordinateParser,
        DeviceConnectionState;
import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/slew_dropdown_button.dart';
import '../../polar_alignment/polar_alignment_screen.dart';

class MountTab extends ConsumerStatefulWidget {
  const MountTab({super.key});

  @override
  ConsumerState<MountTab> createState() => _MountTabState();
}

class _MountTabState extends ConsumerState<MountTab> {
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

  @override
  void dispose() {
    _raController.removeListener(_syncRaToProvider);
    _decController.removeListener(_syncDecToProvider);
    _raController.dispose();
    _decController.dispose();
    super.dispose();
  }

  /// Sync mount to coordinates from text fields with validation
  Future<void> _handleSync() async {
    final ra = CoordinateParser.parseRa(_raController.text);
    final dec = CoordinateParser.parseDec(_decController.text);
    if (ra == null || dec == null) {
      context.showErrorSnackBar(
          "Invalid coordinates. Supported formats: decimal, HH:MM:SS, DD:MM:SS");
      return;
    }
    final result = await ref.read(mountCommandServiceProvider).sync(ra, dec);
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final mountState = ref.watch(mountStateProvider);
    final isConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final isMobile = Responsive.isMobile(context);

    // Watch mount capabilities to gate UI features
    final capabilitiesAsync =
        ref.watch(mountCapabilitiesProvider(mountState.deviceId ?? ''));
    final capabilities = capabilitiesAsync.valueOrNull;
    final canTogglePark = isConnected &&
        (mountState.isParked
            ? (capabilities == null || capabilities.canUnpark)
            : (capabilities == null || capabilities.canPark));
    final canToggleTracking =
        isConnected && (capabilities == null || capabilities.canSetTracking);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                      if (isConnected)
                        _StatusBadge(
                          label: mountState.isSlewing
                              ? 'SLEWING'
                              : (mountState.isTracking
                                  ? 'TRACKING'
                                  : 'STOPPED'),
                          color: mountState.isSlewing
                              ? colors.warning
                              : (mountState.isTracking
                                  ? colors.success
                                  : colors.textSecondary),
                        ),
                      if (!isConnected)
                        _StatusBadge(
                          label: 'DISCONNECTED',
                          color: colors.error,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ResponsiveCoordinateGrid(
                    isMobile: isMobile,
                    children: [
                      _InfoRow(
                          label: 'RA',
                          value: mountState.ra?.toStringAsFixed(4) ?? '--'),
                      _InfoRow(
                          label: 'Dec',
                          value: mountState.dec?.toStringAsFixed(4) ?? '--'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ResponsiveCoordinateGrid(
                    isMobile: isMobile,
                    children: [
                      _InfoRow(
                          label: 'Alt',
                          value:
                              mountState.altitude?.toStringAsFixed(2) ?? '--'),
                      _InfoRow(
                          label: 'Az',
                          value:
                              mountState.azimuth?.toStringAsFixed(2) ?? '--'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ResponsiveCoordinateGrid(
                    isMobile: isMobile,
                    children: [
                      _InfoRow(
                          label: 'Pier', value: mountState.sideOfPier ?? '--'),
                      _InfoRow(
                          label: 'Status',
                          value: mountState.isParked ? 'Parked' : 'Ready'),
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
                          label: mountState.isParked ? 'Unpark' : 'Park',
                          icon: LucideIcons.parkingSquare,
                          variant: ButtonVariant.outline,
                          onPressed: canTogglePark
                              ? () async {
                                  final result = await ref
                                      .read(mountCommandServiceProvider)
                                      .togglePark();
                                  if (!context.mounted) return;
                                  context.showCommandActionResult(result);
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: mountState.isTracking
                              ? 'Stop Track'
                              : 'Start Track',
                          icon: LucideIcons.activity,
                          variant: mountState.isTracking
                              ? ButtonVariant.outline
                              : ButtonVariant.primary,
                          onPressed: canToggleTracking
                              ? () async {
                                  final result = await ref
                                      .read(mountCommandServiceProvider)
                                      .setTracking(!mountState.isTracking);
                                  if (!context.mounted) return;
                                  context.showCommandActionResult(result);
                                }
                              : null,
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
                      onPressed: isConnected
                          ? () async {
                              final result = await ref
                                  .read(mountCommandServiceProvider)
                                  .abortSlew();
                              if (!context.mounted) return;
                              context.showCommandActionResult(result);
                            }
                          : null,
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
                              constraints: const BoxConstraints(
                                  maxWidth: 800, maxHeight: 600),
                              child: const PolarAlignmentScreen(),
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
                                ref
                                    .read(slewCoordinatesProvider)
                                    .copyWith(raText: value);
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
                                ref
                                    .read(slewCoordinatesProvider)
                                    .copyWith(decText: value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            // Parse coordinates for the slew dropdown
                            final ra =
                                CoordinateParser.parseRa(_raController.text);
                            final dec =
                                CoordinateParser.parseDec(_decController.text);
                            final hasValidCoords = ra != null && dec != null;

                            if (!hasValidCoords) {
                              // Show disabled button if coordinates are invalid
                              return const NightshadeButton(
                                label: 'Slew',
                                icon: LucideIcons.move,
                                // onPressed null makes button appear disabled
                                onPressed: null,
                              );
                            }

                            return SlewDropdownButton(
                              ra: ra,
                              dec: dec,
                              targetName: 'Manual Coordinates',
                              // No rotation from manual coordinate entry
                              targetRotation: null,
                              isEnabled: isConnected,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: 'Sync',
                          icon: LucideIcons.refreshCw,
                          variant: ButtonVariant.outline,
                          onPressed: _handleSync,
                        ),
                      ),
                    ],
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
                        _PulseButton(
                            icon: LucideIcons.chevronUp,
                            label: "N",
                            onPressed: () async {
                              final result = await ref
                                  .read(mountCommandServiceProvider)
                                  .pulseGuide("North");
                              if (!context.mounted) return;
                              context.showCommandActionResult(result);
                            }),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PulseButton(
                                icon: LucideIcons.chevronLeft,
                                label: "W",
                                onPressed: () async {
                                  final result = await ref
                                      .read(mountCommandServiceProvider)
                                      .pulseGuide("West");
                                  if (!context.mounted) return;
                                  context.showCommandActionResult(result);
                                }),
                            const SizedBox(width: 48),
                            _PulseButton(
                                icon: LucideIcons.chevronRight,
                                label: "E",
                                onPressed: () async {
                                  final result = await ref
                                      .read(mountCommandServiceProvider)
                                      .pulseGuide("East");
                                  if (!context.mounted) return;
                                  context.showCommandActionResult(result);
                                }),
                          ],
                        ),
                        _PulseButton(
                            icon: LucideIcons.chevronDown,
                            label: "S",
                            onPressed: () async {
                              final result = await ref
                                  .read(mountCommandServiceProvider)
                                  .pulseGuide("South");
                              if (!context.mounted) return;
                              context.showCommandActionResult(result);
                            }),
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
        Text(label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          value,
          style: NightshadeTypography.monoSm.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
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
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _PulseButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PulseButton(
      {required this.icon, required this.label, required this.onPressed});

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
        Text(label,
            style: TextStyle(fontSize: 10, color: colors.textSecondary)),
      ],
    );
  }
}

/// Responsive grid layout for coordinate pairs.
/// On mobile, stacks children vertically; on desktop, shows them side-by-side.
class _ResponsiveCoordinateGrid extends StatelessWidget {
  final bool isMobile;
  final List<Widget> children;

  const _ResponsiveCoordinateGrid({
    required this.isMobile,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      // Stack vertically on mobile with smaller spacing
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }
    // Side-by-side on desktop
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) const SizedBox(width: 16),
        ],
      ],
    );
  }
}
