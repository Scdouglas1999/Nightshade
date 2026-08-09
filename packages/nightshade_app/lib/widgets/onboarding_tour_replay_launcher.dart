import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'onboarding/onboarding_overlay.dart';

/// Mounts the [OnboardingOverlay] above the app shell whenever the first-launch
/// tour's persisted status is [FirstLaunchTourStatus.pending].
///
/// ## Why this exists
///
/// Under the single-spine startup model (Onboarding & First-Light IA, C13) the
/// first-launch tour no longer auto-fires on a fresh install — the equipment
/// onboarding spine owns first-run setup. The tour is **replay-only**: Settings
/// → Help & Tutorials → "Re-run onboarding tour" calls
/// [OnboardingTourNotifier.reset], which flips the persisted status back to
/// pending and invalidates [firstLaunchTourStatusProvider].
///
/// This launcher is the consumer that closes that loop. It watches the status
/// provider and, on `pending`, overlays the tour on top of the running app so
/// the replay button actually shows the tour — without a restart and without
/// the tour ever auto-launching on first run. `pending` means "a replay was
/// explicitly requested and is unfinished"; a brand-new install has no row at
/// all and reads as [FirstLaunchTourStatus.notStarted], which does not mount
/// anything.
///
/// The overlay sits in a [Stack] above [child] (rather than as a route) so it
/// floats over whatever screen the user is on — exactly where the per-step
/// spotlight cutouts need to be to highlight the live navigation chrome. When
/// the user completes or skips the tour, [OnboardingTourNotifier] persists the
/// terminal status and invalidates the provider, so this launcher tears the
/// overlay down on the next rebuild.
class OnboardingTourReplayLauncher extends ConsumerWidget {
  final Widget child;

  const OnboardingTourReplayLauncher({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(firstLaunchTourStatusProvider);

    // Only overlay the tour on an explicit pending status. Loading and error
    // states fail closed to "do not show" — a tour is a non-critical nicety and
    // must never wedge the app or flash on a transient read error.
    final showTour = statusAsync.maybeWhen(
      data: (status) => status == FirstLaunchTourStatus.pending,
      orElse: () => false,
    );

    if (!showTour) {
      return child;
    }

    return Stack(
      children: [
        child,
        const Positioned.fill(
          child: OnboardingOverlay(),
        ),
      ],
    );
  }
}
