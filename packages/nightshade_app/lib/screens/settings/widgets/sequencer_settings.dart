import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/help/field_help_copy.dart';
import 'settings_widgets.dart';

class SequencerSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const SequencerSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<SequencerSettings> createState() => _SequencerSettingsState();
}

class _SequencerSettingsState extends ConsumerState<SequencerSettings> {
  // Live Stacking & Broadcast settings controllers. The
  // watermark template is kept as a TextEditingController so the
  // VariablePicker can splice values into the caret position; the port
  // input shares the same SettingsNumberInput pattern used by the rest of
  // the page.
  final _broadcastPortController = TextEditingController();
  final _broadcastWatermarkController = TextEditingController();
  bool _broadcastInitialized = false;

  // Sequencer settings controllers
  final _autoFocusController = TextEditingController();
  // Frames-based cadence for the standard AutofocusInterval
  // trigger. Distinct from `_autoFocusController` (which is in minutes for the
  // app-level AppSettings UX) — this one targets the Rust trigger directly.
  final _autoFocusIntervalFramesController = TextEditingController();
  final _ditherController = TextEditingController();

  // Meridian flip settings controllers
  final _minutesPastMeridianController = TextEditingController();
  final _minutesBeforeLimitController = TextEditingController();
  final _hourAngleThresholdController = TextEditingController();
  final _trackingLimitWaitController = TextEditingController();
  final _settleTimeController = TextEditingController();
  final _maxRetriesController = TextEditingController();

  bool _initialized = false;
  bool _meridianInitialized = false;

  @override
  void dispose() {
    _autoFocusController.dispose();
    _autoFocusIntervalFramesController.dispose();
    _ditherController.dispose();
    _minutesPastMeridianController.dispose();
    _minutesBeforeLimitController.dispose();
    _hourAngleThresholdController.dispose();
    _trackingLimitWaitController.dispose();
    _settleTimeController.dispose();
    _maxRetriesController.dispose();
    _broadcastPortController.dispose();
    _broadcastWatermarkController.dispose();
    super.dispose();
  }

  void _initBroadcastControllers(SequencerDefaults defaults) {
    if (_broadcastInitialized) return;
    _broadcastPortController.text = defaults.livestackingDefaultPort.toString();
    _broadcastWatermarkController.text =
        defaults.livestackingDefaultWatermark ?? '';
    _broadcastInitialized = true;
  }

  Widget _buildBroadcastSection(SequencerDefaults defaults) {
    final notifier = ref.read(sequencerDefaultsProvider.notifier);
    return SettingsSection(
      title: 'Live Stacking & Broadcast',
      children: [
        SettingRow(
          icon: LucideIcons.shieldOff,
          title: 'Disable broadcast everywhere',
          subtitle: 'Master kill switch — every LiveStacking node will '
              'build the stack in memory but refuse public requests. '
              'Useful when you want to test without exposing imagery.',
          trailing: SettingsSwitch(
            value: defaults.livestackingDisableEverywhere,
            onChanged: (value) {
              notifier.updateLiveStackingDefaults(disableEverywhere: value);
            },
          ),
        ),
        SettingRow(
          icon: LucideIcons.network,
          title: 'Default broadcast port',
          subtitle: 'Port used by newly-created LiveStacking nodes. '
              'Must not clash with the headless API server.',
          trailing: SettingsNumberInput(
            controller: _broadcastPortController,
            suffix: '',
            min: 1,
            max: 65535,
            decimals: 0,
            onChanged: (value) {
              notifier.updateLiveStackingDefaults(
                defaultPort: value.toInt(),
              );
            },
          ),
        ),
        SettingRow(
          icon: LucideIcons.layers,
          title: 'Default stack method',
          subtitle: 'Average is fastest; Median + Rejection and Sigma '
              'reject outliers but are slower.',
          trailing: settingsTrailingDropdown(
            context: context,
            value: defaults.livestackingDefaultStackMethod.label,
            items: LiveStackingMethod.values.map((m) => m.label).toList(),
            designWidth: 200,
            isMobile: widget.isMobile,
            onChanged: (value) {
              if (value == null) return;
              final method = LiveStackingMethod.values.firstWhere(
                (m) => m.label == value,
                orElse: () => LiveStackingMethod.average,
              );
              notifier.updateLiveStackingDefaults(defaultStackMethod: method);
            },
          ),
        ),
        SettingRow(
          icon: LucideIcons.type,
          title: 'Default watermark template',
          subtitle: 'Rendered on the broadcast JPEG. Variable interpolation '
              r'(e.g. "${target.name} — L ${integration.hms}") applied at '
              'render time. Leave empty for no watermark.',
          trailing: settingsTrailingTextInput(
            context: context,
            controller: _broadcastWatermarkController,
            hint: 'e.g. M42 — \${integration.hms}',
            designWidth: 240,
            isMobile: widget.isMobile,
            onChanged: (value) {
              // Persist empty string as cleared (null in memory). The
              // notifier's _sentinel pattern preserves the distinction
              // so reload sees an empty default rather than the
              // hard-coded fallback.
              notifier.updateLiveStackingDefaults(
                defaultWatermark: value.isEmpty ? null : value,
              );
            },
          ),
        ),
        SettingRow(
          icon: LucideIcons.globe2,
          title: 'Public by default',
          subtitle: 'Off → new nodes start with auth required. Turn on '
              'only if you routinely run public outreach events.',
          trailing: SettingsSwitch(
            value: defaults.livestackingPublicByDefault,
            onChanged: (value) {
              notifier.updateLiveStackingDefaults(publicByDefault: value);
            },
          ),
        ),
        SettingRow(
          icon: LucideIcons.image,
          title: 'Default thumbnail size',
          subtitle: 'Output dimensions for the broadcast JPEG. Smaller '
              'is phone-friendly; larger preserves more detail.',
          trailing: settingsTrailingDropdown(
            context: context,
            value: defaults.livestackingDefaultThumbnailSize.label,
            items:
                LiveStackingThumbnailSize.values.map((s) => s.label).toList(),
            designWidth: 220,
            isMobile: widget.isMobile,
            onChanged: (value) {
              if (value == null) return;
              final picked = LiveStackingThumbnailSize.values.firstWhere(
                (s) => s.label == value,
                orElse: () => LiveStackingThumbnailSize.medium,
              );
              notifier.updateLiveStackingDefaults(
                defaultThumbnailSize: picked,
              );
            },
          ),
          isLast: true,
        ),
      ],
    );
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _autoFocusController.text = settings.autoFocusEveryMinutes.toString();
      _ditherController.text = settings.ditherEveryFrames.toString();
      // Seed from sequencer defaults provider so the user
      // sees the same value the executor uses on next start().
      final seqDefaults = ref.read(sequencerDefaultsProvider);
      _autoFocusIntervalFramesController.text =
          seqDefaults.autofocusIntervalFrames.toString();
      _initialized = true;
    }
  }

  void _initMeridianControllers(MeridianFlipSettings settings) {
    if (!_meridianInitialized) {
      _minutesPastMeridianController.text =
          settings.minutesPastMeridian.toString();
      _minutesBeforeLimitController.text =
          settings.minutesBeforeLimit.toString();
      _hourAngleThresholdController.text =
          settings.hourAngleThreshold.toString();
      _trackingLimitWaitController.text =
          settings.trackingLimitWaitMinutes.toString();
      _settleTimeController.text = settings.settleTimeSeconds.toString();
      _maxRetriesController.text = settings.maxRetries.toString();
      _meridianInitialized = true;
    }
  }

  String _getFailModeDescription(SafetyFailMode mode) {
    return switch (mode) {
      SafetyFailMode.failClosed =>
        'Treat unavailable safety data as unsafe and park/pause equipment',
      SafetyFailMode.failOpen =>
        'Treat unavailable safety data as safe and continue operations',
      SafetyFailMode.warnOnly =>
        'Continue operations and show a warning when safety data is unavailable',
    };
  }

  String _failModeToString(SafetyFailMode mode) {
    return switch (mode) {
      SafetyFailMode.failClosed => 'Fail Closed (Park)',
      SafetyFailMode.failOpen => 'Fail Open (Continue)',
      SafetyFailMode.warnOnly => 'Warn Only',
    };
  }

  SafetyFailMode _stringToFailMode(String value) {
    return switch (value) {
      'Fail Open (Continue)' => SafetyFailMode.failOpen,
      'Warn Only' => SafetyFailMode.warnOnly,
      _ => SafetyFailMode.failClosed,
    };
  }

  Widget _buildMeridianFlipSection(MeridianFlipSettings flipSettings) {
    final notifier = ref.read(globalMeridianFlipSettingsProvider.notifier);

    return SettingsSection(
      title: 'Meridian Flip',
      children: [
        // Standalone monitoring
        SettingRow(
          icon: LucideIcons.eye,
          title: 'Standalone monitoring',
          subtitle: 'Monitor meridian even when no sequence is running',
          trailing: SettingsSwitch(
            value: flipSettings.standaloneMonitoringEnabled,
            onChanged: (value) {
              notifier.setStandaloneMonitoringEnabled(value);
            },
          ),
        ),
        // Trigger method
        SettingRow(
          icon: LucideIcons.crosshair,
          title: 'Trigger method',
          subtitle: flipSettings.triggerMethod.description,
          trailing: settingsTrailingDropdown(
            context: context,
            value: flipSettings.triggerMethod.displayName,
            items:
                MeridianTriggerMethod.values.map((e) => e.displayName).toList(),
            designWidth: 200,
            isMobile: widget.isMobile,
            onChanged: (value) {
              if (value != null) {
                final method = MeridianTriggerMethod.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setTriggerMethod(method);
              }
            },
          ),
        ),
        // Trigger value - minutes past meridian
        if (flipSettings.triggerMethod ==
            MeridianTriggerMethod.minutesPastMeridian)
          SettingRow(
            icon: LucideIcons.timer,
            title: 'Minutes past meridian',
            helpId: FieldHelpId.meridianFlipTrigger,
            subtitle: 'Flip after target crosses meridian by this amount',
            trailing: SettingsNumberInput(
              controller: _minutesPastMeridianController,
              suffix: 'min',
              min: 0,
              max: 120,
              decimals: 1,
              onChanged: (value) {
                notifier.setMinutesPastMeridian(value);
              },
            ),
          ),
        // Trigger value - minutes before limit
        if (flipSettings.triggerMethod ==
            MeridianTriggerMethod.minutesBeforeLimit)
          SettingRow(
            icon: LucideIcons.timer,
            title: 'Minutes before limit',
            subtitle: 'Flip before mount reaches tracking limit',
            trailing: SettingsNumberInput(
              controller: _minutesBeforeLimitController,
              suffix: 'min',
              min: 0,
              max: 120,
              decimals: 1,
              onChanged: (value) {
                notifier.setMinutesBeforeLimit(value);
              },
            ),
          ),
        // Trigger value - hour angle threshold
        if (flipSettings.triggerMethod ==
            MeridianTriggerMethod.hourAngleThreshold)
          SettingRow(
            icon: LucideIcons.timer,
            title: 'Hour angle threshold',
            subtitle: 'Flip when hour angle exceeds this value',
            trailing: SettingsNumberInput(
              controller: _hourAngleThresholdController,
              suffix: 'h',
              min: 0,
              max: 6,
              decimals: 2,
              onChanged: (value) {
                notifier.setHourAngleThreshold(value);
              },
            ),
          ),
        // Trigger value - tracking limit wait time
        if (flipSettings.triggerMethod ==
            MeridianTriggerMethod.onTrackingLimitHit)
          SettingRow(
            icon: LucideIcons.timer,
            title: 'Wait before flip',
            subtitle:
                'Delay after tracking limit detected (0 = flip immediately)',
            trailing: SettingsNumberInput(
              controller: _trackingLimitWaitController,
              suffix: 'min',
              min: 0,
              max: 60,
              decimals: 1,
              onChanged: (value) {
                notifier.setTrackingLimitWaitMinutes(value);
              },
            ),
          ),
        // Flip sequence - pause guiding
        SettingRow(
          icon: LucideIcons.pause,
          title: 'Pause guiding before flip',
          subtitle: 'Temporarily stop autoguider during flip',
          trailing: SettingsSwitch(
            value: flipSettings.pauseGuidingBeforeFlip,
            onChanged: (value) {
              notifier.setPauseGuidingBeforeFlip(value);
            },
          ),
        ),
        // Flip sequence - recenter
        SettingRow(
          icon: LucideIcons.crosshair,
          title: 'Recenter after flip',
          subtitle: 'Plate solve and re-center target after flip',
          trailing: SettingsSwitch(
            value: flipSettings.recenterAfterFlip,
            onChanged: (value) {
              notifier.setRecenterAfterFlip(value);
            },
          ),
        ),
        // Flip sequence - refocus
        SettingRow(
          icon: LucideIcons.focus,
          title: 'Refocus after flip',
          subtitle: 'Run autofocus after flip completes',
          trailing: SettingsSwitch(
            value: flipSettings.refocusAfterFlip,
            onChanged: (value) {
              notifier.setRefocusAfterFlip(value);
            },
          ),
        ),
        // Flip sequence - resume guiding
        SettingRow(
          icon: LucideIcons.play,
          title: 'Resume guiding after flip',
          subtitle: 'Restart autoguider if it was running',
          trailing: SettingsSwitch(
            value: flipSettings.resumeGuidingAfterFlip,
            onChanged: (value) {
              notifier.setResumeGuidingAfterFlip(value);
            },
          ),
        ),
        // Settle time
        SettingRow(
          icon: LucideIcons.clock,
          title: 'Settle time',
          subtitle: 'Wait time after flip before resuming',
          trailing: SettingsNumberInput(
            controller: _settleTimeController,
            suffix: 'sec',
            min: 0,
            max: 300,
            decimals: 0,
            onChanged: (value) {
              notifier.setSettleTimeSeconds(value);
            },
          ),
        ),
        // Error handling - max retries
        SettingRow(
          icon: LucideIcons.repeat,
          title: 'Max retries',
          subtitle: 'Number of retry attempts if flip fails',
          trailing: SettingsNumberInput(
            controller: _maxRetriesController,
            suffix: '',
            min: 0,
            max: 10,
            decimals: 0,
            onChanged: (value) {
              notifier.setMaxRetries(value.toInt());
            },
          ),
        ),
        // Error handling - failure action
        SettingRow(
          icon: LucideIcons.alertTriangle,
          title: 'On failure',
          subtitle: flipSettings.failureAction.description,
          trailing: settingsTrailingDropdown(
            context: context,
            value: flipSettings.failureAction.displayName,
            items: FlipFailureAction.values.map((e) => e.displayName).toList(),
            designWidth: 160,
            isMobile: widget.isMobile,
            onChanged: (value) {
              if (value != null) {
                final action = FlipFailureAction.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setFailureAction(action);
              }
            },
          ),
        ),
        // Notifications - sound
        SettingRow(
          icon: LucideIcons.volume2,
          title: 'Sound alert',
          subtitle: 'Play sound when flip starts/completes/fails',
          trailing: SettingsSwitch(
            value: flipSettings.soundAlertOnFlip,
            onChanged: (value) {
              notifier.setSoundAlertOnFlip(value);
            },
          ),
        ),
        // Notifications - push
        SettingRow(
          icon: LucideIcons.bell,
          title: 'Push notification',
          subtitle: 'Send notification to mobile app',
          trailing: SettingsSwitch(
            value: flipSettings.pushNotificationOnFlip,
            onChanged: (value) {
              notifier.setPushNotificationOnFlip(value);
            },
          ),
          isLast: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final flipSettings = ref.watch(globalMeridianFlipSettingsProvider);
    _initMeridianControllers(flipSettings);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _initControllers(settings);
        // Seed the broadcast-section controllers on the
        // first build that has both Settings + SequencerDefaults loaded.
        final seqDefaults = ref.watch(sequencerDefaultsProvider);
        _initBroadcastControllers(seqDefaults);

        return SettingsPage(
          title: 'Sequencer',
          description: 'Automation and sequence settings',
          children: [
            SettingsSection(
              title: 'Safety',
              children: [
                SettingRow(
                  icon: LucideIcons.shieldAlert,
                  title: 'Park on unsafe weather',
                  subtitle:
                      'Automatically park mount when weather becomes unsafe',
                  trailing: SettingsSwitch(
                    value: settings.parkOnUnsafeWeather,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setParkOnUnsafeWeather(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.sunrise,
                  title: 'Park before dawn',
                  subtitle: 'Automatically park mount before astronomical dawn',
                  trailing: SettingsSwitch(
                    value: settings.parkBeforeDawn,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setParkBeforeDawn(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: 'Safety fail mode',
                  subtitle: _getFailModeDescription(settings.safetyFailMode),
                  trailing: settingsTrailingDropdown(
                    context: context,
                    value: _failModeToString(settings.safetyFailMode),
                    items: const [
                      'Fail Closed (Park)',
                      'Fail Open (Continue)',
                      'Warn Only',
                    ],
                    designWidth: 180,
                    isMobile: widget.isMobile,
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setSafetyFailMode(_stringToFailMode(value));
                      }
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            _buildMeridianFlipSection(flipSettings),
            SettingsSection(
              title: 'Auto Focus',
              children: [
                SettingRow(
                  icon: LucideIcons.focus,
                  title: 'Auto focus on filter change',
                  subtitle: 'Run auto focus when switching filters',
                  trailing: SettingsSwitch(
                    value: settings.autoFocusOnFilterChange,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setAutoFocusOnFilterChange(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.timer,
                  title: 'Auto focus interval',
                  subtitle: 'Run auto focus periodically',
                  trailing: SettingsNumberInput(
                    controller: _autoFocusController,
                    suffix: 'min',
                    min: 0,
                    max: 240,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setAutoFocusEveryMinutes(value.toInt());
                    },
                  ),
                ),
                // Frames-based AutofocusInterval cadence.
                // The Rust standard trigger ships with `every_n_frames = 25`
                // which is wildly wrong for both 5-second and 5-minute subs;
                // exposing this number directly lets the user tune the
                // cadence to their actual sub-exposure length. Pushed to the
                // executor immediately so a mid-sequence change takes effect.
                SettingRow(
                  icon: LucideIcons.repeat,
                  title: 'Auto focus every N frames',
                  subtitle:
                      'Run autofocus every N completed exposures (frames-based)',
                  trailing: SettingsNumberInput(
                    controller: _autoFocusIntervalFramesController,
                    suffix: 'frames',
                    min: 1,
                    max: 9999,
                    decimals: 0,
                    onChanged: (value) async {
                      final frames = value.toInt();
                      // Persist via SequencerDefaults so the value survives
                      // restart and is consulted by the executor on start().
                      await ref
                          .read(sequencerDefaultsProvider.notifier)
                          .updateAutofocusDefaults(intervalFrames: frames);
                      // Push to the live executor so an in-flight sequence
                      // honours the new cadence without a reload. The bridge
                      // function rejects 0, which we already clamp at 1.
                      try {
                        final backend = ref.read(sequencerBackendProvider);
                        await backend.sequencerUpdateAutofocusInterval(frames);
                      } catch (e) {
                        // Surfacing the error via a snackbar would be noisy;
                        // the executor will pick up the persisted value on
                        // its next start() regardless.
                        debugPrint(
                            'Failed to push autofocus interval to executor: $e');
                      }
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Dithering',
              children: [
                SettingRow(
                  icon: LucideIcons.move,
                  title: 'Enable dithering',
                  subtitle: 'Move mount slightly between exposures',
                  trailing: SettingsSwitch(
                    value: settings.ditherEnabled,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setDitherEnabled(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.hash,
                  title: 'Dither every',
                  subtitle: 'Number of frames between dithers',
                  trailing: SettingsNumberInput(
                    controller: _ditherController,
                    suffix: 'frames',
                    min: 1,
                    max: 20,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setDitherEveryFrames(value.toInt());
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            // Live Stacking & Broadcast defaults. New
            // LiveStackingNodes inherit these knobs (port, stack method,
            // watermark template, thumbnail size, public-by-default,
            // master kill switch). Sits between Dithering and Notes
            // because it logically follows the per-frame capture
            // pipeline knobs above and precedes the post-run journaling
            // surface below.
            _buildBroadcastSection(seqDefaults),
            // Notes prompt opt-out lives here under
            // Sequencer because the prompt fires at sequence-run end.
            // Placed before Development so the user always sees the
            // toggle (Development section is hidden in release builds).
            SettingsSection(
              title: 'Notes & Journal',
              children: [
                SettingRow(
                  icon: LucideIcons.bookOpen,
                  title: 'Prompt for notes after run',
                  subtitle: 'Show a quick journal-entry dialog when a sequence '
                      'finishes so you can capture seeing, dew, anomalies.',
                  trailing: SettingsSwitch(
                    value: settings.promptForNotesAfterRun,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPromptForNotesAfterRun(value);
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            // Smart Night defaults live here too because
            // they all govern sequence-builder behaviour. The wizard
            // mutates these values as the user adjusts knobs, and reads
            // them back on next launch so preferences persist across
            // restarts.
            SettingsSection(
              title: 'Smart Night Defaults',
              children: [
                SettingRow(
                  icon: LucideIcons.bell,
                  title: 'Dashboard auto-prompt',
                  subtitle: 'Show the Smart Night prompt on the dashboard '
                      'when your equipment is ready.',
                  trailing: SettingsSwitch(
                    value: settings.smartNightAutoPromptEnabled,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightAutoPromptEnabled(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.focus,
                  title: 'Autofocus cadence (frames)',
                  subtitle: 'How many exposures between autofocus runs '
                      'when the wizard picks frame-based cadence.',
                  trailing: SettingsNumberInput(
                    controller: TextEditingController(
                        text: settings.smartNightDefaultAfCadenceFrames
                            .toString()),
                    suffix: 'frames',
                    min: 1,
                    max: 9999,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightDefaultAfCadenceFrames(value.toInt());
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.clock,
                  title: 'Integration budget per target',
                  subtitle:
                      'Default per-target imaging budget the wizard uses.',
                  trailing: SettingsNumberInput(
                    controller: TextEditingController(
                        text: settings
                            .smartNightDefaultIntegrationBudgetMinsPerTarget
                            .toString()),
                    suffix: 'min',
                    min: 1,
                    max: 24 * 60,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightDefaultIntegrationBudgetMinsPerTarget(
                              value.toInt());
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.lamp,
                  title: 'Include flats at end',
                  subtitle: 'Append per-filter flats when the active '
                      'profile has a cover calibrator.',
                  trailing: SettingsSwitch(
                    value: settings.smartNightIncludeFlatsAtEnd,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightIncludeFlatsAtEnd(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.listOrdered,
                  title: 'Scheduler for multi-target nights',
                  subtitle: 'Wrap multi-target plans in a TargetScheduler so '
                      'the executor can swap between them by altitude.',
                  trailing: SettingsSwitch(
                    value: settings.smartNightUseSchedulerForMultiTarget,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightUseSchedulerForMultiTarget(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.hash,
                  title: 'Scheduler threshold (targets)',
                  subtitle: 'Use the scheduler when target count reaches this '
                      'number; otherwise chain them linearly.',
                  trailing: SettingsNumberInput(
                    controller: TextEditingController(
                        text: settings.smartNightSchedulerTargetThreshold
                            .toString()),
                    suffix: '',
                    min: 2,
                    max: 20,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightSchedulerTargetThreshold(value.toInt());
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.compass,
                  title: 'Polar alignment stale after',
                  subtitle: 'If the last polar alignment is older than '
                      'this, the wizard prepends a fresh alignment node.',
                  trailing: SettingsNumberInput(
                    controller: TextEditingController(
                        text: settings.smartNightPolarAlignmentStaleAfterDays
                            .toString()),
                    suffix: 'days',
                    min: 1,
                    max: 365,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSmartNightPolarAlignmentStaleAfterDays(
                              value.toInt());
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            if (!kReleaseMode)
              SettingsSection(
                title: 'Development',
                children: [
                  SettingRow(
                    icon: LucideIcons.testTube,
                    title: 'Simulation mode',
                    subtitle: 'Use simulated devices instead of real hardware',
                    trailing: SettingsSwitch(
                      value: settings.useSimulationMode,
                      onChanged: (value) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setUseSimulationMode(value);
                      },
                    ),
                    isLast: true,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
