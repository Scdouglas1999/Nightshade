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
import 'utils/equipment_disconnect.dart';
import '../../localization/nightshade_localizations.dart';
import '../../utils/cooled_camera_guard.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/equipment_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../sequencer/widgets/run_dashboard/recovery_banner.dart';

part 'equipment_screen/layout_rail.dart';
part 'equipment_screen/profile_undo.dart';
part 'equipment_screen/progress_dashboard.dart';
part 'equipment_screen/sidebar_onboarding.dart';

// Providers for equipment screen state

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

// Constants for sidebar dimensions

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

// Equipment screen

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  int _profileOperationGeneration = 0;

  void _bumpProfileMutationEpoch() {
    ref.read(profileMutationEpochProvider.notifier).state++;
  }

  bool _isCurrentProfileOperation(
    int generation,
    NightshadeBackend authority,
  ) {
    return mounted &&
        generation == _profileOperationGeneration &&
        identical(ref.read(backendProvider), authority);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (previous == null || identical(previous, next)) return;
      _profileOperationGeneration++;
      _bumpProfileMutationEpoch();
    });
    final colors = NightshadeColors.of(context);
    final profilesAsync = ref.watch(equipmentProfilesProvider);
    if (profilesAsync.hasError) {
      return _EquipmentProfilesUnavailable(
        error: profilesAsync.error!,
        onRetry: () => _retryProfiles(ref),
      );
    }
    final profilesState = profilesAsync.valueOrNull;
    if (profilesState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profilesState.error != null) {
      return _EquipmentProfilesUnavailable(
        error: profilesState.error!,
        onRetry: () => _retryProfiles(ref),
      );
    }
    final profiles = List<EquipmentProfileModel>.from(profilesState.profiles)
      ..sort((a, b) {
        final orderCompare = a.sortOrder.compareTo(b.sortOrder);
        if (orderCompare != 0) return orderCompare;
        return a.name.compareTo(b.name);
      });
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
      // Equipment is the host the floating card cannot share a corner with.
      // Measured at 1000x800 on a fresh install, the card (x 745-985,
      // y 620-745) lands on the DISCOVERY panel header's Scan All / Collapse
      // buttons and abuts the mount card's Unpark / Track / Home / Flip row;
      // at 1600x900 it covers the STATUS rail's "Ready to image" blockers
      // block. Those are live, non-scrollable controls in exactly the corner
      // the nudge anchors to — the case
      // [ContextualTourPrompt.reserveSpaceForCard] exists for. Every other
      // screen keeps the floating default.
      reserveSpaceForCard: true,
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
            // Spotlight target for the Equipment Setup tour's first step.
            key: EquipmentTutorialKeys.profileSelector,
            selectedProfileId: selectedProfileId,
            onProfileSelected: (id) {
              ref.read(selectedEquipmentProfileIdProvider.notifier).state = id;
            },
            onCreateProfile: () => _showProfileEditor(context, null),
            onEditProfile: (profile) => _showProfileEditor(context, profile),
            onConnectAll: _connectAllDevices,
            onDisconnectAll: _disconnectAllDevices,
            onSetDefault: _setDefaultProfile,
            onActivateProfile: _activateProfile,
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

  void _retryProfiles(WidgetRef ref) {
    ref.invalidate(allProfilesProvider);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(equipmentProfilesProvider);
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

  // Profile operations

  Future<void> _showProfileEditor(
      BuildContext context, EquipmentProfileModel? profile) async {
    final saved = await ProfileEditorDialog.show(context, profile: profile);
    if (saved == true) _bumpProfileMutationEpoch();
  }

  Future<void> _createEmptyProfile() async {
    final authority = ref.read(backendProvider);
    final generation = ++_profileOperationGeneration;
    try {
      final profileId = await ref
          .read(equipmentProfilesProvider.notifier)
          .createProfile(name: 'My Equipment');
      if (!_isCurrentProfileOperation(generation, authority)) return;
      _bumpProfileMutationEpoch();
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = profileId;
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      context.showErrorSnackBar(
        context.l10n
            .text('equipmentCreateProfileFailed', params: {'error': '$e'}),
      );
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

  /// Point the app at [profile] for this session without touching which
  /// profile loads at startup.
  ///
  /// `setActiveProfile` is the app's single, remote-aware activation authority:
  /// it pushes the row into the native executor before committing SQLite.
  Future<void> _activateProfile(EquipmentProfileModel profile) async {
    final profileId = profile.id;
    if (profileId == null) return;
    final authority = ref.read(backendProvider);
    final generation = ++_profileOperationGeneration;
    try {
      await ref
          .read(equipmentProfilesProvider.notifier)
          .setActiveProfile(profileId);
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      _bumpProfileMutationEpoch();
      context.showSuccessSnackBar('Now using "${profile.name}"');
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      context.showErrorSnackBar(
        'Could not switch to "${profile.name}": $e',
      );
    }
  }

  Future<void> _setDefaultProfile(EquipmentProfileModel profile) async {
    final authority = ref.read(backendProvider);
    final generation = ++_profileOperationGeneration;
    try {
      // makeActive: false — the star means "Make Startup Default" and nothing
      // else. Switching which rig is in use is its own action now ("Use This
      // Profile" / [_activateProfile]), so starring a profile you are not
      // imaging with must not yank the session onto it and re-push its devices
      // to the Rust executor mid-run. Settings > Equipment Profiles has always
      // treated the same action this way (screen_shell.dart _setDefaultProfile);
      // this is the Equipment screen catching up rather than two surfaces
      // disagreeing about what one label does.
      await ref
          .read(equipmentProfilesProvider.notifier)
          .setDefaultProfile(profile.id, makeActive: false);
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      _bumpProfileMutationEpoch();
      context.showSuccessSnackBar(
        context.l10n.text('equipmentDefaultProfileSet'),
      );
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      context.showErrorSnackBar(
        context.l10n.text('equipmentSetDefaultFailed', params: {'error': '$e'}),
      );
    }
  }

  Future<void> _duplicateProfile(int profileId) async {
    final authority = ref.read(backendProvider);
    final generation = ++_profileOperationGeneration;
    try {
      // Get the source profile to derive a name for the copy
      final profiles = ref.read(sortedProfilesProvider);
      final sourceProfile =
          profiles.where((profile) => profile.id == profileId).firstOrNull;
      if (sourceProfile == null) {
        throw StateError('Profile $profileId no longer exists');
      }
      final newName = '${sourceProfile.name} (Copy)';
      final newId = await ref
          .read(equipmentProfilesProvider.notifier)
          .duplicateProfile(profileId, newName);
      if (!_isCurrentProfileOperation(generation, authority)) return;
      _bumpProfileMutationEpoch();
      // Select the newly duplicated profile
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = newId;
      if (!mounted) return;
      context.showSuccessSnackBar(
        context.l10n.text('equipmentProfileDuplicated'),
      );
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      context.showErrorSnackBar(
        context.l10n.text('equipmentDuplicateFailed', params: {'error': '$e'}),
      );
    }
  }

  Future<void> _deleteProfile(int profileId) async {
    final backendOwner = ref.read(backendProvider.notifier);
    final backendAtDelete = backendOwner.currentBackend;
    final generation = ++_profileOperationGeneration;
    try {
      // Resolve the row-to-delete from the remote-aware in-memory list, not the
      // local-only DAO: on a slave (NetworkBackend) the local SQLite is empty,
      // so a direct DAO read would return null and abort the delete. The model
      // from this list already carries name/isActive for the undo snackbar.
      final deletedProfile = ref
          .read(sortedProfilesProvider)
          .where((p) => p.id == profileId)
          .firstOrNull;
      if (deletedProfile == null) {
        throw StateError('Profile $profileId no longer exists');
      }

      // Keep the undo payload in the authority that owns it. A remote profile
      // is already fully represented by [deletedProfile], while a local
      // profile retains the service's versioned JSON for an exact restore.
      final deletedProfileJson = backendAtDelete is NetworkBackend
          ? null
          : await ref.read(profileServiceProvider).exportProfileToJson(
                profileId,
              );
      if (!_isCurrentProfileOperation(generation, backendAtDelete)) return;
      await ref
          .read(equipmentProfilesProvider.notifier)
          .deleteProfile(profileId);
      if (!_isCurrentProfileOperation(generation, backendAtDelete)) return;
      _bumpProfileMutationEpoch();
      final epochAtDelete = ref.read(profileMutationEpochProvider);

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
        // Everything the Undo needs is captured HERE, while the screen is
        // alive: the messenger and the container both outlive this route, so
        // the offer still works after the operator navigates away.
        final container = ProviderScope.containerOf(context, listen: false);
        final colors = NightshadeColors.of(context);
        final l10n = context.l10n;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('equipmentProfileDeleted',
                params: {'name': deletedProfile.name})),
            duration: const Duration(seconds: 6),
            // `persist` defaults to `action != null` in Flutter 3.44
            // (SnackBar's constructor), and ScaffoldMessenger's timer returns
            // without hiding when it is set — so `duration` was inert and this
            // bar sat over the status bar (profile, device states, focuser
            // position, temperature, clock, LST) until the app was restarted.
            // An undo offer is not a modal: honour the 6 s window and give the
            // operator an explicit ✕ as well.
            persist: false,
            showCloseIcon: true,
            action: SnackBarAction(
              label: context.l10n.text('commonUndo'),
              onPressed: () {
                unawaited(restoreDeletedProfile(
                  deletedProfile,
                  container: container,
                  messenger: messenger,
                  colors: colors,
                  l10n: l10n,
                  localExportJson: deletedProfileJson,
                  epochAtDelete: epochAtDelete,
                  backendOwner: backendOwner,
                  backendAtDelete: backendAtDelete,
                ));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, backendAtDelete)) return;
      if (!mounted) return;
      context.showErrorSnackBar(
        context.l10n.text('equipmentDeleteFailed', params: {'error': '$e'}),
      );
    }
  }

  Future<void> _reorderProfiles(int oldIndex, int newIndex) async {
    final authority = ref.read(backendProvider);
    final generation = ++_profileOperationGeneration;
    try {
      final profiles = ref.read(sortedProfilesProvider);
      if (oldIndex < 0 || oldIndex >= profiles.length) {
        throw StateError('The profile list changed before reordering.');
      }

      // Build reordered list
      final reordered = [...profiles];
      final item = reordered.removeAt(oldIndex);
      if (newIndex < 0 || newIndex > reordered.length) {
        throw StateError('The profile destination is no longer available.');
      }
      // ProfileSidebar uses ReorderableListView.onReorderItem, whose
      // destination index is already adjusted for removal of the source.
      reordered.insert(newIndex, item);

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
      if (_isCurrentProfileOperation(generation, authority)) {
        _bumpProfileMutationEpoch();
      }
    } catch (e) {
      if (!_isCurrentProfileOperation(generation, authority)) return;
      if (!mounted) return;
      context.showErrorSnackBar('Failed to reorder: $e');
    }
  }

  // Device connection operations

  Future<void> _connectAllDevices(EquipmentProfileModel profile) async {
    final deviceService = ref.read(deviceServiceProvider);
    final discoveryNotifier = ref.read(unifiedDiscoveryProvider.notifier);
    final progressNotifier =
        ref.read(deviceConnectionProgressProvider.notifier);

    // Count how many devices we need to connect. Must list every slot the
    // sweep itself dispatches (see DeviceService.connectAllFromProfile),
    // otherwise a profile holding only a safety monitor and a power switch is
    // turned away as "no devices configured" and then connects nothing.
    final deviceIds = [
      profile.cameraId,
      profile.mountId,
      profile.focuserId,
      profile.filterWheelId,
      profile.guiderId,
      profile.rotatorId,
      profile.domeId,
      profile.weatherId,
      profile.safetyMonitorId,
      profile.switchId,
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

    // NOTHING ELSE IS CONNECTED HERE. "Connect All" sits under the profile
    // card and means "connect this profile's devices" — the sweep above, which
    // already includes the profile's safety monitor and switch.
    //
    // Reaching past the profile — e.g. to the discovery cache's first safety
    // monitor — makes two identical presses connect different rigs, and leaves
    // a device the header counts that the profile does not, so it vanishes on
    // the next launch. A device that is not in the profile is assigned in
    // Discovery, deliberately, once.

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
    // Disconnect All includes the camera: gate on an active cooler so the TEC
    // is never cut abruptly without an explicit confirm (same guard as the
    // per-device card).
    final proceed = await confirmDisconnectCooledCamera(context, ref);
    if (!proceed || !mounted) return;

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

  // Settings

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

class _EquipmentProfilesUnavailable extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _EquipmentProfilesUnavailable({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState.compact(
        icon: LucideIcons.alertTriangle,
        title: 'Could not load equipment profiles',
        body: 'Nightshade could not read the equipment configuration. '
            'No profiles or setup actions are shown until it can be loaded.\n\n'
            '$error',
        action: NightshadeButton(
          label: 'Retry',
          icon: LucideIcons.refreshCw,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onRetry,
        ),
      ),
    );
  }
}
