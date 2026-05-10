import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/database.dart'
    show PsfFieldTileRow, AstrometryResidualVectorRow;
import '../services/optical_train_diagnostics_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'science_provider.dart'
    show
        sessionPsfTilesProvider,
        sessionResidualVectorsProvider,
        sessionlessPsfTilesProvider,
        sessionlessResidualVectorsProvider;

/// Service provider for OpticalTrainDiagnosticsService.
final opticalTrainDiagnosticsServiceProvider =
    Provider<OpticalTrainDiagnosticsService>((ref) {
  return const OpticalTrainDiagnosticsService();
});

/// Reactive PSF field tiles stream for a given session.
final psfTilesForSessionProvider = StreamProvider.autoDispose
    .family<List<PsfFieldTileRow>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemotePsfTiles(backend, sessionId);
  }
  return ref.watch(scienceDaoProvider).watchPsfTilesForSession(sessionId);
});

/// Reactive astrometry residual vectors stream for a given session.
final residualVectorsForSessionProvider = StreamProvider.autoDispose
    .family<List<AstrometryResidualVectorRow>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteResiduals(backend, sessionId);
  }
  return ref.watch(scienceDaoProvider).watchResidualsForSession(sessionId);
});

/// Reactive optical train diagnostics for a given session.
///
/// Watches PSF field tiles and astrometry residual vectors from the science
/// DAO and feeds them into the diagnostics service. Pass the session ID as
/// the family parameter.
final opticalTrainDiagnosticsProvider = Provider.autoDispose
    .family<AsyncValue<OpticalTrainDiagnostics>, int>((ref, sessionId) {
  final psfAsync = ref.watch(psfTilesForSessionProvider(sessionId));
  final residualsAsync =
      ref.watch(residualVectorsForSessionProvider(sessionId));
  final service = ref.watch(opticalTrainDiagnosticsServiceProvider);

  if (psfAsync.hasError) {
    return AsyncValue.error(
      psfAsync.error!,
      psfAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (residualsAsync.hasError) {
    return AsyncValue.error(
      residualsAsync.error!,
      residualsAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (psfAsync.isLoading || residualsAsync.isLoading) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    service.analyze(
      psfTiles: psfAsync.value ?? const [],
      residualVectors: residualsAsync.value ?? const [],
    ),
  );
});

/// Memoized optical-train diagnostics derived from the *latest captured-image
/// snapshot* of PSF tiles and residual vectors. Used by the science analytics
/// tab, where rebuilds were re-running `analyze()` every Riverpod frame
/// (audit §6.20). Pass the active session ID, or `null` for sessionless /
/// quick-capture mode — the provider switches sources accordingly.
final latestSnapshotOpticalTrainDiagnosticsProvider = Provider.autoDispose
    .family<OpticalTrainDiagnostics, int?>((ref, sessionId) {
  final psfTiles = sessionId != null
      ? ref.watch(sessionPsfTilesProvider(sessionId)).valueOrNull ?? const []
      : ref.watch(sessionlessPsfTilesProvider).valueOrNull ?? const [];
  final residuals = sessionId != null
      ? ref.watch(sessionResidualVectorsProvider(sessionId)).valueOrNull ??
          const []
      : ref.watch(sessionlessResidualVectorsProvider).valueOrNull ?? const [];

  // Snapshot to the latest captured-image worth of tiles/vectors so the
  // diagnostics reflect "this exposure" rather than averaging across the
  // session. Matches the snapshot rendered by the PSF heatmap and residual
  // cards above the diagnostics block.
  final latestPsf = _latestPsfSnapshot(psfTiles);
  final latestResiduals = _latestResidualSnapshot(residuals);

  final service = ref.watch(opticalTrainDiagnosticsServiceProvider);
  return service.analyze(
    psfTiles: latestPsf,
    residualVectors: latestResiduals,
  );
});

List<PsfFieldTileRow> _latestPsfSnapshot(List<PsfFieldTileRow> rows) {
  if (rows.isEmpty) {
    return const [];
  }
  int? latestId;
  DateTime latestTime = DateTime.fromMillisecondsSinceEpoch(0);
  for (final row in rows) {
    if (row.capturedImageId == null) {
      continue;
    }
    if (row.timestamp.isAfter(latestTime)) {
      latestTime = row.timestamp;
      latestId = row.capturedImageId;
    }
  }
  if (latestId == null) {
    return rows;
  }
  return rows
      .where((row) => row.capturedImageId == latestId)
      .toList(growable: false);
}

List<AstrometryResidualVectorRow> _latestResidualSnapshot(
  List<AstrometryResidualVectorRow> rows,
) {
  if (rows.isEmpty) {
    return const [];
  }
  int? latestId;
  DateTime latestTime = DateTime.fromMillisecondsSinceEpoch(0);
  for (final row in rows) {
    if (row.capturedImageId == null) {
      continue;
    }
    if (row.timestamp.isAfter(latestTime)) {
      latestTime = row.timestamp;
      latestId = row.capturedImageId;
    }
  }
  if (latestId == null) {
    return rows;
  }
  return rows
      .where((row) => row.capturedImageId == latestId)
      .toList(growable: false);
}

Stream<List<PsfFieldTileRow>> _pollRemotePsfTiles(
  NetworkBackend backend,
  int sessionId,
) async* {
  yield await backend.getSessionPsfTiles(sessionId);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await backend.getSessionPsfTiles(sessionId);
  }
}

Stream<List<AstrometryResidualVectorRow>> _pollRemoteResiduals(
  NetworkBackend backend,
  int sessionId,
) async* {
  yield await backend.getSessionResidualVectors(sessionId);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await backend.getSessionResidualVectors(sessionId);
  }
}
