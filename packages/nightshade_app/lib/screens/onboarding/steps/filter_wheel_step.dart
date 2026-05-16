import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'device_picker_step.dart';

/// Filter wheel selection + filter-name editing.
///
/// Optional — many imagers run mono-OSC setups without a filter wheel.
/// When a wheel is picked we render an inline editor for filter names
/// keyed by slot index so a 7-position EFW shows seven editable rows.
/// The slot count comes from the driver's discovery data when available,
/// otherwise we default to 5 (the most common amateur-rig count).
class OnboardingFilterWheelStep extends ConsumerStatefulWidget {
  const OnboardingFilterWheelStep({super.key});

  @override
  ConsumerState<OnboardingFilterWheelStep> createState() =>
      _OnboardingFilterWheelStepState();
}

class _OnboardingFilterWheelStepState
    extends ConsumerState<OnboardingFilterWheelStep> {
  static const int _defaultSlots = 5;

  List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _rebuildControllers(ref.read(onboardingDraftProvider).filterNames);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildControllers(List<String> names) {
    for (final c in _controllers) {
      c.dispose();
    }
    final count = names.isNotEmpty ? names.length : _defaultSlots;
    _controllers = List.generate(
      count,
      (i) => TextEditingController(
        text: i < names.length ? names[i] : 'Filter ${i + 1}',
      ),
    );
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);
    final hasWheel = draft.filterWheelId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Picker takes a fixed portion so the filter editor below has
          // breathing room when the wheel is selected.
          height: hasWheel ? 240 : 380,
          child: OnboardingDevicePickerBody(
            title: 'Pick your filter wheel (optional)',
            subtitle:
                'Tell us what each slot holds so flats, autofocus, and offsets work per filter.',
            icon: LucideIcons.disc,
            deviceType: DeviceType.filterWheel,
            selectedDeviceId: draft.filterWheelId,
            selectedDeviceName: draft.filterWheelName,
            allowSkip: true,
            onSelected: (device) {
              notifier.setFilterWheel(
                id: device.activeDeviceId,
                name: device.displayName,
              );
              // After picking a wheel, build local controllers if they
              // haven't been seeded yet so the editor renders immediately.
              if (_controllers.isEmpty) {
                _rebuildControllers(const []);
              }
              setState(() {});
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
              NightshadeButton(
                icon: LucideIcons.plus,
                label: 'Add slot',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed:
                    _controllers.length < 12 ? _addSlot : null,
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
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
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
                      LucideIcons.trash2,
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
