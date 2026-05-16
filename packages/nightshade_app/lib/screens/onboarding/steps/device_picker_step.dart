import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Reusable device-picker step body shared between Camera / Mount /
/// Focuser / Filter Wheel / Guider onboarding steps.
///
/// Plugs into the real [unifiedDiscoveryProvider] so the listed devices
/// come from an actual discovery run (Native SDK / ASCOM / Alpaca /
/// INDI), not a fixture. The selected driver subset persisted in
/// [onboardingDraftProvider] gates which backends discovery runs against.
///
/// Why one widget for many device types: every device type has the same
/// "scan → list → pick → connect-optional" affordance. Cloning this five
/// times would diverge over time. The caller passes a [deviceType] and
/// callbacks for when the user picks/clears a device.
class OnboardingDevicePickerBody extends ConsumerStatefulWidget {
  const OnboardingDevicePickerBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.deviceType,
    required this.selectedDeviceId,
    required this.selectedDeviceName,
    required this.onSelected,
    required this.onCleared,
    this.allowSkip = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final DeviceType deviceType;
  final String? selectedDeviceId;
  final String? selectedDeviceName;
  final void Function(UnifiedDevice device) onSelected;
  final VoidCallback onCleared;

  /// True for steps that should render an explicit "Skip this device"
  /// affordance (focuser, filter wheel, guider).
  final bool allowSkip;

  @override
  ConsumerState<OnboardingDevicePickerBody> createState() =>
      _OnboardingDevicePickerBodyState();
}

class _OnboardingDevicePickerBodyState
    extends ConsumerState<OnboardingDevicePickerBody> {
  bool _scanRequested = false;

  @override
  void initState() {
    super.initState();
    // Kick discovery off the first time the step renders so the user
    // doesn't have to hit "Scan" on every step. We schedule it post-
    // frame because [_runDiscovery] reads providers — calling it during
    // the build/initState pass would error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scanRequested) return;
      _runDiscovery();
    });
  }

  Future<void> _runDiscovery() async {
    if (!mounted) return;
    setState(() => _scanRequested = true);
    // discoverAll() pings every available backend. The discovery state
    // notifier batches the results so the rest of the UI updates as
    // each backend finishes — we don't need to await for individual
    // device types here.
    await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    final discovery = ref.watch(unifiedDiscoveryProvider);
    final draft = ref.watch(onboardingDraftProvider);

    // Filter the unified devices by:
    //   1. The requested DeviceType (camera/mount/etc.)
    //   2. The user's chosen driver subset (so a user who unchecked INDI
    //      doesn't see INDI-only devices in the list).
    final allDevices = discovery.getDevicesByType(widget.deviceType);
    final selectedDrivers = draft.selectedDrivers;
    final devices = allDevices.where((device) {
      // Keep the device if it has at least one backend in the user's
      // selected driver set; otherwise we'd surface a device the user
      // can't actually connect to.
      return device.availableBackends.keys.any(selectedDrivers.contains);
    }).toList();

    final isDiscovering = discovery.isDiscovering;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, color: colors.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Scan controls
        Row(
          children: [
            NightshadeButton(
              icon: LucideIcons.refreshCw,
              label: isDiscovering ? 'Scanning...' : 'Scan again',
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: isDiscovering ? null : _runDiscovery,
            ),
            const SizedBox(width: 12),
            if (widget.selectedDeviceId != null)
              NightshadeButton(
                icon: LucideIcons.x,
                label: 'Clear selection',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: widget.onCleared,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Per-backend status (so the user understands why some lists are
        // empty — e.g. INDI server unreachable).
        _BackendStatusRow(discovery: discovery, drivers: selectedDrivers),

        const SizedBox(height: 12),

        // Device list
        Expanded(
          child: _DeviceList(
            devices: devices,
            isDiscovering: isDiscovering,
            selectedDeviceId: widget.selectedDeviceId,
            onSelected: widget.onSelected,
          ),
        ),

        if (widget.allowSkip) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No matching device? You can skip this step and add it later from the Equipment screen.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BackendStatusRow extends StatelessWidget {
  const _BackendStatusRow({required this.discovery, required this.drivers});

  final UnifiedDiscoveryState discovery;
  final Set<DriverType> drivers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    final entries = drivers
        .map((d) => MapEntry(d, discovery.backendStates[d]))
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: entries.map((entry) {
        final driver = entry.key;
        final state = entry.value;
        IconData icon;
        Color color;
        String label = driver.shortLabel;
        String? tooltipMessage;

        if (state == null) {
          icon = LucideIcons.circle;
          color = colors.textMuted;
          tooltipMessage = 'Not scanned yet';
        } else {
          switch (state.status) {
            case DiscoveryStatus.idle:
              icon = LucideIcons.circle;
              color = colors.textMuted;
              break;
            case DiscoveryStatus.discovering:
              icon = LucideIcons.loader;
              color = colors.primary;
              break;
            case DiscoveryStatus.completed:
              icon = LucideIcons.checkCircle2;
              color = colors.success;
              label = '${driver.shortLabel} (${state.devices.length})';
              break;
            case DiscoveryStatus.error:
              icon = LucideIcons.alertTriangle;
              color = colors.error;
              tooltipMessage = state.error ?? 'Discovery failed';
              break;
          }
        }

        final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        );

        if (tooltipMessage == null) return chip;
        return Tooltip(message: tooltipMessage, child: chip);
      }).toList(),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.isDiscovering,
    required this.selectedDeviceId,
    required this.onSelected,
  });

  final List<UnifiedDevice> devices;
  final bool isDiscovering;
  final String? selectedDeviceId;
  final void Function(UnifiedDevice device) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDiscovering ? LucideIcons.loader : LucideIcons.searchX,
                color: colors.textMuted,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                isDiscovering
                    ? 'Scanning for devices...'
                    : 'No devices found. Make sure your device is connected and powered on, then try Scan again.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final device = devices[index];
        // Selection match is done on activeDeviceId (the id of the
        // recommended backend) so re-selecting through "Use this device"
        // keeps the same backend the user previously chose.
        final isSelected = device.activeDeviceId == selectedDeviceId;
        return InkWell(
          onTap: () => onSelected(device),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.08)
                  : colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.4)
                    : colors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? LucideIcons.checkCircle2
                      : LucideIcons.circle,
                  color:
                      isSelected ? colors.primary : colors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.availableBackends.keys
                            .map((b) => b.shortLabel)
                            .join(' / '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
