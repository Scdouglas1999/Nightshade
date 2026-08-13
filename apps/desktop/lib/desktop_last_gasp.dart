import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// How a desktop session ended, as recorded on disk.
enum DesktopSessionOutcome {
  /// The process wrote "I am alive" and never wrote anything else — it was
  /// killed, crashed, or the engine took it down. Nothing was safed by us.
  running,

  /// The operator closed the window and the shell accepted the close.
  clean,

  /// A death path we saw coming (a stop signal, an unrecoverable error): the
  /// record was written and the rig-safing hook was run.
  fatal,
}

/// The last-gasp record the desktop GUI leaves behind for the NEXT launch.
///
/// Why it exists: the GUI could die with six devices connected — window black,
/// process gone — and leave a log whose last line was an unrelated warning. No
/// shutdown record, no device safing, no way to tell afterwards whether the
/// mount was parked. An unattended imager must never end that quietly, and the
/// operator must be able to find out that it did.
@immutable
class DesktopSessionRecord {
  const DesktopSessionRecord({
    required this.outcome,
    required this.reason,
    required this.at,
    this.version,
    this.pid,
    this.lastError,
    this.rigSafed,
    this.safingError,
  });

  final DesktopSessionOutcome outcome;

  /// Human-readable trigger ("Received SIGTERM", "Window closed").
  final String reason;
  final DateTime at;
  final String? version;
  final int? pid;

  /// The most recent framework/engine error this session saw. On a session
  /// that ends as [DesktopSessionOutcome.running] this is the only evidence of
  /// what took the process down.
  final String? lastError;

  /// Whether the rig-safing hook completed. Null when safing was never
  /// attempted (a clean close, or a session that just vanished).
  final bool? rigSafed;
  final String? safingError;

  bool get endedWithoutShutdownPath => outcome == DesktopSessionOutcome.running;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'reason': reason,
    'at': at.toIso8601String(),
    if (version != null) 'version': version,
    if (pid != null) 'pid': pid,
    if (lastError != null) 'lastError': lastError,
    if (rigSafed != null) 'rigSafed': rigSafed,
    if (safingError != null) 'safingError': safingError,
  };

  /// Parses a record written by a previous session. Returns null for anything
  /// unreadable — a truncated record (the process died mid-write) must never
  /// be louder than the silent death it is evidence of.
  static DesktopSessionRecord? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final at = DateTime.tryParse(decoded['at'] as String? ?? '');
      if (at == null) return null;
      final outcome = DesktopSessionOutcome.values.firstWhere(
        (value) => value.name == decoded['outcome'],
        orElse: () => DesktopSessionOutcome.running,
      );
      return DesktopSessionRecord(
        outcome: outcome,
        reason: decoded['reason'] as String? ?? 'unknown',
        at: at,
        version: decoded['version'] as String?,
        pid: decoded['pid'] as int?,
        lastError: decoded['lastError'] as String?,
        rigSafed: decoded['rigSafed'] as bool?,
        safingError: decoded['safingError'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  DesktopSessionRecord copyWith({
    DesktopSessionOutcome? outcome,
    String? reason,
    DateTime? at,
    String? lastError,
    bool? rigSafed,
    String? safingError,
  }) {
    return DesktopSessionRecord(
      outcome: outcome ?? this.outcome,
      reason: reason ?? this.reason,
      at: at ?? this.at,
      version: version,
      pid: pid,
      lastError: lastError ?? this.lastError,
      rigSafed: rigSafed ?? this.rigSafed,
      safingError: safingError ?? this.safingError,
    );
  }
}

/// The file a desktop session records its ending in, under the data root this
/// instance actually uses (`NIGHTSHADE_DATA_DIR` when the operator set one).
File resolveDesktopSessionRecordFile(String dataRoot) =>
    File(path.join(dataRoot, 'last_session.json'));

/// Writes the desktop GUI's shutdown record and safes the rig on the way out.
///
/// Deliberately owns no UI: the operator is not necessarily at the machine —
/// that is the whole problem — so the deliverables are a durable record and a
/// parked mount, not a dialog. All writes are SYNCHRONOUS: a process on its way
/// out may not survive another turn of the event loop, and a record written
/// after the death is worth nothing.
class DesktopLastGasp {
  DesktopLastGasp({
    required File recordFile,
    required Future<void> Function() safeRig,
    required void Function(int code) exitProcess,
    void Function(String message, {Object? error})? onInfo,
    void Function(String message, {Object? error})? onCritical,
    Duration safingTimeout = const Duration(seconds: 45),
    Duration errorRecordInterval = const Duration(seconds: 5),
    DateTime Function() now = DateTime.now,
    String? version,
    int? pid,
  }) : _recordFile = recordFile,
       _safeRig = safeRig,
       _exitProcess = exitProcess,
       _onInfo = onInfo,
       _onCritical = onCritical,
       _safingTimeout = safingTimeout,
       _errorRecordInterval = errorRecordInterval,
       _now = now,
       _version = version,
       _pid = pid;

  final File _recordFile;
  final Future<void> Function() _safeRig;
  final void Function(int code) _exitProcess;
  final void Function(String message, {Object? error})? _onInfo;
  final void Function(String message, {Object? error})? _onCritical;
  final Duration _safingTimeout;
  final Duration _errorRecordInterval;
  final DateTime Function() _now;
  final String? _version;
  final int? _pid;

  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];
  DesktopSessionRecord? _current;
  DateTime? _lastErrorWrite;
  bool _shuttingDown = false;
  bool _exited = false;

  /// The record left by the PREVIOUS session, or null when there is none (a
  /// first launch, a new data directory, or a record torn in half).
  DesktopSessionRecord? readPreviousSession() {
    try {
      if (!_recordFile.existsSync()) return null;
      return DesktopSessionRecord.tryParse(_recordFile.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// Stamp "this session is running". A record still saying this at the next
  /// launch is the proof that a session ended with no shutdown path at all.
  void markRunning({String reason = 'Session started'}) {
    _write(
      DesktopSessionRecord(
        outcome: DesktopSessionOutcome.running,
        reason: reason,
        at: _now(),
        version: _version,
        pid: _pid,
      ),
    );
  }

  /// The operator closed the window and the shell let it go.
  void recordCleanExit(String reason) {
    if (_shuttingDown) return;
    _write(
      (_current ?? _blank()).copyWith(
        outcome: DesktopSessionOutcome.clean,
        reason: reason,
        at: _now(),
      ),
    );
  }

  /// Remember the newest framework/engine error against the live record.
  ///
  /// This is what turns a silent death into a diagnosable one: the process that
  /// disappears after a frame-timeout leaves a `running` record naming the last
  /// error it saw. Throttled, because a render error can repeat every frame and
  /// this writes to disk.
  void noteError(String summary, {bool force = false}) {
    if (_shuttingDown) return;
    final record = _current ?? _blank();
    if (!force && record.lastError == summary) {
      final last = _lastErrorWrite;
      if (last != null && _now().difference(last) < _errorRecordInterval) {
        return;
      }
    }
    _lastErrorWrite = _now();
    _write(record.copyWith(lastError: summary, at: _now()));
  }

  /// The death path: record FIRST, then safe the rig, then exit.
  ///
  /// Ordering is the whole point. The record is the only evidence that survives
  /// a safing call that hangs, so it is on disk before a single device command
  /// is sent, and it is rewritten once safing settles. Safing is bounded and
  /// never throws — a failure to park must not stop the process from ending.
  /// A second call while one is in flight forces an immediate exit, so an
  /// operator (or a second signal) can always escape a wedged teardown.
  Future<void> handleFatal(
    String reason, {
    Object? error,
    StackTrace? stackTrace,
    int exitCode = 70,
  }) async {
    if (_shuttingDown) {
      _onCritical?.call('$reason during shutdown; forcing immediate exit');
      _terminate(1);
      return;
    }
    _shuttingDown = true;
    _onCritical?.call(
      '$reason; recording shutdown and safing the rig',
      error: error,
    );

    _write(
      (_current ?? _blank()).copyWith(
        outcome: DesktopSessionOutcome.fatal,
        reason: reason,
        at: _now(),
        lastError: error == null ? null : _summarise(error, stackTrace),
        rigSafed: false,
      ),
    );

    try {
      await _safeRig().timeout(_safingTimeout);
      _write((_current ?? _blank()).copyWith(rigSafed: true, at: _now()));
      _onInfo?.call('Rig safed during desktop shutdown');
    } catch (e) {
      _write(
        (_current ?? _blank()).copyWith(
          rigSafed: false,
          safingError: '$e',
          at: _now(),
        ),
      );
      _onCritical?.call(
        'Rig safing failed during desktop shutdown; the rig may still be '
        'tracking or exposed',
        error: e,
      );
    }

    _terminate(exitCode);
  }

  /// Wire the process-level death paths this entry point can actually see.
  ///
  /// * [signals] — a stop signal (logout, `systemctl stop`, Ctrl+C from a
  ///   terminal launch) is a real, common death that safed nothing before.
  /// * Framework errors are RECORDED, never acted on: an overflow or a stray
  ///   async error is not a reason to park a mount mid-sequence, but it is the
  ///   context the next launch needs if the process vanishes afterwards.
  void install({Iterable<ProcessSignal> signals = const []}) {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousOnError?.call(details);
      noteError(_summarise(details.exception, details.stack));
    };

    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      noteError(_summarise(error, stack));
      return previousPlatformOnError?.call(error, stack) ?? false;
    };

    for (final signal in signals) {
      try {
        _signalSubscriptions.add(
          signal.watch().listen(
            (received) => unawaited(handleFatal('Received $received')),
          ),
        );
      } catch (e) {
        // Not every signal is watchable on every platform (SIGTERM on
        // Windows). One unavailable signal must not cost us the others.
        _onInfo?.call('Cannot watch $signal for shutdown', error: e);
      }
    }
  }

  Future<void> dispose() async {
    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _signalSubscriptions.clear();
  }

  DesktopSessionRecord _blank() => DesktopSessionRecord(
    outcome: DesktopSessionOutcome.running,
    reason: 'Session started',
    at: _now(),
    version: _version,
    pid: _pid,
  );

  void _write(DesktopSessionRecord record) {
    _current = record;
    try {
      final parent = _recordFile.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);
      _recordFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(record.toJson()),
        flush: true,
      );
    } catch (e) {
      // A record we cannot write is not worth taking the process down over —
      // but it must not be silent either, or we reproduce the defect.
      _onCritical?.call(
        'Could not write the desktop shutdown record to ${_recordFile.path}',
        error: e,
      );
    }
  }

  void _terminate(int code) {
    if (_exited) return;
    _exited = true;
    _exitProcess(code);
  }

  String _summarise(Object error, StackTrace? stack) {
    final text = error.toString().split('\n').first.trim();
    if (stack == null) return text;
    final frame = stack
        .toString()
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    return frame.isEmpty ? text : '$text | $frame';
  }
}
