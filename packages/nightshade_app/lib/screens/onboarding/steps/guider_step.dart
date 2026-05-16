import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'device_picker_step.dart';

/// Guider step.
///
/// Most users guide with PHD2 over its TCP socket (default 4400), so
/// alongside the device picker we expose a dedicated host:port field
/// with a "Test connection" button that runs [bridge.checkPhd2Running]
/// — a real socket probe, not a stub. Native guiders (camera-tracked
/// stars without PHD2) still show up in the picker.
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

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _lastResult = null;
      _lastError = null;
    });
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
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
      final running = await bridge.checkPhd2Running(host: host, port: port);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _lastResult = running;
        _lastError = running
            ? null
            : 'No response on $host:$port. Is PHD2 running with "Enable Server" turned on?';
      });
      if (running) {
        // Persist the PHD2 endpoint in the draft using the phd2: prefix
        // so it can be wired to backend.connectGuider later.
        await ref.read(onboardingDraftProvider.notifier).setGuider(
              id: 'phd2:$host:$port',
              name: 'PHD2 ($host:$port)',
            );
      }
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    return Column(
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.crosshair,
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
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Host',
                        labelStyle: TextStyle(color: colors.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
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
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Port',
                        labelStyle: TextStyle(color: colors.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.primary),
                        ),
                        filled: true,
                        fillColor: colors.background,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NightshadeButton(
                    icon: LucideIcons.zap,
                    label: _testing ? 'Testing…' : 'Test',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: _testing ? null : _testConnection,
                  ),
                ],
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _lastResult == true
                          ? LucideIcons.checkCircle2
                          : LucideIcons.alertTriangle,
                      size: 16,
                      color: _lastResult == true
                          ? colors.success
                          : colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastResult == true
                            ? 'PHD2 reachable. Selection saved.'
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

        // Native guider picker (camera-tracked etc.)
        SizedBox(
          height: 240,
          child: OnboardingDevicePickerBody(
            title: 'Native guiders',
            subtitle:
                'Cameras that publish a guider interface — usually only relevant for OAGs with dedicated drivers.',
            icon: LucideIcons.eye,
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
    );
  }
}
