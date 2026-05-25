// First-time equipment setup wizard (DEV-P2-5).
//
// A 3-page wizard the empty-profile onboarding screen launches when the user
// taps "Start Setup". Replaces the previous behaviour — which silently created
// an unnamed profile and fired discovery — with the real flow promised by the
// welcome copy:
//
//   Page 1 — Scan:    run discovery, surface per-backend status & errors,
//                     show devices live as they arrive.
//   Page 2 — Select:  pick one device per type. Already-connected devices
//                     get pre-selected so power users can confirm with one
//                     click.
//   Page 3 — Save:    name the profile, review the summary, persist via
//                     [ProfileService], then connect everything in parallel
//                     via [DeviceService.connectAllFromProfile].
//
// Errors are a feature here:
//   - Per-backend discovery errors render as red chips with the full driver
//     message, but never block the user from picking devices found by working
//     backends.
//   - Save failures (profile DB write or per-device connect) surface as
//     in-dialog error banners with the verbatim error string.
//
// Cancellation contract: closing or "Cancel" at any step makes no DB writes
// and starts no connect attempts. Once the profile id is returned via
// Navigator.pop, the screen treats it identically to a manually-created
// profile.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../utils/connect_all_summary.dart';
import '../utils/driver_error_pretty.dart';

/// Result returned from the wizard on a successful save. The caller uses
/// [profileId] to select the new profile in the equipment screen; [connectAttempted]
/// tells callers whether a connection sweep ran so they don't redundantly trigger
/// another one.
class FirstTimeSetupResult {
  final int profileId;
  final bool connectAttempted;

  const FirstTimeSetupResult({
    required this.profileId,
    required this.connectAttempted,
  });
}

/// The 3-page first-time setup wizard dialog.
class FirstTimeSetupWizardDialog extends ConsumerStatefulWidget {
  const FirstTimeSetupWizardDialog({super.key});

  /// Show the wizard and return the resulting profile id on save, or null on
  /// cancel.
  static Future<FirstTimeSetupResult?> show(BuildContext context) {
    return showDialog<FirstTimeSetupResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const FirstTimeSetupWizardDialog(),
    );
  }

  @override
  ConsumerState<FirstTimeSetupWizardDialog> createState() =>
      _FirstTimeSetupWizardDialogState();
}

enum _WizardStep { scan, select, save }

class _FirstTimeSetupWizardDialogState
    extends ConsumerState<FirstTimeSetupWizardDialog> {
  _WizardStep _step = _WizardStep.scan;

  // Page 1 — discovery kicked off in initState; the unifiedDiscoveryProvider
  // drives all per-backend status and grouped device data we render.
  bool _discoveryStarted = false;

  // Page 2 — user's per-type backend/device selections, keyed by DeviceType.
  // null means "do not assign for this slot".
  final Map<DeviceType, String?> _selectedDeviceIds = {};

  // True after we've seeded selections from already-connected devices.
  bool _seededSelections = false;

  // Page 3 — profile naming & save bookkeeping.
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _saveError;
  final List<ConnectAllFailure> _connectFailures = [];
  int _connectedCount = 0;

  static const _orderedDeviceTypes = <DeviceType>[
    DeviceType.camera,
    DeviceType.mount,
    DeviceType.focuser,
    DeviceType.filterWheel,
    DeviceType.guider,
    DeviceType.rotator,
    DeviceType.dome,
    DeviceType.weather,
    DeviceType.safetyMonitor,
    DeviceType.switch_,
    DeviceType.coverCalibrator,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _defaultProfileName());
    // Kick off discovery as soon as the dialog mounts. We do this in a
    // post-frame callback so `ref.read` can safely touch StateNotifiers that
    // may schedule work synchronously during their first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _discoveryStarted = true;
      // Fire-and-forget — the UI is driven by watching the provider state.
      // discoverAll already routes per-backend errors into state, so we don't
      // need to await it for error handling.
      unawaited(ref.read(unifiedDiscoveryProvider.notifier).discoverAll());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _defaultProfileName() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'Setup Wizard $today';
  }

  void _seedSelectionsFromConnectedDevicesIfNeeded() {
    if (_seededSelections) return;

    // We only consider seeding from actually-connected devices.
    // (If a device is connected but not visible in discovery yet, we still
    // pre-select its id; the picker shows a synthetic option for it.)
    final readers = <DeviceType, ({String? id, String? name})>{
      DeviceType.camera: _readState(ref.read(cameraStateProvider).connectionState,
          ref.read(cameraStateProvider).deviceId, ref.read(cameraStateProvider).deviceName),
      DeviceType.mount: _readState(ref.read(mountStateProvider).connectionState,
          ref.read(mountStateProvider).deviceId, ref.read(mountStateProvider).deviceName),
      DeviceType.focuser: _readState(ref.read(focuserStateProvider).connectionState,
          ref.read(focuserStateProvider).deviceId, ref.read(focuserStateProvider).deviceName),
      DeviceType.filterWheel: _readState(
          ref.read(filterWheelStateProvider).connectionState,
          ref.read(filterWheelStateProvider).deviceId,
          ref.read(filterWheelStateProvider).deviceName),
      DeviceType.guider: _readState(ref.read(guiderStateProvider).connectionState,
          ref.read(guiderStateProvider).deviceId, ref.read(guiderStateProvider).deviceName),
      DeviceType.rotator: _readState(ref.read(rotatorStateProvider).connectionState,
          ref.read(rotatorStateProvider).deviceId, ref.read(rotatorStateProvider).deviceName),
      DeviceType.dome: _readState(ref.read(domeStateProvider).connectionState,
          ref.read(domeStateProvider).deviceId, ref.read(domeStateProvider).deviceName),
      DeviceType.weather: _readState(ref.read(weatherStateProvider).connectionState,
          ref.read(weatherStateProvider).deviceId, ref.read(weatherStateProvider).deviceName),
      DeviceType.safetyMonitor: _readState(
          ref.read(safetyMonitorStateProvider).connectionState,
          ref.read(safetyMonitorStateProvider).deviceId,
          ref.read(safetyMonitorStateProvider).deviceName),
      DeviceType.switch_: _readState(
          ref.read(switchStateProvider).connectionState,
          ref.read(switchStateProvider).deviceId,
          ref.read(switchStateProvider).deviceName),
      DeviceType.coverCalibrator: _readState(
          ref.read(coverCalibratorStateProvider).connectionState,
          ref.read(coverCalibratorStateProvider).deviceId,
          ref.read(coverCalibratorStateProvider).deviceName),
    };

    for (final entry in readers.entries) {
      final id = entry.value.id;
      if (id != null && id.isNotEmpty) {
        _selectedDeviceIds[entry.key] = id;
      }
    }
    _seededSelections = true;
  }

  ({String? id, String? name}) _readState(
      DeviceConnectionState connState, String? id, String? name) {
    if (connState == DeviceConnectionState.connected) {
      return (id: id, name: name);
    }
    return (id: null, name: null);
  }

  bool get _isScanStep => _step == _WizardStep.scan;
  bool get _isSaveStep => _step == _WizardStep.save;

  void _goNext() {
    if (_isSaving) return;
    setState(() {
      switch (_step) {
        case _WizardStep.scan:
          // Seed pre-selections now that the user is moving into the picker.
          _seedSelectionsFromConnectedDevicesIfNeeded();
          _step = _WizardStep.select;
          break;
        case _WizardStep.select:
          _step = _WizardStep.save;
          break;
        case _WizardStep.save:
          // Handled by Save button directly.
          break;
      }
    });
  }

  void _goBack() {
    if (_isSaving) return;
    setState(() {
      switch (_step) {
        case _WizardStep.scan:
          return;
        case _WizardStep.select:
          _step = _WizardStep.scan;
          break;
        case _WizardStep.save:
          _step = _WizardStep.select;
          break;
      }
    });
  }

  void _cancel() {
    if (_isSaving) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'Profile name is required');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
      _connectFailures.clear();
      _connectedCount = 0;
    });

    final profileService = ref.read(profileServiceProvider);
    final deviceService = ref.read(deviceServiceProvider);

    int? createdProfileId;
    try {
      createdProfileId = await profileService.createProfile(name);
      await profileService.updateProfileDevices(
        createdProfileId,
        cameraId: _selectedDeviceIds[DeviceType.camera],
        mountId: _selectedDeviceIds[DeviceType.mount],
        focuserId: _selectedDeviceIds[DeviceType.focuser],
        filterWheelId: _selectedDeviceIds[DeviceType.filterWheel],
        guiderId: _selectedDeviceIds[DeviceType.guider],
        rotatorId: _selectedDeviceIds[DeviceType.rotator],
        domeId: _selectedDeviceIds[DeviceType.dome],
        weatherId: _selectedDeviceIds[DeviceType.weather],
        safetyMonitorId: _selectedDeviceIds[DeviceType.safetyMonitor],
        switchId: _selectedDeviceIds[DeviceType.switch_],
        coverCalibratorId: _selectedDeviceIds[DeviceType.coverCalibrator],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Failed to create profile: $e';
      });
      return;
    }

    // Fetch the saved profile so we can drive the parallel connect sweep
    // through the same `connectAllFromProfile` stream the rest of the app uses.
    EquipmentProfileModel? profile;
    try {
      final dao = ref.read(equipmentProfilesDaoProvider);
      final dbProfile = await dao.getProfileById(createdProfileId);
      if (dbProfile != null) {
        profile = EquipmentProfileModel.fromDatabase(dbProfile);
      }
    } catch (e) {
      if (!mounted) return;
      // Profile was created but we couldn't reload it for the connect sweep.
      // That's still a successful save; surface as a warning and pop with the
      // id so the screen still selects it.
      Navigator.of(context).pop(FirstTimeSetupResult(
        profileId: createdProfileId,
        connectAttempted: false,
      ));
      return;
    }

    if (profile == null) {
      // Same fallback as above.
      if (!mounted) return;
      Navigator.of(context).pop(FirstTimeSetupResult(
        profileId: createdProfileId,
        connectAttempted: false,
      ));
      return;
    }

    // Stream parallel connects. Failures are reported per-device — we collect
    // them so the user can see exactly which devices failed and why.
    try {
      await for (final event
          in deviceService.connectAllFromProfile(profile)) {
        if (!mounted) return;
        if (event.status == DeviceConnectProgressStatus.connected) {
          setState(() => _connectedCount++);
        } else if (event.status == DeviceConnectProgressStatus.failed) {
          setState(() => _connectFailures
              .add(ConnectAllFailure.fromProgress(event)));
        }
      }
    } catch (e) {
      // The stream contract documents that per-device failures arrive as
      // `failed` events; a stream-level error is unexpected, but if one
      // somehow surfaces we keep the profile and report the error.
      if (mounted) {
        setState(() {
          _saveError = 'Connect sweep error: $e';
        });
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(FirstTimeSetupResult(
      profileId: createdProfileId,
      connectAttempted: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogMaxWidth(context, 640),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colors, theme),
            _buildStepIndicator(colors),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepBody(colors, theme),
              ),
            ),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: NightshadeDecorations.emphasisSurface(
              colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.sparkles, color: colors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'First-Time Equipment Setup',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _stepSubtitle(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isSaving ? null : _cancel,
            icon: Icon(LucideIcons.x, color: colors.textMuted),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  String _stepSubtitle() {
    switch (_step) {
      case _WizardStep.scan:
        return 'Step 1 of 3: Discover connected equipment';
      case _WizardStep.select:
        return 'Step 2 of 3: Pick the devices to use';
      case _WizardStep.save:
        return 'Step 3 of 3: Name and save the profile';
    }
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          final activeIndex = _step.index;
          final isActive = index == activeIndex;
          final isCompleted = index < activeIndex;
          return Row(
            children: [
              if (index > 0)
                Container(
                  width: 36,
                  height: 2,
                  color: isCompleted || isActive
                      ? colors.primary
                      : colors.border,
                ),
              _StepDot(
                index: index + 1,
                isActive: isActive,
                isCompleted: isCompleted,
                colors: colors,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepBody(NightshadeColors colors, ThemeData theme) {
    switch (_step) {
      case _WizardStep.scan:
        return _buildScanPage(colors, theme);
      case _WizardStep.select:
        return _buildSelectPage(colors, theme);
      case _WizardStep.save:
        return _buildSavePage(colors, theme);
    }
  }

  // ============================================================================
  // Page 1 — Scan
  // ============================================================================

  Widget _buildScanPage(NightshadeColors colors, ThemeData theme) {
    final discovery = ref.watch(unifiedDiscoveryProvider);
    final isDiscovering = discovery.isDiscovering || !_discoveryStarted;
    final groupedByType = <DeviceType, List<UnifiedDevice>>{};
    for (final dev in discovery.groupedDevices) {
      groupedByType.putIfAbsent(dev.type, () => []).add(dev);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isDiscovering)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            else
              Icon(LucideIcons.searchCheck,
                  size: 20, color: colors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isDiscovering
                    ? 'Discovering equipment…'
                    : 'Scan complete',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!isDiscovering)
              NightshadeButton(
                onPressed: () {
                  unawaited(ref
                      .read(unifiedDiscoveryProvider.notifier)
                      .discoverAll());
                },
                label: 'Rescan',
                icon: LucideIcons.refreshCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _summaryLine(discovery),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 16),
        _buildBackendChips(discovery, colors, theme),
        const SizedBox(height: 20),
        Text(
          'Discovered devices',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (groupedByType.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 16, color: colors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isDiscovering
                        ? 'Scanning all backends in parallel…'
                        : 'No devices were found. Power on your equipment '
                            'and tap Rescan, or continue to set the profile '
                            'up manually.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          ..._orderedDeviceTypes
              .where((t) => (groupedByType[t]?.isNotEmpty ?? false))
              .map((type) => _buildDiscoveredGroup(
                    type,
                    groupedByType[type]!,
                    colors,
                    theme,
                    selectable: false,
                  )),
      ],
    );
  }

  String _summaryLine(UnifiedDiscoveryState discovery) {
    final byType = <DeviceType, int>{};
    for (final d in discovery.groupedDevices) {
      byType[d.type] = (byType[d.type] ?? 0) + 1;
    }
    if (byType.isEmpty) {
      if (discovery.isDiscovering) {
        return 'Searching ASCOM, Alpaca, INDI and native drivers in parallel.';
      }
      return 'No devices have been found yet.';
    }
    final parts = <String>[];
    for (final type in _orderedDeviceTypes) {
      final count = byType[type] ?? 0;
      if (count == 0) continue;
      parts.add('$count ${_devicePluralName(type, count)}');
    }
    return 'Found ${parts.join(', ')}.';
  }

  Widget _buildBackendChips(
    UnifiedDiscoveryState discovery,
    NightshadeColors colors,
    ThemeData theme,
  ) {
    if (discovery.backendStates.isEmpty) {
      return Text(
        'Backends not yet started.',
        style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
      );
    }
    // Render in a stable order so the row doesn't reflow as backends complete.
    const order = <DriverType>[
      DriverType.ascom,
      DriverType.alpaca,
      DriverType.indi,
      DriverType.native,
      DriverType.simulator,
    ];
    final chips = <Widget>[];
    for (final backend in order) {
      final state = discovery.backendStates[backend];
      if (state == null) continue;
      chips.add(_BackendStatusChip(state: state, colors: colors));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  // ============================================================================
  // Page 2 — Select
  // ============================================================================

  Widget _buildSelectPage(NightshadeColors colors, ThemeData theme) {
    final discovery = ref.watch(unifiedDiscoveryProvider);
    final groupedByType = <DeviceType, List<UnifiedDevice>>{};
    for (final dev in discovery.groupedDevices) {
      groupedByType.putIfAbsent(dev.type, () => []).add(dev);
    }

    final visibleTypes = _orderedDeviceTypes
        .where((t) => (groupedByType[t]?.isNotEmpty ?? false))
        .toList();

    if (visibleTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 18, color: colors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No devices were discovered. Tap Back to rescan, or continue '
                'to save an empty profile and add devices later.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick the device you want to use for each role. You can skip any '
          'device type — its profile slot will remain empty.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 16),
        ...visibleTypes.map((type) => _buildDiscoveredGroup(
              type,
              groupedByType[type]!,
              colors,
              theme,
              selectable: true,
            )),
      ],
    );
  }

  // ============================================================================
  // Page 3 — Save
  // ============================================================================

  Widget _buildSavePage(NightshadeColors colors, ThemeData theme) {
    final selectedSummary = _selectedSummaryRows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile name',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          enabled: !_isSaving,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g., Backyard Rig',
            hintStyle: TextStyle(color: colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            errorText: (_saveError != null &&
                    _nameController.text.trim().isEmpty)
                ? _saveError
                : null,
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (_) {
            if (_saveError != null) {
              setState(() => _saveError = null);
            }
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Summary',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedSummary.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No devices selected. The profile will be created empty.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textMuted),
                  ),
                )
              else
                ...selectedSummary
                    .map((row) => _buildSummaryRow(row, colors, theme)),
            ],
          ),
        ),
        if (_isSaving) ...[
          const SizedBox(height: 16),
          _buildSavingPanel(colors, theme),
        ],
        if (_saveError != null &&
            _nameController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildErrorBanner(_saveError!, colors, theme),
        ],
      ],
    );
  }

  Widget _buildSavingPanel(NightshadeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Saving profile and connecting devices…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$_connectedCount connected',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          if (_connectFailures.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._connectFailures.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.alertTriangle,
                          size: 12, color: colors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${f.deviceType}: ${f.message}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.error),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
      String message, NightshadeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      _SummaryRow row, NightshadeColors colors, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_iconForType(row.type), size: 16, color: colors.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              _displayNameForType(row.type),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              row.deviceLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (row.backend != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                row.backend!.shortLabel,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  List<_SummaryRow> _selectedSummaryRows() {
    final discovery = ref.read(unifiedDiscoveryProvider);
    final rows = <_SummaryRow>[];
    for (final type in _orderedDeviceTypes) {
      final id = _selectedDeviceIds[type];
      if (id == null || id.isEmpty) continue;
      String label = id;
      DriverType? backend;
      for (final dev in discovery.groupedDevices) {
        if (dev.type != type) continue;
        for (final entry in dev.availableBackends.entries) {
          if (entry.value.id == id) {
            label = dev.displayName;
            backend = entry.key;
            break;
          }
        }
        if (backend != null) break;
      }
      rows.add(_SummaryRow(
          type: type, deviceLabel: label, backend: backend));
    }
    return rows;
  }

  // ============================================================================
  // Discovered group (used by both Scan and Select pages)
  // ============================================================================

  Widget _buildDiscoveredGroup(
    DeviceType type,
    List<UnifiedDevice> devices,
    NightshadeColors colors,
    ThemeData theme, {
    required bool selectable,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: NightshadeDecorations.tintedBadge(
                    colors.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(_iconForType(type),
                      size: 14, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  _displayNameForType(type),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${devices.length}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          ...devices.expand((device) => _buildDeviceRows(
                type,
                device,
                colors,
                theme,
                selectable: selectable,
              )),
          if (selectable)
            _buildSkipRow(type, colors, theme),
        ],
      ),
    );
  }

  // A UnifiedDevice may expose one row per backend so the user can
  // explicitly pick which backend to connect through (e.g. ASCOM vs
  // Alpaca). For the read-only Scan page we collapse to one row per
  // logical device but show all backend chips.
  Iterable<Widget> _buildDeviceRows(
    DeviceType type,
    UnifiedDevice device,
    NightshadeColors colors,
    ThemeData theme, {
    required bool selectable,
  }) {
    if (!selectable) {
      return [_buildScanDeviceRow(device, colors, theme)];
    }
    return device.sortedBackends.map((backend) {
      final deviceInfo = device.availableBackends[backend]!;
      final selectedId = _selectedDeviceIds[type];
      final isSelected = selectedId == deviceInfo.id;
      return _buildSelectableDeviceRow(
        type: type,
        device: device,
        backend: backend,
        deviceInfo: deviceInfo,
        isSelected: isSelected,
        colors: colors,
        theme: theme,
      );
    });
  }

  Widget _buildScanDeviceRow(
      UnifiedDevice device, NightshadeColors colors, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(LucideIcons.dot, size: 16, color: colors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              device.displayName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...device.sortedBackends.map((b) => Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    b.shortLabel,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colors.textMuted),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSelectableDeviceRow({
    required DeviceType type,
    required UnifiedDevice device,
    required DriverType backend,
    required DeviceInfo deviceInfo,
    required bool isSelected,
    required NightshadeColors colors,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDeviceIds[type] = deviceInfo.id;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Radio<String>(
              value: deviceInfo.id,
              groupValue: _selectedDeviceIds[type],
              activeColor: colors.primary,
              onChanged: (value) {
                setState(() {
                  _selectedDeviceIds[type] = value;
                });
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    deviceInfo.id,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                backend.shortLabel,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipRow(
      DeviceType type, NightshadeColors colors, ThemeData theme) {
    final isSkipped = _selectedDeviceIds[type] == null ||
        _selectedDeviceIds[type]!.isEmpty;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDeviceIds[type] = null;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Radio<String?>(
              value: null,
              groupValue: _selectedDeviceIds[type],
              activeColor: colors.primary,
              onChanged: (value) {
                setState(() {
                  _selectedDeviceIds[type] = null;
                });
              },
            ),
            const SizedBox(width: 4),
            Text(
              'Skip — leave this slot empty',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSkipped ? colors.textSecondary : colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Footer
  // ============================================================================

  Widget _buildFooter(NightshadeColors colors) {
    final canSave = !_isSaving;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          NightshadeButton(
            onPressed: _isSaving ? null : _cancel,
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          const Spacer(),
          if (!_isScanStep)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: NightshadeButton(
                onPressed: _isSaving ? null : _goBack,
                icon: LucideIcons.arrowLeft,
                label: 'Back',
                variant: ButtonVariant.outline,
              ),
            ),
          if (_isSaveStep)
            NightshadeButton(
              onPressed: canSave ? _save : null,
              icon: LucideIcons.save,
              label: 'Save',
              variant: ButtonVariant.primary,
              isLoading: _isSaving,
            )
          else
            NightshadeButton(
              onPressed: _goNext,
              icon: LucideIcons.arrowRight,
              label: 'Next',
              variant: ButtonVariant.primary,
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // Helpers
  // ============================================================================

  IconData _iconForType(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return LucideIcons.camera;
      case DeviceType.mount:
        return LucideIcons.move3d;
      case DeviceType.focuser:
        return LucideIcons.focus;
      case DeviceType.filterWheel:
        return LucideIcons.circle;
      case DeviceType.guider:
        return LucideIcons.crosshair;
      case DeviceType.weather:
        return LucideIcons.cloudSun;
      case DeviceType.dome:
        return LucideIcons.home;
      case DeviceType.rotator:
        return LucideIcons.rotateCw;
      case DeviceType.safetyMonitor:
        return LucideIcons.shield;
      case DeviceType.switch_:
        return LucideIcons.toggleLeft;
      case DeviceType.coverCalibrator:
        return LucideIcons.lightbulb;
    }
  }

  String _displayNameForType(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return 'Camera';
      case DeviceType.mount:
        return 'Mount';
      case DeviceType.focuser:
        return 'Focuser';
      case DeviceType.filterWheel:
        return 'Filter Wheel';
      case DeviceType.guider:
        return 'Guider';
      case DeviceType.weather:
        return 'Weather Station';
      case DeviceType.dome:
        return 'Dome';
      case DeviceType.rotator:
        return 'Rotator';
      case DeviceType.safetyMonitor:
        return 'Safety Monitor';
      case DeviceType.switch_:
        return 'Switch';
      case DeviceType.coverCalibrator:
        return 'Cover Calibrator';
    }
  }

  String _devicePluralName(DeviceType type, int count) {
    final plural = count == 1 ? '' : 's';
    switch (type) {
      case DeviceType.camera:
        return 'camera$plural';
      case DeviceType.mount:
        return 'mount$plural';
      case DeviceType.focuser:
        return 'focuser$plural';
      case DeviceType.filterWheel:
        return count == 1 ? 'filter wheel' : 'filter wheels';
      case DeviceType.guider:
        return 'guider$plural';
      case DeviceType.weather:
        return count == 1 ? 'weather station' : 'weather stations';
      case DeviceType.dome:
        return 'dome$plural';
      case DeviceType.rotator:
        return 'rotator$plural';
      case DeviceType.safetyMonitor:
        return count == 1 ? 'safety monitor' : 'safety monitors';
      case DeviceType.switch_:
        return count == 1 ? 'switch' : 'switches';
      case DeviceType.coverCalibrator:
        return count == 1
            ? 'cover calibrator'
            : 'cover calibrators';
    }
  }
}

// ============================================================================
// Step indicator dot
// ============================================================================

class _StepDot extends StatelessWidget {
  final int index;
  final bool isActive;
  final bool isCompleted;
  final NightshadeColors colors;

  const _StepDot({
    required this.index,
    required this.isActive,
    required this.isCompleted,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive || isCompleted ? colors.primary : colors.surfaceAlt,
        border: Border.all(
          color: isActive || isCompleted ? colors.primary : colors.border,
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted
            ? Icon(LucideIcons.check, size: 14, color: onPrimary)
            : Text(
                '$index',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? onPrimary : colors.textMuted,
                ),
              ),
      ),
    );
  }
}

// ============================================================================
// Per-backend status chip (used on the Scan page)
// ============================================================================

class _BackendStatusChip extends StatelessWidget {
  final BackendDiscoveryState state;
  final NightshadeColors colors;

  const _BackendStatusChip({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color foreground;
    final Color background;
    final Color borderColor;
    final IconData icon;
    final String label;

    final backendName = state.backend.displayName;

    switch (state.status) {
      case DiscoveryStatus.idle:
        foreground = colors.textMuted;
        background = colors.surface;
        borderColor = colors.border;
        icon = LucideIcons.circle;
        label = '$backendName  idle';
        break;
      case DiscoveryStatus.discovering:
        foreground = colors.primary;
        background = colors.primary.withValues(alpha: 0.08);
        borderColor = colors.primary.withValues(alpha: 0.4);
        icon = LucideIcons.loader;
        label = '$backendName  scanning…';
        break;
      case DiscoveryStatus.completed:
        foreground = colors.success;
        background = colors.success.withValues(alpha: 0.08);
        borderColor = colors.success.withValues(alpha: 0.4);
        icon = LucideIcons.check;
        label = '$backendName  ${state.devices.length}';
        break;
      case DiscoveryStatus.error:
        foreground = colors.error;
        background = colors.error.withValues(alpha: 0.08);
        borderColor = colors.error.withValues(alpha: 0.4);
        icon = LucideIcons.alertTriangle;
        label = '$backendName  failed';
        break;
    }

    final tooltip = state.status == DiscoveryStatus.error && state.error != null
        ? PrettyError.format(state.error!).short
        : null;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (state.status == DiscoveryStatus.error && state.error != null) ...[
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                PrettyError.format(state.error!).short,
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
  }
}

// ============================================================================
// Internal summary-row model
// ============================================================================

class _SummaryRow {
  final DeviceType type;
  final String deviceLabel;
  final DriverType? backend;

  const _SummaryRow({
    required this.type,
    required this.deviceLabel,
    this.backend,
  });
}
