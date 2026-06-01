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

part 'equipment_screen/layout_rail.dart';
part 'equipment_screen/progress_dashboard.dart';
part 'equipment_screen/sidebar_onboarding.dart';

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

/// Whether the right-hand status rail (System Health + Ready-to-image) is
/// collapsed to an icon strip. Desktop-only; the rail itself is suppressed
/// below [_railBreakpoint] in favor of stacked collapsed bars.
final equipmentStatusRailCollapsedProvider =
    StateProvider<bool>((ref) => false);

/// Signature of the device-mismatch set the user last dismissed (✕). The
/// banner re-appears only when the *set* of mismatched devices changes (so a
/// genuinely new mismatch is never silently hidden). Session-scoped: cleared on
/// app restart, matching the "dismiss for this session" contract.
final dismissedMismatchSignatureProvider =
    StateProvider<String?>((ref) => null);

// ============================================================================
// Constants for sidebar dimensions
// ============================================================================

const double _sidebarExpandedWidth = 240.0;
const double _sidebarMinWidth = 200.0;
const double _sidebarMaxWidth = 350.0;
const double _sidebarCollapsedWidth = 48.0;

/// Width of the status rail and its collapsed icon strip.
const double _statusRailWidth = 320.0;
const double _statusRailCollapsedWidth = 44.0;

/// Minimum *main-column* width (sidebar already excluded) at which the status
/// rail is shown side-by-side with the device cards. Below this the supporting
/// panels fall back to stacked collapsed bars so the cards never get pinched
/// between two side panels.
const double _railBreakpoint = 900.0;

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
            // Rail is desktop-only. On mobile the supporting panels stack as
            // collapsed bars instead of competing with a second side panel.
            allowRail: !isMobile,
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

    if (mounted) {
      context.showInfoSnackBar('Connecting devices...');
    }
    // The connect path uses the profile's persisted device ids and does not
    // depend on a fresh scan (DEV-P1-7); startup discovery already populated
    // the "Available Devices" sidebar, and device topology rarely changes
    // mid-session. So refresh the sidebar in the background with a long
    // freshness window rather than blocking the connect on a redundant
    // rescan — the user clicked "Connect all", not "Scan". (Without the long
    // maxAge the default 30s window forces a full rescan every time the user
    // spends more than half a minute setting up before connecting.)
    unawaited(
      discoveryNotifier.discoverIfNeeded(maxAge: const Duration(minutes: 10)),
    );

    // DEV-P1-5: parallel connect with per-device progress. We push each
    // event into [deviceConnectionProgressProvider] so the per-device
    // chips can render live status, and we tally counts locally for the
    // post-sweep snackbar summary.
    progressNotifier.startSweep();

    int successCount = 0;
    int failCount = 0;
    final List<ConnectAllFailure> failures = [];

    try {
      await for (final event in deviceService.connectAllFromProfile(profile)) {
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
