import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../../localization/nightshade_localizations.dart';
import '../../utils/startup_surface_coordinator.dart';
import '../../widgets/catalog_setup_dialog.dart';
import '../../widgets/onboarding_tour_replay_launcher.dart';
import '../../widgets/tutorial_overlay.dart';
import '../../widgets/mobile_sequence_overlay.dart';
import '../../widgets/running_sequence_mini_bar.dart';
import '../sequencer/sequencer_screen.dart' show kSequencerRoutePath;
import '../../widgets/notification_toast_overlay.dart';
import '../../widgets/autofocus_progress_overlay.dart';
import '../../widgets/connection_stale_banner.dart';
import '../../widgets/disconnected_backend_banner.dart';
import '../../widgets/ios_background_banner.dart';
import '../../widgets/android_notifications_banner.dart';
import '../../widgets/weather/weather_alert_banner.dart';
import 'widgets/title_bar.dart';
import 'widgets/status_bar.dart';
import 'widgets/side_navigation.dart';
import 'shell_chrome.dart';
import 'shell_navigation.dart';
import 'immersive_chrome.dart';
import 'widgets/immersive_bottom_chrome.dart';
import 'widgets/nightshade_bottom_navigation.dart';

// Conditional import for window_manager (desktop only)
import 'app_shell_stub.dart' if (dart.library.io) 'app_shell_desktop.dart'
    as window_impl;

enum AppStartupCheckpointOutcome {
  noRecovery,
  resumed,
  discarded,
  failed,
}

enum AppCheckpointRecoveryChoice {
  resume,
  discard,
}

/// What a failed recovery attempt actually left behind.
///
/// The dialog used to assert, unconditionally, that "the checkpoint is still
/// available. Retry resume or discard it to start fresh" — directly under the
/// executor's own `Exception: No valid checkpoint to resume from`. One of those
/// two sentences was always wrong. [checkpointStillResumable] is re-read from
/// the backend after the failure so the modal states what is true now.
@visibleForTesting
class CheckpointAttemptFailure {
  final Object error;
  final bool checkpointStillResumable;

  const CheckpointAttemptFailure({
    required this.error,
    required this.checkpointStillResumable,
  });
}

/// Render [error] as a sentence rather than as a Dart object.
///
/// `'$error'` on a plain `Exception` prints `Exception: <message>`, which is
/// how a raw runtime string ended up in the operator's startup modal.
@visibleForTesting
String describeCheckpointFailure(Object error) {
  final text = error is NightshadeError ? error.userMessage : '$error';
  final trimmed = text.trim();
  for (final prefix in const ['Exception: ', 'Bad state: ']) {
    if (trimmed.startsWith(prefix)) return trimmed.substring(prefix.length);
  }
  return trimmed;
}

const String kCatalogSetupSkippedSettingKey = 'catalog_setup_skipped';

/// File names the native `CheckpointManager` uses inside the checkpoint
/// directory (`native/nightshade_native/sequencer/src/checkpoint.rs`,
/// `CHECKPOINT_FILENAME` / `CHECKPOINT_BACKUP`). Only
/// [adoptLegacyGuiCheckpoint] needs them, and only to move a pre-existing pair
/// forward; if the native names ever change, the adoption quietly finds
/// nothing, which is the same outcome as not migrating at all.
const List<String> _kCheckpointFileNames = <String>[
  'nightshade_session.checkpoint',
  'nightshade_session.checkpoint.bak',
];

/// Directory the desktop GUI keeps its sequence-recovery checkpoint in.
///
/// Anchored to the folder that holds the *open database*, not the platform
/// application-support folder. Every Nightshade GUI on a machine shares one
/// support folder, so the old anchor let a second instance — pointed at its
/// own database via `NIGHTSHADE_DATABASE_DIR` — be offered the first
/// instance's interrupted run: a "Recover Sequence?" modal naming a sequence
/// that has no row in the database the user actually has open, whose only
/// dismissal (Discard) then deleted the *other* instance's recovery state.
/// Anchoring on the database directory makes that structurally impossible: a
/// checkpoint can only ever be found beside the database whose run wrote it.
///
/// The `checkpoints/` subfolder mirrors `resolveHostCheckpointDirectory` in
/// the headless host, so a GUI and a daemon sharing a database directory still
/// do not overwrite one another's file.
@visibleForTesting
Future<Directory> resolveGuiCheckpointDirectory({
  Future<File> Function() databaseFileResolver = resolveDefaultDatabaseFile,
}) async {
  final databaseFile = await databaseFileResolver();
  return Directory(
    '${databaseFile.parent.path}${Platform.pathSeparator}checkpoints',
  );
}

/// Carries a checkpoint written by a build that stored it in the application
/// support directory into [targetDir], so upgrading between a crash and the
/// next launch does not silently drop a resumable night.
///
/// Only performed when `NIGHTSHADE_DATABASE_DIR` is unset. In that default
/// layout there is exactly one database on the machine, so the legacy file
/// provably belongs to it — and [SingleInstanceLock] guarantees no other
/// Nightshade is running against it, so nothing can be moved out from under a
/// live process. With the override set, the legacy file may belong to any of
/// several databases; adopting it would re-create the very defect this
/// relocation removes, so it is left alone (and ignored) instead.
///
/// Never throws: a failed adoption must not stop the app from configuring the
/// checkpoint directory it will write tonight's recovery data to.
@visibleForTesting
Future<void> adoptLegacyGuiCheckpoint({
  required Directory targetDir,
  Future<Directory> Function() legacyDirectoryResolver =
      getApplicationSupportDirectory,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final override = env[nightshadeDatabaseDirEnv]?.trim();
  if (override != null && override.isNotEmpty) return;

  try {
    final legacyDir = await legacyDirectoryResolver();
    if (legacyDir.path == targetDir.path) return;

    for (final name in _kCheckpointFileNames) {
      final legacyFile =
          File('${legacyDir.path}${Platform.pathSeparator}$name');
      if (!await legacyFile.exists()) continue;
      final destination =
          File('${targetDir.path}${Platform.pathSeparator}$name');
      // An existing file at the destination is this database's own, newer
      // checkpoint; never let the legacy copy overwrite it.
      if (await destination.exists()) continue;
      await targetDir.create(recursive: true);
      await legacyFile.rename(destination.path);
    }
  } catch (_) {
    // Deliberately swallowed — see doc comment.
  }
}

@visibleForTesting
bool catalogSetupWasSkipped(String? persistedValue) =>
    persistedValue?.trim().toLowerCase() == 'true';

/// The startup "Recover Sequence?" modal.
///
/// Top-level and [visibleForTesting] because its escape hatch is the thing that
/// keeps a failing recovery from wedging the whole app: the modal is
/// deliberately `barrierDismissible: false` (an interrupted run must be decided,
/// not swiped away), so with only Resume and Discard a backend that throws on
/// BOTH — a read-only checkpoint directory, a corrupt file — re-presents the
/// dialog forever with no way out. "Not now" appears only after an attempt has
/// actually failed, leaves the checkpoint on disk, and lets the operator into
/// the app to fix the cause.
@visibleForTesting
Widget buildCheckpointRecoveryDialog({
  required BuildContext context,
  required CheckpointInfo info,
  required CheckpointAttemptFailure? failure,
}) {
  final canRetry = failure == null || failure.checkpointStillResumable;
  final aftermath = canRetry
      ? 'The checkpoint is still on disk. Retry, or discard it to start fresh.'
      : 'This checkpoint can no longer be resumed. Discard it to clear the '
          'prompt.';
  final colors = NightshadeColors.of(context);
  final ageMinutes = info.ageSeconds ~/ 60;
  final ageStr = ageMinutes < 60
      ? '${ageMinutes}m ago'
      : '${ageMinutes ~/ 60}h ${ageMinutes % 60}m ago';
  final integrationMins = (info.completedIntegrationSecs / 60).round();

  return AlertDialog(
    backgroundColor: colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: NightshadeTokens.borderRadiusInline8,
      side: BorderSide(color: colors.border),
    ),
    title: Row(
      children: [
        Icon(
          NightshadeIcons.warning,
          size: 22,
          color: colors.warning,
        ),
        const SizedBox(width: 12),
        Text(
          'Recover Sequence?',
          style: TextStyle(color: colors.textPrimary),
        ),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A previous sequence was interrupted and can be resumed.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: NightshadeTypography.fontSize13,
          ),
        ),
        const SizedBox(height: 16),
        NightshadeCard(
          variant: CardVariant.standard,
          borderRadius: NightshadeTokens.radiusInline8,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _checkpointInfoRow(colors, 'Sequence', info.sequenceName),
              const SizedBox(height: 6),
              _checkpointInfoRow(colors, 'Saved', ageStr),
              const SizedBox(height: 6),
              _checkpointInfoRow(
                colors,
                'Completed',
                '${info.completedExposures} frames '
                    '(${integrationMins}m integration)',
              ),
            ],
          ),
        ),
        if (failure != null) ...[
          const SizedBox(height: 16),
          NightshadeAlert(
            severity: NightshadeAlertSeverity.error,
            title: 'Recovery did not complete',
            message: '${describeCheckpointFailure(failure.error)}\n\n'
                '$aftermath',
          ),
        ],
      ],
    ),
    actions: [
      if (failure != null)
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Not now',
          variant: ButtonVariant.ghost,
        ),
      NightshadeButton(
        onPressed: () => Navigator.of(context).pop(
          AppCheckpointRecoveryChoice.discard,
        ),
        label: 'Discard',
        variant: ButtonVariant.destructive,
      ),
      // Offering "Retry Resume" for a checkpoint the backend has just told us
      // is no longer resumable is the same lie as the old message: the button
      // can only fail again. Discard (and "Not now") remain.
      if (canRetry)
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(
            AppCheckpointRecoveryChoice.resume,
          ),
          label: failure == null ? 'Resume' : 'Retry Resume',
        ),
    ],
  );
}

Widget _checkpointInfoRow(NightshadeColors colors, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 80,
        child: Text(
          label,
          style: NightshadeTypography.labelSm.copyWith(color: colors.textMuted),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
      ),
    ],
  );
}

@visibleForTesting
Future<AppStartupCheckpointOutcome> runAppCheckpointRecovery({
  required Future<AppCheckpointRecoveryChoice?> Function(
    CheckpointAttemptFailure? lastFailure,
  ) choose,
  required Future<void> Function() resume,
  required Future<void> Function() discard,
  required Future<bool> Function() checkpointStillResumable,
}) async {
  CheckpointAttemptFailure? lastFailure;
  while (true) {
    final choice = await choose(lastFailure);
    if (choice == null) return AppStartupCheckpointOutcome.failed;

    try {
      switch (choice) {
        case AppCheckpointRecoveryChoice.resume:
          await resume();
          return AppStartupCheckpointOutcome.resumed;
        case AppCheckpointRecoveryChoice.discard:
          await discard();
          return AppStartupCheckpointOutcome.discarded;
      }
    } catch (error) {
      // Ask the backend what survived the attempt instead of assuming. A
      // resume that failed because the checkpoint is invalid must not be
      // followed by "the checkpoint is still available"; a probe that itself
      // fails is treated as "cannot be resumed", the conservative reading.
      var stillResumable = false;
      try {
        stillResumable = await checkpointStillResumable();
      } catch (_) {
        stillResumable = false;
      }
      lastFailure = CheckpointAttemptFailure(
        error: error,
        checkpointStillResumable: stillResumable,
      );
    }
  }
}

@visibleForTesting
Future<void> runAppStartupChecks({
  required Future<AppStartupCheckpointOutcome> Function() checkCheckpoint,
  required Future<void> Function() checkCatalogs,
}) async {
  final checkpointOutcome = await checkCheckpoint();
  if (checkpointOutcome == AppStartupCheckpointOutcome.noRecovery ||
      checkpointOutcome == AppStartupCheckpointOutcome.discarded) {
    await checkCatalogs();
  }
}

@visibleForTesting
bool appCloseHasActiveOperations({
  required bool sequenceOwnsHardware,
  required bool sessionBusy,
  required bool cameraBusy,
  required bool mountBusy,
  required bool flatWizardBusy,
  required bool autofocusBusy,
}) {
  return sequenceOwnsHardware ||
      sessionBusy ||
      cameraBusy ||
      mountBusy ||
      flatWizardBusy ||
      autofocusBusy;
}

/// An unavailable close preference is not an opt-out. When hardware is active,
/// only a successfully loaded, explicit `false` may bypass confirmation.
@visibleForTesting
bool appCloseShouldConfirm({
  required bool hasActiveOperations,
  required bool? confirmBeforeClosing,
}) {
  return hasActiveOperations && confirmBeforeClosing != false;
}

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _fallbackSideNavExpanded = true;
  bool _hasCheckedCatalogs = false;
  Future<AppStartupCheckpointOutcome>? _checkpointCheck;
  String? _lastImmersiveLocation;
  bool? _lastImmersiveEnabled;

  @override
  void initState() {
    super.initState();
    // Initialize window manager if on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      window_impl.initWindowManager(
        this,
        onCloseRequested: _onCloseRequested,
      );
    }
    // Decide checkpoint recovery before showing any other startup modal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupChecks());
    });
  }

  Future<void> _runStartupChecks() {
    return runAppStartupChecks(
      checkCheckpoint: _checkCheckpointIfNeeded,
      checkCatalogs: _checkCatalogsIfNeeded,
    );
  }

  /// Handle window close request - show confirmation if needed
  Future<bool> _onCloseRequested() async {
    final sessionState = ref.read(sessionStateProvider);
    final sequenceState = ref.read(sequenceExecutionStateProvider);
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);
    final flatWizardState = ref.read(flatWizardProvider);
    final autofocusState = ref.read(autofocusOverlayProvider);
    final hasActiveOperations = appCloseHasActiveOperations(
      sequenceOwnsHardware: sequenceState.ownsHardware,
      sessionBusy: sessionState.isCapturing ||
          sessionState.isAutofocusing ||
          sessionState.isDithering ||
          sessionState.isGuiding,
      cameraBusy: cameraState.isExposing ||
          cameraState.isCooling ||
          cameraState.isWarming ||
          (cameraState.coolerPower ?? 0) > 2,
      mountBusy: mountState.isSlewing || mountState.isTracking,
      flatWizardBusy: flatWizardState.isCapturing,
      autofocusBusy: autofocusState.isRunning,
    );

    final settingsAsync = ref.read(appSettingsProvider);
    final loadedPreference = settingsAsync.hasValue &&
            !settingsAsync.isLoading &&
            !settingsAsync.hasError
        ? settingsAsync.valueOrNull!.confirmBeforeClosing
        : null;
    if (!appCloseShouldConfirm(
      hasActiveOperations: hasActiveOperations,
      confirmBeforeClosing: loadedPreference,
    )) {
      return _flushEditsBeforeClose();
    }

    // Show confirmation dialog
    final shouldClose = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final colors = NightshadeColors.of(context);
        final l10n = context.l10n;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            l10n.text('closeNightshadeTitle'),
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            l10n.text('closeNightshadeBody'),
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: l10n.text('cancel'),
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(true),
              label: l10n.text('closeAnyway'),
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
            ),
          ],
        );
      },
    );

    if (shouldClose != true) return false;
    return _flushEditsBeforeClose();
  }

  Future<bool> _flushEditsBeforeClose() async {
    try {
      await ref.read(backendProvider.notifier).prepareForShutdown();
      return true;
    } catch (error) {
      if (!mounted) return false;
      final colors = NightshadeColors.of(context);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Latest sequence changes were not saved',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Nightshade is staying open so your edits are not lost. '
            'Check the database or remote-host connection, then try closing '
            'again.\n\n$error',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Keep Nightshade open',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    // Dispose window manager if on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      window_impl.disposeWindowManager(this);
    }
    super.dispose();
  }

  Future<void> _checkCatalogsIfNeeded() async {
    if (_hasCheckedCatalogs) return;
    _hasCheckedCatalogs = true;

    try {
      // Onboarding is the single first-run spine. The persistent catalog
      // banner remains available after setup, so do not overlay its route with
      // a separate catalog modal.
      if (await ref.read(shouldRunEquipmentOnboardingProvider.future)) return;

      final settingsDao = ref.read(settingsDaoProvider);
      if (catalogSetupWasSkipped(
        await settingsDao.getSetting(kCatalogSetupSkippedSettingKey),
      )) {
        return;
      }

      final starStatus = await CatalogManager.instance.getStarCatalogStatus();
      final dsoStatus = await CatalogManager.instance.getDsoCatalogStatus();

      // If neither catalog is installed, show setup dialog
      if (!starStatus.isInstalled && !dsoStatus.isInstalled) {
        if (mounted) {
          final result = await ref
              .read(startupSurfaceCoordinatorProvider)
              .run<bool?>(() async {
            if (!mounted) return null;
            return CatalogSetupDialog.show(context);
          });
          if (result == false) {
            await settingsDao.setSetting(
              kCatalogSetupSkippedSettingKey,
              'true',
            );
          }
        }
      }
    } catch (e) {
      ref.read(loggingServiceProvider).warning(
          '[AppShell] Error checking catalog status: $e',
          source: 'AppShell',
          fields: {'error': e.toString()});
    }
  }

  Future<AppStartupCheckpointOutcome> _checkCheckpointIfNeeded() {
    return _checkpointCheck ??= _performCheckpointCheck();
  }

  Future<AppStartupCheckpointOutcome> _performCheckpointCheck() async {
    try {
      final backend = ref.read(sequencerBackendProvider);

      // Initialize the checkpoint directory on desktop so checkpoints are
      // actually persisted this session. The desktop GUI never set it, so no
      // checkpoint was ever written and a mid-night crash was unrecoverable
      // (no resume banner, all sequence state lost). Only when this process IS
      // the backend: a remote host owns its own storage layout, and pushing
      // this machine's support directory at it would point the rig's crash
      // recovery at a path that does not exist there.
      //
      // The directory is derived from the OPEN DATABASE, not from the shared
      // application-support folder — see [resolveGuiCheckpointDirectory] for
      // why that distinction is the difference between "your interrupted run"
      // and someone else's.
      final isLocalBackend = backend is! NetworkBackend;
      if (isLocalBackend &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        try {
          final checkpointDir = await resolveGuiCheckpointDirectory();
          // Configure first, adopt second: nothing reads the directory until
          // hasCheckpoint() below, and a slow or failing adoption must not be
          // able to leave tonight's run with no checkpoint directory at all.
          await backend.sequencerSetCheckpointDir(checkpointDir.path);
          await adoptLegacyGuiCheckpoint(targetDir: checkpointDir);
        } catch (e) {
          ref.read(loggingServiceProvider).warning(
              '[AppShell] Failed to initialize checkpoint directory: $e',
              source: 'AppShell',
              fields: {'error': e.toString()});
        }
      }

      final hasCheckpoint = await backend.hasCheckpoint();
      if (!hasCheckpoint) return AppStartupCheckpointOutcome.noRecovery;

      final info = await backend.getCheckpointInfo();
      if (info == null || !info.canResume) {
        return AppStartupCheckpointOutcome.noRecovery;
      }

      if (!mounted) return AppStartupCheckpointOutcome.failed;

      return ref.read(startupSurfaceCoordinatorProvider).run(
            () => runAppCheckpointRecovery(
              choose: (lastFailure) async {
                if (!mounted) return null;
                return showDialog<AppCheckpointRecoveryChoice>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => buildCheckpointRecoveryDialog(
                    context: dialogContext,
                    info: info,
                    failure: lastFailure,
                  ),
                );
              },
              checkpointStillResumable: () async {
                final current = await backend.getCheckpointInfo();
                return current?.canResume ?? false;
              },
              // Route through the SequenceExecutor provider — it re-seeds the
              // runtime config and starts the restored native tree. The raw backend
              // resume only prepares that tree and would leave execution idle.
              resume: () =>
                  ref.read(sequenceExecutorProvider).resumeFromCheckpoint(),
              discard: backend.discardCheckpoint,
            ),
          );
    } catch (e) {
      ref.read(loggingServiceProvider).error(
          '[AppShell] Error checking checkpoint: $e',
          source: 'AppShell',
          fields: {'error': e.toString()});
      return AppStartupCheckpointOutcome.failed;
    }
  }

  String _getCurrentLocation(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      final matches = router.routerDelegate.currentConfiguration.matches;
      if (matches.isEmpty) {
        return '/dashboard';
      }
      return matches.last.matchedLocation;
    } catch (_) {
      return '/dashboard';
    }
  }

  int _getCurrentIndex(BuildContext context) {
    final location = _getCurrentLocation(context);

    // Update current screen provider for smart notifications
    // Use Future.microtask to avoid modification during build
    final screen = locationToAppScreen(location);
    Future.microtask(() {
      if (mounted) {
        ref.read(currentScreenProvider.notifier).state = screen;
      }
    });

    // -1 = nothing highlighted, and that is the correct answer for every route
    // no rail destination hosts: Settings (+ its plate-solving child), Polar
    // Alignment, Tonight, the Flat Wizard, the mosaic / session-review /
    // stack-result viewers and /diagnostics/dump. Defaulting to 0 lit up
    // Dashboard on all of them, so the rail confidently claimed the operator was
    // on a screen they were not — the strongest signal the shell gives about
    // where you are was simply wrong. Sub-routes still resolve to their host
    // (/imaging/preview/:id lights Imaging), which the old exact-match default
    // also got wrong.
    return ShellNavigation.primaryIndexForLocation(location);
  }

  void _onTabSelected(int index, BuildContext context) {
    final route = ShellNavigation.primaryRouteForIndex(index);
    if (route == null) return;
    try {
      context.go(route);
    } catch (e) {
      // Router might not be available yet, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    // One bool, not the whole settings object: the shell is the root of every
    // routed screen, so watching all of `appSettingsProvider` rebuilt the nav,
    // the status bar, the mini-player and the routed child's element tree on
    // every settings toggle, autosave and remote settings push.
    final sidebarCollapsed = ref.watch(
      appSettingsProvider.select((s) => s.valueOrNull?.sidebarCollapsed),
    );
    final currentLocation = _getCurrentLocation(context);
    final currentIndex = _getCurrentIndex(context);

    // Activate the error notification bridge so backend errors show as toast notifications
    ref.watch(errorNotificationBridgeProvider);
    // Why: keep the meridian-flip disconnect guard alive
    // for the shell's lifetime so a mount disconnect during an in-flight flip
    // resets `flipExecutionStateProvider` to `aborted` and unsticks the UI.
    ref.watch(meridianFlipDisconnectGuardProvider);
    // Why: the standalone meridian monitor must be kept
    // alive while the shell is mounted so the Sequencer Settings ->
    // "Standalone monitoring" toggle actually does something — when enabled,
    // it polls mount HA against the configured trigger and alerts the
    // operator when the meridian is crossed outside of a sequence run.
    ref.watch(meridianFlipStandaloneMonitorProvider);
    // Scheduler lifetime: keep auto-reevaluation listeners mounted
    // with the shell, not only while Plan Tonight -> Target Queue is visible.
    // Otherwise target/goals/constraint edits made elsewhere can stop waking
    // the scheduler once the operator navigates away from that tab.
    ref.watch(schedulerAutoReevalProvider);
    // Collaborative Sky WS3 Gap 3: keep the longitude-baton scheduler mounted for
    // the shell's lifetime so a co-imaging session hands the night east on the
    // rise/set even while the operator is on another tab. Lazy otherwise, so this
    // read is what makes it tick in the GUI (the headless host eager-reads it in
    // main_headless). No-op until a session is joined and a site is configured.
    ref.watch(coImagingBatonSchedulerProvider);
    final isSideNavExpanded =
        sidebarCollapsed != null ? !sidebarCollapsed : _fallbackSideNavExpanded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useBottomNav =
            ShellChrome.useBottomNavigation(constraints.maxWidth);
        // The shell Scaffold owns IME resizing. If its fixed gear strip,
        // status bar, mini-player and bottom navigation remain mounted while a
        // landscape keyboard is open, they can consume the entire shrunken
        // body before the focused route gets any height. Keyboard interaction
        // is already a modal navigation context, so temporarily reclaim that
        // chrome and restore it unchanged when the IME closes.
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

        // Phone "immersive" chrome: the bottom nav + status bar auto-hide when
        // idle so content gets the (very short, on a foldable cover) height,
        // and reappear on any interaction or a swipe up from the grabber.
        // Pinned visible on desktop/tablet (enabled = false → no timer).
        final chromeVisible = ref.watch(immersiveChromeProvider);
        final immersive = ref.read(immersiveChromeProvider.notifier);
        // Only schedule the sync when it has something to do. Both calls below
        // are no-ops when nothing changed, so an unconditional post-frame
        // callback cost one closure allocation per shell rebuild to reach two
        // early returns.
        final routeChanged =
            useBottomNav && currentLocation != _lastImmersiveLocation;
        if (_lastImmersiveEnabled != useBottomNav || routeChanged) {
          _lastImmersiveEnabled = useBottomNav;
          if (routeChanged) _lastImmersiveLocation = currentLocation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            immersive.enabled = useBottomNav;
            // Reveal the chrome (and re-arm the one-shot idle auto-hide)
            // whenever the operator navigates to a different screen.
            if (routeChanged) immersive.onRouteChanged();
          });
        }

        // The first-launch tour is replay-only (C13): OnboardingTourReplayLauncher
        // watches firstLaunchTourStatusProvider and overlays OnboardingOverlay on
        // top of the whole shell when the user re-runs it from Settings → Help.
        // Mounted at the shell level so the spotlight cutouts can target the
        // live side-navigation TutorialKeys.
        //
        // The progressive first-launch "coach" popup was removed (it was an
        // intrusive readiness nudge whose info is reachable from the Equipment
        // "Ready to image" panel).
        final Widget shell = OnboardingTourReplayLauncher(
          child: TutorialOverlay(
            child: Scaffold(
              backgroundColor: colors.background,
              body: Column(
                children: [
                  // Desktop title bar (window drag + global actions). Hidden on
                  // mobile — bottom nav covers primary routes; saves vertical space.
                  if (!useBottomNav) const TitleBar(),

                  // Mobile gear strip. Settings left the bottom bar in the
                  // six-tab consolidation, so this thin app-bar action keeps it
                  // one tap away on phones.
                  if (useBottomNav && !keyboardVisible)
                    SafeArea(
                      bottom: false,
                      child: _MobileSettingsBar(
                        onOpenSettings: () => context.go('/settings'),
                      ),
                    ),

                  // Desktop keeps the full recovery banner; mobile uses the
                  // compact status-bar connection indicator.
                  if (!useBottomNav) const DisconnectedBackendBanner(),

                  // iOS background-monitoring advisory (audit §3.2). Renders
                  // above the weather banner so it's the first thing the
                  // operator sees while a sequence is running on iOS.
                  const IosBackgroundBanner(),

                  // Android POST_NOTIFICATIONS advisory. Visible
                  // whenever the runtime permission is denied on Android 13+
                  // so the operator knows sequence/safety alerts will not
                  // wake them and points to System Settings.
                  const AndroidNotificationsBanner(),

                  // Stale-connection advisory (audit §3.6). Visible during
                  // the WS reconnect grace window so the operator knows
                  // controls may be momentarily out of date.
                  const ConnectionStaleBanner(),

                  // Weather Alert Banner
                  const WeatherAlertBanner(),

                  // Main content
                  Expanded(
                    child: Row(
                      children: [
                        // Side navigation (Desktop only)
                        if (!useBottomNav)
                          SideNavigation(
                            key: TutorialKeys.sideNavigation,
                            tutorialKeys: [
                              TutorialKeys.navDashboard,
                              TutorialKeys.navEquipment,
                              TutorialKeys.navImaging,
                              TutorialKeys.navSequencer,
                              TutorialKeys.navGuiding,
                              null,
                              TutorialKeys.navPlanner,
                              TutorialKeys.navAnalytics,
                            ],
                            currentIndex: currentIndex,
                            onTabSelected: (index) =>
                                _onTabSelected(index, context),
                            isExpanded: isSideNavExpanded,
                            onToggleExpanded: () {
                              final currentSettings =
                                  ref.read(appSettingsProvider).valueOrNull;
                              if (currentSettings != null) {
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setSidebarCollapsed(
                                        !currentSettings.sidebarCollapsed);
                              } else {
                                setState(() {
                                  _fallbackSideNavExpanded =
                                      !_fallbackSideNavExpanded;
                                });
                              }
                            },
                          ),

                        // Main content area
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.background,
                              border: Border(
                                left: useBottomNav
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: colors.border,
                                        width: 1,
                                      ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // Both chromes own the top inset above this
                                // content: desktop via the TitleBar, mobile via
                                // the gear strip, so the content never re-insets
                                // the notch/status-bar edge itself.
                                SafeArea(
                                  top: false,
                                  bottom: false,
                                  child: widget.child,
                                ),
                                // Mobile sequence overlay (only on mobile and
                                // sequencer screen). §14: gated on the shared
                                // route constant instead of a literal string so
                                // the router and this check stay in sync. The
                                // app-wide running-sequence mini-player (run
                                // controls reachable off the sequencer route)
                                // lives in the bottom chrome below as
                                // [RunningSequenceMiniBar].
                                if (useBottomNav &&
                                    currentLocation.split('?').first ==
                                        kSequencerRoutePath)
                                  const MobileSequenceOverlay(),
                                // Autofocus progress overlay
                                const AutofocusProgressOverlay(),
                                // Toast notifications - always on top
                                const NotificationToastOverlay(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // App-wide running-sequence mini-player. Persistent across
                  // every route so pause/stop/skip stay reachable after the
                  // operator navigates away from the sequencer mid-run; it
                  // self-hides on the sequencer route (full controls live there)
                  // and whenever no sequence is active. Sits just above the
                  // bottom chrome so it reads as part of the persistent
                  // run-control surface.
                  if (!keyboardVisible)
                    RunningSequenceMiniBar(currentLocation: currentLocation),

                  // Bottom chrome. On phone the status bar + bottom nav live in
                  // one auto-hiding block (immersive) so they reclaim the short
                  // cover-screen height when idle; on desktop the status bar is
                  // pinned and navigation is the side rail (no bottom nav).
                  if (useBottomNav && !keyboardVisible)
                    ImmersiveBottomChrome(
                      visible: chromeVisible,
                      onToggle: immersive.toggle,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StatusBar(compact: true),
                          NightshadeBottomNavigation(
                            currentRoute: currentLocation,
                            onRouteSelected: (route) {
                              try {
                                context.go(route);
                              } catch (_) {
                                // Router might not be available yet, ignore.
                              }
                            },
                          ),
                        ],
                      ),
                    )
                  else if (!useBottomNav)
                    const StatusBar(compact: false),
                ],
              ),
            ),
          ),
        );

        if (!useBottomNav) return shell;
        // Dynamic UI shrink for phones: scale text down as the screen's short
        // side falls below a ~440px reference so dense cover screens (e.g. a
        // foldable ~369px) fit more without manual zoom. Multiplies (respects)
        // the user's own accessibility text scaling. Tablets (short side >=
        // 440) and desktop are unscaled.
        final mq = MediaQuery.of(context);
        final uiScale = (mq.size.shortestSide / 440.0).clamp(0.82, 1.0);
        // System-back policy (phone): primary tabs are go()-navigated, so the
        // router usually has nothing to pop and a bare back gesture would
        // finish the Activity from ANY screen. Order: a screen-registered
        // interceptor (e.g. Settings' detail pane) → pop a pushed route
        // (Flat Wizard, mosaic detail…) → return to Dashboard (Material
        // back-to-home convention) → only from Dashboard leave the app.
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (ShellBackDispatcher.dispatch()) return;
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
              return;
            }
            if (!_getCurrentLocation(context).startsWith('/dashboard')) {
              context.go('/dashboard');
              return;
            }
            SystemNavigator.pop();
          },
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * uiScale),
            ),
            child: shell,
          ),
        );
      },
    );
  }
}

class _MobileSettingsBar extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _MobileSettingsBar({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    // A narrow DESKTOP window still has no OS decorations (the runners set
    // TitleBarStyle.hidden), so this bar owns minimize/maximize/close and the
    // drag-to-move region below the side-nav breakpoint exactly as the full
    // TitleBar does above it. Without them, resizing under 768px left the
    // window with no mouse-reachable way to be closed, minimized or moved.
    final isDesktopWindow = ShellChrome.isDesktopWindow;

    final bar = Container(
      height: ShellChromeMetrics.titleBarHeight,
      color: colors.surface,
      // Caption buttons are flush to the window edge (platform convention and
      // Fitts' law), so the trailing inset is dropped when they are present.
      padding: EdgeInsets.only(
        left: NightshadeTokens.spaceLg,
        right: isDesktopWindow ? 0 : NightshadeTokens.spaceLg,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: NightshadeTokens.borderRadiusMd,
            ),
            child: Icon(NightshadeIcons.sparkle, size: 14, color: onPrimary),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm + 2),
          // The wordmark yields before the caption buttons do: on a very
          // narrow window the title may ellipsize, but close must not vanish.
          Flexible(
            child: Text(
              'NIGHTSHADE',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            key: TutorialKeys.navSettings,
            onTap: onOpenSettings,
            borderRadius: NightshadeTokens.borderRadiusInline4,
            child: Padding(
              padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
              child: Icon(
                NightshadeIcons.settings,
                size: NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (isDesktopWindow) ...[
            const SizedBox(width: NightshadeTokens.spaceSm),
            WindowControls(colors: colors),
          ],
        ],
      ),
    );

    if (!isDesktopWindow) return bar;
    return WindowDragArea(child: bar);
  }
}
