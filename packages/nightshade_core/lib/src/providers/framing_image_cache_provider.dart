import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/framing_image_cache_service.dart';
import 'framing_provider.dart' show SurveySource;

/// Canonical dependency-injection handle for [FramingImageCacheService].
///
/// Before this provider existed, the framing notifier instantiated the cache
/// service ad-hoc, which made it impossible to override the on-disk location in
/// tests and meant two call sites could end up with diverging configuration.
/// Everything that needs to read or write cached survey snapshots should now
/// resolve the service through this provider so there is a single, overridable
/// instance.
///
/// Tests (and any environment that must redirect the cache to a temporary
/// directory) override this provider with a service constructed via
/// `FramingImageCacheService(supportDirProvider: ...)`.
final framingImageCacheServiceProvider = Provider<FramingImageCacheService>(
  (ref) => FramingImageCacheService(),
);

/// Family argument for [cachedSurveyImageFileProvider]: the target coordinates
/// and survey source identifying a single cached snapshot.
///
/// `raHours` is right ascension in **decimal hours** and `decDegrees` is
/// declination in **decimal degrees**, matching
/// [FramingImageCacheService.loadCachedSurveyImage] and the rest of the framing
/// subsystem (see `FramingTarget`/`Targets.ra`). A record is used so Riverpod
/// gets structural value equality for free, letting it cache and dedupe lookups
/// for the same target/source.
typedef CachedSurveyImageKey = ({
  double raHours,
  double decDegrees,
  SurveySource source,
});

/// Resolves the on-disk [File] for a previously-cached survey snapshot, or
/// `null` when no entry has been pinned for the requested target + source.
///
/// This is a thin read-through over
/// [FramingImageCacheService.loadCachedSurveyImage]; it intentionally contains
/// no fetch-or-fallback logic. The offline-first read orchestration (deciding
/// whether to serve the cached file versus hitting the network) lives in the
/// framing notifier so this file keeps a single, narrow responsibility.
///
/// Errors from the underlying service (IO failures while probing the cache
/// directory) propagate as an [AsyncError] rather than being swallowed —
/// surfacing failures is intentional (errors are a feature, see CLAUDE.md). A
/// genuine cache miss is represented as a `null` value, not an error.
final cachedSurveyImageFileProvider =
    FutureProvider.family<File?, CachedSurveyImageKey>((ref, key) async {
  final service = ref.watch(framingImageCacheServiceProvider);
  return service.loadCachedSurveyImage(
    raHours: key.raHours,
    decDegrees: key.decDegrees,
    source: key.source,
  );
});
