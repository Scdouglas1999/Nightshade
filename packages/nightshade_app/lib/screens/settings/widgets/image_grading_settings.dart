// Pack G — image-grading settings UI.
//
// Surfaces the master toggle and per-check thresholds that the Rust
// executor's `RuntimeConfig.default_quality_check` reads at sequence
// start. Each numeric threshold is independently nullable so an operator
// can enable just the checks they want (e.g. "absolute HFR + min star
// count" without the eccentricity gate). The master toggle is the
// safety valve: when false, grading is disabled regardless of the
// individual thresholds.
//
// FITS-side companion: see `expose.rs` / `image_grading.rs` for how
// these thresholds drive the per-frame Pass/Reject decision and the
// reject-folder side-channel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../session_review/auto_integration_service.dart';
import 'settings_widgets.dart';

class ImageGradingSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const ImageGradingSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<ImageGradingSettings> createState() =>
      _ImageGradingSettingsState();
}

class _ImageGradingSettingsState extends ConsumerState<ImageGradingSettings> {
  final _hfrController = TextEditingController();
  final _baselineController = TextEditingController();
  final _eccentricityController = TextEditingController();
  final _starCountController = TextEditingController();
  final _maxRejectsController = TextEditingController();
  final _rejectFolderController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _hfrController.dispose();
    _baselineController.dispose();
    _eccentricityController.dispose();
    _starCountController.dispose();
    _maxRejectsController.dispose();
    _rejectFolderController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _hfrController.text = settings.imageGradingHfrThresholdPx != null
          ? settings.imageGradingHfrThresholdPx!.toStringAsFixed(2)
          : '';
      _baselineController.text =
          settings.imageGradingHfrBaselinePercent != null
              ? settings.imageGradingHfrBaselinePercent!.toStringAsFixed(0)
              : '';
      _eccentricityController.text =
          settings.imageGradingEccentricityThreshold != null
              ? settings.imageGradingEccentricityThreshold!
                  .toStringAsFixed(2)
              : '';
      _starCountController.text = settings.imageGradingStarCountMin != null
          ? settings.imageGradingStarCountMin!.toString()
          : '';
      _maxRejectsController.text =
          settings.imageGradingMaxConsecutiveRejects.toString();
      _rejectFolderController.text =
          settings.imageGradingRejectFolderPath ?? '';
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

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
        final notifier = ref.read(appSettingsProvider.notifier);
        final enabled = settings.enableImageGrading;

        return SettingsPage(
          title: 'Image Grading',
          description:
              'Auto-reject blurry / trailed / clouded frames at capture time',
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: 'Master toggle',
              children: [
                SettingRow(
                  icon: LucideIcons.toggleLeft,
                  title: 'Enable image grading',
                  subtitle:
                      'When on, every captured frame is scored against the thresholds below. Bad frames are moved to the reject folder.',
                  trailing: SettingsSwitch(
                    value: enabled,
                    onChanged: (value) async {
                      await notifier.setEnableImageGrading(value);
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Focus thresholds',
              children: [
                SettingRow(
                  icon: LucideIcons.crosshair,
                  title: 'HFR absolute (pixels)',
                  subtitle:
                      'Reject if measured HFR exceeds this absolute value. Leave blank to disable.',
                  trailing: _OptionalNumberInput(
                    controller: _hfrController,
                    suffix: 'px',
                    min: 0.1,
                    max: 50.0,
                    decimals: 2,
                    enabled: enabled,
                    onCommit: (value) async {
                      await notifier.setImageGradingHfrThreshold(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.trendingUp,
                  title: 'HFR baseline percent',
                  subtitle:
                      'Reject if HFR > baseline × (1 + percent/100). The baseline is the median of the first 5 accepted frames of each target.',
                  trailing: _OptionalNumberInput(
                    controller: _baselineController,
                    suffix: '%',
                    min: 1.0,
                    max: 500.0,
                    decimals: 0,
                    enabled: enabled,
                    onCommit: (value) async {
                      await notifier.setImageGradingHfrBaselinePercent(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Star shape thresholds',
              children: [
                SettingRow(
                  icon: LucideIcons.move,
                  title: 'Eccentricity max',
                  subtitle:
                      'Reject if star eccentricity exceeds this value. 0.6 catches trailed frames; 0.8 catches catastrophic tracking failure. Leave blank to disable.',
                  trailing: _OptionalNumberInput(
                    controller: _eccentricityController,
                    suffix: '',
                    min: 0.0,
                    max: 1.0,
                    decimals: 2,
                    enabled: enabled,
                    onCommit: (value) async {
                      await notifier
                          .setImageGradingEccentricityThreshold(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.star,
                  title: 'Star count min',
                  subtitle:
                      'Reject if detected star count drops below this value. Trips when clouds roll in or the dome slit drifts off-target. Leave blank to disable.',
                  trailing: _OptionalIntInput(
                    controller: _starCountController,
                    suffix: 'stars',
                    min: 1,
                    max: 100000,
                    enabled: enabled,
                    onCommit: (value) async {
                      await notifier.setImageGradingStarCountMin(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Escalation',
              children: [
                SettingRow(
                  icon: LucideIcons.alertOctagon,
                  title: 'Max consecutive rejects',
                  subtitle:
                      'Pause the sequence after this many consecutive rejected frames — the safety valve when something is systematically wrong (drifted focus, clouds, dome misalignment).',
                  trailing: _OptionalIntInput(
                    controller: _maxRejectsController,
                    suffix: 'frames',
                    min: 1,
                    max: 100,
                    enabled: enabled,
                    allowClear: false,
                    onCommit: (value) async {
                      if (value == null) return;
                      await notifier
                          .setImageGradingMaxConsecutiveRejects(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Post-session integration',
              children: [
                SettingRow(
                  icon: LucideIcons.sparkles,
                  title: 'Auto-integrate at end of run',
                  subtitle:
                      'When on, the accepted subs are integrated into an '
                      'archival master automatically when a sequence run '
                      'completes — wake up to a finished image. The result '
                      'lands in Session Review › Masters.',
                  trailing: const _AutoIntegrateSwitch(),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Reject folder',
              children: [
                SettingRow(
                  icon: LucideIcons.folderX,
                  title: 'Reject folder path',
                  subtitle:
                      'Where rejected frames go. Leave blank for the default <save_path>/Reject/. Relative paths resolve against save_path; absolute paths are honoured verbatim.',
                  trailing: SettingsTextInput(
                    controller: _rejectFolderController,
                    hint: '<save_path>/Reject/',
                    onChanged: (value) async {
                      // Only persist when the user finishes typing (loses
                      // focus would be ideal; settings_widgets doesn't
                      // expose that, so we save on every change but the
                      // setter trims empty -> null).
                      await notifier.setImageGradingRejectFolderPath(value);
                    },
                    isMobile: widget.isMobile,
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

/// Opt-in toggle for the post-session auto-integration hook. Persists the
/// boolean directly through [settingsDaoProvider] under
/// [kAutoIntegrateSettingKey] (a feature-local key, no AppSettings schema
/// change), defaulting to off so unattended-night auto-processing is opt-in.
class _AutoIntegrateSwitch extends ConsumerStatefulWidget {
  const _AutoIntegrateSwitch();

  @override
  ConsumerState<_AutoIntegrateSwitch> createState() =>
      _AutoIntegrateSwitchState();
}

class _AutoIntegrateSwitchState extends ConsumerState<_AutoIntegrateSwitch> {
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final raw =
        await ref.read(settingsDaoProvider).getSetting(kAutoIntegrateSettingKey);
    if (!mounted) return;
    setState(() {
      _enabled = raw == 'true';
      _loaded = true;
    });
  }

  Future<void> _set(bool value) async {
    setState(() => _enabled = value);
    await ref
        .read(settingsDaoProvider)
        .setSetting(kAutoIntegrateSettingKey, value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSwitch(
      value: _enabled,
      onChanged: (v) {
        if (!_loaded) return;
        _set(v);
      },
    );
  }
}

/// Pack G — a number input that supports an "empty = null" state for the
/// optional thresholds. Clearing the field commits `null` to the setting
/// (disabling that specific check while keeping the master toggle on).
class _OptionalNumberInput extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final double min;
  final double max;
  final int decimals;
  final bool enabled;
  final ValueChanged<double?> onCommit;
  final bool isMobile;

  const _OptionalNumberInput({
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.decimals,
    required this.enabled,
    required this.onCommit,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final effectiveWidth = isMobile ? 120.0 : 140.0;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SizedBox(
          width: effectiveWidth,
          child: TextField(
            controller: controller,
            keyboardType:
                TextInputType.numberWithOptions(decimal: decimals > 0),
            style: TextStyle(
              fontSize: isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize12,
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '—',
              suffixText: suffix.isEmpty ? null : suffix,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
            ),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                onCommit(null);
                return;
              }
              final parsed = double.tryParse(value.trim());
              if (parsed != null) {
                final clamped = parsed.clamp(min, max);
                onCommit(clamped);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Pack G — integer-only variant of `_OptionalNumberInput` for star
/// count + max consecutive rejects.
class _OptionalIntInput extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final int min;
  final int max;
  final bool enabled;
  final bool allowClear;
  final ValueChanged<int?> onCommit;
  final bool isMobile;

  const _OptionalIntInput({
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onCommit,
    this.allowClear = true,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final effectiveWidth = isMobile ? 120.0 : 140.0;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SizedBox(
          width: effectiveWidth,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontSize: isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize12,
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: allowClear ? '—' : '',
              suffixText: suffix.isEmpty ? null : suffix,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
            ),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                if (allowClear) onCommit(null);
                return;
              }
              final parsed = int.tryParse(value.trim());
              if (parsed != null) {
                final clamped = parsed.clamp(min, max);
                onCommit(clamped);
              }
            },
          ),
        ),
      ),
    );
  }
}
