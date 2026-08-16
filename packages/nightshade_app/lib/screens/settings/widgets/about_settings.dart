import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// Canonical public home used by both mobile and desktop About layouts.
const String kNightshadeRepositoryUrl =
    'https://github.com/Scdouglas1999/Nightshade';

/// One row of the About page's link strip.
///
/// [compactLabel] is what the phone layout shows, where the buttons sit in a
/// Wrap and a long label pushes the third button onto its own line.
class AboutLink {
  final IconData icon;
  final String label;
  final String compactLabel;
  final String url;

  const AboutLink({
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.url,
  });
}

/// WHY only these three: a shipped About page must not offer a destination we
/// cannot stand behind. The project has no community chat server, so there is
/// no Discord button — an invite that lands the user in a stranger's server is
/// worse than no button at all. Documentation lives in the repository (the
/// README links `docs/index.md`); there is no docs site to point at.
const List<AboutLink> kAboutLinks = [
  AboutLink(
    icon: LucideIcons.github,
    label: 'GitHub',
    compactLabel: 'GitHub',
    url: kNightshadeRepositoryUrl,
  ),
  AboutLink(
    icon: LucideIcons.bookOpen,
    label: 'Documentation',
    compactLabel: 'Docs',
    url: '$kNightshadeRepositoryUrl/blob/main/docs/index.md',
  ),
  AboutLink(
    icon: LucideIcons.bug,
    label: 'Report an Issue',
    compactLabel: 'Issues',
    url: '$kNightshadeRepositoryUrl/issues',
  ),
];

/// The licence this build ships under, verbatim from the repository's LICENSE
/// file. Settings search sends both `license` and `credits` to About, so the
/// page has to actually carry them.
const String kNightshadeLicenseName =
    'Nightshade Source-Available License v1.2';
const String kNightshadeCopyright = 'Copyright (c) 2025 Sean Douglas';
const String kNightshadeLicenseUrl =
    '$kNightshadeRepositoryUrl/blob/main/LICENSE';

/// Opens an external URL. Injected so a widget test can assert which address a
/// button actually hands to the platform rather than only that it was tapped.
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

final aboutLinkLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) => (uri) async => await canLaunchUrl(uri) && await launchUrl(uri),
);

/// The newest release published for this project.
class LatestRelease {
  /// Version as published, with any leading `v` stripped.
  final String version;

  /// Human-facing page for the release (release notes + downloads).
  final String url;

  const LatestRelease({required this.version, required this.url});
}

/// Resolves the newest published release, or null when the project has none.
typedef LatestReleaseChecker = Future<LatestRelease?> Function();

/// Why the releases API and not the in-app updater: `UpdateService` talks to a
/// Nightshade update server (`/api/version` + signed manifests) that no shipped
/// desktop build is configured with — `UpdateNotifier.configure` is only ever
/// called by the headless appliance wiring, so the GUI's updater is inert and
/// the app could never tell anyone a new version existed. The published
/// releases page is the channel that actually exists today. This only reports;
/// it never downloads or installs, so it needs none of the signing material
/// the OTA path (correctly) refuses to run without.
final latestReleaseCheckerProvider = Provider<LatestReleaseChecker>(
  (ref) => _fetchLatestRelease,
);

Future<LatestRelease?> _fetchLatestRelease() async {
  final response = await http.get(
    Uri.parse(
      'https://api.github.com/repos/Scdouglas1999/Nightshade/releases/latest',
    ),
    headers: const {'Accept': 'application/vnd.github+json'},
  ).timeout(const Duration(seconds: 15));

  // 404 is the documented answer for "this repository has no releases", which
  // is not an error the operator can act on.
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw HttpException('the release server answered ${response.statusCode}');
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('unexpected release payload');
  }
  final tag = decoded['tag_name'];
  if (tag is! String || tag.trim().isEmpty) {
    throw const FormatException('release carries no version tag');
  }
  final url = decoded['html_url'];
  return LatestRelease(
    version: normalizeReleaseVersion(tag),
    url: url is String && url.isNotEmpty
        ? url
        : '$kNightshadeRepositoryUrl/releases/latest',
  );
}

/// `v6.1.0` / ` 6.1.0 ` -> `6.1.0`.
String normalizeReleaseVersion(String raw) {
  final trimmed = raw.trim();
  return trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
}

/// Compare two dotted versions, ignoring any pre-release suffix.
///
/// Returns null when either side cannot be read as numbers, so the caller can
/// name the published release without asserting that it is newer or older —
/// guessing there would be exactly the kind of confident-and-wrong claim this
/// screen is being fixed for.
int? compareReleaseVersions(String a, String b) {
  List<int>? parts(String value) {
    final core = value.split(RegExp('[-+]')).first;
    final segments = core.split('.');
    final numbers = <int>[];
    for (final segment in segments) {
      final parsed = int.tryParse(segment.trim());
      if (parsed == null) return null;
      numbers.add(parsed);
    }
    return numbers.isEmpty ? null : numbers;
  }

  final left = parts(a);
  final right = parts(b);
  if (left == null || right == null) return null;
  for (var i = 0;
      i < (left.length > right.length ? left.length : right.length);
      i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

class AboutSettings extends ConsumerWidget {
  final bool isMobile;

  const AboutSettings({super.key, this.isMobile = false});

  Future<void> _launchUrl(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final uri = Uri.parse(url);
    var launched = false;
    try {
      launched = await ref.read(aboutLinkLauncherProvider)(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      context.showErrorSnackBar('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final appVersion = ref.watch(appVersionProvider);
    final logoSize = isMobile ? 64.0 : 80.0;
    final logoIconSize = isMobile ? 32.0 : 40.0;

    return SettingsPage(
      title: 'About',
      description: 'Application information',
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                decoration: NightshadeDecorations.iconChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: logoIconSize,
                  color: colors.primary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Nightshade',
                style: TextStyle(
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize20
                      : NightshadeTypography.fontSize24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version ${appVersion.version} (build ${appVersion.buildNumber})',
                style: TextStyle(
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize13
                      : NightshadeTypography.fontSize14,
                  color: colors.textSecondary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Advanced astrophotography suite',
                style: TextStyle(
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize12
                      : NightshadeTypography.fontSize13,
                  color: colors.textMuted,
                ),
              ),
              SizedBox(height: isMobile ? 24 : 32),
              isMobile
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final link in kAboutLinks)
                          SettingsLinkButton(
                            icon: link.icon,
                            label: link.compactLabel,
                            onTap: () => _launchUrl(context, ref, link.url),
                            compact: true,
                          ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < kAboutLinks.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          SettingsLinkButton(
                            icon: kAboutLinks[i].icon,
                            label: kAboutLinks[i].label,
                            onTap: () =>
                                _launchUrl(context, ref, kAboutLinks[i].url),
                          ),
                        ],
                      ],
                    ),
              const SizedBox(height: 32),
              _SoftwareUpdateCard(isMobile: isMobile),
              const SizedBox(height: 32),
              _LicenseCard(
                isMobile: isMobile,
                onOpenUrl: (url) => _launchUrl(context, ref, url),
              ),
              const SizedBox(height: 32),
              const _SystemInformationCard(),
            ],
          ),
        ),
      ],
    );
  }
}

/// One labelled fact in the System Information card.
class SupportFact {
  const SupportFact(this.label, this.value);

  final String label;
  final String value;
}

/// What "System Information" reports.
///
/// A support conversation opens by asking for the build number, which host the
/// app is driving and what schema its data is on — none of which Platform / OS
/// Version / Dart Version answer — so those are gathered here and the whole
/// block is copyable in one action.
///
/// Deliberately synchronous: About must render its facts on the first frame,
/// never behind a spinner. The one fact that cannot be resolved synchronously
/// (the data folder) lives in [nightshadeDataFolderProvider] and is appended
/// when it arrives.
final systemInformationProvider = Provider<List<SupportFact>>((ref) {
  final facts = <SupportFact>[];

  try {
    final version = ref.watch(appVersionProvider);
    facts.add(
      SupportFact(
        'Nightshade',
        '${version.version} (build ${version.buildNumber})',
      ),
    );
  } catch (_) {
    // appVersionProvider throws when nothing overrode it (its documented
    // contract). The rest of the block is still worth reporting.
  }

  facts
    ..add(SupportFact('Platform', Platform.operatingSystem))
    ..add(SupportFact('OS version', Platform.operatingSystemVersion))
    ..add(SupportFact('Dart', Platform.version.split(' ').first));

  final backend = ref.watch(backendProvider);
  facts.add(
    SupportFact(
      'Connected to',
      backend is NetworkBackend
          ? 'imaging host ${backend.serverHost}'
          : 'this computer',
    ),
  );

  try {
    facts.add(
      SupportFact(
        'Database schema',
        '${ref.watch(databaseProvider).schemaVersion}',
      ),
    );
  } catch (_) {
    // No local database in this process (or none configured in a test bench).
  }

  return facts;
});

/// Where this process keeps its writable data, or null while unresolved.
///
/// Its own provider because `path_provider` is a platform channel: awaiting it
/// inside [systemInformationProvider] would put the whole card behind a
/// pending future.
final nightshadeDataFolderProvider = FutureProvider<String?>((ref) async {
  try {
    return (await resolveNightshadeDataDirectory()).path;
  } catch (_) {
    // path_provider can fail on an unusual OS configuration; the rest of the
    // block is still worth showing.
    return null;
  }
});

/// The block a bug report starts with, and a one-press way to hand it over.
class _SystemInformationCard extends ConsumerWidget {
  const _SystemInformationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final dataFolder = ref.watch(nightshadeDataFolderProvider).valueOrNull;
    final facts = [
      ...ref.watch(systemInformationProvider),
      if (dataFolder != null) SupportFact('Data folder', dataFolder),
    ];

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'System Information',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              NightshadeButton(
                label: 'Copy',
                icon: LucideIcons.clipboard,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          facts.map((f) => '${f.label}: ${f.value}').join('\n'),
                    ),
                  );
                  if (context.mounted) {
                    context.showSuccessSnackBar('System information copied');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final fact in facts)
            SettingsInfoRow(label: fact.label, value: fact.value),
        ],
      ),
    );
  }
}

/// The licence Nightshade ships under, plus the open-source credits.
///
/// Settings search has always routed `license` and `credits` to About, and
/// About carried neither: the page named a version, a tagline and three links
/// and stopped. Searching for a term that lands on exactly one destination
/// which then does not have it is the search lying about what the app knows.
class _LicenseCard extends ConsumerWidget {
  final bool isMobile;
  final void Function(String url) onOpenUrl;

  const _LicenseCard({required this.isMobile, required this.onOpenUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final appVersion = ref.watch(appVersionProvider);

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'License',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            '$kNightshadeLicenseName\n$kNightshadeCopyright',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                label: 'Read the license',
                icon: LucideIcons.scrollText,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => onOpenUrl(kNightshadeLicenseUrl),
              ),
              NightshadeButton(
                label: 'Open-source licenses',
                icon: LucideIcons.package,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                // Flutter's own page, fed by LicenseRegistry, so the credits
                // list is the set of packages actually linked into this build
                // rather than a hand-maintained list that would drift.
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Nightshade',
                  applicationVersion:
                      'Version ${appVersion.version} (build ${appVersion.buildNumber})',
                  applicationLegalese:
                      '$kNightshadeCopyright\n$kNightshadeLicenseName',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Manual "is there a newer Nightshade?" check.
///
/// This is the only local update surface Settings has: searching it for
/// "update" otherwise returns About and the appliance OTA page, which is about
/// a REMOTE rig and renders a single sentence off-network. The in-app updater
/// cannot answer either — nothing configures its server URL on desktop. An
/// astrophotographer needs to know a fix landed before the night, not after, so
/// this asks the published releases feed on demand and says exactly what it
/// found. It never downloads or installs anything.
class _SoftwareUpdateCard extends ConsumerStatefulWidget {
  final bool isMobile;

  const _SoftwareUpdateCard({required this.isMobile});

  @override
  ConsumerState<_SoftwareUpdateCard> createState() =>
      _SoftwareUpdateCardState();
}

class _SoftwareUpdateCardState extends ConsumerState<_SoftwareUpdateCard> {
  bool _checking = false;
  int _generation = 0;
  LatestRelease? _latest;
  String? _error;
  DateTime? _checkedAt;

  Future<void> _check() async {
    if (_checking) return;
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final latest = await ref.read(latestReleaseCheckerProvider)();
      if (!mounted || generation != _generation) return;
      setState(() {
        _latest = latest;
        _checkedAt = DateTime.now();
        _checking = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$e';
        _checking = false;
      });
    }
  }

  /// What the check found, in the operator's terms. Never guesses: an
  /// unparseable tag is reported by name without a newer/older claim.
  String _statusLine(String current) {
    if (_checking) return 'Checking for updates…';
    if (_error != null) return 'Could not check for updates: $_error';
    final latest = _latest;
    if (_checkedAt == null) {
      return 'Nightshade does not check for updates on its own.';
    }
    if (latest == null) {
      return 'No published release found for this project.';
    }
    final comparison = compareReleaseVersions(latest.version, current);
    if (comparison == null) {
      return 'Latest published release: ${latest.version}.';
    }
    if (comparison > 0) {
      return 'Nightshade ${latest.version} is available.';
    }
    return 'You are running the latest release (${latest.version}).';
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final appVersion = ref.watch(appVersionProvider);
    final latest = _latest;
    final isNewer = latest != null &&
        (compareReleaseVersions(latest.version, appVersion.version) ?? 0) > 0;

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Software Update',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            _statusLine(appVersion.version),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: _error != null ? colors.error : colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                label: 'Check for updates',
                icon: LucideIcons.refreshCw,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                isLoading: _checking,
                onPressed: _checking ? null : _check,
              ),
              if (latest != null)
                NightshadeButton(
                  label: isNewer ? 'View release notes' : 'View releases',
                  icon: LucideIcons.externalLink,
                  variant:
                      isNewer ? ButtonVariant.primary : ButtonVariant.ghost,
                  size: ButtonSize.small,
                  onPressed: () async {
                    final uri = Uri.parse(latest.url);
                    var launched = false;
                    try {
                      launched = await ref.read(aboutLinkLauncherProvider)(uri);
                    } catch (_) {
                      launched = false;
                    }
                    if (!launched && context.mounted) {
                      context.showErrorSnackBar('Could not open ${latest.url}');
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
