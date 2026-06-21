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
import 'widgets/switch_control_card.dart';
import 'dialogs/profile_editor_dialog.dart';
import 'tabs/settings_tab.dart';
import 'utils/connect_all_summary.dart';
import 'utils/driver_error_pretty.dart';
import 'utils/equipment_disconnect.dart';
import '../../localization/nightshade_localizations.dart';
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
  /// Bumped on any profile mutation so delete-undo cannot race edits.
  int _profileMutationEpoch = 0;

  void _bumpProfileMutationEpoch() {
    _profileMutationEpoch++;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final profiles = ref.watch(sortedProfilesProvider);
    final selectedProfileId = ref.watch(selectedEquipmentProfileIdProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);

    // Check for first-time user (no profiles).
    //
    // REMOTE (slave) mode: never show the local first-run onboarding. A slave
    // controls the master's hardware and its profiles hydrate from the host's
    // SQLite over /api/profiles; before they arrive (or if the host genuinely
    // has none yet) the slave still renders the dashboard + discovery so the
    // operator can see connected devices and act — not a "create your first
    // profile" wizard that would write the slave's own empty DB. Local/host and
    // mobile first-run onboarding is unchanged (isRemoteMode false there).
    if (profiles.isEmpty && !isRemoteMode) {
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
      title: context.l10n.text('equipmentTourTitle'),
      description: context.l10n.text('equipmentTourDescription'),
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Structure decision is device-class, not viewport width: a phone
          // held in landscape reports a tablet-ish width (~932 px) but is still
          // a phone and must take the stacked mobile layout — the desktop
          // profile sidebar + rail would overflow its short height. On desktop
          // `Responsive.isPhone` falls back to live width, so narrowing a
          // window still collapses to the mobile column as before. Genuine
          // tablets keep the desktop split.
          final isMobile = Responsive.isPhone(context) ||
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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline2),
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
        context.showErrorSnackBar(
          context.l10n
              .text('equipmentCreateProfileFailed', params: {'error': '$e'}),
        );
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
      // HOST ACTIVATION RUST WRITE-THROUGH: the notifier's local branch wrote
      // SQLite; the GUI path bypasses the REST handleLoadProfile write-through,
      // so push the now-active profile into the native (Rust) executor store so
      // headless sequencing keeps a correct active-profile context. No-op /
      // skipped in remote mode (the host owns activation via REST loadProfile).
      if (profile.id != null && !ref.read(isRemoteModeProvider)) {
        await writeActiveProfileThroughToRustFromWidget(ref, profile.id!);
      }
      if (mounted) {
        context.showSuccessSnackBar(
          context.l10n.text('equipmentDefaultProfileSet'),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          context.l10n
              .text('equipmentSetDefaultFailed', params: {'error': '$e'}),
        );
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
        context.showSuccessSnackBar(
          context.l10n.text('equipmentProfileDuplicated'),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          context.l10n
              .text('equipmentDuplicateFailed', params: {'error': '$e'}),
        );
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
            content: Text(context.l10n.text('equipmentProfileDeleted',
                params: {'name': deletedProfile.name})),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: context.l10n.text('commonUndo'),
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
        context.showErrorSnackBar(
          context.l10n.text('equipmentDeleteFailed', params: {'error': '$e'}),
        );
      }
    }
  }

  Future<void> _reorderProfiles(int oldIndex, int newIndex) async {
    try {
      final profiles = ref.read(sortedProfilesProvider);

      // Build reordered list
      final reordered = [...profiles];
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);

      // Single notifier passthrough for both modes. On a slave this POSTs the
      // ordered id list to the host's dedicated reorder endpoint (writing the
      // slave's own empty DB would create phantom rows the host-poll erases);
      // locally it writes the DAO in one transaction. Only persisted profiles
      // carry an id, so a null filter keeps this safe.
      final orderedIds =
          reordered.map((m) => m.id).whereType<int>().toList(growable: false);
      await ref
          .read(equipmentProfilesProvider.notifier)
          .reorderProfiles(orderedIds);
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
        context.showSuccessSnackBar(
          context.l10n.text('equipmentProfileRestored'),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          context.l10n.text('equipmentRestoreFailed', params: {'error': '$e'}),
        );
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
        context.showWarningSnackBar(
          context.l10n.text('equipmentNoDevicesConfigured'),
        );
      }
      return;
    }

    if (mounted) {
      context.showInfoSnackBar('Connecting devices...');
    }
    // The connect path uses the profile's persisted device ids and does not
    // depend on a fresh scan; startup discovery already populated
    // the "Available Devices" sidebar, and device topology rarely changes
    // mid-session. So refresh the sidebar in the background with a long
    // freshness window rather than blocking the connect on a redundant
    // rescan — the user clicked "Connect all", not "Scan". (Without the long
    // maxAge the default 30s window forces a full rescan every time the user
    // spends more than half a minute setting up before connecting.)
    unawaited(
      discoveryNotifier.discoverIfNeeded(maxAge: const Duration(minutes: 10)),
    );

    // Parallel connect with per-device progress. We push each
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
      context.showErrorSnackBar(
        context.l10n
            .text('equipmentDisconnectFailed', params: {'device': failure}),
      );
    }

    if (summary.successCount > 0 && summary.failures.isEmpty) {
      context.showSuccessSnackBar(
        context.l10n.text('equipmentAllDevicesDisconnected'),
      );
    }
  }

  // ============================================================================
  // Settings
  // ============================================================================

  void _showSettings(BuildContext context) {
    // On a phone this becomes a full-screen route (settings is content-heavy);
    // on tablet/desktop it stays the familiar 700×500 dialog. The body manages
    // its own per-section scrolling, so the scaffold must not double-wrap it.
    if (Responsive.isPhone(context)) {
      showAdaptiveModal<void>(
        context: context,
        designWidth: 700,
        designHeight: 500,
        phoneMode: PhoneModalMode.fullScreen,
        builder: (modalContext) {
          final colors = NightshadeColors.of(modalContext);
          return Scaffold(
            backgroundColor: colors.background,
            appBar: AppBar(
              backgroundColor: colors.surface,
              title: Text(modalContext.l10n.text('equipmentSettingsTitle')),
              leading: IconButton(
                icon: const Icon(LucideIcons.x),
                tooltip: modalContext.l10n.text('commonClose'),
                onPressed: () => Navigator.of(modalContext).pop(),
              ),
            ),
            body: const SafeArea(child: EquipmentSettingsTab()),
          );
        },
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => NightshadeDialog(
        title: dialogContext.l10n.text('equipmentSettingsTitle'),
        icon: LucideIcons.settings,
        width: 700,
        height: 500,
        // EquipmentSettingsTab manages its own scrolling per-section, so the
        // dialog scaffold must not double-wrap it in a SingleChildScrollView.
        scrollableBody: false,
        bodyPadding: EdgeInsets.zero,
        child: const EquipmentSettingsTab(),
      ),
    );
  }
}
