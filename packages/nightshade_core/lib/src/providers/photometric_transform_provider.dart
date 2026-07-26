import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' show PhotometricTransformRow;
import '../models/science/science_models.dart';
import '../backend/network_backend.dart';
import '../services/science/photometric_transform_service.dart';
import '../utils/resilient_poll_stream.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// Watches all photometric transforms in the database.
final allPhotometricTransformsProvider =
    StreamProvider<List<PhotometricTransformRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return _pollRemoteTransforms(
          backend,
          interval: ref.watch(remotePhotometricTransformPollIntervalProvider),
        );
      }
      return ref.watch(scienceDaoProvider).watchAllTransforms();
    });

/// Watches transforms relevant to the current equipment profile.
final activeProfileTransformsProvider =
    StreamProvider<List<PhotometricTransformRow>>((ref) {
      final backend = ref.watch(backendProvider);
      final profileId = ref.watch(activeEquipmentProfileIdProvider);
      if (backend is NetworkBackend) {
        return _pollRemoteTransforms(
          backend,
          profileId: profileId,
          interval: ref.watch(remotePhotometricTransformPollIntervalProvider),
        );
      }
      return ref.watch(scienceDaoProvider).watchTransformsForProfile(profileId);
    });

/// Reads the active equipment profile's ID (nullable).
final activeEquipmentProfileIdProvider = Provider<int?>((ref) {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  return profile?.id;
});

/// Host transform catalogs are low-churn. Exposed for deterministic poll
/// recovery tests without waiting for the production interval.
final remotePhotometricTransformPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// Provides the transform coefficients for a given filter, considering the
/// active equipment profile.
final transformForFilterProvider =
    FutureProvider.family<PhotometricTransformCoefficients?, String>((
      ref,
      filterName,
    ) async {
      final backend = ref.watch(backendProvider);
      final profileId = ref.watch(activeEquipmentProfileIdProvider);
      if (backend is NetworkBackend) {
        final transforms = await backend.getPhotometricTransforms(
          profileId: profileId,
        );
        final row = transforms
            .where((transform) => transform.filterName == filterName)
            .firstOrNull;
        if (row == null) {
          return null;
        }
        return PhotometricTransformCoefficients(
          id: row.id,
          equipmentProfileId: row.equipmentProfileId,
          filterName: row.filterName,
          colorTerm: row.colorTerm,
          extinctionCoefficient: row.extinctionCoefficient,
          zeroPoint: row.zeroPoint,
          rmsResidual: row.rmsResidual,
          matchedStarCount: row.matchedStarCount,
          catalogSource: row.catalogSource,
          fitData: _decodeTransformFitData(row.fitDataJson),
          dateComputed: row.dateComputed,
        );
      }
      return ref
          .read(photometricTransformServiceProvider)
          .getTransformForFilter(filterName, equipmentProfileId: profileId);
    });

Stream<List<PhotometricTransformRow>> _pollRemoteTransforms(
  NetworkBackend backend, {
  int? profileId,
  Duration interval = const Duration(seconds: 10),
}) => resilientDistinctPoll(
  fetch: () => backend.getPhotometricTransforms(profileId: profileId),
  unchanged: listEquals,
  interval: interval,
  onRetainedError: (error, stackTrace) {
    developer.log(
      'Remote photometric-transform poll failed; retaining last value',
      name: 'PhotometricTransformProvider',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  },
);

List<TransformStarMatch> _decodeTransformFitData(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((row) => TransformStarMatch.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}
