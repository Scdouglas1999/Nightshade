import 'package:nightshade_desktop/headless_api/response_helpers.dart';
import 'package:nightshade_desktop/headless_api/validation.dart';
import 'package:shelf/shelf.dart';

Future<Response> translateHandlerErrors(Future<Response> response) async {
  try {
    return await response;
  } on BadRequestError catch (error) {
    return jsonBadRequest(error.toJsonBody());
  } on HandlerFailure catch (error) {
    return jsonResponse(
      error.toJsonBody(requestId: 'test-request'),
      statusCode: error.statusCode,
    );
  } catch (_) {
    return jsonInternalServerError({
      'error': 'internal_error',
      'requestId': 'test-request',
    });
  }
}
