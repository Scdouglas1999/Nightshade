// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Installed-catalog and SIMBAD search-result sections that mount under the candidate list once the user has typed enough characters into the planner search bar.
part of '../planner_screen.dart';

/// Section that resolves a name fragment against SIMBAD and renders the
/// matches as send-to-framing rows. Only mounts when the planner search bar
/// has ≥3 characters typed.
class _InstalledCatalogResultsSection extends ConsumerWidget {
  final String query;
  final NightshadeColors colors;

  const _InstalledCatalogResultsSection({
    required this.query,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plannerInstalledCatalogSearchProvider(query));

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Searching installed catalogs for "$query"...',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
            ),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Text(
          'Installed catalog lookup failed: $e',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12, color: colors.warning),
        ),
      ),
      data: (matches) {
        if (matches.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: NightshadeTokens.space2xl),
            SectionHeader(
              title: 'Installed catalog',
              subtitle:
                  '${matches.length} match${matches.length == 1 ? '' : 'es'} for "$query" outside tonight\'s scored candidates',
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final match in matches)
              _CatalogResultRow(match: match, colors: colors),
          ],
        );
      },
    );
  }
}

class _CatalogResultRow extends StatelessWidget {
  final CatalogSearchResult match;
  final NightshadeColors colors;

  const _CatalogResultRow({
    required this.match,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      match.type,
      if (match.magnitude != null) 'mag ${match.magnitude!.toStringAsFixed(1)}',
      if (match.constellation != null && match.constellation!.isNotEmpty)
        match.constellation!,
      'RA ${CoordinateFormat.ra(match.ra / 15.0)}  Dec ${CoordinateFormat.dec(match.dec)}',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: NightshadeCard(
        variant: CardVariant.subtle,
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.name,
                    style: NightshadeTypography.h5.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    metaParts.join(' · '),
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.crosshair,
              size: ButtonSize.small,
              onPressed: () {
                final uri = Uri(
                  path: '/framing',
                  queryParameters: {
                    'ra': (match.ra / 15.0).toStringAsFixed(6),
                    'dec': match.dec.toStringAsFixed(6),
                    'name': match.name,
                  },
                );
                context.go(uri.toString());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SimbadResultsSection extends ConsumerWidget {
  final String query;
  final NightshadeColors colors;
  final bool hasLocalMatches;

  const _SimbadResultsSection({
    required this.query,
    required this.colors,
    required this.hasLocalMatches,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plannerSimbadResultsProvider(query));

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Searching SIMBAD for "$query"…',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
            ),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Text(
          'SIMBAD lookup failed: $e',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12, color: colors.warning),
        ),
      ),
      data: (matches) {
        if (matches.isEmpty) {
          if (hasLocalMatches) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
            child: Text(
              'SIMBAD found no objects matching "$query".',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: NightshadeTokens.space2xl),
            SectionHeader(
              title: 'From SIMBAD',
              subtitle:
                  '${matches.length} match${matches.length == 1 ? '' : 'es'} for "$query" — not scored for tonight',
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final m in matches) _SimbadResultRow(match: m, colors: colors),
          ],
        );
      },
    );
  }
}

class _SimbadResultRow extends ConsumerWidget {
  final SimbadNameMatch match;
  final NightshadeColors colors;

  const _SimbadResultRow({required this.match, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metaParts = <String>[];
    if (match.objectType != null && match.objectType!.isNotEmpty) {
      metaParts.add(match.objectType!);
    }
    if (match.magnitudeV != null) {
      metaParts.add('mag ${match.magnitudeV!.toStringAsFixed(1)}');
    }
    metaParts.add(
      'RA ${CoordinateFormat.ra(match.raHours)}  Dec ${CoordinateFormat.dec(match.decDegrees)}',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: NightshadeCard(
        variant: CardVariant.subtle,
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.mainId,
                    style: NightshadeTypography.h5.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    metaParts.join(' · '),
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.crosshair,
              size: ButtonSize.small,
              onPressed: () {
                final uri = Uri(
                  path: '/framing',
                  queryParameters: {
                    'ra': match.raHours.toStringAsFixed(6),
                    'dec': match.decDegrees.toStringAsFixed(6),
                    'name': match.mainId,
                  },
                );
                context.go(uri.toString());
              },
            ),
          ],
        ),
      ),
    );
  }
}
