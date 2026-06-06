import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'device_picker_step.dart';

/// Filter wheel selection + filter-name editing.
///
/// Optional — many imagers run mono-OSC setups without a filter wheel.
/// When a wheel is picked we connect it and read its ACTUAL slot count +
/// driver-reported filter names, so an 8-position ZWO EFW shows eight editable
/// rows (not a hardcoded default). Names the user already typed are preserved
/// for the slots they cover. If the wheel can't be connected we fall back to
/// the existing draft/last-resort editor rather than fabricating a count.
/// Merge the driver's actual filter-slot names with names the user already
/// typed in the onboarding draft. The result ALWAYS has exactly
/// [driverNames.length] entries (the wheel's real slot count), and keeps a
/// user-entered name for any slot they already filled in — otherwise it uses
/// the driver-reported name for that slot. Pure + [visibleForTesting] so the
/// "use the device count, preserve user names" rule is unit-tested directly.
@visibleForTesting
List<String> mergeFilterSlotNames(
  List<String> driverNames,
  List<String> draftNames,
) {
  return List<String>.generate(
    driverNames.length,
    (i) => i < draftNames.length && draftNames[i].trim().isNotEmpty
        ? draftNames[i]
        : driverNames[i],
  );
}

class OnboardingFilterWheelStep extends ConsumerStatefulWidget {
  const OnboardingFilterWheelStep({super.key});

  @override
  ConsumerState<OnboardingFilterWheelStep> createState() =>
      _OnboardingFilterWheelStepState();
}

class _OnboardingFilterWheelStepState
    extends ConsumerState<OnboardingFilterWheelStep> {
  // Last-resort fallback ONLY when a wheel's real slot count can't be read
  // (connect failed AND the draft carries no prior names). The happy path
  // reads the actual slot count + names from the connected driver.
  static const int _fallbackSlots = 5;

  List<TextEditingController> _controllers = [];

  /// True while we connect the just-picked wheel to read its real slot count
  /// and driver-reported filter names.
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    final draftNames = ref.read(onboardingDraftProvider).filterNames;
    _rebuildControllers(
      count: draftNames.isNotEmpty ? draftNames.length : _fallbackSlots,
      names: draftNames,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildControllers(
      {required int count, required List<String> names}) {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers = List.generate(
      count,
      (i) => TextEditingController(
        text: i < names.length && names[i].trim().isNotEmpty
            ? names[i]
            : 'Filter ${i + 1}',
      ),
    );
  }

  /// Connect the picked filter wheel and seed the slot editor from the driver's
  /// ACTUAL slot count + reported names (e.g. an 8-position ZWO EFW shows eight
  /// slots, not the fallback). Names the user already entered in the draft are
  /// preserved for the slots they cover. Best-effort: a failed connect leaves
  /// the current editor intact — the real count is re-read when the wheel
  /// connects later in the normal equipment flow.
  Future<void> _seedSlotsFromDevice(String deviceId) async {
    setState(() => _loadingSlots = true);
    try {
      await ref
          .read(filterWheelStateProvider.notifier)
          .connect(deviceId, maxRetries: 1);
      if (!mounted) return;
      final fw = ref.read(filterWheelStateProvider);
      final driverNames = fw.filterNames;
      if (fw.connectionState == DeviceConnectionState.connected &&
          driverNames.isNotEmpty) {
        final draftNames = ref.read(onboardingDraftProvider).filterNames;
        final seeded = mergeFilterSlotNames(driverNames, draftNames);
        if (!mounted) return;
        setState(() => _rebuildControllers(
              count: seeded.length,
              names: seeded,
            ));
        _commitFilters();
      }
    } catch (e) {
      // Surface for diagnostics but don't block onboarding on a flaky connect.
      developer.log(
        'Filter wheel slot read failed for $deviceId: $e',
        name: 'OnboardingFilterWheelStep',
        level: 900,
      );
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  void _commitFilters() {
    final names = _controllers
        .map((c) =>
            c.text.trim().isNotEmpty ? c.text.trim() : 'Slot ${_controllers.indexOf(c) + 1}')
        .toList();
    ref.read(onboardingDraftProvider.notifier).setFilterNames(names);
  }

  void _addSlot() {
    setState(() {
      _controllers.add(
        TextEditingController(text: 'Filter ${_controllers.length + 1}'),
      );
    });
    _commitFilters();
  }

  void _removeSlot(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
    _commitFilters();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final hasWheel = draft.filterWheelId != null;

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final pickerHeight = hasWheel
        ? clampPanelWidth(
            viewportHeight,
            fraction: 0.28,
            min: 180,
            max: 240,
          )
        : clampPanelWidth(
            viewportHeight,
            fraction: 0.45,
            min: 240,
            max: 380,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Picker takes a viewport-fraction so the filter editor below has
          // breathing room when the wheel is selected.
          height: pickerHeight,
          child: OnboardingDevicePickerBody(
            title: 'Pick your filter wheel (optional)',
            subtitle:
                'Tell us what each slot holds so flats, autofocus, and offsets work per filter.',
            icon: NightshadeIcons.filterWheel,
            deviceType: DeviceType.filterWheel,
            selectedDeviceId: draft.filterWheelId,
            selectedDeviceName: draft.filterWheelName,
            allowSkip: true,
            onSelected: (device) {
              notifier.setFilterWheel(
                id: device.activeDeviceId,
                name: device.displayName,
              );
              setState(() {});
              // Connect the wheel and read its real slot count + filter names
              // so the editor reflects the hardware (e.g. 8 slots), not a
              // hardcoded default.
              _seedSlotsFromDevice(device.activeDeviceId);
            },
            onCleared: () {
              notifier.setFilterWheel(id: '');
              setState(() {});
            },
          ),
        ),
        if (hasWheel) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Filters',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_loadingSlots) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Reading wheel…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textMuted),
                ),
                const SizedBox(width: 8),
              ],
              NightshadeButton(
                icon: NightshadeIcons.add,
                label: 'Add slot',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: (_loadingSlots || _controllers.length >= 12)
                    ? null
                    : _addSlot,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // List of editable filter slots. We deliberately render inline
          // (not in a separate Drift table) so the user sees their
          // changes saved on Next without needing to confirm a sub-form.
          ...List.generate(_controllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[i],
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        hintText: 'L / R / G / B / Ha …',
                        hintStyle: TextStyle(color: colors.textMuted),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: NightshadeTokens.borderRadiusMd,
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: NightshadeTokens.borderRadiusMd,
                          borderSide: BorderSide(color: colors.primary),
                        ),
                        filled: true,
                        fillColor: colors.surface,
                      ),
                      onChanged: (_) => _commitFilters(),
                    ),
                  ),
                  IconButton(
                    onPressed: _controllers.length > 1
                        ? () => _removeSlot(i)
                        : null,
                    icon: Icon(
                      NightshadeIcons.delete,
                      size: 16,
                      color: _controllers.length > 1
                          ? colors.error
                          : colors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
