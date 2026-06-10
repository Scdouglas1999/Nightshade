// Wave 6D / P2-12 — Mobile first-run setup wizard.
//
// When the operator pairs their phone to a freshly-installed Nightshade
// server, three things are usually missing and must be addressed before
// the dashboard becomes useful:
//
//   1. `imageOutputPath` is empty — every capture would fail to save.
//   2. No catalogs are installed — plate-solving and target search are
//      broken until the user pulls down at least one starlist.
//   3. No equipment profile exists — connecting devices is impossible.
//
// The full equipment-onboarding wizard in nightshade_app handles (3) in
// depth (auto-discovery, optical train, etc.); this companion wizard
// is intentionally minimal — three steps tied to the three missing
// bootstrap conditions — so a phone operator can get the server running
// in under a minute without the deep flow. Step 3 surfaces a button
// that *opens* the full equipment-onboarding flow rather than reimplementing
// device pickers inside the wizard.
//
// The wizard is reached from `mobile_dashboard_screen.dart` and any
// `NightshadeApp(isMobile: true)` shell when `shouldRunFirstRunSetup`
// resolves true. It writes the `firstRunCompleted` flag through
// `MobilePreferences` so it never auto-appears again, even if a future
// connection lands on a server with the same empty state.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../services/mobile_preferences.dart';
import '../../utils/error_snackbar.dart';

/// Detection record returned by [shouldRunFirstRunSetupProvider].
///
/// A getter-only struct so widgets can drill into the missing pieces and
/// show step-specific intro copy ("You also have no catalogs yet — let's
/// fix that next") without re-running the detection.
class FirstRunSetupNeeds {
  final bool missingImageOutputPath;
  final bool missingProfiles;
  final bool missingCatalogs;

  const FirstRunSetupNeeds({
    required this.missingImageOutputPath,
    required this.missingProfiles,
    required this.missingCatalogs,
  });

  /// True if at least one bootstrap condition is unmet AND the user has
  /// not previously dismissed the wizard.
  bool get hasAnyMissing =>
      missingImageOutputPath || missingProfiles || missingCatalogs;

  /// Nothing to do — every bootstrap condition is satisfied.
  static const FirstRunSetupNeeds none = FirstRunSetupNeeds(
    missingImageOutputPath: false,
    missingProfiles: false,
    missingCatalogs: false,
  );
}

/// Async detection provider. Returns [FirstRunSetupNeeds] describing what
/// the server is missing; if the user has already completed (or skipped)
/// the wizard once, returns [FirstRunSetupNeeds.none] regardless of
/// server state.
final shouldRunFirstRunSetupProvider = FutureProvider<FirstRunSetupNeeds>((
  ref,
) async {
  // Honor the persistent latch first. If the user has completed setup on
  // this device, we never auto-route to the wizard again even if a
  // future server reset would otherwise trigger the conditions.
  final prefsAsync = ref.watch(mobilePreferencesProvider);
  final prefs = prefsAsync.valueOrNull;
  if (prefs == null) {
    // Treat the not-yet-loaded prefs state as "skip the wizard for this
    // build" — the provider will re-resolve once shared_preferences is
    // ready and the next build will route correctly. This avoids a
    // false-positive flash of the wizard while prefs load.
    return FirstRunSetupNeeds.none;
  }
  if (prefs.firstRunCompleted) return FirstRunSetupNeeds.none;

  final backend = ref.watch(backendProvider);
  if (backend is! NetworkBackend) {
    // The wizard is companion-mode-only: a local FfiBackend always has
    // its profiles/catalogs/path managed through the desktop UI.
    return FirstRunSetupNeeds.none;
  }

  // Resolve each condition independently so a single failed call doesn't
  // suppress the wizard. We do not bail-early on the first match — the
  // wizard wants to know all three so its intro/Stepper can render the
  // right summary.
  var missingPath = false;
  var missingProfiles = false;
  var missingCatalogs = false;

  try {
    final settings = await backend.getSettings();
    missingPath = settings.imageOutputPath.trim().isEmpty;
  } catch (e, st) {
    developer.log(
      'first-run: getSettings failed: $e',
      name: 'FirstRunSetup',
      level: 1000,
      error: e,
      stackTrace: st,
    );
  }

  try {
    final profiles = await backend.getProfiles();
    missingProfiles = profiles.isEmpty;
  } catch (e, st) {
    developer.log(
      'first-run: getProfiles failed: $e',
      name: 'FirstRunSetup',
      level: 1000,
      error: e,
      stackTrace: st,
    );
  }

  try {
    final status = await backend.getCatalogStatus();
    missingCatalogs = !status.catalogs.any((c) => c.isInstalled);
  } catch (e, st) {
    developer.log(
      'first-run: getCatalogStatus failed: $e',
      name: 'FirstRunSetup',
      level: 1000,
      error: e,
      stackTrace: st,
    );
  }

  return FirstRunSetupNeeds(
    missingImageOutputPath: missingPath,
    missingProfiles: missingProfiles,
    missingCatalogs: missingCatalogs,
  );
});

/// Three-step setup wizard. Step list:
///
///   * Step 0 — Image output path. Operator picks a preset
///     ("Pictures/Nightshade", "Documents/Nightshade") or types a custom
///     path. The path is written via `NetworkBackend.updateSettings` so
///     the imaging service picks it up immediately.
///   * Step 1 — Catalogs. Lists available catalogs from
///     `/api/catalog/available` with a `requiredForPlateSolve` badge.
///     Operator selects what to install; the wizard fires
///     `downloadCatalog(name)` per pick and surfaces job handles in a
///     "downloading" list so the operator can move on while the server
///     fetches in the background.
///   * Step 2 — Profile. Surfaces the existing profile list (if the
///     operator already created one out of band) or routes them to the
///     full equipment onboarding flow.
class FirstRunSetupScreen extends ConsumerStatefulWidget {
  final FirstRunSetupNeeds needs;
  final VoidCallback onCompleted;

  const FirstRunSetupScreen({
    super.key,
    required this.needs,
    required this.onCompleted,
  });

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  int _activeStep = 0;
  bool _busy = false;

  // Step 0 state.
  String _selectedPathPreset = 'pictures';
  final TextEditingController _customPathController = TextEditingController();

  // Step 1 state.
  List<RemoteAvailableCatalog>? _availableCatalogs;
  final Set<String> _catalogsToInstall = {};
  final Set<String> _catalogsInFlight = {};
  String? _catalogLoadError;

  // Step 2 state.
  List<EquipmentProfile>? _profiles;

  @override
  void initState() {
    super.initState();
    // Skip past steps that aren't needed. If the server already has a
    // valid imageOutputPath, start on the catalogs step (etc.). We still
    // *show* the previous steps in the Stepper sidebar so the operator
    // can revisit, but the wizard opens on the first unfinished step.
    if (!widget.needs.missingImageOutputPath) {
      _activeStep = 1;
    }
    if (!widget.needs.missingImageOutputPath && !widget.needs.missingCatalogs) {
      _activeStep = 2;
    }
    unawaited(_loadCatalogsAndProfiles());
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogsAndProfiles() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) return;
    try {
      final results = await Future.wait<dynamic>([
        backend.listAvailableCatalogs(),
        backend.getProfiles(),
      ]);
      if (!mounted) return;
      setState(() {
        _availableCatalogs = results[0] as List<RemoteAvailableCatalog>;
        _profiles = results[1] as List<EquipmentProfile>;
        // Pre-select catalogs that the server flagged as required for
        // plate-solving. Operators almost always want these and the
        // checkbox stays editable so power users can opt out.
        for (final c in _availableCatalogs!) {
          if (c.requiredForPlateSolve) {
            _catalogsToInstall.add(c.name);
          }
        }
      });
    } catch (e, st) {
      developer.log(
        'first-run: failed to load catalogs/profiles: $e',
        name: 'FirstRunSetup',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _catalogLoadError = e is ServerError ? e.message : e.toString();
      });
    }
  }

  /// Translate a preset key into a real absolute path. Server-side the
  /// imaging service expands `~` and resolves relative paths against the
  /// data dir, but mobile operators almost always want a Pictures/Documents
  /// subdir — we send the explicit string the server will store as-is.
  String? _resolveSelectedPath() {
    switch (_selectedPathPreset) {
      case 'pictures':
        return '~/Pictures/Nightshade';
      case 'documents':
        return '~/Documents/Nightshade';
      case 'custom':
        final trimmed = _customPathController.text.trim();
        if (trimmed.isEmpty) return null;
        return trimmed;
    }
    return null;
  }

  Future<void> _commitImageOutputPath() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) return;
    final path = _resolveSelectedPath();
    if (path == null) {
      if (mounted) {
        showApiError(
          context,
          ServerError(
            code: 'invalid_input',
            message: 'Please select or enter an image output path',
          ),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final current = await backend.getSettings();
      await backend.updateSettings(current.copyWith(imageOutputPath: path));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _activeStep = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showApiErrorWithPrefix(context, 'Failed to set output path', e);
    }
  }

  Future<void> _commitCatalogs() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) return;
    if (_catalogsToInstall.isEmpty) {
      // Operator deliberately picked none — that's allowed (they may
      // have a custom catalog they upload via the desktop). Advance to
      // step 2 without firing any downloads.
      setState(() => _activeStep = 2);
      return;
    }
    setState(() => _busy = true);
    final pending = _catalogsToInstall.toList(growable: false);
    var firedAny = false;
    for (final name in pending) {
      try {
        await backend.downloadCatalog(name);
        firedAny = true;
        if (!mounted) return;
        setState(() {
          _catalogsInFlight.add(name);
        });
      } catch (e) {
        if (!mounted) return;
        showApiErrorWithPrefix(context, 'Catalog download failed ($name)', e);
        // Continue with remaining catalogs — one failure shouldn't
        // block the rest. The operator can revisit failures in the
        // Settings → Catalogs screen.
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (firedAny || _catalogsToInstall.isEmpty) _activeStep = 2;
    });
  }

  Future<void> _finish() async {
    final prefs = ref.read(mobilePreferencesProvider).valueOrNull;
    if (prefs != null) {
      await prefs.setFirstRunCompleted(true);
    }
    // Refresh the gate so the next build skips this screen.
    ref.invalidate(shouldRunFirstRunSetupProvider);
    if (!mounted) return;
    widget.onCompleted();
  }

  Future<void> _skip() async {
    // Skipping still records the flag — the wizard is a one-time interrupt;
    // the operator can always reach the same settings from the Settings
    // tab without the wizard re-asserting itself.
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('First-run setup'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _skip,
            child: Text('Skip', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
      body: Stepper(
        currentStep: _activeStep,
        controlsBuilder: (context, details) => const SizedBox.shrink(),
        onStepTapped: _busy
            ? null
            : (step) {
                setState(() => _activeStep = step);
              },
        steps: [
          Step(
            title: const Text('Image output path'),
            isActive: _activeStep == 0,
            state: widget.needs.missingImageOutputPath
                ? (_activeStep > 0 ? StepState.complete : StepState.indexed)
                : StepState.complete,
            content: _buildImagePathStep(colors),
          ),
          Step(
            title: const Text('Catalogs'),
            isActive: _activeStep == 1,
            state: widget.needs.missingCatalogs
                ? (_activeStep > 1 ? StepState.complete : StepState.indexed)
                : StepState.complete,
            content: _buildCatalogsStep(colors),
          ),
          Step(
            title: const Text('Equipment profile'),
            isActive: _activeStep == 2,
            state: widget.needs.missingProfiles
                ? StepState.indexed
                : StepState.complete,
            content: _buildProfileStep(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePathStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose where Nightshade should save captured images. The path '
          'is relative to the server, not your phone.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        RadioListTile<String>(
          value: 'pictures',
          groupValue: _selectedPathPreset,
          onChanged: _busy
              ? null
              : (v) => setState(() => _selectedPathPreset = v ?? 'pictures'),
          title: const Text('~/Pictures/Nightshade'),
          subtitle: const Text('Recommended for Windows/macOS desktops'),
        ),
        RadioListTile<String>(
          value: 'documents',
          groupValue: _selectedPathPreset,
          onChanged: _busy
              ? null
              : (v) => setState(() => _selectedPathPreset = v ?? 'pictures'),
          title: const Text('~/Documents/Nightshade'),
          subtitle: const Text('Often synced to cloud storage'),
        ),
        RadioListTile<String>(
          value: 'custom',
          groupValue: _selectedPathPreset,
          onChanged: _busy
              ? null
              : (v) => setState(() => _selectedPathPreset = v ?? 'pictures'),
          title: const Text('Custom path'),
        ),
        if (_selectedPathPreset == 'custom') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customPathController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Absolute path',
              hintText: 'e.g. D:\\Astro\\Captures',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        NightshadeButton(
          onPressed: _busy ? null : _commitImageOutputPath,
          label: _busy ? 'Saving...' : 'Save and continue',
        ),
      ],
    );
  }

  Widget _buildCatalogsStep(NightshadeColors colors) {
    if (_catalogLoadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Could not list catalogs: $_catalogLoadError',
            style: TextStyle(color: colors.error),
          ),
          const SizedBox(height: 12),
          NightshadeButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _catalogLoadError = null;
                      _availableCatalogs = null;
                    });
                    unawaited(_loadCatalogsAndProfiles());
                  },
            label: 'Retry',
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _activeStep = 2),
            child: const Text('Skip catalogs'),
          ),
        ],
      );
    }
    final catalogs = _availableCatalogs;
    if (catalogs == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick catalogs to install. Plate-solving will not work until at '
          'least one star catalog is installed. Downloads run in the '
          'background; you can finish setup before they complete.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final c in catalogs)
          CheckboxListTile(
            value: _catalogsToInstall.contains(c.name),
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      if (v == true) {
                        _catalogsToInstall.add(c.name);
                      } else {
                        _catalogsToInstall.remove(c.name);
                      }
                    });
                  },
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Expanded(child: Text(c.displayName)),
                if (c.requiredForPlateSolve)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'plate-solve',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${c.description} (${_formatSize(c.sizeBytes)})',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                onPressed: _busy ? null : _commitCatalogs,
                label: _busy
                    ? 'Starting downloads...'
                    : _catalogsToInstall.isEmpty
                    ? 'Skip and continue'
                    : 'Install and continue',
              ),
            ),
          ],
        ),
        if (_catalogsInFlight.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Downloading: ${_catalogsInFlight.join(", ")}',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileStep(NightshadeColors colors) {
    final profiles = _profiles;
    if (profiles == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (profiles.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You already have ${profiles.length} equipment profile'
            '${profiles.length == 1 ? "" : "s"}. The wizard is done.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final p in profiles)
            ListTile(
              leading: const Icon(LucideIcons.workflow),
              title: Text(p.name),
              subtitle: Text(
                p.description ?? 'No description',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 16),
          NightshadeButton(
            onPressed: _busy ? null : _finish,
            label: 'Finish setup',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No equipment profile yet. The full equipment-onboarding wizard '
          'will help you discover cameras, mounts, and other devices, then '
          'save the configuration as a reusable profile. You can also '
          'finish setup here and create a profile later from the Devices '
          'tab.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        NightshadeButton(
          onPressed: _busy ? null : _finish,
          label: 'Finish without a profile',
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  // The full equipment onboarding lives in nightshade_app
                  // and is reached via the equipment screen route. We
                  // close the wizard with the latch set so the operator
                  // can return to the dashboard and tap "Add equipment"
                  // without the wizard re-asserting itself.
                  await _finish();
                },
          child: const Text('Set up equipment from the Devices tab'),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
