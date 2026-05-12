import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Imports the model leaf directly rather than `nightshade_core.dart` so
// tests can exercise this widget without pulling in the entire core
// barrel (which transitively touches broken framing/scheduler providers
// on the v2.5.0-hardening base). Once those are fixed, the import can
// move back to the public barrel — both surfaces export the same types.
import 'package:nightshade_core/src/models/plate_solver.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Status banner shown at the top of the Plate Solving settings page.
///
/// Three visual states, driven entirely by the supplied [detection]:
///   * ASTAP detected + catalog found → green check, path + catalog string
///   * ASTAP detected but no catalog → amber warning, prompts user to set
///     the catalog dir
///   * No solver installed → red, with a clickable install link
class SolverDetectionCard extends StatelessWidget {
  static const String astapDownloadUrl = 'https://www.hnsky.org/astap.htm';
  static const String astrometryDownloadUrl =
      'https://astrometry.net/use.html';

  final PlateSolverDetection detection;

  /// Optional verify-result info to display alongside the green check.
  /// `null` when the user hasn't yet pressed "Verify".
  final PlateSolverInfo? astapVerifyInfo;

  /// Optional verify-result error message; surfaced inline when verify
  /// fails so the user understands the install is broken even though the
  /// binary exists on disk.
  final String? astapVerifyError;

  const SolverDetectionCard({
    super.key,
    required this.detection,
    this.astapVerifyInfo,
    this.astapVerifyError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    if (detection.astapPath == null) {
      return _buildNotInstalled(theme, colors);
    }
    if (!detection.astapReady) {
      return _buildCatalogMissing(theme, colors);
    }
    return _buildReady(theme, colors);
  }

  Widget _buildReady(ThemeData theme, NightshadeColors colors) {
    final catalogName = detection.catalogName ?? '';
    final magLimit = detection.catalogMagnitudeLimit;
    final catalogSuffix = catalogName.isEmpty
        ? ''
        : magLimit == null
            ? ' (catalog: $catalogName)'
            : ' (catalog: $catalogName to mag '
                '${magLimit.toStringAsFixed(0)})';

    return _CardShell(
      colors: colors,
      borderColor: colors.success,
      icon: LucideIcons.checkCircle,
      iconColor: colors.success,
      title: 'ASTAP detected$catalogSuffix',
      body: [
        Text(
          detection.astapPath!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (astapVerifyInfo != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 14, color: colors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${astapVerifyInfo!.flavour}: '
                  '${astapVerifyInfo!.versionLine}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.success,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (astapVerifyError != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  astapVerifyError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (detection.astrometryPath != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(LucideIcons.plus, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Astrometry.net fallback: ${detection.astrometryPath!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCatalogMissing(ThemeData theme, NightshadeColors colors) {
    return _CardShell(
      colors: colors,
      borderColor: colors.warning,
      icon: LucideIcons.alertTriangle,
      iconColor: colors.warning,
      title: 'ASTAP detected — catalog missing',
      body: [
        Text(
          detection.astapPath!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'ASTAP needs a star catalog (V17, D80, G18, …) to solve. Use '
          '"Browse for ASTAP catalog directory" below, or copy a catalog '
          'next to astap.exe.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        _LinkText(
          url: astapDownloadUrl,
          label: 'Download an ASTAP catalog',
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildNotInstalled(ThemeData theme, NightshadeColors colors) {
    final hasAstrometry = detection.astrometryPath != null;

    return _CardShell(
      colors: colors,
      borderColor: colors.error,
      icon: LucideIcons.xCircle,
      iconColor: colors.error,
      title: hasAstrometry
          ? 'ASTAP not installed — only Astrometry.net available'
          : 'ASTAP not installed — Nightshade cannot plate-solve',
      body: [
        if (!hasAstrometry)
          Text(
            'Nightshade needs at least one plate solver to centre targets, '
            'verify framing, and perform polar alignment. ASTAP is the '
            'recommended choice for almost all setups.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
            ),
          )
        else
          Text(
            'Astrometry.net is reachable at '
            '${detection.astrometryPath!}, but ASTAP is the recommended '
            'solver — it is faster and works fully offline. Install ASTAP '
            'and re-scan to switch.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
            ),
          ),
        const SizedBox(height: 6),
        _LinkText(
          url: astapDownloadUrl,
          label: 'Download ASTAP — hnsky.org',
          colors: colors,
        ),
        const SizedBox(height: 2),
        _LinkText(
          url: astrometryDownloadUrl,
          label: 'Install Astrometry.net (Linux/macOS)',
          colors: colors,
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  final NightshadeColors colors;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> body;

  const _CardShell({
    required this.colors,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ...body,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  final String url;
  final String label;
  final NightshadeColors colors;

  const _LinkText({
    required this.url,
    required this.label,
    required this.colors,
  });

  Future<void> _open() async {
    final uri = Uri.parse(url);
    // Why no fallback: install links are static, well-formed https URLs.
    // canLaunchUrl + launchUrl raise on failure so the user gets a real
    // error rather than a silent no-op.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.externalLink, size: 12, color: colors.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
