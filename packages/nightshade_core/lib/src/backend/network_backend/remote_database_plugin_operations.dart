part of '../network_backend.dart';

mixin _NetworkBackendRemoteDatabasePluginOperations
    on _NetworkBackendTransport {
  /// GET /api/sequence-runs?sequenceId=&limit=&offset=
  Future<RemotePage<RemoteSequenceRun>> fetchSequenceRuns({
    int? sequenceId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('sequence-runs', {
      if (sequenceId != null) 'sequenceId': sequenceId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteSequenceRun.fromJson);
  }

  /// GET /api/notes-journal?equipmentProfileId=&limit=&offset=
  Future<RemotePage<RemoteNotesJournalEntry>> fetchNotesJournal({
    int? equipmentProfileId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('notes-journal', {
      if (equipmentProfileId != null)
        'equipmentProfileId': equipmentProfileId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteNotesJournalEntry.fromJson);
  }

  /// GET /api/guide-rms-history?sinceMs=&untilMs=&limit=&offset=
  Future<RemotePage<RemoteGuideRmsHistoryEntry>> fetchGuideRmsHistory({
    int? sinceMs,
    int? untilMs,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('guide-rms-history', {
      if (sinceMs != null) 'sinceMs': sinceMs.toString(),
      if (untilMs != null) 'untilMs': untilMs.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteGuideRmsHistoryEntry.fromJson);
  }

  /// GET /api/polar-alignment-history?equipmentProfileId=&limit=&offset=
  Future<RemotePage<RemotePolarAlignmentHistoryEntry>>
      fetchPolarAlignmentHistory({
    int? equipmentProfileId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('polar-alignment-history', {
      if (equipmentProfileId != null)
        'equipmentProfileId': equipmentProfileId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(
      response,
      RemotePolarAlignmentHistoryEntry.fromJson,
    );
  }

  /// GET /api/db/dark-library?gainMin=&gainMax=&temperatureC=&exposureSecs=&limit=&offset=
  ///
  /// Returns the raw `dark_library` Drift rows. The pre-existing
  /// `listDarks()` method (P1-10) projects the same table through the
  /// `RemoteDarkLibraryEntry` wire model used by the calibration UI, but
  /// elides several columns (master frame path, master count) that the
  /// P2-8 read surface intentionally exposes. Hence the separate
  /// [RemoteDbDarkLibraryRow] wire type — different consumers, different
  /// shapes, no risk of one breaking the other.
  Future<RemotePage<RemoteDbDarkLibraryRow>> fetchDarkLibrary({
    int? gainMin,
    int? gainMax,
    double? temperatureC,
    double? exposureSecs,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('db/dark-library', {
      if (gainMin != null) 'gainMin': gainMin.toString(),
      if (gainMax != null) 'gainMax': gainMax.toString(),
      if (temperatureC != null) 'temperatureC': temperatureC.toString(),
      if (exposureSecs != null) 'exposureSecs': exposureSecs.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteDbDarkLibraryRow.fromJson);
  }

  /// GET /api/db/flat-history?filterName=&panelKey=&limit=&offset=
  ///
  /// Distinct from the calibration UI's `listFlats()` for the same reason
  /// the dark-library variant is — see the comment on [fetchDarkLibrary].
  Future<RemotePage<RemoteDbFlatHistoryRow>> fetchFlatHistory({
    String? filterName,
    int? panelKey,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('db/flat-history', {
      if (filterName != null && filterName.isNotEmpty) 'filterName': filterName,
      if (panelKey != null) 'panelKey': panelKey.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteDbFlatHistoryRow.fromJson);
  }

  // Wave 7B replay scrubber — per-run endpoints.
  Future<RemoteSequenceRunDetail> fetchSequenceRunById(int runId) async {
    final response = await _get('sequence-runs/$runId');
    final run = response['run'];
    if (run is! Map) {
      throw StateError(
          'Malformed /sequence-runs/$runId response: missing run object');
    }
    return RemoteSequenceRunDetail.fromJson(run.cast<String, dynamic>());
  }

  Future<RemoteReplayEventsPage> fetchSequenceRunEvents(
    int runId, {
    int? sinceMs,
    int? untilMs,
    String? severityMin,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('sequence-runs/$runId/events', {
      if (sinceMs != null) 'since': sinceMs.toString(),
      if (untilMs != null) 'until': untilMs.toString(),
      if (severityMin != null && severityMin.isNotEmpty)
        'severityMin': severityMin,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemoteReplayEventsPage.fromJson(response);
  }

  Future<RemotePage<RemoteReplayFrame>> fetchSequenceRunFrames(
    int runId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('sequence-runs/$runId/frames', {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteReplayFrame.fromJson);
  }

  // =========================================================================
  // P2-11 — plugin management. Methods live on NetworkBackend because the
  // FfiBackend manages plugins directly via PluginHost; the network path
  // is the only one that needs HTTP wiring.
  // =========================================================================

  /// GET /api/plugins
  Future<List<RemotePluginManifest>> listPlugins() async {
    final response = await _get('plugins');
    final raw = response['items'];
    if (raw is! List) {
      throw StateError('Malformed /plugins response: missing items list');
    }
    return raw
        .whereType<Map>()
        .map((m) => RemotePluginManifest.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// POST /api/plugins/upload — sends the plugin bytes with `filename` as
  /// a query parameter. Server computes SHA-256, persists the file under
  /// the app-data plugin directory, and returns the new manifest.
  Future<RemotePluginManifest> uploadPlugin(
    List<int> bytes, {
    required String filename,
  }) async {
    final response = await _postRaw(
      'plugins/upload',
      {'filename': filename},
      Uint8List.fromList(bytes),
      contentType: 'application/octet-stream',
    );
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/upload response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// POST /api/plugins/{id}/enable
  Future<RemotePluginManifest> enablePlugin(String pluginId) async {
    final response = await _post('plugins/$pluginId/enable');
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/enable response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// POST /api/plugins/{id}/disable
  Future<RemotePluginManifest> disablePlugin(String pluginId) async {
    final response = await _post('plugins/$pluginId/disable');
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/disable response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// DELETE /api/plugins/{id}
  Future<void> uninstallPlugin(String pluginId) async {
    await _delete('plugins/$pluginId');
  }

  // [Wave 6E log tail] — client surface for the headless server's
  // remote-log endpoints. Lets the mobile log tab show ENTRIES emitted on
  // the host (not just NightshadeEvents) when the backend is networked.
  //
  // Wire shapes mirror `apps/desktop/lib/headless_api/handlers/log_handlers.dart`:
  //   GET  /api/logs/recent       — JSON { entries: [...], count, totalBuffered }
  //   GET  /api/logs/tail         — SSE  `id: <iso>\nevent: log\ndata: <json>\n\n`
  //   POST /api/logs/clear        — JSON { /* server-defined; we discard */ }
  //
  // We deliberately keep these methods OUT of [NightshadeBackend]'s
  // abstract surface because the local FFI backend has no equivalent
  // remote-log concept (it consumes the LoggingService directly). UI
  // callers do an `is NetworkBackend` check before invoking these.

  /// Fetch the last `limit` entries from the server's in-memory ring
  /// buffer, optionally filtered by severity and source substring.
  /// Throws on transport errors (let the UI display the failure rather
}
