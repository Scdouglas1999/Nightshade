import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../utils/snackbar_helper.dart';
import 'catalog_settings_screen.dart';
import 'equipment_profiles_screen.dart';
import 'plugins_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedCategory = 0;

  static const _categories = [
    ('Connection', LucideIcons.wifi),
    ('General', LucideIcons.settings),
    ('Appearance', LucideIcons.palette),
    ('Location', LucideIcons.mapPin),
    ('Equipment Profiles', LucideIcons.boxes),
    ('Catalogs', LucideIcons.database),
    ('Imaging', LucideIcons.camera),
    ('Annotations', LucideIcons.tag),
    ('Sequencer', LucideIcons.listOrdered),
    ('Plate Solving', LucideIcons.crosshair),
    ('PHD2 Guiding', LucideIcons.target),
    ('Notifications', LucideIcons.bell),
    ('File Paths', LucideIcons.folder),
    ('Plugins', LucideIcons.puzzle),
    ('About', LucideIcons.info),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        // Categories sidebar
        ResizablePanel(
          initialWidth: 240,
          minWidth: 180,
          maxWidth: 400,
          side: ResizeSide.right,
          child: Container(
            // width: 240, // Removed for ResizablePanel
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final (label, icon) = _categories[index];
                      return _CategoryItem(
                        icon: icon,
                        label: label,
                        isSelected: index == _selectedCategory,
                        onTap: () => setState(() => _selectedCategory = index),
                        colors: colors,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Settings content
        Expanded(
          child: _buildContent(colors),
        ),
      ],
    );
  }

  Widget _buildContent(NightshadeColors colors) {
    switch (_selectedCategory) {
      case 0:
        return _ConnectionSettings(colors: colors);
      case 1:
        return _GeneralSettings(colors: colors);
      case 2:
        return _AppearanceSettings(colors: colors);
      case 3:
        return _LocationSettings(colors: colors);
      case 4:
        return const EquipmentProfilesScreen();
      case 5:
        return const CatalogSettingsScreen();
      case 6:
        return _ImagingSettings(colors: colors);
      case 7:
        return _AnnotationSettings(colors: colors);
      case 8:
        return _SequencerSettings(colors: colors);
      case 9:
        return _PlateSolvingSettings(colors: colors);
      case 10:
        return _Phd2GuidingSettings(colors: colors);
      case 11:
        return _NotificationSettings(colors: colors);
      case 12:
        return _FilePathSettings(colors: colors);
      case 13:
        return const PluginsScreen();
      case 14:
        return _AboutSettings(colors: colors);
      default:
        return const SizedBox();
    }
  }
}

class _CategoryItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.1)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(color: widget.colors.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
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
    );
  }
}

class _SettingsPage extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> children;
  final NightshadeColors colors;

  const _SettingsPage({
    required this.title,
    required this.description,
    required this.children,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final NightshadeColors colors;

  const _SettingsSection({
    required this.title,
    required this.children,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: children,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool isLast;
  final NightshadeColors colors;

  const _SettingRow({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.isLast = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor ?? colors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

// ============================================================================
// Connection Settings (Mobile-focused)
// ============================================================================

class _ConnectionSettings extends ConsumerWidget {
  final NightshadeColors colors;

  const _ConnectionSettings({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final isConnected = backend is NetworkBackend;
    final isDisconnected = backend is DisconnectedBackend;

    // Extract server info from NetworkBackend if connected
    String serverAddress = 'Not connected';
    String connectionStatus = 'Disconnected';
    Color statusColor = colors.textMuted;

    if (isConnected) {
      serverAddress = '${backend.serverHost}:${backend.serverPort}';
      connectionStatus = 'Connected';
      statusColor = colors.success;
    } else if (!isDisconnected) {
      // FfiBackend (local mode)
      serverAddress = 'Local';
      connectionStatus = 'Local Mode';
      statusColor = colors.primary;
    }

    return _SettingsPage(
      title: 'Connection',
      description: 'Server connection settings',
      colors: colors,
      children: [
        _SettingsSection(
          title: 'Server Status',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.server,
              title: 'Connection Status',
              subtitle: serverAddress,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  connectionStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              colors: colors,
            ),
            if (isConnected)
              _SettingRow(
                icon: LucideIcons.globe,
                title: 'Server Address',
                subtitle: 'IP address and port of connected server',
                trailing: SelectableText(
                  serverAddress,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                colors: colors,
              ),
            _SettingRow(
              icon: isConnected ? LucideIcons.logOut : LucideIcons.logIn,
              title: isConnected ? 'Disconnect' : 'Connect to Server',
              subtitle: isConnected
                  ? 'Return to connection screen to connect to a different server'
                  : 'Open connection screen to connect to a server',
              trailing: ElevatedButton(
                onPressed: () => _handleConnectionAction(context, ref, isConnected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? colors.error : colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: Text(isConnected ? 'Disconnect' : 'Connect'),
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        if (isConnected)
          _SettingsSection(
            title: 'Remote Features',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.refreshCw,
                title: 'Sync Location',
                subtitle: 'Download location from remote server',
                trailing: IconButton(
                  icon: Icon(LucideIcons.downloadCloud, color: colors.primary, size: 18),
                  onPressed: () async {
                    try {
                      final location = await backend.getLocation();
                      if (location != null) {
                        await ref.read(appSettingsProvider.notifier).updateLocation(
                          latitude: location.latitude,
                          longitude: location.longitude,
                          elevation: location.elevation,
                        );
                        if (context.mounted) {
                          context.showSuccessSnackBar('Location synced from server');
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        context.showErrorSnackBar('Sync failed: $e');
                      }
                    }
                  },
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
      ],
    );
  }

  void _handleConnectionAction(BuildContext context, WidgetRef ref, bool isConnected) {
    if (isConnected) {
      // Show confirmation dialog before disconnecting
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disconnect from Server?'),
          content: const Text(
            'You will return to the connection screen where you can connect to a different server.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Disconnect from server
                ref.read(backendProvider.notifier).disconnect();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
    } else {
      // Show connection dialog
      _showConnectDialog(context, ref);
    }
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    final hostController = TextEditingController(text: 'localhost');
    final portController = TextEditingController(text: '8765');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: 'e.g., localhost or 192.168.1.100',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8765',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 8765;
              if (host.isNotEmpty) {
                Navigator.pop(ctx);
                // Connect to server
                ref.read(backendProvider.notifier).connect(host, port);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// General Settings
// ============================================================================

class _GeneralSettings extends ConsumerWidget {
  final NightshadeColors colors;

  const _GeneralSettings({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) => _SettingsPage(
        title: 'General',
        description: 'Basic application settings',
        colors: colors,
        children: [
          _SettingsSection(
            title: 'Startup',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.power,
                title: 'Start minimized',
                subtitle: 'Launch app minimized to system tray',
                trailing: _SettingsSwitch(
                  value: settings.startMinimized,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setStartMinimized(value);
                  },
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.plug,
                title: 'Auto-connect equipment',
                subtitle: 'Connect to last used devices on startup',
                trailing: _SettingsSwitch(
                  value: settings.autoConnectEquipment,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setAutoConnectEquipment(value);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Behavior',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.save,
                title: 'Auto-save sequences',
                subtitle: 'Automatically save sequence changes',
                trailing: _SettingsSwitch(
                  value: settings.autoSaveSequences,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setAutoSaveSequences(value);
                  },
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.alertTriangle,
                title: 'Confirm before closing',
                subtitle: 'Show confirmation when closing during capture',
                trailing: _SettingsSwitch(
                  value: settings.confirmBeforeClosing,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setConfirmBeforeClosing(value);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Appearance Settings
// ============================================================================

class _AppearanceSettings extends ConsumerWidget {
  final NightshadeColors colors;

  const _AppearanceSettings({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) => _SettingsPage(
        title: 'Appearance',
        description: 'Customize how Nightshade looks',
        colors: colors,
        children: [
          _SettingsSection(
            title: 'Theme',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.moon,
                title: 'Dark mode',
                subtitle: 'Use dark theme (recommended for night use)',
                trailing: _SettingsSwitch(
                  value: settings.theme == 'dark',
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setTheme(value ? 'dark' : 'light');
                  },
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.palette,
                title: 'Accent color',
                subtitle: 'Primary accent color',
                trailing: _ColorPicker(
                  selectedColor: settings.accentColor,
                  onColorSelected: (color) {
                    ref.read(appSettingsProvider.notifier).setAccentColor(color);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Display',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.type,
                title: 'Font size',
                subtitle: 'Interface text size',
                trailing: _SettingsDropdown(
                  value: settings.fontSize,
                  items: const ['Small', 'Medium', 'Large'],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appSettingsProvider.notifier).setFontSize(value);
                    }
                  },
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.panelLeft,
                title: 'Sidebar collapsed by default',
                trailing: _SettingsSwitch(
                  value: settings.sidebarCollapsed,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setSidebarCollapsed(value);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Location Settings
// ============================================================================

class _LocationSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _LocationSettings({required this.colors});

  @override
  ConsumerState<_LocationSettings> createState() => _LocationSettingsState();
}

class _LocationSettingsState extends ConsumerState<_LocationSettings> {
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _elevController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _elevController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _latController.text = settings.latitude.toStringAsFixed(6);
      _lonController.text = settings.longitude.toStringAsFixed(6);
      _elevController.text = settings.elevation.toStringAsFixed(0);
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);
        
        return _SettingsPage(
          title: 'Location',
          description: 'Observatory location for calculations',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'Coordinates',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Latitude',
                  subtitle: 'Positive for North, negative for South',
                  trailing: _NumberInput(
                    controller: _latController,
                    suffix: '°',
                    min: -90,
                    max: 90,
                    decimals: 6,
                    onChanged: (value) async {
                      // Update settings - locationSyncProvider will automatically sync to planetarium
                      await ref.read(appSettingsProvider.notifier).setLatitude(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Longitude',
                  subtitle: 'Positive for East, negative for West',
                  trailing: _NumberInput(
                    controller: _lonController,
                    suffix: '°',
                    min: -180,
                    max: 180,
                    decimals: 6,
                    onChanged: (value) async {
                      // Update settings - locationSyncProvider will automatically sync to planetarium
                      await ref.read(appSettingsProvider.notifier).setLongitude(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.mountain,
                  title: 'Elevation',
                  subtitle: 'Height above sea level',
                  trailing: _NumberInput(
                    controller: _elevController,
                    suffix: 'm',
                    min: -500,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) async {
                      // Update settings - locationSyncProvider will automatically sync to planetarium
                      await ref.read(appSettingsProvider.notifier).setElevation(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: false,
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.refreshCw,
                  title: 'Sync from Server',
                  subtitle: 'Fetch location from Headless Server',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.downloadCloud, color: widget.colors.primary),
                    onPressed: () async {
                      try {
                        final backend = ref.read(backendProvider);
                        final location = await backend.getLocation();
                        
                        if (location != null) {
                          await ref.read(appSettingsProvider.notifier).updateLocation(
                            latitude: location.latitude,
                            longitude: location.longitude,
                            elevation: location.elevation,
                          );
                        }
                        
                        if (context.mounted) {
                          context.showSuccessSnackBar('Location synced from server');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          context.showErrorSnackBar('Sync failed: $e');
                        }
                      }
                    },
                  ),
                  isLast: false,
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.locate,
                  title: 'Use Device Location',
                  subtitle: 'Get location from GPS',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.crosshair, color: widget.colors.primary),
                    onPressed: () async {
                      try {
                        final location = await GeolocationService.fetchLocationFromGPS();
                        if (location != null) {
                          final (lat, lon, name) = location;
                          await ref.read(appSettingsProvider.notifier).updateLocation(
                            latitude: lat,
                            longitude: lon,
                            elevation: 0, 
                          );
                          if (context.mounted) {
                            context.showSuccessSnackBar('Location updated: $name');
                          }
                        } else {
                          if (context.mounted) {
                            context.showWarningSnackBar('Could not get GPS location. Check permissions.');
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          context.showErrorSnackBar('Error: $e');
                        }
                      }
                    },
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Time',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.clock,
                  title: 'Timezone',
                  trailing: _SettingsDropdown(
                    value: settings.timezone,
                    items: _getTimezones(),
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setTimezone(value);
                      }
                    },
                    colors: widget.colors,
                    width: 200,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.globe,
                  title: 'Use system time',
                  subtitle: 'Sync time from operating system',
                  trailing: _SettingsSwitch(
                    value: settings.useSystemTime,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setUseSystemTime(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<String> _getTimezones() {
    return [
      'UTC',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
      'America/Phoenix',
      'America/Anchorage',
      'Pacific/Honolulu',
      'Europe/London',
      'Europe/Paris',
      'Europe/Berlin',
      'Europe/Moscow',
      'Asia/Tokyo',
      'Asia/Shanghai',
      'Asia/Kolkata',
      'Australia/Sydney',
      'Australia/Perth',
      'Pacific/Auckland',
    ];
  }
}

// ============================================================================
// Imaging Settings
// ============================================================================

class _ImagingSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _ImagingSettings({required this.colors});

  @override
  ConsumerState<_ImagingSettings> createState() => _ImagingSettingsState();
}

class _ImagingSettingsState extends ConsumerState<_ImagingSettings> {
  final _patternController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _patternController.text = settings.fileNamingPattern;
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);
        
        return _SettingsPage(
          title: 'Imaging',
          description: 'Default capture settings',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'File Format',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.file,
                  title: 'Image format',
                  subtitle: 'Output file format for captured images',
                  trailing: _SettingsDropdown(
                    value: settings.imageFormat,
                    items: const ['FITS', 'XISF', 'TIFF'],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setImageFormat(value);
                      }
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.binary,
                  title: 'Bit depth',
                  subtitle: 'Image bit depth for output files',
                  trailing: _SettingsDropdown(
                    value: settings.bitDepth,
                    items: const ['16-bit', '32-bit'],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setBitDepth(value);
                      }
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.fileText,
                  title: 'File naming pattern',
                  subtitle: r'Variables: $TARGET, $FILTER, $DATE, $SEQ, $EXPOSURE',
                  trailing: _TextInput(
                    controller: _patternController,
                    width: 220,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setFileNamingPattern(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Annotation Settings
// ============================================================================

class _AnnotationSettings extends ConsumerWidget {
  final NightshadeColors colors;

  const _AnnotationSettings({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(annotationSettingsProvider);
    final markerStyleAsync = ref.watch(annotationMarkerStyleProvider);
    final settingsNotifier = ref.read(annotationSettingsProvider.notifier);
    final markerNotifier = ref.read(annotationMarkerStyleProvider.notifier);

    final settings = settingsAsync.valueOrNull ?? const AnnotationSettings();
    final markerStyle = markerStyleAsync.valueOrNull ?? const AnnotationMarkerStyle();

    return _SettingsPage(
      title: 'Annotations',
      description: 'Configure object annotations on captured images',
      colors: colors,
      children: [
        // Display Settings
        _SettingsSection(
          title: 'Display',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.eye,
              title: 'Enable annotations',
              subtitle: 'Show object annotations on images',
              trailing: Switch(
                value: settings.enabled,
                onChanged: (value) => settingsNotifier.setEnabled(value),
                activeThumbColor: colors.primary,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.tag,
              title: 'Show labels',
              subtitle: 'Display object names next to markers',
              trailing: Switch(
                value: settings.showLabels,
                onChanged: (value) => settingsNotifier.setShowLabels(value),
                activeThumbColor: colors.primary,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.hash,
              title: 'Show magnitudes',
              subtitle: 'Display magnitude values with labels',
              trailing: Switch(
                value: settings.showMagnitudes,
                onChanged: (value) => settingsNotifier.setShowMagnitudes(value),
                activeThumbColor: colors.primary,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.listTree,
              title: 'Max objects to display',
              subtitle: 'Limit number of annotations for performance',
              trailing: _CompactSlider(
                value: settings.maxObjectsToDisplay.toDouble(),
                min: 50,
                max: 2000,
                divisions: 39,
                label: settings.maxObjectsToDisplay.toString(),
                onChanged: (value) => settingsNotifier.setMaxObjectsToDisplay(value.toInt()),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Magnitude Filtering
        _SettingsSection(
          title: 'Magnitude Filter',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.sunDim,
              title: 'Minimum magnitude',
              subtitle: 'Brightest objects to show (lower = brighter)',
              trailing: _CompactSlider(
                value: settings.minMagnitude,
                min: -5,
                max: 10,
                divisions: 30,
                label: settings.minMagnitude.toStringAsFixed(1),
                onChanged: (value) => settingsNotifier.setMinMagnitude(value),
                colors: colors,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.sunMedium,
              title: 'Maximum magnitude',
              subtitle: 'Faintest objects to show (higher = fainter)',
              trailing: _CompactSlider(
                value: settings.magnitudeCutoff,
                min: 8,
                max: 22,
                divisions: 28,
                label: settings.magnitudeCutoff.toStringAsFixed(1),
                onChanged: (value) => settingsNotifier.setMagnitudeCutoff(value),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Object Types
        _SettingsSection(
          title: 'Object Types',
          colors: colors,
          children: [
            _ObjectTypeToggle(
              title: 'Galaxies',
              icon: LucideIcons.circle,
              color: Color(markerStyle.galaxyColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.galaxies),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.galaxies),
              colors: colors,
            ),
            _ObjectTypeToggle(
              title: 'Nebulae',
              icon: LucideIcons.cloud,
              color: Color(markerStyle.nebulaColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.nebulae),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.nebulae),
              colors: colors,
            ),
            _ObjectTypeToggle(
              title: 'Star Clusters',
              icon: LucideIcons.sparkles,
              color: Color(markerStyle.clusterColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.starClusters),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.starClusters),
              colors: colors,
            ),
            _ObjectTypeToggle(
              title: 'Planetary Nebulae',
              icon: LucideIcons.target,
              color: Color(markerStyle.planetaryNebulaColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.planetaryNebulae),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.planetaryNebulae),
              colors: colors,
            ),
            _ObjectTypeToggle(
              title: 'Stars',
              icon: LucideIcons.star,
              color: Color(markerStyle.starColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.stars),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.stars),
              colors: colors,
            ),
            _ObjectTypeToggle(
              title: 'Other Objects',
              icon: LucideIcons.helpCircle,
              color: Color(markerStyle.otherColor),
              isEnabled: settings.visibleTypes.contains(AnnotationObjectFilter.other),
              onChanged: (value) => settingsNotifier.toggleObjectType(AnnotationObjectFilter.other),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Fade Effects
        _SettingsSection(
          title: 'Fade Effects',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.mousePointer,
              title: 'Fade when not hovering',
              subtitle: 'Dim annotations when mouse leaves image',
              trailing: Switch(
                value: settings.fadeWhenNotHovering,
                onChanged: (value) => settingsNotifier.setFadeWhenNotHovering(value),
                activeThumbColor: colors.primary,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.sun,
              title: 'Hover opacity',
              subtitle: 'Brightness when mouse is over image',
              trailing: _CompactSlider(
                value: settings.hoverOpacity,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                label: '${(settings.hoverOpacity * 100).toInt()}%',
                onChanged: (value) => settingsNotifier.setHoverOpacity(value),
                colors: colors,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.moon,
              title: 'Idle opacity',
              subtitle: 'Brightness when mouse leaves image',
              trailing: _CompactSlider(
                value: settings.idleOpacity,
                min: 0.0,
                max: 0.5,
                divisions: 10,
                label: '${(settings.idleOpacity * 100).toInt()}%',
                onChanged: (value) => settingsNotifier.setIdleOpacity(value),
                colors: colors,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.timer,
              title: 'Fade duration',
              subtitle: 'Animation speed in milliseconds',
              trailing: _CompactSlider(
                value: settings.fadeAnimationMs.toDouble(),
                min: 100,
                max: 1000,
                divisions: 9,
                label: '${settings.fadeAnimationMs}ms',
                onChanged: (value) => settingsNotifier.setFadeAnimationMs(value.toInt()),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Click to Identify
        _SettingsSection(
          title: 'Click to Identify',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.mousePointerClick,
              title: 'Enable click to identify',
              subtitle: 'Click on image to identify objects',
              trailing: Switch(
                value: settings.clickToIdentify,
                onChanged: (value) => settingsNotifier.setClickToIdentify(value),
                activeThumbColor: colors.primary,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.crosshair,
              title: 'Search radius',
              subtitle: 'Distance to search for objects (arcseconds)',
              trailing: _CompactSlider(
                value: settings.clickSearchRadiusArcsec,
                min: 5,
                max: 120,
                divisions: 23,
                label: '${settings.clickSearchRadiusArcsec.toInt()}"',
                onChanged: (value) => settingsNotifier.setClickSearchRadius(value),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Marker Styles
        _SettingsSection(
          title: 'Marker Styles',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.pencil,
              title: 'Stroke width',
              subtitle: 'Thickness of marker outlines',
              trailing: _CompactSlider(
                value: markerStyle.strokeWidth,
                min: 0.5,
                max: 4.0,
                divisions: 7,
                label: markerStyle.strokeWidth.toStringAsFixed(1),
                onChanged: (value) => markerNotifier.setStrokeWidth(value),
                colors: colors,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.type,
              title: 'Label font size',
              subtitle: 'Size of text labels',
              trailing: _CompactSlider(
                value: markerStyle.labelFontSize,
                min: 8,
                max: 18,
                divisions: 10,
                label: '${markerStyle.labelFontSize.toInt()}px',
                onChanged: (value) => markerNotifier.setLabelFontSize(value),
                colors: colors,
              ),
              colors: colors,
            ),
            _SettingRow(
              icon: LucideIcons.scaling,
              title: 'Scale by object size',
              subtitle: 'Larger objects get larger markers',
              trailing: Switch(
                value: markerStyle.scaleBySize,
                onChanged: (value) => markerNotifier.setScaleBySize(value),
                activeThumbColor: colors.primary,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Automation
        _SettingsSection(
          title: 'Automation',
          colors: colors,
          children: [
            _SettingRow(
              icon: LucideIcons.zap,
              title: 'Auto-annotate images',
              subtitle: 'Automatically annotate plate-solved images',
              trailing: Switch(
                value: settings.autoAnnotate,
                onChanged: (value) => settingsNotifier.setAutoAnnotate(value),
                activeThumbColor: colors.primary,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Reset Button
        Center(
          child: TextButton.icon(
            onPressed: () {
              settingsNotifier.reset();
              markerNotifier.reset();
            },
            icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.warning),
            label: Text(
              'Reset to Defaults',
              style: TextStyle(color: colors.warning),
            ),
          ),
        ),
      ],
    );
  }
}

/// Toggle widget for object type filters
class _ObjectTypeToggle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;
  final bool isLast;
  final NightshadeColors colors;

  const _ObjectTypeToggle({
    required this.title,
    required this.icon,
    required this.color,
    required this.isEnabled,
    required this.onChanged,
    this.isLast = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: isEnabled ? 'Visible' : 'Hidden',
      trailing: Switch(
        value: isEnabled,
        onChanged: onChanged,
        activeThumbColor: color,
      ),
      isLast: isLast,
      colors: colors,
    );
  }
}

/// Compact slider widget for settings
class _CompactSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;

  const _CompactSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Sequencer Settings
// ============================================================================

class _SequencerSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _SequencerSettings({required this.colors});

  @override
  ConsumerState<_SequencerSettings> createState() => _SequencerSettingsState();
}

class _SequencerSettingsState extends ConsumerState<_SequencerSettings> {
  // Sequencer settings controllers
  final _autoFocusController = TextEditingController();
  final _ditherController = TextEditingController();

  // Meridian flip settings controllers
  final _minutesPastMeridianController = TextEditingController();
  final _minutesBeforeLimitController = TextEditingController();
  final _hourAngleThresholdController = TextEditingController();
  final _settleTimeController = TextEditingController();
  final _maxRetriesController = TextEditingController();

  bool _initialized = false;
  bool _meridianInitialized = false;

  @override
  void dispose() {
    _autoFocusController.dispose();
    _ditherController.dispose();
    _minutesPastMeridianController.dispose();
    _minutesBeforeLimitController.dispose();
    _hourAngleThresholdController.dispose();
    _settleTimeController.dispose();
    _maxRetriesController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _autoFocusController.text = settings.autoFocusEveryMinutes.toString();
      _ditherController.text = settings.ditherEveryFrames.toString();
      _initialized = true;
    }
  }

  void _initMeridianControllers(MeridianFlipSettings settings) {
    if (!_meridianInitialized) {
      _minutesPastMeridianController.text = settings.minutesPastMeridian.toString();
      _minutesBeforeLimitController.text = settings.minutesBeforeLimit.toString();
      _hourAngleThresholdController.text = settings.hourAngleThreshold.toString();
      _settleTimeController.text = settings.settleTimeSeconds.toString();
      _maxRetriesController.text = settings.maxRetries.toString();
      _meridianInitialized = true;
    }
  }

  String _getFailModeDescription(SafetyFailMode mode) {
    return switch (mode) {
      SafetyFailMode.failOpen => 'Continue imaging when safety data unavailable',
      SafetyFailMode.failClosed => 'Park mount when safety data unavailable',
      SafetyFailMode.warnOnly => 'Show warning but continue imaging',
    };
  }

  String _failModeToString(SafetyFailMode mode) {
    return switch (mode) {
      SafetyFailMode.failOpen => 'Fail Open (Continue)',
      SafetyFailMode.failClosed => 'Fail Closed (Park)',
      SafetyFailMode.warnOnly => 'Warn Only',
    };
  }

  SafetyFailMode _stringToFailMode(String value) {
    return switch (value) {
      'Fail Open (Continue)' => SafetyFailMode.failOpen,
      'Fail Closed (Park)' => SafetyFailMode.failClosed,
      'Warn Only' => SafetyFailMode.warnOnly,
      _ => SafetyFailMode.failOpen,
    };
  }

  Widget _buildMeridianFlipSection(MeridianFlipSettings flipSettings) {
    final notifier = ref.read(globalMeridianFlipSettingsProvider.notifier);

    return _SettingsSection(
      title: 'Meridian Flip',
      colors: widget.colors,
      children: [
        // Standalone monitoring
        _SettingRow(
          icon: LucideIcons.eye,
          title: 'Standalone monitoring',
          subtitle: 'Monitor meridian even when no sequence is running',
          trailing: _SettingsSwitch(
            value: flipSettings.standaloneMonitoringEnabled,
            onChanged: (value) {
              notifier.setStandaloneMonitoringEnabled(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Trigger method
        _SettingRow(
          icon: LucideIcons.crosshair,
          title: 'Trigger method',
          subtitle: flipSettings.triggerMethod.description,
          trailing: _SettingsDropdown(
            value: flipSettings.triggerMethod.displayName,
            items: MeridianTriggerMethod.values.map((e) => e.displayName).toList(),
            onChanged: (value) {
              if (value != null) {
                final method = MeridianTriggerMethod.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setTriggerMethod(method);
              }
            },
            colors: widget.colors,
            width: 200,
          ),
          colors: widget.colors,
        ),
        // Trigger value - minutes past meridian
        if (flipSettings.triggerMethod == MeridianTriggerMethod.minutesPastMeridian)
          _SettingRow(
            icon: LucideIcons.timer,
            title: 'Minutes past meridian',
            subtitle: 'Flip after target crosses meridian by this amount',
            trailing: _NumberInput(
              controller: _minutesPastMeridianController,
              suffix: 'min',
              min: 0,
              max: 120,
              decimals: 1,
              onChanged: (value) {
                notifier.setMinutesPastMeridian(value);
              },
              colors: widget.colors,
            ),
            colors: widget.colors,
          ),
        // Trigger value - minutes before limit
        if (flipSettings.triggerMethod == MeridianTriggerMethod.minutesBeforeLimit)
          _SettingRow(
            icon: LucideIcons.timer,
            title: 'Minutes before limit',
            subtitle: 'Flip before mount reaches tracking limit',
            trailing: _NumberInput(
              controller: _minutesBeforeLimitController,
              suffix: 'min',
              min: 0,
              max: 120,
              decimals: 1,
              onChanged: (value) {
                notifier.setMinutesBeforeLimit(value);
              },
              colors: widget.colors,
            ),
            colors: widget.colors,
          ),
        // Trigger value - hour angle threshold
        if (flipSettings.triggerMethod == MeridianTriggerMethod.hourAngleThreshold)
          _SettingRow(
            icon: LucideIcons.timer,
            title: 'Hour angle threshold',
            subtitle: 'Flip when hour angle exceeds this value',
            trailing: _NumberInput(
              controller: _hourAngleThresholdController,
              suffix: 'h',
              min: 0,
              max: 6,
              decimals: 2,
              onChanged: (value) {
                notifier.setHourAngleThreshold(value);
              },
              colors: widget.colors,
            ),
            colors: widget.colors,
          ),
        // Flip sequence - pause guiding
        _SettingRow(
          icon: LucideIcons.pause,
          title: 'Pause guiding before flip',
          subtitle: 'Temporarily stop autoguider during flip',
          trailing: _SettingsSwitch(
            value: flipSettings.pauseGuidingBeforeFlip,
            onChanged: (value) {
              notifier.setPauseGuidingBeforeFlip(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Flip sequence - recenter
        _SettingRow(
          icon: LucideIcons.crosshair,
          title: 'Recenter after flip',
          subtitle: 'Plate solve and re-center target after flip',
          trailing: _SettingsSwitch(
            value: flipSettings.recenterAfterFlip,
            onChanged: (value) {
              notifier.setRecenterAfterFlip(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Flip sequence - refocus
        _SettingRow(
          icon: LucideIcons.focus,
          title: 'Refocus after flip',
          subtitle: 'Run autofocus after flip completes',
          trailing: _SettingsSwitch(
            value: flipSettings.refocusAfterFlip,
            onChanged: (value) {
              notifier.setRefocusAfterFlip(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Flip sequence - resume guiding
        _SettingRow(
          icon: LucideIcons.play,
          title: 'Resume guiding after flip',
          subtitle: 'Restart autoguider if it was running',
          trailing: _SettingsSwitch(
            value: flipSettings.resumeGuidingAfterFlip,
            onChanged: (value) {
              notifier.setResumeGuidingAfterFlip(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Settle time
        _SettingRow(
          icon: LucideIcons.clock,
          title: 'Settle time',
          subtitle: 'Wait time after flip before resuming',
          trailing: _NumberInput(
            controller: _settleTimeController,
            suffix: 'sec',
            min: 0,
            max: 300,
            decimals: 0,
            onChanged: (value) {
              notifier.setSettleTimeSeconds(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Error handling - max retries
        _SettingRow(
          icon: LucideIcons.repeat,
          title: 'Max retries',
          subtitle: 'Number of retry attempts if flip fails',
          trailing: _NumberInput(
            controller: _maxRetriesController,
            suffix: '',
            min: 0,
            max: 10,
            decimals: 0,
            onChanged: (value) {
              notifier.setMaxRetries(value.toInt());
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Error handling - failure action
        _SettingRow(
          icon: LucideIcons.alertTriangle,
          title: 'On failure',
          subtitle: flipSettings.failureAction.description,
          trailing: _SettingsDropdown(
            value: flipSettings.failureAction.displayName,
            items: FlipFailureAction.values.map((e) => e.displayName).toList(),
            onChanged: (value) {
              if (value != null) {
                final action = FlipFailureAction.values
                    .firstWhere((e) => e.displayName == value);
                notifier.setFailureAction(action);
              }
            },
            colors: widget.colors,
            width: 160,
          ),
          colors: widget.colors,
        ),
        // Notifications - sound
        _SettingRow(
          icon: LucideIcons.volume2,
          title: 'Sound alert',
          subtitle: 'Play sound when flip starts/completes/fails',
          trailing: _SettingsSwitch(
            value: flipSettings.soundAlertOnFlip,
            onChanged: (value) {
              notifier.setSoundAlertOnFlip(value);
            },
            colors: widget.colors,
          ),
          colors: widget.colors,
        ),
        // Notifications - push
        _SettingRow(
          icon: LucideIcons.bell,
          title: 'Push notification',
          subtitle: 'Send notification to mobile app',
          trailing: _SettingsSwitch(
            value: flipSettings.pushNotificationOnFlip,
            onChanged: (value) {
              notifier.setPushNotificationOnFlip(value);
            },
            colors: widget.colors,
          ),
          isLast: true,
          colors: widget.colors,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final flipSettings = ref.watch(globalMeridianFlipSettingsProvider);
    _initMeridianControllers(flipSettings);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);

        return _SettingsPage(
          title: 'Sequencer',
          description: 'Automation and sequence settings',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'Safety',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.shieldAlert,
                  title: 'Park on unsafe weather',
                  subtitle: 'Automatically park mount when weather becomes unsafe',
                  trailing: _SettingsSwitch(
                    value: settings.parkOnUnsafeWeather,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setParkOnUnsafeWeather(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.sunrise,
                  title: 'Park before dawn',
                  subtitle: 'Automatically park mount before astronomical dawn',
                  trailing: _SettingsSwitch(
                    value: settings.parkBeforeDawn,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setParkBeforeDawn(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: 'Safety fail mode',
                  subtitle: _getFailModeDescription(settings.safetyFailMode),
                  trailing: _SettingsDropdown(
                    value: _failModeToString(settings.safetyFailMode),
                    items: const ['Fail Open (Continue)', 'Fail Closed (Park)', 'Warn Only'],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setSafetyFailMode(_stringToFailMode(value));
                      }
                    },
                    colors: widget.colors,
                    width: 180,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _buildMeridianFlipSection(flipSettings),
            _SettingsSection(
              title: 'Auto Focus',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.focus,
                  title: 'Auto focus on filter change',
                  subtitle: 'Run auto focus when switching filters',
                  trailing: _SettingsSwitch(
                    value: settings.autoFocusOnFilterChange,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setAutoFocusOnFilterChange(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.timer,
                  title: 'Auto focus interval',
                  subtitle: 'Run auto focus periodically',
                  trailing: _NumberInput(
                    controller: _autoFocusController,
                    suffix: 'min',
                    min: 0,
                    max: 240,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setAutoFocusEveryMinutes(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Dithering',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.move,
                  title: 'Enable dithering',
                  subtitle: 'Move mount slightly between exposures',
                  trailing: _SettingsSwitch(
                    value: settings.ditherEnabled,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setDitherEnabled(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.hash,
                  title: 'Dither every',
                  subtitle: 'Number of frames between dithers',
                  trailing: _NumberInput(
                    controller: _ditherController,
                    suffix: 'frames',
                    min: 1,
                    max: 20,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setDitherEveryFrames(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Development',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.cpu,
                  title: 'Use native execution',
                  subtitle: 'Execute sequences using native Rust engine',
                  trailing: _SettingsSwitch(
                    value: settings.useNativeExecution,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setUseNativeExecution(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.testTube,
                  title: 'Simulation mode',
                  subtitle: 'Use simulated devices instead of real hardware',
                  trailing: _SettingsSwitch(
                    value: settings.useSimulationMode,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setUseSimulationMode(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Plate Solving Settings
// ============================================================================

class _PlateSolvingSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _PlateSolvingSettings({required this.colors});

  @override
  ConsumerState<_PlateSolvingSettings> createState() => _PlateSolvingSettingsState();
}

class _PlateSolvingSettingsState extends ConsumerState<_PlateSolvingSettings> {
  final _timeoutController = TextEditingController();
  final _radiusController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _timeoutController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _timeoutController.text = settings.plateSolveTimeout.toString();
      _radiusController.text = settings.plateSolveSearchRadius.toStringAsFixed(1);
      _initialized = true;
    }
  }

  Future<void> _selectAstapPath() async {
    String? initialDir;
    if (Platform.isWindows) {
      initialDir = 'C:\\Program Files\\astap';
    } else if (Platform.isMacOS) {
      initialDir = '/Applications';
    }

    final result = await getDirectoryPath(
      initialDirectory: initialDir,
      confirmButtonText: 'Select',
    );

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setAstapPath(result);
    }
  }

  Future<void> _selectAstrometryPath() async {
    final result = await getDirectoryPath(
      confirmButtonText: 'Select',
    );

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setAstrometryPath(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);
        
        return _SettingsPage(
          title: 'Plate Solving',
          description: 'Configure plate solving backends',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'Solver',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.crosshair,
                  title: 'Primary solver',
                  subtitle: 'Select the plate solving engine to use',
                  trailing: _SettingsDropdown(
                    value: settings.plateSolver,
                    items: const ['ASTAP', 'Astrometry.net', 'PlateSolve2'],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setPlateSolver(value);
                      }
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.folder,
                  title: 'ASTAP path',
                  subtitle: settings.astapPath.isEmpty ? 'Not configured' : settings.astapPath,
                  trailing: _PathInput(
                    path: settings.astapPath,
                    onBrowse: _selectAstapPath,
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.folder,
                  title: 'Astrometry.net path',
                  subtitle: settings.astrometryPath.isEmpty ? 'Not configured' : settings.astrometryPath,
                  trailing: _PathInput(
                    path: settings.astrometryPath,
                    onBrowse: _selectAstrometryPath,
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Solve Parameters',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.timer,
                  title: 'Timeout',
                  subtitle: 'Maximum time to attempt solving',
                  trailing: _NumberInput(
                    controller: _timeoutController,
                    suffix: 'sec',
                    min: 10,
                    max: 300,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPlateSolveTimeout(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.search,
                  title: 'Search radius',
                  subtitle: 'Area to search around expected position',
                  trailing: _NumberInput(
                    controller: _radiusController,
                    suffix: '°',
                    min: 1,
                    max: 180,
                    decimals: 1,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPlateSolveSearchRadius(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.compass,
                  title: 'Blind solve',
                  subtitle: 'Solve without position hint (slower)',
                  trailing: _SettingsSwitch(
                    value: settings.blindSolve,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setBlindSolve(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// PHD2 Guiding Settings
// ============================================================================

class _Phd2GuidingSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _Phd2GuidingSettings({required this.colors});

  @override
  ConsumerState<_Phd2GuidingSettings> createState() => _Phd2GuidingSettingsState();
}

class _Phd2GuidingSettingsState extends ConsumerState<_Phd2GuidingSettings> {
  final _portController = TextEditingController();
  final _hostController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _portController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _portController.text = settings.phd2Port.toString();
      _hostController.text = settings.phd2Host;
      _initialized = true;
    }
  }

  Future<void> _selectPhd2Path() async {
    String? initialDir;
    if (Platform.isWindows) {
      initialDir = 'C:\\Program Files';
    } else if (Platform.isMacOS) {
      initialDir = '/Applications';
    }

    final result = await getDirectoryPath(
      initialDirectory: initialDir,
      confirmButtonText: 'Select',
    );

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setPhd2Path(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);

        return _SettingsPage(
          title: 'PHD2 Guiding',
          description: 'Configure PHD2 guiding software connection',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'PHD2 Connection',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.server,
                  title: 'Host',
                  subtitle: 'PHD2 server hostname or IP address',
                  trailing: _TextInput(
                    controller: _hostController,
                    hint: 'localhost',
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPhd2Host(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.network,
                  title: 'Port',
                  subtitle: 'PHD2 server port (default: 4400)',
                  trailing: _NumberInput(
                    controller: _portController,
                    suffix: '',
                    min: 1,
                    max: 65535,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPhd2Port(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.folder,
                  title: 'PHD2 executable path',
                  subtitle: settings.phd2Path.isEmpty ? 'Auto-detect (optional)' : settings.phd2Path,
                  trailing: _PathInput(
                    path: settings.phd2Path,
                    onBrowse: _selectPhd2Path,
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Information',
              colors: widget.colors,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'PHD2 will be automatically detected on common installation paths if not specified. '
                    'The connection settings are used when connecting to PHD2 for guiding operations.',
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Notification Settings
// ============================================================================

class _NotificationSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _NotificationSettings({required this.colors});

  @override
  ConsumerState<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  final _discordController = TextEditingController();
  final _pushoverKeyController = TextEditingController();
  final _pushoverUserController = TextEditingController();
  bool _initialized = false;
  bool _testingDiscord = false;
  bool _testingPushover = false;

  @override
  void dispose() {
    _discordController.dispose();
    _pushoverKeyController.dispose();
    _pushoverUserController.dispose();
    super.dispose();
  }

  Future<void> _testDiscord() async {
    if (_discordController.text.isEmpty) {
      context.showWarningSnackBar('Please enter a Discord webhook URL');
      return;
    }

    setState(() => _testingDiscord = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final success = await notificationService.testDiscordWebhook(_discordController.text);
      if (mounted) {
        if (success) {
          context.showSuccessSnackBar('Discord test notification sent successfully!');
        } else {
          context.showErrorSnackBar('Failed to send Discord notification. Check your webhook URL.');
        }
      }
    } finally {
      if (mounted) setState(() => _testingDiscord = false);
    }
  }

  Future<void> _testPushover() async {
    if (_pushoverKeyController.text.isEmpty || _pushoverUserController.text.isEmpty) {
      context.showWarningSnackBar('Please enter both API key and User key');
      return;
    }

    setState(() => _testingPushover = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final success = await notificationService.testPushover(
        _pushoverKeyController.text,
        _pushoverUserController.text,
      );
      if (mounted) {
        if (success) {
          context.showSuccessSnackBar('Pushover test notification sent successfully!');
        } else {
          context.showErrorSnackBar('Failed to send Pushover notification. Check your API and User keys.');
        }
      }
    } finally {
      if (mounted) setState(() => _testingPushover = false);
    }
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _discordController.text = settings.discordWebhook;
      _pushoverKeyController.text = settings.pushoverKey;
      _pushoverUserController.text = settings.pushoverUser;
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) {
        _initControllers(settings);
        
        return _SettingsPage(
          title: 'Notifications',
          description: 'Configure alerts and notifications',
          colors: widget.colors,
          children: [
            _SettingsSection(
              title: 'General',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.bell,
                  title: 'Enable notifications',
                  subtitle: 'Send notifications for important events',
                  trailing: _SettingsSwitch(
                    value: settings.notificationsEnabled,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setNotificationsEnabled(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.volume2,
                  title: 'Sound alerts',
                  subtitle: 'Play sounds for notifications',
                  trailing: _SettingsSwitch(
                    value: settings.soundEnabled,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setSoundEnabled(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Notification Events',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.checkCircle,
                  title: 'Sequence complete',
                  subtitle: 'Notify when sequence finishes',
                  trailing: _SettingsSwitch(
                    value: settings.notifyOnSequenceComplete,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setNotifyOnSequenceComplete(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.alertCircle,
                  title: 'Errors',
                  subtitle: 'Notify on errors and failures',
                  trailing: _SettingsSwitch(
                    value: settings.notifyOnError,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setNotifyOnError(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.rotateCw,
                  title: 'Meridian flip',
                  subtitle: 'Notify when meridian flip occurs',
                  trailing: _SettingsSwitch(
                    value: settings.notifyOnMeridianFlip,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setNotifyOnMeridianFlip(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Discord',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.messageSquare,
                  title: 'Webhook URL',
                  subtitle: 'Discord channel webhook for notifications',
                  trailing: _TextInput(
                    controller: _discordController,
                    hint: 'https://discord.com/api/webhooks/...',
                    width: 260,
                    obscure: true,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setDiscordWebhook(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.send,
                  title: 'Test Discord',
                  subtitle: 'Send a test notification to your Discord channel',
                  trailing: SizedBox(
                    width: 100,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: _testingDiscord ? null : _testDiscord,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.colors.primary,
                        padding: EdgeInsets.zero,
                      ),
                      child: _testingDiscord
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Test', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            _SettingsSection(
              title: 'Pushover',
              colors: widget.colors,
              children: [
                _SettingRow(
                  icon: LucideIcons.key,
                  title: 'API Key',
                  subtitle: 'Pushover application API key',
                  trailing: _TextInput(
                    controller: _pushoverKeyController,
                    hint: 'API key',
                    width: 200,
                    obscure: true,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPushoverKey(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.user,
                  title: 'User Key',
                  subtitle: 'Pushover user/group key',
                  trailing: _TextInput(
                    controller: _pushoverUserController,
                    hint: 'User key',
                    width: 200,
                    obscure: true,
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPushoverUser(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                _SettingRow(
                  icon: LucideIcons.send,
                  title: 'Test Pushover',
                  subtitle: 'Send a test notification to your device',
                  trailing: SizedBox(
                    width: 100,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: _testingPushover ? null : _testPushover,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.colors.primary,
                        padding: EdgeInsets.zero,
                      ),
                      child: _testingPushover
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Test', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// File Path Settings
// ============================================================================

class _FilePathSettings extends ConsumerWidget {
  final NightshadeColors colors;

  const _FilePathSettings({required this.colors});

  Future<void> _selectPath(WidgetRef ref, String settingKey) async {
    final result = await getDirectoryPath(
      confirmButtonText: 'Select',
    );

    if (result != null) {
      final notifier = ref.read(appSettingsProvider.notifier);
      switch (settingKey) {
        case 'image':
          await notifier.setImageOutputPath(result);
          break;
        case 'sequences':
          await notifier.setSequencesPath(result);
          break;
        case 'database':
          await notifier.setDatabasePath(result);
          break;
        case 'logs':
          await notifier.setLogsPath(result);
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (settings) => _SettingsPage(
        title: 'File Paths',
        description: 'Configure storage locations',
        colors: colors,
        children: [
          _SettingsSection(
            title: 'Storage',
            colors: colors,
            children: [
              _SettingRow(
                icon: LucideIcons.image,
                title: 'Image output',
                subtitle: settings.imageOutputPath.isEmpty ? 'Not configured' : settings.imageOutputPath,
                trailing: _PathInput(
                  path: settings.imageOutputPath,
                  onBrowse: () => _selectPath(ref, 'image'),
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.listOrdered,
                title: 'Sequences',
                subtitle: settings.sequencesPath.isEmpty ? 'Not configured' : settings.sequencesPath,
                trailing: _PathInput(
                  path: settings.sequencesPath,
                  onBrowse: () => _selectPath(ref, 'sequences'),
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.database,
                title: 'Database',
                subtitle: settings.databasePath.isEmpty ? 'Default location' : settings.databasePath,
                trailing: _PathInput(
                  path: settings.databasePath,
                  onBrowse: () => _selectPath(ref, 'database'),
                  colors: colors,
                ),
                colors: colors,
              ),
              _SettingRow(
                icon: LucideIcons.fileText,
                title: 'Logs',
                subtitle: settings.logsPath.isEmpty ? 'Default location' : settings.logsPath,
                trailing: _PathInput(
                  path: settings.logsPath,
                  onBrowse: () => _selectPath(ref, 'logs'),
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// About Settings
// ============================================================================

class _AboutSettings extends StatelessWidget {
  final NightshadeColors colors;

  const _AboutSettings({required this.colors});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsPage(
      title: 'About',
      description: 'Application information',
      colors: colors,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  LucideIcons.sparkles,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Nightshade',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 2.2.0',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Advanced astrophotography suite',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LinkButton(
                    icon: LucideIcons.github,
                    label: 'GitHub',
                    onTap: () => _launchUrl('https://github.com/nightshade-astro'),
                    colors: colors,
                  ),
                  const SizedBox(width: 12),
                  _LinkButton(
                    icon: LucideIcons.bookOpen,
                    label: 'Documentation',
                    onTap: () => _launchUrl('https://nightshade.astro/docs'),
                    colors: colors,
                  ),
                  const SizedBox(width: 12),
                  _LinkButton(
                    icon: LucideIcons.messageCircle,
                    label: 'Discord',
                    onTap: () => _launchUrl('https://discord.gg/nightshade'),
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      'System Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(label: 'Platform', value: Platform.operatingSystem, colors: colors),
                    _InfoRow(label: 'OS Version', value: Platform.operatingSystemVersion, colors: colors),
                    _InfoRow(label: 'Dart Version', value: Platform.version.split(' ').first, colors: colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Widget Components
// ============================================================================

class _SettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final NightshadeColors colors;

  const _SettingsSwitch({
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.primary : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? colors.primary : colors.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final NightshadeColors colors;
  final double width;

  const _SettingsDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.colors,
    this.width = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 14,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: 12,
            color: colors.textPrimary,
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TextInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final double width;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final NightshadeColors colors;

  const _TextInput({
    required this.controller,
    this.hint,
    this.width = 160,
    this.obscure = false,
    required this.onChanged,
    required this.colors,
  });

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: 32,
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: widget.obscure && _obscured,
              style: TextStyle(
                fontSize: 12,
                color: widget.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: widget.colors.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.obscure)
            GestureDetector(
              onTap: () => setState(() => _obscured = !_obscured),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  _obscured ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 14,
                  color: widget.colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberInput extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;

  const _NumberInput({
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 32,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  final clamped = parsed.clamp(min, max);
                  onChanged(clamped);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final String selectedColor;
  final ValueChanged<String> onColorSelected;
  final NightshadeColors colors;

  const _ColorPicker({
    required this.selectedColor,
    required this.onColorSelected,
    required this.colors,
  });

  static const _accentColors = [
    ('#6366F1', 'Indigo'),
    ('#10B981', 'Emerald'),
    ('#F59E0B', 'Amber'),
    ('#EF4444', 'Red'),
    ('#8B5CF6', 'Violet'),
    ('#EC4899', 'Pink'),
    ('#06B6D4', 'Cyan'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _accentColors.map((colorData) {
        final (hex, _) = colorData;
        final color = Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
        final isSelected = selectedColor.toLowerCase() == hex.toLowerCase();
        
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: GestureDetector(
            onTap: () => onColorSelected(hex),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PathInput extends StatelessWidget {
  final String path;
  final VoidCallback onBrowse;
  final NightshadeColors colors;

  const _PathInput({
    required this.path,
    required this.onBrowse,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            path.isEmpty ? 'Not set' : path,
            style: TextStyle(
              fontSize: 11,
              color: path.isEmpty ? colors.textMuted : colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onBrowse,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              LucideIcons.folderOpen,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_LinkButton> createState() => _LinkButtonState();
}

class _LinkButtonState extends State<_LinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.surfaceAlt
                : widget.colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
