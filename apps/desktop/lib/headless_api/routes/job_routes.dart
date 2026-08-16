/// Declarative route table for the long-running job model.
///
/// Counterpart to `handlers/job_handlers.dart`. Parametric handlers are passed
/// as method tear-offs, not wrapped in a closure: shelf_router introspects the
/// handler's arity and [JobHandlers.handleGetJob] and friends are already
/// declared `(Request, String)`.
library;

import '../handlers/job_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [JobHandlers].
List<HeadlessRoute> buildJobRoutes(JobHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/jobs', h.handleListJobs),
  HeadlessRoute(HttpMethod.get, '/api/jobs/<jobId>', h.handleGetJob),
  HeadlessRoute(HttpMethod.post, '/api/jobs/<jobId>/cancel', h.handleCancelJob),
  HeadlessRoute(HttpMethod.delete, '/api/jobs/<jobId>', h.handlePurgeJob),
];
