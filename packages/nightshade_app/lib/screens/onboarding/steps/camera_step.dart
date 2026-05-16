import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'device_picker_step.dart';

/// Camera selection step. Picks a camera via the unified discovery
/// pipeline. The driver-reported display name is captured so the profile
/// row has a friendly label even before connection.
class OnboardingCameraStep extends ConsumerWidget {
  const OnboardingCameraStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);

    return OnboardingDevicePickerBody(
      title: 'Pick your camera',
      subtitle:
          'Cameras discovered through the drivers you selected appear here. The brand is reported by the driver itself.',
      icon: LucideIcons.camera,
      deviceType: DeviceType.camera,
      selectedDeviceId: draft.cameraId,
      selectedDeviceName: draft.cameraName,
      onSelected: (device) => notifier.setCamera(
        id: device.activeDeviceId,
        name: device.displayName,
      ),
      onCleared: () => notifier.setCamera(id: '', name: ''),
    );
  }
}
