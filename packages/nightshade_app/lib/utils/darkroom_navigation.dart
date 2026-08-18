/// How the rest of the app opens the Darkroom.
///
/// The `/darkroom` route is scoped by ONE of two query parameters — `recipe`
/// for a saved recipe row and `master` for a linear master whose newest recipe
/// should be loaded. Every entry point goes through the builders here so the
/// parameter names live in one place: a link written by hand somewhere else
/// would resolve to the screen's empty state without ever saying why.
///
/// Screens that only hold a session id resolve it with
/// [resolveDarkroomTargetForSession], which reads the session's masters the
/// same way the dawn autopilot does and answers with the reason when there is
/// nothing to open. A "refine this" control that silently opened an empty
/// editor would be the cry-wolf defect class.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'snackbar_helper.dart';

/// The Darkroom location for a saved recipe row.
String darkroomRecipeLocation(int recipeId) => '/darkroom?recipe=$recipeId';

/// The Darkroom location for a linear master; the screen loads its newest
/// recipe, or offers to compose one when the master has none.
String darkroomMasterLocation(int masterId) => '/darkroom?master=$masterId';

/// The one sentence every Darkroom entry point refuses a remote client with.
///
/// Shared rather than repeated so two controls cannot answer the same question
/// in two different ways: the session-level "Refine in Darkroom" explained
/// itself inline while the master card's "Darkroom" navigated into the
/// host-only screen, and an operator pressing both learned two different things
/// about the same machine.
const String kDarkroomHostOnlyRefusal =
    'The Darkroom works on the imaging host, where the linear masters are '
    'stored. Open Nightshade there to refine this night.';

/// Why this machine cannot open the Darkroom, or null when it can.
///
/// Gated on the client ROLE ([isRemoteClientProvider]), not on the connection:
/// a desktop launched with `--remote-host` that has not reached its rig is
/// `Disconnected`, so `backend is NetworkBackend` reads false for the whole
/// pre-handshake window and after every drop — and during exactly that window
/// the client owns none of the host's masters.
String? darkroomHostOnlyRefusal(WidgetRef ref) =>
    ref.read(isRemoteClientProvider) ? kDarkroomHostOnlyRefusal : null;

/// Push the Darkroom scoped to [masterId].
///
/// The raw push. Callers must have asked [darkroomHostOnlyRefusal] — directly
/// or through [resolveDarkroomTargetForSession] — before reaching it;
/// [openDarkroomForMasterRow] is the entry point that does both.
void openDarkroomForMaster(BuildContext context, int masterId) {
  context.push(darkroomMasterLocation(masterId));
}

/// Open the Darkroom on [masterId] from a control that names the master row
/// itself, or refuse where the operator pressed.
///
/// The master library's "Darkroom" button called [openDarkroomForMaster]
/// directly, so on a client it navigated into the host-only screen while the
/// session-level control on the same launch refused inline. One resolver, one
/// behaviour: no Darkroom control on a client lands on a gate screen.
void openDarkroomForMasterRow(
  BuildContext context,
  WidgetRef ref,
  int masterId,
) {
  final refusal = darkroomHostOnlyRefusal(ref);
  if (refusal != null) {
    context.showInfoSnackBar(refusal);
    return;
  }
  openDarkroomForMaster(context, masterId);
}

/// What a session resolves to for the Darkroom: a master to open, or the
/// sentence explaining why the night has none.
///
/// Exactly one of the two is non-null, so a caller cannot navigate and explain
/// at the same time.
class DarkroomSessionTarget {
  /// The `integrated_masters.id` to open, or null when there is none.
  final int? masterId;

  /// Why the session cannot be opened, in the words the user reads.
  final String? unavailableReason;

  const DarkroomSessionTarget.master(int this.masterId)
      : unavailableReason = null;

  const DarkroomSessionTarget.unavailable(String this.unavailableReason)
      : masterId = null;
}

/// Resolve the linear master the Darkroom should open for [sessionId].
///
/// The resolution is the dawn autopilot's own ([DawnMasterResolver]), so the
/// master this opens is the master the night's draft was made from rather than
/// a second, differently-derived answer to the same question.
///
/// Host-only by construction: the resolver reads the local database and the
/// master's pixels live on the imaging host's disk, so a remote client is told
/// where to open it instead of being handed a path it cannot read.
///
/// The refusal is [darkroomHostOnlyRefusal] — the same words, from the same
/// role question, that every other Darkroom entry point uses.
Future<DarkroomSessionTarget> resolveDarkroomTargetForSession(
  WidgetRef ref,
  int sessionId,
) async {
  final refusal = darkroomHostOnlyRefusal(ref);
  if (refusal != null) {
    return DarkroomSessionTarget.unavailable(refusal);
  }

  final DawnMasterSet set;
  try {
    set = await ref.read(dawnMasterResolverProvider).resolve(sessionId);
  } catch (error) {
    return DarkroomSessionTarget.unavailable(
      'This session\'s masters could not be read: $error',
    );
  }

  if (set.masters.isNotEmpty) {
    return DarkroomSessionTarget.master(set.masters.first.masterId);
  }

  // Name the reason the resolver gave when it has one: a master that is still
  // accumulating has grown without writing a FITS, which is a different problem
  // from a night that was never integrated at all.
  final blocked = set.withoutFile.isEmpty ? null : set.withoutFile.first;
  return DarkroomSessionTarget.unavailable(
    blocked == null
        ? 'This session has no integrated master yet. Integrate it in Session '
            'Review first, then refine it here.'
        : '${blocked.name}: ${blocked.reason}.',
  );
}

/// Resolve [sessionId] and push the Darkroom onto its master, or say why there
/// is nothing to open.
///
/// For callers that are a screen rather than a dialog: it navigates without
/// dismissing anything. A dialog resolves with
/// [resolveDarkroomTargetForSession] instead, so it can close itself before
/// pushing.
Future<void> openDarkroomForSession(
  BuildContext context,
  WidgetRef ref,
  int sessionId,
) async {
  final target = await resolveDarkroomTargetForSession(ref, sessionId);
  if (!context.mounted) return;
  final masterId = target.masterId;
  if (masterId == null) {
    context.showInfoSnackBar(target.unavailableReason!);
    return;
  }
  openDarkroomForMaster(context, masterId);
}
