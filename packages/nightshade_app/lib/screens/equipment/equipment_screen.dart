import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'widgets/profile_sidebar.dart';
import 'widgets/connected_device_card.dart';
import 'widgets/discovery_panel.dart';
import 'dialogs/profile_editor_dialog.dart';
import 'tabs/settings_tab.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/equipment_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

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
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
      description: 'Learn how to connect and manage your astrophotography equipment.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Row(
        children: [
          // Profile Sidebar (collapsible, resizable)
          _CollapsibleSidebar(
            isCollapsed: sidebarCollapsed,
            onToggle: () {
              ref.read(equipmentSidebarCollapsedProvider.notifier).state = !sidebarCollapsed;
            },
            child: ProfileSidebar(
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
              onCollapse: () {
                ref.read(equipmentSidebarCollapsedProvider.notifier).state = true;
              },
            ),
          ),

          // Main content area
          Expanded(
            child: Column(
              children: [
                // Dashboard header
                _DashboardHeader(
                  profileName: selectedProfile?.name,
                  onSettings: () => _showSettings(context),
                ),

                // Device cards grid
                Expanded(
                  child: _DeviceDashboard(
                    profile: selectedProfile,
                  ),
                ),

                // Discovery panel (collapsible)
                const DiscoveryPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Profile Operations
  // ============================================================================

  Future<void> _showProfileEditor(BuildContext context, EquipmentProfileModel? profile) async {
    await ProfileEditorDialog.show(context, profile: profile);
  }

  Future<void> _createEmptyProfile() async {
    try {
      final profileService = ref.read(profileServiceProvider);
      final profileId = await profileService.createProfile('My Equipment');
      ref.read(selectedEquipmentProfileIdProvider.notifier).state = profileId;
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to create profile: $e');
      }
    }
  }

  void _showCreateProfileWizard(BuildContext context) {
    // Quick setup: Create a new profile and immediately trigger device discovery
    _createEmptyProfile().then((_) {
      // Trigger device discovery to find available equipment
      ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
    });
  }

  Future<void> _setDefaultProfile(int profileId) async {
    try {
      final dao = ref.read(equipmentProfilesDaoProvider);
      await dao.setActiveProfile(profileId);
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
      await profileService.deleteProfile(profileId);

      // If we deleted the selected profile, select another one
      final selectedId = ref.read(selectedEquipmentProfileIdProvider);
      if (selectedId == profileId) {
        final profiles = ref.read(sortedProfilesProvider);
        final remainingProfiles = profiles.where((p) => p.id != profileId).toList();
        if (remainingProfiles.isNotEmpty) {
          ref.read(selectedEquipmentProfileIdProvider.notifier).state = remainingProfiles.first.id;
        } else {
          ref.read(selectedEquipmentProfileIdProvider.notifier).state = null;
        }
      }

      if (mounted) {
        context.showSuccessSnackBar('Profile deleted');
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

  // ============================================================================
  // Device Connection Operations
  // ============================================================================

  Future<void> _connectAllDevices(EquipmentProfileModel profile) async {
    final deviceService = ref.read(deviceServiceProvider);
    final discoveryNotifier = ref.read(unifiedDiscoveryProvider.notifier);

    // Count how many devices we need to connect
    final deviceIds = [
      profile.cameraId,
      profile.mountId,
      profile.focuserId,
      profile.filterWheelId,
      profile.guiderId,
      profile.rotatorId,
    ].where((id) => id != null && id.isNotEmpty).toList();

    if (deviceIds.isEmpty) {
      if (mounted) {
        context.showWarningSnackBar('No devices configured in this profile');
      }
      return;
    }

    // Use cached discovery results if they are recent (< 30s old).
    // Only rescan backends whose results are stale or missing.
    if (mounted) {
      context.showInfoSnackBar('Connecting devices...');
    }
    await discoveryNotifier.discoverIfNeeded();

    final connections = <(String?, Future<void> Function(String), String)>[
      (profile.cameraId, deviceService.connectCamera, 'camera'),
      (profile.mountId, deviceService.connectMount, 'mount'),
      (profile.focuserId, deviceService.connectFocuser, 'focuser'),
      (profile.filterWheelId, deviceService.connectFilterWheel, 'filter wheel'),
      (profile.guiderId, deviceService.connectGuider, 'guider'),
      (profile.rotatorId, deviceService.connectRotator, 'rotator'),
    ];

    int successCount = 0;
    int failCount = 0;
    final List<String> failedDevices = [];

    for (final (id, connect, name) in connections) {
      if (id != null && id.isNotEmpty) {
        try {
          await connect(id);
          successCount++;
        } catch (e) {
          failCount++;
          failedDevices.add(name);
        }
      }
    }

    if (!mounted) return;

    if (successCount > 0 && failCount == 0) {
      context.showSuccessSnackBar('Connected $successCount device${successCount > 1 ? 's' : ''}');
    } else if (successCount > 0 && failCount > 0) {
      context.showWarningSnackBar(
        'Connected $successCount device${successCount > 1 ? 's' : ''}, '
        'failed: ${failedDevices.join(", ")}'
      );
    } else if (failCount > 0) {
      context.showErrorSnackBar(
        'Failed to connect: ${failedDevices.join(", ")}. '
        'Ensure devices are powered on and available.'
      );
    }
  }

  Future<void> _disconnectAllDevices() async {
    final deviceService = ref.read(deviceServiceProvider);

    final disconnects = <(Future<void> Function(), String)>[
      (deviceService.disconnectCamera, 'camera'),
      (deviceService.disconnectMount, 'mount'),
      (deviceService.disconnectFocuser, 'focuser'),
      (deviceService.disconnectFilterWheel, 'filter wheel'),
      (deviceService.disconnectGuider, 'guider'),
      (deviceService.disconnectRotator, 'rotator'),
    ];

    int successCount = 0;

    for (final (disconnect, name) in disconnects) {
      try {
        await disconnect();
        successCount++;
      } catch (e) {
        // Only show error if device was actually connected
        if (e.toString().contains('not connected')) continue;
        if (mounted) {
          context.showErrorSnackBar('Failed to disconnect $name: $e');
        }
      }
    }

    if (mounted && successCount > 0) {
      context.showSuccessSnackBar('All devices disconnected');
    }
  }

  // ============================================================================
  // Settings
  // ============================================================================

  void _showSettings(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 700,
          height: 500,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.settings, color: colors.textPrimary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Equipment Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              // Content
              const Expanded(
                child: EquipmentSettingsTab(),
              ),
            ],
          ),
        ),
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

  const _DashboardHeader({
    required this.profileName,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (profileName != null) ...[
            Icon(LucideIcons.layers, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              profileName!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ] else
            Text(
              'Select a profile',
              style: TextStyle(
                fontSize: 16,
                color: colors.textMuted,
              ),
            ),
          const Spacer(),
          // Connection status summary
          _ConnectionStatusSummary(),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(LucideIcons.settings, size: 18),
            tooltip: 'Equipment Settings',
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Connection Status Summary Widget
// ============================================================================

class _ConnectionStatusSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

    final connectionStates = [
      cameraState.connectionState,
      mountState.connectionState,
      focuserState.connectionState,
      filterWheelState.connectionState,
      guiderState.connectionState,
      rotatorState.connectionState,
    ];

    final connectedCount = connectionStates
        .where((state) => state == DeviceConnectionState.connected)
        .length;

    if (connectedCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.success.withValues(alpha: 0.3)),
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

  const _DeviceDashboard({this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch device connection states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

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
      final hasDevicesAssigned = (p.cameraId != null && p.cameraId!.isNotEmpty) ||
          (p.mountId != null && p.mountId!.isNotEmpty) ||
          (p.focuserId != null && p.focuserId!.isNotEmpty) ||
          (p.filterWheelId != null && p.filterWheelId!.isNotEmpty) ||
          (p.guiderId != null && p.guiderId!.isNotEmpty) ||
          (p.rotatorId != null && p.rotatorId!.isNotEmpty);

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
                'Use "Connect All" in the sidebar to connect your equipment',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
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
                'Edit the profile to add devices, or use discovery below',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

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
            // Welcome icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.2),
                    colors.primary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                LucideIcons.moon,
                size: 36,
                color: colors.primary,
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Welcome to Nightshade',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              "Let's set up your first equipment profile",
              style: TextStyle(
                fontSize: 16,
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
                borderRadius: BorderRadius.circular(16),
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
                icon: LucideIcons.sparkles,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
                onPressed: onStartSetup,
              ),
            ),

            const SizedBox(height: 12),

            NightshadeButton(
              onPressed: onManualSetup,
              label: "I'll do it manually",
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
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
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.15),
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
