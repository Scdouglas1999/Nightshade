/// The morning report: what one dawn job integrated, what it drafted, what
/// calibration actually ran, and where the artifacts went.
///
/// Every number here is read from a record that survives a restart — the
/// `integrated_masters` row, the `darkroom_jobs` row, the `delivery_journal` —
/// so a job re-queued after a crash reports the same facts the first attempt
/// would have. Nothing is carried in memory from the integration that produced
/// it.
///
/// The report states omissions as loudly as results: a filter whose master has
/// no file yet, a calibration slot with no master, a draft step the data would
/// not support. A morning report that mentions only what worked is the
/// cry-wolf defect in reverse.
library;

import 'dart:convert';

import '../darkroom_delivery/delivery_service.dart';
import 'dawn_draft_builder.dart';
import 'dawn_master_resolver.dart';

/// One calibration slot's outcome, as the native applied-masters report
/// recorded it at integration time.
class DawnCalibrationSlot {
  /// `dark`, `flat`, or `bias`.
  final String kind;

  /// The master's path, or null when none was applied.
  final String? path;

  /// Whether this correction actually ran over the lights.
  final bool applied;

  /// `exact`, `acceptable`, `unverified`, `fallback`, `missing`, or
  /// `notRequired`.
  final String quality;

  /// Whether age or sensor temperature exceeded this slot's threshold.
  final bool stale;

  /// Dimensions that differ past tolerance, each named.
  final List<String> mismatches;

  /// Dimensions left unjudged because one side's header lacked the keyword.
  final List<String> unverified;

  const DawnCalibrationSlot({
    required this.kind,
    required this.path,
    required this.applied,
    required this.quality,
    required this.stale,
    required this.mismatches,
    required this.unverified,
  });

  /// True when this slot is something the morning report must mention.
  ///
  /// It mirrors the native `CalibrationReport::has_warnings` rule exactly:
  /// a fallback, a missing correction, a match nothing could be verified
  /// against, or a stale master. `notRequired` is not a warning — a matched
  /// dark already carries the bias pedestal, and subtracting a bias as well
  /// would remove it twice.
  bool get isWarning =>
      stale ||
      quality == 'fallback' ||
      quality == 'missing' ||
      quality == 'unverified' ||
      unverified.isNotEmpty;

  /// The report's sentence for this slot, or null when there is nothing to say.
  String? get sentence {
    if (!isWarning) return null;
    if (quality == 'missing') {
      return 'No master $kind was applied, so that correction did not run.';
    }
    final parts = <String>[];
    if (quality == 'fallback') {
      parts.add(
        'the master $kind differs from the lights past tolerance '
        '(${mismatches.join(', ')})',
      );
    }
    if (quality == 'unverified') {
      parts.add(
        'the master $kind could not be compared to the lights on any '
        'dimension, so nothing confirms it matches',
      );
    } else if (unverified.isNotEmpty) {
      parts.add(
        'the master $kind was not comparable on ${unverified.join(', ')}',
      );
    }
    if (stale) {
      parts.add('the master $kind is outside its age or temperature window');
    }
    if (parts.isEmpty) return null;
    return '${_capitalize(parts.first)}${parts.length > 1 ? '; ${parts.skip(1).join('; ')}' : ''}.';
  }

  /// The slot as report JSON.
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'path': path,
    'applied': applied,
    'quality': quality,
    'stale': stale,
    'mismatches': mismatches,
    'unverified': unverified,
    'warning': isWarning,
  };

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

/// What one master's integration recorded about itself.
///
/// Parsed from `integrated_masters.stats_json`, which the post-session
/// integration writes at persist time. A field the row does not carry is
/// reported absent rather than filled with a plausible number.
class DawnMasterStats {
  /// Frames that survived rejection and contributed pixels, or null when the
  /// row records none.
  final int? framesIntegrated;

  /// Frames rejected during integration, or null when the row records none.
  final int? framesRejected;

  /// Total integration time in seconds, or null when the row records none.
  final double? totalIntegrationSec;

  /// The applied-masters report, one entry per calibration slot. Empty when
  /// the master predates the report (integrated before this build).
  final List<DawnCalibrationSlot> calibration;

  /// Warnings the Dart calibration matcher raised while choosing the masters.
  final List<String> matcherWarnings;

  /// Whether per-light transient repair ran, or null when unrecorded.
  final bool? cosmeticCorrection;

  /// True when the anchor light's header could not be read, so every dimension
  /// is unverified rather than matched.
  final bool anchorUnreadable;

  const DawnMasterStats({
    required this.framesIntegrated,
    required this.framesRejected,
    required this.totalIntegrationSec,
    required this.calibration,
    required this.matcherWarnings,
    required this.cosmeticCorrection,
    required this.anchorUnreadable,
  });

  /// The empty statement: a master whose row records nothing.
  static const DawnMasterStats unrecorded = DawnMasterStats(
    framesIntegrated: null,
    framesRejected: null,
    totalIntegrationSec: null,
    calibration: <DawnCalibrationSlot>[],
    matcherWarnings: <String>[],
    cosmeticCorrection: null,
    anchorUnreadable: false,
  );

  /// The single flag the morning report branches on — the same thing the
  /// master FITS carries as its `CALWARN` card.
  bool get calibrationWarned =>
      anchorUnreadable ||
      matcherWarnings.isNotEmpty ||
      calibration.any((slot) => slot.isWarning);

  /// One sentence per calibration problem, in slot order.
  List<String> get calibrationSentences => <String>[
    if (anchorUnreadable)
      "The anchor light's header could not be read, so no calibration master "
          'could be compared against it.',
    for (final slot in calibration)
      if (slot.sentence != null) slot.sentence!,
    ...matcherWarnings,
  ];

  /// Parse `integrated_masters.stats_json`.
  ///
  /// A payload that is not a JSON object is reported [unrecorded]: the column
  /// is written by this app, so an unreadable value describes a master this
  /// build cannot account for, and inventing frame counts for it would put
  /// numbers in the morning report that nothing measured.
  static DawnMasterStats parse(String statsJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(statsJson);
    } on FormatException {
      return unrecorded;
    }
    if (decoded is! Map<String, dynamic>) return unrecorded;

    final calibration = decoded['calibration'];
    final slots = <DawnCalibrationSlot>[];
    var anchorUnreadable = false;
    bool? cosmetic;
    if (calibration is Map<String, dynamic>) {
      final anchor = calibration['anchorUnreadable'];
      anchorUnreadable = anchor is bool && anchor;
      final cosmeticRaw = calibration['cosmeticCorrection'];
      if (cosmeticRaw is bool) cosmetic = cosmeticRaw;
      final masters = calibration['masters'];
      if (masters is List) {
        for (final entry in masters) {
          if (entry is! Map<String, dynamic>) continue;
          final kind = entry['kind'];
          if (kind is! String) continue;
          slots.add(
            DawnCalibrationSlot(
              kind: kind,
              path: entry['path'] is String ? entry['path'] as String : null,
              applied: entry['applied'] == true,
              quality: entry['quality'] is String
                  ? entry['quality'] as String
                  : 'unverified',
              stale: entry['stale'] == true,
              mismatches: _mismatchNames(entry['mismatches']),
              unverified: _stringList(entry['unverified']),
            ),
          );
        }
      }
    }

    return DawnMasterStats(
      framesIntegrated: _asInt(decoded['framesIntegrated']),
      framesRejected: _asInt(decoded['framesRejected']),
      totalIntegrationSec: _asDouble(decoded['totalIntegrationSec']),
      calibration: List.unmodifiable(slots),
      matcherWarnings: _stringList(decoded['calibrationWarnings']),
      cosmeticCorrection: cosmetic,
      anchorUnreadable: anchorUnreadable,
    );
  }

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return List.unmodifiable(<String>[
      for (final entry in value)
        if (entry is String) entry,
    ]);
  }

  static List<String> _mismatchNames(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['withinTolerance'] == true) continue;
      final dimension = entry['dimension'];
      final light = entry['light'];
      final master = entry['master'];
      if (dimension is! String) continue;
      out.add(
        light is String && master is String
            ? '$dimension: lights $light, master $master'
            : dimension,
      );
    }
    return List.unmodifiable(out);
  }
}

/// One master's line in the morning report.
class DawnMasterReport {
  /// The master itself.
  final DawnMaster master;

  /// The target's name, or null when the master carries no target row.
  final String? targetName;

  /// What the integration recorded.
  final DawnMasterStats stats;

  /// The first draft, or null when one could not be composed.
  final DawnDraft? draft;

  /// The `recipes.id` the draft was persisted as, or null when it was not.
  final int? recipeId;

  /// Path of the rendered draft image, or null when no render was produced.
  final String? draftRenderPath;

  /// Why this master has no draft, or null when it has one.
  final String? failure;

  const DawnMasterReport({
    required this.master,
    required this.targetName,
    required this.stats,
    required this.draft,
    required this.recipeId,
    required this.draftRenderPath,
    required this.failure,
  });

  /// True when a draft image exists for this master.
  bool get hasDraft => draftRenderPath != null;

  /// True when the pipeline actually read this master's pixels.
  ///
  /// [draft] is the composition the registry answered with, and the registry
  /// only answers after it has opened the FITS and measured it. A null draft
  /// therefore means the read itself failed — a truncated file, a path that
  /// vanished — while a non-null draft with a [failure] means the pixels were
  /// read and a later stage (the export, the step measurement) stopped.
  ///
  /// Delivery keys on this: a master whose bytes could not be read must not be
  /// copied to a destination as though it were the night's result.
  bool get pixelsWereRead => draft != null;

  /// The master as report JSON.
  Map<String, dynamic> toJson() => {
    'masterId': master.masterId,
    'name': master.name,
    'targetName': targetName,
    'filter': master.filter,
    'channels': master.channels,
    'masterFitsPath': master.masterFitsPath,
    'framesFolded': master.frameCount,
    'framesIntegrated': stats.framesIntegrated,
    'framesRejected': stats.framesRejected,
    'integrationSeconds': master.totalIntegrationSeconds,
    'calibrationWarned': stats.calibrationWarned,
    'calibration': [for (final slot in stats.calibration) slot.toJson()],
    'calibrationSentences': stats.calibrationSentences,
    'recipeId': recipeId,
    'draftRenderPath': draftRenderPath,
    'draftSteps': draft == null ? const <Map<String, dynamic>>[] : draft!.steps,
    'draftNotes': draft == null
        ? const <Map<String, dynamic>>[]
        : [for (final note in draft!.notes) note.toJson()],
    'failure': failure,
  };
}

/// Whether the morning notification was sent, and why.
class DawnNotificationDecision {
  /// True when the notification reached at least one transport.
  final bool sent;

  /// Why it was or was not sent, naming the flag that decided.
  final String reason;

  const DawnNotificationDecision({required this.sent, required this.reason});

  /// The decision as report JSON.
  Map<String, dynamic> toJson() => {'sent': sent, 'reason': reason};
}

/// The whole job's morning report.
class DawnJobReport {
  /// The `darkroom_jobs.id` this report belongs to.
  final int jobId;

  /// `dawn` or `manual`.
  final String kind;

  /// The session processed.
  final int sessionId;

  /// When the job started, UTC.
  final DateTime startedAt;

  /// When the job finished, UTC.
  final DateTime finishedAt;

  /// The job's final state, as the row records it.
  final String state;

  /// One entry per master with a linear FITS.
  final List<DawnMasterReport> masters;

  /// Masters the night touched that have no file to draft over.
  final List<DawnMasterWithoutFile> withoutFile;

  /// What delivery did, or null when delivery did not run.
  final DeliveryRunReport? delivery;

  /// One sentence per delivery problem, each naming its mechanism.
  final List<String> deliveryProblems;

  /// The notification decision, or null for a job that does not notify.
  final DawnNotificationDecision? notification;

  /// Why the job stopped short, or null when it ran to the end.
  final String? failure;

  const DawnJobReport({
    required this.jobId,
    required this.kind,
    required this.sessionId,
    required this.startedAt,
    required this.finishedAt,
    required this.state,
    required this.masters,
    required this.withoutFile,
    required this.delivery,
    required this.deliveryProblems,
    required this.notification,
    required this.failure,
  });

  /// Frames that contributed pixels across every master, counting only the
  /// masters whose row records the number.
  int get framesUsed => masters.fold<int>(
    0,
    (sum, m) => sum + (m.stats.framesIntegrated ?? m.master.frameCount),
  );

  /// Frames rejected across every master whose row records the number.
  int get framesRejected => masters.fold<int>(0, (sum, m) {
    final rejected = m.stats.framesRejected;
    return rejected == null ? sum : sum + rejected;
  });

  /// Total integration seconds across every master.
  double get integrationSeconds => masters.fold<double>(
    0.0,
    (sum, m) => sum + m.master.totalIntegrationSeconds,
  );

  /// Drafts rendered by this job.
  int get draftsRendered => masters.where((m) => m.hasDraft).length;

  /// True when any master's calibration is something the operator must know
  /// about — the same thing the master FITS records as `CALWARN`.
  bool get calibrationWarned => masters.any((m) => m.stats.calibrationWarned);

  /// Every calibration sentence across every master, prefixed by the master it
  /// belongs to.
  List<String> get calibrationSentences => <String>[
    for (final master in masters)
      for (final sentence in master.stats.calibrationSentences)
        '${master.master.name}: $sentence',
  ];

  /// The target this night was about, when every master shares one.
  String? get primaryTargetName {
    final names = masters
        .map((m) => m.targetName)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toSet();
    return names.length == 1 ? names.single : null;
  }

  /// The same report recorded under another [state], carrying [failure].
  ///
  /// The pipeline uses it to rewrite the report as the ending the job row
  /// actually took, so the artifact on disk can never announce a state the row
  /// never reached.
  DawnJobReport withEnding({required String state, String? failure}) =>
      DawnJobReport(
        jobId: jobId,
        kind: kind,
        sessionId: sessionId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        state: state,
        masters: masters,
        withoutFile: withoutFile,
        delivery: delivery,
        deliveryProblems: deliveryProblems,
        notification: notification,
        failure: failure ?? this.failure,
      );

  /// The notification's title line.
  ///
  /// A night that rendered nothing says so. "Your 0 drafts are ready" reads as
  /// a successful delivery of nothing, which is the cry-wolf shape in reverse:
  /// the operator has to open the report to learn that the headline was about
  /// an empty hand.
  String get headline {
    final target = primaryTargetName;
    final time = formatDawnIntegration(integrationSeconds);
    if (draftsRendered == 0) {
      return '${target ?? 'Your night'} — no draft was rendered; '
          '$time integrated';
    }
    if (target == null) {
      return draftsRendered == 1
          ? 'Your draft is ready — $time integrated'
          : 'Your $draftsRendered drafts are ready — $time integrated';
    }
    return '$target — $time integrated';
  }

  /// The notification's body: what was integrated, what was rejected, what the
  /// calibration did, whether a draft exists, and where it went.
  String get body {
    final lines = <String>[];
    lines.add(
      '$framesUsed frame${framesUsed == 1 ? '' : 's'} used, '
      '$framesRejected rejected.',
    );
    if (draftsRendered > 0) {
      lines.add(
        '$draftsRendered draft${draftsRendered == 1 ? '' : 's'} ready to open '
        'in the Darkroom.',
      );
    } else {
      lines.add('No draft was rendered; the report says why.');
    }
    for (final master in masters) {
      if (master.failure != null) {
        lines.add('${master.master.name}: ${master.failure}');
      }
    }
    for (final missing in withoutFile) {
      lines.add('${missing.name}: ${missing.reason}');
    }
    if (calibrationWarned) {
      lines.addAll(calibrationSentences);
    }
    final deliveryReport = delivery;
    if (deliveryReport != null) {
      lines.add('Delivery — ${deliveryReport.summary}.');
    }
    // Outside the `delivery != null` arm: the problems that matter most are the
    // ones raised when nothing could be handed to a destination at all, and
    // those are exactly the runs where there is no destination report to nest
    // them under.
    lines.addAll(deliveryProblems);
    final stopped = failure;
    if (stopped != null) lines.add(stopped);
    return lines.join('\n');
  }

  /// The report as the JSON artifact delivery ships as the night report.
  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'kind': kind,
    'sessionId': sessionId,
    'state': state,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'framesUsed': framesUsed,
    'framesRejected': framesRejected,
    'integrationSeconds': integrationSeconds,
    'draftsRendered': draftsRendered,
    'calibrationWarned': calibrationWarned,
    'headline': headline,
    'body': body,
    'masters': [for (final master in masters) master.toJson()],
    'mastersWithoutFile': [
      for (final missing in withoutFile)
        {
          'masterId': missing.masterId,
          'name': missing.name,
          'reason': missing.reason,
        },
    ],
    'delivery': delivery == null
        ? null
        : {
            'summary': delivery!.summary,
            'delivered': delivery!.delivered,
            'awaitingPull': delivery!.awaitingPull,
            'retrying': delivery!.retrying,
            // Apart from `retrying`, which is files an attempt was spent on.
            // These are files a stop reached first; both are owed, and only
            // this one says the pass was cut short.
            'stoppedPending': delivery!.stoppedPending,
            'failed': delivery!.failed,
            'problems': deliveryProblems,
          },
    // Also at the top level, because a run that delivered nothing has no
    // `delivery` object to carry its problems and those are the runs whose
    // problems the operator most needs.
    'deliveryProblems': deliveryProblems,
    'notification': notification?.toJson(),
    'failure': failure,
  };
}

/// Format integration seconds as `3h 12m`, `42m`, or `0m`.
///
/// Named for the dawn report rather than generically: the app already exports a
/// `formatIntegration` of its own, and two same-named helpers imported into one
/// library is an ambiguity the compiler reports at every call site.
String formatDawnIntegration(double seconds) {
  if (seconds <= 0) return '0m';
  final totalMinutes = (seconds / 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
