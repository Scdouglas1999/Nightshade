import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'device_picker_step.dart';

/// Guider step.
///
/// Most users guide with PHD2 over its TCP socket (default 4400), so
/// alongside the device picker we expose a dedicated host:port field
/// with a "Test connection" button that runs [GuidingBackend.isPhd2Running]
/// — a real socket probe, not a stub. Native guiders (camera-tracked
/// stars without PHD2) still show up in the picker.
///
/// Selecting PHD2 is deliberately independent of the probe. This wizard is run
/// indoors, at a desk, before PHD2 has been installed or launched for the
/// night; when "Use PHD2" only existed as a side effect of a *successful*
/// test, that user could not record their guider at all — Next silently
/// dropped the typed host/port and the summary step said "— not set —". Test
/// stays as verification you can run when PHD2 is up.
class OnboardingGuiderStep extends ConsumerStatefulWidget {
  const OnboardingGuiderStep({super.key});

  @override
  ConsumerState<OnboardingGuiderStep> createState() =>
      _OnboardingGuiderStepState();
}

class _OnboardingGuiderStepState extends ConsumerState<OnboardingGuiderStep> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  bool _testing = false;
  bool? _lastResult;
  String? _lastError;

  /// The `host:port` the last test actually probed.
  ///
  /// The result line is only shown while the fields still read the same
  /// endpoint. Editing the host after a green "PHD2 reachable. Selection
  /// saved." left that sentence on screen describing a different machine — and
  /// the guider stored in the draft (plus the phd2Host/phd2Port settings the
  /// connect path reads) was still the *old* address, so the user carried on
  /// believing the box they were now looking at had been verified and saved.
  String? _testedEndpoint;

  String get _currentEndpoint =>
      '${_hostController.text.trim()}:${_portController.text.trim()}';

  @override
  void initState() {
    super.initState();
    // Seed the host/port from the current app settings so the user sees
    // their previous PHD2 setup. Falls back to localhost:4400.
    _hostController = TextEditingController(text: 'localhost');
    _portController = TextEditingController(text: '4400');

    // Pull the live PHD2 host/port via the settings provider for resume.
    Future.microtask(() async {
      if (!mounted) return;
      try {
        final settings = await ref.read(appSettingsProvider.future);
        if (!mounted) return;
        _hostController.text = settings.phd2Host;
        _portController.text = settings.phd2Port.toString();
      } catch (_) {
        // Fall back to defaults — settings will get persisted when the
        // user finishes the wizard.
      }
    });
  }

  /// `host:port` when [guiderId] is a PHD2 selection, else null.
  ///
  /// The draft — not a local flag — is the source of truth for "PHD2 is the
  /// chosen guider", so picking a native guider below silently retires the
  /// PHD2 selection line instead of leaving two contradictory ticks.
  static String? _phd2EndpointOf(String? guiderId) {
    const prefix = 'phd2:';
    if (guiderId == null || !guiderId.startsWith(prefix)) return null;
    return guiderId.substring(prefix.length);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  /// Record PHD2 at the typed endpoint as this profile's guider.
  ///
  /// Deliberately does not probe: the wizard has to be completable with PHD2
  /// switched off. Returns false (and leaves the draft alone) only when the
  /// endpoint is not a usable address at all.
  Future<bool> _savePhd2Selection(String host, int? port) async {
    if (host.isEmpty || port == null) {
      setState(() {
        _lastResult = false;
        _lastError = 'Enter a host and a numeric port.';
        _testedEndpoint = _currentEndpoint;
      });
      return false;
    }
    await ref.read(onboardingDraftProvider.notifier).setGuider(
          id: 'phd2:$host:$port',
          name: 'PHD2 ($host:$port)',
        );
    // _connectGuider reads phd2Host/phd2Port from settings (not the device
    // id), so persist the chosen endpoint or a non-default host connects
    // back to localhost:4400.
    final s = ref.read(appSettingsProvider.notifier);
    await s.setPhd2Host(host);
    await s.setPhd2Port(port);
    return true;
  }

  Future<void> _useThisPhd2() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    await _savePhd2Selection(host, port);
  }

  Future<void> _clearPhd2Selection() async {
    await ref.read(onboardingDraftProvider.notifier).setGuider(id: '');
    if (!mounted) return;
    setState(() {
      _lastResult = null;
      _lastError = null;
      _testedEndpoint = null;
    });
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    setState(() {
      _testing = true;
      _lastResult = null;
      _lastError = null;
      _testedEndpoint = '$host:$portText';
    });
    final port = int.tryParse(portText);
    if (host.isEmpty || port == null) {
      setState(() {
        _testing = false;
        _lastResult = false;
        _lastError = 'Host or port is empty.';
      });
      return;
    }
    try {
      final running = await ref
          .read(guidingBackendProvider)
          .isPhd2Running(host: host, port: port);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _lastResult = running;
        _lastError = running
            ? null
            : 'No response on $host:$port. Is PHD2 running with "Enable Server" turned on?';
      });
      // A passing probe still selects PHD2 in one tap — the common case where
      // the user already has it running.
      if (running) await _savePhd2Selection(host, port);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _lastResult = false;
        _lastError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    // `host:port` recorded in the draft as the PHD2 guider (null when the
    // draft holds no guider, or a native one).
    final savedEndpoint = _phd2EndpointOf(draft.guiderId);
    final phd2IsSelected = savedEndpoint == _currentEndpoint;

    // Scrollable: this step stacks a PHD2 card, a divider and a whole device
    // picker, which together need more height than a small desktop window or a
    // phone gives the wizard body. As a bare Column the surplus overflowed and
    // painted over whatever sat below it.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set up guiding (optional)',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'PHD2 over TCP is the most common setup. We can also discover native guiders if your camera supports tracking.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // PHD2 quick path
          NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusLg,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(NightshadeIcons.crosshair,
                        color: colors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'PHD2',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _hostController,
                        // Re-derive the result line on every keystroke: a test
                        // result describes one endpoint and must disappear the
                        // moment the fields name a different one.
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: colors.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Host',
                          labelStyle: TextStyle(color: colors.textSecondary),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: NightshadeTokens.borderRadiusMd,
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: NightshadeTokens.borderRadiusMd,
                            borderSide: BorderSide(color: colors.primary),
                          ),
                          filled: true,
                          fillColor: colors.background,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: colors.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Port',
                          labelStyle: TextStyle(color: colors.textSecondary),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: NightshadeTokens.borderRadiusMd,
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: NightshadeTokens.borderRadiusMd,
                            borderSide: BorderSide(color: colors.primary),
                          ),
                          filled: true,
                          fillColor: colors.background,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    NightshadeButton(
                      icon: NightshadeIcons.bolt,
                      label: _testing ? 'Testing…' : 'Test',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: _testing ? null : _testConnection,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // The selection action, separate from the probe. Test only
                // reports reachability; this is what writes the guider into
                // the profile, so an indoor setup with PHD2 not yet running
                // can still finish the wizard with its guider recorded.
                Row(
                  children: [
                    NightshadeButton(
                      icon: NightshadeIcons.check,
                      label: phd2IsSelected ? 'PHD2 selected' : 'Use PHD2',
                      variant: ButtonVariant.primary,
                      size: ButtonSize.small,
                      onPressed: phd2IsSelected ? null : _useThisPhd2,
                    ),
                    if (savedEndpoint != null) ...[
                      const SizedBox(width: 8),
                      NightshadeButton(
                        label: 'Clear',
                        variant: ButtonVariant.ghost,
                        size: ButtonSize.small,
                        onPressed: _clearPhd2Selection,
                      ),
                    ],
                  ],
                ),
                if (savedEndpoint != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(LucideIcons.checkCircle2,
                          size: 16, color: colors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          phd2IsSelected
                              ? 'Guider set to PHD2 at $savedEndpoint.'
                              // Fields edited after selecting: name both
                              // addresses rather than leaving a tick over an
                              // address that is not the one in the profile.
                              : 'Saved guider is still PHD2 at $savedEndpoint. '
                                  'Press Use PHD2 to switch to '
                                  '$_currentEndpoint.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: phd2IsSelected
                                ? colors.success
                                : colors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_lastResult != null &&
                    _testedEndpoint == _currentEndpoint) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        _lastResult == true
                            ? LucideIcons.checkCircle2
                            : NightshadeIcons.warning,
                        size: 16,
                        color:
                            _lastResult == true ? colors.success : colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastResult == true
                              ? 'PHD2 reachable at $_testedEndpoint.'
                              : (_lastError ?? 'Connection failed.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _lastResult == true
                                ? colors.success
                                : colors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Divider(color: colors.border, thickness: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'or pick a native guider',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: colors.border, thickness: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Native guider picker (camera-tracked etc.).
          //
          // The height has to clear the picker's own chrome (heading, subtitle,
          // Scan-again row, per-backend status row and skip footnote) plus its
          // empty state. At 240 it did not: the list slot collapsed to almost
          // nothing and the "No devices found" empty state painted straight
          // through the footnote beneath it. The step scrolls, so the taller box
          // costs reachability nothing.
          SizedBox(
            height: 340,
            child: OnboardingDevicePickerBody(
              title: 'Native guiders',
              subtitle:
                  'Cameras that publish a guider interface — usually only relevant for OAGs with dedicated drivers.',
              icon: NightshadeIcons.visible,
              deviceType: DeviceType.guider,
              selectedDeviceId: draft.guiderId,
              selectedDeviceName: draft.guiderName,
              allowSkip: true,
              onSelected: (device) => notifier.setGuider(
                id: device.activeDeviceId,
                name: device.displayName,
              ),
              onCleared: () => notifier.setGuider(id: ''),
            ),
          ),
        ],
      ),
    );
  }
}
