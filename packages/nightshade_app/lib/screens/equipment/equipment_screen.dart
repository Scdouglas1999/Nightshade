import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'tabs/connections_tab.dart';
import 'tabs/settings_tab.dart';
import 'widgets/quick_connect_bar.dart';
import 'widgets/connection_status_zone.dart';
import '../../services/mount_command_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/tutorial_keys/equipment_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

// ============================================================================
// Device ID Formatting Helpers
// ============================================================================

/// Format a device ID into a user-friendly display name
String _formatDeviceId(String id) {
  final lowerId = id.toLowerCase();

  // Handle native device IDs: native:vendor:index or native:vendor_type:index
  if (lowerId.startsWith('native:')) {
    final parts = id.substring(7).split(':');
    if (parts.isNotEmpty) {
      final devicePart = parts[0];
      final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

      // Handle vendor_type format (e.g., zwo_eaf)
      if (devicePart.contains('_')) {
        final subParts = devicePart.split('_');
        final vendor = _capitalizeVendor(subParts[0]);
        final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
        return '$vendor $type';
      }

      // Simple vendor format
      final vendor = _capitalizeVendor(devicePart);
      if (index != null) {
        return '$vendor #${index + 1}';
      }
      return vendor;
    }
  }

  // Handle ASCOM device IDs: ascom:ASCOM.Vendor.Type
  if (lowerId.startsWith('ascom:')) {
    final ascomId = id.substring(6);
    final parts = ascomId.split('.');
    if (parts.length >= 2) {
      // Extract vendor part (after ASCOM. prefix)
      final vendorPart = parts.length > 1 ? parts[1] : parts[0];
      return _formatAscomVendor(vendorPart);
    }
  }

  // Handle Alpaca device IDs
  if (lowerId.startsWith('alpaca:')) {
    final alpacaPart = id.substring(7);
    return 'Alpaca: $alpacaPart';
  }

  // Handle PHD2
  if (lowerId.contains('phd2') || lowerId.contains('phd 2')) {
    return 'PHD2';
  }

  // Fallback: try to clean up the ID
  return _cleanupId(id);
}

/// Capitalize vendor names properly
String _capitalizeVendor(String vendor) {
  const knownVendors = {
    'zwo': 'ZWO',
    'asi': 'ZWO ASI',
    'qhy': 'QHY',
    'playerone': 'PlayerOne',
    'svbony': 'SVBony',
    'atik': 'Atik',
    'fli': 'FLI',
    'moravian': 'Moravian',
    'touptek': 'Touptek',
    'pegasus': 'Pegasus',
    'pegasusastro': 'Pegasus Astro',
    'ioptron': 'iOptron',
    'skywatcher': 'Sky-Watcher',
    'celestron': 'Celestron',
    'meade': 'Meade',
    'losmandy': 'Losmandy',
    'moonlite': 'MoonLite',
    'optec': 'Optec',
    'lacerta': 'Lacerta',
    'esatto': 'Esatto',
    'primaluce': 'PrimaLuce',
  };

  final lower = vendor.toLowerCase();
  if (knownVendors.containsKey(lower)) {
    return knownVendors[lower]!;
  }

  // Default: capitalize first letter
  if (vendor.isEmpty) return vendor;
  return vendor[0].toUpperCase() + vendor.substring(1);
}

/// Format ASCOM vendor string by adding spaces before capitals/numbers
String _formatAscomVendor(String vendor) {
  // Insert spaces before capital letters and numbers
  final spaced = vendor.replaceAllMapped(
    RegExp(r'([a-z])([A-Z0-9])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  return spaced;
}

/// Clean up an unrecognized ID for display
String _cleanupId(String id) {
  // Remove common prefixes
  var cleaned = id;
  for (final prefix in ['native:', 'ascom:', 'alpaca:', 'ASCOM.']) {
    if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
      cleaned = cleaned.substring(prefix.length);
    }
  }

  // Replace underscores and dots with spaces
  cleaned = cleaned.replaceAll('_', ' ').replaceAll('.', ' ');

  // Remove trailing numbers that look like indices
  cleaned = cleaned.replaceAll(RegExp(r'\s*:\s*\d+$'), '');

  // Capitalize words
  if (cleaned.isNotEmpty) {
    cleaned = cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  return cleaned.isEmpty ? id : cleaned;
}

/// Get display name for a device, preferring deviceName, falling back to formatted deviceId
String _getDeviceDisplayName(String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return _formatDeviceId(deviceId);
  }
  return fallback;
}

/// Device protocol types (kept for backward compatibility)
enum DeviceProtocol {
  ascom,
  alpaca,
  indi,
  native,
}

/// Provider for currently selected profile in the equipment screen
final selectedEquipmentProfileIdProvider = StateProvider<int?>((ref) {
  // Default to the active profile
  final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
  return activeProfile?.id;
});

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen>
    with SingleTickerProviderStateMixin {
  int _currentSubTab = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static final _subTabs = [
    _SubTabData(icon: LucideIcons.radar, label: 'Discovery', key: EquipmentTutorialKeys.discoveryTab),
    _SubTabData(icon: LucideIcons.plugZap, label: 'Connected', key: EquipmentTutorialKeys.connectedTab),
    _SubTabData(icon: LucideIcons.settings2, label: 'Settings', key: EquipmentTutorialKeys.settingsTab),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index != _currentSubTab) {
      _fadeController.reset();
      setState(() => _currentSubTab = index);
      _fadeController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final profilesAsync = ref.watch(allProfilesProvider);
    final selectedProfileId = ref.watch(selectedEquipmentProfileIdProvider);

    // Check for first-time user (no profiles)
    final showOnboarding = profilesAsync.maybeWhen(
      data: (profiles) => profiles.isEmpty,
      orElse: () => false,
    );

    if (showOnboarding) {
      return _FirstTimeOnboarding(
        colors: colors,
        onStartSetup: () => _showCreateProfileWizard(context),
        onManualSetup: () {
          // Create an empty profile and proceed
          _createEmptyProfile();
        },
      );
    }

    // Get selected profile
    final selectedProfile = profilesAsync.maybeWhen(
      data: (profiles) => profiles.where((p) => p.id == selectedProfileId).firstOrNull,
      orElse: () => null,
    );

    return ContextualTourPrompt(
      screenId: 'equipment',
      tourCategory: TutorialCategory.equipmentTour,
      title: 'Equipment Tour',
      description: 'Learn how to connect and manage your astrophotography equipment.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Column(
        children: [
          // ZONE 1: Quick Connect Bar
          QuickConnectBar(
            selectedProfileId: selectedProfileId,
            onProfileSelected: (profile) {
              ref.read(selectedEquipmentProfileIdProvider.notifier).state = profile.id;
            },
            onCreateProfile: () => _showCreateProfileDialog(context),
          ),

          // ZONE 2: Connection Status Zone
          ConnectionStatusZone(
            selectedProfile: selectedProfile,
            onConnectAll: () => _connectAllDevices(selectedProfile),
            onDisconnectAll: () => _disconnectAllDevices(),
            onEditProfile: () => _showEditProfileDialog(context, selectedProfile),
            onSaveSetup: () => _saveConnectedDevices(context, selectedProfile),
          ),

          // ZONE 3: Device Management Tabs
          Expanded(
            child: Column(
              children: [
                // Tab bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border(
                      bottom: BorderSide(color: colors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      _SubTabBar(
                        tabs: _subTabs,
                        currentIndex: _currentSubTab,
                        onTabSelected: _onTabSelected,
                        colors: colors,
                      ),
                      const Spacer(),
                      _ConnectionBadge(colors: colors),
                    ],
                  ),
                ),

                // Tab content
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: IndexedStack(
                      index: _currentSubTab,
                      children: const [
                        ConnectionsTab(), // Discovery tab (renamed)
                        _ConnectedDevicesTab(), // New connected devices tab
                        EquipmentSettingsTab(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectAllDevices(db.EquipmentProfile? profile) async {
    if (profile == null) return;

    final deviceService = ref.read(deviceServiceProvider);
    final connections = <(String?, Future<void> Function(String), String)>[
      (profile.cameraId, deviceService.connectCamera, 'camera'),
      (profile.mountId, deviceService.connectMount, 'mount'),
      (profile.focuserId, deviceService.connectFocuser, 'focuser'),
      (profile.filterWheelId, deviceService.connectFilterWheel, 'filter wheel'),
      (profile.guiderId, deviceService.connectGuider, 'guider'),
      (profile.rotatorId, deviceService.connectRotator, 'rotator'),
    ];

    for (final (id, connect, name) in connections) {
      if (id != null && id.isNotEmpty) {
        try {
          await connect(id);
        } catch (e) {
          if (mounted) context.showErrorSnackBar('Failed to connect $name: $e');
        }
      }
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

    for (final (disconnect, name) in disconnects) {
      try {
        await disconnect();
      } catch (e) {
        if (mounted) context.showErrorSnackBar('Failed to disconnect $name: $e');
      }
    }
  }

  Future<void> _saveConnectedDevices(BuildContext context, db.EquipmentProfile? activeProfile) async {
    final profileService = ref.read(profileServiceProvider);

    // Check if there's an active profile
    if (activeProfile == null) {
      // Show dialog to create/select profile
      final action = await showDialog<_SaveSetupAction>(
        context: context,
        builder: (context) => _SaveSetupNoProfileDialog(
          onCreateProfile: () => _showCreateProfileDialog(context),
        ),
      );

      if (action == null || action == _SaveSetupAction.cancel) {
        return;
      }

      if (action == _SaveSetupAction.createNew) {
        // Create new profile then save devices
        await _createEmptyProfile();
        // Wait for profile to be created and try again
        await Future.delayed(const Duration(milliseconds: 100));
        final saved = await profileService.saveConnectedDevicesToProfile();
        if (saved && mounted) {
          context.showSuccessSnackBar('Profile created and devices saved');
        }
      } else if (action == _SaveSetupAction.selectExisting) {
        // Show profile picker
        final selectedProfileId = await showDialog<int>(
          context: context,
          builder: (context) => const _SaveSetupProfilePickerDialog(),
        );

        if (selectedProfileId != null) {
          // Set as active profile
          final dao = ref.read(equipmentProfilesDaoProvider);
          await dao.setActiveProfile(selectedProfileId);
          ref.read(selectedEquipmentProfileIdProvider.notifier).state = selectedProfileId;
          // Save devices to this profile
          final saved = await profileService.saveConnectedDevicesToProfile();
          if (saved && mounted) {
            context.showSuccessSnackBar('Devices saved to profile');
          }
        }
      }
      return;
    }

    // Active profile exists - save devices directly
    try {
      final saved = await profileService.saveConnectedDevicesToProfile();
      if (mounted) {
        if (saved) {
          context.showSuccessSnackBar('Devices saved to "${activeProfile.name}"');
        } else {
          context.showWarningSnackBar('No connected devices to save');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save devices: $e');
      }
    }
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

  void _showCreateProfileDialog(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final nameController = TextEditingController(text: 'New Profile');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Create Profile', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Profile Name',
            labelStyle: TextStyle(color: colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            label: 'Create',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () async {
              Navigator.pop(context);
              try {
                final profileService = ref.read(profileServiceProvider);
                final profileId = await profileService.createProfile(nameController.text);
                ref.read(selectedEquipmentProfileIdProvider.notifier).state = profileId;
              } catch (e) {
                if (mounted) {
                  context.showErrorSnackBar('Failed to create profile: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, db.EquipmentProfile? profile) {
    if (profile == null) return;
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final nameController = TextEditingController(text: profile.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Edit Profile', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Profile Name',
                labelStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            label: 'Save',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              try {
                final dao = ref.read(equipmentProfilesDaoProvider);
                await dao.updateProfile(profile.copyWith(
                  name: name,
                  updatedAt: DateTime.now(),
                ));
                if (context.mounted) {
                  Navigator.pop(context);
                  context.showSuccessSnackBar('Profile updated');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to update profile: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showCreateProfileWizard(BuildContext context) {
    // Quick setup: Create a new profile and immediately trigger device discovery
    // The user can then assign discovered devices to their profile
    _createEmptyProfile().then((_) {
      // Trigger device discovery to find available equipment
      ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
    });
  }
}

// ============================================================================
// Save Setup Dialogs
// ============================================================================

/// Action choices for the save setup no-profile dialog
enum _SaveSetupAction {
  createNew,
  selectExisting,
  cancel,
}

/// Dialog shown when user tries to save connected devices but no profile exists
class _SaveSetupNoProfileDialog extends StatelessWidget {
  final VoidCallback onCreateProfile;

  const _SaveSetupNoProfileDialog({
    required this.onCreateProfile,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.alertCircle,
              size: 20,
              color: colors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No Active Profile',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To save your connected devices, you need an equipment profile. '
            'Would you like to create a new profile or select an existing one?',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context, _SaveSetupAction.cancel),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          label: 'Select Existing',
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => Navigator.pop(context, _SaveSetupAction.selectExisting),
        ),
        NightshadeButton(
          label: 'Create New',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: () => Navigator.pop(context, _SaveSetupAction.createNew),
        ),
      ],
    );
  }
}

/// Dialog for selecting an existing profile when saving connected devices
class _SaveSetupProfilePickerDialog extends ConsumerWidget {
  const _SaveSetupProfilePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final profilesAsync = ref.watch(allProfilesProvider);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Select Profile',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 300,
        child: profilesAsync.when(
          data: (profiles) {
            if (profiles.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No profiles found. Create a new profile first.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: profiles.length,
                separatorBuilder: (_, __) => Divider(
                  color: colors.border,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      profile.name,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: profile.description != null
                        ? Text(
                            profile.description!,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: colors.textMuted,
                    ),
                    onTap: () => Navigator.pop(context, profile.id),
                  );
                },
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Failed to load profiles: $error',
              style: TextStyle(color: colors.error),
            ),
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
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

// ============================================================================
// Connected Devices Tab (New)
// ============================================================================

class _ConnectedDevicesTab extends ConsumerWidget {
  const _ConnectedDevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch device states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

    final connectedDevices = <Widget>[];

    // Add connected devices
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        key: EquipmentTutorialKeys.cameraCard,
        icon: LucideIcons.camera,
        title: 'Camera',
        name: _getDeviceDisplayName(cameraState.deviceName, cameraState.deviceId, 'Camera'),
        telemetry: [
          if (cameraState.temperature != null)
            'Temperature: ${cameraState.temperature!.toStringAsFixed(1)}°C',
          if (cameraState.coolerPower != null)
            'Cooler: ${cameraState.coolerPower!.toStringAsFixed(0)}%',
          'Status: ${cameraState.isExposing ? "Exposing" : "Idle"}',
        ],
        accentColor: colors.primary,
        colors: colors,
        onSettings: () {},
        onDisconnect: () => ref.read(deviceServiceProvider).disconnectCamera(),
      ));
    }

    if (mountState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        key: EquipmentTutorialKeys.mountCard,
        icon: LucideIcons.compass,
        title: 'Mount',
        name: _getDeviceDisplayName(mountState.deviceName, mountState.deviceId, 'Mount'),
        telemetry: [
          'RA: ${mountState.ra?.toStringAsFixed(2) ?? "---"}  Dec: ${mountState.dec?.toStringAsFixed(2) ?? "---"}',
          'Tracking: ${mountState.isTracking ? "On" : "Off"}',
          'Status: ${mountState.isSlewing ? "Slewing" : "Ready"}',
        ],
        accentColor: colors.warning,
        colors: colors,
        quickActions: [
          _QuickAction(
            label: mountState.isParked ? 'Unpark' : 'Park',
            onTap: () => ref.read(mountCommandServiceProvider).togglePark(context),
          ),
        ],
        onSettings: () {},
        onDisconnect: () => ref.read(deviceServiceProvider).disconnectMount(),
      ));
    }

    if (focuserState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        icon: LucideIcons.focus,
        title: 'Focuser',
        name: _getDeviceDisplayName(focuserState.deviceName, focuserState.deviceId, 'Focuser'),
        telemetry: [
          'Position: ${focuserState.position ?? "---"}',
          if (focuserState.temperature != null)
            'Temperature: ${focuserState.temperature!.toStringAsFixed(1)}°C',
        ],
        accentColor: colors.success,
        colors: colors,
        onSettings: () {},
        onDisconnect: () => ref.read(deviceServiceProvider).disconnectFocuser(),
      ));
    }

    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        icon: LucideIcons.circle,
        title: 'Filter Wheel',
        name: _getDeviceDisplayName(filterWheelState.deviceName, filterWheelState.deviceId, 'Filter Wheel'),
        telemetry: [
          'Filter: ${filterWheelState.currentFilterName ?? "Unknown"}',
          'Position: ${filterWheelState.currentPosition ?? "---"}',
        ],
        accentColor: colors.warning,
        colors: colors,
        onSettings: () {},
        onDisconnect: () => ref.read(deviceServiceProvider).disconnectFilterWheel(),
      ));
    }

    if (guiderState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        icon: LucideIcons.crosshair,
        title: 'Guider',
        name: _getDeviceDisplayName(guiderState.deviceName, guiderState.deviceId, 'Guider'),
        telemetry: [
          if (guiderState.rmsTotal != null)
            'RMS: ${guiderState.rmsTotal!.toStringAsFixed(2)}"',
          'Status: ${guiderState.isGuiding ? "Guiding" : "Idle"}',
        ],
        accentColor: colors.info,
        colors: colors,
        onSettings: () {},
        onDisconnect: () => ref.read(deviceServiceProvider).disconnectGuider(),
      ));
    }

    if (rotatorState.connectionState == DeviceConnectionState.connected) {
      connectedDevices.add(_ConnectedDeviceCard(
        icon: LucideIcons.rotateCw,
        title: 'Rotator',
        name: _getDeviceDisplayName(rotatorState.deviceName, rotatorState.deviceId, 'Rotator'),
        telemetry: [
          'Position: ${rotatorState.position?.toStringAsFixed(1) ?? "---"}°',
          'Status: ${rotatorState.isMoving ? "Moving" : "Ready"}',
        ],
        accentColor: colors.accent,
        colors: colors,
        onSettings: () {},
        onDisconnect: () => ref.read(rotatorStateProvider.notifier).disconnect(),
      ));
    }

    if (connectedDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.unplug,
              size: 48,
              color: colors.textMuted,
            ),
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
              'Select a profile and click "Connect All" to get started',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: connectedDevices,
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final VoidCallback onTap;

  _QuickAction({required this.label, required this.onTap});
}

class _ConnectedDeviceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String name;
  final List<String> telemetry;
  final Color accentColor;
  final NightshadeColors colors;
  final List<_QuickAction>? quickActions;
  final VoidCallback onSettings;
  final VoidCallback onDisconnect;

  const _ConnectedDeviceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.name,
    required this.telemetry,
    required this.accentColor,
    required this.colors,
    this.quickActions,
    required this.onSettings,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.2),
                      accentColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: colors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
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
                      'Connected',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Telemetry
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: telemetry.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              )).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              if (quickActions != null)
                ...quickActions!.map((action) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: action.onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(action.label, style: const TextStyle(fontSize: 12)),
                  ),
                )),
              const Spacer(),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(LucideIcons.settings2, size: 16),
                tooltip: 'Settings',
                style: IconButton.styleFrom(
                  foregroundColor: colors.textMuted,
                ),
              ),
              IconButton(
                onPressed: onDisconnect,
                icon: const Icon(LucideIcons.unplug, size: 16),
                tooltip: 'Disconnect',
                style: IconButton.styleFrom(
                  foregroundColor: colors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Sub-tab components
// ============================================================================

class _SubTabData {
  final IconData icon;
  final String label;
  final GlobalKey? key;

  const _SubTabData({required this.icon, required this.label, this.key});
}

class _ConnectionBadge extends ConsumerWidget {
  final NightshadeColors colors;

  const _ConnectionBadge({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);

    final connectionStates = [
      cameraState.connectionState,
      mountState.connectionState,
      focuserState.connectionState,
      filterWheelState.connectionState,
      guiderState.connectionState,
    ];
    final connectedCount = connectionStates
        .where((state) => state == DeviceConnectionState.connected)
        .length;
    final totalDevices = connectionStates.length;
    final allConnected = connectedCount == totalDevices && totalDevices > 0;
    final someConnected = connectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: allConnected
            ? colors.success.withValues(alpha: 0.15)
            : someConnected
                ? colors.warning.withValues(alpha: 0.15)
                : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: allConnected
              ? colors.success.withValues(alpha: 0.3)
              : someConnected
                  ? colors.warning.withValues(alpha: 0.3)
                  : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: allConnected
                  ? colors.success
                  : someConnected
                      ? colors.warning
                      : colors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$connectedCount / $totalDevices',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: allConnected
                  ? colors.success
                  : someConnected
                      ? colors.warning
                      : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabBar extends StatelessWidget {
  final List<_SubTabData> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final NightshadeColors colors;

  const _SubTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = index == currentIndex;

          return _SubTabButton(
            key: tab.key,
            icon: tab.icon,
            label: tab.label,
            isSelected: isSelected,
            onTap: () => onTabSelected(index),
            colors: colors,
          );
        }).toList(),
      ),
    );
  }
}

class _SubTabButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _SubTabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_SubTabButton> createState() => _SubTabButtonState();
}

class _SubTabButtonState extends State<_SubTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.surface
                : _isHovered
                    ? widget.colors.surface.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: Colors.transparent,
              highlightColor: widget.colors.primary.withValues(alpha: 0.1),
              splashColor: widget.colors.primary.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 14,
                      color: widget.isSelected
                          ? widget.colors.primary
                          : widget.colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isSelected
                            ? widget.colors.textPrimary
                            : widget.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
