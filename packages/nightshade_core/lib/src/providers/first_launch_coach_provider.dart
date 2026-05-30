import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/tutorial_progress_dao.dart';
import 'tutorial_provider.dart' show tutorialProgressDaoProvider;

/// Stable category name for the rich progressive first-launch coach,
/// persisted in the `tutorial_progress` table. The coach overlay reads and
/// writes this row to decide whether to surface itself on a fresh install.
///
/// Deliberately distinct from the other onboarding flows' category strings
/// — `'equipmentOnboarding'` (the startup wizard), `'firstLaunchTour'` (the
/// lightweight spotlight tour), and `'firstNight'` (the modal wizard). Each
/// flow is completed or dismissed independently: a user who finishes the
/// equipment wizard may still benefit from the progressive coach, so the
/// coach owns its own persistence row and must never collide with the
/// others.
const String firstLaunchCoachCategory = 'firstLaunchCoach';

/// Persistence status of the first-launch coach.
///
/// Why a four-state enum rather than a bool: `unknown` lets the UI render
/// nothing while the DAO read is in flight, avoiding a frame where the coach
/// briefly mounts before persistence says it was already finished.
/// `completed` and `dismissed` are kept distinct because Settings → Help can
/// render different replay copy ("Replay" vs "Restart") and because the two
/// outcomes carry different intent — one user worked through the coach, the
/// other opted out — even though both suppress the auto-launch gate.
enum FirstLaunchCoachStatus {
  /// The DAO read has not returned yet — render nothing.
  unknown,

  /// No persisted row exists (or a row exists with neither flag set) — the
  /// coach should auto-show on launch.
  pending,

  /// The user worked through the coach to the end.
  completed,

  /// The user explicitly dismissed the coach without finishing.
  dismissed,
}

/// Thin wrapper around [TutorialProgressDao] that answers the questions the
/// first-launch coach needs — "should I auto-open?", "did the user dismiss
/// me?", "mark me done" — without the coach widget having to know the
/// category-name string or duplicate the completed/dismissed flag mapping.
///
/// Mirrors the established `FirstLaunchTourDao` pattern verbatim so the two
/// flows stay structurally identical and persistence behavior is obvious to
/// anyone who has read either one.
class FirstLaunchCoachDao {
  final TutorialProgressDao _dao;

  FirstLaunchCoachDao(this._dao);

  /// Resolve the coach's current persistence status from the backing row.
  ///
  /// A missing row maps to [FirstLaunchCoachStatus.pending] (fresh install).
  /// A row with `completed` set maps to [FirstLaunchCoachStatus.completed];
  /// `dismissed` maps to [FirstLaunchCoachStatus.dismissed]. A row that
  /// exists but has neither flag set — e.g. the user closed the app
  /// mid-coach before any terminal action — maps back to
  /// [FirstLaunchCoachStatus.pending] so the coach reappears next launch.
  Future<FirstLaunchCoachStatus> getStatus() async {
    final progress = await _dao.getProgress(firstLaunchCoachCategory);
    if (progress == null) {
      return FirstLaunchCoachStatus.pending;
    }
    if (progress.completed) {
      return FirstLaunchCoachStatus.completed;
    }
    if (progress.dismissed) {
      return FirstLaunchCoachStatus.dismissed;
    }
    return FirstLaunchCoachStatus.pending;
  }

  /// Mark the coach finished. After this, [getStatus] returns
  /// [FirstLaunchCoachStatus.completed] and the launch gate stays closed
  /// until [reset] is called.
  Future<void> markCompleted() {
    return _dao.markCompleted(firstLaunchCoachCategory);
  }

  /// Mark the coach dismissed — the user opted out before finishing.
  /// Recorded distinctly from [markCompleted] so Settings → Help can show
  /// different replay copy, but both suppress the auto-launch gate.
  Future<void> markDismissed() {
    return _dao.markDismissed(firstLaunchCoachCategory);
  }

  /// Wipe the coach's persisted progress so it auto-opens again on the next
  /// launch. Backs the Settings → Help "Re-run" action.
  Future<void> reset() {
    return _dao.resetProgress(firstLaunchCoachCategory);
  }
}

/// Provider for the first-launch coach DAO wrapper.
///
/// Built on top of [tutorialProgressDaoProvider] so it shares the same
/// underlying Drift database connection — no risk of the coach reading stale
/// state because it holds its own DAO instance.
final firstLaunchCoachDaoProvider = Provider<FirstLaunchCoachDao>((ref) {
  return FirstLaunchCoachDao(ref.watch(tutorialProgressDaoProvider));
});

/// Resolves the first-launch coach's current persistence status.
///
/// The coach launcher watches this provider; when it resolves to
/// [FirstLaunchCoachStatus.pending], the coach mounts. Widget code that
/// calls [FirstLaunchCoachDao.markCompleted] / [FirstLaunchCoachDao.markDismissed]
/// / [FirstLaunchCoachDao.reset] should `ref.invalidate` this provider
/// afterward so the launcher's gate re-resolves immediately without an app
/// restart.
final firstLaunchCoachStatusProvider =
    FutureProvider<FirstLaunchCoachStatus>((ref) {
  return ref.watch(firstLaunchCoachDaoProvider).getStatus();
});

/// Fresh-install gate for the first-launch coach.
///
/// Returns `true` only when the coach is [FirstLaunchCoachStatus.pending] —
/// i.e. it has neither been completed nor dismissed. Both terminal outcomes
/// close the gate, so the coach never re-fires on its own after the user has
/// finished or opted out.
final shouldShowFirstLaunchCoachProvider = FutureProvider<bool>((ref) async {
  final status = await ref.watch(firstLaunchCoachStatusProvider.future);
  return status == FirstLaunchCoachStatus.pending;
});
