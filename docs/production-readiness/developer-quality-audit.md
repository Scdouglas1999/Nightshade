# Developer Quality Audit

- Passed: `true`
- Issues: `0`

This rollup consumes UI consistency, headless API contract, headless route policy, headless response helper, oversized-file, and structured logging evidence. It fails on blocking UI, API contract, route-policy, response-helper, or correlation logging regressions. Oversized files remain planning evidence.

## Checks

| Status | Check | Evidence | Metrics |
| --- | --- | --- | --- |
| PASS | UI consistency rules | `docs/production-readiness/ui-consistency-audit.json` | findingCount=203; blockingFindingCount=0; rawButtonStyle=0; largeRadius=0; emptyCallback=0; fakeCallback=0; stubCallback=0; headlessRouteNotAdvertised=0; designSystemGalleryReady=true; designSystemGalleryMissing=0; rawMaterialColor=203; semanticRawMaterialColor=0; intentionalImageOverlayColor=203 |
| PASS | Headless API contract | `docs/production-readiness/headless-api-contract-audit.json` | registeredRouteCount=295; advertisedRouteCount=295; openApiOperationCount=293; networkBackendRouteCount=255; networkBackendMissingOnServer=0; openApiMetadataCoverage=9/9; webSocketContractCoverage=4/4; networkBackendContractCoverage=3/3; versionNegotiationCoverage=10/10 |
| PASS | Headless route policy | `docs/production-readiness/headless-route-policy-audit.json` | issueCount=0; highRiskPolicyCount=19; defaultLimitedPolicyCount=9; ordinaryReadLimited=false; fileBrowseAuditAction=file_browse; bodyLimitRouteCount=6; bodyLimitedApiWriteRouteCount=161; serverMiddlewareTestCount=4 |
| PASS | Headless response helpers | `docs/production-readiness/headless-response-helper-audit.json` | issueCount=0; rawResponseCallCount=2; intentionalRawResponseCallCount=2; unclassifiedRawResponseCallCount=0; jsonContentTypeCount=1; helperImportCount=26; helperCallCount=759 |
| PASS | Oversized files | `docs/production-readiness/oversized-file-audit.json` | scannedFileCount=716; warningFileCount=65; criticalFileCount=16; prioritySplitCandidateCount=6; warningLineLimit=1000; criticalLineLimit=2500; releaseBlocking=false |
| PASS | Structured request/audit logging | `packages/nightshade_core/lib/src/services/logging_service.dart; packages/nightshade_core/test/services/logging_service_test.dart; apps/desktop/lib/headless_api_server.dart; packages/nightshade_core/lib/src/backend/network_backend.dart` | requiredFileCount=4; missingTextCount=0; requestCorrelationFieldsRequired=true; auditCorrelationFieldsRequired=true; networkBackendCorrelationRequired=true |
