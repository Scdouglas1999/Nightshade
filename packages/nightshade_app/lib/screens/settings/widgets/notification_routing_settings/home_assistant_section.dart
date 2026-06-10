part of '../notification_routing_settings.dart';

// Home Assistant MQTT auto-discovery settings. Lives next to the MQTT
// broker section because it reuses that broker connection — discovery
// publishes retained HA config/state topics over the same host.

class _HomeAssistantSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _HomeAssistantSection({required this.isMobile});

  @override
  ConsumerState<_HomeAssistantSection> createState() =>
      _HomeAssistantSectionState();
}

class _HomeAssistantSectionState extends ConsumerState<_HomeAssistantSection> {
  final _deviceName = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _save(HomeAssistantDiscoveryConfig Function(
          HomeAssistantDiscoveryConfig) change) async {
    final current = ref.read(homeAssistantConfigProvider).valueOrNull ??
        const HomeAssistantDiscoveryConfig();
    await ref
        .read(homeAssistantConfigProvider.notifier)
        .save(change(current));
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(homeAssistantConfigProvider);
    final mqttCfg = ref.watch(mqttTransportConfigProvider).valueOrNull;
    final brokerConfigured = (mqttCfg?.host ?? '').isNotEmpty;

    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const NightshadeInlineBanner(
        message: 'Could not load Home Assistant routing configuration.',
        severity: NightshadeAlertSeverity.error,
      ),
      data: (cfg) {
        if (!_initialized) {
          _deviceName.text = cfg.deviceName;
          _initialized = true;
        }
        return SettingsSection(
          title: 'Home Assistant',
          children: [
            SettingRow(
              icon: LucideIcons.home,
              title: 'Publish to Home Assistant',
              subtitle: brokerConfigured
                  ? 'Auto-discover this observatory as a Home Assistant '
                      'device (uses the MQTT broker above)'
                  : 'Configure the MQTT broker above first',
              trailing: SettingsSwitch(
                value: cfg.enabled,
                onChanged: (v) {
                  if (v && !brokerConfigured) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Set an MQTT broker host above before enabling '
                              'Home Assistant discovery')),
                    );
                    return;
                  }
                  _save((c) => c.copyWith(enabled: v));
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.tag,
              title: 'Device name',
              subtitle: 'Blank = "Nightshade Observatory <profile>"',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _deviceName,
                hint: 'Nightshade Observatory',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.shieldAlert,
              title: 'Allow control from Home Assistant',
              subtitle:
                  'Lets HA pause/resume and abort the running sequence. '
                  'Off = read-only sensors.',
              trailing: SettingsSwitch(
                value: cfg.allowControl,
                onChanged: (v) => _save((c) => c.copyWith(allowControl: v)),
              ),
            ),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save Home Assistant config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  await _save(
                      (c) => c.copyWith(deviceName: _deviceName.text.trim()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Home Assistant config saved')),
                  );
                },
              ),
              isLast: true,
            ),
          ],
        );
      },
    );
  }
}
