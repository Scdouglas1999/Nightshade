# Platform Capability Audit

- Passed: `true`
- Files: `13`
- Issues: `0`

This audit checks that platform capability support is visible and aligned across the shared model, headless API responses, settings UI, backend selector gating, docs, and tests.

## Files

| File | Exists | Missing required text |
| --- | --- | ---: |
| `packages/nightshade_core/lib/src/models/backend/platform_capabilities.dart` | `true` | `0` |
| `packages/nightshade_core/test/models/platform_capabilities_test.dart` | `true` | `0` |
| `apps/desktop/lib/headless_api_server.dart` | `true` | `0` |
| `apps/desktop/lib/headless_api/handlers/equipment_handlers.dart` | `true` | `0` |
| `apps/desktop/test/headless_api/equipment_handlers_test.dart` | `true` | `0` |
| `apps/desktop/test/headless_api/auth_middleware_test.dart` | `true` | `0` |
| `packages/nightshade_app/lib/screens/equipment/widgets/backend_selector_chips.dart` | `true` | `0` |
| `packages/nightshade_app/test/screens/equipment/backend_selector_chips_test.dart` | `true` | `0` |
| `packages/nightshade_app/lib/screens/settings/widgets/connection_settings.dart` | `true` | `0` |
| `packages/nightshade_app/test/screens/settings/platform_capabilities_settings_test.dart` | `true` | `0` |
| `docs/supported-hardware-by-platform.md` | `true` | `0` |
| `docs/production-readiness/feature-parity-matrix.md` | `true` | `0` |
| `docs/api/web-server-api.md` | `true` | `0` |
