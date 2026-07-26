import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// App-side Riverpod surface for the unified Collaborative Sky screen (6.0
/// pillar). It composes the three collaborative flows the pillar productizes —
/// live co-imaging (WS3), collaborative mosaics (WS2), and the shared
/// calibration library (WS1) — on top of the SAME self-hosted hub credentials
/// Constellation (Pillar C) already resolves through
/// `constellationConfiguredProvider` / `constellationHubInfoProvider`.
///
/// Each list fails closed (an auth/network [ConstellationException]) exactly
/// like the existing constellation providers, so the screen renders an inline
/// error card rather than crashing.

/// Active collaborative mosaics advertised on the configured hub (WS2). Empty
/// until a club publishes a mosaic; surfaces the panel grid as claimable work.
final collaborativeMosaicsProvider = FutureProvider<List<CollabMosaic>>((ref) {
  return ref.watch(collaborativeMosaicServiceProvider).listMosaics();
});

/// The detailed state of one collaborative mosaic (its per-panel grid, claim
/// status, and contributor attribution), keyed by the hub mosaic id. The list
/// endpoint returns mosaics WITHOUT their panels (a deliberately cheap browse
/// payload), so the cards watch this to populate real combined panel-progress
/// and per-panel credit.
final collaborativeMosaicDetailProvider =
    FutureProvider.family<CollabMosaic, String>((ref, mosaicId) {
  return ref.watch(collaborativeMosaicServiceProvider).getMosaic(mosaicId);
});

/// The authoritative contributor credits for one collaborative mosaic, read back
/// from the hub's `GET /v1/attribution` (WS4) rather than reconstructed from the
/// browse payload. This is the WS5 contributor-credits UI source: the hub
/// resolves each display name consent-aware (a withheld contributor renders as
/// "Anonymous contributor"), so the UI never has to trust a local copy. Fails
/// closed like the other collaborative providers; the cards fall back to the
/// embedded owner/panel names while it loads or when the hub is unreachable.
final collaborativeMosaicAttributionProvider =
    FutureProvider.family<ArtifactAttribution, String>((ref, mosaicId) {
  return ref
      .watch(collaborativeMosaicServiceProvider)
      .fetchMosaicAttribution(mosaicId);
});

/// The authoritative contributor credits for one live co-imaging session, read
/// back from the hub's `GET /v1/attribution` (WS4) rather than reconstructed
/// from the participant roster. Consent-aware (withheld rigs render anonymously)
/// and fails closed; the card falls back to the participant display names while
/// it loads or when the hub is unreachable.
final coImagingAttributionProvider =
    FutureProvider.family<ArtifactAttribution, String>((ref, sessionId) {
  return ref.watch(coImagingSessionServiceProvider).fetchAttribution(sessionId);
});

/// A read-only summary of this device's participation in the shared calibration
/// library (WS1): how many local masters the user has PUBLISHED to the hub, and
/// how many remote masters the user has PULLED down and merged. Both are read
/// from the durable local library — no hub round-trip — so the card renders
/// instantly and honestly even when the hub is briefly unreachable.
class SharedLibrarySummary {
  /// Local masters the user has shared out to the hub (`publishedRemoteId` set).
  final int publishedCount;

  /// Remote masters the user has accepted into the local library (carry an
  /// authoritative `sharedBy` credit but are no longer an inbound candidate).
  final int pulledCount;

  const SharedLibrarySummary({
    required this.publishedCount,
    required this.pulledCount,
  });

  int get total => publishedCount + pulledCount;

  bool get isEmpty => total == 0;
}

/// Summarises shared-calibration participation from the durable local library.
final sharedLibrarySummaryProvider =
    FutureProvider<SharedLibrarySummary>((ref) async {
  final records = await ref
      .watch(calibrationLibraryServiceProvider)
      .listMasters(enrichFromHeaders: false);
  var published = 0;
  var pulled = 0;
  for (final r in records) {
    if (r.publishedRemoteId != null) {
      published++;
    } else if (r.sharedBy != null && r.remoteId == null) {
      // A pulled-in remote master: it carries an authoritative producer credit
      // but is NOT a not-yet-downloaded inbound candidate (those still hold a
      // `remoteId`). Those are the masters this rig saved instead of re-shooting.
      pulled++;
    }
  }
  return SharedLibrarySummary(publishedCount: published, pulledCount: pulled);
});
