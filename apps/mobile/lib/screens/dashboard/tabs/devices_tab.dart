import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart'
    show GuideHealthCard, FocusModelCurveCard;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/error_snackbar.dart';

/// Devices tab — one row per device class (camera, mount, focuser, filter
/// wheel, guider), with connection status and connect/disconnect controls.
///
/// Reads the equipment state notifiers from nightshade_core; the actual
/// connect/disconnect work routes through DeviceService so this tab stays
/// stateless. Why each card is its own widget: the cards subscribe to
/// different providers and rebuilding all of them on a single state change
/// thrashes the connected-device polling timers.
class DevicesTab extends ConsumerWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Re-enumerate devices on the backend; the per-device state
        // notifiers pick up whatever the rescan surfaces. Refresh the host
        // focus snapshot too so the focus card's retry copy is actionable.
        try {
          await ref.read(deviceBackendProvider).rescanDevices();
          if (ref.read(isRemoteModeProvider) && activeProfile != null) {
            final profileData = focusProfileDataProvider(
              activeProfile.id.toString(),
            );
            ref.invalidate(profileData);
            await ref.read(profileData.future);
          }
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeProfile == null)
            const _NoProfileBanner()
          else
            _ProfileSummary(profile: activeProfile),
          const SizedBox(height: 12),
          const _CameraCard(),
          const SizedBox(height: 12),
          const _MountCard(),
          const SizedBox(height: 12),
          const _FocuserCard(),
          // Surface the temperature-compensation focus model when the focuser
          // and profile exist. A remote controller must not pre-gate this from
          // its own documents folder: the samples live on the imaging host and
          // FocusModelCurveCard fetches them over the backend-aware provider.
          // In local mode retain the old "only once data exists" gate.
          Consumer(
            builder: (context, ref, _) {
              final focuser = ref.watch(focuserStateProvider);
              final profile = ref.watch(activeEquipmentProfileProvider);
              if (focuser.connectionState != DeviceConnectionState.connected) {
                return const SizedBox.shrink();
              }
              if (profile == null) return const SizedBox.shrink();
              if (!ref.watch(isRemoteModeProvider)) {
                final focusData = ref.watch(
                  focusProfileDataProvider(profile.id.toString()),
                );
                if (focusData.valueOrNull?.dataPoints.isEmpty != false) {
                  return const SizedBox.shrink();
                }
              }
              return const Padding(
                padding: EdgeInsets.only(top: 12),
                child: FocusModelCurveCard(compact: true),
              );
            },
          ),
          const SizedBox(height: 12),
          const _FilterWheelCard(),
          const SizedBox(height: 12),
          const _GuiderCard(),
          // surface live guide-health (sparkline + RMS + state)
          // only when the guider is actually connected. The card hides
          // itself when disconnected too, but checking here keeps the
          // disconnected-state copy from duplicating _GuiderCard's
          // "Connect" call to action.
          Consumer(
            builder: (context, ref, _) {
              final guider = ref.watch(guiderStateProvider);
              if (guider.connectionState != DeviceConnectionState.connected) {
                return const SizedBox.shrink();
              }
              return const Padding(
                padding: EdgeInsets.only(top: 12),
                child: GuideHealthCard(),
              );
            },
          ),
          const SizedBox(height: 12),
          // Bottom padding above the safe-area inset so the last card is
          // not tucked against the bottom nav.
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NoProfileBanner extends StatelessWidget {
  const _NoProfileBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.warning,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No active equipment profile. Connect from the desktop or open '
              'the profile settings to pick one.',
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  final EquipmentProfileModel profile;
  const _ProfileSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.user, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared visual shell so each device card lines up regardless of state.
class _DeviceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final DeviceConnectionState state;
  final String? deviceName;
  final String? statusLine;
  final DeviceError? error;
  final Future<void> Function()? onConnect;
  final Future<void> Function()? onDisconnect;

  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.state,
    this.deviceName,
    this.statusLine,
    this.error,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  bool _actionInFlight = false;

  Future<void> _run(Future<void> Function()? action) async {
    if (action == null || _actionInFlight) return;
    setState(() => _actionInFlight = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isConnected = widget.state == DeviceConnectionState.connected;
    final isBusy =
        widget.state == DeviceConnectionState.connecting || _actionInFlight;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 20, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _StateChip(state: widget.state),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.deviceName ?? 'No device assigned',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          if (widget.statusLine != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.statusLine!,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.error!.message,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (isConnected)
                Expanded(
                  // 48 dp min height per HIG via ButtonSize.large.
                  child: NightshadeButton(
                    label: isBusy ? 'Disconnecting…' : 'Disconnect',
                    icon: LucideIcons.unplug,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.large,
                    isLoading: isBusy,
                    onPressed: isBusy ? null : () => _run(widget.onDisconnect),
                  ),
                )
              else
                Expanded(
                  child: NightshadeButton(
                    label: isBusy ? 'Connecting…' : 'Connect',
                    icon: isBusy ? null : LucideIcons.plug,
                    size: ButtonSize.large,
                    isLoading: isBusy,
                    onPressed: isBusy ? null : () => _run(widget.onConnect),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final DeviceConnectionState state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (label, color) = switch (state) {
      DeviceConnectionState.connected => ('Connected', colors.success),
      DeviceConnectionState.connecting => ('Connecting', colors.warning),
      DeviceConnectionState.disconnected => ('Offline', colors.textMuted),
      DeviceConnectionState.error => ('Error', colors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CameraCard extends ConsumerWidget {
  const _CameraCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraStateProvider);
    final service = ref.read(deviceServiceProvider);
    final profile = ref.read(activeEquipmentProfileProvider);

    String? status;
    if (state.connectionState == DeviceConnectionState.connected) {
      final temp = state.temperature;
      if (temp != null) {
        status =
            'Sensor ${temp.toStringAsFixed(1)} °C  '
            '${state.isCooling ? "cooling" : "warm"}';
      }
    }

    return _DeviceCard(
      icon: LucideIcons.camera,
      title: 'Camera',
      state: state.connectionState,
      deviceName: state.deviceName ?? profile?.cameraName,
      statusLine: status,
      error: state.lastError,
      onConnect: () async {
        final id = profile?.cameraId;
        if (id == null || id.isEmpty) {
          _showProfileMissing(context, 'camera');
          return;
        }
        try {
          await ref.read(cameraStateProvider.notifier).connect(id);
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
      onDisconnect: () async {
        try {
          await service.disconnectCamera();
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
    );
  }
}

class _MountCard extends ConsumerWidget {
  const _MountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mountStateProvider);
    final service = ref.read(deviceServiceProvider);
    final profile = ref.read(activeEquipmentProfileProvider);

    String? status;
    if (state.connectionState == DeviceConnectionState.connected) {
      final ra = state.ra;
      final dec = state.dec;
      if (ra != null && dec != null) {
        status =
            'RA ${_formatRa(ra)}  Dec ${_formatDec(dec)}  '
            '${state.isParked ? "parked" : (state.isTracking ? "tracking" : "idle")}';
      }
    }

    return _DeviceCard(
      icon: LucideIcons.move,
      title: 'Mount',
      state: state.connectionState,
      deviceName: state.deviceName ?? profile?.mountName,
      statusLine: status,
      error: state.lastError,
      onConnect: () async {
        final id = profile?.mountId;
        if (id == null || id.isEmpty) {
          _showProfileMissing(context, 'mount');
          return;
        }
        try {
          await ref.read(mountStateProvider.notifier).connect(id);
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
      onDisconnect: () async {
        try {
          await service.disconnectMount();
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
    );
  }
}

class _FocuserCard extends ConsumerWidget {
  const _FocuserCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(focuserStateProvider);
    final service = ref.read(deviceServiceProvider);
    final profile = ref.read(activeEquipmentProfileProvider);

    String? status;
    if (state.connectionState == DeviceConnectionState.connected) {
      final temp = state.temperature;
      final tempLabel = temp != null ? ' • ${temp.toStringAsFixed(1)} °C' : '';
      status = 'Position ${state.position ?? "?"}$tempLabel';
    }

    return _DeviceCard(
      icon: LucideIcons.focus,
      title: 'Focuser',
      state: state.connectionState,
      deviceName: state.deviceName ?? profile?.focuserName,
      statusLine: status,
      error: state.lastError,
      onConnect: () async {
        final id = profile?.focuserId;
        if (id == null || id.isEmpty) {
          _showProfileMissing(context, 'focuser');
          return;
        }
        try {
          await ref.read(focuserStateProvider.notifier).connect(id);
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
      onDisconnect: () async {
        try {
          await service.disconnectFocuser();
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
    );
  }
}

class _FilterWheelCard extends ConsumerWidget {
  const _FilterWheelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(filterWheelStateProvider);
    final service = ref.read(deviceServiceProvider);
    final profile = ref.read(activeEquipmentProfileProvider);

    String? status;
    if (state.connectionState == DeviceConnectionState.connected) {
      final filter = state.currentFilterName;
      status = filter != null
          ? 'Current filter: $filter'
          : 'Position ${state.currentPosition ?? "?"}';
    }

    return _DeviceCard(
      icon: LucideIcons.filter,
      title: 'Filter Wheel',
      state: state.connectionState,
      deviceName: state.deviceName ?? profile?.filterWheelName,
      statusLine: status,
      error: state.lastError,
      onConnect: () async {
        final id = profile?.filterWheelId;
        if (id == null || id.isEmpty) {
          _showProfileMissing(context, 'filter wheel');
          return;
        }
        try {
          await ref.read(filterWheelStateProvider.notifier).connect(id);
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
      onDisconnect: () async {
        try {
          await service.disconnectFilterWheel();
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
    );
  }
}

class _GuiderCard extends ConsumerWidget {
  const _GuiderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(guiderStateProvider);
    final service = ref.read(deviceServiceProvider);
    final profile = ref.read(activeEquipmentProfileProvider);

    String? status;
    if (state.connectionState == DeviceConnectionState.connected) {
      if (state.isGuiding && state.rmsTotal != null) {
        status = 'Guiding • RMS ${state.rmsTotal!.toStringAsFixed(2)}"';
      } else if (state.isCalibrating) {
        status = 'Calibrating';
      } else {
        status = 'Idle';
      }
    }

    return _DeviceCard(
      icon: LucideIcons.target,
      title: 'Guider',
      state: state.connectionState,
      deviceName: state.deviceName ?? profile?.guiderName,
      statusLine: status,
      error: state.lastError,
      onConnect: () async {
        final id = profile?.guiderId;
        if (id == null || id.isEmpty) {
          _showProfileMissing(context, 'guider');
          return;
        }
        try {
          await ref.read(guiderStateProvider.notifier).connect(id);
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
      onDisconnect: () async {
        try {
          await service.disconnectGuider();
        } catch (e) {
          if (context.mounted) _showError(context, e);
        }
      },
    );
  }
}

// [error parsing] — delegate to the shared helper so every
// devices-tab catch path benefits from envelope parsing + severity tint.
void _showError(BuildContext context, Object e) {
  showApiError(context, e);
}

void _showProfileMissing(BuildContext context, String deviceClass) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('No $deviceClass assigned in profile')),
  );
}

String _formatRa(double raHours) {
  final h = raHours.floor();
  final m = ((raHours - h) * 60).floor();
  return '${h}h ${m}m';
}

String _formatDec(double decDeg) {
  final sign = decDeg >= 0 ? '+' : '';
  return '$sign${decDeg.toStringAsFixed(1)}°';
}
