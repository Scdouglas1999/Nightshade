import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/database.dart' show PsfFieldTileRow, AstrometryResidualVectorRow;
import '../services/optical_train_diagnostics_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

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
