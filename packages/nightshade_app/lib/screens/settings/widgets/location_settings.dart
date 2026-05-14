import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Hide HorizonProfile from the barrel — the barrel publishes the
// scheduler's samples-based class. This file needs the legacy 8-point
// compass class, which we pull in directly via the leaf path below.
import 'package:nightshade_core/nightshade_core.dart' hide HorizonProfile;
import 'package:nightshade_core/src/providers/settings_provider.dart'
    show HorizonProfile;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class LocationSettingsPage extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const LocationSettingsPage(
      {super.key, required this.colors, this.isMobile = false});

  @override
  ConsumerState<LocationSettingsPage> createState() => _LocationSettingsState();
}

class _LocationSettingsState extends ConsumerState<LocationSettingsPage> {
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _elevController = TextEditingController();
  final Map<String, TextEditingController> _horizonControllers = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    for (final dir in horizonDirections) {
      _horizonControllers[dir] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _elevController.dispose();
    for (final c in _horizonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _latController.text = settings.latitude.toStringAsFixed(6);
      _lonController.text = settings.longitude.toStringAsFixed(6);
      _elevController.text = settings.elevation.toStringAsFixed(0);

      final profile = HorizonProfile.fromJson(settings.horizonProfileJson);
      for (final dir in horizonDirections) {
        _horizonControllers[dir]!.text =
            profile.altitudeAt(dir).toStringAsFixed(0);
      }
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        colors: widget.colors,
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _initControllers(settings);

        return SettingsPage(
          key: SettingsTutorialKeys.location,
          title: 'Location',
          description: 'Observatory location for calculations',
          colors: widget.colors,
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: 'Coordinates',
              colors: widget.colors,
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Latitude',
                  subtitle: 'Positive for North, negative for South',
                  trailing: SettingsNumberInput(
                    controller: _latController,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 6,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setLatitude(value);
                    },
                    colors: widget.colors,
                    isMobile: widget.isMobile,
                  ),
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Longitude',
                  subtitle: 'Positive for East, negative for West',
                  trailing: SettingsNumberInput(
                    controller: _lonController,
                    suffix: '\u00B0',
                    min: -180,
                    max: 180,
                    decimals: 6,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setLongitude(value);
                    },
                    colors: widget.colors,
                    isMobile: widget.isMobile,
                  ),
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.mountain,
                  title: 'Elevation',
                  subtitle: 'Height above sea level',
                  trailing: SettingsNumberInput(
                    controller: _elevController,
                    suffix: 'm',
                    min: -500,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setElevation(value);
                    },
                    colors: widget.colors,
                    isMobile: widget.isMobile,
                  ),
                  isLast: false,
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.refreshCw,
                  title: 'Sync from Server',
                  subtitle: 'Fetch location from Headless Server',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.downloadCloud,
                        color: widget.colors.primary),
                    onPressed: () async {
                      try {
                        final backend = ref.read(backendProvider);
                        final location = await backend.getLocation();

                        if (location != null) {
                          await ref
                              .read(appSettingsProvider.notifier)
                              .updateLocation(
                                latitude: location.latitude,
                                longitude: location.longitude,
                                elevation: location.elevation,
                              );
                        }

                        if (context.mounted) {
                          context.showSuccessSnackBar(
                              'Location synced from server');
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
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.locate,
                  title: 'Use Device Location',
                  subtitle: 'Get location from GPS',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.crosshair,
                        color: widget.colors.primary),
                    onPressed: () async {
                      try {
                        final location =
                            await GeolocationService.fetchLocationFromGPS();
                        if (location != null) {
                          final (lat, lon, name) = location;
                          await ref
                              .read(appSettingsProvider.notifier)
                              .updateLocation(
                                latitude: lat,
                                longitude: lon,
                                elevation: 0,
                              );
                          if (context.mounted) {
                            context
                                .showSuccessSnackBar('Location updated: $name');
                          }
                        } else {
                          if (context.mounted) {
                            context.showWarningSnackBar(
                                'Could not get GPS location. Check permissions.');
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
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Observing Environment',
              colors: widget.colors,
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.sun,
                  title: 'Bortle Class',
                  subtitle: BortleScale.description(settings.bortleClass),
                  trailing: SettingsDropdown(
                    value: settings.bortleClass.toString(),
                    items: List.generate(9, (i) => '${i + 1}'),
                    itemLabels: List.generate(
                      9,
                      (i) =>
                          '${i + 1} - ${BortleScale.description(i + 1)}',
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setBortleClass(int.parse(value));
                      }
                    },
                    colors: widget.colors,
                    width: widget.isMobile ? 200 : 280,
                    isMobile: widget.isMobile,
                  ),
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.eye,
                  title: 'Limiting Magnitude',
                  subtitle: 'Estimated naked-eye limit for Bortle ${settings.bortleClass}',
                  trailing: Text(
                    '${BortleScale.limitingMagnitude(settings.bortleClass).toStringAsFixed(1)}m',
                    style: TextStyle(
                      color: widget.colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  isLast: true,
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Local Horizon Mask',
              colors: widget.colors,
              isMobile: widget.isMobile,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Text(
                    'Set minimum observable altitude at each compass direction. '
                    'Objects below these altitudes are considered obstructed by terrain, '
                    'trees, or buildings.',
                    style: TextStyle(
                      color: widget.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                ...List.generate(horizonDirections.length, (i) {
                  final dir = horizonDirections[i];
                  final azimuth = horizonDirectionAzimuths[i];
                  return SettingRow(
                    icon: _compassIcon(dir),
                    title: '$dir (${azimuth.toStringAsFixed(0)}\u00B0)',
                    subtitle: 'Horizon altitude at $dir',
                    trailing: SettingsNumberInput(
                      controller: _horizonControllers[dir]!,
                      suffix: '\u00B0',
                      min: 0,
                      max: 89,
                      decimals: 0,
                      onChanged: (value) async {
                        _updateHorizonProfile();
                      },
                      colors: widget.colors,
                      isMobile: widget.isMobile,
                    ),
                    isLast: i == horizonDirections.length - 1,
                    colors: widget.colors,
                    isMobile: widget.isMobile,
                  );
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(LucideIcons.rotateCcw, size: 14,
                            color: widget.colors.primary),
                        label: Text('Reset All to 0\u00B0',
                            style: TextStyle(color: widget.colors.primary, fontSize: 12)),
                        onPressed: () {
                          for (final dir in horizonDirections) {
                            _horizonControllers[dir]!.text = '0';
                          }
                          _updateHorizonProfile();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'Time',
              colors: widget.colors,
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.clock,
                  title: 'Timezone',
                  trailing: SettingsDropdown(
                    value: settings.timezone,
                    items: _getTimezones(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setTimezone(value);
                      }
                    },
                    colors: widget.colors,
                    width: widget.isMobile ? 160 : 200,
                    isMobile: widget.isMobile,
                  ),
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.globe,
                  title: 'Use system time',
                  subtitle: 'Sync time from operating system',
                  trailing: SettingsSwitch(
                    value: settings.useSystemTime,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setUseSystemTime(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _updateHorizonProfile() {
    final parts = <String>[];
    for (final dir in horizonDirections) {
      final text = _horizonControllers[dir]!.text;
      final val = double.tryParse(text)?.clamp(0.0, 89.0) ?? 0.0;
      parts.add('"$dir":${val.toStringAsFixed(1)}');
    }
    final json = '{${parts.join(',')}}';
    ref.read(appSettingsProvider.notifier).setHorizonProfileJson(json);
  }

  IconData _compassIcon(String direction) {
    return switch (direction) {
      'N' => LucideIcons.arrowUp,
      'NE' => LucideIcons.arrowUpRight,
      'E' => LucideIcons.arrowRight,
      'SE' => LucideIcons.arrowDownRight,
      'S' => LucideIcons.arrowDown,
      'SW' => LucideIcons.arrowDownLeft,
      'W' => LucideIcons.arrowLeft,
      'NW' => LucideIcons.arrowUpLeft,
      _ => LucideIcons.compass,
    };
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
