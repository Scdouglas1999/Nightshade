import 'dart:io';
import 'dart:math' as math;

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

import '../../../utils/confirm_dialog.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/geolocation_consent.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

typedef HorizonImportPicker = Future<file_selector.XFile?> Function();
typedef HorizonImportReader = Future<String> Function(
  file_selector.XFile file,
);

/// Resolves this machine's position: device GPS when the platform has it,
/// otherwise a third-party IP lookup. Injected so the consent + write flow can
/// be driven in tests without a network.
typedef DeviceLocationFetcher
    = Future<(double latitude, double longitude, String? name)?> Function();

final deviceLocationFetcherProvider = Provider<DeviceLocationFetcher>(
  (ref) => GeolocationService.fetchLocationFromGPS,
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
  bool _legacyTimezoneMigrated = false;

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
        _migrateLegacyTimezone(settings);

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
                  subtitle: 'Decimal degrees or DMS (44 3 29 N). Positive is '
                      'North, negative is South',
                  trailing: SettingsNumberInput(
                    controller: _latController,
                    authoritativeValue: settings.latitude,
                    authorityKey: authority,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 6,
                    parse: (text) => parseSiteAngle(
                      text,
                      maxDegrees: 90,
                      positiveHemisphere: 'N',
                      negativeHemisphere: 'S',
                    ),
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
                  subtitle: 'Decimal degrees or DMS (121 18 55 W). Positive is '
                      'East, negative is West',
                  trailing: SettingsNumberInput(
                    controller: _lonController,
                    authoritativeValue: settings.longitude,
                    authorityKey: authority,
                    suffix: '\u00B0',
                    min: -180,
                    max: 180,
                    decimals: 6,
                    parse: (text) => parseSiteAngle(
                      text,
                      maxDegrees: 180,
                      positiveHemisphere: 'E',
                      negativeHemisphere: 'W',
                    ),
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
                // Only a remote session HAS a server to read from: over a local
                // backend `profileSettingsBackendProvider` reads this app's own
                // settings store, so the row wrote the values back unchanged
                // and still reported "Location synced from server".
                if (isRemoteMode)
                  SettingRow(
                    icon: LucideIcons.refreshCw,
                    title: 'Sync from Server',
                    subtitle: 'Fetch location from the connected imaging host',
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
                                    'The imaging host changed while syncing. '
                                    'Try again on the current host.',
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
                                  'Location read from the imaging host');
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
                  // Not "GPS": on desktop there is no GPS receiver, and the
                  // service silently falls back to a third-party IP lookup.
                  title: 'Detect Location',
                  subtitle: 'Device GPS if this machine has it, otherwise a '
                      'city-level estimate from your IP address',
                  trailing: IconButton(
                    icon: Icon(LucideIcons.crosshair,
                        color: NightshadeColors.of(context).primary),
                    onPressed: () => _detectLocation(settings),
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
                    'trees, or buildings.\n'
                    // The resolution actually in force, stated where the mask
                    // is edited. These eight numbers are a summary whenever a
                    // survey is loaded, and the whole model otherwise — and
                    // which of the two it is decides whether a target inside
                    // an obstructed sector is refused or allowed.
                    '${horizonProfile.sampleCount >= 2 ? 'An imported survey of '
                        '${horizonProfile.sampleCount} samples is in use — the '
                        'planner and sky chart interpolate it. These eight '
                        'fields summarise it by sector; editing any of them '
                        'replaces the survey with your eight values.' : 'These '
                        'eight 45° sectors are the whole mask, so the tallest '
                        'obstruction in a sector applies across all of it. '
                        'Import a .hor / CSV survey to keep full resolution.'}',
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
                          onPressed: () => _resetHorizon(horizonProfile),
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
                  subtitle: _timezoneSubtitle(settings),
                  trailing: SettingsDropdown(
                    value: utcOffsetForTimezone(settings.timezone),
                    items: kUtcOffsetTimezones,
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

  /// How far the resolved position may sit from the stored one before the
  /// stored elevation is treated as belonging to a different place. An IP
  /// estimate is accurate to roughly a city (~10 km), so a fix inside this
  /// radius is plausibly the same observing site.
  static const double _sameSiteRadiusKm = 25;

  /// Great-circle distance in kilometres.
  static double _kmBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return earthRadiusKm * 2 * math.asin(math.min(1.0, math.sqrt(a)));
  }

  /// Resolve this machine's position, with consent, and never leave the site
  /// in a state that does not exist.
  ///
  /// Two things this used to get wrong. It was labelled GPS while on every
  /// desktop `GeolocationService` falls back to a third-party IP lookup — a
  /// silent outbound request from an app that is often run on an isolated
  /// observatory network. And it wrote the new latitude/longitude while
  /// passing the OLD elevation straight through, so an IP fix in Pennsylvania
  /// inherited a 1234 m elevation from a previous Seattle site: a place that
  /// does not exist, feeding refraction and horizon maths.
  Future<void> _detectLocation(AppSettingsState settings) async {
    // Shared with the first-run wizard's site step, which fires the same
    // service: one dialog means the two surfaces cannot describe the outbound
    // request differently, or one of them forget to ask.
    final consented = await confirmGeolocationLookup(
      context,
      outcome: kGeolocationWritesSiteOutcome,
    );
    if (!consented || !mounted) return;

    try {
      final actionAuthority = ref.read(backendProvider);
      final location = await ref.read(deviceLocationFetcherProvider)();
      if (!mounted || !identical(ref.read(backendProvider), actionAuthority)) {
        if (mounted) {
          context.showWarningSnackBar(
            'The imaging host changed while reading the device location. Try '
            'again on the current host.',
          );
        }
        return;
      }
      if (location == null) {
        context.showWarningSnackBar(
          'Could not determine a location. Check location permissions, or '
          'network access if this machine has no GPS.',
        );
        return;
      }

      final (lat, lon, name) = location;
      final movedKm =
          _kmBetween(settings.latitude, settings.longitude, lat, lon);
      final keepElevation = movedKm <= _sameSiteRadiusKm;
      await ref.read(appSettingsProvider.notifier).updateLocation(
            latitude: lat,
            longitude: lon,
            // Clearing beats inheriting: an elevation from another site is a
            // wrong number the app would use, while 0 m is the app's own
            // "not set" value and is called out in the message below.
            elevation: keepElevation ? settings.elevation : 0,
          );
      if (!mounted) return;
      final where = name ??
          '${lat.toStringAsFixed(4)}, '
              '${lon.toStringAsFixed(4)}';
      context.showSuccessSnackBar(
        keepElevation
            ? 'Coordinates set to $where. Elevation kept at '
                '${settings.elevation.toStringAsFixed(0)} m.'
            : 'Coordinates set to $where. Elevation cleared to 0 m — '
                'enter the elevation for this site.',
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not detect a location: $e');
      }
    }
  }

  /// Import a horizon obstruction profile from a Stellarium-style `.hor` file
  /// or a CSV of `azimuth,altitude` pairs. Every sample is persisted, and the
  /// eight compass fields on this page summarise them (highest altitude per
  /// 45° sector, so the number shown never under-reports an obstruction).
  ///
  /// The import used to keep ONLY those eight numbers, behind a snackbar that
  /// said just "Horizon profile imported from `<file>`". A 29° tree at azimuth
  /// 190 was therefore applied to everything from 157.5° to 202.5°, and it
  /// only showed up months later as the planner refusing targets that were
  /// plainly clear — on exactly the southern sky a horizon survey is made for.
  /// [LegacyHorizonProfile] now carries the samples and interpolates them in
  /// `altitudeAtAzimuth`, which is what the planner's visibility filter and
  /// the planetarium's 360-entry terrain table both already called.
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
      final sampleCount = _countHorizonSamples(content);

      final confirmed = await _confirmHorizonReduction(
        fileName: file.name,
        sampleCount: sampleCount,
        imported: imported,
      );
      if (confirmed != true ||
          !_isCurrentHorizonImport(generation, authority)) {
        return;
      }

      await ref
          .read(appSettingsProvider.notifier)
          .setHorizonProfileJson(imported.toJson());
      if (!mounted || !_isCurrentHorizonImport(generation, authority)) {
        return;
      }

      context.showSuccessSnackBar(
        'Horizon imported from ${file.name} — $sampleCount '
        '${sampleCount == 1 ? 'sample' : 'samples'} stored; the eight fields '
        'below summarise them by sector.',
      );
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

  /// How many azimuth/altitude samples the file actually contained.
  ///
  /// Counts the lines [LegacyHorizonProfile.parseHorizonText] treats as data:
  /// it skips blanks and `#`/`//`/`;` comments and REQUIRES every remaining
  /// line to be a valid pair (it throws otherwise), so after a successful
  /// parse this count is the sample count. Deliberately does not re-parse the
  /// numbers — the parser above is the authority on what is a sample.
  static int _countHorizonSamples(String text) {
    var count = 0;
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith(';')) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// Show what the import is about to store before it overwrites the mask.
  ///
  /// Returns true only if the user accepted it.
  Future<bool?> _confirmHorizonReduction({
    required String fileName,
    required int sampleCount,
    required LegacyHorizonProfile imported,
  }) {
    final colors = NightshadeColors.of(context);
    // The survey is kept whole; the eight fields are its summary. Stated in
    // both directions because the eight numbers below are what the operator
    // will then SEE on this page, and a 36-sample import that displays as
    // eight numbers looks exactly like an import that threw 28 of them away.
    final resolution = imported.sampleCount >= 2
        ? 'All $sampleCount are stored and interpolated between, so the '
            'planner and the sky chart use the skyline your file describes, '
            'not a 45°-wide step.'
        : 'A single sample describes a flat horizon, so it is stored as one '
            'altitude all the way round.';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Import horizon from $fileName?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$sampleCount ${sampleCount == 1 ? 'sample' : 'samples'} read. '
                '$resolution',
              ),
              const SizedBox(height: 12),
              Text(
                'Summarised on this page as the tallest obstruction in each '
                'of the eight 45° sectors:',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final dir in horizonDirections)
                    Text(
                      '$dir ${imported.altitudeAt(dir).toStringAsFixed(0)}°',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'This replaces the current mask. Editing any of the eight '
                'values afterwards replaces the imported skyline with those '
                'eight sector altitudes.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          NightshadeButton(
            label: 'Import',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
  }

  /// Flatten the horizon mask — after asking, whenever there is something to
  /// lose.
  ///
  /// "Reset All to 0°" sits on the same row as "Import .hor / CSV", about
  /// 120 px from it, and used to fire on the first click. A survey is hours of
  /// work with a compass and an inclinometer (or a file that has to be found
  /// again), the app does not keep the source file, and there is no undo — so
  /// the misclick beside the Import button silently cost the whole skyline.
  Future<void> _resetHorizon(LegacyHorizonProfile current) async {
    final hasSurvey = current.sampleCount >= 2;
    final hasMask = horizonDirections.any((dir) => current.altitudeAt(dir) > 0);

    if (hasSurvey || hasMask) {
      final what = hasSurvey
          ? 'The imported survey of ${current.sampleCount} samples, and the '
              'eight sector values below it, will be replaced by a flat 0° '
              'horizon.'
          : 'The eight sector values below will be replaced by a flat 0° '
              'horizon.';
      final confirmed = await ConfirmDialog.show(
        context: context,
        title: 'Reset the horizon mask?',
        message: '$what Nightshade does not keep the file it was imported '
            'from, so this cannot be undone.',
        confirmLabel: 'Reset horizon',
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    try {
      final reset = <String, double>{
        for (final dir in horizonDirections) dir: 0,
      };
      await ref.read(appSettingsProvider.notifier).setHorizonProfileJson(
            LegacyHorizonProfile(reset).toJson(),
          );
    } catch (error) {
      if (mounted) {
        context.showErrorSnackBar('Could not reset the horizon mask: $error');
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

  /// What the Timezone row can honestly say about the value below it.
  ///
  /// Reads [clockProvider] rather than the raw setting, so the sentence
  /// describes the clock the app is actually running on. The old row said
  /// nothing at all, which is how a picker that changed no displayed time
  /// anywhere survived: there was no claim to falsify.
  String _timezoneSubtitle(AppSettingsState settings) {
    if (settings.useSystemTime) {
      return 'Ignored while "Use system time" is on — times follow this '
          "computer's clock";
    }
    final clock = ref.watch(clockProvider);
    if (clock is! FixedOffsetClock) {
      return 'Nightshade cannot apply "${settings.timezone}", so times follow '
          "this computer's clock — choose a UTC offset";
    }
    final now = clock.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Capture timestamps and scheduling use ${clock.label} — now '
        '$hh:$mm (fixed offset, no daylight saving)';
  }

  /// Rewrites an IANA label left by the previous picker to the equivalent
  /// standard-time UTC offset.
  ///
  /// The old dropdown offered 18 IANA names but `clockProvider` parses only
  /// `UTC` and `UTC±HH:MM`, so 17 of them resolved to null and fell back to
  /// the system clock — the setting persisted, was displayed, and did
  /// nothing. Migrating means the choice the operator already made starts
  /// being honoured instead of being silently discarded.
  void _migrateLegacyTimezone(AppSettingsState settings) {
    if (_legacyTimezoneMigrated) return;
    final stored = settings.timezone;
    if (kUtcOffsetTimezones.contains(stored)) return;
    final mapped = kLegacyIanaUtcOffsets[stored];
    if (mapped == null) return;
    _legacyTimezoneMigrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ref.read(appSettingsProvider.notifier).setTimezone(mapped);
      } catch (error) {
        // A host-only/remote write failure leaves the stored label in place;
        // the row's subtitle then reports that it is not being applied.
        debugPrint('Could not migrate legacy timezone "$stored": $error');
      }
    });
  }
}

/// Timezone values the app can actually honour.
///
/// `clockProvider` builds its [FixedOffsetClock] from these labels, so every
/// entry here changes the clock when "Use system time" is off. Offsets rather
/// than IANA zones because Nightshade carries no timezone database; naming
/// cities we cannot resolve is what made the old picker inert.
const List<String> kUtcOffsetTimezones = [
  'UTC-12:00',
  'UTC-11:00',
  'UTC-10:00',
  'UTC-09:30',
  'UTC-09:00',
  'UTC-08:00',
  'UTC-07:00',
  'UTC-06:00',
  'UTC-05:00',
  'UTC-04:00',
  'UTC-03:30',
  'UTC-03:00',
  'UTC-02:00',
  'UTC-01:00',
  'UTC',
  'UTC+01:00',
  'UTC+02:00',
  'UTC+03:00',
  'UTC+03:30',
  'UTC+04:00',
  'UTC+04:30',
  'UTC+05:00',
  'UTC+05:30',
  'UTC+05:45',
  'UTC+06:00',
  'UTC+06:30',
  'UTC+07:00',
  'UTC+08:00',
  'UTC+08:45',
  'UTC+09:00',
  'UTC+09:30',
  'UTC+10:00',
  'UTC+10:30',
  'UTC+11:00',
  'UTC+12:00',
  'UTC+12:45',
  'UTC+13:00',
  'UTC+14:00',
];

/// Standard-time offset for each IANA label the previous picker could store.
/// Standard, not summer, time: a fixed offset cannot follow a DST rule, and
/// pretending otherwise for half the year would be the same class of lie.
const Map<String, String> kLegacyIanaUtcOffsets = {
  'America/New_York': 'UTC-05:00',
  'America/Chicago': 'UTC-06:00',
  'America/Denver': 'UTC-07:00',
  'America/Los_Angeles': 'UTC-08:00',
  'America/Phoenix': 'UTC-07:00',
  'America/Anchorage': 'UTC-09:00',
  'Pacific/Honolulu': 'UTC-10:00',
  'Europe/London': 'UTC',
  'Europe/Paris': 'UTC+01:00',
  'Europe/Berlin': 'UTC+01:00',
  'Europe/Moscow': 'UTC+03:00',
  'Asia/Tokyo': 'UTC+09:00',
  'Asia/Shanghai': 'UTC+08:00',
  'Asia/Kolkata': 'UTC+05:30',
  'Australia/Sydney': 'UTC+10:00',
  'Australia/Perth': 'UTC+08:00',
  'Pacific/Auckland': 'UTC+12:00',
};

/// The offset entry a stored timezone label should select in the picker.
String utcOffsetForTimezone(String stored) {
  if (kUtcOffsetTimezones.contains(stored)) return stored;
  return kLegacyIanaUtcOffsets[stored] ?? 'UTC';
}

/// Read a site latitude or longitude written the way coordinates are normally
/// quoted, and return it in decimal degrees.
///
/// Accepted, for [positiveHemisphere]/[negativeHemisphere] = N/S or E/W:
///   `44.0582`  `-121.3153`  `44.0582 N`  `44 3 29 N`  `44° 3' 29" N`
///   `44d03m29s`  `N 44 03 29`  `121 18 55 W`
///
/// Returns `null` for invalid or out-of-range input rather than clamping it.
double? parseSiteAngle(
  String input, {
  required double maxDegrees,
  required String positiveHemisphere,
  required String negativeHemisphere,
}) {
  var text = input.trim();
  if (text.isEmpty) return null;

  // `s` is BOTH the South hemisphere and the seconds unit. The two spellings
  // are told apart by whether the string uses the other unit letters: in
  // `44d03m29s` the trailing s closes a d/m/s triple, while in `44 03 29 S` it
  // is a hemisphere. Nothing else is ambiguous — n/e/w are never units.
  final usesUnitLetters = RegExp(r'\d\s*[dm]', caseSensitive: false)
      .hasMatch(text.replaceAll(RegExp('[^0-9a-zA-Z ]'), ''));

  // ...and, when they are, by whether the trailing letter is GLUED to a digit.
  // `44d03m29s` closes a triple; `44d03m29s S` says South after it, and
  // reading that as a second seconds marker put the site 88 degrees away in
  // the wrong hemisphere without saying so.
  final lowered = input.trim().toLowerCase();
  final trailingLetterFollowsDigit = lowered.length >= 2 &&
      RegExp(r'\d').hasMatch(lowered[lowered.length - 2]);

  bool? negativeHemisphereSeen;
  for (final (letter, isNegative) in [
    (positiveHemisphere, false),
    (negativeHemisphere, true),
  ]) {
    final ambiguousSeconds = usesUnitLetters &&
        letter.toLowerCase() == 's' &&
        trailingLetterFollowsDigit;
    if (text.toLowerCase().startsWith(letter.toLowerCase())) {
      text = text.substring(letter.length).trim();
      negativeHemisphereSeen = isNegative;
      break;
    }
    if (!ambiguousSeconds &&
        text.toLowerCase().endsWith(letter.toLowerCase())) {
      text = text.substring(0, text.length - letter.length).trim();
      negativeHemisphereSeen = isNegative;
      break;
    }
  }
  if (text.isEmpty) return null;

  final explicitlyNegative = text.startsWith('-');
  // "-44 S" says south twice, or north-and-south; either way the operator and
  // the app would disagree about which hemisphere was stored.
  if (explicitlyNegative && negativeHemisphereSeen != null) return null;
  if (explicitlyNegative || text.startsWith('+')) {
    text = text.substring(1).trim();
  }

  // Everything that separates the three components — degree/minute/second
  // marks, unit letters, colons, commas — becomes whitespace, leaving numbers.
  final normalized = text
      .replaceAll(RegExp("[°º:,dhmsʹʺ'′″\"]", caseSensitive: false), ' ')
      .trim();
  if (normalized.isEmpty) return null;
  final parts = normalized.split(RegExp(r'\s+'));
  if (parts.length > 3) return null;

  var magnitude = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final value = double.tryParse(parts[i]);
    if (value == null || !value.isFinite || value < 0) return null;
    // Only the last component may be fractional: "44 3.5 29" is not a
    // coordinate anyone writes, and reading it would be guesswork.
    if (i < parts.length - 1 && value != value.roundToDouble()) return null;
    if (i > 0 && value >= 60) return null;
    magnitude += value / [1.0, 60.0, 3600.0][i];
  }

  if (magnitude > maxDegrees) return null;
  final negative = explicitlyNegative || (negativeHemisphereSeen ?? false);
  return negative ? -magnitude : magnitude;
}
