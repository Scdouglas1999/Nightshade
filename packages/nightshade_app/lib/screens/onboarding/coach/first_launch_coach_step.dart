import 'package:nightshade_core/nightshade_core.dart' show ReadinessItemId;

/// Rich, presentation-layer content for one step of the first-launch coach.
///
/// Each step maps a single [ReadinessItemId] (the pure readiness signal from
/// `nightshade_core`) to the human-facing copy and the deep-link target the
/// coach uses to take the user straight to the screen that resolves it.
///
/// This model is intentionally pure Dart — no Flutter, no Riverpod, no
/// go_router types — so it can be unit-tested in isolation and reused by any
/// presentation layer. The copy here is *static*, written for first-launch
/// guidance, and is deliberately distinct from [ReadinessItem.detail], which is
/// state-dependent (it describes the user's *current* status, not why the step
/// matters or what action to take).
class FirstLaunchCoachStep {
  /// The readiness signal this coach step is teaching the user about.
  final ReadinessItemId id;

  /// One-line, action-oriented heading (e.g. `Set your observing location`).
  final String title;

  /// One-line explanation of why this step matters for imaging. Written in the
  /// second person and kept to a single sentence so it reads cleanly in a card.
  final String whyItMatters;

  /// Short call-to-action label for the step's primary button
  /// (e.g. `Set location`).
  final String actionLabel;

  /// go_router location the coach navigates to when the user takes the action.
  ///
  /// Any `?section=` query value here is verified by tests to exist in
  /// `kSettingsSectionIndex` (in `settings_screen.dart`), so a typo fails the
  /// build rather than silently deep-linking to the wrong settings page.
  final String deepLinkRoute;

  const FirstLaunchCoachStep({
    required this.id,
    required this.title,
    required this.whyItMatters,
    required this.actionLabel,
    required this.deepLinkRoute,
  });
}

/// The ordered set of first-launch coach steps.
///
/// Order is load-bearing: the coach walks the user through these in sequence
/// (critical hardware first, then the settings that make planning and
/// calibration correct, then focus). The list MUST cover every
/// [ReadinessItemId] exactly once — [stepFor] and the package tests both
/// enforce this, so adding a new readiness id without a coach step is a
/// surfaced error rather than a silent gap.
const List<FirstLaunchCoachStep> kFirstLaunchCoachSteps = <FirstLaunchCoachStep>[
  FirstLaunchCoachStep(
    id: ReadinessItemId.criticalDevices,
    title: 'Connect your camera and mount',
    whyItMatters:
        'Nothing can be captured or pointed until your camera (and ideally your mount) are connected through an equipment profile.',
    actionLabel: 'Open equipment',
    deepLinkRoute: '/equipment',
  ),
  FirstLaunchCoachStep(
    id: ReadinessItemId.location,
    title: 'Set your observing location',
    whyItMatters:
        'Targets, altitude, and meridian flips are computed from your latitude and longitude.',
    actionLabel: 'Set location',
    deepLinkRoute: '/settings?section=location',
  ),
  FirstLaunchCoachStep(
    id: ReadinessItemId.outputPath,
    title: 'Choose where images are saved',
    whyItMatters:
        'Every light, flat, and dark frame is written to your output folder, so a valid path must exist before a sequence runs.',
    actionLabel: 'Set output folder',
    deepLinkRoute: '/settings?section=file-paths',
  ),
  FirstLaunchCoachStep(
    id: ReadinessItemId.plateSolver,
    title: 'Install a plate solver',
    whyItMatters:
        'Plate solving turns a quick exposure into precise coordinates so the app can center your target automatically.',
    actionLabel: 'Set up solving',
    deepLinkRoute: '/settings?section=plate-solving',
  ),
  FirstLaunchCoachStep(
    id: ReadinessItemId.darkLibrary,
    title: 'Build your dark library',
    whyItMatters:
        'Matching master darks remove sensor noise from every light frame, so calibrated stacks come out far cleaner.',
    actionLabel: 'Open dark library',
    deepLinkRoute: '/settings?section=dark-library',
  ),
  FirstLaunchCoachStep(
    id: ReadinessItemId.focusState,
    title: 'Achieve focus',
    whyItMatters:
        'A focus run sharpens the optics and gives the app a known star size to monitor throughout the night.',
    actionLabel: 'Open equipment',
    deepLinkRoute: '/equipment',
  ),
];

/// Returns the coach step for [id].
///
/// Throws a [StateError] if no step is defined for [id]. The list is required
/// to be exhaustive over [ReadinessItemId], so a missing step is a programming
/// error that must surface immediately rather than be papered over with a
/// silent fallback (errors are a feature in this codebase).
FirstLaunchCoachStep stepFor(ReadinessItemId id) {
  for (final step in kFirstLaunchCoachSteps) {
    if (step.id == id) {
      return step;
    }
  }
  throw StateError(
    'No FirstLaunchCoachStep defined for ReadinessItemId.${id.name}. '
    'kFirstLaunchCoachSteps must cover every ReadinessItemId.',
  );
}
