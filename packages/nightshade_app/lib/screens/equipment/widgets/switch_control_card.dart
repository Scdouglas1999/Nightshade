import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

/// Per-channel control for a connected multi-channel Switch / power box (dew
/// heaters, outlets, etc.).
///
/// Switches are not a [ConnectedDeviceType], so they get no standard device
/// card; the Equipment screen renders this card directly when a switch is
/// connected. Reads/writes go through [DeviceService] → SwitchChannelService,
/// which now works over the network as well as locally (the remote-switch fix),
/// so a tablet operator can toggle the rig's dew heaters / power outlets.
class SwitchControlCard extends ConsumerStatefulWidget {
  const SwitchControlCard({super.key});

  @override
  ConsumerState<SwitchControlCard> createState() => _SwitchControlCardState();
}

class _SwitchControlCardState extends ConsumerState<SwitchControlCard> {
  final _pending = <int>{};

  @override
  void initState() {
    super.initState();
    // Connect already refreshes channels, but a client that opens the screen
    // after the switch connected needs a pull to populate names/states.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceServiceProvider).refreshSwitchChannels();
    });
  }

  Future<void> _toggle(int index, bool value) async {
    setState(() => _pending.add(index));
    try {
      await ref.read(deviceServiceProvider).setSwitchChannel(index, value);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Switch failed: $e');
    } finally {
      if (mounted) setState(() => _pending.remove(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(switchStateProvider);
    if (state.connectionState != DeviceConnectionState.connected) {
      return const SizedBox.shrink();
    }
    final count = state.channelCount;
    final names = state.channelNames;
    final states = state.channelStates;

    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.power, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                state.deviceName ?? 'Switch',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(LucideIcons.refreshCw,
                    size: 16, color: colors.textMuted),
                tooltip: 'Refresh channels',
                onPressed: () =>
                    ref.read(deviceServiceProvider).refreshSwitchChannels(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (count == 0)
            Text('No channels reported',
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12))
          else
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (i < names.length && names[i].isNotEmpty)
                            ? names[i]
                            : 'Channel ${i + 1}',
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize13),
                      ),
                    ),
                    if (_pending.contains(i))
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Switch(
                        value: i < states.length && states[i],
                        onChanged: (v) => _toggle(i, v),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
