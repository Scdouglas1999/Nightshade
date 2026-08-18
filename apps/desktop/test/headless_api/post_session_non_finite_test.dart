// A number JSON cannot carry has to be refused by the request, not by the
// encoder inside the job.
//
// `POST /api/post-session/integrate` with `"exposuresSec":[1e400]` answered
// `200 {"jobId":…,"status":"queued"}` and then failed the job with
// "Converting object to an encodable object failed: Infinity" — the only
// refusal on this surface naming neither the field, the index, nor a next step.
// The guard written for exactly this input lives in the bridge
// (`post_session/helpers.rs`: "exposuresSec[0] is …, which is not a number of
// seconds") and could never run, because `jsonEncode` threw before the payload
// reached it.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/post_session_handlers.dart';
import 'package:nightshade_desktop/headless_api/job_manager.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase database;
  late ProviderContainer container;
  late JobManager jobManager;
  late PostSessionHandlers handlers;

  setUp(() {
    database = NightshadeDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    jobManager = JobManager(emitEvent: (_) {});
    handlers = PostSessionHandlers(container, jobManager: jobManager);
  });

  tearDown(() async {
    await jobManager.dispose();
    container.dispose();
    await database.close();
  });

  // The body is a raw JSON string, never `jsonEncode`d here: `1e400` is how a
  // client writes an overflowing literal, and Dart's own encoder cannot write
  // the `double.infinity` its decoder reads back from it. This is the byte
  // sequence curl put on the wire against the running host.
  Request post(String path, String body) => Request(
    'POST',
    Uri.parse('http://localhost$path'),
    body: body,
    headers: {'content-type': 'application/json'},
  );

  String integrateBody({String exposures = '', String settings = '{}'}) =>
      '{"runId":"x","lightPaths":["/tmp/a.fits"],'
      '${exposures.isEmpty ? '' : '"exposuresSec":$exposures,'}'
      '"calibration":{},"settings":$settings,'
      '"output":{"masterFitsPath":"/tmp/o.fits"}}';

  test('integrate names the non-finite exposure by field and index', () async {
    final response = await translateHandlerErrors(
      handlers.handleIntegrateSession(
        post(
          '/api/post-session/integrate',
          integrateBody(exposures: '[1e400]'),
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['field'], 'exposuresSec[0]');
    expect(body['code'], 'invalid_request');
    expect(
      body['message'],
      'exposuresSec[0] is Infinity, which is not a finite number; every '
      'numeric field must be a finite value',
    );
    expect(
      jobManager.length,
      0,
      reason: 'a refused request registers no job to poll',
    );
  });

  test('master-accumulate refuses the same input the same way', () async {
    final response = await translateHandlerErrors(
      handlers.handleMasterAccumulate(
        post(
          '/api/post-session/master-accumulate',
          '{"op":"add","masterPath":"/tmp/m.fits",'
              '"lightPaths":["/tmp/a.fits"],"exposuresSec":[-1e400],'
              '"calibration":{},"settings":{}}',
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['field'], 'exposuresSec[0]');
    expect(body['message'], contains('-Infinity'));
    expect(jobManager.length, 0);
  });

  test('a nested non-finite is named by its own path', () async {
    final response = await translateHandlerErrors(
      handlers.handleIntegrateSession(
        post(
          '/api/post-session/integrate',
          integrateBody(settings: '{"sigmaHigh":1e400}'),
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['field'], 'settings.sigmaHigh');
    expect(jobManager.length, 0);
  });

  test('analyze-night refuses a non-finite exposure too', () async {
    final response = await translateHandlerErrors(
      handlers.handleAnalyzeNight(
        post(
          '/api/post-session/analyze-night',
          '{"qualities":[1.0],"weights":[1.0],"exposuresS":[1.0,1e400]}',
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['field'], 'exposuresS[1]');
    expect(jobManager.length, 0);
  });

  test('a body of finite numbers still queues its job', () async {
    final response = await translateHandlerErrors(
      handlers.handleIntegrateSession(
        post(
          '/api/post-session/integrate',
          integrateBody(exposures: '[60.0,60.0]'),
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['status'], 'queued');
    expect(
      jobManager.length,
      1,
      reason: 'the guard refuses only what the encoder cannot carry',
    );
  });
}
