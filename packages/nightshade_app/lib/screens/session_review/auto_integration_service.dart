import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;

/// App-settings key controlling whether the post-session integration runs
/// automatically when a sequence run completes. Off by default — the user opts
/// in from Settings so an unattended night "just has the master ready" in the
/// morning.
const String kAutoIntegrateSettingKey = 'post_session.auto_integrate';

/// Result of an auto-integration attempt, surfaced to the run-completion host so
/// it can toast / notify the user.
class AutoIntegrationResult {
  /// True when an integration / accumulation actually ran.
  final bool ran;

  /// Human-readable summary for the toast / notification body.
  final String message;

  /// The new master id when a fresh batch integration produced one, else null.
  final int? masterId;

  const AutoIntegrationResult({
    required this.ran,
    required this.message,
    this.masterId,
  });

  static const AutoIntegrationResult disabled =
      AutoIntegrationResult(ran: false, message: 'Auto-integration disabled.');
}

/// Runs the post-session integration automatically at the end of a sequence run
/// when the opt-in setting is enabled (the "wake up to a finished image" hook).
///
/// For each target+filter group captured in the just-completed session it:
///  - folds the accepted subs into the target's active *accumulating* master
///    when one exists (multi-night growth), else
///  - runs a one-shot batch integration to produce a fresh linear master.
///
/// It never blocks the UI — the run-completion listener fires-and-forgets
/// [maybeRunForSession]; failures are returned, not thrown, so a botched
/// auto-run never crashes the app.
class AutoIntegrationService {
  AutoIntegrationService(this._ref);

  final Ref _ref;

  /// Run auto-integration for [sessionId] when enabled. Returns
  /// [AutoIntegrationResult.disabled] when the setting is off or there is
  /// nothing to integrate; otherwise a summary of what ran.
  Future<AutoIntegrationResult> maybeRunForSession(int sessionId) async {
    final enabled = await _isEnabled();
    if (!enabled) return AutoIntegrationResult.disabled;

    final images =
        await _ref.read(imagesDaoProvider).getImagesForSession(sessionId);
    final accepted = images
        .where((i) => i.frameType == 'light' && i.isAccepted)
        .toList(growable: false);
    if (accepted.isEmpty) {
      return const AutoIntegrationResult(
        ran: false,
        message: 'No accepted subs to integrate.',
      );
    }

    final settings = await _loadDefaultSettings();
    final targetId = accepted
        .map((i) => i.targetId)
        .firstWhere((id) => id != null, orElse: () => null);
    final targetName = targetId != null
        ? (await _ref.read(targetsDaoProvider).getTargetById(targetId))?.name
        : null;

    // Multi-night + multi-filter: split tonight's accepted subs by filter and
    // route EACH bucket independently — fold into that filter's active
    // accumulating master when one exists (multi-night growth), else collect it
    // for a fresh batch integration. An LRGB / SHO night must never silently
    // drop the subs of any non-dominant filter: every bucket is either folded or
    // batch-integrated, and the toast reports the total across all of them.
    final byFilter = _groupByFilter(accepted);

    // Buckets without an accumulating master are batch-integrated together (the
    // integrate service fans out per filter itself); buckets with one are folded.
    final batchSubs = <DbCapturedImage>[];
    var accumulatedSubs = 0;
    var accumulatedRejected = 0;
    var accumulatedSeconds = 0.0;
    final accumulatedInto = <String>[];

    try {
      for (final bucket in byFilter.entries) {
        final filter = bucket.key.isEmpty ? null : bucket.key;
        final group = bucket.value;

        final master = targetId == null
            ? null
            : await _ref
                .read(integratedMastersDaoProvider)
                .getAccumulatingForTargetFilter(
                    targetId: targetId, filter: filter);
        if (master == null) {
          // No accumulating master for this filter — batch-integrate it.
          batchSubs.addAll(group);
          continue;
        }

        final result =
            await _ref.read(masterAccumulationServiceProvider).addNight(
                  masterId: master.id,
                  subs: group,
                  label: DateTime.now().toIso8601String().split('T').first,
                  settings: settings,
                );
        accumulatedSubs += result.framesAdded;
        accumulatedRejected += result.rejected;
        accumulatedSeconds += result.totalIntegrationSec;
        accumulatedInto.add(master.name);
      }
    } catch (e) {
      return AutoIntegrationResult(
        ran: false,
        message: 'Auto-accumulate failed: $e',
      );
    }

    // One-shot batch integration of every filter bucket that had no accumulating
    // master to grow.
    var batchSubsIntegrated = 0;
    var batchRejected = 0;
    var batchSeconds = 0.0;
    var batchMasters = 0;
    int? firstBatchMasterId;
    if (batchSubs.isNotEmpty) {
      try {
        final outDir = await _outputDir();
        final outcomes =
            await _ref.read(postSessionIntegrationServiceProvider).integrate(
                  subs: batchSubs,
                  settings: settings,
                  targetId: targetId,
                  targetName: targetName,
                  outputFitsPathBuilder: (filterBucket) {
                    final stamp = DateTime.now().millisecondsSinceEpoch;
                    final base = _safeName(targetName ?? 'session');
                    final tag = filterBucket ==
                            PostSessionIntegrationService.noFilterBucket
                        ? ''
                        : '_${_safeName(filterBucket)}';
                    return p.join(outDir, '$base${tag}_master_$stamp.fits');
                  },
                );
        batchSubsIntegrated =
            outcomes.fold<int>(0, (a, o) => a + o.result.framesIntegrated);
        batchRejected =
            outcomes.fold<int>(0, (a, o) => a + o.result.framesRejected);
        batchSeconds = outcomes.fold<double>(
            0, (a, o) => a + o.result.totalIntegrationSec);
        batchMasters = outcomes.length;
        firstBatchMasterId =
            outcomes.isNotEmpty ? outcomes.first.masterId : null;
      } catch (e) {
        return AutoIntegrationResult(
            ran: false, message: 'Auto-integrate failed: $e');
      }
    }

    final totalKept = accumulatedSubs + batchSubsIntegrated;
    final totalRejected = accumulatedRejected + batchRejected;
    if (totalKept == 0 && accumulatedInto.isEmpty) {
      return const AutoIntegrationResult(
        ran: false,
        message: 'Integration produced no master.',
      );
    }

    await _afterSuccess(
      sessionId: sessionId,
      targetId: targetId,
      targetName: targetName,
      integrationSeconds: accumulatedSeconds + batchSeconds,
      framesKept: totalKept,
      framesRejected: totalRejected,
    );

    return AutoIntegrationResult(
      ran: true,
      masterId: firstBatchMasterId,
      message: _summaryMessage(
        totalKept: totalKept,
        batchMasters: batchMasters,
        accumulatedInto: accumulatedInto,
      ),
    );
  }

  /// Build the run-completion toast covering BOTH paths: subs folded into
  /// existing accumulating masters and subs freshly batch-integrated. Reports
  /// the total subs across every filter so a multi-filter night never
  /// under-reports.
  static String _summaryMessage({
    required int totalKept,
    required int batchMasters,
    required List<String> accumulatedInto,
  }) {
    final parts = <String>[];
    if (batchMasters > 0) {
      parts.add('$batchMasters master${batchMasters == 1 ? '' : 's'}');
    }
    if (accumulatedInto.isNotEmpty) {
      parts.add(accumulatedInto.length == 1
          ? '${accumulatedInto.single} (grown)'
          : '${accumulatedInto.length} accumulating masters (grown)');
    }
    final into = parts.isEmpty ? 'your library' : parts.join(' + ');
    return 'Your image is ready — integrated $totalKept subs into $into.';
  }

  /// Split accepted subs into filter buckets keyed by their trimmed filter name
  /// (empty string for the no-filter bucket). The trim mirrors the
  /// case-sensitive whitespace handling so a whitespace-padded filter name never
  /// fragments a bucket or silently drops its subs.
  Map<String, List<DbCapturedImage>> _groupByFilter(
      List<DbCapturedImage> subs) {
    final out = <String, List<DbCapturedImage>>{};
    for (final s in subs) {
      final key = (s.filter ?? '').trim();
      out.putIfAbsent(key, () => <DbCapturedImage>[]).add(s);
    }
    return out;
  }

  /// Fail-soft post-success hook fired after a master grows (accumulate) or is
  /// freshly integrated (batch). Two side effects, both individually guarded so
  /// neither can break the run-completion path:
  ///
  ///  (a) compute + persist the Night Doctor report for [sessionId]
  ///      ([NightAnalysisService.computeReport]), and
  ///  (b) enqueue a "master ready" phone push
  ///      (`Your TARGET master is ready — Hh Mm, +x% from culling`).
  ///
  /// Any failure in either is swallowed (logged via the result is not possible
  /// here — this runs after the result is decided) so an unattended morning
  /// still has its master even if reporting / push fails.
  Future<void> _afterSuccess({
    required int sessionId,
    int? targetId,
    String? targetName,
    required double integrationSeconds,
    required int framesKept,
    required int framesRejected,
  }) async {
    // (a) Night Doctor report. Best-effort: a reporting failure must never
    // sink the integration run.
    try {
      await _ref.read(nightAnalysisServiceProvider).computeReport(
            sessionId: sessionId,
            targetId: targetId,
          );
    } catch (_) {
      // Swallow — the master is already produced; a missing report is benign.
    }

    // (b) "Master ready" push. Independently guarded from (a).
    try {
      final body = _masterReadyBody(
        targetName: targetName,
        integrationSeconds: integrationSeconds,
        framesKept: framesKept,
        framesRejected: framesRejected,
      );
      _ref.read(pushNotificationServiceProvider).enqueue(
            PushNotification(
              title: 'Master ready',
              body: body,
              priority: PushNotificationPriority.normal,
              eventType: 'PostSessionMasterReady',
              category: EventCategory.imaging,
              timestamp: DateTime.now(),
            ),
          );
    } catch (_) {
      // Swallow — push is a courtesy, not part of the integration contract.
    }
  }

  /// Build the "master ready" push body, of the form
  /// `Your TARGET master is ready — Hh Mm, +x% from culling`.
  ///
  /// The "+x% from culling" is the predicted SNR uplift from dropping the
  /// rejected subs, approximated by the rejected-frame fraction (a conservative
  /// stand-in for the optimizer's gain until the marginal-SNR curve is wired
  /// through this path). It is omitted when nothing was culled.
  static String _masterReadyBody({
    required String? targetName,
    required double integrationSeconds,
    required int framesKept,
    required int framesRejected,
  }) {
    final who = (targetName != null && targetName.trim().isNotEmpty)
        ? '${targetName.trim()} '
        : '';
    final time = _formatIntegration(integrationSeconds);
    final total = framesKept + framesRejected;
    final buffer = StringBuffer('Your ${who}master is ready — $time');
    if (framesRejected > 0 && total > 0) {
      final pct = (framesRejected / total * 100).round();
      if (pct > 0) buffer.write(', +$pct% from culling');
    }
    return buffer.toString();
  }

  /// Format integration seconds as `Hh Mm` (e.g. `3h 12m`), or `Mm` when under
  /// an hour (e.g. `42m`), or `0m` when there is nothing to show.
  static String _formatIntegration(double seconds) {
    if (seconds <= 0) return '0m';
    final totalMinutes = (seconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  Future<bool> _isEnabled() async {
    final raw = await _ref
        .read(settingsDaoProvider)
        .getSetting(kAutoIntegrateSettingKey);
    return raw == 'true';
  }

  Future<IntegrationSettings> _loadDefaultSettings() async {
    final raw = await _ref
        .read(settingsDaoProvider)
        .getSetting('post_session.default_settings');
    return IntegrationSettings.fromJsonStringOrDefault(raw);
  }

  Future<String> _outputDir() async {
    final configured = await _ref
        .read(settingsDaoProvider)
        .getSetting('default_image_directory');
    if (configured != null && configured.trim().isNotEmpty) {
      return p.join(configured.trim(), 'masters');
    }
    return p.join('.', 'masters');
  }

  static String _safeName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'session' : cleaned;
  }
}

/// Provider for the [AutoIntegrationService].
final autoIntegrationServiceProvider = Provider<AutoIntegrationService>(
  (ref) => AutoIntegrationService(ref),
);
