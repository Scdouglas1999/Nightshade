import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Wraps the app shell and routes a brand-new user (no profiles, no
/// onboarding completion record) into `/onboarding` on first launch.
///
/// Why a launcher widget rather than a router redirect: GoRouter
/// redirects fire on every navigation, and we only want to forcibly
/// route on the first frame after app launch. Inside the launcher we
/// also defer the check so any higher-priority startup dialogs
/// (database recovery, session recovery) get to render first.
class EquipmentOnboardingLauncher extends ConsumerStatefulWidget {
  final Widget child;

  const EquipmentOnboardingLauncher({super.key, required this.child});

  @override
  ConsumerState<EquipmentOnboardingLauncher> createState() =>
      _EquipmentOnboardingLauncherState();
}

class _EquipmentOnboardingLauncherState
    extends ConsumerState<EquipmentOnboardingLauncher> {
  bool _hasChecked = false;
  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  void _scheduleCheck() {
    if (_hasChecked || !mounted) return;
    // Defer by 800 ms so that DatabaseRecoveryLauncher and any session
    // recovery flow get to claim the navigator first. Once those flows
    // have rendered, the navigator is stable enough to push /onboarding.
    _deferTimer = Timer(const Duration(milliseconds: 800), _maybeLaunch);
  }

  Future<void> _maybeLaunch() async {
    if (_hasChecked || !mounted) return;
    _hasChecked = true;

    final shouldRun =
        await ref.read(shouldRunEquipmentOnboardingProvider.future);
    if (!shouldRun || !mounted) return;

    // Only auto-launch if the user is still parked on the default
    // dashboard route — otherwise they navigated somewhere themselves
    // and we shouldn't yank them away.
    final router = GoRouter.of(context);
    final currentLocation =
        router.routerDelegate.currentConfiguration.uri.toString();
    if (currentLocation == '/' || currentLocation == '/dashboard') {
      router.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
