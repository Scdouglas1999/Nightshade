import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// INDI Server Configuration Dialog (Linux/macOS)
class IndiServerDialog extends ConsumerStatefulWidget {
  const IndiServerDialog({super.key});

  @override
  ConsumerState<IndiServerDialog> createState() => _IndiServerDialogState();
}

class _IndiServerDialogState extends ConsumerState<IndiServerDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  // Independent busy flags so a probe and a save can each guard against
  // double-taps and against each other without either being mistaken for the
  // other's spinner.
  bool _isTesting = false;
  bool _isSaving = false;

  // Tracks whether the async settings hydration has completed and whether the
  // user has typed into each field. Late hydration must never clobber an edit
  // the operator made while the load was still in flight.
  bool _hostEdited = false;
  bool _portEdited = false;

  String? _statusMessage;
  bool? _statusSuccess;
  String? _hostError;
  String? _portError;

  @override
  void initState() {
    super.initState();
    // Initialize with default values; persisted settings hydrate in below.
    _hostController = TextEditingController(text: 'localhost');
    _portController = TextEditingController(text: '7624');

    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromSettings());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  /// Load the persisted INDI address, tolerating a failing settings source.
  Future<void> _hydrateFromSettings() async {
    try {
      final settings = await ref.read(appSettingsProvider.future);
      if (!mounted) return;
      setState(() {
        // Only adopt persisted values for fields the operator has not touched,
        // so a slow load never overwrites what they typed in the meantime.
        if (!_hostEdited) {
          _hostController.text = settings.indiServerHost;
        }
        if (!_portEdited) {
          _portController.text = settings.indiServerPort.toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusSuccess = false;
        _statusMessage = 'Could not load saved INDI settings: $e';
      });
    }
  }

  /// Validate host and port, surfacing per-field errors. Returns the parsed
  /// values only when both are valid — never silently coerces a malformed port
  /// to a default.
  ({String host, int port})? _validatedInputs() {
    final host = _hostController.text.trim();
    final portRaw = _portController.text.trim();

    String? hostError;
    String? portError;

    if (host.isEmpty) {
      hostError = 'Enter a host name or IP address.';
    }
    final port = int.tryParse(portRaw);
    if (port == null) {
      portError = 'Port must be a whole number.';
    } else if (port < 1 || port > 65535) {
      portError = 'Port must be between 1 and 65535.';
    }

    setState(() {
      _hostError = hostError;
      _portError = portError;
    });

    if (hostError != null || portError != null || port == null) {
      return null;
    }
    return (host: host, port: port);
  }

  Future<void> _testConnection() async {
    if (_isTesting || _isSaving) return;
    final inputs = _validatedInputs();
    if (inputs == null) return;

    setState(() {
      _isTesting = true;
      _statusMessage = null;
      _statusSuccess = null;
    });

    try {
      // Real, awaited discovery probe against the entered address.
      final deviceService = ref.read(deviceServiceProvider);
      final devices =
          await deviceService.discoverIndiAtAddress(inputs.host, inputs.port);

      if (!mounted) return;
      setState(() {
        _isTesting = false;
        final n = devices.length;
        // An EMPTY result is not evidence of a connection. The FFI backend
        // catches a refused/timed-out INDI socket and returns an empty device
        // list (ffi_backend/discovery_camera_operations.dart
        // `_discoverAddressDevices`), so "connected to a server with no drivers
        // loaded" and "nothing is listening on that address at all" arrive here
        // as the exact same value. Reporting the first as a green tick sent an
        // operator who had typo'd their Raspberry Pi's address off to hunt the
        // wrong problem all night. Only a device we actually enumerated proves
        // the server answered.
        _statusSuccess = n > 0;
        _statusMessage = n > 0
            ? 'Connected. Found $n device${n == 1 ? '' : 's'}.'
            : 'No INDI devices at ${inputs.host}:${inputs.port}. If '
                'indiserver is running there, it has no drivers loaded — '
                'otherwise check the host and port.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _statusSuccess = false;
        // Name the endpoint that was actually probed, matching the PHD2 test's
        // wording on the guider step.
        _statusMessage = 'No response on ${inputs.host}:${inputs.port}. $e';
      });
    }
  }

  /// Persist the INDI server address. This only stores configuration — it does
  /// not open a live INDI session (startup discovery consults it later) — so
  /// the action is labelled "Save", not "Connect".
  Future<void> _save() async {
    if (_isSaving || _isTesting) return;
    final inputs = _validatedInputs();
    if (inputs == null) return;

    setState(() {
      _isSaving = true;
      _statusMessage = null;
      _statusSuccess = null;
    });

    try {
      final settingsNotifier = ref.read(appSettingsProvider.notifier);
      await settingsNotifier.setIndiServerHost(inputs.host);
      await settingsNotifier.setIndiServerPort(inputs.port);
    } catch (e) {
      if (!mounted) return;
      // Keep the dialog open so the operator can retry.
      setState(() {
        _isSaving = false;
        _statusSuccess = false;
        _statusMessage = 'Could not save INDI settings: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, {
      'host': inputs.host,
      'port': inputs.port,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final dialog = AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(NightshadeIcons.power, color: colors.primary, size: 24),
          const SizedBox(width: 12),
          Text(
            'INDI Server Configuration',
            style: TextStyle(color: colors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogMaxWidth(context, 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info about INDI
            Container(
              padding: const EdgeInsets.all(12),
              decoration: NightshadeDecorations.emphasisSurface(
                colors.primary,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(NightshadeIcons.info, color: colors.primary, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'INDI (Instrument Neutral Distributed Interface) provides '
                      'cross-platform access to astronomical equipment on Linux and macOS.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Host input
            TextField(
              key: const ValueKey('indi-host-field'),
              controller: _hostController,
              style: TextStyle(color: colors.textPrimary),
              onChanged: (_) {
                _hostEdited = true;
                if (_hostError != null) setState(() => _hostError = null);
              },
              decoration: InputDecoration(
                labelText: 'INDI Server Host',
                labelStyle: TextStyle(color: colors.textMuted),
                hintText: 'localhost or IP address',
                hintStyle:
                    TextStyle(color: colors.textMuted.withValues(alpha: 0.5)),
                errorText: _hostError,
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Port input
            TextField(
              key: const ValueKey('indi-port-field'),
              controller: _portController,
              style: TextStyle(color: colors.textPrimary),
              keyboardType: TextInputType.number,
              onChanged: (_) {
                _portEdited = true;
                if (_portError != null) setState(() => _portError = null);
              },
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: TextStyle(color: colors.textMuted),
                hintText: '7624 (default)',
                hintStyle:
                    TextStyle(color: colors.textMuted.withValues(alpha: 0.5)),
                errorText: _portError,
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test connection button
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: (_isTesting || _isSaving) ? null : _testConnection,
                icon: NightshadeIcons.refresh,
                label: _isTesting ? 'Testing...' : 'Test Connection',
                variant: ButtonVariant.outline,
                isLoading: _isTesting,
              ),
            ),

            // Status message
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: NightshadeDecorations.emphasisSurface(
                  (_statusSuccess ?? false) ? colors.success : colors.error,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
                child: Row(
                  children: [
                    Icon(
                      (_statusSuccess ?? false)
                          ? NightshadeIcons.success
                          : NightshadeIcons.error,
                      size: 16,
                      color: (_statusSuccess ?? false)
                          ? colors.success
                          : colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed:
              (_isSaving || _isTesting) ? null : () => Navigator.pop(context),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: (_isSaving || _isTesting) ? null : _save,
          label: _isSaving ? 'Saving...' : 'Save',
          variant: ButtonVariant.primary,
          isLoading: _isSaving,
        ),
      ],
    );
    return PopScope(canPop: !_isTesting && !_isSaving, child: dialog);
  }
}
