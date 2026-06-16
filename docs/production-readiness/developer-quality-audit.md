# Developer Quality Audit

- Passed: `true`
- Issues: `0`

This rollup consumes UI consistency, headless API contract, headless route policy, headless response helper, oversized-file, and structured logging evidence. It fails on blocking UI, API contract, route-policy, response-helper, or correlation logging regressions. Oversized files remain planning evidence.

## Checks

| Status | Check | Evidence | Metrics |
| --- | --- | --- | --- |
| PASS | UI consistency rules | `docs/production-readiness/ui-consistency-audit.json` | findingCount=136; blockingFindingCount=0; rawButtonStyle=0; largeRadius=0; emptyCallback=0; fakeCallback=0; stubCallback=0; headlessRouteNotAdvertised=0; designSystemGalleryReady=true; designSystemGalleryMissing=0; rawMaterialColor=136; semanticRawMaterialColor=0; intentionalImageOverlayColor=136 |
| PASS | Headless API contract | `docs/production-readiness/headless-api-contract-audit.json` | registeredRouteCount=467; advertisedRouteCount=467; openApiOperationCount=464; networkBackendRouteCount=372; networkBackendMissingOnServer=0; openApiMetadataCoverage=9/9; webSocketContractCoverage=4/4; networkBackendContractCoverage=4/4; versionNegotiationCoverage=10/10 |
| PASS | Headless route policy | `docs/production-readiness/headless-route-policy-audit.json` | issueCount=0; highRiskPolicyCount=19; defaultLimitedPolicyCount=9; ordinaryReadLimited=false; fileBrowseAuditAction=file_browse; bodyLimitRouteCount=6; bodyLimitedApiWriteRouteCount=222; serverMiddlewareTestCount=4 |
| PASS | Headless response helpers | `docs/production-readiness/headless-response-helper-audit.json` | issueCount=0; rawResponseCallCount=0; intentionalRawResponseCallCount=0; unclassifiedRawResponseCallCount=0; jsonContentTypeCount=2; helperImportCount=43; helperCallCount=675 |
| PASS | Oversized files | `docs/production-readiness/oversized-file-audit.json` | scannedFileCount=1788; warningFileCount=0; criticalFileCount=0; prioritySplitCandidateCount=0; modularizedSourceFamilyCount=5; warningLineLimit=1000; criticalLineLimit=2500; releaseBlocking=false |
| PASS | Structured request/audit logging | `packages/nightshade_core/lib/src/services/logging_service.dart; packages/nightshade_core/test/services/logging_service_test.dart; apps/desktop/lib/headless_api_server.dart; packages/nightshade_core/lib/src/backend/network_backend.dart` | requiredFileCount=4; missingTextCount=0; requestCorrelationFieldsRequired=true; auditCorrelationFieldsRequired=true; networkBackendCorrelationRequired=true |
