part of '../diagnostics_screen.dart';

class _DiagnosticsContent extends ConsumerWidget {
  final int sessionId;
  final bool isMobile;

  const _DiagnosticsContent({
    required this.sessionId,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final diagnosticsAsync =
        ref.watch(opticalTrainDiagnosticsProvider(sessionId));
    final psfAsync = ref.watch(psfTilesForSessionProvider(sessionId));
    final residualsAsync =
        ref.watch(residualVectorsForSessionProvider(sessionId));

    return diagnosticsAsync.when(
      data: (diagnostics) {
        final psfTiles = psfAsync.valueOrNull ?? const [];
        final residuals = residualsAsync.valueOrNull ?? const [];

        return LayoutBuilder(
          builder: (context, constraints) {
            final stackLayout = isMobile ||
                constraints.maxWidth < NightshadeTokens.breakpointTablet;
            if (stackLayout) {
              return _MobileLayout(
                diagnostics: diagnostics,
                psfTiles: psfTiles,
                residuals: residuals,
                colors: colors,
              );
            }
            return _DesktopLayout(
              diagnostics: diagnostics,
              psfTiles: psfTiles,
              residuals: residuals,
              colors: colors,
              maxWidth: constraints.maxWidth,
            );
          },
        );
      },
      // Shimmer grid placeholder keeps the diagnostics card layout in place
      // while the analysis stream loads, instead of collapsing to a spinner.
      loading: () => const _DiagnosticsLoadingSkeleton(),
      error: (error, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 32, color: colors.error),
            const SizedBox(height: 12),
            Text(
              context.l10n.text('diagnosticsFailedTitle'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text('diagnosticsFailedBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            NightshadeButton(
              label: context.l10n.text('diagnosticsRetry'),
              icon: LucideIcons.refreshCw,
              size: ButtonSize.small,
              onPressed: () {
                ref.invalidate(opticalTrainDiagnosticsProvider(sessionId));
                ref.invalidate(psfTilesForSessionProvider(sessionId));
                ref.invalidate(residualVectorsForSessionProvider(sessionId));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final List<PsfFieldTileRow> psfTiles;
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;
  final double maxWidth;

  const _DesktopLayout({
    required this.diagnostics,
    required this.psfTiles,
    required this.residuals,
    required this.colors,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final panelWidth = clampPanelWidth(
      maxWidth,
      fraction: 0.32,
      min: 280,
      max: 320,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: health grade + issues
        SizedBox(
          width: panelWidth,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _HealthGradeCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _TiltAssessmentCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _CollimationCard(diagnostics: diagnostics, colors: colors),
                const SizedBox(height: 12),
                _IssuesCard(diagnostics: diagnostics, colors: colors),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right column: field map + residual overlay
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _PsfFieldMapCard(
                  psfTiles: psfTiles,
                  colors: colors,
                ),
                const SizedBox(height: 12),
                _ResidualVectorCard(
                  residuals: residuals,
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final OpticalTrainDiagnostics diagnostics;
  final List<PsfFieldTileRow> psfTiles;
  final List<AstrometryResidualVectorRow> residuals;
  final NightshadeColors colors;

  const _MobileLayout({
    required this.diagnostics,
    required this.psfTiles,
    required this.residuals,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _HealthGradeCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _TiltAssessmentCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _CollimationCard(diagnostics: diagnostics, colors: colors),
          const SizedBox(height: 12),
          _PsfFieldMapCard(psfTiles: psfTiles, colors: colors),
          const SizedBox(height: 12),
          _ResidualVectorCard(residuals: residuals, colors: colors),
          const SizedBox(height: 12),
          _IssuesCard(diagnostics: diagnostics, colors: colors),
        ],
      ),
    );
  }
}

// --- Health Grade Card ---
