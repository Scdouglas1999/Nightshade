import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../screens/tutorial/first_night_wizard.dart';

/// Wraps the app shell and auto-opens the [FirstNightWizard] on first
/// launch when the user has never seen it.
///
/// "First launch" is defined precisely: there is no row in the
/// `tutorial_progress` table for the firstNight category. That means a
/// dismissed-forever or completed user never sees the wizard again (they
/// can still replay it from Settings → Help), and a user who closed it
/// mid-way via the X button sees it again next launch (we wipe progress
/// on the soft close so the wizard feels resumable, not nagging).
///
/// Why a wrapper widget instead of a hook inside QuickStartChecker: the
/// quick-start dialog is for returning users (it surfaces recent
/// sessions). The first-night wizard is for users with zero history. They
/// don't overlap in practice, but keeping them in separate widgets means
/// neither dialog hides the other if both qualify (the priority is
/// session recovery > quick start > first-night wizard — the wizard is
/// the lowest priority and only fires when nothing else has anything to
/// show).
class FirstNightWizardLauncher extends ConsumerStatefulWidget {
  final Widget child;

  const FirstNightWizardLauncher({super.key, required this.child});

  @override
  ConsumerState<FirstNightWizardLauncher> createState() =>
      _FirstNightWizardLauncherState();
}

class _FirstNightWizardLauncherState
    extends ConsumerState<FirstNightWizardLauncher> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    // Post-frame so the navigator is laid out before we push the dialog.
    // We don't start the DAO read in initState directly because the
    // database may not yet be initialized this early in the app lifecycle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_hasChecked || !mounted) return;
    _hasChecked = true;

    // Defer slightly so any higher-priority startup dialogs (session
    // recovery, quick start) get to render first. 1500 ms is long enough
    // for those flows to claim the dialog stack but short enough that a
    // first-night user perceives it as instant.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final shouldShow = await ref.read(shouldShowFirstNightProvider.future);
    if (!shouldShow || !mounted) return;

    // If any other dialog is already on top of the navigator, skip this
    // launch — the wizard will open on the next launch because we
    // haven't recorded any progress yet. ModalRoute.canPop is a cheap
    // proxy for "is something modal currently above us".
    if (ModalRoute.of(context)?.isCurrent != true) return;

    await FirstNightWizard.show(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
