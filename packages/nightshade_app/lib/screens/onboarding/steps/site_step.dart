import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../utils/snackbar_helper.dart';

/// Why the observing-site step will not let the wizard advance, or null when the
/// current entry is acceptable.
///
/// The step owns the in-progress field text, so the wizard shell cannot
/// re-derive validity from the onboarding draft or from persisted settings — a
/// rejected coordinate never reaches either. The shell reads this before Next
/// and "Skip this step" advance, which is what stops an out-of-range entry from
/// being waved through with its red error still on screen.
final onboardingSiteEntryErrorProvider = StateProvider<String?>((ref) => null);

/// The approximate-location lookup used to *offer* a starting point. Injected so
/// tests exercise the suggestion UI without reaching the network.
typedef ApproximateLocationLookup = Future<(double, double, String?)?>
    Function();

final onboardingApproximateLocationProvider =
    Provider<ApproximateLocationLookup>(
  (ref) => GeolocationService.fetchLocation,
);

/// Observing-site step.
///
/// The rest of the wizard builds an equipment profile; this step captures the
/// one piece of setup that is not equipment — where the user observes from.
/// Without it `AppSettingsState.latitude/longitude` sit at 0/0 ("null island")
/// and every location-driven surface (Tonight's one-tap pick, the planner's
/// visibility / dark windows, meridian-flip timing, the weather radar) falls
/// back to its "your location is not set" apology state.
///
/// Unlike the device steps this writes straight through to app settings via
/// [appSettingsProvider] rather than the onboarding draft: the coordinates are
/// global observer settings, not per-profile, so persisting them here means the
/// location-driven surfaces light up immediately and the summary/next-steps
/// screens can read them back from settings. The step is optional — a user
/// setting up indoors during the day can skip it and be nudged to fill it in
/// from the next-steps screen.
///
/// Two rules keep a site the user never chose out of the database:
///
///  * **An unusable entry reverts to what the step started with.** Typing "100"
///    transits the in-range prefixes "1" and "10"; persisting each keystroke
///    left a rejected latitude showing 100 in the field while 10°N sat on record
///    as the site. Whenever the pair is incomplete or out of range the step puts
///    back the coordinates it was seeded with, so a typo can neither invent a
///    site nor destroy the one already saved. Reverting synchronously rather
///    than debouncing the write also means there is no window in which Next
///    arrives before the commit does.
///  * **An IP estimate is a suggestion, never a default.** Free IP-geolocation
///    services resolve to the ISP's egress point, disagree with each other by
///    tens of kilometres, and can be wrong by far more. The estimate is offered
///    as a labelled starting point the user accepts explicitly; it is never
///    written to settings behind their back, because an unconfirmed site
///    silently skews every twilight, transit, and meridian-flip time the app
///    computes with no outward sign that anything is approximate.
class OnboardingSiteStep extends ConsumerStatefulWidget {
  const OnboardingSiteStep({super.key});

  @override
  ConsumerState<OnboardingSiteStep> createState() => _OnboardingSiteStepState();
}

class _OnboardingSiteStepState extends ConsumerState<OnboardingSiteStep> {
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _elevController = TextEditingController();

  String? _latError;
  String? _lonError;
  String? _elevError;

  /// The site as it stood when the step was entered. An entry that is not a
  /// usable coordinate pair restores these rather than leaving a partially typed
  /// value on record.
  double _baselineLat = 0.0;
  double _baselineLon = 0.0;

  /// Guards the one-time controller seed from persisted settings. Re-seeding on
  /// every rebuild would fight the user's in-progress typing.
  bool _seeded = false;
  bool _locating = false;

  /// IP-derived starting point, offered only when there is no site on record.
  (double, double, String?)? _ipEstimate;
  bool _ipLookupStarted = false;
  bool _ipLookupRunning = false;

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _elevController.dispose();
    super.dispose();
  }

  /// Prefill the fields from persisted settings, but only when the user has an
  /// actual site on record. lat/lon both at 0.0 is the "null island" default,
  /// not a real Gulf-of-Guinea observatory, so we leave the fields blank there
  /// to prompt real entry rather than seeding a misleading 0/0.
  void _seedFrom(AppSettingsState settings) {
    if (_seeded) return;
    _seeded = true;
    final hasSite = settings.latitude != 0.0 || settings.longitude != 0.0;
    _baselineLat = settings.latitude;
    _baselineLon = settings.longitude;
    if (hasSite) {
      _latController.text = _trimNumber(settings.latitude);
      _lonController.text = _trimNumber(settings.longitude);
    }
    if (settings.elevation != 0.0) {
      _elevController.text = settings.elevation.toStringAsFixed(0);
    }
    // Re-publish the blocking reason for the seeded text. The provider outlives
    // this widget, so a stale reason left by an earlier visit would otherwise
    // block Next until the user happened to touch a field. Seeded values are
    // always valid, so this normally clears it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishBlockingReason();
    });
    if (!hasSite && !_ipLookupStarted) {
      _ipLookupStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_lookUpIpEstimate());
      });
    }
  }

  /// Fetch an approximate position to *offer*. Failure is silent: a first run
  /// with no network must show manual entry, not an error the user cannot act
  /// on.
  Future<void> _lookUpIpEstimate() async {
    setState(() => _ipLookupRunning = true);
    final estimate = await ref.read(onboardingApproximateLocationProvider)();
    if (!mounted) return;
    setState(() {
      _ipLookupRunning = false;
      _ipEstimate = estimate;
    });
  }

  /// Accept the IP estimate as the starting point. This is the only path by
  /// which an IP-derived coordinate reaches settings, and it requires a click.
  Future<void> _applyIpEstimate() async {
    final estimate = _ipEstimate;
    if (estimate == null) return;
    final (lat, lon, _) = estimate;
    _latController.text = _trimNumber(lat);
    _lonController.text = _trimNumber(lon);
    _onFieldChanged();
  }

  static String? _validateLatitude(String raw) {
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < -90 || value > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    return null;
  }

  static String? _validateLongitude(String raw) {
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < -180 || value > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    return null;
  }

  static String? _validateElevation(String raw) {
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < -500 || value > 10000) {
      return 'Elevation must be between -500 and 10000 m.';
    }
    return null;
  }

  /// Validate every field on each keystroke so the inline error is immediate,
  /// publish the shell's blocking reason, then reconcile settings.
  void _onFieldChanged() {
    setState(() {
      _latError = _validateLatitude(_latController.text.trim());
      _lonError = _validateLongitude(_lonController.text.trim());
      _elevError = _validateElevation(_elevController.text.trim());
    });
    _publishBlockingReason();
    unawaited(_commitIfValid());
  }

  void _publishBlockingReason() {
    final latRaw = _latController.text.trim();
    final lonRaw = _lonController.text.trim();
    final halfASite = latRaw.isEmpty != lonRaw.isEmpty
        ? 'Enter both latitude and longitude, or clear both to skip this step.'
        : null;
    final reason = _latError ?? _lonError ?? _elevError ?? halfASite;
    ref.read(onboardingSiteEntryErrorProvider.notifier).state = reason;
  }

  /// Reconcile persisted settings with what is currently in the fields.
  ///
  /// Exactly three outcomes, evaluated against the *whole* field text rather
  /// than the keystroke that arrived:
  ///
  ///  * a valid, complete pair → persist it;
  ///  * both fields cleared → persist the unset 0/0 sentinel, so the database
  ///    agrees with the blank fields on screen instead of keeping a coordinate
  ///    the user just deleted;
  ///  * anything else (out of range, unparseable, or only one of the pair) →
  ///    restore the baseline. This is what keeps a rejected "100" from leaving
  ///    its in-range prefix "10" on record, and equally keeps a typo from
  ///    destroying a site that was already saved.
  Future<void> _commitIfValid() async {
    if (!mounted) return;
    final latRaw = _latController.text.trim();
    final lonRaw = _lonController.text.trim();
    final elevRaw = _elevController.text.trim();

    final double latitude;
    final double longitude;
    final entryIsUsable = _validateLatitude(latRaw) == null &&
        _validateLongitude(lonRaw) == null &&
        latRaw.isNotEmpty &&
        lonRaw.isNotEmpty;
    if (entryIsUsable) {
      latitude = double.parse(latRaw);
      longitude = double.parse(lonRaw);
    } else if (latRaw.isEmpty && lonRaw.isEmpty) {
      latitude = 0.0;
      longitude = 0.0;
    } else {
      latitude = _baselineLat;
      longitude = _baselineLon;
    }

    final elevation = _validateElevation(elevRaw) != null || elevRaw.isEmpty
        ? null
        : double.parse(elevRaw);

    final current = ref.read(appSettingsProvider).valueOrNull;
    if (current != null &&
        current.latitude == latitude &&
        current.longitude == longitude &&
        (elevation == null || current.elevation == elevation)) {
      return;
    }
    await ref.read(appSettingsProvider.notifier).updateLocation(
          latitude: latitude,
          longitude: longitude,
          elevation: elevation,
        );
  }

  /// Render a coordinate without a trailing ".0" so a whole-degree site does
  /// not display as "45.0".
  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  /// Read the device GPS and write all three coordinates in one batched update,
  /// mirroring Settings → Location's "Use Device Location" affordance. Guards
  /// the async gap with a backend-authority check so a host switch mid-read
  /// never applies the reading to the replacement host.
  Future<void> _useDeviceLocation() async {
    if (_locating) return;
    final authority = ref.read(backendProvider);
    setState(() => _locating = true);
    try {
      final location = await GeolocationService.fetchLocationFromGPS();
      if (!mounted || !identical(ref.read(backendProvider), authority)) {
        return;
      }
      if (location == null) {
        context.showWarningSnackBar(
          'Could not get GPS location. Check permissions.',
        );
        return;
      }
      final (lat, lon, name) = location;
      await ref.read(appSettingsProvider.notifier).updateLocation(
            latitude: lat,
            longitude: lon,
          );
      if (!mounted || !identical(ref.read(backendProvider), authority)) return;
      _latController.text = _trimNumber(lat);
      _lonController.text = _trimNumber(lon);
      setState(() {
        _latError = null;
        _lonError = null;
      });
      _publishBlockingReason();
      context.showSuccessSnackBar(
        name != null ? 'Location updated: $name' : 'Location updated',
      );
    } catch (error) {
      if (mounted && identical(ref.read(backendProvider), authority)) {
        context.showErrorSnackBar('Could not read device location: $error');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// The IP estimate, presented as a suggestion with its provenance and its
  /// error budget stated plainly. It is deliberately not written into the
  /// coordinate fields until the user presses "Use this": a value sitting in the
  /// field looks like a value the app knows, and this one is a guess.
  Widget _buildIpEstimate(ThemeData theme, NightshadeColors colors) {
    final estimate = _ipEstimate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.primary,
        borderRadius: NightshadeTokens.borderRadiusLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.globe, color: colors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: estimate == null
                ? Text(
                    'Looking up an approximate location…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Approximate location from your IP address',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_trimNumber(estimate.$1)}°, '
                        '${_trimNumber(estimate.$2)}°'
                        '${estimate.$3 != null ? ' — ${estimate.$3}' : ''}. '
                        'This is where your internet provider appears to be, '
                        'not where your telescope is, so it can be tens of '
                        'kilometres out. Use it as a starting point and correct '
                        'it if you can.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
          ),
          if (estimate != null) ...[
            const SizedBox(width: 8),
            NightshadeButton(
              label: 'Use this',
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => unawaited(_applyIpEstimate()),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: colors.primary),
      ),
      error: (error, _) => Text(
        'Could not load location settings: $error',
        style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
      ),
      data: (settings) {
        _seedFrom(settings);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where do you observe?',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your site drives Tonight, the planner’s visibility and dark '
                'windows, meridian-flip timing, and the weather radar. You can '
                'change it any time in Settings → Location.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              Row(
                children: [
                  NightshadeButton(
                    icon: LucideIcons.locate,
                    label: 'Use my current location',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    isLoading: _locating,
                    onPressed: _locating ? null : _useDeviceLocation,
                  ),
                ],
              ),
              if (_ipLookupRunning || _ipEstimate != null) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                _buildIpEstimate(theme, colors),
              ],
              const SizedBox(height: NightshadeTokens.spaceLg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _CoordinateField(
                      controller: _latController,
                      label: 'Latitude',
                      hint: 'e.g. 40.71',
                      suffix: '°',
                      helper: 'Positive for North, negative for South',
                      errorText: _latError,
                      onChanged: _onFieldChanged,
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: _CoordinateField(
                      controller: _lonController,
                      label: 'Longitude',
                      hint: 'e.g. -74.01',
                      suffix: '°',
                      helper: 'Positive for East, negative for West',
                      errorText: _lonError,
                      onChanged: _onFieldChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _CoordinateField(
                controller: _elevController,
                label: 'Elevation (optional)',
                hint: 'e.g. 120',
                suffix: 'm',
                helper: 'Height above sea level, in metres',
                errorText: _elevError,
                onChanged: _onFieldChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A labelled decimal coordinate input: a label, a [NightshadeTextField] that
/// accepts signed decimals, and a muted helper line. Mirrors the numeric-field
/// styling used by the camera-defaults step.
class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.helper,
    required this.suffix,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String helper;
  final String suffix;
  final String? errorText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs + 2),
        NightshadeTextField(
          controller: controller,
          hint: hint,
          suffix: suffix,
          errorText: errorText,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\-\.]')),
          ],
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
