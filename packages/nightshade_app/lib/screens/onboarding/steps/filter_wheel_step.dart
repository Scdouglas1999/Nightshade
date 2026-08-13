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

  /// Upper bound used ONLY when the wheel's real position count is unknown.
  /// A connected wheel caps the editor at what it actually reports.
  static const int _hardSlotCap = 12;

  List<TextEditingController> _controllers = [];

  /// True while we connect the just-picked wheel to read its real slot count
  /// and driver-reported filter names.
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingDraftProvider);
    final draftNames = draft.filterNames;
    _rebuildControllers(
      count: draftNames.isNotEmpty ? draftNames.length : _fallbackSlots,
      names: draftNames,
    );
    // Re-entering the step with a wheel already picked but no names on record
    // (an earlier visit whose connect failed) rendered the fallback slots
    // without ever saving them. Adopt what is displayed so the profile carries
    // the filters the user was shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (draft.filterWheelId == null) return;
      _commitFiltersIfUnset();
    });
  }

  /// Commit the on-screen slot names when the draft carries none.
  ///
  /// Only when the draft is empty: the driver-reported names take precedence,
  /// and a user-typed name must never be replaced by a `Filter N` placeholder.
  void _commitFiltersIfUnset() {
    if (ref.read(onboardingDraftProvider).filterNames.isNotEmpty) return;
    _commitFilters();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildControllers({required int count, required List<String> names}) {
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
      if (mounted) {
        setState(() => _loadingSlots = false);
        // The editor only reached the draft when the user typed in it, so a
        // wheel whose slot count could not be read showed a column of named,
        // apparently-saved slots and then created a profile with no filters at
        // all — the sequencer's filter list came up empty on the first night.
        // Commit what is on screen whenever the draft still has nothing, so the
        // profile matches the slots the step displayed. Deliberately after the
        // driver merge, and only when the draft is empty, so real driver names
        // are never overwritten by the "Filter N" placeholders.
        _commitFiltersIfUnset();
      }
    }
  }

  void _commitFilters() {
    final names = _controllers
        .map((c) => c.text.trim().isNotEmpty
            ? c.text.trim()
            : 'Slot ${_controllers.indexOf(c) + 1}')
        .toList();
    ref.read(onboardingDraftProvider.notifier).setFilterNames(names);
  }

  /// Add a slot back, recovering the wheel's own name for that position.
  ///
  /// Deleting slot 7 ("SII") and adding one back used to produce "Filter 7" — a
  /// name nobody typed and no wheel reports, which then travelled into FITS
  /// headers, flat matching and per-filter focus offsets. The connected wheel
  /// already told us what sits at that position; when it has not, the row opens
  /// blank so the user names it rather than inheriting a placeholder.
  void _addSlot() {
    final driverNames = ref.read(filterWheelStateProvider).filterNames;
    final index = _controllers.length;
    final recovered = index < driverNames.length ? driverNames[index] : '';
    setState(() {
      _controllers.add(TextEditingController(text: recovered));
    });
    _commitFilters();
  }

  /// Delete a slot, confirming first when it is not the LAST row.
  ///
  /// Slot labels are positions on the wheel, so removing a middle row shifts
  /// every row below it up one position — the name the user typed for
  /// position 5 silently becomes position 4, and per-filter focus offsets keyed
  /// by position follow it. Deleting the last row cannot renumber anything, so
  /// it stays a single click.
  Future<void> _removeSlot(int index) async {
    final isLast = index == _controllers.length - 1;
    if (!isLast) {
      final name = _controllers[index].text.trim();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove this slot?'),
          content: Text(
            'Removing slot ${index + 1}${name.isEmpty ? '' : ' ($name)'} moves '
            'every slot below it up one position, so the filters after it will '
            'no longer sit on the positions you gave them.',
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            NightshadeButton(
              label: 'Remove slot',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
    _commitFilters();
  }

  /// Positions the CONNECTED wheel reports, or null when we have no reading.
  ///
  /// Only trusted when the connected device is the one the draft picked: a
  /// stale connection to another wheel must not cap this one's editor.
  int? _reportedSlotCount(OnboardingDraft draft, FilterWheelState wheel) {
    if (draft.filterWheelId == null) return null;
    if (wheel.connectionState != DeviceConnectionState.connected) return null;
    if (wheel.deviceId != draft.filterWheelId) return null;
    return wheel.filterNames.isEmpty ? null : wheel.filterNames.length;
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final hasWheel = draft.filterWheelId != null;

    // The wheel's own position count is the cap. Inventing slot 8 on a
    // 7-position wheel produced a profile whose filter list the hardware can
    // never reach — the sequencer would ask for a position that does not exist.
    // With no reading (connect failed) fall back to the generic hard cap.
    final reportedSlots =
        _reportedSlotCount(draft, ref.watch(filterWheelStateProvider));
    final slotCap = reportedSlots ?? _hardSlotCap;
    final atSlotCap = _controllers.length >= slotCap;

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
              Tooltip(
                message: atSlotCap
                    ? (reportedSlots != null
                        ? '${draft.filterWheelName ?? 'This wheel'} reports '
                            '$reportedSlots positions — it has no slot '
                            '${_controllers.length + 1} to hold another filter.'
                        : 'A profile can hold at most $_hardSlotCap filters.')
                    : 'Add another filter slot',
                child: NightshadeButton(
                  icon: NightshadeIcons.add,
                  label: 'Add slot',
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: (_loadingSlots || atSlotCap) ? null : _addSlot,
                ),
              ),
            ],
          ),
          if (reportedSlots != null) ...[
            const SizedBox(height: 4),
            Text(
              atSlotCap
                  ? 'All $reportedSlots positions on this wheel are listed.'
                  : '${draft.filterWheelName ?? 'This wheel'} reports '
                      '$reportedSlots positions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
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
                    onPressed:
                        _controllers.length > 1 ? () => _removeSlot(i) : null,
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
