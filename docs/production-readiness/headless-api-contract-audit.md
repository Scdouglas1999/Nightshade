# Headless API Contract Audit

- Passed: `true`
- Registered routes: `295`
- Advertised routes: `295`
- Advertised HTTP routes: `293`
- OpenAPI paths: `270`
- NetworkBackend routes: `255`
- Registered not advertised: `0`
- Advertised not registered: `0`
- NetworkBackend missing on server: `0`
- Advertised HTTP missing OpenAPI: `0`
- OpenAPI metadata coverage: `9/9`
- WebSocket contract coverage: `4/4`
- NetworkBackend contract coverage: `3/3`
- Version negotiation coverage: `10/10`

This audit compares the `HeadlessApiServer` route registrations, `/api/info` advertised endpoint table, generated OpenAPI route surface, and `NetworkBackend` call sites. It is a source-level contract audit; runtime smoke tests still verify packaged server behavior.

## OpenAPI Metadata Coverage

| Marker | Present |
| --- | --- |
| `request_body_limit_extension` | `true` |
| `rate_limit_extension` | `true` |
| `audit_action_extension` | `true` |
| `oversized_response` | `true` |
| `rate_limited_response` | `true` |
| `bearer_security_scheme` | `true` |
| `required_scope_extension` | `true` |
| `public_endpoint_extension` | `true` |
| `api_version_mismatch_response` | `true` |

## WebSocket Contract Coverage

| Marker | Present |
| --- | --- |
| `heartbeat_ping_pong` | `true` |
| `compatibility_before_socket` | `true` |
| `headless_event_wrapper_to_event_stream` | `true` |
| `polar_alignment_event_stream` | `true` |

## NetworkBackend Contract Coverage

| Marker | Present |
| --- | --- |
| `advertised_endpoints_match_registered_routes` | `true` |
| `network_backend_calls_registered_routes` | `true` |
| `openapi_includes_every_http_route` | `true` |

## Version Negotiation Coverage

| Marker | Present |
| --- | --- |
| `shared_compatibility_policy` | `true` |
| `shared_compatibility_tests` | `true` |
| `server_http_version_middleware_test` | `true` |
| `server_websocket_version_middleware_test` | `true` |
| `network_backend_preflight` | `true` |
| `network_backend_version_headers` | `true` |
| `network_backend_websocket_query_version` | `true` |
| `dashboard_http_version_header` | `true` |
| `dashboard_websocket_query_version` | `true` |
| `docs_user_facing_compatibility` | `true` |
