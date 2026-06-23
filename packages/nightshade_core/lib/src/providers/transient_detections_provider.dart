import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../backend/network_backend.dart';
import '../database/daos/transient_detections_dao.dart';
import '../database/database.dart';
import '../services/logging_service.dart';
import '../services/science/photometric_catalog_service.dart';
import '../services/sky_atlas/sky_atlas_service.dart' show defaultAtlasRoot;
import '../services/transients/difference_image_seam.dart';
import '../services/transients/first_light_service.dart';
import '../services/transients/transient_submission_service.dart';
import 'backend_provider.dart';

/// Riverpod surface for Pillar B ("First Light") — difference-imaging transients.
///
/// [firstLightServiceProvider] builds the scan orchestrator from the transient
/// DAO + FFI seam + photometric catalog; [transientDetectionsProvider] is the
/// reactive newest-first feed the transient gallery and the Narrator's transient
/// surface render, scoped to a session.

/// The First Light scan service.
final firstLightServiceProvider = Provider<FirstLightService>((ref) {
  return FirstLightService(
    dao: ref.watch(transientDetectionsDaoProvider),
    seam: ref.watch(differenceImageSeamProvider),
    catalog: PhotometricCatalogMatcher(
      ref.watch(photometricCatalogServiceProvider),
    ),
    logger: ref.watch(loggingServiceProvider),
    atlasRootResolver: defaultAtlasRoot,
  );
});

/// Host-only submission seam for First Light discovery reports (real TNS
/// bot-API upload + AAVSO/MPC export). Wired with an http.Client + logger; the
/// TNS api key is read from the keyring by the caller, not injected here.
final transientSubmissionServiceProvider = Provider<TransientSubmissionService>(
  (ref) {
    final client = http.Client();
    ref.onDispose(client.close);
    return TransientSubmissionService(
      httpClient: client,
      logger: ref.watch(loggingServiceProvider),
    );
  },
);

/// Reactive newest-first transient detections for a session.
final transientDetectionsProvider =
    StreamProvider.family<List<TransientDetectionRow>, int>((ref, sessionId) {
      return ref
          .watch(transientDetectionsDaoProvider)
          .watchDetectionsForSession(sessionId);
    });

/// Reactive newest-first transient detections across all sessions — backs the
/// standalone gallery and the export hub's candidate snapshot.
final allTransientDetectionsProvider =
    StreamProvider<List<TransientDetectionRow>>((ref) {
      return ref.watch(transientDetectionsDaoProvider).watchAllDetections();
    });

/// Reconstruct a [TransientDetectionRow] from the wire JSON the appliance's
/// `/api/firstlight/candidates` endpoint emits (see
/// `FirstLightHandlers._rowToWireJson`). Mirrors the DB row exactly so the
/// remote First Light surface renders identically to the local one.
TransientDetectionRow transientDetectionFromWireJson(
  Map<String, dynamic> json,
) {
  return TransientDetectionRow(
    id: (json['id'] as num).toInt(),
    sessionId: (json['sessionId'] as num?)?.toInt(),
    capturedImageId: (json['capturedImageId'] as num?)?.toInt(),
    tileId: (json['tileId'] as num).toInt(),
    detectedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['detectedAt'] as num).toInt(),
    ),
    raDeg: (json['raDeg'] as num).toDouble(),
    decDeg: (json['decDeg'] as num).toDouble(),
    residualFlux: (json['residualFlux'] as num).toDouble(),
    deltaMag: (json['deltaMag'] as num?)?.toDouble(),
    snr: (json['snr'] as num).toDouble(),
    fwhm: (json['fwhm'] as num).toDouble(),
    eccentricity: (json['eccentricity'] as num).toDouble(),
    positionAngleDeg: (json['positionAngleDeg'] as num?)?.toDouble() ?? 0.0,
    kind: json['kind'] as String,
    catalogMatch: json['catalogMatch'] as String?,
    confidence: (json['confidence'] as num).toDouble(),
    reviewed: (json['reviewed'] as bool?) ?? false,
    dismissed: (json['dismissed'] as bool?) ?? false,
  );
}

/// Backend-aware First Light candidate feed. Local: the DB-watched
/// across-sessions stream, updating the instant the difference pipeline
/// persists. Remote (companion) mode: a REST snapshot from the appliance,
/// refreshed when backend events arrive (a new capture is exactly what produces
/// a new scan), so the discovery surface works on desktop and mobile alike.
final firstLightCandidatesProvider =
    StreamProvider<List<TransientDetectionRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return _remoteFirstLightStream(
          ref,
          backend,
          () => backend.getFirstLightCandidates(),
        );
      }
      return ref.watch(transientDetectionsDaoProvider).watchAllDetections();
    });

/// REST snapshot stream for the remote First Light feed: fetch once, then
/// re-fetch (debounced) whenever a backend event arrives. Keeps the last good
/// snapshot on a transient fetch failure rather than flashing an empty feed —
/// the same shape the remote narrator feed uses.
Stream<List<TransientDetectionRow>> _remoteFirstLightStream(
  Ref ref,
  NetworkBackend backend,
  Future<List<Map<String, dynamic>>> Function() fetch,
) {
  final controller = StreamController<List<TransientDetectionRow>>();
  Timer? debounce;

  Future<void> refetch() async {
    try {
      final raw = await fetch();
      final rows = raw
          .map(transientDetectionFromWireJson)
          .toList(growable: false);
      if (!controller.isClosed) controller.add(rows);
    } catch (_) {
      // Transient (reconnect / host busy): keep the last good snapshot.
    }
  }

  refetch();
  final sub = backend.eventStream.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 750), refetch);
  });
  ref.onDispose(() {
    debounce?.cancel();
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
}

/// Triage a First Light candidate (mark reviewed/confirmed, or dismiss as an
/// artefact). Routes to the host over REST in companion mode, else writes the
/// local DB directly. Exposed as a callback the discovery surface invokes from
/// a card action so both desktop and mobile share one triage path.
final firstLightTriageProvider = Provider<FirstLightTriage>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    // Remote (slave) triage: the host applies the reviewed/dismissed flag, but
    // the remote feed is a debounced REST snapshot that otherwise only re-fetches
    // on an unrelated backend event — so the card's badge would stay stale until
    // a capture tick arrived. Await the host POST THEN invalidate the feed to
    // force an immediate re-fetch of /api/firstlight/candidates reflecting the
    // host's just-applied flags (badge updates within one round-trip). Await
    // before invalidating so a FAILED triage doesn't wipe the current state.
    return FirstLightTriage(
      review: (id) async {
        await backend.reviewFirstLightCandidate(id);
        ref.invalidate(firstLightCandidatesProvider);
      },
      dismiss: (id) async {
        await backend.dismissFirstLightCandidate(id);
        ref.invalidate(firstLightCandidatesProvider);
      },
    );
  }
  final service = ref.watch(firstLightServiceProvider);
  return FirstLightTriage(
    review: (id) => service.markReviewed(id, dismissed: false),
    dismiss: (id) => service.markReviewed(id, dismissed: true),
  );
});

/// Backend-agnostic triage callbacks for a First Light candidate.
class FirstLightTriage {
  const FirstLightTriage({required this.review, required this.dismiss});

  /// Mark the candidate reviewed (confirmed).
  final Future<void> Function(int id) review;

  /// Dismiss the candidate as a triaged artefact.
  final Future<void> Function(int id) dismiss;
}
