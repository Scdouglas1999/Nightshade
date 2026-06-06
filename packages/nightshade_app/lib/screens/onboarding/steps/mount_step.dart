import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'device_picker_step.dart';

class OnboardingMountStep extends ConsumerWidget {
  const OnboardingMountStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);

    return OnboardingDevicePickerBody(
      title: 'Pick your mount',
      subtitle:
          "Tracking mode and park position settings can be tuned later from the Equipment screen — we'll save sensible defaults for now.",
      icon: NightshadeIcons.compass,
      deviceType: DeviceType.mount,
      selectedDeviceId: draft.mountId,
      selectedDeviceName: draft.mountName,
      onSelected: (device) => notifier.setMount(
        id: device.activeDeviceId,
        name: device.displayName,
      ),
      onCleared: () => notifier.setMount(id: ''),
    );
  }
}
