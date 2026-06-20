// Pillar C ("Constellation") — the HTTP client for a Nightshade hub.
//
// A Constellation hub is a self-hosted, LAN-or-internet REST service
// (`server/nightshade_hub/`, `docs/nightshade_5_0_contracts.md` §5) that fuses
// per-tile additive accumulators from many imagers into a community co-add.
// This client speaks that wire contract verbatim: a bearer token carries the
// account's `contribute`/`read` scopes, JSON bodies everywhere except the tile
// blobs (the `.nst` accumulator payload travels as `application/octet-stream`),
// and the `order` query parameter pins the HEALPix tiling so a mismatched hub
// is detected up front.
//
// Transport mirrors `webdav_sync_target.dart`: nothing but `package:http`, a
// single `_send` choke point that maps `SocketException`/`ClientException`/
// timeouts onto a typed [ConstellationException], and a `_throwForStatus` that
// classifies the HTTP status. The client is deliberately stateless beyond its
// base URL + token so one instance can be created per hub from a provider.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, SocketException;

import 'package:http/http.dart' as http;

import 'constellation_models.dart';

/// Thin REST client for one Constellation hub (one account / bearer token).
///
/// Every method maps to a single endpoint in the §5 contract. Heavy tile
/// transfers ([pushTile] / [pullTile]) stream the `.nst` blob to/from disk so a
/// deep tile never has to be held in memory twice.
class ConstellationClient {
  /// Hub root, e.g. `https://hub.example.org` or `http://192.168.1.20:8088`.
  /// The `/v1` base path is appended internally.
  final Uri hubBaseUrl;

  /// Account bearer token (scopes `contribute` / `read` / `admin`).
  final String bearerToken;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// [client] is injectable for tests (`package:http/testing.dart` MockClient).
  /// When omitted a real client is created and owned here ([close] disposes it).
  ConstellationClient({
    required this.hubBaseUrl,
    required this.bearerToken,
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _timeout = timeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer $bearerToken',
  };

  /// Resolve a `/v1`-rooted path (+ optional query) against [hubBaseUrl],
  /// preserving any path prefix the hub is mounted under.
  Uri _v1(String relPath, [Map<String, String>? query]) {
    final segments = <String>[
      ...hubBaseUrl.pathSegments.where((s) => s.isNotEmpty),
      'v1',
      ...relPath.split('/').where((s) => s.isNotEmpty),
    ];
    return hubBaseUrl.replace(
      pathSegments: segments,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(_authHeaders);
    if (headers != null) request.headers.addAll(headers);
    if (bodyBytes != null) request.bodyBytes = bodyBytes;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on ConstellationException {
      rethrow;
    } on SocketException catch (e) {
      throw ConstellationException(
        'Cannot reach ${uri.host}: ${e.message}',
        kind: ConstellationErrorKind.network,
      );
    } on http.ClientException catch (e) {
      throw ConstellationException(
        'Request to ${uri.host} failed: ${e.message}',
        kind: ConstellationErrorKind.network,
      );
    } on TimeoutException {
      throw ConstellationException(
        'Request to ${uri.host} timed out',
        kind: ConstellationErrorKind.network,
      );
    }
  }

  Never _throwForStatus(http.Response response, String operation) {
    final status = response.statusCode;
    final kind = switch (status) {
      401 || 403 => ConstellationErrorKind.auth,
      404 => ConstellationErrorKind.notFound,
      // A 409 from the hub is a geometry/order mismatch (§5) — the tiling on
      // this hub does not match ours, so the contribution can never fuse.
      409 => ConstellationErrorKind.geometryMismatch,
      405 || 423 => ConstellationErrorKind.conflict,
      >= 500 => ConstellationErrorKind.server,
      _ => ConstellationErrorKind.unknown,
    };
    final detail = switch (kind) {
      ConstellationErrorKind.auth =>
        'authentication failed — token missing the required scope',
      ConstellationErrorKind.notFound => 'not found on hub',
      ConstellationErrorKind.geometryMismatch =>
        'tile geometry/order mismatch (hub uses a different HEALPix tiling)',
      ConstellationErrorKind.conflict => 'hub state conflict',
      ConstellationErrorKind.server => 'hub server error',
      _ => 'unexpected hub response',
    };
    final body = response.body.trim();
    throw ConstellationException(
      '$operation failed: $detail (HTTP $status)'
      '${body.isEmpty ? '' : ' — $body'}',
      kind: kind,
      statusCode: status,
    );
  }

  Map<String, dynamic> _decodeJson(http.Response response, String operation) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw ConstellationException(
        '$operation returned malformed JSON: $e',
        kind: ConstellationErrorKind.protocol,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ConstellationException(
        '$operation returned a non-object payload',
        kind: ConstellationErrorKind.protocol,
      );
    }
    return decoded;
  }

  // --- Endpoints ----------------------------------------------------------

  /// `GET /v1/info` — hub identity + tiling. Call before contributing so an
  /// order/tile-size mismatch is caught before any blob leaves the device.
  Future<HubInfo> info() async {
    final response = await _send('GET', _v1('info'));
    if (response.statusCode != 200) _throwForStatus(response, 'Hub info');
    return HubInfo.fromJson(_decodeJson(response, 'Hub info'));
  }

  /// `GET /v1/targets` — the swarm's shared-target listing. The browse payload
  /// is not pinned field-for-field by the contract (§5 leaves it to the hub), so
  /// the decoded JSON is returned raw (a `List` or a `{ "targets": [...] }`
  /// envelope) for [ConstellationService] to map into [SharedTarget]s.
  Future<Object?> browseRaw() async {
    final response = await _send('GET', _v1('targets'));
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Browse shared targets');
    }
    try {
      return jsonDecode(response.body);
    } on FormatException catch (e) {
      throw ConstellationException(
        'Browse shared targets returned malformed JSON: $e',
        kind: ConstellationErrorKind.protocol,
      );
    }
  }

  /// `POST /v1/accounts` — register an account on a hub that allows open
  /// signup (or admin-gated, in which case the bearer token must carry the
  /// `admin` scope). Returns the new account id + its issued bearer token,
  /// which the caller persists to build a per-hub [ConstellationClient].
  Future<HubAccount> createAccount({
    required String publicKey,
    required String displayName,
  }) async {
    final response = await _send(
      'POST',
      _v1('accounts'),
      headers: {'Content-Type': 'application/json'},
      bodyBytes: utf8.encode(
        jsonEncode({'publicKey': publicKey, 'displayName': displayName}),
      ),
    );
    final status = response.statusCode;
    if (status != 200 && status != 201) {
      _throwForStatus(response, 'Create account');
    }
    return HubAccount.fromJson(_decodeJson(response, 'Create account'));
  }

  /// `POST /v1/tiles/{tileId}/contributions?order=…` — upload the additive
  /// `.nst` delta at [deltaPath]. Provenance hints (frame/integration deltas +
  /// instrument fingerprint, *not* PII) ride as headers per the contract.
  Future<ContributionReceipt> pushTile({
    required int tileId,
    required int order,
    required String deltaPath,
    int framesDelta = 0,
    double integrationSecondsDelta = 0,
    double? medianFwhm,
    String? solver,
    String? instrument,
  }) async {
    final file = File(deltaPath);
    if (!file.existsSync()) {
      throw ConstellationException(
        'Contribution delta not found: $deltaPath',
        kind: ConstellationErrorKind.notFound,
      );
    }
    final bytes = await file.readAsBytes();
    final headers = <String, String>{
      'Content-Type': 'application/octet-stream',
      'framesDelta': '$framesDelta',
      'integrationSecondsDelta': '$integrationSecondsDelta',
      if (medianFwhm != null) 'medianFwhm': '$medianFwhm',
      if (solver != null && solver.isNotEmpty) 'solver': solver,
      if (instrument != null && instrument.isNotEmpty) 'instrument': instrument,
    };
    final response = await _send(
      'POST',
      _v1('tiles/$tileId/contributions', {'order': '$order'}),
      headers: headers,
      bodyBytes: bytes,
    );
    final status = response.statusCode;
    if (status != 200 && status != 201) {
      _throwForStatus(response, 'Push tile $tileId');
    }
    return ContributionReceipt.fromJson(
      _decodeJson(response, 'Push tile $tileId'),
    );
  }

  /// `GET /v1/tiles/{tileId}?order=…&finalized=…` — download the community
  /// co-add for [tileId] to [outPath]. [finalized] true pulls a rendered FITS;
  /// false pulls the merged `.nst` accumulator (still additive, so it can be
  /// merged locally). Returns [outPath] on success.
  Future<String> pullTile({
    required int tileId,
    required int order,
    required String outPath,
    bool finalized = true,
  }) async {
    final response = await _send(
      'GET',
      _v1('tiles/$tileId', {'order': '$order', 'finalized': '$finalized'}),
    );
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Pull tile $tileId');
    }
    final out = File(outPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(response.bodyBytes, flush: true);
    return outPath;
  }

  /// `DELETE /v1/contributions/{id}` — retract a prior contribution. The hub
  /// subtracts it from the fused tile (exact when no clipping is configured).
  Future<RetractionReceipt> retract(String remoteContributionId) async {
    final response = await _send(
      'DELETE',
      _v1('contributions/$remoteContributionId'),
    );
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Retract $remoteContributionId');
    }
    return RetractionReceipt.fromJson(
      _decodeJson(response, 'Retract $remoteContributionId'),
    );
  }

  // --- Follow-the-night handoff -------------------------------------------

  /// `GET /v1/handoff/{targetId}` — ask whether a shared target is dark and
  /// available for this user right now. Returns null when the hub has no
  /// handoff state for the target (HTTP 404 is treated as "no claim").
  Future<HandoffClaim?> queryHandoff(int targetId) async {
    final response = await _send('GET', _v1('handoff/$targetId'));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Handoff query $targetId');
    }
    return HandoffClaim.fromJson(
      _decodeJson(response, 'Handoff query $targetId'),
    );
  }

  /// `POST /v1/handoff/{targetId}/claim` — take the active-imager baton for a
  /// shared target so the swarm does not double-collect the same sky.
  Future<HandoffClaim?> claimHandoff(int targetId) async {
    final response = await _send('POST', _v1('handoff/$targetId/claim'));
    if (response.statusCode == 404) return null;
    // 409 here means another user holds the baton — surfaced as a conflict so
    // the caller can fall back to the next dark target.
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Handoff claim $targetId');
    }
    return HandoffClaim.fromJson(
      _decodeJson(response, 'Handoff claim $targetId'),
    );
  }

  /// `POST /v1/handoff/{targetId}/release` — hand the baton back when this
  /// user's window on the target closes (set below the horizon / dawn).
  Future<void> releaseHandoff(int targetId) async {
    final response = await _send('POST', _v1('handoff/$targetId/release'));
    if (response.statusCode != 200) {
      _throwForStatus(response, 'Handoff release $targetId');
    }
  }
}
