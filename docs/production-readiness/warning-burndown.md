# Warning Burndown

| Status | File | Code | Owner | Notes |
| --- | --- | --- | --- | --- |
| Closed | packages/nightshade_bridge/lib/src/bridge_stub.dart | INVALID_USE_OF_INTERNAL_MEMBER | Core Bridge | Replaced direct FRB internal calls with public `api.dart` wrappers. |
| Closed | packages/nightshade_core/lib/src/models/flat_wizard/flat_wizard_state.dart | INVALID_ANNOTATION_TARGET | Core Models | Replaced `JsonKey` parameter annotation with runtime-only converter. |
| Closed | packages/nightshade_core/lib/src/providers/filter_offset_provider.dart | DEAD_NULL_AWARE_EXPRESSION | Core Providers | Removed dead null-aware branch for non-nullable list. |
| Closed | workspace production scope | UNUSED_* family | App/Core | Production analyzer gate now reports warnings=0 under `analyzer-policy.yaml`. |
