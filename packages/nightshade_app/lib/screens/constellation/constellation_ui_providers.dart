import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// The core barrel also exports a `ConstellationPrivacy` (the wire enum
// `contributeTarget` consumes). This file declares the richer app-side enum of
// the same name, so the core one is imported under a prefix to disambiguate.
import 'package:nightshade_core/nightshade_core.dart' hide ConstellationPrivacy;
import 'package:nightshade_core/nightshade_core.dart' as core
    show ConstellationPrivacy;

/// App-side Riverpod surface for the Constellation screens (Pillar C).
///
/// The community workflow itself lives in `constellationServiceProvider` (core);
/// these providers add the small slices of UI state the screens need on top of
/// it: the verified hub identity for the connected header, the locally-imaged
/// depth that backs the "your contribution" bar, and the persisted display
/// name / privacy choice the contribute consent flow reads and writes.

/// Settings key the chosen Constellation display name persists under.
const String constellationDisplayNameSettingKey = 'constellation.display_name';

/// Settings key the per-install stable public key persists under (random hex,
/// minted on first account registration; the self-hosted hub only needs a
/// stable opaque key, not a real keypair).
const String constellationPublicKeySettingKey = 'constellation.public_key';

/// Settings key the contribution privacy choice persists under. Wire value is
/// the [ConstellationPrivacy.name] (`sums` | `subs`); default is `sums`.
const String constellationPrivacySettingKey = 'constellation.privacy';

/// What a contributor sends to the hub. `sums` (default) shares only the same
/// additive accumulator the master integration already keeps — never the raw
/// individual subframes. `subs` is the heavier, more revealing option a user
/// can knowingly opt into for a hub that re-grades centrally.
enum ConstellationPrivacy {
  /// Additive co-add sums only (the `.nst` keystone bytes). Recommended.
  sums,

  /// Raw calibrated subframes. More to upload, more revealing.
  subs;

  String get label => this == ConstellationPrivacy.sums
      ? 'Share co-add sums (recommended)'
      : 'Share raw subframes';

  String get blurb => this == ConstellationPrivacy.sums
      ? 'Only the additive stack your atlas already keeps leaves this device — '
          'never your individual exposures. Others cannot recover your subs.'
      : 'Every calibrated subframe is uploaded so the hub can re-grade and '
          'reject centrally. Larger, slower, and more revealing of your rig.';

  /// The core wire enum [ConstellationService.contributeTarget] consumes. The
  /// two enums are kept name-aligned (`sums` | `subs`) so the persisted setting
  /// round-trips through either side.
  core.ConstellationPrivacy get wire => this == ConstellationPrivacy.sums
      ? core.ConstellationPrivacy.sums
      : core.ConstellationPrivacy.subs;
}

/// The hub identity once connectivity + tiling have been verified, or null when
/// no hub is configured. Surfaces the order-mismatch refusal as an error state.
final constellationHubInfoProvider = FutureProvider<HubInfo?>((ref) async {
  final configured = await ref.watch(constellationConfiguredProvider.future);
  if (!configured) return null;
  return ref.watch(constellationServiceProvider).signIn();
});

/// The persisted display name for this imager, or an empty string before the
/// user has signed in / chosen one.
final constellationDisplayNameProvider = FutureProvider<String>((ref) async {
  final settings = ref.watch(settingsDaoProvider);
  return (await settings.getSetting(constellationDisplayNameSettingKey)) ?? '';
});

/// The persisted contribution privacy choice (defaults to [ConstellationPrivacy.sums]).
final constellationPrivacyProvider =
    FutureProvider<ConstellationPrivacy>((ref) async {
  final settings = ref.watch(settingsDaoProvider);
  final raw = await settings.getSetting(constellationPrivacySettingKey);
  return ConstellationPrivacy.values.firstWhere(
    (p) => p.name == raw,
    orElse: () => ConstellationPrivacy.sums,
  );
});

/// The user's locally-imaged integration depth (seconds) inside a shared
/// target's cone — the numerator of the "your contribution" bar. Reads the
/// personal atlas coverage and sums every local tile whose centre falls within
/// [_contributionRadiusDeg] of the target.
final yourContributionSecondsProvider =
    FutureProvider.family<double, SharedTarget>((ref, target) async {
  final coverage = await ref.watch(skyAtlasCoverageProvider.future);
  var total = 0.0;
  for (final tile in coverage) {
    final sep = _angularSeparationDeg(
      target.raDeg,
      target.decDeg,
      tile.centerRaDeg,
      tile.centerDecDeg,
    );
    if (sep <= _contributionRadiusDeg) {
      total += tile.integrationSeconds;
    }
  }
  return total;
});

/// Matches the contribute/pull cone radius the [ConstellationService] uses so
/// the displayed "your contribution" depth lines up with what actually ships.
const double _contributionRadiusDeg = 1.5;

/// Great-circle separation (deg) via the haversine formula.
double _angularSeparationDeg(
  double ra1Deg,
  double dec1Deg,
  double ra2Deg,
  double dec2Deg,
) {
  const deg2rad = math.pi / 180.0;
  final dRa = (ra2Deg - ra1Deg) * deg2rad;
  final dDec = (dec2Deg - dec1Deg) * deg2rad;
  final lat1 = dec1Deg * deg2rad;
  final lat2 = dec2Deg * deg2rad;
  final a = math.sin(dDec / 2) * math.sin(dDec / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dRa / 2) * math.sin(dRa / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return c / deg2rad;
}
