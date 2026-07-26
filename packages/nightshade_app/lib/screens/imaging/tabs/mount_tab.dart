import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        MountCapabilities,
        mountStateProvider,
        equipmentMountCapabilitiesProvider,
        gateCapability,
        slewCoordinatesProvider,
        CoordinateParser,
        CoordinateUtils,
        DeviceConnectionState;
import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/slew_dropdown_button.dart';

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
    // Watch the persisted text state so validation and the command payload
    // rebuild on every edit. Reading only the TextEditingControllers inside a
    // Builder left the disabled/enabled state and captured coordinates stale.
    final slewCoordinates = ref.watch(slewCoordinatesProvider);
    final targetRa = CoordinateParser.parseRa(slewCoordinates.raText);
    final targetDec = CoordinateParser.parseDec(slewCoordinates.decText);
    final hasValidTarget = targetRa != null && targetDec != null;
    final isConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final isMobile = Responsive.isMobile(context);

    // Watch mount capabilities to gate UI features.
    //
    // Gated through the equipment capability provider which
    // returns a fail-closed boolean — a driver that refuses to report
    // `canPark` no longer ships a button that hits a "Not implemented"
    // path. While loading we keep buttons visible (`loadingDefault: true`)
    // so the UI does not flash empty on every tab switch.
    final mountCapsAsync = ref
        .watch(equipmentMountCapabilitiesProvider(mountState.deviceId ?? ''));
    final canPark = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canPark,
      loadingDefault: true,
    );
    final canUnpark = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canUnpark,
      loadingDefault: true,
    );
    final canSetTracking = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canSetTracking,
      loadingDefault: true,
    );
    final canAbortSlew = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canAbortSlew,
      loadingDefault: true,
    );
    final canSync = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canSync,
      loadingDefault: false,
    );
    final canSlew = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canSlew || c.canSlewAsync,
      loadingDefault: false,
    );
    final canPulseGuide = gateCapability<MountCapabilities>(
      mountCapsAsync,
      (c) => c.canPulseGuide,
      loadingDefault: false,
    );
    final mountCaps = mountCapsAsync.valueOrNull;
    final minimumPulseMs = mountCaps?.minPulseGuideMs?.ceil() ?? 1;
    final maximumPulseMs = mountCaps?.maxPulseGuideMs?.floor();
    final hasValidPulseRange = minimumPulseMs > 0 &&
        (maximumPulseMs == null || maximumPulseMs >= minimumPulseMs);
    var pulseDurationMs = 500;
    if (pulseDurationMs < minimumPulseMs) pulseDurationMs = minimumPulseMs;
    if (maximumPulseMs != null && pulseDurationMs > maximumPulseMs) {
      pulseDurationMs = maximumPulseMs;
    }
    final pulseControlsEnabled = isConnected &&
        canPulseGuide &&
        hasValidPulseRange &&
        !mountState.isParked &&
        !mountState.isSlewing;

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
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Mount Status',
                        style: NightshadeTypography.h5
                            .copyWith(color: colors.textPrimary),
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
                          // Mount RA is hours (0-24); render sexagesimal so
                          // astronomers read HH MM SS rather than raw decimals.
                          value: mountState.ra != null
                              ? CoordinateUtils.formatRA(mountState.ra!)
                              : '--'),
                      _InfoRow(
                          label: 'Dec',
                          // Mount Dec is degrees (-90..+90); render signed DMS.
                          value: mountState.dec != null
                              ? CoordinateUtils.formatDec(mountState.dec!)
                              : '--'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ResponsiveCoordinateGrid(
                    isMobile: isMobile,
                    children: [
                      _InfoRow(
                          label: 'Alt',
                          value: mountState.altitude != null
                              ? '${mountState.altitude!.toStringAsFixed(2)}°'
                              : '--'),
                      _InfoRow(
                          label: 'Az',
                          value: mountState.azimuth != null
                              ? '${mountState.azimuth!.toStringAsFixed(2)}°'
                              : '--'),
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
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeButton(
                          label: mountState.isParked ? 'Unpark' : 'Park',
                          icon: LucideIcons.parkingSquare,
                          variant: ButtonVariant.outline,
                          // Gate on canPark/canUnpark with
                          // fail-closed capability lookup — see
                          // gateCapability above.
                          onPressed: isConnected &&
                                  !mountState.isSlewing &&
                                  (mountState.isParked ? canUnpark : canPark)
                              ? () => ref
                                      .read(mountCommandServiceProvider)
                                      .togglePark()
                                      .then((result) {
                                    if (context.mounted) {
                                      context.showCommandActionResult(result);
                                    }
                                  })
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: mountState.isTracking
                              ? 'Stop Track'
                              : 'Start Track',
                          icon: NightshadeIcons.activity,
                          variant: mountState.isTracking
                              ? ButtonVariant.outline
                              : ButtonVariant.primary,
                          // Gate on canSetTracking capability.
                          onPressed: isConnected &&
                                  canSetTracking &&
                                  !mountState.isParked &&
                                  !mountState.isSlewing
                              ? () => ref
                                      .read(mountCommandServiceProvider)
                                      .setTracking(!mountState.isTracking)
                                      .then((result) {
                                    if (context.mounted) {
                                      context.showCommandActionResult(result);
                                    }
                                  })
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
                      // Gate on canAbortSlew. Drivers without
                      // abort support would otherwise stall the user when
                      // a runaway slew demands the panic button.
                      onPressed: isConnected && canAbortSlew
                          ? () => ref
                                  .read(mountCommandServiceProvider)
                                  .abortSlew()
                                  .then((result) {
                                if (context.mounted) {
                                  context.showCommandActionResult(result);
                                }
                              })
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
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      label: 'Three-Point Polar Alignment',
                      icon: NightshadeIcons.compass,
                      variant: ButtonVariant.outline,
                      onPressed: () => context.push('/polar-alignment'),
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
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
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
                        child: !hasValidTarget
                            ? const NightshadeButton(
                                label: 'Slew',
                                icon: NightshadeIcons.move,
                                onPressed: null,
                              )
                            : SlewDropdownButton(
                                ra: targetRa,
                                dec: targetDec,
                                targetName: 'Manual Coordinates',
                                // No rotation from manual coordinate entry
                                targetRotation: null,
                                isEnabled: isConnected &&
                                    canSlew &&
                                    !mountState.isParked &&
                                    !mountState.isSlewing,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NightshadeButton(
                          label: 'Sync',
                          icon: NightshadeIcons.refresh,
                          variant: ButtonVariant.outline,
                          onPressed: isConnected &&
                                  canSync &&
                                  hasValidTarget &&
                                  !mountState.isParked &&
                                  !mountState.isSlewing
                              ? _handleSync
                              : null,
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
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !isConnected
                        ? 'Connect a mount to send guide corrections.'
                        : !canPulseGuide
                            ? 'Pulse guiding is unavailable for this mount.'
                            : !hasValidPulseRange
                                ? 'The mount reported an invalid pulse-duration range.'
                                : mountState.isParked
                                    ? 'Unpark the mount before pulse guiding.'
                                    : mountState.isSlewing
                                        ? 'Pulse guiding is disabled during a slew.'
                                        : '$pulseDurationMs ms correction pulses',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        _PulseButton(
                            icon: NightshadeIcons.chevronUp,
                            label: "N",
                            onPressed: pulseControlsEnabled
                                ? () => ref
                                        .read(mountCommandServiceProvider)
                                        .pulseGuide(
                                          "north",
                                          durationMs: pulseDurationMs,
                                        )
                                        .then((result) {
                                      if (context.mounted) {
                                        context.showCommandActionResult(result);
                                      }
                                    })
                                : null),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PulseButton(
                                icon: NightshadeIcons.chevronLeft,
                                label: "W",
                                onPressed: pulseControlsEnabled
                                    ? () => ref
                                            .read(mountCommandServiceProvider)
                                            .pulseGuide(
                                              "west",
                                              durationMs: pulseDurationMs,
                                            )
                                            .then((result) {
                                          if (context.mounted) {
                                            context.showCommandActionResult(
                                                result);
                                          }
                                        })
                                    : null),
                            const SizedBox(width: 48),
                            _PulseButton(
                                icon: NightshadeIcons.chevronRight,
                                label: "E",
                                onPressed: pulseControlsEnabled
                                    ? () => ref
                                            .read(mountCommandServiceProvider)
                                            .pulseGuide(
                                              "east",
                                              durationMs: pulseDurationMs,
                                            )
                                            .then((result) {
                                          if (context.mounted) {
                                            context.showCommandActionResult(
                                                result);
                                          }
                                        })
                                    : null),
                          ],
                        ),
                        _PulseButton(
                            icon: NightshadeIcons.chevronDown,
                            label: "S",
                            onPressed: pulseControlsEnabled
                                ? () => ref
                                        .read(mountCommandServiceProvider)
                                        .pulseGuide(
                                          "south",
                                          durationMs: pulseDurationMs,
                                        )
                                        .then((result) {
                                      if (context.mounted) {
                                        context.showCommandActionResult(result);
                                      }
                                    })
                                : null),
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
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary)),
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}

class _PulseButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PulseButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final enabled = onPressed != null;
    return Column(
      children: [
        Material(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: enabled ? colors.primary : colors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                color: colors.textSecondary)),
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
