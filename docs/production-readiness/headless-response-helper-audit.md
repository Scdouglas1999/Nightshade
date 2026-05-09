# Headless Response Helper Audit

- Passed: `true`
- Issues: `0`
- Scanned files: `26`
- Raw `Response.*` calls: `2`
- Intentional raw `Response.*` calls: `2`
- Unclassified raw `Response.*` calls: `0`
- JSON content-type mentions: `1`
- JSON helper imports: `26`
- JSON helper calls: `759`

This audit proves typed response helpers exist and are covered by unit tests. Raw `Response.*` route calls are allowed only in the headless server for static dashboard assets and empty CORS preflight behavior.

## Required Files

| File | Exists | Missing required text |
| --- | --- | ---: |
| `apps/desktop/lib/headless_api/response_helpers.dart` | `true` | `0` |
| `apps/desktop/test/headless_api/response_helpers_test.dart` | `true` | `0` |

## Classified Raw Responses

| File | Raw | Intentional | Unclassified | Reasons |
| --- | ---: | ---: | ---: | --- |
| `apps/desktop/lib/headless_api_server.dart` | `2` | `2` | `0` | dashboard static asset byte response<br>empty CORS preflight response |
