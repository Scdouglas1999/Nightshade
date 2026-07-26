import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// The barrel's `HorizonProfile` is the scheduler's samples-based class;
// this screen needs the legacy 8-point compass profile, exported through
// the barrel under the `LegacyHorizonProfile` alias (see
// `src/legacy_aliases.dart`).
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

typedef HorizonImportPicker = Future<file_selector.XFile?> Function();
typedef HorizonImportReader = Future<String> Function(
  file_selector.XFile file,
);

Future<file_selector.XFile?> _pickHorizonImport() {
  return file_selector.openFile(
    acceptedTypeGroups: [
      const file_selector.XTypeGroup(
        label: 'Horizon profile (.hor / .csv / .txt)',
        extensions: ['hor', 'csv', 'txt'],
      ),
    ],
  );
}

final horizonImportPickerProvider =
    Provider<HorizonImportPicker>((ref) => _pickHorizonImport);

final horizonImportReaderProvider = Provider<HorizonImportReader>(
  (ref) => (file) => File(file.path).readAsString(),
);

class LocationSettingsPage extends ConsumerStatefulWidget {
  final bool isMobile;

  const LocationSettingsPage({super.key, this.isMobile = false});

  @override
  ConsumerState<LocationSettingsPage> createState() => _LocationSettingsState();
}

class _LocationSettingsState extends ConsumerState<LocationSettingsPage> {
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _elevController = TextEditingController();
  final Map<String, TextEditingController> _horizonControllers = {};
  bool _isImportingHorizon = false;
  int _horizonImportGeneration = 0;

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

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (!_isImportingHorizon ||
          previous == null ||
          identical(previous, next)) {
        return;
      }
      _horizonImportGeneration++;
      setState(() => _isImportingHorizon = false);
    });

    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        final authority = ref.watch(backendProvider);
        final isRemoteMode = ref.watch(isRemoteModeProvider);
        final horizonProfile =
            LegacyHorizonProfile.fromJson(settings.horizonProfileJson);

        return SettingsPage(
          key: SettingsTutorialKeys.location,
          title: 'Location',
          description: 'Observatory location for calculations',
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: 'Coordinates',
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Latitude',
                  subtitle: 'Positive for North, negative for South',
                  trailing: SettingsNumberInput(
                    controller: _latController,
                    authoritativeValue: settings.latitude,
                    authorityKey: authority,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 6,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setLatitude(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.mapPin,
                  title: 'Longitude',
                  subtitle: 'Positive for East, negative for West',
                  trailing: SettingsNumberInput(
                    controller: _lonController,
                    authoritativeValue: settings.longitude,
                    authorityKey: authority,
                    suffix: '\u00B0',
                    min: -180,
                    max: 180,
                    decimals: 6,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setLongitude(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.mountain,
                  title: 'Elevation',
                  subtitle: 'Height above sea level',
                  trailing: SettingsNumberInput(
                    controller: _elevController,
                    authoritativeValue: settings.elevation,
                    authorityKey: authority,
                    suffix: 'm',
                    min: -500,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setElevation(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isLast: false,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.refreshCw,
                  title: 'Sync from Server',
                  subtitle: 'Fetch location from Headless Server',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.downloadCloud,
                        color: NightshadeColors.of(context).primary),
                    onPressed: () async {
                      try {
                        final actionAuthority = ref.read(backendProvider);
                        final backend =
                            ref.read(profileSettingsBackendProvider);
                        final location = await backend.getLocation();

                        if (!mounted ||
                            !identical(
                              ref.read(backendProvider),
                              actionAuthority,
                            )) {
                          if (mounted) {
                            this.context.showWarningSnackBar(
                                  'The imaging host changed while syncing. Try '
                                  'again on the current host.',
                                );
                          }
                          return;
                        }

                        if (location != null) {
                          await ref
                              .read(appSettingsProvider.notifier)
                              .updateLocation(
                                latitude: location.latitude,
                                longitude: location.longitude,
                                elevation: location.elevation,
                              );
                          if (context.mounted) {
                            context.showSuccessSnackBar(
                                'Location synced from server');
                          }
                        } else {
                          if (context.mounted) {
                            this.context.showWarningSnackBar(
                                'No location available from server');
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          context.showErrorSnackBar('Sync failed: $e');
                        }
                      }
                    },
                  ),
                  isLast: false,
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.locate,
                  title: 'Use Device Location',
                  subtitle: 'Get location from GPS',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.crosshair,
                        color: NightshadeColors.of(context).primary),
                    onPressed: () async {
                      try {
                        final actionAuthority = ref.read(backendProvider);
                        final location =
                            await GeolocationService.fetchLocationFromGPS();
                        if (!mounted ||
                            !identical(
                              ref.read(backendProvider),
                              actionAuthority,
                            )) {
                          if (mounted) {
                            this.context.showWarningSnackBar(
                                  'The imaging host changed while reading the '
                                  'device location. Try again on the current host.',
                                );
                          }
                          return;
                        }
                        if (location != null) {
                          final (lat, lon, name) = location;
                          await ref
                              .read(appSettingsProvider.notifier)
                              .updateLocation(
                                latitude: lat,
                                longitude: lon,
                                elevation: settings.elevation,
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
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Observing Environment',
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
                      (i) => '${i + 1} - ${BortleScale.description(i + 1)}',
                    ),
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setBortleClass(int.parse(value));
                    },
                    width: widget.isMobile ? 200 : 280,
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.eye,
                  title: 'Limiting Magnitude',
                  subtitle:
                      'Estimated naked-eye limit for Bortle ${settings.bortleClass}',
                  trailing: Text(
                    '${BortleScale.limitingMagnitude(settings.bortleClass).toStringAsFixed(1)}m',
                    style: NightshadeTypography.h5.copyWith(
                        color: NightshadeColors.of(context).textPrimary),
                  ),
                  isLast: true,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Local Horizon Mask',
              isMobile: widget.isMobile,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Text(
                    'Set minimum observable altitude at each compass direction. '
                    'Objects below these altitudes are considered obstructed by terrain, '
                    'trees, or buildings.',
                    style: TextStyle(
                      color: NightshadeColors.of(context).textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                ),
                // The horizon mask (`horizon_profile_json`) is intentionally
                // non-remotable \u2014 editing it over NetworkBackend throws. Show a
                // host-only notice instead of editors that can't persist.
                if (isRemoteMode)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Text(
                      'The local horizon mask can only be edited on the imaging '
                      'host.',
                      style: TextStyle(
                        color: NightshadeColors.of(context).textSecondary,
                        fontSize: NightshadeTypography.fontSize12,
                      ),
                    ),
                  )
                else ...[
                  ...List.generate(horizonDirections.length, (i) {
                    final dir = horizonDirections[i];
                    final azimuth = horizonDirectionAzimuths[i];
                    return SettingRow(
                      icon: _compassIcon(dir),
                      title: '$dir (${azimuth.toStringAsFixed(0)}\u00B0)',
                      subtitle: 'Horizon altitude at $dir',
                      trailing: SettingsNumberInput(
                        controller: _horizonControllers[dir]!,
                        authoritativeValue: horizonProfile.altitudeAt(dir),
                        authorityKey: authority,
                        suffix: '\u00B0',
                        min: 0,
                        max: 89,
                        decimals: 0,
                        onChanged: (_) => _updateHorizonProfile(),
                        isMobile: widget.isMobile,
                      ),
                      isLast: i == horizonDirections.length - 1,
                      isMobile: widget.isMobile,
                    );
                  }),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          icon: _isImportingHorizon
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  LucideIcons.upload,
                                  size: 14,
                                  color: NightshadeColors.of(context).primary,
                                ),
                          label: Text(
                              _isImportingHorizon
                                  ? 'Importing horizon...'
                                  : 'Import .hor / CSV',
                              style: TextStyle(
                                  color: _isImportingHorizon
                                      ? NightshadeColors.of(context).textMuted
                                      : NightshadeColors.of(context).primary,
                                  fontSize: NightshadeTypography.fontSize12)),
                          onPressed:
                              _isImportingHorizon ? null : _importHorizonFile,
                        ),
                        TextButton.icon(
                          icon: Icon(LucideIcons.rotateCcw,
                              size: 14,
                              color: NightshadeColors.of(context).primary),
                          label: Text('Reset All to 0\u00B0',
                              style: TextStyle(
                                  color: NightshadeColors.of(context).primary,
                                  fontSize: NightshadeTypography.fontSize12)),
                          onPressed: () async {
                            try {
                              final reset = <String, double>{
                                for (final dir in horizonDirections) dir: 0,
                              };
                              await ref
                                  .read(appSettingsProvider.notifier)
                                  .setHorizonProfileJson(
                                    LegacyHorizonProfile(reset).toJson(),
                                  );
                            } catch (error) {
                              if (mounted) {
                                this.context.showErrorSnackBar(
                                      'Could not reset the horizon mask: $error',
                                    );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            SettingsSection(
              title: 'Time',
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.clock,
                  title: 'Timezone',
                  trailing: SettingsDropdown(
                    value: settings.timezone,
                    items: _getTimezones(),
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setTimezone(value);
                    },
                    width: widget.isMobile ? 160 : 200,
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.globe,
                  title: 'Use system time',
                  subtitle: 'Sync time from operating system',
                  trailing: SettingsSwitch(
                    value: settings.useSystemTime,
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setUseSystemTime(value);
                    },
                  ),
                  isLast: true,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Import a horizon obstruction profile from a Stellarium-style `.hor` file
  /// or a CSV of `azimuth,altitude` pairs. The arbitrary samples are binned
  /// onto the eight compass directions (highest altitude per sector wins so an
  /// obstruction is never under-reported), then persisted.
  Future<void> _importHorizonFile() async {
    if (_isImportingHorizon) return;
    final generation = ++_horizonImportGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _isImportingHorizon = true);

    try {
      final file = await ref.read(horizonImportPickerProvider)();
      if (file == null || !_isCurrentHorizonImport(generation, authority)) {
        return;
      }

      final content = await ref.read(horizonImportReaderProvider)(file);
      if (!_isCurrentHorizonImport(generation, authority)) return;
      final imported = LegacyHorizonProfile.parseHorizonText(content);

      await ref
          .read(appSettingsProvider.notifier)
          .setHorizonProfileJson(imported.toJson());
      if (!mounted || !_isCurrentHorizonImport(generation, authority)) {
        return;
      }

      context.showSuccessSnackBar('Horizon profile imported from ${file.name}');
    } on FormatException catch (e) {
      if (mounted && _isCurrentHorizonImport(generation, authority)) {
        context.showErrorSnackBar('Could not import horizon: ${e.message}');
      }
    } catch (e) {
      if (mounted && _isCurrentHorizonImport(generation, authority)) {
        context.showErrorSnackBar('Could not import horizon file: $e');
      }
    } finally {
      if (_isCurrentHorizonImport(generation, authority)) {
        setState(() => _isImportingHorizon = false);
      }
    }
  }

  bool _isCurrentHorizonImport(
    int generation,
    NightshadeBackend authority,
  ) {
    return mounted &&
        generation == _horizonImportGeneration &&
        identical(ref.read(backendProvider), authority);
  }

  Future<void> _updateHorizonProfile() async {
    final parts = <String>[];
    for (final dir in horizonDirections) {
      final text = _horizonControllers[dir]!.text;
      final val = double.tryParse(text)?.clamp(0.0, 89.0) ?? 0.0;
      parts.add('"$dir":${val.toStringAsFixed(1)}');
    }
    final json = '{${parts.join(',')}}';
    await ref.read(appSettingsProvider.notifier).setHorizonProfileJson(json);
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
