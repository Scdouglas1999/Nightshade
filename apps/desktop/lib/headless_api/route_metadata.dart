/// Metadata about the headless HTTP routes: body limits, OpenAPI generation,
/// path classification (auth scope / audit / resource) and rate limiting.
///
/// Split into `route_metadata/` for size; this barrel keeps the prefixed
/// `import '.../route_metadata.dart' as route_metadata;` call sites unchanged.
library;

export 'route_metadata/body_limits.dart';
export 'route_metadata/openapi.dart';
export 'route_metadata/path_classification.dart';
export 'route_metadata/rate_limiting.dart';
