import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for Pillar B ("First Light") — the difference-imaging transient
/// discovery surface.
///
/// The difference pipeline and its persistence run on the appliance/desktop
/// (where solved frames land); a remote tablet/desktop cannot watch that DB, so
/// these endpoints expose the persisted [TransientDetectionRow] feed over REST
/// and let a remote client triage (review / dismiss) a candidate. Reads default
/// to `view` scope, the triage mutations to `control`, per `route_metadata`.
class FirstLightHandlers {
  final ProviderContainer container;

  FirstLightHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FirstLightHandlers');

  TransientDetectionsDao get _dao =>
      container.read(transientDetectionsDaoProvider);

  /// POST `/api/firstlight/<id>/submit/tns` — REAL TNS bot-API submission.
  ///
  /// The host holds the credentials (non-secret in ScienceSettings, the secret
  /// api key in the keyring). A slave only triggers this; the api key never
  /// crosses the wire. Returns the submission result JSON.
  Future<Response> handleSubmitTns(Request request, String id) async {
    final detectionId = int.tryParse(id);
    if (detectionId == null) {
      throw BadRequestError(
        field: 'id',
        expected: 'integer',
        message: 'detection id must be an integer',
      );
    }
    _logInfo('[API] POST /api/firstlight/$detectionId/submit/tns');

    final detection = await _dao.detectionById(detectionId);
    if (detection == null) {
      return jsonNotFound('No transient detection with id $detectionId');
    }

    final settings = await container.read(scienceSettingsProvider.future);
    final apiKey = await container
        .read(secretsStoreProvider)
        .read(SecretField.tnsApiKey);
    final creds = TnsCredentials(
      botId: settings.tnsBotId,
      botName: settings.tnsBotName,
      reportingGroupId: settings.tnsReportingGroupId,
      dataSourceId: settings.tnsDataSourceId,
      reporterName: settings.tnsReporterName.isNotEmpty
          ? settings.tnsReporterName
          : settings.observerName,
      apiKey: apiKey,
      useSandbox: settings.tnsUseSandbox,
    );
    if (!creds.isComplete) {
      return jsonBadRequest({
        'success': false,
        'message':
            'TNS credentials are not configured on the host. Set the bot '
            'id/name/group/source, reporter, and api key in '
            'Settings > Science on the rig host.',
      });
    }

    final result = await container
        .read(transientSubmissionServiceProvider)
        .submitToTns(detection: detection, creds: creds);
    return jsonOk({
      'success': result.success,
      'atName': result.atName,
      'reportId': result.reportId,
      'message': result.message,
    });
  }

  /// POST `/api/firstlight/<id>/export/aavso` — generate an ingestible AAVSO
  /// Extended File Format report and return it as a downloadable attachment.
  ///
  /// Requires a photometric zeropoint (passed in the body) and the host's
  /// observer code; without a calibrated magnitude the AAVSO format is
  /// disabled (returns 400), never a `na`-stuffed DIF row.
  Future<Response> handleExportAavso(Request request, String id) async {
    final detectionId = int.tryParse(id);
    if (detectionId == null) {
      throw BadRequestError(
        field: 'id',
        expected: 'integer',
        message: 'detection id must be an integer',
      );
    }
    _logInfo('[API] POST /api/firstlight/$detectionId/export/aavso');

    final detection = await _dao.detectionById(detectionId);
    if (detection == null) {
      return jsonNotFound('No transient detection with id $detectionId');
    }
    final payload = await readJsonObject(request);
    final magZeroPoint = (payload['magZeroPoint'] as num?)?.toDouble();
    final standardBand = optionalString(payload, 'standardBand');

    final settings = await container.read(scienceSettingsProvider.future);
    final reports = TransientReportService();
    final reason = reports.aavsoDisabledReason(
      detection,
      observerCode: settings.aavsoObserverCode,
      magZeroPoint: magZeroPoint,
    );
    if (reason != null) {
      return jsonBadRequest({'error': reason});
    }

    final content = reports.generateAavsoReport(
      detection: detection,
      observerCode: settings.aavsoObserverCode,
      magZeroPoint: magZeroPoint!,
      standardBand: standardBand,
    );
    return attachmentResponse(
      content,
      fileName: 'aavso_transient_$detectionId.txt',
      contentType: 'text/plain; charset=utf-8',
    );
  }

  /// POST `/api/firstlight/<id>/export/mpc` — generate an MPC ADES PSV
  /// astrometry report and return it as a downloadable attachment. Requires the
  /// host's 3-char observatory code.
  Future<Response> handleExportMpc(Request request, String id) async {
    final detectionId = int.tryParse(id);
    if (detectionId == null) {
      throw BadRequestError(
        field: 'id',
        expected: 'integer',
        message: 'detection id must be an integer',
      );
    }
    _logInfo('[API] POST /api/firstlight/$detectionId/export/mpc');

    final detection = await _dao.detectionById(detectionId);
    if (detection == null) {
      return jsonNotFound('No transient detection with id $detectionId');
    }
    final settings = await container.read(scienceSettingsProvider.future);
    final reports = TransientReportService();
    if (!reports.mpcAdesAvailable(
      observatoryCode: settings.mpcObservatoryCode,
    )) {
      return jsonBadRequest({
        'error':
            'Set your 3-character MPC observatory code in Settings > Science '
            'on the host first.',
      });
    }

    final content = reports.generateMpcAdesPsv(
      detection: detection,
      observatoryCode: settings.mpcObservatoryCode,
      observerName: settings.observerName,
      astrometricCatalog: settings.mpcAstrometricCatalog,
    );
    return attachmentResponse(
      content,
      fileName: 'mpc_ades_transient_$detectionId.psv',
      contentType: 'text/plain; charset=utf-8',
    );
  }

  /// GET `/api/firstlight/candidates?sessionId=` — newest-first transient
  /// detections. `sessionId` is optional; omit it for the across-sessions feed
  /// the standalone gallery and the export hub read.
  Future<Response> handleGetCandidates(Request request) async {
    final raw = request.url.queryParameters['sessionId'];
    _logInfo(
      '[API] GET /api/firstlight/candidates${raw == null ? '' : '?sessionId=$raw'}',
    );

    final List<TransientDetectionRow> rows;
    if (raw == null || raw.isEmpty) {
      rows = await _dao.allDetections();
    } else {
      final sessionId = int.tryParse(raw);
      if (sessionId == null) {
        throw BadRequestError(
          field: 'sessionId',
          expected: 'integer',
          message: 'sessionId query parameter must be an integer when present',
        );
      }
      rows = await _dao.detectionsForSession(sessionId);
    }

    return jsonOk({
      'candidates': rows.map(_rowToWireJson).toList(),
      'unnamedCount': rows.where((r) => r.catalogMatch == null).length,
    });
  }

  /// POST `/api/firstlight/<id>/review` — mark a detection reviewed (confirmed).
  Future<Response> handleReview(Request request, String id) async {
    final detectionId = int.tryParse(id);
    if (detectionId == null) {
      throw BadRequestError(
        field: 'id',
        expected: 'integer',
        message: 'detection id must be an integer',
      );
    }
    _logInfo('[API] POST /api/firstlight/$detectionId/review');

    final existing = await _dao.detectionById(detectionId);
    if (existing == null) {
      return jsonNotFound('No transient detection with id $detectionId');
    }
    await _dao.markReviewed(detectionId, dismissed: false);
    final updated = await _dao.detectionById(detectionId);

    return jsonOk({
      'status': 'reviewed',
      'detection': updated == null ? null : _rowToWireJson(updated),
    });
  }

  /// POST `/api/firstlight/<id>/dismiss` — flag a detection as a triaged
  /// artefact so the next difference scan suppresses the same position.
  Future<Response> handleDismiss(Request request, String id) async {
    final detectionId = int.tryParse(id);
    if (detectionId == null) {
      throw BadRequestError(
        field: 'id',
        expected: 'integer',
        message: 'detection id must be an integer',
      );
    }
    _logInfo('[API] POST /api/firstlight/$detectionId/dismiss');

    final existing = await _dao.detectionById(detectionId);
    if (existing == null) {
      return jsonNotFound('No transient detection with id $detectionId');
    }
    await _dao.markReviewed(detectionId, dismissed: true);
    final updated = await _dao.detectionById(detectionId);

    return jsonOk({
      'status': 'dismissed',
      'detection': updated == null ? null : _rowToWireJson(updated),
    });
  }

  /// Serialize a persisted detection to the wire shape the client's
  /// `transientDetectionFromWireJson` reconstructs. Field names mirror the
  /// `TransientDetections` columns so the remote feed renders identically to the
  /// local one.
  Map<String, dynamic> _rowToWireJson(TransientDetectionRow row) => {
    'id': row.id,
    'sessionId': row.sessionId,
    'capturedImageId': row.capturedImageId,
    'tileId': row.tileId,
    'detectedAt': row.detectedAt.millisecondsSinceEpoch,
    'raDeg': row.raDeg,
    'decDeg': row.decDeg,
    'residualFlux': row.residualFlux,
    'deltaMag': row.deltaMag,
    'snr': row.snr,
    'fwhm': row.fwhm,
    'eccentricity': row.eccentricity,
    'positionAngleDeg': row.positionAngleDeg,
    'kind': row.kind,
    'catalogMatch': row.catalogMatch,
    'confidence': row.confidence,
    'reviewed': row.reviewed,
    'dismissed': row.dismissed,
  };
}
