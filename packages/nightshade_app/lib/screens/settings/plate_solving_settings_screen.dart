import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
