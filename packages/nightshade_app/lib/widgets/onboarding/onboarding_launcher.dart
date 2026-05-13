import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show FirstLaunchTourStatus, firstLaunchTourStatusProvider;

import 'onboarding_overlay.dart';

/// Wraps the app body in a Stack and conditionally mounts the
/// [OnboardingOverlay] when the first-launch tour hasn't been completed
/// or skipped.
///
/// "First launch" here means the persistence layer reports
/// [FirstLaunchTourStatus.pending] — i.e. no row in `tutorial_progress`
/// for the firstLaunchTour category. Completed and skipped users never
/// see the overlay again automatically; they can re-run it from
/// Settings → Help & Tutorials.
///
/// The launcher is mounted in `app.dart` rather than inside the app
/// shell so it sits above every screen, including transient ones like
/// Settings and Polar Alignment. Mounting in the shell would defeat the
/// purpose for users whose router lands them on a non-shell route.
class OnboardingTourLauncher extends ConsumerWidget {
  final Widget child;

  /// When true, the launcher checks the persistence layer and only mounts
  /// the overlay if the tour is pending. When false, it always mounts the
  /// overlay — used by Settings → Help → "Re-run tutorial" via a wrapper
  /// that resets the DAO state first.
  ///
  /// Default true: production code uses the gated path; only widget
  /// tests and the Settings "Re-run" action override.
  final bool gated;

  const OnboardingTourLauncher({
    super.key,
    required this.child,
    this.gated = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(firstLaunchTourStatusProvider);

    // If gated and the status hasn't resolved yet, render the child
    // alone. We intentionally don't show a loading state — the overlay
    // is an additive UX hint and a brief "no overlay yet" frame is
    // strictly preferable to a spinner over the app shell.
    final shouldMount = !gated ||
        statusAsync.maybeWhen(
          data: (s) => s == FirstLaunchTourStatus.pending,
          orElse: () => false,
        );

    if (!shouldMount) {
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
