import 'dart:convert';
import 'dart:io';

const _jsonOutputPath = 'docs/production-readiness/public-release-gate.json';
const _markdownOutputPath = 'docs/production-readiness/public-release-gate.md';
const _checklistAuditPath =
    'docs/production-readiness/public-release-checklist-audit.json';

void main(List<String> args) async {
  final failOnNotReady = args.contains('--fail-on-not-ready');
  final checks = <_GateCheck>[
    _checkAnalyzer(),
    _checkPlaceholderAudit(),
    _checkFailClosedAudit(),
    _checkUiConsistency(),
    _checkDeveloperQuality(),
    _checkWindowsBundle(),
    _checkDependencyHygiene(),
    _checkHeadlessApiContract(),
    _checkHeadlessRoutePolicy(),
    _checkHeadlessResponseHelpers(),
    _checkDocsLinks(),
    _checkReleaseDocs(),
    _checkPlatformCapabilities(),
    _checkPublicReleaseSelfTests(),
    _checkReleaseStaging(),
    _checkLinuxReleaseWorkflow(),
    _checkLinuxEnvironment(),
    _checkHardwareAvailability(),
    _checkSyntheticMigrationRegression(),
    _checkManualMigration(),
    _checkMobileRemoteSmoke(),
    _checkMobileReconnectSmoke(),
    _checkSecondDeviceLan(),
    _checkRealControlActions(),
    _checkFinalChecklist(),
  ];

  final blockers = checks.where((check) => !check.passed).toList();
  final ready = blockers.isEmpty;
  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'decision': ready ? 'READY' : 'NOT_READY',
    'ready': ready,
    'passedCount': checks.length - blockers.length,
    'blockerCount': blockers.length,
    'checks': checks.map((check) => check.toJson()).toList(),
  };

  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(
    ready: ready,
    checks: checks,
    blockers: blockers,
  ));

  stdout.writeln('Public release gate complete.');
  stdout.writeln('Decision: ${ready ? 'READY' : 'NOT_READY'}');
  stdout.writeln('Passed checks: ${checks.length - blockers.length}');
  stdout.writeln('Blockers: ${blockers.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');

  if (failOnNotReady && !ready) {
    exit(1);
  }
}

_GateCheck _checkAnalyzer() {
  final data = _readJson('docs/production-readiness/analyzer-rollup.json');
  if (data == null) {
    return _missing(
        'production_analyzer', 'Analyzer rollup artifact is missing.');
  }
  final summary = data['summary'] as Map<String, dynamic>? ?? const {};
  final production = summary['production'] as Map<String, dynamic>? ?? const {};
  final errors = (production['errors'] as num?)?.toInt();
  final warnings = (production['warnings'] as num?)?.toInt();
  return _GateCheck(
    id: 'production_analyzer',
    label: 'Production analyzer',
    passed: errors == 0 && warnings == 0,
    evidence: 'docs/production-readiness/analyzer-rollup.json',
    detail: 'Production analyzer errors=$errors warnings=$warnings.',
  );
}

_GateCheck _checkPlaceholderAudit() {
  final highRisk = File('.audit_highrisk.txt');
  if (!highRisk.existsSync()) {
    return _missing(
      'placeholder_audit',
      'Placeholder audit artifact .audit_highrisk.txt is missing.',
    );
  }
  final text = highRisk.readAsStringSync();
  final highRiskHits =
      text.split('\n').where((line) => line.trim().isNotEmpty).length;
  return _GateCheck(
    id: 'placeholder_audit',
    label: 'Placeholder audit',
    passed: highRiskHits == 0,
    evidence: '.audit_highrisk.txt',
    detail: 'High-risk marker hits=$highRiskHits.',
  );
}

_GateCheck _checkFailClosedAudit() {
  final data = _readJson('docs/production-readiness/fail-closed-audit.json');
  if (data == null) {
    return _missing('fail_closed', 'Fail-closed audit artifact is missing.');
  }
  final violations = (data['violationCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'fail_closed',
    label: 'Fail-closed policy',
    passed: data['passed'] == true && violations == 0,
    evidence: 'docs/production-readiness/fail-closed-audit.json',
    detail: 'Fail-closed violations=$violations.',
  );
}

_GateCheck _checkUiConsistency() {
  final data = _readJson('docs/production-readiness/ui-consistency-audit.json');
  if (data == null) {
    return _missing(
        'ui_consistency', 'UI consistency audit artifact is missing.');
  }
  final findingCount = (data['findingCount'] as num?)?.toInt();
  final blockingFindingCount = (data['blockingFindingCount'] as num?)?.toInt();
  final countsByRule =
      data['countsByRule'] as Map<String, dynamic>? ?? const {};
  final rawColorClassifications =
      data['rawColorClassifications'] as Map<String, dynamic>? ?? const {};
  final designSystemGallery =
      data['designSystemGallery'] as Map<String, dynamic>? ?? const {};
  return _GateCheck(
    id: 'ui_consistency',
    label: 'UI consistency audit',
    passed: blockingFindingCount == 0,
    evidence:
        'docs/production-readiness/ui-consistency-audit.json; .ui_consistency_audit.txt',
    detail:
        'findings=$findingCount blockingFindings=$blockingFindingCount rawButtonStyle=${countsByRule['raw_button_style'] ?? 0} largeRadius=${countsByRule['large_radius'] ?? 0} emptyCallback=${countsByRule['empty_callback'] ?? 0} fakeCallback=${countsByRule['fake_callback'] ?? 0} stubCallback=${countsByRule['stub_callback'] ?? 0} headlessRouteNotAdvertised=${countsByRule['headless_route_not_advertised'] ?? 0} designSystemGalleryReady=${designSystemGallery['ready']} designSystemGalleryMissing=${countsByRule['design_system_gallery_missing'] ?? 0} semanticRawMaterialColors=${rawColorClassifications['semantic_theme_color'] ?? 0} intentionalImageOverlayColors=${rawColorClassifications['intentional_image_overlay'] ?? 0}.',
  );
}

_GateCheck _checkDeveloperQuality() {
  final data =
      _readJson('docs/production-readiness/developer-quality-audit.json');
  if (data == null) {
    return _missing(
      'developer_quality',
      'Developer quality audit artifact is missing.',
    );
  }
  final issueCount = (data['issueCount'] as num?)?.toInt();
  final checks = data['checks'] as List? ?? const [];
  final detailParts = <String>[];
  for (final rawCheck in checks) {
    if (rawCheck is! Map) continue;
    final check = rawCheck.cast<String, dynamic>();
    final metrics = check['metrics'] as Map<String, dynamic>? ?? const {};
    detailParts.add(
      '${check['id']}: passed=${check['passed']} metrics=${metrics.entries.map((entry) => '${entry.key}=${entry.value}').join(',')}',
    );
  }
  return _GateCheck(
    id: 'developer_quality',
    label: 'Developer quality audit',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/developer-quality-audit.json',
    detail: 'issues=$issueCount ${detailParts.join(' ')}.',
  );
}

_GateCheck _checkWindowsBundle() {
  final data = _readJson('docs/production-readiness/windows-bundle-audit.json');
  if (data == null) {
    return _missing(
      'windows_bundle',
      'Windows bundle audit artifact is missing.',
    );
  }
  final files = (data['fileCount'] as num?)?.toInt();
  final missing = (data['missingRequiredFileCount'] as num?)?.toInt();
  final disallowed = (data['disallowedFileCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'windows_bundle',
    label: 'Windows bundle audit',
    passed: data['passed'] == true && missing == 0 && disallowed == 0,
    evidence: 'docs/production-readiness/windows-bundle-audit.json',
    detail:
        'bundle=${data['bundlePath']} files=$files missingRequired=$missing disallowed=$disallowed.',
  );
}

_GateCheck _checkDependencyHygiene() {
  final data = _readJson('docs/production-readiness/dependency-hygiene.json');
  if (data == null) {
    return _missing(
      'dependency_hygiene',
      'Dependency hygiene audit artifact is missing.',
    );
  }
  final packages = (data['packageCount'] as num?)?.toInt();
  final violations = (data['violationCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'dependency_hygiene',
    label: 'Dependency hygiene',
    passed: data['passed'] == true && violations == 0,
    evidence: 'docs/production-readiness/dependency-hygiene.json',
    detail: 'packages=$packages violations=$violations.',
  );
}

_GateCheck _checkHeadlessApiContract() {
  final data =
      _readJson('docs/production-readiness/headless-api-contract-audit.json');
  if (data == null) {
    return _missing(
      'headless_api_contract',
      'Headless API contract audit artifact is missing.',
    );
  }
  final registered = (data['registeredRouteCount'] as num?)?.toInt();
  final advertised = (data['advertisedRouteCount'] as num?)?.toInt();
  final httpRoutes = (data['advertisedHttpRouteCount'] as num?)?.toInt();
  final openApiPaths = (data['openApiPathCount'] as num?)?.toInt();
  final networkBackend = (data['networkBackendRouteCount'] as num?)?.toInt();
  final registeredNotAdvertised =
      (data['registeredNotAdvertisedCount'] as num?)?.toInt();
  final advertisedNotRegistered =
      (data['advertisedNotRegisteredCount'] as num?)?.toInt();
  final networkMissing =
      (data['networkBackendMissingOnServerCount'] as num?)?.toInt();
  final openApiMissing =
      (data['advertisedHttpMissingOpenApiCount'] as num?)?.toInt();
  final openApiMetadata =
      data['openApiMetadataCoverage'] as Map<String, dynamic>? ?? const {};
  final openApiMetadataReady = openApiMetadata.isNotEmpty &&
      openApiMetadata.values.every((v) => v == true);
  final openApiMetadataCount =
      (data['openApiMetadataCoverageCount'] as num?)?.toInt() ??
          openApiMetadata.values.where((v) => v == true).length;
  final webSocketContract =
      data['webSocketContractCoverage'] as Map<String, dynamic>? ?? const {};
  final webSocketContractReady = webSocketContract.isNotEmpty &&
      webSocketContract.values.every((v) => v == true);
  final webSocketContractCount =
      (data['webSocketContractCoverageCount'] as num?)?.toInt() ??
          webSocketContract.values.where((v) => v == true).length;
  final versionNegotiation =
      data['versionNegotiationCoverage'] as Map<String, dynamic>? ?? const {};
  final versionNegotiationReady = versionNegotiation.isNotEmpty &&
      versionNegotiation.values.every((v) => v == true);
  final versionNegotiationCount =
      (data['versionNegotiationCoverageCount'] as num?)?.toInt() ??
          versionNegotiation.values.where((v) => v == true).length;
  return _GateCheck(
    id: 'headless_api_contract',
    label: 'Headless API contract',
    passed: data['passed'] == true &&
        openApiMetadataReady &&
        webSocketContractReady &&
        versionNegotiationReady,
    evidence: 'docs/production-readiness/headless-api-contract-audit.json',
    detail:
        'registered=$registered advertised=$advertised advertisedHttp=$httpRoutes openApiPaths=$openApiPaths networkBackendRoutes=$networkBackend registeredNotAdvertised=$registeredNotAdvertised advertisedNotRegistered=$advertisedNotRegistered networkBackendMissingOnServer=$networkMissing advertisedHttpMissingOpenApi=$openApiMissing openApiMetadataCoverage=$openApiMetadataCount/${openApiMetadata.length} webSocketContractCoverage=$webSocketContractCount/${webSocketContract.length} versionNegotiationCoverage=$versionNegotiationCount/${versionNegotiation.length}.',
  );
}

_GateCheck _checkHeadlessRoutePolicy() {
  final data =
      _readJson('docs/production-readiness/headless-route-policy-audit.json');
  if (data == null) {
    return _missing(
      'headless_route_policy',
      'Headless route policy audit artifact is missing.',
    );
  }
  final issues = (data['issueCount'] as num?)?.toInt();
  final highRisk = (data['highRiskPolicyCount'] as num?)?.toInt();
  final defaultLimited = (data['defaultLimitedPolicyCount'] as num?)?.toInt();
  final ordinaryReadLimited = data['ordinaryReadLimited'] == true;
  final fileBrowseAction = data['fileBrowseAuditAction']?.toString();
  final serverMiddlewareTests =
      data['serverMiddlewareTests'] as Map<String, dynamic>? ?? const {};
  final bodyLimits = data['bodyLimits'] as Map<String, dynamic>? ?? const {};
  final serverMiddlewareTestCount = (data['serverMiddlewareTestCount'] as num?)
          ?.toInt() ??
      serverMiddlewareTests.values.where((present) => present == true).length;
  final serverMiddlewareTestsPassed = serverMiddlewareTests.isNotEmpty &&
      serverMiddlewareTests.values.every((present) => present == true);
  return _GateCheck(
    id: 'headless_route_policy',
    label: 'Headless route policy',
    passed:
        data['passed'] == true && issues == 0 && serverMiddlewareTestsPassed,
    evidence: 'docs/production-readiness/headless-route-policy-audit.json',
    detail:
        'issues=$issues bodyLimitRoutes=${bodyLimits.length} highRiskPolicies=$highRisk defaultLimitedPolicies=$defaultLimited ordinaryReadLimited=$ordinaryReadLimited fileBrowseAuditAction=$fileBrowseAction serverMiddlewareTests=$serverMiddlewareTestCount/${serverMiddlewareTests.length}.',
  );
}

_GateCheck _checkHeadlessResponseHelpers() {
  final data = _readJson(
      'docs/production-readiness/headless-response-helper-audit.json');
  if (data == null) {
    return _missing(
      'headless_response_helpers',
      'Headless response helper audit artifact is missing.',
    );
  }
  final issueCount = (data['issueCount'] as num?)?.toInt();
  final usage = data['usage'] as Map<String, dynamic>? ?? const {};
  final helper = data['helper'] as Map<String, dynamic>? ?? const {};
  final tests = data['tests'] as Map<String, dynamic>? ?? const {};
  final rawResponseCalls = usage['rawResponseCallCount'];
  final intentionalRawResponseCalls = usage['intentionalRawResponseCallCount'];
  final unclassifiedRawResponseCalls =
      usage['unclassifiedRawResponseCallCount'];
  return _GateCheck(
    id: 'headless_response_helpers',
    label: 'Headless JSON response helpers',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/headless-response-helper-audit.json',
    detail:
        'issues=$issueCount helperMissing=${helper['missingTextCount']} testMissing=${tests['missingTextCount']} rawResponseCalls=$rawResponseCalls intentionalRawResponseCalls=$intentionalRawResponseCalls unclassifiedRawResponseCalls=$unclassifiedRawResponseCalls jsonContentTypeMentions=${usage['jsonContentTypeCount']} helperImports=${usage['helperImportCount']} helperCalls=${usage['helperCallCount']}. Remaining raw responses are classified stream, attachment, binary, static asset, or preflight behavior.',
  );
}

_GateCheck _checkDocsLinks() {
  final data = _readJson('docs/production-readiness/docs-link-audit.json');
  if (data == null) {
    return _missing('docs_links', 'Docs link audit artifact is missing.');
  }
  final markdownFiles = (data['markdownFileCount'] as num?)?.toInt();
  final checkedLocalLinks = (data['checkedLocalLinkCount'] as num?)?.toInt();
  final brokenLocalLinks = (data['brokenLocalLinkCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'docs_links',
    label: 'Docs local links',
    passed: brokenLocalLinks == 0,
    evidence: 'docs/production-readiness/docs-link-audit.json',
    detail:
        'Markdown files=$markdownFiles checkedLocalLinks=$checkedLocalLinks brokenLocalLinks=$brokenLocalLinks.',
  );
}

_GateCheck _checkPublicReleaseSelfTests() {
  final data =
      _readJson('docs/production-readiness/public-release-self-tests.json');
  if (data == null) {
    return _missing(
      'public_release_self_tests',
      'Public release self-test aggregate artifact is missing.',
    );
  }

  final passed = data['passed'] == true;
  final selfTestCount = (data['selfTestCount'] as num?)?.toInt();
  final expectedSelfTestCount =
      (data['expectedSelfTestCount'] as num?)?.toInt();
  final passedCount = (data['passedCount'] as num?)?.toInt();
  final failedCount = (data['failedCount'] as num?)?.toInt();
  final results = (data['results'] as List? ?? const [])
      .whereType<Map>()
      .map((result) => result.cast<String, dynamic>())
      .toList();
  final failedScripts = results
      .where((result) =>
          result['passed'] != true ||
          ((result['exitCode'] as num?)?.toInt() ?? 1) != 0)
      .map((result) => result['script']?.toString() ?? 'unknown')
      .toList();
  const expectedVerifierSelfTestCount = 25;
  final hasExpectedResults = selfTestCount == expectedSelfTestCount &&
      expectedSelfTestCount == expectedVerifierSelfTestCount &&
      results.length == selfTestCount;

  return _GateCheck(
    id: 'public_release_self_tests',
    label: 'Public release verifier self-tests',
    passed: passed &&
        hasExpectedResults &&
        passedCount == expectedSelfTestCount &&
        failedCount == 0 &&
        failedScripts.isEmpty,
    evidence: 'docs/production-readiness/public-release-self-tests.json',
    detail:
        'passed=$passed selfTests=$selfTestCount expected=$expectedSelfTestCount passedCount=$passedCount failedCount=$failedCount failedScripts=${failedScripts.join(', ')}.',
  );
}

_GateCheck _checkReleaseDocs() {
  final data = _readJson('docs/production-readiness/release-docs-audit.json');
  if (data == null) {
    return _missing(
      'release_docs',
      'Release docs audit artifact is missing.',
    );
  }
  final documentCount = (data['documentCount'] as num?)?.toInt();
  final issueCount = (data['issueCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'release_docs',
    label: 'Release documentation coverage',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/release-docs-audit.json',
    detail: 'documents=$documentCount issues=$issueCount.',
  );
}

_GateCheck _checkPlatformCapabilities() {
  final data =
      _readJson('docs/production-readiness/platform-capability-audit.json');
  if (data == null) {
    return _missing(
      'platform_capabilities',
      'Platform capability audit artifact is missing.',
    );
  }
  final fileCount = (data['fileCount'] as num?)?.toInt();
  final issueCount = (data['issueCount'] as num?)?.toInt();
  return _GateCheck(
    id: 'platform_capabilities',
    label: 'Platform capability clarity',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/platform-capability-audit.json',
    detail:
        'files=$fileCount issues=$issueCount. ASCOM/Alpaca/INDI/native capability model, headless API exposure, settings UI, backend selector gating, docs, and tests are aligned.',
  );
}

_GateCheck _checkReleaseStaging() {
  final data =
      _readJson('docs/production-readiness/release-staging-audit.json');
  if (data == null) {
    return _missing(
        'release_staging', 'Release staging audit artifact is missing.');
  }
  final splitPlan =
      _readJson('docs/production-readiness/release-pr-split-plan.json');
  final entryCount = (data['entryCount'] as num?)?.toInt() ?? -1;
  final untrackedCritical =
      (data['untrackedReleaseCriticalCount'] as num?)?.toInt() ?? -1;
  final branch = data['currentBranch']?.toString() ?? 'unknown';
  final splitPlanCoverage = splitPlan == null
      ? const _SplitPlanCoverage(
          valid: false,
          detail: 'No release PR split plan artifact exists.',
        )
      : _checkSplitPlanCoverage(stagingAudit: data, splitPlan: splitPlan);
  final stagedBranchValidation = _stagedBranchValidationDetail();
  return _GateCheck(
    id: 'release_staging',
    label: 'Clean release branch / PR staging',
    passed: entryCount == 0 && untrackedCritical == 0 && branch != 'main',
    evidence:
        'docs/production-readiness/release-staging-audit.json; docs/production-readiness/release-pr-split-plan.json; docs/production-readiness/release-pr-staged-branch-validation.json',
    detail:
        'branch=$branch entryCount=$entryCount untrackedReleaseCritical=$untrackedCritical. ${splitPlanCoverage.detail} $stagedBranchValidation A clean non-main release branch/PR is still required.',
  );
}

String _stagedBranchValidationDetail() {
  final data = _readJson(
    'docs/production-readiness/release-pr-staged-branch-validation.json',
  );
  if (data == null) {
    return 'No staged-branch validation artifact exists.';
  }
  final matrixIntegrity =
      data['matrixIntegrity'] as Map<String, dynamic>? ?? const {};
  return 'Staged-branch validation mode=${data['mode']} passed=${data['passed']} observed=${data['observedPathCount']} issues=${data['issueCount']} warnings=${data['warningCount']} matrixSourceMatches=${matrixIntegrity['sourceSplitPlanMatches']} pathspecs=${matrixIntegrity['pathspecCount']}.';
}

_SplitPlanCoverage _checkSplitPlanCoverage({
  required Map<String, dynamic> stagingAudit,
  required Map<String, dynamic> splitPlan,
}) {
  const pathspecDir = 'docs/production-readiness/release-pr-pathspecs';
  final stagingPaths = _stagingAuditPaths(stagingAudit);
  final plannedPaths = _splitPlanPaths(splitPlan);
  final pathspecFiles = Directory(pathspecDir).existsSync()
      ? Directory(pathspecDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.txt'))
          .toList()
      : <File>[];
  pathspecFiles.sort((a, b) => a.path.compareTo(b.path));

  final pathspecLines = <String>[];
  for (final file in pathspecFiles) {
    pathspecLines.addAll(file
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty));
  }
  final uniquePathspecLines = pathspecLines.toSet();
  final planEntryCount = (splitPlan['entryCount'] as num?)?.toInt() ?? -1;
  final planBucketCount = (splitPlan['bucketCount'] as num?)?.toInt() ?? -1;
  final sourceGeneratedAt = splitPlan['sourceGeneratedAt']?.toString();
  final stagingGeneratedAt = stagingAudit['generatedAt']?.toString();

  final issues = <String>[];
  if (sourceGeneratedAt != stagingGeneratedAt) {
    issues.add('source audit timestamp mismatch');
  }
  if (planEntryCount != stagingPaths.length) {
    issues.add(
      'plan entryCount=$planEntryCount but staging paths=${stagingPaths.length}',
    );
  }
  if (plannedPaths.length != stagingPaths.length ||
      !plannedPaths.containsAll(stagingPaths) ||
      !stagingPaths.containsAll(plannedPaths)) {
    issues.add('planned JSON paths do not match staging audit paths');
  }
  if (pathspecLines.length != planEntryCount) {
    issues.add(
      'pathspec lines=${pathspecLines.length} but plan entryCount=$planEntryCount',
    );
  }
  if (uniquePathspecLines.length != pathspecLines.length) {
    issues.add('pathspec files contain duplicate paths');
  }
  if (uniquePathspecLines.length != plannedPaths.length ||
      !uniquePathspecLines.containsAll(plannedPaths) ||
      !plannedPaths.containsAll(uniquePathspecLines)) {
    issues.add('pathspec paths do not match planned JSON paths');
  }

  final prefix =
      'Split plan buckets=$planBucketCount pathspecFiles=${pathspecFiles.length} pathspecLines=${pathspecLines.length} uniquePathspecLines=${uniquePathspecLines.length}.';
  if (issues.isEmpty) {
    return _SplitPlanCoverage(
      valid: true,
      detail: '$prefix Split-plan pathspec coverage is exact.',
    );
  }

  return _SplitPlanCoverage(
    valid: false,
    detail: '$prefix Split-plan coverage issues: ${issues.join('; ')}.',
  );
}

Set<String> _stagingAuditPaths(Map<String, dynamic> stagingAudit) {
  final categories =
      stagingAudit['categories'] as Map<String, dynamic>? ?? const {};
  final paths = <String>{};
  for (final category in categories.values) {
    final categoryData = category as Map<String, dynamic>? ?? const {};
    final entries = categoryData['paths'] as List? ?? const [];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final path = entry['path']?.toString();
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }
  }
  return paths;
}

Set<String> _splitPlanPaths(Map<String, dynamic> splitPlan) {
  final buckets = splitPlan['buckets'] as List? ?? const [];
  final paths = <String>{};
  for (final bucket in buckets) {
    if (bucket is! Map) continue;
    final entries = bucket['paths'] as List? ?? const [];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final path = entry['path']?.toString();
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }
  }
  return paths;
}

_GateCheck _checkLinuxReleaseWorkflow() {
  final data =
      _readJson('docs/production-readiness/linux-release-workflow-audit.json');
  if (data == null) {
    return _missing(
      'linux_release_workflow',
      'Linux release workflow audit artifact is missing.',
    );
  }
  final issueCount = (data['issueCount'] as num?)?.toInt();
  final workflow = data['workflow'] as Map<String, dynamic>? ?? const {};
  final metadataTool =
      data['metadataTool'] as Map<String, dynamic>? ?? const {};
  final ciRecipe = data['ciRecipe'] as Map<String, dynamic>? ?? const {};
  final metadataRequirements =
      data['metadataRequirements'] as Map<String, dynamic>? ?? const {};
  final workflowRequirements =
      data['workflowRequirements'] as Map<String, dynamic>? ?? const {};
  final recipeRequirements =
      data['recipeRequirements'] as Map<String, dynamic>? ?? const {};
  return _GateCheck(
    id: 'linux_release_workflow',
    label: 'Linux release workflow automation',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/linux-release-workflow-audit.json',
    detail:
        'issues=$issueCount workflowExists=${workflow['exists']} workflowMissing=${workflow['missingTextCount']} metadataToolExists=${metadataTool['exists']} metadataToolMissing=${metadataTool['missingTextCount']} ciRecipeExists=${ciRecipe['exists']} ciRecipeMissing=${ciRecipe['missingTextCount']} packageSha256=${metadataRequirements['packageSha256']} perFileSha256=${metadataRequirements['perFileSha256']} sourceGitHead=${metadataRequirements['sourceGitHead']} githubRunContext=${metadataRequirements['githubRunContext']} schemaVersion=${metadataRequirements['schemaVersion']} toolVersions=${metadataRequirements['toolVersions']} sha256Sidecar=${metadataRequirements['sha256Sidecar']} checkout=${workflowRequirements['checkout']} timeoutMinutes=${workflowRequirements['timeoutMinutes']} failOnMissingArtifacts=${workflowRequirements['failOnMissingArtifacts']} artifactRetention=${workflowRequirements['artifactRetention']} recipeRuntimeSmokeGate=${recipeRequirements['runtimeSmokeGate']}. This verifies automation wiring and the CI recipe only; a real Linux workflow run remains required.',
  );
}

_GateCheck _checkLinuxEnvironment() {
  final data =
      _readJson('docs/production-readiness/linux-environment-probe.json');
  if (data == null) {
    return _missing(
        'linux_release_build', 'Linux environment probe artifact is missing.');
  }
  final external = _externalEvidenceCheck('linux_release_build');
  final available = data['linuxBuildEnvironmentAvailable'] == true;
  return _GateCheck(
    id: 'linux_release_build',
    label: 'Linux release build/package evidence',
    passed: external.passed,
    evidence:
        'docs/production-readiness/linux-environment-probe.json; docs/production-readiness/public-release-external-evidence.json',
    detail: external.passed
        ? 'Validated Linux release build/package evidence is present.'
        : available
            ? 'Linux-capable environment exists, but validated Linux release build/package evidence is missing. ${external.detail}'
            : 'Linux build environment is unavailable on this host; validated Linux release build/package evidence is missing. ${external.detail}',
  );
}

_GateCheck _checkHardwareAvailability() {
  final data =
      _readJson('docs/production-readiness/hardware-availability-probe.json');
  if (data == null) {
    return _missing(
      'hardware_control_smoke',
      'Hardware availability artifact is missing.',
    );
  }
  final fullRealOrSimulatorCoverage =
      data['fullRealOrSimulatorCoverage'] == true ||
          (data['fullRealOrSimulatorCoverage'] == null &&
              data['fullCoverage'] == true);
  final missingAny = (data['missingRealOrSimulatorDeviceTypes'] as List? ??
          data['missingDeviceTypes'] as List? ??
          const [])
      .map((value) => value.toString())
      .join(', ');
  final missingNonSimulator =
      (data['missingNonSimulatorDeviceTypes'] as List? ?? const [])
          .map((value) => value.toString())
          .join(', ');
  final external = _externalEvidenceCheck('hardware_control_smoke');
  return _GateCheck(
    id: 'hardware_control_smoke',
    label: 'Full hardware/control smoke',
    passed: external.passed,
    evidence:
        'docs/production-readiness/hardware-availability-probe.json; docs/production-readiness/public-release-external-evidence.json',
    detail: external.passed
        ? 'Validated full hardware/control smoke evidence is present.'
        : fullRealOrSimulatorCoverage
            ? 'Required classes are discoverable with real or simulator-backed devices, but validated command/control smoke evidence is missing. Non-simulator gaps: $missingNonSimulator. ${external.detail}'
            : 'Required real-or-simulator classes missing on this host: $missingAny. Non-simulator gaps: $missingNonSimulator. Command/control smoke remains unverified. ${external.detail}',
  );
}

_GateCheck _checkSyntheticMigrationRegression() {
  final data =
      _readJson('docs/production-readiness/migration-regression-audit.json');
  if (data == null) {
    return _missing(
      'synthetic_migration_regression',
      'Migration regression audit artifact is missing.',
    );
  }
  final issueCount = (data['issueCount'] as num?)?.toInt();
  final fixture = data['fixture'] as Map<String, dynamic>? ?? const {};
  final tests = data['tests'] as Map<String, dynamic>? ?? const {};
  final manualProbe = data['manualProbe'] as Map<String, dynamic>? ?? const {};
  return _GateCheck(
    id: 'synthetic_migration_regression',
    label: 'Synthetic migration regression coverage',
    passed: data['passed'] == true && issueCount == 0,
    evidence: 'docs/production-readiness/migration-regression-audit.json',
    detail:
        'issues=$issueCount fixtureMissing=${fixture['missingTextCount']} testMissing=${tests['missingTextCount']} manualProbeMissing=${manualProbe['missingTextCount']} manualRealArtifactGatePreserved=${data['manualRealArtifactGatePreserved']}. Real older-profile migration remains a separate blocker.',
  );
}

_GateCheck _checkManualMigration() {
  final data =
      _readJson('docs/production-readiness/manual-migration-probe.json');
  if (data == null) {
    return _missing(
        'manual_migration', 'Manual migration probe artifact is missing.');
  }
  final verified = data['migrationVerified'] == true;
  final artifactProvided = data['artifactProvided'] == true;
  final sourceExists = data['sourceExists'] == true;
  final sourceSizeBytes = (data['sourceSizeBytes'] as num?)?.toInt() ?? 0;
  final sourceSha256 = data['sourceSha256']?.toString() ?? '';
  final sourceIdentityValid = sourceSizeBytes > 0 &&
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sourceSha256);
  final copiedSourceSha256Matches = data['copiedSourceSha256Matches'] == true;
  final qualifiesAsOlderProfile = data['qualifiesAsOlderProfile'] == true;
  final expectedTableCount = (data['expectedTableCount'] as num?)?.toInt() ?? 0;
  final migratedTableCount = (data['migratedTableCount'] as num?)?.toInt() ?? 0;
  final defaultSettingCount =
      (data['defaultSettingCount'] as num?)?.toInt() ?? 0;
  final missingTables = (data['missingTables'] as List? ?? const []).length;
  final missingSettings =
      (data['missingDefaultSettings'] as List? ?? const []).length;
  final passed = verified &&
      artifactProvided &&
      sourceExists &&
      sourceIdentityValid &&
      copiedSourceSha256Matches &&
      qualifiesAsOlderProfile &&
      expectedTableCount > 0 &&
      migratedTableCount >= expectedTableCount &&
      defaultSettingCount > 0 &&
      missingTables == 0 &&
      missingSettings == 0;
  return _GateCheck(
    id: 'manual_migration',
    label: 'Older real profile/database migration',
    passed: passed,
    evidence: 'docs/production-readiness/manual-migration-probe.json',
    detail:
        'artifactProvided=$artifactProvided sourceExists=$sourceExists sourceSizeBytes=$sourceSizeBytes sourceSha256Recorded=${sourceSha256.isNotEmpty} copiedSourceSha256Matches=$copiedSourceSha256Matches qualifiesAsOlderProfile=$qualifiesAsOlderProfile migrationVerified=$verified expectedTableCount=$expectedTableCount migratedTableCount=$migratedTableCount defaultSettingCount=$defaultSettingCount missingTables=$missingTables missingDefaultSettings=$missingSettings.',
  );
}

_GateCheck _checkMobileRemoteSmoke() {
  final files = [
    'docs/production-readiness/android-emulator-remote-smoke-log.txt',
    'docs/production-readiness/android-emulator-remote-smoke.png',
    'docs/production-readiness/mobile-remote-window-connected.xml',
  ];
  final missing = files.where((path) => !File(path).existsSync()).toList();
  return _GateCheck(
    id: 'mobile_remote_smoke',
    label: 'Android emulator remote smoke',
    passed: missing.isEmpty,
    evidence: files.join(', '),
    detail: missing.isEmpty
        ? 'Android emulator remote smoke artifacts are present.'
        : 'Missing artifacts: ${missing.join(', ')}.',
  );
}

_GateCheck _checkMobileReconnectSmoke() {
  const path =
      'docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt';
  final exists = File(path).existsSync();
  final text = exists ? File(path).readAsStringSync() : '';
  final hasReconnect = text.contains('WebSocket connected successfully') &&
      text.contains('Reconnecting in');
  return _GateCheck(
    id: 'mobile_reconnect_smoke',
    label: 'Android emulator reconnect smoke',
    passed: exists && hasReconnect,
    evidence: path,
    detail: exists
        ? 'Reconnect log exists; reconnect markers present=$hasReconnect.'
        : 'Reconnect log artifact is missing.',
  );
}

_GateCheck _checkSecondDeviceLan() {
  final external = _externalEvidenceCheck('second_device_lan_firewall');
  return _GateCheck(
    id: 'second_device_lan_firewall',
    label: 'Second-device LAN/firewall smoke',
    passed: external.passed,
    evidence:
        'docs/production-readiness/public-release-external-evidence.json; docs/production-readiness/public-release-audit-report.md; docs/production-readiness/public-release-master-checklist.md',
    detail: external.passed
        ? 'Validated second-device LAN/firewall smoke evidence is present.'
        : 'No validated artifact proves access from a second physical device/browser through the real firewall/router path. ${external.detail}',
  );
}

_GateCheck _checkRealControlActions() {
  final external = _externalEvidenceCheck('real_remote_control_actions');
  return _GateCheck(
    id: 'real_remote_control_actions',
    label: 'Real remote-control actions',
    passed: external.passed,
    evidence:
        'docs/production-readiness/public-release-external-evidence.json; docs/production-readiness/hardware-availability-probe.json; docs/production-readiness/public-release-audit-report.md',
    detail: external.passed
        ? 'Validated real remote-control action evidence is present.'
        : 'No validated artifact proves actual remote control actions against real or simulator-backed devices. ${external.detail}',
  );
}

_GateCheck _checkFinalChecklist() {
  final checklistPath =
      'docs/production-readiness/public-release-master-checklist.md';
  final checklist = File(checklistPath);
  if (!checklist.existsSync()) {
    return _missing(
        'final_checklist', 'Public release master checklist is missing.');
  }
  final checklistAudit = _readJson(_checklistAuditPath);
  if (checklistAudit == null) {
    return _GateCheck(
      id: 'final_checklist',
      label: 'Final release checklist/sign-off',
      passed: false,
      evidence:
          '$checklistPath; $_checklistAuditPath; docs/production-readiness/public-release-external-evidence.json',
      detail:
          'Checklist audit artifact is missing. Run audit:public-release-checklist before the public release gate.',
    );
  }

  final total = (checklistAudit['totalItemCount'] as num?)?.toInt() ?? -1;
  final checked = (checklistAudit['checkedItemCount'] as num?)?.toInt() ?? -1;
  final unchecked =
      (checklistAudit['uncheckedItemCount'] as num?)?.toInt() ?? -1;
  final checkedWithoutEvidence =
      (checklistAudit['checkedWithoutEvidenceCount'] as num?)?.toInt() ?? -1;
  final knownLimitationsReferenced =
      checklistAudit['knownLimitationsReferenced'] == true;
  final supportedHardwareReferenced =
      checklistAudit['supportedHardwareByPlatformReferenced'] == true;
  final external = _externalEvidenceCheck('final_release_signoff');
  final checklistPassed = unchecked == 0 &&
      checkedWithoutEvidence == 0 &&
      knownLimitationsReferenced &&
      supportedHardwareReferenced;
  return _GateCheck(
    id: 'final_checklist',
    label: 'Final release checklist/sign-off',
    passed: checklistPassed && external.passed,
    evidence:
        '$checklistPath; $_checklistAuditPath; docs/production-readiness/public-release-external-evidence.json',
    detail: external.passed
        ? 'Checklist items=$total checked=$checked unchecked=$unchecked checkedWithoutEvidence=$checkedWithoutEvidence knownLimitationsReferenced=$knownLimitationsReferenced supportedHardwareByPlatformReferenced=$supportedHardwareReferenced; final sign-off evidence is validated.'
        : 'Checklist items=$total checked=$checked unchecked=$unchecked checkedWithoutEvidence=$checkedWithoutEvidence knownLimitationsReferenced=$knownLimitationsReferenced supportedHardwareByPlatformReferenced=$supportedHardwareReferenced; validated final sign-off evidence is missing. ${external.detail}',
  );
}

_ExternalEvidenceResult _externalEvidenceCheck(String id) {
  final data = _readJson(
      'docs/production-readiness/public-release-external-evidence.json');
  if (data == null) {
    return const _ExternalEvidenceResult(
      passed: false,
      detail:
          'Run audit:public-release-external-evidence and provide the matching evidence file.',
    );
  }
  final checks = data['checks'] as List? ?? const [];
  for (final item in checks) {
    if (item is! Map) continue;
    final check = item.cast<String, dynamic>();
    if (check['id'] != id) continue;
    final passed = check['passed'] == true;
    if (passed) {
      return const _ExternalEvidenceResult(
        passed: true,
        detail: 'External evidence validator passed.',
      );
    }
    final evidencePath = check['evidencePath']?.toString() ?? 'unknown';
    final templatePath = check['templatePath']?.toString() ?? 'unknown';
    final issues = (check['issues'] as List? ?? const [])
        .map((issue) => issue.toString())
        .join(' ');
    return _ExternalEvidenceResult(
      passed: false,
      detail:
          'External evidence validator did not pass for $evidencePath. Template: $templatePath. $issues',
    );
  }
  return _ExternalEvidenceResult(
    passed: false,
    detail: 'External evidence validator has no check with id `$id`.',
  );
}

_GateCheck _missing(String id, String detail) {
  return _GateCheck(
    id: id,
    label: id,
    passed: false,
    evidence: null,
    detail: detail,
  );
}

class _ExternalEvidenceResult {
  final bool passed;
  final String detail;

  const _ExternalEvidenceResult({
    required this.passed,
    required this.detail,
  });
}

class _SplitPlanCoverage {
  final bool valid;
  final String detail;

  const _SplitPlanCoverage({
    required this.valid,
    required this.detail,
  });
}

Map<String, dynamic>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

String _renderMarkdown({
  required bool ready,
  required List<_GateCheck> checks,
  required List<_GateCheck> blockers,
}) {
  final buffer = StringBuffer()
    ..writeln('# Public Release Gate')
    ..writeln()
    ..writeln('- Decision: `${ready ? 'READY' : 'NOT_READY'}`')
    ..writeln('- Passed checks: `${checks.length - blockers.length}`')
    ..writeln('- Blockers: `${blockers.length}`')
    ..writeln()
    ..writeln(
      'This gate is conservative. It treats missing direct evidence as a blocker and does not accept proxy signals as completion.',
    )
    ..writeln()
    ..writeln('## Checks')
    ..writeln()
    ..writeln('| Status | Check | Evidence | Detail |')
    ..writeln('| --- | --- | --- | --- |');

  for (final check in checks) {
    final evidence = check.evidence == null ? 'none' : '`${check.evidence}`';
    buffer.writeln(
      '| ${check.passed ? 'PASS' : 'BLOCKED'} | ${check.label} | '
      '$evidence | ${_escapeTable(check.detail)} |',
    );
  }

  if (blockers.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Blockers')
      ..writeln();
    for (final blocker in blockers) {
      buffer.writeln('- `${blocker.id}`: ${blocker.detail}');
    }
  }

  return buffer.toString();
}

String _escapeTable(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

class _GateCheck {
  final String id;
  final String label;
  final bool passed;
  final String? evidence;
  final String detail;

  const _GateCheck({
    required this.id,
    required this.label,
    required this.passed,
    required this.evidence,
    required this.detail,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'passed': passed,
        'evidence': evidence,
        'detail': detail,
      };
}
