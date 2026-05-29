import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'widgets/profile_sidebar.dart';
import 'widgets/connected_device_card.dart';
import 'widgets/discovery_panel.dart';
import 'widgets/equipment_health_panel.dart';
import 'widgets/equipment_readiness_panel.dart';
import 'dialogs/profile_editor_dialog.dart';
import 'tabs/settings_tab.dart';
import 'utils/connect_all_summary.dart';
import 'utils/driver_error_pretty.dart';
import 'utils/equipment_disconnect.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/equipment_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../sequencer/widgets/run_dashboard/recovery_banner.dart';

// ============================================================================
// Providers for equipment screen state
// ============================================================================

/// Provider for currently selected profile in the equipment screen
final selectedEquipmentProfileIdProvider = StateProvider<int?>((ref) {
  // Default to the active profile
  final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
  return activeProfile?.id;
});

/// Whether the profile sidebar is collapsed (icon-only mode)
final equipmentSidebarCollapsedProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// Constants for sidebar dimensions
// ============================================================================

const double _sidebarExpandedWidth = 240.0;
const double _sidebarMinWidth = 200.0;
const double _sidebarMaxWidth = 350.0;
const double _sidebarCollapsedWidth = 48.0;

// ============================================================================
// Equipment Screen
// ============================================================================

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  /// UI-P0-6: bumped on any profile mutation so delete-undo cannot race edits.
  int _profileMutationEpoch = 0;

  void _bumpProfileMutationEpoch() {
    _profileMutationEpoch++;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final profiles = ref.watch(sortedProfilesProvider);
    final selectedProfileId = ref.watch(selectedEquipmentProfileIdProvider);

    // Check for first-time user (no profiles)
    if (profiles.isEmpty) {
      return _FirstTimeOnboarding(
        colors: colors,
        onStartSetup: () => _showCreateProfileWizard(context),
        onManualSetup: _createEmptyProfile,
      );
    }

    // Get selected profile
    final selectedProfile = selectedProfileId != null
        ? profiles.where((p) => p.id == selectedProfileId).firstOrNull
        : null;

    final sidebarCollapsed = ref.watch(equipmentSidebarCollapsedProvider);

    return ContextualTourPrompt(
      screenId: 'equipment',
      tourCategory: TutorialCategory.equipmentTour,
      title: 'Equipment Tour',
      description:
          'Learn how to connect and manage your astrophotography equipment.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile =
              constraints.maxWidth < NightshadeTokens.breakpointTablet;

          final profileSidebar = ProfileSidebar(
            selectedProfileId: selectedProfileId,
            onProfileSelected: (id) {
              ref.read(selectedEquipmentProfileIdProvider.notifier).state = id;
            },
            onCreateProfile: () => _showProfileEditor(context, null),
            onEditProfile: (profile) => _showProfileEditor(context, profile),
            onConnectAll: _connectAllDevices,
            onDisconnectAll: _disconnectAllDevices,
            onSetDefault: _setDefaultProfile,
            onDuplicateProfile: _duplicateProfile,
            onDeleteProfile: _deleteProfile,
            onReorderProfiles: _reorderProfiles,
            onCollapse: isMobile
                ? null
                : () {
                    ref.read(equipmentSidebarCollapsedProvider.notifier).state =
                        true;
                  },
          );

          final mainColumn = _EquipmentMainColumn(
            selectedProfile: selectedProfile,
            onSettings: () => _showSettings(context),
            onProfileTap: isMobile
                ? () => _showProfilePickerSheet(context, profileSidebar)
                : null,
            onConnectAll: _connectAllDevices,
            onEditProfile: (profile) => _showProfileEditor(context, profile),
          );

          if (isMobile) {
            return FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: mainColumn,
            );
          }

          return FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Row(
              children: [
                _CollapsibleSidebar(
                  isCollapsed: sidebarCollapsed,
                  onToggle: () {
                    ref.read(equipmentSidebarCollapsedProvider.notifier).state =
                        !sidebarCollapsed;
                  },
                  child: profileSidebar,
                ),
                Expanded(child: mainColumn),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showProfilePickerSheet(BuildContext context, Widget profileSidebar) {
    final colors = NightshadeColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NightshadeTokens.radiusLg)),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: profileSidebar),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Profile Operations
  // ============================================================================

  Future<void> _showProfileEditor(
      BuildContext context, EquipmentProfileModel? profile) async {
    await ProfileEditorDialog.show(context, profile: profile);
  }

  Future<void> _createEmptyProfile() async {
    try {
      final profileService = ref.read(profileServiceProvider);
      final profileId = await profileService.createProfile('My Equipment');
      _bumpProfileMutationEpoch();
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = profileId;
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to create profile: $e');
      }
    }
  }

  void _showCreateProfileWizard(BuildContext context) {
    // Onboarding & First-Light IA (C13): the empty-state "Start Setup" now
    // routes to the single onboarding spine rather than opening a bespoke
    // in-screen wizard dialog. The `/onboarding` route owns the full
    // Scan → Select → Save flow, persists the first profile, and hands off
    // to first light on completion — keeping a single linear first-run path
    // instead of two competing setup experiences. The manual fallback
    // (`_createEmptyProfile`) is unchanged for users who'd rather build a
    // profile by hand.
    context.go('/onboarding');
  }

  Future<void> _setDefaultProfile(EquipmentProfileModel profile) async {
    try {
      await ref
          .read(equipmentProfilesProvider.notifier)
          .setDefaultProfile(profile.id, makeActive: true);
      if (mounted) {
        context.showSuccessSnackBar('Default profile set');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to set default: $e');
      }
    }
  }

  Future<void> _duplicateProfile(int profileId) async {
    try {
      final profileService = ref.read(profileServiceProvider);
      // Get the source profile to derive a name for the copy
      final profiles = ref.read(sortedProfilesProvider);
      final sourceProfile = profiles.firstWhere(
        (p) => p.id == profileId,
        orElse: () => profiles.first,
      );
      final newName = '${sourceProfile.name} (Copy)';
      final newId = await profileService.duplicateProfile(profileId, newName);
      _bumpProfileMutationEpoch();
      // Select the newly duplicated profile
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = newId;
      if (mounted) {
        context.showSuccessSnackBar('Profile duplicated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to duplicate: $e');
      }
    }
  }

  Future<void> _deleteProfile(int profileId) async {
    try {
      final profileService = ref.read(profileServiceProvider);
      final dao = ref.read(equipmentProfilesDaoProvider);
      final deletedProfile = await dao.getProfileById(profileId);
      if (deletedProfile == null) {
        throw StateError('Profile $profileId no longer exists');
      }
      final deletedProfileJson =
          await profileService.exportProfileToJson(profileId);
      await profileService.deleteProfile(profileId);
      final epochAtDelete = _profileMutationEpoch;
      _bumpProfileMutationEpoch();

      // If we deleted the selected profile, select another one
      final selectedId = ref.read(selectedEquipmentProfileIdProvider);
      if (selectedId == profileId) {
        final profiles = ref.read(sortedProfilesProvider);
        final remainingProfiles =
            profiles.where((p) => p.id != profileId).toList();
        if (remainingProfiles.isNotEmpty) {
          ref.read(selectedEquipmentProfileIdProvider.notifier).state =
              remainingProfiles.first.id;
        } else {
          ref.read(selectedEquipmentProfileIdProvider.notifier).state = null;
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted "${deletedProfile.name}"'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                unawaited(_restoreDeletedProfile(
                  deletedProfileJson,
                  wasActive: deletedProfile.isActive,
                  epochAtDelete: epochAtDelete,
                ));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to delete: $e');
      }
    }
  }

  Future<void> _reorderProfiles(int oldIndex, int newIndex) async {
    try {
      final dao = ref.read(equipmentProfilesDaoProvider);
      final profiles = ref.read(sortedProfilesProvider);

      // Build reordered list
      final reordered = [...profiles];
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);

      // Update sort_order for all affected profiles
      for (int i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          final profile = await dao.getProfileById(reordered[i].id!);
          if (profile != null) {
            await dao.updateProfile(profile.copyWith(sortOrder: i));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to reorder: $e');
      }
    }
  }

  Future<void> _restoreDeletedProfile(
    String exportedProfileJson, {
    required bool wasActive,
    required int epochAtDelete,
  }) async {
    if (epochAtDelete != _profileMutationEpoch) {
      if (mounted) {
        context.showWarningSnackBar(
          'Undo expired — profiles changed after the delete.',
        );
      }
      return;
    }

    try {
      final profileService = ref.read(profileServiceProvider);
      final dao = ref.read(equipmentProfilesDaoProvider);
      final restoredId =
          await profileService.importProfileFromJson(exportedProfileJson);
      _bumpProfileMutationEpoch();
      if (wasActive) {
        await dao.setActiveProfile(restoredId);
      }
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = restoredId;
      if (mounted) {
        context.showSuccessSnackBar('Profile restored');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to restore profile: $e');
      }
    }
  }

  // ============================================================================
  // Device Connection Operations
  // ============================================================================

  Future<void> _connectAllDevices(EquipmentProfileModel profile) async {
    final deviceService = ref.read(deviceServiceProvider);
    final discoveryNotifier = ref.read(unifiedDiscoveryProvider.notifier);
    final progressNotifier =
        ref.read(deviceConnectionProgressProvider.notifier);

    // Count how many devices we need to connect
    final deviceIds = [
      profile.cameraId,
      profile.mountId,
      profile.focuserId,
      profile.filterWheelId,
      profile.guiderId,
      profile.rotatorId,
      profile.domeId,
      profile.weatherId,
      profile.coverCalibratorId,
    ].where((id) => id != null && id.isNotEmpty).toList();

    if (deviceIds.isEmpty) {
      if (mounted) {
        context.showWarningSnackBar('No devices configured in this profile');
      }
      return;
    }

    // Keep the cached-discovery refresh: this populates the discovery
    // panel sidebar, which is independent of the connect path. With
    // DEV-P1-7 the connect calls themselves no longer depend on a fresh
    // discovery, but the UI's "Available Devices" list still does.
    if (mounted) {
      context.showInfoSnackBar('Connecting devices...');
    }
    await discoveryNotifier.discoverIfNeeded();

    // DEV-P1-5: parallel connect with per-device progress. We push each
    // event into [deviceConnectionProgressProvider] so the per-device
    // chips can render live status, and we tally counts locally for the
    // post-sweep snackbar summary.
    progressNotifier.startSweep();

    int successCount = 0;
    int failCount = 0;
    final List<ConnectAllFailure> failures = [];

    try {
      await for (final event
          in deviceService.connectAllFromProfile(profile)) {
        progressNotifier.record(event);
        if (event.status == DeviceConnectProgressStatus.connected) {
          successCount++;
        } else if (event.status == DeviceConnectProgressStatus.failed) {
          failCount++;
          final failure = ConnectAllFailure.fromProgress(event);
          failures.add(failure);
          ref.read(loggingServiceProvider).warning(
            'Connect All failed for ${event.deviceType} (${event.deviceId}): '
            '${event.errorMessage ?? event.error}',
            source: 'EquipmentScreen',
            fields: {
              'deviceType': event.deviceType,
              'deviceId': event.deviceId,
              if (event.error != null) 'error': event.error.toString(),
            },
          );
        }
      }
    } finally {
      progressNotifier.endSweep();
    }

    // Try to auto-connect safety monitor if available. The profile may
    // not list a safety monitor id, but the unified discovery panel may
    // have surfaced one — connect to that as a best-effort.
    try {
      final safetyState = ref.read(safetyMonitorStateProvider);
      if (safetyState.connectionState == DeviceConnectionState.disconnected) {
        final safetyMonitors = ref.read(unifiedSafetyMonitorsProvider);
        if (safetyMonitors.isNotEmpty) {
          final safetyId = safetyMonitors.first.activeDeviceId;
          progressNotifier.record(DeviceConnectProgress(
            deviceType: 'safety monitor',
            deviceId: safetyId,
            status: DeviceConnectProgressStatus.connecting,
          ));
          try {
            await deviceService.connectSafetyMonitor(safetyId);
            successCount++;
            progressNotifier.record(DeviceConnectProgress(
              deviceType: 'safety monitor',
              deviceId: safetyId,
              status: DeviceConnectProgressStatus.connected,
            ));
          } catch (e) {
            failCount++;
            failures.add(ConnectAllFailure(
              deviceType: 'safety monitor',
              message: PrettyError.format(e.toString()).short,
            ));
            ref.read(loggingServiceProvider).warning(
              'Connect All failed for safety monitor: $e',
              source: 'EquipmentScreen',
            );
            progressNotifier.record(DeviceConnectProgress(
              deviceType: 'safety monitor',
              deviceId: safetyId,
              status: DeviceConnectProgressStatus.failed,
              error: e,
              errorMessage: e.toString(),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Error during connect all: $e');
    }

    if (!mounted) return;

    final message = formatConnectAllSnackBar(
      successCount: successCount,
      failCount: failCount,
      failures: failures,
    );
    if (successCount > 0 && failCount == 0) {
      context.showSuccessSnackBar(message);
    } else if (successCount > 0 && failCount > 0) {
      context.showWarningSnackBar(message);
    } else if (failCount > 0) {
      context.showErrorSnackBar(message);
    }
  }

  Future<void> _disconnectAllDevices() async {
    final summary = await runEquipmentDisconnectAll(ref);

    if (!mounted) return;

    for (final failure in summary.failures) {
      context.showErrorSnackBar('Failed to disconnect $failure');
    }

    if (summary.successCount > 0 && summary.failures.isEmpty) {
      context.showSuccessSnackBar('All devices disconnected');
    }
  }

  // ============================================================================
  // Settings
  // ============================================================================

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const NightshadeDialog(
        title: 'Equipment Settings',
        icon: LucideIcons.settings,
        width: 700,
        height: 500,
        // EquipmentSettingsTab manages its own scrolling per-section, so the
        // dialog scaffold must not double-wrap it in a SingleChildScrollView.
        scrollableBody: false,
        bodyPadding: EdgeInsets.zero,
        child: EquipmentSettingsTab(),
      ),
    );
  }
}

// ============================================================================
// Dashboard Header Widget
// ============================================================================

class _DashboardHeader extends StatelessWidget {
  final String? profileName;
  final VoidCallback onSettings;
  final VoidCallback? onProfileTap;

  const _DashboardHeader({
    required this.profileName,
    required this.onSettings,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = onProfileTap != null;
    final horizontalPadding = isMobile ? 12.0 : 20.0;

    Widget profileTitle;
    if (profileName != null) {
      profileTitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.layers, size: 16, color: colors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              profileName!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (isMobile) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: colors.textMuted),
          ],
        ],
      );
    } else {
      profileTitle = Text(
        'Select a profile',
        style: TextStyle(
          fontSize: 16,
          color: colors.textMuted,
        ),
      );
    }

    if (onProfileTap != null) {
      profileTitle = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onProfileTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: profileTitle,
            ),
          ),
        ),
      );
    }

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: profileTitle),
          const SizedBox(width: 8),
          // Wave 4 Recovery Mode — sequencer status LED. Always visible so
          // an operator scanning the Equipment screen knows at a glance
          // whether a sequence is running, paused, or recovering. Pulses
          // red in recovering state.
          const SequencerStatusLed(showLabel: true),
          const SizedBox(width: 12),
          // Connection status summary
          _ConnectionStatusSummary(),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(LucideIcons.settings, size: 18),
            tooltip: 'Equipment Settings',
            color: colors.textMuted,
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Polar alignment entry (Equipment discoverability)
// ============================================================================

/// Compact shortcut so pre-flight hints that mention Equipment can point
/// somewhere real. Shown when the active profile has a mount assigned.
class _PolarAlignmentShortcut extends ConsumerWidget {
  const _PolarAlignmentShortcut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final hasMount = profile?.mountId != null && profile!.mountId!.isNotEmpty;
    if (!hasMount) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(LucideIcons.compass, color: colors.warning, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Polar Alignment',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Three-point or all-sky alignment with plate solving.',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              NightshadeButton(
                label: 'Open',
                icon: LucideIcons.arrowRight,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => context.push('/polar-alignment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Main column (shared by desktop + mobile)
// ============================================================================

class _EquipmentMainColumn extends StatelessWidget {
  final EquipmentProfileModel? selectedProfile;
  final VoidCallback onSettings;
  final VoidCallback? onProfileTap;
  final void Function(EquipmentProfileModel) onConnectAll;
  final void Function(EquipmentProfileModel) onEditProfile;

  const _EquipmentMainColumn({
    required this.selectedProfile,
    required this.onSettings,
    required this.onConnectAll,
    required this.onEditProfile,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const RunDashboardRecoveryBanner(),
        _DashboardHeader(
          profileName: selectedProfile?.name,
          onSettings: onSettings,
          onProfileTap: onProfileTap,
        ),
        const _ProfileMismatchBanner(),
        const _ConnectAllProgressStrip(),
        const EquipmentHealthPanel(),
        // C13/C14: the actionable "ready to image" checklist. Sits above the
        // device dashboard so the readiness summary and its per-item Fix
        // deep-links are the first thing an operator sees on the Equipment
        // screen. Wrapped in a loose Flexible with an internal scroll so on a
        // short screen it yields height to the device dashboard (and scrolls
        // its own content) instead of overflowing the column.
        const Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: EquipmentReadinessPanel(),
            ),
          ),
        ),
        const _PolarAlignmentShortcut(),
        Expanded(
          child: _DeviceDashboard(
            profile: selectedProfile,
            onConnectAll: onConnectAll,
            onEditProfile: onEditProfile,
          ),
        ),
        const DiscoveryPanel(),
      ],
    );
  }
}

// ============================================================================
// DEV-P1-5: Connect-All per-device progress strip
// ============================================================================

/// Renders one chip per device-type tracked by
/// [deviceConnectionProgressProvider]. Each chip shows the device icon, a
/// status indicator (idle/connecting/connected/failed), and a tooltip with
/// the backend error message when the connect attempt failed.
///
/// The strip hides itself completely when no sweep has been run yet (the
/// provider state is empty). After a sweep completes the chips remain
/// visible until [DeviceConnectionProgressNotifier.clear] is called, so the
/// user can review what failed without having to re-run "Connect All".
class _ConnectAllProgressStrip extends ConsumerWidget {
  const _ConnectAllProgressStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(deviceConnectionProgressProvider);

    if (state.byDeviceType.isEmpty) {
      return const SizedBox.shrink();
    }

    // Stable canonical ordering matching the connectAllFromProfile dispatch
    // order so chips don't jitter between rebuilds.
    const order = <String>[
      'camera',
      'mount',
      'focuser',
      'filter wheel',
      'guider',
      'rotator',
      'dome',
      'weather station',
      'safety monitor',
      'cover calibrator',
    ];

    final entries = <DeviceConnectProgress>[
      for (final type in order)
        if (state.byDeviceType.containsKey(type)) state.byDeviceType[type]!,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              state.isSweeping ? 'Connecting…' : 'Connect All result',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          for (final event in entries)
            _ConnectAllProgressChip(event: event, colors: colors),
          if (!state.isSweeping)
            NightshadeButton(
              label: 'Clear',
              size: ButtonSize.small,
              variant: ButtonVariant.ghost,
              onPressed: () => ref
                  .read(deviceConnectionProgressProvider.notifier)
                  .clear(),
            ),
        ],
      ),
    );
  }
}

class _ConnectAllProgressChip extends StatelessWidget {
  final DeviceConnectProgress event;
  final NightshadeColors colors;

  const _ConnectAllProgressChip({
    required this.event,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _statusVisuals(event.status, colors);
    final iconForType = _iconForDeviceType(event.deviceType);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForType, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            event.deviceType,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          if (event.status == DeviceConnectProgressStatus.connecting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (event.status == DeviceConnectProgressStatus.failed &&
        event.errorMessage != null) {
      return Tooltip(
        message: event.errorMessage!,
        waitDuration: const Duration(milliseconds: 200),
        child: chip,
      );
    }
    return chip;
  }

  static (IconData, Color, String) _statusVisuals(
      DeviceConnectProgressStatus status, NightshadeColors colors) {
    switch (status) {
      case DeviceConnectProgressStatus.connecting:
        return (LucideIcons.loader, colors.warning, 'Connecting');
      case DeviceConnectProgressStatus.connected:
        return (LucideIcons.checkCircle, colors.success, 'Connected');
      case DeviceConnectProgressStatus.failed:
        return (LucideIcons.xCircle, colors.error, 'Failed');
    }
  }

  static IconData _iconForDeviceType(String deviceType) {
    switch (deviceType) {
      case 'camera':
        return LucideIcons.camera;
      case 'mount':
        return LucideIcons.compass;
      case 'focuser':
        return LucideIcons.focus;
      case 'filter wheel':
        return LucideIcons.circle;
      case 'guider':
        return LucideIcons.crosshair;
      case 'rotator':
        return LucideIcons.rotateCw;
      case 'dome':
        return LucideIcons.home;
      case 'weather station':
        return LucideIcons.cloudSun;
      case 'safety monitor':
        return LucideIcons.shieldCheck;
      case 'cover calibrator':
        return LucideIcons.lamp;
      default:
        return LucideIcons.circle;
    }
  }
}

// ============================================================================
// Connection Status Summary Widget
// ============================================================================

class _ConnectionStatusSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final domeState = ref.watch(domeStateProvider);
    final weatherState = ref.watch(weatherStateProvider);
    final safetyMonitorState = ref.watch(safetyMonitorStateProvider);
    final switchState = ref.watch(switchStateProvider);
    final coverCalibratorState = ref.watch(coverCalibratorStateProvider);

    final connectionStates = [
      cameraState.connectionState,
      mountState.connectionState,
      focuserState.connectionState,
      filterWheelState.connectionState,
      guiderState.connectionState,
      rotatorState.connectionState,
      domeState.connectionState,
      weatherState.connectionState,
      safetyMonitorState.connectionState,
      switchState.connectionState,
      coverCalibratorState.connectionState,
    ];

    final connectedCount = connectionStates
        .where((state) => state == DeviceConnectionState.connected)
        .length;

    if (connectedCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: NightshadeDecorations.statusChip(
        colors.success,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.success,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$connectedCount connected',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.success,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Device Dashboard Widget
// ============================================================================

class _DeviceDashboard extends ConsumerWidget {
  final EquipmentProfileModel? profile;

  /// Invoked when the empty-state primary CTA is pressed. Required so the
  /// "Connect Devices" button is discoverable directly from the empty state
  /// itself rather than only from the (potentially collapsed) sidebar.
  /// See audit §4.6.
  final void Function(EquipmentProfileModel) onConnectAll;

  /// Invoked when the empty-state secondary CTA is pressed in the
  /// "no devices assigned" branch. Routes to the profile editor so the user
  /// can attach equipment without hunting through the sidebar menu.
  final void Function(EquipmentProfileModel) onEditProfile;

  const _DeviceDashboard({
    this.profile,
    required this.onConnectAll,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    // Watch device connection states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final domeState = ref.watch(domeStateProvider);
    final weatherState = ref.watch(weatherStateProvider);
    final safetyMonitorState = ref.watch(safetyMonitorStateProvider);
    final coverCalibratorState = ref.watch(coverCalibratorStateProvider);

    // Build list of connected device cards
    final connectedCards = <Widget>[];

    if (cameraState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.cameraCard,
        type: ConnectedDeviceType.camera,
      ));
    }

    if (mountState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.mountCard,
        type: ConnectedDeviceType.mount,
      ));
    }

    if (focuserState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.focuser,
      ));
    }

    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.filterWheel,
      ));
    }

    if (guiderState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.guider,
      ));
    }

    if (rotatorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.rotator,
      ));
    }

    if (domeState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.dome,
      ));
    }

    if (weatherState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.weather,
      ));
    }

    if (safetyMonitorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.safetyMonitor,
      ));
    }

    if (coverCalibratorState.connectionState ==
        DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.coverCalibrator,
      ));
    }

    // No profile selected state
    if (profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.layoutGrid, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Select a profile to view devices',
              style: TextStyle(
                fontSize: 16,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // No devices connected state - show prompt to connect
    if (connectedCards.isEmpty) {
      // Check if the profile has any devices assigned (profile is guaranteed non-null here)
      final p = profile!;
      final hasDevicesAssigned =
          (p.cameraId != null && p.cameraId!.isNotEmpty) ||
              (p.mountId != null && p.mountId!.isNotEmpty) ||
              (p.focuserId != null && p.focuserId!.isNotEmpty) ||
              (p.filterWheelId != null && p.filterWheelId!.isNotEmpty) ||
              (p.guiderId != null && p.guiderId!.isNotEmpty) ||
              (p.rotatorId != null && p.rotatorId!.isNotEmpty) ||
              (p.domeId != null && p.domeId!.isNotEmpty) ||
              (p.weatherId != null && p.weatherId!.isNotEmpty) ||
              (p.coverCalibratorId != null && p.coverCalibratorId!.isNotEmpty);

      // Audit §4.6: surface a primary CTA in the empty state itself.
      // Previously the copy advised the user to find "Connect All" in the
      // sidebar — which lives inside the per-profile menu and is undiscoverable
      // when the sidebar is collapsed.
      if (hasDevicesAssigned) {
        // Profile has devices but none connected
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.unplug, size: 48, color: colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No devices connected',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect the equipment assigned to this profile.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              NightshadeButton(
                label: 'Connect Devices',
                icon: LucideIcons.plug,
                variant: ButtonVariant.primary,
                onPressed: () => onConnectAll(p),
              ),
            ],
          ),
        );
      } else {
        // Profile has no devices assigned
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plusCircle, size: 48, color: colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No devices assigned',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add equipment to this profile to begin, or discover devices below.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              NightshadeButton(
                label: 'Edit Profile',
                icon: LucideIcons.pencil,
                variant: ButtonVariant.primary,
                onPressed: () => onEditProfile(p),
              ),
            ],
          ),
        );
      }
    }

    // Show connected device cards in a responsive grid
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: connectedCards,
      ),
    );
  }
}

// ============================================================================
// Collapsible Sidebar Widget
// ============================================================================

class _CollapsibleSidebar extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsibleSidebar({
    required this.isCollapsed,
    required this.onToggle,
    required this.child,
  });

  @override
  State<_CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<_CollapsibleSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;
  double _currentExpandedWidth = _sidebarExpandedWidth;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _updateAnimation();
    if (!widget.isCollapsed) {
      _animationController.value = 1.0;
    }
  }

  void _updateAnimation() {
    _widthAnimation = Tween<double>(
      begin: _sidebarCollapsedWidth,
      end: _currentExpandedWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_CollapsibleSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCollapsed != widget.isCollapsed) {
      if (widget.isCollapsed) {
        _animationController.reverse();
      } else {
        _updateAnimation();
        _animationController.forward();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        final width = _widthAnimation.value;
        final isEffectivelyCollapsed = width < _sidebarCollapsedWidth + 20;

        if (isEffectivelyCollapsed) {
          // Collapsed state - show icon button strip
          return Container(
            width: _sidebarCollapsedWidth,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                right: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Show Profiles',
                  child: IconButton(
                    icon: Icon(
                      LucideIcons.layers,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    onPressed: widget.onToggle,
                  ),
                ),
              ],
            ),
          );
        }

        // Expanded state - show resizable panel with content
        return SizedBox(
          width: width,
          child: ResizablePanel(
            initialWidth: width,
            minWidth: _sidebarMinWidth,
            maxWidth: _sidebarMaxWidth,
            side: ResizeSide.right,
            onWidthChanged: (newWidth) {
              setState(() {
                _currentExpandedWidth = newWidth;
                _updateAnimation();
              });
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ============================================================================
// First-Time User Onboarding
// ============================================================================

class _FirstTimeOnboarding extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onStartSetup;
  final VoidCallback onManualSetup;

  const _FirstTimeOnboarding({
    required this.colors,
    required this.onStartSetup,
    required this.onManualSetup,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.moon,
              size: NightshadeTokens.iconXl,
              color: colors.primary,
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            Text(
              'Welcome to Nightshade',
              style: NightshadeTypography.h2.copyWith(
                color: colors.textPrimary,
              ),
            ),

            const SizedBox(height: NightshadeTokens.spaceSm),

            Text(
              "Let's set up your first equipment profile",
              style: NightshadeTypography.body.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 40),

            // Setup steps
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _SetupStep(
                    number: '1',
                    text: "We'll scan for connected equipment",
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  _SetupStep(
                    number: '2',
                    text: 'Select the devices you want to use',
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  _SetupStep(
                    number: '3',
                    text: 'Save as a profile for one-click connection',
                    colors: colors,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label: 'Start Setup',
                icon: LucideIcons.arrowRight,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
                onPressed: onStartSetup,
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: onManualSetup,
                label: "I'll do it manually",
                variant: ButtonVariant.outline,
                size: ButtonSize.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final String number;
  final String text;
  final NightshadeColors colors;

  const _SetupStep({
    required this.number,
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: NightshadeDecorations.kpiBadge(
            colors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMismatchBanner extends ConsumerWidget {
  const _ProfileMismatchBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) return const SizedBox.shrink();

    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final domeState = ref.watch(domeStateProvider);
    final weatherState = ref.watch(weatherStateProvider);
    final safetyMonitorState = ref.watch(safetyMonitorStateProvider);
    final switchState = ref.watch(switchStateProvider);
    final coverCalibratorState = ref.watch(coverCalibratorStateProvider);

    final mismatches = <String>[];

    void check(String? connectedId, String? profileId, String deviceName) {
      if (connectedId != null &&
          connectedId.isNotEmpty &&
          profileId != null &&
          profileId.isNotEmpty &&
          connectedId != profileId) {
        mismatches.add(deviceName);
      }
    }

    check(cameraState.deviceId, activeProfile.cameraId, 'Camera');
    check(mountState.deviceId, activeProfile.mountId, 'Mount');
    check(focuserState.deviceId, activeProfile.focuserId, 'Focuser');
    check(
        filterWheelState.deviceId, activeProfile.filterWheelId, 'Filter Wheel');
    check(guiderState.deviceId, activeProfile.guiderId, 'Guider');
    check(rotatorState.deviceId, activeProfile.rotatorId, 'Rotator');
    check(domeState.deviceId, activeProfile.domeId, 'Dome');
    check(weatherState.deviceId, activeProfile.weatherId, 'Weather Station');
    check(safetyMonitorState.deviceId, activeProfile.safetyMonitorId,
        'Safety Monitor');
    check(switchState.deviceId, activeProfile.switchId, 'Switch');
    check(coverCalibratorState.deviceId, activeProfile.coverCalibratorId,
        'Cover Calibrator');

    if (mismatches.isEmpty) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: colors.warning.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: colors.warning, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Device Mismatch: The connected ${mismatches.join(", ")} do not match the assignments in active profile "${activeProfile.name}".',
              style: TextStyle(
                fontSize: 12,
                color: colors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
