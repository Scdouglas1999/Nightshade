import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/sequence/sequence_models.dart';
import '../../plate_solver_provider.dart';
import '../sequence_validation.dart';

/// A sequence that centres on its target cannot run without a plate solver.
///
/// The executor already refuses this case
/// (`native/nightshade_native/sequencer/src/executor/start/preflight.rs`:
/// "This sequence centers on a target but no plate solver … was found"), but
/// nothing checked it BEFORE the run: pre-flight reported "Ready with
/// warnings", Start was enabled, and the run died in 0 s with the reason
/// buried in History → Session summary. Driven and reproduced on the built
/// bundle 2026-09-09 with the "Mono LRGB M51" starter, which contains a
/// Center node.
///
/// Silent when the detection probe has not answered yet: an unknown solver
/// state must not block a run that would have succeeded.
class PlateSolverForCenteringRule implements RefAwareSequenceValidator {
  @override
  String get name => 'PlateSolverForCentering';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final centres = sequence.nodes.values.any(
      (node) => node.isEnabled && node is CenterNode,
    );
    if (!centres) return const [];

    final ref = ctx.ref;
    final detection = ref.read(plateSolverDetectionProvider).valueOrNull;
    final preference = ref.read(plateSolverPreferenceProvider).valueOrNull;
    if (detection == null || preference == null) return const [];
    if (detection.supports(preference.choice)) return const [];

    return const [
      ValidationIssue(
        severity: ValidationSeverity.error,
        category: ValidationCategory.equipment,
        title: 'No plate solver',
        description:
            'This sequence centres on its target, and no plate solver is '
            'installed or configured. The executor refuses to start, so the '
            'run would fail immediately.',
        resolutionHint:
            'Install ASTAP (with a star catalog) or astrometry.net, then set '
            'it up in Settings → Plate solving. Or disable the Center node.',
      ),
    ];
  }
}
