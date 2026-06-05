// Wave 8 — Conversational sequence builder: AI Assistant settings panel.
//
// Lives in Settings → AI Assistant. Lets the user:
//   * Pick which LLM provider is active (OpenAI-compatible / Anthropic /
//     Ollama).
//   * For each provider: edit base URL, model name, API key.
//   * Tap "Test connection" to verify the credentials.
//   * Read a privacy disclosure so they understand what context the
//     conversational dialog ships off-device.
//
// API keys go through [SecretsStore] via [LlmSettingsService] (never
// plaintext in app_settings). The non-secret bits round-trip through
// the existing app_settings table as JSON blobs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

class AiAssistantSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const AiAssistantSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<AiAssistantSettings> createState() =>
      _AiAssistantSettingsState();
}

class _AiAssistantSettingsState extends ConsumerState<AiAssistantSettings> {
  /// Per-kind in-progress edits. Hydrated from the persisted blob on
  /// first build; the user clicks Save to commit (we don't auto-save
  /// every keystroke because that would write to the OS keyring on
  /// every key, and the textfield for the API key is hidden by default).
  final Map<LlmProviderKind, _ProviderEditState> _edits = {};
  LlmProviderKind _selectedKind = LlmProviderKind.openAiCompatible;

  /// Whether we've already seeded [_edits] from the persisted record.
  /// Avoids stomping on the user's mid-edit fields if the underlying
  /// StreamProvider emits a refresh while they're typing.
  bool _hydrated = false;

  /// Connection-test result per kind — surfaces the inline result row.
  final Map<LlmProviderKind, LlmConnectionTestResult> _testResults = {};
  final Map<LlmProviderKind, bool> _testRunning = {};

  /// Whether the API-key field is visible (default hidden, like a
  /// password field).
  final Map<LlmProviderKind, bool> _keyVisible = {};

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = widget.isMobile;
    final settingsAsync = ref.watch(llmAssistantSettingsProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(isMobile: isMobile),
      error: (err, _) => SettingsErrorState(
        isMobile: isMobile,
        error: err,
        onRetry: () => ref.invalidate(llmAssistantSettingsProvider),
      ),
      data: (settings) {
        _hydrateIfNeeded(settings);
        return SettingsPage(
          title: 'AI Assistant',
          description:
              'Configure a Large Language Model to drive the conversational '
              'sequence builder. Pick a provider, point it at an endpoint, '
              'and the sparkle button in the sequencer becomes available.',
          isMobile: isMobile,
          hideHeader: isMobile,
          children: [
            _buildActiveProviderSection(colors, isMobile, settings),
            const SizedBox(height: 16),
            _buildProviderConfigSection(colors, isMobile),
            const SizedBox(height: 16),
            _buildPrivacySection(colors, isMobile),
          ],
        );
      },
    );
  }

  void _hydrateIfNeeded(LlmAssistantSettings settings) {
    if (_hydrated) return;
    _hydrated = true;
    _selectedKind = settings.activeKind;
    for (final kind in LlmProviderKind.values) {
      final base = settings.perKind[kind] ?? defaultConfigFor(kind);
      _edits[kind] = _ProviderEditState(
        baseUrl: base.baseUrl,
        model: base.model,
        anthropicVersion: base.anthropicVersion,
        maxTokens: base.maxTokens,
        temperature: base.temperature,
        timeoutSecs: base.requestTimeout.inSeconds,
        apiKey: '',
        apiKeyLoaded: false,
      );
      _keyVisible[kind] = false;
    }
    // Lazy-load the API keys so the field shows the "••••••" placeholder
    // on first paint, then upgrades to the real value when the user
    // taps the eye icon.
    _loadKeyForKind(_selectedKind);
  }

  Future<void> _loadKeyForKind(LlmProviderKind kind) async {
    final service = ref.read(llmSettingsServiceProvider);
    final key = await service.readApiKey(kind);
    if (!mounted) return;
    setState(() {
      final state = _edits[kind];
      if (state != null) {
        state.apiKey = key;
        state.apiKeyLoaded = true;
      }
    });
  }

  // -------------------------------------------------------------------------
  // §1 Active provider selector
  // -------------------------------------------------------------------------

  Widget _buildActiveProviderSection(
    NightshadeColors colors,
    bool isMobile,
    LlmAssistantSettings settings,
  ) {
    return SettingsSection(
      title: 'Active Provider',
      isMobile: isMobile,
      children: [
        for (final kind in LlmProviderKind.values)
          SettingRow(
            icon: kind == LlmProviderKind.ollama
                ? LucideIcons.cpu
                : kind == LlmProviderKind.anthropic
                    ? LucideIcons.sparkles
                    : LucideIcons.bot,
            title: kind.label,
            subtitle: kind == _selectedKind
                ? 'Currently selected'
                : 'Tap to use this provider',
            trailing: Radio<LlmProviderKind>(
              value: kind,
              groupValue: _selectedKind,
              onChanged: (next) async {
                if (next == null) return;
                setState(() => _selectedKind = next);
                await ref
                    .read(llmSettingsServiceProvider)
                    .setActiveKind(next);
                if (!_edits[next]!.apiKeyLoaded) {
                  await _loadKeyForKind(next);
                }
              },
            ),
            isMobile: isMobile,
            isLast: kind == LlmProviderKind.values.last,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // §2 Per-provider config form
  // -------------------------------------------------------------------------

  Widget _buildProviderConfigSection(
    NightshadeColors colors,
    bool isMobile,
  ) {
    final state = _edits[_selectedKind];
    if (state == null) return const SizedBox.shrink();
    final testResult = _testResults[_selectedKind];
    final testRunning = _testRunning[_selectedKind] ?? false;

    return SettingsSection(
      title: '${_selectedKind.label} — configuration',
      isMobile: isMobile,
      children: [
        _LabeledTextField(
          isMobile: isMobile,
          icon: LucideIcons.link,
          label: 'Base URL',
          hint: defaultConfigFor(_selectedKind).baseUrl,
          value: state.baseUrl,
          onChanged: (v) => setState(() => state.baseUrl = v),
        ),
        _LabeledTextField(
          isMobile: isMobile,
          icon: LucideIcons.cpu,
          label: 'Model',
          hint: defaultConfigFor(_selectedKind).model,
          value: state.model,
          onChanged: (v) => setState(() => state.model = v),
        ),
        _LabeledTextField(
          isMobile: isMobile,
          icon: LucideIcons.key,
          label: _selectedKind == LlmProviderKind.ollama
              ? 'API key (optional — only if your Ollama is behind auth)'
              : 'API key',
          hint: state.apiKeyLoaded
              ? (state.apiKey.isEmpty ? 'No key stored' : '••••••••')
              : 'Loading…',
          value: state.apiKey,
          obscure: !(_keyVisible[_selectedKind] ?? false),
          trailingIcon: (_keyVisible[_selectedKind] ?? false)
              ? LucideIcons.eyeOff
              : LucideIcons.eye,
          onTrailingTap: () => setState(() {
            _keyVisible[_selectedKind] =
                !(_keyVisible[_selectedKind] ?? false);
          }),
          onChanged: (v) => setState(() => state.apiKey = v),
        ),
        _LabeledNumericField(
          isMobile: isMobile,
          icon: LucideIcons.gauge,
          label: 'Max tokens',
          value: state.maxTokens.toDouble(),
          min: 256,
          max: 32768,
          step: 256,
          onChanged: (v) => setState(() => state.maxTokens = v.toInt()),
          format: (v) => v.toInt().toString(),
        ),
        _LabeledNumericField(
          isMobile: isMobile,
          icon: LucideIcons.thermometer,
          label: 'Temperature',
          value: state.temperature,
          min: 0.0,
          max: 1.5,
          step: 0.05,
          onChanged: (v) => setState(() => state.temperature = v),
          format: (v) => v.toStringAsFixed(2),
        ),
        _LabeledNumericField(
          isMobile: isMobile,
          icon: LucideIcons.timer,
          label: 'Request timeout (seconds)',
          value: state.timeoutSecs.toDouble(),
          min: 15,
          max: 600,
          step: 5,
          onChanged: (v) => setState(() => state.timeoutSecs = v.toInt()),
          format: (v) => v.toInt().toString(),
        ),
        if (_selectedKind == LlmProviderKind.anthropic)
          _LabeledTextField(
            isMobile: isMobile,
            icon: LucideIcons.tag,
            label: 'Anthropic API version',
            hint: '2023-06-01',
            value: state.anthropicVersion,
            onChanged: (v) => setState(() => state.anthropicVersion = v),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _save(state),
                icon: const Icon(LucideIcons.save, size: 14),
                label: const Text('Save'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: testRunning ? null : () => _testConnection(state),
                icon: testRunning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.zap, size: 14),
                label: const Text('Test connection'),
              ),
              const Spacer(),
              if (testResult != null)
                _TestResultBadge(result: testResult),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save(_ProviderEditState state) async {
    final service = ref.read(llmSettingsServiceProvider);
    try {
      await service.setProviderConfig(
        _selectedKind,
        LlmProviderConfig(
          baseUrl: state.baseUrl.trim(),
          model: state.model.trim(),
          anthropicVersion: state.anthropicVersion.trim(),
          maxTokens: state.maxTokens,
          temperature: state.temperature,
          requestTimeout: Duration(seconds: state.timeoutSecs),
        ),
      );
      await service.writeApiKey(_selectedKind, state.apiKey);
      if (!mounted) return;
      context.showSuccessSnackBar('AI Assistant settings saved.');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to save AI settings: $e');
    }
  }

  Future<void> _testConnection(_ProviderEditState state) async {
    final factory = ref.read(llmProviderFactoryProvider);
    setState(() => _testRunning[_selectedKind] = true);
    final provider = factory.create(
      _selectedKind,
      LlmProviderConfig(
        baseUrl: state.baseUrl.trim(),
        model: state.model.trim(),
        apiKey: state.apiKey,
        anthropicVersion: state.anthropicVersion.trim(),
        maxTokens: state.maxTokens,
        temperature: state.temperature,
        requestTimeout: Duration(seconds: state.timeoutSecs),
      ),
    );
    try {
      if (!provider.isConfigured) {
        setState(() {
          _testResults[_selectedKind] = const LlmConnectionTestResult(
            success: false,
            message:
                'Configuration incomplete — at least base URL + model are required.',
            roundTripMs: 0,
          );
        });
        return;
      }
      final result = await provider.testConnection();
      if (!mounted) return;
      setState(() {
        _testResults[_selectedKind] = result;
      });
    } finally {
      provider.close();
      if (mounted) {
        setState(() => _testRunning[_selectedKind] = false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // §3 Privacy disclosure
  // -------------------------------------------------------------------------

  Widget _buildPrivacySection(NightshadeColors colors, bool isMobile) {
    return SettingsSection(
      title: 'Privacy',
      isMobile: isMobile,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.shield, size: 16, color: colors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'When you use the conversational builder, the LLM provider '
                  'you have configured sees: your active equipment profile '
                  '(camera/mount/filters), your observer location '
                  '(latitude/longitude), the candidate target list you opened '
                  'the dialog with, and your free-text prompt.\n\n'
                  'Local providers (Ollama) keep this data entirely on your '
                  'machine. Cloud providers (OpenAI, Anthropic) transmit it '
                  'over TLS to their servers and may retain it according to '
                  'their data-retention policy.\n\n'
                  'Nightshade never sends data automatically — every build '
                  'requires an explicit Submit click.',
                  style: TextStyle(
                    fontSize: isMobile ? NightshadeTypography.fontSize11 : NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderEditState {
  String baseUrl;
  String model;
  String anthropicVersion;
  int maxTokens;
  double temperature;
  int timeoutSecs;
  String apiKey;
  bool apiKeyLoaded;

  _ProviderEditState({
    required this.baseUrl,
    required this.model,
    required this.anthropicVersion,
    required this.maxTokens,
    required this.temperature,
    required this.timeoutSecs,
    required this.apiKey,
    required this.apiKeyLoaded,
  });
}

class _LabeledTextField extends StatefulWidget {
  final bool isMobile;
  final IconData icon;
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  const _LabeledTextField({
    required this.isMobile,
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.obscure = false,
    this.trailingIcon,
    this.onTrailingTap,
  });

  @override
  State<_LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<_LabeledTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_LabeledTextField old) {
    super.didUpdateWidget(old);
    // When the parent state replaces the value externally (e.g. lazy
    // load of the API key), sync our controller. Avoid resetting if
    // the user is mid-edit (the controller text matches the user's
    // last keystroke, not the prop).
    if (widget.value != _controller.text && !_controller.text.isNotEmpty) {
      _controller.text = widget.value;
    } else if (widget.value != old.value &&
        widget.value != _controller.text &&
        _controller.text == old.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: widget.icon,
      title: widget.label,
      trailing: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = settingsTrailingIsNarrow(
            context,
            isMobile: widget.isMobile,
            constraints: constraints,
            fixedWidth: 320,
          );
          final fieldWidth = narrow
              ? null
              : dialogMaxWidth(context, widget.isMobile ? 180 : 320);
          return SizedBox(
            width: fieldWidth,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                controller: _controller,
                obscureText: widget.obscure,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: NightshadeColors.of(context).textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                  ),
                ),
                onChanged: widget.onChanged,
              ),
            ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(widget.trailingIcon, size: 14),
                    onPressed: widget.onTrailingTap,
                    tooltip: 'Toggle visibility',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          );
        },
      ),
      isMobile: widget.isMobile,
      stackOnMobile: true,
    );
  }
}

class _LabeledNumericField extends StatelessWidget {
  final bool isMobile;
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  const _LabeledNumericField({
    required this.isMobile,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return SettingRow(
      icon: icon,
      title: label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.minus, size: 14),
            onPressed:
                value <= min ? null : () => onChanged((value - step).clamp(min, max)),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 64,
            child: Text(
              format(value),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus, size: 14),
            onPressed:
                value >= max ? null : () => onChanged((value + step).clamp(min, max)),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      isMobile: isMobile,
    );
  }
}

class _TestResultBadge extends StatelessWidget {
  final LlmConnectionTestResult result;

  const _TestResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final color = result.success ? colors.success : colors.error;
    final icon = result.success ? LucideIcons.checkCircle : LucideIcons.xCircle;
    return Tooltip(
      message: '${result.message}\nRound trip: ${result.roundTripMs}ms',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: NightshadeDecorations.statusChip(
          color,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              result.success
                  ? 'OK (${result.roundTripMs}ms)'
                  : 'Failed (${result.roundTripMs}ms)',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
