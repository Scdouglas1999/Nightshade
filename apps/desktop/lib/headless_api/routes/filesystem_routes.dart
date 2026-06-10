/// Declarative route table for the remote filesystem-browse surface.
///
/// Counterpart to `handlers/filesystem_handlers.dart`. The browse
/// endpoint is sandboxed inside the configured app-data directories;
/// the validate endpoint round-trips a candidate path to confirm it is
/// writable.
library;

import '../handlers/filesystem_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [FileSystemHandlers].
List<HeadlessRoute> buildFileSystemRoutes(
  FileSystemHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/files/browse', h.handleBrowseDirectories),
  HeadlessRoute(
    HttpMethod.post,
    '/api/files/validate',
    h.handleValidateDirectory,
  ),
];
