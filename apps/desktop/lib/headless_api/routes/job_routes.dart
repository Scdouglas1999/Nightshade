/// Declarative route table for the long-running job model.
///
/// Counterpart to `handlers/job_handlers.dart`. The previous inline
/// registration wrapped each parametric route in a `(Request req,
/// String jobId) => h.handleX(req, jobId)` closure — that wrapper is
/// redundant because shelf_router introspects the handler's arity, and
/// [JobHandlers.handleGetJob] / [JobHandlers.handleCancelJob] /
/// [JobHandlers.handlePurgeJob] are already declared as
/// `(Request, String)`. Passing the method tear-off directly produces
/// identical dispatch with one less allocation per request.
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
