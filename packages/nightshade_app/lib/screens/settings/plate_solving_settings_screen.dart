import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/snackbar_helper.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/solver_detection_card.dart';

/// Dedicated full-screen Plate Solving settings page (W6-SOLVER-UX §6.1).
///
/// Layered above the legacy `PlateSolvingSettings` widget that lives in
/// the main Settings shell — this screen exposes the new detection /
/// verify / catalog tooling needed for the centering, framing, and polar
/// alignment workflows. Reached via `/settings/plate-solving`.
class PlateSolvingSettingsScreen extends ConsumerStatefulWidget {
  const PlateSolvingSettingsScreen({super.key});

  @override
  ConsumerState<PlateSolvingSettingsScreen> createState() =>
      _PlateSolvingSettingsScreenState();
}

class _PlateSolvingSettingsScreenState
    extends ConsumerState<PlateSolvingSettingsScreen> {
  Future<void> _browseAstapExecutable(PlateSolverPreference current) async {
    final typeGroup = XTypeGroup(
      label: 'ASTAP executable',
      extensions: Platform.isWindows ? const ['exe'] : null,
    );
    final file = await openFile(
      acceptedTypeGroups: [typeGroup],
      confirmButtonText: 'Use this ASTAP',
    );
    if (file == null || !mounted) return;
    await _savePreference(current.copyWith(astapPath: file.path));
  }

  Future<void> _browseAstapCatalogDirectory(
      PlateSolverPreference current) async {
    final dir = await getDirectoryPath(
      confirmButtonText: 'Use this catalog folder',
    );
    if (dir == null || !mounted) return;
    await _savePreference(current.copyWith(catalogPath: dir));
  }

  Future<void> _browseAstrometryExecutable(
      PlateSolverPreference current) async {
    final typeGroup = XTypeGroup(
      label: 'solve-field',
      extensions: Platform.isWindows ? const ['exe'] : null,
    );
    final file = await openFile(
      acceptedTypeGroups: [typeGroup],
      confirmButtonText: 'Use this solve-field',
    );
    if (file == null || !mounted) return;
    await _savePreference(current.copyWith(astrometryPath: file.path));
  }

  Future<void> _savePreference(PlateSolverPreference next) async {
    final notifier = ref.read(plateSolverSettingsNotifierProvider.notifier);
    try {
      final ok = await notifier.updatePreference(next);
      if (!mounted) return;
      if (ok) {
        context.showSuccessSnackBar('Plate-solver settings saved.');
      } else {
        context
            .showErrorSnackBar('Another save is already in flight. Wait, '
                'then try again.');
      }
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to save plate-solver settings: $e');
    }
  }

  Future<void> _rescan() async {
    final notifier = ref.read(plateSolverSettingsNotifierProvider.notifier);
    try {
      await notifier.rescan();
      if (!mounted) return;
      context.showSuccessSnackBar('Re-scanned plate-solver paths.');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Re-scan failed: $e');
    }
  }

  Future<void> _verifyAstap(String executablePath) async {
    final notifier = ref.read(plateSolverSettingsNotifierProvider.notifier);
    await notifier.verifyAstap(executablePath);
  }

  Future<void> _verifyAstrometry(String executablePath) async {
    final notifier = ref.read(plateSolverSettingsNotifierProvider.notifier);
    await notifier.verifyAstrometry(executablePath);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final detectionAsync = ref.watch(plateSolverDetectionProvider);
    final prefAsync = ref.watch(plateSolverPreferenceProvider);
    final uiState = ref.watch(plateSolverSettingsNotifierProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('Plate Solving'),
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: detectionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertCircle, color: colors.error, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Plate-solver detection failed: $error',
                  style: TextStyle(color: colors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                NightshadeButton(
                  label: 'Retry',
                  onPressed: _rescan,
                  icon: LucideIcons.refreshCw,
                ),
              ],
            ),
          ),
        ),
        data: (detection) => prefAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load plate-solver preferences: $error',
                style: TextStyle(color: colors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (pref) => _buildBody(
            colors: colors,
            detection: detection,
            preference: pref,
            uiState: uiState,
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required NightshadeColors colors,
    required PlateSolverDetection detection,
    required PlateSolverPreference preference,
    required PlateSolverSettingsState uiState,
  }) {
    return SettingsPage(
      title: 'Plate Solving',
      description:
          'Configure ASTAP / Astrometry.net for centering, framing, and '
          'polar alignment.',
      colors: colors,
      children: [
        SolverDetectionCard(
          detection: detection,
          astapVerifyInfo: uiState.astapVerifyInfo,
          astapVerifyError: uiState.astapVerifyError,
        ),
        if (!detection.hasAnySolver) ...[
          const SizedBox(height: 16),
          _NoSolverQuickStart(
            colors: colors,
            onRescan: uiState.savingPreference ? null : _rescan,
            isRescanning: uiState.savingPreference,
          ),
        ] else if (detection.astapPath != null && !detection.astapReady) ...[
          const SizedBox(height: 12),
          _CatalogMissingHint(
            colors: colors,
            preference: preference,
            onBrowseCatalog: () => _browseAstapCatalogDirectory(preference),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: NightshadeButton(
            label: uiState.savingPreference ? 'Re-scanning…' : 'Re-scan',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            isLoading: uiState.savingPreference,
            onPressed: uiState.savingPreference ? null : _rescan,
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'ASTAP',
          colors: colors,
          children: [
            SettingRow(
              icon: LucideIcons.fileCode,
              title: 'ASTAP executable',
              subtitle: preference.astapPath.isEmpty
                  ? (detection.astapPath ?? 'Auto-detect — not found')
                  : preference.astapPath,
              trailing: SettingsPathInput(
                path: preference.astapPath,
                onBrowse: () => _browseAstapExecutable(preference),
                colors: colors,
              ),
              colors: colors,
            ),
            SettingRow(
              icon: LucideIcons.folder,
              title: 'ASTAP catalog directory',
              subtitle: preference.catalogPath.isEmpty
                  ? (detection.catalogPath ?? 'Auto-detect — not found')
                  : preference.catalogPath,
              trailing: SettingsPathInput(
                path: preference.catalogPath,
                onBrowse: () => _browseAstapCatalogDirectory(preference),
                colors: colors,
              ),
              colors: colors,
            ),
            SettingRow(
              icon: LucideIcons.shieldCheck,
              title: 'Verify ASTAP',
              subtitle: _verifyAstapSubtitle(
                  detection: detection,
                  preference: preference,
                  uiState: uiState),
              trailing: NightshadeButton(
                label: uiState.verifying ? 'Verifying…' : 'Verify',
                icon: LucideIcons.play,
                variant: ButtonVariant.outline,
                isLoading: uiState.verifying,
                onPressed: _resolveAstapTarget(detection, preference) == null
                    ? null
                    : () => _verifyAstap(
                        _resolveAstapTarget(detection, preference)!),
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Astrometry.net',
          colors: colors,
          children: [
            SettingRow(
              icon: LucideIcons.fileCode,
              title: 'solve-field executable',
              subtitle: preference.astrometryPath.isEmpty
                  ? (detection.astrometryPath ??
                      'Auto-detect — not found')
                  : preference.astrometryPath,
              trailing: SettingsPathInput(
                path: preference.astrometryPath,
                onBrowse: () => _browseAstrometryExecutable(preference),
                colors: colors,
              ),
              colors: colors,
            ),
            SettingRow(
              icon: LucideIcons.shieldCheck,
              title: 'Verify Astrometry.net',
              subtitle: _verifyAstrometrySubtitle(
                  detection: detection,
                  preference: preference,
                  uiState: uiState),
              trailing: NightshadeButton(
                label: uiState.verifying ? 'Verifying…' : 'Verify',
                icon: LucideIcons.play,
                variant: ButtonVariant.outline,
                isLoading: uiState.verifying,
                onPressed:
                    _resolveAstrometryTarget(detection, preference) == null
                        ? null
                        : () => _verifyAstrometry(
                            _resolveAstrometryTarget(detection, preference)!),
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Active solver',
          colors: colors,
          children: [
            _ChoiceRow(
              label: 'ASTAP',
              subtitle:
                  'Fast offline solver — recommended for almost all setups.',
              icon: LucideIcons.zap,
              value: PlateSolverChoice.astap,
              groupValue: preference.choice,
              colors: colors,
              onChanged: (next) async {
                if (next == null) return;
                await _savePreference(preference.copyWith(choice: next));
              },
            ),
            _ChoiceRow(
              label: 'Astrometry.net',
              subtitle:
                  'Local solve-field. Slower but useful on Linux/macOS.',
              icon: LucideIcons.globe,
              value: PlateSolverChoice.astrometry,
              groupValue: preference.choice,
              colors: colors,
              onChanged: (next) async {
                if (next == null) return;
                await _savePreference(preference.copyWith(choice: next));
              },
            ),
            _ChoiceRow(
              label: 'Auto-fallback',
              subtitle:
                  'Try ASTAP first; fall back to Astrometry.net if ASTAP '
                  'fails or is missing.',
              icon: LucideIcons.shuffle,
              value: PlateSolverChoice.auto,
              groupValue: preference.choice,
              colors: colors,
              onChanged: (next) async {
                if (next == null) return;
                await _savePreference(preference.copyWith(choice: next));
              },
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  /// Resolve which ASTAP path the verify button should run against.
  /// Prefers the user-configured override (preference), then the detected
  /// auto-found path. Returns `null` if neither is set.
  static String? _resolveAstapTarget(
    PlateSolverDetection detection,
    PlateSolverPreference preference,
  ) {
    if (preference.astapPath.isNotEmpty) return preference.astapPath;
    return detection.astapPath;
  }

  static String? _resolveAstrometryTarget(
    PlateSolverDetection detection,
    PlateSolverPreference preference,
  ) {
    if (preference.astrometryPath.isNotEmpty) return preference.astrometryPath;
    return detection.astrometryPath;
  }

  static String _verifyAstapSubtitle({
    required PlateSolverDetection detection,
    required PlateSolverPreference preference,
    required PlateSolverSettingsState uiState,
  }) {
    final target = _resolveAstapTarget(detection, preference);
    if (target == null) {
      return 'No ASTAP path to verify. Browse for one above first.';
    }
    if (uiState.astapVerifyError != null) {
      return 'Last verify failed: ${uiState.astapVerifyError}';
    }
    final info = uiState.astapVerifyInfo;
    if (info != null) {
      return 'OK — ${info.flavour}: ${info.versionLine}';
    }
    return 'Run --help against $target to confirm the binary is healthy.';
  }

  static String _verifyAstrometrySubtitle({
    required PlateSolverDetection detection,
    required PlateSolverPreference preference,
    required PlateSolverSettingsState uiState,
  }) {
    final target = _resolveAstrometryTarget(detection, preference);
    if (target == null) {
      return 'No solve-field path to verify. Browse for one above first.';
    }
    if (uiState.astrometryVerifyError != null) {
      return 'Last verify failed: ${uiState.astrometryVerifyError}';
    }
    final info = uiState.astrometryVerifyInfo;
    if (info != null) {
      return 'OK — ${info.flavour}: ${info.versionLine}';
    }
    return 'Run --help against $target to confirm the binary is healthy.';
  }
}

/// Three-step quick-start visual shown beneath the detection banner when
/// no plate solver is installed yet. Walks the user from "install ASTAP"
/// to "download a catalog" to "re-scan".
class _NoSolverQuickStart extends StatelessWidget {
  static const String _astapDownloadUrl = 'https://www.hnsky.org/astap.htm';

  final NightshadeColors colors;
  final VoidCallback? onRescan;
  final bool isRescanning;

  const _NoSolverQuickStart({
    required this.colors,
    required this.onRescan,
    required this.isRescanning,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get started in 3 steps',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nightshade needs a plate solver to centre targets, verify '
            'framing, and run polar alignment. Follow these steps, then '
            'click Re-scan to detect the install.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          _QuickStartStep(
            colors: colors,
            stepNumber: 1,
            title: 'Install ASTAP',
            body: 'ASTAP is fast, free, and works fully offline. Click '
                'below to open the download page.',
            icon: LucideIcons.download,
            action: NightshadeButton(
              label: 'Open ASTAP download page',
              icon: LucideIcons.externalLink,
              size: ButtonSize.small,
              variant: ButtonVariant.outline,
              onPressed: () => _openUrl(_astapDownloadUrl),
            ),
            onTap: () => _openUrl(_astapDownloadUrl),
          ),
          const SizedBox(height: 10),
          _QuickStartStep(
            colors: colors,
            stepNumber: 2,
            title: 'Download a star catalog',
            body: 'Grab a catalog from the same page. V17 is recommended '
                'for almost all setups — it covers stars down to mag 17 '
                'and works across the full sky. Drop the catalog next to '
                'astap.exe, or into the folder you will point Nightshade '
                'at below.',
            icon: LucideIcons.database,
            action: NightshadeButton(
              label: 'Open ASTAP catalog page',
              icon: LucideIcons.externalLink,
              size: ButtonSize.small,
              variant: ButtonVariant.outline,
              onPressed: () => _openUrl(_astapDownloadUrl),
            ),
            onTap: () => _openUrl(_astapDownloadUrl),
          ),
          const SizedBox(height: 10),
          _QuickStartStep(
            colors: colors,
            stepNumber: 3,
            title: 'Click Re-scan',
            body: 'Once ASTAP and the catalog are installed, click Re-scan '
                'so Nightshade picks them up.',
            icon: LucideIcons.refreshCw,
            action: NightshadeButton(
              label: isRescanning ? 'Re-scanning…' : 'Re-scan now',
              icon: LucideIcons.refreshCw,
              size: ButtonSize.small,
              isLoading: isRescanning,
              onPressed: onRescan,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStartStep extends StatelessWidget {
  final NightshadeColors colors;
  final int stepNumber;
  final String title;
  final String body;
  final IconData icon;
  final Widget action;

  /// Optional tap target for the whole card; used by step 1 / step 2 so the
  /// whole row navigates to the install page, matching the "clickable card"
  /// behaviour called out in the spec.
  final VoidCallback? onTap;

  const _QuickStartStep({
    required this.colors,
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.icon,
    required this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '$stepNumber',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                action,
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: card,
    );
  }
}

/// Inline hint shown above the ASTAP settings section when ASTAP is
/// detected but no star catalog is found. The directory probed by
/// Nightshade is surfaced verbatim alongside a one-click browse button
/// so the user can point the app at the catalog they already have.
class _CatalogMissingHint extends StatelessWidget {
  final NightshadeColors colors;
  final PlateSolverPreference preference;
  final VoidCallback onBrowseCatalog;

  const _CatalogMissingHint({
    required this.colors,
    required this.preference,
    required this.onBrowseCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final probed = preference.catalogPath.isNotEmpty
        ? preference.catalogPath
        : 'the directory containing astap.exe';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.folderSearch, size: 16, color: colors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Searching for catalogs in $probed. If your catalog lives '
              'somewhere else, point Nightshade at it now.',
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            label: 'Browse for catalog directory',
            icon: LucideIcons.folderOpen,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: onBrowseCatalog,
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final PlateSolverChoice value;
  final PlateSolverChoice groupValue;
  final NightshadeColors colors;
  final ValueChanged<PlateSolverChoice?> onChanged;
  final bool isLast;

  const _ChoiceRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.colors,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: icon,
      title: label,
      subtitle: subtitle,
      trailing: Radio<PlateSolverChoice>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: colors.accent,
      ),
      isLast: isLast,
      colors: colors,
    );
  }
}
