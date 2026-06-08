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

    final images = await _ref.read(imagesDaoProvider).getImagesForSession(sessionId);
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
    final targetId =
        accepted.map((i) => i.targetId).firstWhere((id) => id != null, orElse: () => null);
    final targetName = targetId != null
        ? (await _ref.read(targetsDaoProvider).getTargetById(targetId))?.name
        : null;

    // Multi-night: if the target has an active accumulating master for the
    // dominant filter, fold tonight's subs into it rather than starting fresh.
    if (targetId != null) {
      final filter = _dominantFilter(accepted);
      final master = await _ref
          .read(integratedMastersDaoProvider)
          .getAccumulatingForTargetFilter(targetId: targetId, filter: filter);
      if (master != null) {
        try {
          final group =
              accepted.where((s) => (s.filter ?? '') == (filter ?? '')).toList();
          final result =
              await _ref.read(masterAccumulationServiceProvider).addNight(
                    masterId: master.id,
                    subs: group,
                    label: DateTime.now().toIso8601String().split('T').first,
                    settings: settings,
                  );
          await _afterSuccess(
            sessionId: sessionId,
            targetId: targetId,
            targetName: targetName ?? master.name,
            integrationSeconds: result.totalIntegrationSec,
            framesKept: result.framesAdded,
            framesRejected: result.rejected,
          );
          return AutoIntegrationResult(
            ran: true,
            message: 'Added ${result.framesAdded} subs to ${master.name} '
                '(${result.frameCount} total).',
          );
        } catch (e) {
          return AutoIntegrationResult(
            ran: false,
            message: 'Auto-accumulate failed: $e',
          );
        }
      }
    }

    // One-shot batch integration of the night.
    try {
      final outDir = await _outputDir();
      final outcomes =
          await _ref.read(postSessionIntegrationServiceProvider).integrate(
                subs: accepted,
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
      if (outcomes.isEmpty) {
        return const AutoIntegrationResult(
          ran: false,
          message: 'Integration produced no master.',
        );
      }
      final total = outcomes.fold<int>(0, (a, o) => a + o.result.framesIntegrated);
      final rejected =
          outcomes.fold<int>(0, (a, o) => a + o.result.framesRejected);
      final integrationSeconds =
          outcomes.fold<double>(0, (a, o) => a + o.result.totalIntegrationSec);
      await _afterSuccess(
        sessionId: sessionId,
        targetId: targetId,
        targetName: targetName,
        integrationSeconds: integrationSeconds,
        framesKept: total,
        framesRejected: rejected,
      );
      return AutoIntegrationResult(
        ran: true,
        masterId: outcomes.first.masterId,
        message: 'Your image is ready — integrated $total subs into '
            '${outcomes.length} master${outcomes.length == 1 ? '' : 's'}.',
      );
    } catch (e) {
      return AutoIntegrationResult(ran: false, message: 'Auto-integrate failed: $e');
    }
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
    final raw =
        await _ref.read(settingsDaoProvider).getSetting(kAutoIntegrateSettingKey);
    return raw == 'true';
  }

  Future<IntegrationSettings> _loadDefaultSettings() async {
    final raw = await _ref
        .read(settingsDaoProvider)
        .getSetting('post_session.default_settings');
    return IntegrationSettings.fromJsonStringOrDefault(raw);
  }

  String? _dominantFilter(List<DbCapturedImage> subs) {
    final counts = <String, int>{};
    for (final s in subs) {
      final f = (s.filter ?? '').trim();
      counts[f] = (counts[f] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return best.isEmpty ? null : best;
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
