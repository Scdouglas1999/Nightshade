import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class SequencerSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const SequencerSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  ConsumerState<SequencerSettings> createState() => _SequencerSettingsState();
}

class _SequencerSettingsState extends ConsumerState<SequencerSettings> {
  // Sequencer settings controllers
  final _autoFocusController = TextEditingController();
  // Wave 1.5 Pack A: frames-based cadence for the standard AutofocusInterval
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
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _autoFocusController.text = settings.autoFocusEveryMinutes.toString();
      _ditherController.text = settings.ditherEveryFrames.toString();
      // Wave 1.5 Pack A: seed from sequencer defaults provider so the user
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
      colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Trigger method
        SettingRow(
          icon: LucideIcons.crosshair,
          title: 'Trigger method',
          subtitle: flipSettings.triggerMethod.description,
          trailing: SettingsDropdown(
            value: flipSettings.triggerMethod.displayName,
            items:
                MeridianTriggerMethod.values.map((e) => e.displayName).toList(),
            onChanged: (value) {
              if (value != null) {
                final method = MeridianTriggerMethod.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setTriggerMethod(method);
              }
            },
            colors: widget.colors,
            width: 200,
          ),
          colors: widget.colors,
        ),
        // Trigger value - minutes past meridian
        if (flipSettings.triggerMethod ==
            MeridianTriggerMethod.minutesPastMeridian)
          SettingRow(
            icon: LucideIcons.timer,
            title: 'Minutes past meridian',
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
              colors: widget.colors,
            ),
            colors: widget.colors,
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
              colors: widget.colors,
            ),
            colors: widget.colors,
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
              colors: widget.colors,
            ),
            colors: widget.colors,
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
              colors: widget.colors,
            ),
            colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Error handling - failure action
        SettingRow(
          icon: LucideIcons.alertTriangle,
          title: 'On failure',
          subtitle: flipSettings.failureAction.description,
          trailing: SettingsDropdown(
            value: flipSettings.failureAction.displayName,
            items: FlipFailureAction.values.map((e) => e.displayName).toList(),
            onChanged: (value) {
              if (value != null) {
                final action = FlipFailureAction.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setFailureAction(action);
              }
            },
            colors: widget.colors,
            width: 160,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          colors: widget.colors,
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
            colors: widget.colors,
          ),
          isLast: true,
          colors: widget.colors,
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
        colors: widget.colors,
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _initControllers(settings);

        return SettingsPage(
          title: 'Sequencer',
          description: 'Automation and sequence settings',
          colors: widget.colors,
          children: [
            SettingsSection(
              title: 'Safety',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                SettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: 'Safety fail mode',
                  subtitle: _getFailModeDescription(settings.safetyFailMode),
                  trailing: SettingsDropdown(
                    value: _failModeToString(settings.safetyFailMode),
                    items: const [
                      'Fail Closed (Park)',
                      'Fail Open (Continue)',
                      'Warn Only',
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setSafetyFailMode(_stringToFailMode(value));
                      }
                    },
                    colors: widget.colors,
                    width: 180,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _buildMeridianFlipSection(flipSettings),
            SettingsSection(
              title: 'Auto Focus',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Dithering',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Development',
              colors: widget.colors,
              children: [
                SettingRow(
                  icon: LucideIcons.cpu,
                  title: 'Use native execution',
                  subtitle: 'Execute sequences using native Rust engine',
                  trailing: SettingsSwitch(
                    value: settings.useNativeExecution,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setUseNativeExecution(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: kReleaseMode,
                  colors: widget.colors,
                ),
                if (!kReleaseMode)
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
                      colors: widget.colors,
                    ),
                    isLast: true,
                    colors: widget.colors,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
