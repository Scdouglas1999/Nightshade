/// Delivery over SFTP to a host the rig can reach — "my Linux box in the
/// office".
///
/// Config (`delivery_targets.config_json`), no key material:
///
/// ```json
/// {"host": "office.local", "port": 22, "user": "sean",
///  "remoteDir": "/srv/astro/incoming",
///  "hostKeyFingerprint": "SHA256:s0m3Base64",
///  "digestCommand": "sha256sum"}
/// ```
///
/// The private key lives in `SecretsStore` under the destination row's
/// `secret_ref` and is written to a mode-0600 file inside a private scratch
/// directory for the duration of the delivery.
///
/// **Host key pinning.** On the first delivery the transport scans the
/// server's host keys, pins one fingerprint onto the destination row, and
/// writes a known-hosts file for the session. Every later delivery requires
/// the server to still present that key: a mismatch is a
/// [DeliveryFailureKind.hostKeyMismatch] failure and no bytes move. This is
/// trust on first use — the first connection is the one an attacker would have
/// to already own.
///
/// **Password authentication is not offered.** OpenSSH deliberately refuses to
/// read a password from a pipe, and the alternative (`sshpass`) is not a
/// dependency of this project. A destination configured for password auth
/// fails with [DeliveryFailureKind.authMethodUnavailable] naming the
/// substitute — a key — rather than appearing to work and hanging on a prompt.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../models/darkroom/delivery.dart';
import '../notification/secrets_store.dart';
import 'artifact_transport.dart';
import 'atomic_file_write.dart';
import 'delivery_failure.dart';
import 'delivery_artifact.dart';
import 'sftp_command_runner.dart';

/// How long any one OpenSSH invocation may run before it is killed. The
/// upload gets its own, longer budget.
const Duration kSftpControlCommandTimeout = Duration(seconds: 30);

/// How long one file upload may run before it is killed.
const Duration kSftpUploadTimeout = Duration(minutes: 30);

/// The remote command used to verify a delivered file when the destination
/// names none.
const String kDefaultRemoteDigestCommand = 'sha256sum';

/// Called when the transport learns a host key it had no pin for, so the
/// caller can persist it onto the destination row. Delivery does not continue
/// until the pin is durable — a fingerprint that lives only in memory would be
/// re-learned (and re-trusted) on the next attempt.
typedef HostKeyPinWriter = Future<void> Function(String fingerprint);

/// Copies artifacts to an SFTP server, one atomic file at a time.
class SftpTransport implements ArtifactTransport {
  /// The destination row this transport serves.
  final ArtifactDestination destination;

  /// The job whose artifacts are being delivered; names the remote staged
  /// files.
  final int jobId;

  final SftpCommandRunner _runner;
  final SecretsStore _secrets;
  final HostKeyPinWriter _pinHostKey;

  _SftpSession? _session;

  SftpTransport({
    required this.destination,
    required this.jobId,
    required SecretsStore secrets,
    required HostKeyPinWriter pinHostKey,
    SftpCommandRunner runner = const ProcessSftpCommandRunner(),
  }) : _secrets = secrets,
       _pinHostKey = pinHostKey,
       _runner = runner;

  @override
  ArtifactDestinationKind get kind => ArtifactDestinationKind.sftp;

  @override
  Future<void> open(List<DeliveryFile> artifacts) async {
    final config = _SftpConfig.parse(destination);

    for (final tool in const ['ssh', 'sftp', 'ssh-keyscan']) {
      if (!await _runner.isAvailable(tool)) {
        throw DeliveryFailure(
          DeliveryFailureKind.transportToolMissing,
          'SFTP delivery drives the OpenSSH client and `$tool` is not on this '
          'machine\'s PATH',
        );
      }
    }

    final secretRef = destination.secretRef;
    if (secretRef == null || secretRef.trim().isEmpty) {
      throw const DeliveryFailure(
        DeliveryFailureKind.credentialMissing,
        'This SFTP destination names no secret_ref, so there is no key to '
        'authenticate with',
      );
    }
    final privateKey = await _secrets.read(secretRef);
    if (privateKey.isEmpty) {
      throw DeliveryFailure(
        DeliveryFailureKind.credentialMissing,
        'The keyring holds no value for $secretRef',
      );
    }

    final workDir = await Directory.systemTemp.createTemp('ns_sftp_');
    final _SftpSession session;
    try {
      session = await _openSession(
        config: config,
        privateKey: privateKey,
        workDir: workDir,
      );
    } on Object catch (error, stack) {
      // The scratch directory holds the private key. Whatever went wrong, the
      // key does not outlive the failed attempt — and the original failure is
      // what reaches the caller, with its stack intact.
      await _deleteWorkDir(workDir);
      Error.throwWithStackTrace(error, stack);
    }
    _session = session;
  }

  /// Write the key material, pin the host key, and prove the remote directory
  /// is there. The caller owns [workDir] and removes it if this throws.
  Future<_SftpSession> _openSession({
    required _SftpConfig config,
    required String privateKey,
    required Directory workDir,
  }) async {
    final keyFile = File(p.join(workDir.path, 'id_delivery'));
    await keyFile.writeAsString(
      privateKey.endsWith('\n') ? privateKey : '$privateKey\n',
    );
    if (!Platform.isWindows) {
      // OpenSSH refuses a private key any other account can read. Dart cannot
      // set a file mode directly, so this is the one place the transport
      // shells out for something other than SSH itself.
      final chmod = await _runner.run('chmod', [
        '600',
        keyFile.path,
      ], timeout: const Duration(seconds: 10));
      if (!chmod.succeeded) {
        throw DeliveryFailure(
          DeliveryFailureKind.transportFailure,
          'The delivery key file could not be made private: '
          '${chmod.diagnostic}',
        );
      }
    }

    final knownHosts = File(p.join(workDir.path, 'known_hosts'));
    final pinned = await _pinAndWriteKnownHosts(
      config: config,
      knownHosts: knownHosts,
    );

    final session = _SftpSession(
      config: config,
      workDir: workDir,
      keyFile: keyFile,
      knownHosts: knownHosts,
      pinnedFingerprint: pinned,
    );

    final probe = await _runner.run('ssh', [
      ...session.sshOptions,
      config.userAtHost,
      'test',
      '-d',
      config.quotedRemoteDir,
    ], timeout: kSftpControlCommandTimeout);
    if (!probe.succeeded) {
      throw DeliveryFailure(
        DeliveryFailureKind.destinationUnreachable,
        '${config.userAtHost}:${config.remoteDir} did not answer as a '
        'directory: ${probe.diagnostic}',
      );
    }

    return session;
  }

  @override
  Future<TransportDeliveryOutcome> deliver(DeliveryFile artifact) async {
    final session = _session;
    if (session == null) {
      throw const DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'This SFTP destination was asked to deliver before it was opened',
      );
    }
    final config = session.config;
    final finalPath = p.posix.join(config.remoteDir, artifact.fileName);
    final stagedPath = p.posix.join(
      config.remoteDir,
      '.${artifact.fileName}.$jobId$kStagedDeliverySuffix',
    );
    _refuseUnquotableName(artifact.fileName);

    final existing = await _runner.run('ssh', [
      ...session.sshOptions,
      config.userAtHost,
      'test',
      '-e',
      _quote(finalPath),
    ], timeout: kSftpControlCommandTimeout);
    if (existing.succeeded) {
      final remoteDigest = await _remoteDigest(session, finalPath);
      if (remoteDigest == artifact.checksum) {
        return TransportDeliveryOutcome(
          disposition: DeliveryDisposition.delivered,
          checksum: remoteDigest,
          destinationDescription: '${config.userAtHost}:$finalPath',
        );
      }
      throw DeliveryFailure(
        DeliveryFailureKind.destinationConflict,
        '${config.userAtHost}:$finalPath already exists with different '
        'content (there: $remoteDigest, here: ${artifact.checksum}); delivery '
        'copies and never overwrites',
      );
    }

    final upload = await _runner.run(
      'sftp',
      [...session.sftpOptions, '-b', '-', config.userAtHost],
      timeout: kSftpUploadTimeout,
      stdinText: 'put ${_quote(artifact.sourcePath)} ${_quote(stagedPath)}\n',
    );
    if (!upload.succeeded) {
      await _removeRemote(session, stagedPath);
      throw DeliveryFailure(
        DeliveryFailureKind.transportFailure,
        'Uploading ${artifact.fileName} to ${config.userAtHost} failed: '
        '${upload.diagnostic}',
      );
    }

    final landed = await _remoteDigest(session, stagedPath);
    if (landed != artifact.checksum) {
      await _removeRemote(session, stagedPath);
      throw DeliveryFailure(
        DeliveryFailureKind.checksumMismatch,
        'The copy of ${artifact.fileName} on ${config.userAtHost} hashes to '
        '$landed, not ${artifact.checksum}',
      );
    }

    final rename = await _runner.run(
      'sftp',
      [...session.sftpOptions, '-b', '-', config.userAtHost],
      timeout: kSftpControlCommandTimeout,
      stdinText: 'rename ${_quote(stagedPath)} ${_quote(finalPath)}\n',
    );
    if (!rename.succeeded) {
      await _removeRemote(session, stagedPath);
      throw DeliveryFailure(
        DeliveryFailureKind.transportFailure,
        'Renaming ${artifact.fileName} into place on ${config.userAtHost} '
        'failed: ${rename.diagnostic}',
      );
    }

    return TransportDeliveryOutcome(
      disposition: DeliveryDisposition.delivered,
      checksum: landed,
      destinationDescription: '${config.userAtHost}:$finalPath',
    );
  }

  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    if (session != null) await _deleteWorkDir(session.workDir);
  }

  /// Scan the server's host keys, compare them with the pin on the
  /// destination row, and write the known-hosts file the session uses.
  Future<String> _pinAndWriteKnownHosts({
    required _SftpConfig config,
    required File knownHosts,
  }) async {
    final scan = await _runner.run('ssh-keyscan', [
      '-p',
      '${config.port}',
      config.host,
    ], timeout: kSftpControlCommandTimeout);
    final entries = parseHostKeyScan(scan.stdout);
    if (entries.isEmpty) {
      throw DeliveryFailure(
        DeliveryFailureKind.destinationUnreachable,
        '${config.host}:${config.port} presented no host key: '
        '${scan.diagnostic}',
      );
    }

    final expected = config.hostKeyFingerprint;
    if (expected == null) {
      final learned = entries.first;
      await _pinHostKey(learned.fingerprint);
      await knownHosts.writeAsString('${learned.line}\n');
      return learned.fingerprint;
    }

    for (final entry in entries) {
      if (entry.fingerprint == expected) {
        await knownHosts.writeAsString('${entry.line}\n');
        return entry.fingerprint;
      }
    }
    throw DeliveryFailure(
      DeliveryFailureKind.hostKeyMismatch,
      '${config.host}:${config.port} presented '
      '${entries.map((e) => e.fingerprint).join(', ')} but this destination is '
      'pinned to $expected; nothing was sent',
    );
  }

  /// The remote digest of [remotePath], as lowercase hex.
  Future<String> _remoteDigest(_SftpSession session, String remotePath) async {
    final config = session.config;
    final commands = <String>[
      config.digestCommand,
      if (config.digestCommand == kDefaultRemoteDigestCommand) 'shasum -a 256',
    ];
    SftpCommandResult? last;
    for (final command in commands) {
      final result = await _runner.run('ssh', [
        ...session.sshOptions,
        config.userAtHost,
        command,
        _quote(remotePath),
      ], timeout: kSftpControlCommandTimeout);
      if (result.succeeded) {
        final digest = result.stdout.trim().split(RegExp(r'\s+')).first;
        if (digest.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(digest)) {
          return digest.toLowerCase();
        }
        throw DeliveryFailure(
          DeliveryFailureKind.transportToolMissing,
          '`$command` on ${config.userAtHost} answered "${digest.isEmpty ? result.stdout.trim() : digest}", '
          'which is not a SHA-256 digest',
        );
      }
      last = result;
    }
    throw DeliveryFailure(
      DeliveryFailureKind.transportToolMissing,
      '${config.userAtHost} offers no SHA-256 command to verify the delivery '
      'with (tried ${commands.join(', ')}): ${last?.diagnostic ?? 'no output'}',
    );
  }

  /// Remove a remote staged file. The failure that brought us here is the one
  /// reported; a staged file left behind is overwritten by the next attempt
  /// for the same job and file.
  Future<void> _removeRemote(_SftpSession session, String remotePath) async {
    await _runner.run(
      'sftp',
      [...session.sftpOptions, '-b', '-', session.config.userAtHost],
      timeout: kSftpControlCommandTimeout,
      stdinText: 'rm ${_quote(remotePath)}\n',
    );
  }

  Future<void> _deleteWorkDir(Directory workDir) async {
    try {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    } on FileSystemException catch (error) {
      throw DeliveryFailure(
        DeliveryFailureKind.transportFailure,
        'The private key file at ${workDir.path} could not be removed: '
        '${error.message}',
        cause: error,
      );
    }
  }
}

/// One host key `ssh-keyscan` reported.
class HostKeyScanEntry {
  /// The known-hosts line, verbatim.
  final String line;

  /// OpenSSH's `SHA256:<base64>` fingerprint of the key blob on that line.
  final String fingerprint;

  const HostKeyScanEntry({required this.line, required this.fingerprint});
}

/// Parse `ssh-keyscan` output into host-key entries with their OpenSSH
/// SHA-256 fingerprints.
///
/// The fingerprint is computed here rather than by shelling out to
/// `ssh-keygen -lf`: it is exactly the unpadded base64 of the SHA-256 of the
/// key blob, so computing it removes one binary from the dependency list and
/// one place the two could disagree.
List<HostKeyScanEntry> parseHostKeyScan(String scanOutput) {
  final entries = <HostKeyScanEntry>[];
  for (final raw in const LineSplitter().convert(scanOutput)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final List<int>? blob = _decodeBase64(parts[2]);
    if (blob == null) continue;
    final digest = sha256.convert(blob);
    final encoded = base64.encode(digest.bytes).replaceAll('=', '');
    entries.add(HostKeyScanEntry(line: line, fingerprint: 'SHA256:$encoded'));
  }
  return entries;
}

List<int>? _decodeBase64(String value) {
  try {
    return base64.decode(value);
  } on FormatException {
    // A keyscan line whose third field is not base64 is not a host key —
    // `ssh-keyscan` also emits comment and error lines. Skipping it here is
    // what makes the caller's "presented no host key" failure fire when NONE
    // of the lines parse.
    return null;
  }
}

/// The SFTP transport's parsed, non-secret configuration.
class _SftpConfig {
  final String host;
  final int port;
  final String user;
  final String remoteDir;
  final String? hostKeyFingerprint;
  final String digestCommand;

  const _SftpConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.remoteDir,
    required this.hostKeyFingerprint,
    required this.digestCommand,
  });

  String get userAtHost => '$user@$host';

  String get quotedRemoteDir => _quote(remoteDir);

  static _SftpConfig parse(ArtifactDestination destination) {
    final decoded = jsonDecode(destination.configJson);
    if (decoded is! Map) {
      throw const DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'This SFTP destination\'s configuration is not a JSON object',
      );
    }
    final config = decoded.cast<String, Object?>();

    final authMethod = config['authMethod'];
    if (authMethod is String && authMethod.trim().toLowerCase() == 'password') {
      throw const DeliveryFailure(
        DeliveryFailureKind.authMethodUnavailable,
        'SFTP delivery authenticates with a key. OpenSSH refuses to read a '
        'password from a pipe, so configure this destination with a private '
        'key in the keyring instead',
      );
    }

    final host = _requiredString(config, 'host');
    final user = _requiredString(config, 'user');
    final remoteDir = _requiredString(config, 'remoteDir');
    _refuseUnquotableName(remoteDir);

    final rawPort = config['port'];
    final port = rawPort ?? 22;
    if (port is! int || port < 1 || port > 65535) {
      throw DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'port on this SFTP destination is $rawPort, which is not a TCP port',
      );
    }

    final fingerprint = config['hostKeyFingerprint'];
    if (fingerprint != null && fingerprint is! String) {
      throw DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'hostKeyFingerprint on this SFTP destination is $fingerprint, which '
        'is not a fingerprint string',
      );
    }

    final digest = config['digestCommand'];
    if (digest != null && (digest is! String || digest.trim().isEmpty)) {
      throw DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'digestCommand on this SFTP destination is $digest, which is not a '
        'command',
      );
    }
    final digestCommand =
        (digest as String?)?.trim() ?? kDefaultRemoteDigestCommand;
    _refuseUnquotableName(digestCommand);

    return _SftpConfig(
      host: host,
      port: port,
      user: user,
      remoteDir: remoteDir,
      hostKeyFingerprint: (fingerprint as String?)?.trim(),
      digestCommand: digestCommand,
    );
  }

  static String _requiredString(Map<String, Object?> config, String key) {
    final value = config[key];
    if (value is! String || value.trim().isEmpty) {
      throw DeliveryFailure(
        DeliveryFailureKind.configurationInvalid,
        'This SFTP destination names no $key',
      );
    }
    return value.trim();
  }
}

/// One opened SFTP session: the scratch key material and the option list
/// every OpenSSH invocation shares.
class _SftpSession {
  final _SftpConfig config;
  final Directory workDir;
  final File keyFile;
  final File knownHosts;
  final String pinnedFingerprint;

  const _SftpSession({
    required this.config,
    required this.workDir,
    required this.keyFile,
    required this.knownHosts,
    required this.pinnedFingerprint,
  });

  /// Options common to `ssh` and `sftp`.
  ///
  /// `BatchMode=yes` and `NumberOfPasswordPrompts=0` are what turn a server
  /// that wants a password into an immediate non-zero exit instead of a
  /// process blocked on a prompt no one will ever see.
  List<String> get _commonOptions => <String>[
    '-o',
    'BatchMode=yes',
    '-o',
    'StrictHostKeyChecking=yes',
    '-o',
    'UserKnownHostsFile=${knownHosts.path}',
    '-o',
    'GlobalKnownHostsFile=${p.join(workDir.path, 'no_global_known_hosts')}',
    '-o',
    'IdentitiesOnly=yes',
    '-o',
    'PasswordAuthentication=no',
    '-o',
    'NumberOfPasswordPrompts=0',
    '-o',
    'ConnectTimeout=15',
    '-i',
    keyFile.path,
  ];

  /// `ssh` argument prefix.
  List<String> get sshOptions => <String>[
    ..._commonOptions,
    '-p',
    '${config.port}',
  ];

  /// `sftp` argument prefix. `sftp` spells the port `-P`.
  List<String> get sftpOptions => <String>[
    ..._commonOptions,
    '-P',
    '${config.port}',
  ];
}

/// Wrap [value] in single quotes for the remote shell.
String _quote(String value) => "'$value'";

/// Refuse a name that cannot be safely quoted for the remote shell.
///
/// Every remote path is passed inside single quotes, which is airtight for
/// every character except a single quote itself. Rather than build an escaping
/// scheme, a name carrying one is refused — an astronomical target name never
/// needs it, and a half-escaped path is how a delivery becomes a command.
void _refuseUnquotableName(String value) {
  if (value.contains("'")) {
    throw DeliveryFailure(
      DeliveryFailureKind.configurationInvalid,
      'SFTP delivery cannot address "$value": a single quote in a remote path '
      'cannot be passed to the remote shell safely',
    );
  }
}
