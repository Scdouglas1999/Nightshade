import 'dart:convert';
import 'dart:io';

const _templateDirectory =
    'docs/production-readiness/external-evidence-templates';
const _jsonOutputPath =
    'docs/production-readiness/public-release-external-evidence.json';
const _markdownOutputPath =
    'docs/production-readiness/public-release-external-evidence.md';
const _checklistAuditPath =
    'docs/production-readiness/public-release-checklist-audit.json';
const _publicReleaseGatePath =
    'docs/production-readiness/public-release-gate.json';
const _knownLimitationsPath = 'docs/known-limitations.md';
const _supportedHardwarePath = 'docs/supported-hardware-by-platform.md';
const _releaseNotesTemplatePath = 'docs/release-notes-template.md';

const _requiredDeviceTypes = [
  'camera',
  'mount',
  'focuser',
  'filterWheel',
  'rotator',
  'guider',
  'dome',
  'weather',
  'safetyMonitor',
];

const _requiredReleaseNoteHeadings = [
  '## Release',
  '## Release Summary',
  '## Supported Platforms',
  '## Supported Hardware And Drivers',
  '## Security And Remote Access',
  '## Migration And Compatibility',
  '## Known Limitations',
  '## Verification Summary',
  '## Upgrade Notes',
  '## Rollback Plan',
];

const _allowedRemoteClientTypes = [
  'dashboard',
  'mobile',
  'headless-api',
];

const _requiredLinuxRuntimeSmokeChecks = [
  'headless_process_started',
  'api_info_ok',
  'openapi_ok',
  'dashboard_asset_ok',
];

void main() async {
  final checks = <_EvidenceCheck>[
    _validateLinuxBuildEvidence(),
    _validateHardwareControlEvidence(),
    _validateSecondDeviceEvidence(),
    _validateRealRemoteControlEvidence(),
    _validateFinalSignoffEvidence(),
  ];

  await _writeTemplates();

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'ready': checks.every((check) => check.passed),
    'passedCount': checks.where((check) => check.passed).length,
    'checkCount': checks.length,
    'checks': checks.map((check) => check.toJson()).toList(),
  };

  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(checks));

  stdout.writeln('Public release external evidence audit complete.');
  stdout.writeln(
      'Passed checks: ${checks.where((check) => check.passed).length}');
  stdout.writeln('Checks: ${checks.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');
}

Future<void> _writeTemplates() async {
  final directory = Directory(_templateDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }

  final templates = {
    'linux-release-build-evidence.template.json': {
      'platform': 'linux',
      'metadataSchemaVersion': 2,
      'buildCommand': 'dart run melos run build:desktop:linux --no-select',
      'toolVersions': {
        'operatingSystem': 'linux',
        'dartVersion': 'replace with dart --version output',
        'flutterVersion': 'replace with flutter --version output',
        'rustcVersion': 'replace with rustc --version output',
      },
      'buildPassed': true,
      'packageArtifactPath': '/path/to/nightshade-linux-artifact',
      'packageSizeBytes': 1,
      'packageSha256':
          '0000000000000000000000000000000000000000000000000000000000000000',
      'packageSha256Path': '/path/to/nightshade-linux-artifact.sha256',
      'metadataPath':
          'docs/production-readiness/linux-release-package-metadata.json',
      'runtimeSmokePassed': true,
      'runtimeSmokeArtifact':
          'docs/production-readiness/linux-runtime-smoke.log',
      'runtimeSmokeChecks': [
        {
          'check': 'headless_process_started',
          'passed': true,
          'evidence': 'process PID and listening port recorded in smoke log',
        },
        {
          'check': 'api_info_ok',
          'passed': true,
          'evidence': '/api/info returned HTTP 200 with version metadata',
        },
        {
          'check': 'openapi_ok',
          'passed': true,
          'evidence': '/api/openapi.json returned HTTP 200',
        },
        {
          'check': 'dashboard_asset_ok',
          'passed': true,
          'evidence': 'dashboard HTML/JS/CSS assets returned HTTP 200',
        },
      ],
      'nativeLibraryNotes': [
        'replace with ldd/native shared library findings from the Linux artifact',
        'replace with bundled or runtime vendor SDK library notes',
      ],
      'linuxPermissionNotes': [
        'replace with udev rules and dialout/plugdev/video group checks from the smoke host',
        'replace with local or remote INDI server package/source and driver notes',
      ],
      'notes':
          'Replace placeholder values with actual Linux build evidence. The package artifact and runtime smoke log must exist when this verifier runs.',
    },
    'full-hardware-control-smoke-evidence.template.json': {
      'coveredDeviceTypes': _requiredDeviceTypes,
      'connectDisconnectPassed': true,
      'safeStatusReadsPassed': true,
      'safeControlActionsPassed': true,
      'smokeLogPath':
          'docs/production-readiness/full-hardware-control-smoke.log',
      'connectionResults': [
        {
          'deviceType': 'camera',
          'deviceId': 'example',
          'backingType': 'real',
          'connectPassed': true,
          'disconnectPassed': true,
          'statusReadback': 'recorded status after connect',
        }
      ],
      'commandResults': [
        {
          'deviceType': 'camera',
          'deviceId': 'example',
          'backingType': 'real',
          'command': 'short exposure',
          'stateReadback': 'recorded state after command',
          'passed': true,
        }
      ],
      'skippedUnsafeActions': [],
      'notes':
          'Use real or simulator-backed devices and record every command result. The smoke log path must exist when this verifier runs.',
    },
    'second-device-lan-firewall-smoke-evidence.template.json': {
      'usedPhysicalSecondDevice': true,
      'clientDevice': 'phone/tablet/laptop model',
      'clientIp': '192.168.1.50',
      'serverLanUrl': 'http://192.168.1.10:7624',
      'windowsFirewallRule': {
        'name': 'Nightshade Headless API',
        'profile': 'Private',
        'port': 7624,
        'action': 'Allow',
      },
      'networkPath': 'same trusted LAN; no guest Wi-Fi or VPN isolation',
      'dashboardLoaded': true,
      'authPositivePassed': true,
      'authNegativePassed': true,
      'websocketConnected': true,
      'websocketReconnectObserved': true,
      'evidenceArtifacts': [
        'docs/production-readiness/second-device-lan-screenshot.png'
      ],
      'notes':
          'Do not use localhost, 127.0.0.1, or Android emulator 10.0.2.2. Every evidence artifact path must exist when this verifier runs.',
    },
    'real-remote-control-actions-evidence.template.json': {
      'usedRealOrSimulatorBackedDevices': true,
      'remoteClientType': 'dashboard',
      'coveredDeviceTypes': ['mount'],
      'stateReadbackPassed': true,
      'auditLogPath': 'docs/production-readiness/real-control-audit.log',
      'commandResults': [
        {
          'deviceType': 'mount',
          'deviceId': 'example',
          'requestId': 'request id from the remote command/audit log',
          'command': 'safe status/control action',
          'passed': true,
          'stateReadback': 'recorded state after command',
        }
      ],
      'skippedUnsafeActions': [
        {
          'command': 'example unsafe command',
          'reason': 'skipped in real environment; simulator used instead',
        }
      ],
      'notes':
          'Record request IDs and post-command state readback. The audit log path must exist when this verifier runs.',
    },
    'final-release-signoff-evidence.template.json': {
      'reviewer': 'name',
      'date': DateTime.now().toUtc().toIso8601String().split('T').first,
      'commit': 'full git commit hash',
      'decision': 'ship',
      'checklistComplete': true,
      'noUnresolvedBlockers': true,
      'knownLimitationsReviewed': true,
      'releaseNotesReady': true,
      'releaseNotesPath': 'docs/release-notes.md',
      'notes':
          'Final sign-off is valid only after the master checklist audit is complete and release notes exist.',
    },
  };

  for (final entry in templates.entries) {
    await File('$_templateDirectory/${entry.key}')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(entry.value));
  }
}

_EvidenceCheck _validateLinuxBuildEvidence() {
  const path = 'docs/production-readiness/linux-release-build-evidence.json';
  final data = _readEvidence(path);
  final issues = <String>[];
  if (data == null) {
    issues.add('Evidence file is missing or is not valid JSON.');
  } else {
    _requireStringEquals(data, issues, 'platform', 'linux');
    _requireIntAtLeast(data, issues, 'metadataSchemaVersion', 2);
    _requireStringContains(data, issues, 'buildCommand', 'build:desktop:linux');
    _requireToolVersions(data, issues, 'toolVersions');
    _requireBool(data, issues, 'buildPassed');
    _requireNonEmptyString(data, issues, 'packageArtifactPath');
    _requirePositiveInt(data, issues, 'packageSizeBytes');
    _requireSha256(data, issues, 'packageSha256');
    _requireNonEmptyString(data, issues, 'packageSha256Path');
    _requireNonEmptyString(data, issues, 'metadataPath');
    _requireBool(data, issues, 'runtimeSmokePassed');
    _requireNonEmptyString(data, issues, 'runtimeSmokeArtifact');
    _requireNonEmptyList(data, issues, 'runtimeSmokeChecks');
    _requireNonEmptyList(data, issues, 'nativeLibraryNotes');
    _requireNonEmptyList(data, issues, 'linuxPermissionNotes');
    _validateLinuxRuntimeSmokeChecks(data, issues);
    final packageArtifact = _requireExistingFile(
      data,
      issues,
      'packageArtifactPath',
      nonEmpty: true,
    );
    if (packageArtifact != null) {
      _requireFileSizeMatches(
        data,
        issues,
        'packageSizeBytes',
        packageArtifact,
      );
      _requireFileSha256Matches(
        data,
        issues,
        'packageSha256',
        packageArtifact,
      );
    }
    final packageSha256File = _requireExistingFile(
      data,
      issues,
      'packageSha256Path',
      nonEmpty: true,
    );
    if (packageSha256File != null) {
      _requireSha256SidecarMatches(
        data,
        issues,
        'packageSha256Path',
        packageSha256File,
      );
    }
    final metadataFile = _requireExistingFile(
      data,
      issues,
      'metadataPath',
      nonEmpty: true,
    );
    if (metadataFile != null) {
      _requireLinuxPackageMetadataMatches(data, issues, metadataFile);
    }
    _requireExistingFile(data, issues, 'runtimeSmokeArtifact', nonEmpty: true);
  }

  return _EvidenceCheck(
    id: 'linux_release_build',
    label: 'Linux release build/package evidence',
    evidencePath: path,
    templatePath:
        '$_templateDirectory/linux-release-build-evidence.template.json',
    passed: issues.isEmpty,
    issues: issues,
    requirements: [
      'Linux platform build command passed.',
      'Evidence uses metadata schema v2 or newer and records toolchain provenance.',
      'Package SHA256 sidecar exists and contains the package hash.',
      'Generated package metadata exists and matches the evidence hash/size.',
      'Package artifact path exists, size matches, and SHA256 matches.',
      'Runtime/headless smoke from the Linux artifact passed, covers required checks, and its log exists.',
      'Linux native shared library and permission notes are recorded.',
    ],
  );
}

_EvidenceCheck _validateHardwareControlEvidence() {
  const path =
      'docs/production-readiness/full-hardware-control-smoke-evidence.json';
  final data = _readEvidence(path);
  final issues = <String>[];
  if (data == null) {
    issues.add('Evidence file is missing or is not valid JSON.');
  } else {
    final covered = _stringList(data['coveredDeviceTypes']);
    final missing = _requiredDeviceTypes
        .where((deviceType) => !covered.contains(deviceType))
        .toList();
    if (missing.isNotEmpty) {
      issues.add('coveredDeviceTypes is missing: ${missing.join(', ')}.');
    }
    _requireBool(data, issues, 'connectDisconnectPassed');
    _requireBool(data, issues, 'safeStatusReadsPassed');
    _requireBool(data, issues, 'safeControlActionsPassed');
    _requireNonEmptyString(data, issues, 'smokeLogPath');
    _requireExistingFile(data, issues, 'smokeLogPath', nonEmpty: true);
    _requireNonEmptyList(data, issues, 'connectionResults');
    _validateConnectionResults(data, issues);
    _requireNonEmptyList(data, issues, 'commandResults');
    _validateCommandResults(
      data,
      issues,
      requireEveryDeviceType: true,
      requireStateReadback: true,
    );
  }

  return _EvidenceCheck(
    id: 'hardware_control_smoke',
    label: 'Full hardware/control smoke',
    evidencePath: path,
    templatePath:
        '$_templateDirectory/full-hardware-control-smoke-evidence.template.json',
    passed: issues.isEmpty,
    issues: issues,
    requirements: [
      'All required device classes are covered.',
      'Per-device connect/disconnect and status reads passed.',
      'Command results cover every required device type and the smoke log exists.',
    ],
  );
}

_EvidenceCheck _validateSecondDeviceEvidence() {
  const path =
      'docs/production-readiness/second-device-lan-firewall-smoke-evidence.json';
  final data = _readEvidence(path);
  final issues = <String>[];
  if (data == null) {
    issues.add('Evidence file is missing or is not valid JSON.');
  } else {
    _requireBool(data, issues, 'usedPhysicalSecondDevice');
    _requireNonEmptyString(data, issues, 'clientDevice');
    _requireNonEmptyString(data, issues, 'clientIp');
    _requireNonEmptyString(data, issues, 'serverLanUrl');
    final url = data['serverLanUrl']?.toString().toLowerCase() ?? '';
    if (url.contains('localhost') ||
        url.contains('127.0.0.1') ||
        url.contains('10.0.2.2')) {
      issues.add('serverLanUrl must not be localhost, 127.0.0.1, or 10.0.2.2.');
    }
    _requireWindowsFirewallRule(data, issues);
    _requireNonEmptyString(data, issues, 'networkPath');
    _requireBool(data, issues, 'dashboardLoaded');
    _requireBool(data, issues, 'authPositivePassed');
    _requireBool(data, issues, 'authNegativePassed');
    _requireBool(data, issues, 'websocketConnected');
    _requireBool(data, issues, 'websocketReconnectObserved');
    _requireNonEmptyList(data, issues, 'evidenceArtifacts');
    _requireExistingFilesInList(data, issues, 'evidenceArtifacts');
  }

  return _EvidenceCheck(
    id: 'second_device_lan_firewall',
    label: 'Second-device LAN/firewall smoke',
    evidencePath: path,
    templatePath:
        '$_templateDirectory/second-device-lan-firewall-smoke-evidence.template.json',
    passed: issues.isEmpty,
    issues: issues,
    requirements: [
      'A physical second device uses the real LAN URL.',
      'Evidence records client IP, Windows firewall rule/profile, and network path.',
      'Dashboard, auth success/failure, WebSocket connection, and reconnect are verified.',
      'Screenshot/log evidence artifact paths exist.',
    ],
  );
}

_EvidenceCheck _validateRealRemoteControlEvidence() {
  const path =
      'docs/production-readiness/real-remote-control-actions-evidence.json';
  final data = _readEvidence(path);
  final issues = <String>[];
  if (data == null) {
    issues.add('Evidence file is missing or is not valid JSON.');
  } else {
    _requireBool(data, issues, 'usedRealOrSimulatorBackedDevices');
    _requireRemoteClientType(data, issues);
    _requireCoveredDeviceTypes(data, issues);
    _requireBool(data, issues, 'stateReadbackPassed');
    _requireNonEmptyString(data, issues, 'auditLogPath');
    _requireExistingFile(data, issues, 'auditLogPath', nonEmpty: true);
    _requireNonEmptyList(data, issues, 'commandResults');
    _validateCommandResults(
      data,
      issues,
      requireStateReadback: true,
      requireRequestId: true,
    );
    _validateCoveredCommandScope(data, issues);
    _requireAuditLogContainsCommandRequestIds(data, issues);
  }

  return _EvidenceCheck(
    id: 'real_remote_control_actions',
    label: 'Real remote-control actions',
    evidencePath: path,
    templatePath:
        '$_templateDirectory/real-remote-control-actions-evidence.template.json',
    passed: issues.isEmpty,
    issues: issues,
    requirements: [
      'Remote client sends actual safe commands.',
      'Evidence declares the applicable remote-control device types in scope.',
      'Command results all pass and include device IDs.',
      'Post-command state readback and request IDs are recorded in the server audit log.',
    ],
  );
}

_EvidenceCheck _validateFinalSignoffEvidence() {
  const path = 'docs/production-readiness/final-release-signoff-evidence.json';
  final data = _readEvidence(path);
  final issues = <String>[];
  if (data == null) {
    issues.add('Evidence file is missing or is not valid JSON.');
  } else {
    _requireNonEmptyString(data, issues, 'reviewer');
    _requireNonEmptyString(data, issues, 'date');
    _requireNonEmptyString(data, issues, 'commit');
    _requireIsoDate(data, issues, 'date');
    _requireCurrentGitHead(data, issues, 'commit');
    _requireStringEquals(data, issues, 'decision', 'ship');
    _requireBool(data, issues, 'checklistComplete');
    _requireBool(data, issues, 'noUnresolvedBlockers');
    _requireBool(data, issues, 'knownLimitationsReviewed');
    _requireBool(data, issues, 'releaseNotesReady');
    _requireNonEmptyString(data, issues, 'releaseNotesPath');
    final releaseNotes = _requireExistingFile(
      data,
      issues,
      'releaseNotesPath',
      nonEmpty: true,
    );
    if (releaseNotes != null) {
      _requireReleaseNotesComplete(data, issues, releaseNotes);
    }
    _requireStaticFileExists(issues, _knownLimitationsPath, nonEmpty: true);
    _requireStaticFileExists(issues, _supportedHardwarePath, nonEmpty: true);
    _requireChecklistAuditComplete(issues);
    _requirePublicReleaseGateReady(issues);
  }

  return _EvidenceCheck(
    id: 'final_release_signoff',
    label: 'Final release checklist/sign-off',
    evidencePath: path,
    templatePath:
        '$_templateDirectory/final-release-signoff-evidence.template.json',
    passed: issues.isEmpty,
    issues: issues,
    requirements: [
      'Reviewer, date, and commit are recorded.',
      'Decision is ship.',
      'Commit is a full hash matching current git HEAD.',
      'Checklist audit has zero unchecked and zero checked-without-evidence items.',
      'Public release gate decision is READY with no blockers.',
      'Known limitations, supported hardware, and completed release notes artifacts exist.',
    ],
  );
}

Map<String, dynamic>? _readEvidence(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
}

void _requireBool(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  if (data[field] != true) {
    issues.add('$field must be true.');
  }
}

void _requireNonEmptyString(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  if ((data[field]?.toString().trim() ?? '').isEmpty) {
    issues.add('$field is required.');
  }
}

void _requireStringEquals(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  String expected,
) {
  final actual = data[field]?.toString().trim().toLowerCase() ?? '';
  if (actual != expected.toLowerCase()) {
    issues.add('$field must be `$expected`.');
  }
}

void _requireStringContains(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  String expectedSubstring,
) {
  final actual = data[field]?.toString().toLowerCase() ?? '';
  if (!actual.contains(expectedSubstring.toLowerCase())) {
    issues.add('$field must include `$expectedSubstring`.');
  }
}

void _requireRemoteClientType(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final value = data['remoteClientType']?.toString().trim() ?? '';
  if (value.isEmpty) {
    issues.add('remoteClientType is required.');
    return;
  }
  if (!_allowedRemoteClientTypes.contains(value)) {
    issues.add(
      'remoteClientType must be one of: ${_allowedRemoteClientTypes.join(', ')}.',
    );
  }
}

void _requireCoveredDeviceTypes(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final covered = _stringList(data['coveredDeviceTypes']);
  if (covered.isEmpty) {
    issues.add('coveredDeviceTypes must be a non-empty list.');
    return;
  }
  final unsupported = covered
      .where((deviceType) => !_requiredDeviceTypes.contains(deviceType))
      .toList();
  if (unsupported.isNotEmpty) {
    issues.add(
      'coveredDeviceTypes contains unsupported device types: ${unsupported.join(', ')}.',
    );
  }
}

void _validateLinuxRuntimeSmokeChecks(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final checks = data['runtimeSmokeChecks'];
  if (checks is! List) {
    return;
  }

  final observed = <String>{};
  for (var i = 0; i < checks.length; i++) {
    final check = checks[i];
    if (check is! Map) {
      issues.add('runtimeSmokeChecks[$i] must be an object.');
      continue;
    }
    final entry = check.cast<String, dynamic>();
    final id = entry['check']?.toString().trim() ?? '';
    if (id.isEmpty) {
      issues.add('runtimeSmokeChecks[$i].check is required.');
    } else {
      observed.add(id);
      if (!_requiredLinuxRuntimeSmokeChecks.contains(id)) {
        issues.add(
          'runtimeSmokeChecks[$i].check must be one of: ${_requiredLinuxRuntimeSmokeChecks.join(', ')}.',
        );
      }
    }
    if (entry['passed'] != true) {
      issues.add('runtimeSmokeChecks[$i].passed must be true.');
    }
    if ((entry['evidence']?.toString().trim() ?? '').isEmpty) {
      issues.add('runtimeSmokeChecks[$i].evidence is required.');
    }
  }

  final missing = _requiredLinuxRuntimeSmokeChecks
      .where((check) => !observed.contains(check))
      .toList();
  if (missing.isNotEmpty) {
    issues.add('runtimeSmokeChecks is missing: ${missing.join(', ')}.');
  }
}

void _requirePositiveInt(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field];
  if (value is! num || value <= 0) {
    issues.add('$field must be a positive number.');
  }
}

void _requireIntAtLeast(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  int minimum,
) {
  final value = data[field];
  if (value is! num || value < minimum) {
    issues.add('$field must be at least $minimum.');
  }
}

void _requireToolVersions(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field];
  if (value is! Map) {
    issues.add('$field must record toolchain provenance.');
    return;
  }
  for (final key in ['operatingSystem', 'dartVersion']) {
    if ((value[key]?.toString().trim() ?? '').isEmpty) {
      issues.add('$field.$key is required.');
    }
  }
}

void _requireSha256(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field]?.toString().trim() ?? '';
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    issues.add('$field must be a 64-character SHA256 hex digest.');
  }
}

void _requireNonEmptyList(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field];
  if (value is! List || value.isEmpty) {
    issues.add('$field must be a non-empty list.');
  }
}

File? _requireExistingFile(
  Map<String, dynamic> data,
  List<String> issues,
  String field, {
  bool nonEmpty = false,
}) {
  final path = data[field]?.toString().trim() ?? '';
  if (path.isEmpty) {
    return null;
  }
  final file = File(path);
  if (!file.existsSync()) {
    issues.add('$field file does not exist: $path.');
    return null;
  }
  if (nonEmpty && file.lengthSync() == 0) {
    issues.add('$field file is empty: $path.');
  }
  return file;
}

void _requireExistingFilesInList(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final values = data[field];
  if (values is! List) {
    return;
  }
  for (var i = 0; i < values.length; i++) {
    final path = values[i]?.toString().trim() ?? '';
    if (path.isEmpty) {
      issues.add('$field[$i] is required.');
      continue;
    }
    if (!File(path).existsSync()) {
      issues.add('$field[$i] file does not exist: $path.');
    }
  }
}

void _requireWindowsFirewallRule(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final rule = data['windowsFirewallRule'];
  if (rule is! Map) {
    issues.add(
        'windowsFirewallRule must record rule name, profile, port, and action.');
    return;
  }
  final fields = rule.cast<String, dynamic>();
  for (final field in ['name', 'profile', 'action']) {
    if ((fields[field]?.toString().trim() ?? '').isEmpty) {
      issues.add('windowsFirewallRule.$field is required.');
    }
  }
  final port = fields['port'];
  if (port is! num || port <= 0) {
    issues.add('windowsFirewallRule.port must be a positive number.');
  }
}

void _requireSha256SidecarMatches(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  File file,
) {
  final expected = data['packageSha256']?.toString().trim().toLowerCase() ?? '';
  if (expected.isEmpty) {
    return;
  }
  final text = file.readAsStringSync().toLowerCase();
  final hasExpectedHash = RegExp(r'\b[0-9a-f]{64}\b')
      .allMatches(text)
      .any((match) => match.group(0) == expected);
  if (!hasExpectedHash) {
    issues.add('$field does not contain packageSha256.');
  }
}

void _requireLinuxPackageMetadataMatches(
  Map<String, dynamic> evidence,
  List<String> issues,
  File file,
) {
  final metadata = _readEvidence(file.path);
  if (metadata == null) {
    issues.add('metadataPath file is not valid JSON: ${file.path}.');
    return;
  }

  final schemaVersion = metadata['metadataSchemaVersion'];
  if (schemaVersion is! num || schemaVersion < 2) {
    issues.add('metadataPath metadataSchemaVersion must be at least 2.');
  }

  final toolVersions = metadata['toolVersions'];
  if (toolVersions is! Map) {
    issues.add('metadataPath toolVersions must record toolchain provenance.');
  } else {
    for (final key in ['operatingSystem', 'dartVersion']) {
      if ((toolVersions[key]?.toString().trim() ?? '').isEmpty) {
        issues.add('metadataPath toolVersions.$key is required.');
      }
    }
  }

  if (metadata['artifactSha256'] != evidence['packageSha256']) {
    issues.add('metadataPath artifactSha256 must match packageSha256.');
  }

  if (metadata['artifactSizeBytes'] != evidence['packageSizeBytes']) {
    issues.add('metadataPath artifactSizeBytes must match packageSizeBytes.');
  }

  _requireNonEmptyList(metadata, issues, 'nativeLibraryNotes');
  _requireNonEmptyList(metadata, issues, 'linuxPermissionNotes');

  final fileCount = metadata['fileCount'];
  if (fileCount is! num || fileCount <= 0) {
    issues.add('metadataPath fileCount must be a positive number.');
  }
}

void _requireStaticFileExists(
  List<String> issues,
  String path, {
  bool nonEmpty = false,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    issues.add('Required file does not exist: $path.');
    return;
  }
  if (nonEmpty && file.lengthSync() == 0) {
    issues.add('Required file is empty: $path.');
  }
}

void _requireChecklistAuditComplete(List<String> issues) {
  final data = _readEvidence(_checklistAuditPath);
  if (data == null) {
    issues.add(
        'Checklist audit file is missing or invalid: $_checklistAuditPath.');
    return;
  }
  final unchecked = (data['uncheckedItemCount'] as num?)?.toInt();
  final checkedWithoutEvidence =
      (data['checkedWithoutEvidenceCount'] as num?)?.toInt();
  final knownLimitationsReferenced = data['knownLimitationsReferenced'] == true;
  final supportedHardwareReferenced =
      data['supportedHardwareByPlatformReferenced'] == true;
  if (unchecked != 0) {
    issues.add('Checklist audit has uncheckedItemCount=$unchecked.');
  }
  if (checkedWithoutEvidence != 0) {
    issues.add(
      'Checklist audit has checkedWithoutEvidenceCount=$checkedWithoutEvidence.',
    );
  }
  if (!knownLimitationsReferenced) {
    issues.add('Checklist audit does not reference $_knownLimitationsPath.');
  }
  if (!supportedHardwareReferenced) {
    issues.add('Checklist audit does not reference $_supportedHardwarePath.');
  }
}

void _requirePublicReleaseGateReady(List<String> issues) {
  final data = _readEvidence(_publicReleaseGatePath);
  if (data == null) {
    issues.add(
      'Public release gate file is missing or invalid: $_publicReleaseGatePath.',
    );
    return;
  }
  final decision = data['decision']?.toString() ?? '';
  final ready = data['ready'] == true;
  final blockerCount = (data['blockerCount'] as num?)?.toInt();
  if (decision != 'READY' || !ready || blockerCount != 0) {
    issues.add(
      'Public release gate must be READY with blockerCount=0; '
      'decision=$decision ready=$ready blockerCount=$blockerCount.',
    );
  }
}

void _requireReleaseNotesComplete(
  Map<String, dynamic> data,
  List<String> issues,
  File releaseNotes,
) {
  final configuredPath = data['releaseNotesPath']?.toString().trim() ?? '';
  final normalizedPath = _normalizePath(configuredPath);
  if (normalizedPath == _normalizePath(_releaseNotesTemplatePath)) {
    issues
        .add('releaseNotesPath must not point to the release notes template.');
  }

  final content = releaseNotes.readAsStringSync();
  if (content.contains('Nightshade Release Notes Template') ||
      content.contains('Replace bracketed values')) {
    issues.add('release notes still contain template instructions.');
  }
  for (final heading in _requiredReleaseNoteHeadings) {
    if (!content.contains(heading)) {
      issues.add('release notes are missing required heading: $heading.');
    }
  }
  final placeholder = _releaseNotePlaceholderPattern.firstMatch(content);
  if (placeholder != null) {
    issues.add(
      'release notes contain unreplaced template placeholder `${placeholder.group(0)}`.',
    );
  }
  for (final requiredReference in [
    _knownLimitationsPath,
    _supportedHardwarePath,
    'docs/production-readiness/public-release-gate.json',
  ]) {
    if (!content.contains(requiredReference)) {
      issues.add(
        'release notes must reference $requiredReference.',
      );
    }
  }
}

final _releaseNotePlaceholderPattern = RegExp(
  r'\[(version|commit SHA|YYYY-MM-DD|name|ship / no-ship|supported / limited / not shipped|installer/path|bundle/path|test evidence|camera, mount, \.\.\.|platforms|hardware/simulator notes|vendor/device|workflows|feature|what changed, user impact, verification|yes/no \+ evidence|view/control/admin evidence|loopback/authenticated LAN/other|summary|slew, park, backup restore, file browse, etc\.|version/path|pass/fail|range|versions|limitation|impact|workaround|yes/no|issue id or summary|fix summary|command|log/path|backup requirement|driver/package requirement|settings migration note|path|steps)\]',
  caseSensitive: false,
);

String _normalizePath(String path) => path.replaceAll('\\', '/').toLowerCase();

void _requireFileSizeMatches(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  File file,
) {
  final expected = data[field];
  if (expected is! num || expected <= 0) {
    return;
  }
  final actual = file.lengthSync();
  if (actual != expected.toInt()) {
    issues.add(
      '$field=$expected does not match actual file size $actual for ${file.path}.',
    );
  }
}

void _requireFileSha256Matches(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
  File file,
) {
  final expected = data[field]?.toString().trim().toLowerCase() ?? '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    return;
  }
  final actual = _sha256(file);
  if (actual == null) {
    issues.add('Could not compute SHA256 for ${file.path}.');
    return;
  }
  if (actual != expected) {
    issues.add(
      '$field does not match actual SHA256 for ${file.path}: expected $expected actual $actual.',
    );
  }
}

String? _sha256(File file) {
  final result = Platform.isWindows
      ? Process.runSync('certutil', ['-hashfile', file.path, 'SHA256'])
      : Process.runSync('sha256sum', [file.path]);
  if (result.exitCode != 0) {
    return null;
  }
  final output = result.stdout.toString();
  final match = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(output);
  return match?.group(0)?.toLowerCase();
}

void _requireIsoDate(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field]?.toString().trim() ?? '';
  final parsed = DateTime.tryParse(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) || parsed == null) {
    issues.add('$field must be an ISO date in yyyy-mm-dd format.');
  }
}

void _requireCurrentGitHead(
  Map<String, dynamic> data,
  List<String> issues,
  String field,
) {
  final value = data[field]?.toString().trim().toLowerCase() ?? '';
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    issues.add('$field must be a full 40-character git commit hash.');
    return;
  }
  final result = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (result.exitCode != 0) {
    issues.add('Could not read current git HEAD for final sign-off check.');
    return;
  }
  final head = result.stdout.toString().trim().toLowerCase();
  if (value != head) {
    issues.add('$field must match current git HEAD $head.');
  }
}

void _validateCommandResults(
  Map<String, dynamic> data,
  List<String> issues, {
  bool requireEveryDeviceType = false,
  bool requireStateReadback = false,
  bool requireRequestId = false,
}) {
  final commands = data['commandResults'];
  if (commands is! List) {
    return;
  }

  final coveredDeviceTypes = <String>{};
  for (var i = 0; i < commands.length; i++) {
    final command = commands[i];
    if (command is! Map) {
      issues.add('commandResults[$i] must be an object.');
      continue;
    }
    final entry = command.cast<String, dynamic>();
    if (entry['passed'] != true) {
      issues.add('commandResults[$i].passed must be true.');
    }
    for (final field in ['deviceType', 'deviceId', 'command']) {
      if ((entry[field]?.toString().trim() ?? '').isEmpty) {
        issues.add('commandResults[$i].$field is required.');
      }
    }
    if (requireStateReadback &&
        (entry['stateReadback']?.toString().trim() ?? '').isEmpty) {
      issues.add('commandResults[$i].stateReadback is required.');
    }
    if (requireRequestId &&
        (entry['requestId']?.toString().trim() ?? '').isEmpty) {
      issues.add('commandResults[$i].requestId is required.');
    }
    if (requireEveryDeviceType &&
        !_requiredDeviceTypes.contains(entry['deviceType'])) {
      issues.add(
        'commandResults[$i].deviceType must be one of: ${_requiredDeviceTypes.join(', ')}.',
      );
    }
    if (requireEveryDeviceType) {
      final backingType = entry['backingType']?.toString().trim() ?? '';
      if (backingType.isEmpty) {
        issues.add('commandResults[$i].backingType is required.');
      } else if (backingType != 'real' && backingType != 'simulator') {
        issues.add(
          'commandResults[$i].backingType must be `real` or `simulator`.',
        );
      }
    }
    final deviceType = entry['deviceType']?.toString().trim();
    if (deviceType != null && deviceType.isNotEmpty) {
      coveredDeviceTypes.add(deviceType);
    }
  }

  if (requireEveryDeviceType) {
    final missing = _requiredDeviceTypes
        .where((deviceType) => !coveredDeviceTypes.contains(deviceType))
        .toList();
    if (missing.isNotEmpty) {
      issues.add(
        'commandResults is missing device types: ${missing.join(', ')}.',
      );
    }
  }
}

void _validateConnectionResults(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final connections = data['connectionResults'];
  if (connections is! List) {
    return;
  }

  final coveredDeviceTypes = <String>{};
  for (var i = 0; i < connections.length; i++) {
    final connection = connections[i];
    if (connection is! Map) {
      issues.add('connectionResults[$i] must be an object.');
      continue;
    }
    final entry = connection.cast<String, dynamic>();
    for (final field in ['deviceType', 'deviceId', 'statusReadback']) {
      if ((entry[field]?.toString().trim() ?? '').isEmpty) {
        issues.add('connectionResults[$i].$field is required.');
      }
    }
    final deviceType = entry['deviceType']?.toString().trim() ?? '';
    if (deviceType.isNotEmpty) {
      coveredDeviceTypes.add(deviceType);
      if (!_requiredDeviceTypes.contains(deviceType)) {
        issues.add(
          'connectionResults[$i].deviceType must be one of: ${_requiredDeviceTypes.join(', ')}.',
        );
      }
    }
    final backingType = entry['backingType']?.toString().trim() ?? '';
    if (backingType.isEmpty) {
      issues.add('connectionResults[$i].backingType is required.');
    } else if (backingType != 'real' && backingType != 'simulator') {
      issues.add(
        'connectionResults[$i].backingType must be `real` or `simulator`.',
      );
    }
    if (entry['connectPassed'] != true) {
      issues.add('connectionResults[$i].connectPassed must be true.');
    }
    if (entry['disconnectPassed'] != true) {
      issues.add('connectionResults[$i].disconnectPassed must be true.');
    }
  }

  final missing = _requiredDeviceTypes
      .where((deviceType) => !coveredDeviceTypes.contains(deviceType))
      .toList();
  if (missing.isNotEmpty) {
    issues.add(
      'connectionResults is missing device types: ${missing.join(', ')}.',
    );
  }
}

void _validateCoveredCommandScope(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final covered = _stringList(data['coveredDeviceTypes']);
  final commands = data['commandResults'];
  if (covered.isEmpty || commands is! List) {
    return;
  }

  final commandDeviceTypes = <String>{};
  for (var i = 0; i < commands.length; i++) {
    final command = commands[i];
    if (command is! Map) {
      continue;
    }
    final deviceType = command['deviceType']?.toString().trim() ?? '';
    if (deviceType.isEmpty) {
      continue;
    }
    commandDeviceTypes.add(deviceType);
    if (!covered.contains(deviceType)) {
      issues.add(
        'commandResults[$i].deviceType `$deviceType` is not listed in coveredDeviceTypes.',
      );
    }
  }

  final missing = covered
      .where((deviceType) => !commandDeviceTypes.contains(deviceType))
      .toList();
  if (missing.isNotEmpty) {
    issues.add(
      'commandResults is missing coveredDeviceTypes: ${missing.join(', ')}.',
    );
  }
}

void _requireAuditLogContainsCommandRequestIds(
  Map<String, dynamic> data,
  List<String> issues,
) {
  final auditLogPath = data['auditLogPath']?.toString().trim() ?? '';
  if (auditLogPath.isEmpty) {
    return;
  }
  final auditLog = File(auditLogPath);
  if (!auditLog.existsSync()) {
    return;
  }
  final content = auditLog.readAsStringSync();
  final commands = data['commandResults'];
  if (commands is! List) {
    return;
  }
  for (var i = 0; i < commands.length; i++) {
    final command = commands[i];
    if (command is! Map) {
      continue;
    }
    final requestId = command['requestId']?.toString().trim() ?? '';
    if (requestId.isEmpty) {
      continue;
    }
    if (!content.contains(requestId)) {
      issues.add(
        'auditLogPath does not contain commandResults[$i].requestId $requestId.',
      );
    }
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

String _renderMarkdown(List<_EvidenceCheck> checks) {
  final buffer = StringBuffer()
    ..writeln('# Public Release External Evidence')
    ..writeln()
    ..writeln(
        '- Passed checks: `${checks.where((check) => check.passed).length}`')
    ..writeln('- Total checks: `${checks.length}`')
    ..writeln('- Template directory: `$_templateDirectory`')
    ..writeln()
    ..writeln(
      'This verifier accepts future manual or external evidence only when it matches the required schema. Missing evidence remains blocked.',
    )
    ..writeln()
    ..writeln('## Checks')
    ..writeln()
    ..writeln('| Status | Check | Evidence | Template |')
    ..writeln('| --- | --- | --- | --- |');

  for (final check in checks) {
    buffer.writeln(
      '| ${check.passed ? 'PASS' : 'BLOCKED'} | ${check.label} | `${check.evidencePath}` | `${check.templatePath}` |',
    );
  }

  for (final check in checks) {
    buffer
      ..writeln()
      ..writeln('## ${check.label}')
      ..writeln()
      ..writeln('- ID: `${check.id}`')
      ..writeln('- Status: `${check.passed ? 'PASS' : 'BLOCKED'}`')
      ..writeln('- Evidence path: `${check.evidencePath}`')
      ..writeln('- Template path: `${check.templatePath}`')
      ..writeln()
      ..writeln('Requirements:');
    for (final requirement in check.requirements) {
      buffer.writeln('- $requirement');
    }
    buffer
      ..writeln()
      ..writeln('Issues:');
    if (check.issues.isEmpty) {
      buffer.writeln('- None.');
    } else {
      for (final issue in check.issues) {
        buffer.writeln('- $issue');
      }
    }
  }

  return buffer.toString();
}

class _EvidenceCheck {
  final String id;
  final String label;
  final String evidencePath;
  final String templatePath;
  final bool passed;
  final List<String> issues;
  final List<String> requirements;

  const _EvidenceCheck({
    required this.id,
    required this.label,
    required this.evidencePath,
    required this.templatePath,
    required this.passed,
    required this.issues,
    required this.requirements,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'evidencePath': evidencePath,
        'templatePath': templatePath,
        'passed': passed,
        'requirements': requirements,
        'issues': issues,
      };
}
