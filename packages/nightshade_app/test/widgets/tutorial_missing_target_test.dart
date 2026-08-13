// SET-12: the Dashboard Tour narrated nine panels the default dashboard layout
// does not contain — Live Image Preview, Quick Capture, Session Progress and
// six more — each with the card floating in mid-screen, no spotlight and
// nothing highlighted, because their target keys resolve to widgets that were
// never built.
//
// The walk that decides where such a step sends the operator is pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/tutorial_overlay.dart';
import 'package:nightshade_core/nightshade_core.dart';

TutorialStep _step(String id, {String? targetKey, required int order}) =>
    TutorialStep(
      id: id,
      title: id,
      description: id,
      targetKey: targetKey,
      order: order,
      category: TutorialCategory.dashboardTour,
    );

final _tour = <TutorialStep>[
  _step('welcome', order: 0),
  _step('present', targetKey: 'dashboard_edit_button', order: 1),
  _step('absent', targetKey: 'dashboard_live_preview', order: 2),
  _step('complete', order: 3),
];

bool _onlyEditButtonIsLive(String key) => key == 'dashboard_edit_button';

void main() {
  test('a step whose panel is not on screen is passed over', () {
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: _tour,
        index: 2,
        direction: TutorialDirection.forward,
        isTargetLive: _onlyEditButtonIsLive,
      ),
      3,
    );
  });

  test('going back past a missing panel keeps going back', () {
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: _tour,
        index: 2,
        direction: TutorialDirection.backward,
        isTargetLive: _onlyEditButtonIsLive,
      ),
      1,
      reason: 'Back must not bounce the operator forward off a dead step',
    );
  });

  test('a step whose panel IS on screen stands', () {
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: _tour,
        index: 1,
        direction: TutorialDirection.forward,
        isTargetLive: _onlyEditButtonIsLive,
      ),
      isNull,
    );
  });

  test('centred steps with no target are never skipped', () {
    for (final index in const [0, 3]) {
      expect(
        tutorialStepIndexPastMissingTarget(
          steps: _tour,
          index: index,
          direction: TutorialDirection.forward,
          isTargetLive: (_) => false,
        ),
        isNull,
        reason: 'the welcome and completion cards point at nothing by design',
      );
    }
  });

  test('a tour whose targets have none resolved stands down entirely', () {
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: _tour,
        index: 2,
        direction: TutorialDirection.forward,
        isTargetLive: (_) => false,
      ),
      isNull,
      reason: 'a screen mid-build is not a screen without the panel',
    );
  });

  test('the walk stops at the ends rather than running off them', () {
    final trailing = [_step('absent', targetKey: 'dashboard_x', order: 0)];
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: trailing,
        index: 0,
        direction: TutorialDirection.forward,
        isTargetLive: (_) => false,
      ),
      isNull,
    );
    expect(
      tutorialStepIndexPastMissingTarget(
        steps: trailing,
        index: 0,
        direction: TutorialDirection.backward,
        isTargetLive: (_) => false,
      ),
      isNull,
    );
  });
}
