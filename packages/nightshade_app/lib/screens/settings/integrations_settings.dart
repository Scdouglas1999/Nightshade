// Integrations settings page.
//
// Replaces the orphaned `plugins_screen.dart` with a design-system-compliant
// page that surfaces the four bundled integrations (Discord, Pushover, Home
// Assistant, Weather Logger) and cross-links to the notification router (the
// honest answer to "Discord fires on observatory events" — that path lives in
// Settings > Notification Routing).
//
// Wiring (built on the C3 / C4 surfaces, never reaching into plugin internals):
//   * `pluginRegistrationProvider` (C3) — ensures the bundled plugins are
//     registered into the host before we render. Read (not just watched) so a
//     registration failure surfaces as an error state rather than an empty page.
//   * `pluginHostProvider.pluginInfo` — the per-plugin name/description/enabled/
//     error snapshot rendered as rows.
//   * `pluginEnablementProvider` (C4) — the persisted enabled-set; toggling a
//     row calls `setEnabled(id, value)`, which drives the live host
//     (`PluginHost.setPluginEnabled`, running onEnable/onDisable and
//     registering/unregistering the plugin's sequence nodes) BEFORE persisting
//     the choice, so the running session and the saved state never diverge —
//     not this session, and not after a restart (the settings-backed
//     enablement store the entry point installs replays the same choice into
//     the registration pipeline at next launch).
//   * `pluginLastFiredProvider` (C3) — "last fired <relative time>" per plugin.
//
// Per-plugin configuration is written through the plugin's own public API
// (`configureCredentials` / `configureConnection`) or, for Discord (whose
// real credential is a per-NODE webhook URL), through the live plugin
// `PluginContext.storage` so the value is available as a default + test target.
// Every failure surfaces via [ErrorDialog]; nothing is swallowed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// http is a transitive dependency (via nightshade_plugins / nightshade_core).
// It is used only for the Discord test-send client-factory type, mirroring the
// plugin's own `http.Client Function()` seam.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';
// C3's registration provider is the single seam that loads the bundled
// plugins into the host. It is intentionally not surfaced through the package
// barrel (it is internal wiring), so — exactly like C4's enablement provider —
// we import it by path. The implementation_imports lint is suppressed because
// there is no barrel alternative for this app-layer wiring.
// ignore: implementation_imports
import 'package:nightshade_plugins/src/plugin_registration.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// C4 (plugin enablement persistence) lives in nightshade_core but is not
// surfaced through that package's barrel, so — like C4 itself imports C3 by
// path — we import the provider by path. The implementation_imports lint is
// suppressed deliberately; there is no barrel alternative.
// ignore: implementation_imports
import 'package:nightshade_core/src/providers/plugin_enablement_provider.dart'
    show pluginEnablementProvider;

import 'widgets/settings_widgets.dart';

/// Plugin-storage key holding the Discord plugin's default / test webhook URL.
///
/// The Discord plugin's real credential is per-NODE (each sequence node carries
/// its own webhook). This single key is a convenience: a default URL the
/// "Test send" button targets and that node editors can pre-fill. It lives in
/// the plugin's own [PluginContext.storage] so it travels with the plugin's
/// other settings.
const String kDiscordDefaultWebhookStorageKey = 'discord.defaultWebhookUrl';

/// Stable plugin ids for the three configurable bundled integrations.
const String kDiscordPluginId = 'com.nightshade.examples.discord_webhook';
const String kPushoverPluginId = 'com.nightshade.examples.pushover';
const String kHomeAssistantPluginId = 'com.nightshade.examples.home_assistant';

/// Integrations / Plugins settings page.
///
/// Renders the notification-routing cross-link and the bundled-plugin list.
/// Construct the standard way; tests inject [testHttpClientFactory] so the
/// Discord "Test send" exercises the real node execute path against a mocked
/// HTTP client without hitting the network.
class IntegrationsSettings extends ConsumerWidget {
  const IntegrationsSettings({
    super.key,
    this.isMobile = false,
    this.testHttpClientFactory,
  });

  final bool isMobile;

  /// Optional HTTP client factory used only by the Discord "Test send" path.
  /// Null in production (a real [http.Client] is used). Tests pass a factory
  /// returning a mock client so the test-send asserts success/failure handling
  /// without network access.
  final http.Client Function()? testHttpClientFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure the bundled plugins are registered before we read host state.
    // A registration failure must NOT silently render an empty list — surface
    // it as an error state (errors are a feature).
    final registration = ref.watch(pluginRegistrationProvider);

    return registration.when(
      loading: () => SettingsLoadingState(
        isMobile: isMobile,
        message: 'Loading integrations…',
      ),
      error: (error, _) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(pluginRegistrationProvider),
      ),
      data: (_) => _IntegrationsBody(
        isMobile: isMobile,
        testHttpClientFactory: testHttpClientFactory,
      ),
    );
  }
}

class _IntegrationsBody extends ConsumerWidget {
  const _IntegrationsBody({
    required this.isMobile,
    required this.testHttpClientFactory,
  });

  final bool isMobile;
  final http.Client Function()? testHttpClientFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginHost = ref.watch(pluginHostProvider);
    final plugins = pluginHost.pluginInfo;
    final enabledSet = ref.watch(pluginEnablementProvider);
    final lastFired = ref.watch(pluginLastFiredProvider);

    return SettingsPage(
      title: 'Integrations',
      description:
          'Connect Nightshade to outside services. Route observatory events to '
          'chat and push, and manage the bundled plugins that add sequence '
          'nodes for Discord, Pushover, and Home Assistant.',
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        _NotificationCrossLinkSection(isMobile: isMobile),
        _PluginsSection(
          isMobile: isMobile,
          plugins: plugins,
          enabledSet: enabledSet,
          lastFired: lastFired,
          testHttpClientFactory: testHttpClientFactory,
        ),
      ],
    );
  }
}

/// Top section: the honest "Discord fires on events" answer — a cross-link to
/// the notification router, which owns the event→transport routing.
class _NotificationCrossLinkSection extends StatelessWidget {
  const _NotificationCrossLinkSection({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Notifications & events',
      isMobile: isMobile,
      children: [
        SettingRow(
          icon: LucideIcons.bellRing,
          title: 'Post to Discord / Pushover on observatory events',
          subtitle:
              'Route sequence-complete, safety, and guiding-lost alerts to '
              'Discord, Pushover, email…',
          isMobile: isMobile,
          isLast: true,
          stackOnMobile: true,
          trailing: NightshadeButton(
            label: 'Open Notification Routing',
            icon: LucideIcons.arrowUpRight,
            variant: ButtonVariant.outline,
            size: isMobile ? ButtonSize.small : ButtonSize.medium,
            onPressed: () =>
                context.go('/settings?section=notification-routing'),
          ),
        ),
      ],
    );
  }
}

/// The bundled-plugin list section.
class _PluginsSection extends ConsumerWidget {
  const _PluginsSection({
    required this.isMobile,
    required this.plugins,
    required this.enabledSet,
    required this.lastFired,
    required this.testHttpClientFactory,
  });

  final bool isMobile;
  final List<PluginInfo> plugins;
  final AsyncValue<Set<String>> enabledSet;
  final PluginLastFired lastFired;
  final http.Client Function()? testHttpClientFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plugins.isEmpty) {
      return EmptyState(
        icon: LucideIcons.puzzle,
        title: 'No plugins loaded',
        body: 'Bundled integrations register at startup. If this list is '
            'empty, the plugin host failed to initialize.',
        action: NightshadeButton(
          label: 'Retry',
          icon: LucideIcons.refreshCw,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => ref.invalidate(pluginRegistrationProvider),
        ),
      );
    }

    return SettingsSection(
      title: 'Plugins',
      isMobile: isMobile,
      children: [
        for (var i = 0; i < plugins.length; i++)
          _PluginRow(
            plugin: plugins[i],
            isMobile: isMobile,
            isLast: i == plugins.length - 1,
            enabledSet: enabledSet,
            lastFiredAt: lastFired[plugins[i].id],
            testHttpClientFactory: testHttpClientFactory,
          ),
      ],
    );
  }
}

/// Whether [pluginId] has a configuration dialog.
bool _pluginIsConfigurable(String pluginId) {
  return pluginId == kDiscordPluginId ||
      pluginId == kPushoverPluginId ||
      pluginId == kHomeAssistantPluginId;
}

class _PluginRow extends ConsumerWidget {
  const _PluginRow({
    required this.plugin,
    required this.isMobile,
    required this.isLast,
    required this.enabledSet,
    required this.lastFiredAt,
    required this.testHttpClientFactory,
  });

  final PluginInfo plugin;
  final bool isMobile;
  final bool isLast;
  final AsyncValue<Set<String>> enabledSet;
  final DateTime? lastFiredAt;
  final http.Client Function()? testHttpClientFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final hasError = plugin.error != null;

    // The enabled-set is the authoritative persisted truth (C4). While it is
    // loading we fall back to the host's own snapshot so the switch is never
    // shown in a meaningless intermediate state.
    final enabled =
        enabledSet.valueOrNull?.contains(plugin.id) ?? plugin.enabled;

    return SettingRow(
      icon: hasError ? LucideIcons.alertTriangle : LucideIcons.puzzle,
      iconColor: hasError ? colors.error : null,
      title: plugin.name,
      isMobile: isMobile,
      isLast: isLast,
      stackOnMobile: true,
      // The plugin description is the row subtitle; the status pill (enabled /
      // error / last-fired), the optional Configure button, and the switch all
      // live in the trailing cluster.
      subtitle: plugin.description,
      trailing: _PluginRowTrailing(
        plugin: plugin,
        enabled: enabled,
        enablementLoading: enabledSet.isLoading,
        hasError: hasError,
        lastFiredAt: lastFiredAt,
        testHttpClientFactory: testHttpClientFactory,
      ),
    );
  }
}

/// The trailing cluster for a plugin row: a status pill (enabled/error/last
/// fired), an optional "Configure" button, and the enable/disable switch.
class _PluginRowTrailing extends ConsumerWidget {
  const _PluginRowTrailing({
    required this.plugin,
    required this.enabled,
    required this.enablementLoading,
    required this.hasError,
    required this.lastFiredAt,
    required this.testHttpClientFactory,
  });

  final PluginInfo plugin;
  final bool enabled;
  final bool enablementLoading;
  final bool hasError;
  final DateTime? lastFiredAt;
  final http.Client Function()? testHttpClientFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configurable = _pluginIsConfigurable(plugin.id);

    final pill = _PluginStatusPill(
      enabled: enabled,
      hasError: hasError,
      error: plugin.error,
      lastFiredAt: lastFiredAt,
    );

    final configureButton = configurable
        ? NightshadeButton(
            label: 'Configure',
            icon: LucideIcons.settings,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => _openConfigureDialog(context, ref),
          )
        : null;

    final toggle = _PluginEnableSwitch(
      pluginId: plugin.id,
      value: enabled,
      enabled: !enablementLoading,
    );

    // Wrap (not Row) so the pill + Configure button + switch reflow onto a
    // second line on narrow widths instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: NightshadeTokens.spaceSm,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        pill,
        if (configureButton != null) configureButton,
        toggle,
      ],
    );
  }

  Future<void> _openConfigureDialog(BuildContext context, WidgetRef ref) async {
    final host = ref.read(pluginHostProvider);
    final instance = host.getPlugin(plugin.id);
    final pluginContext = host.contextFor(plugin.id);
    if (instance == null || pluginContext == null) {
      await ErrorDialog.show(
        context,
        title: 'Plugin unavailable',
        message:
            'The "${plugin.name}" plugin is not currently loaded, so it cannot '
            'be configured.',
        technicalDetails:
            'No live instance/context for ${plugin.id} in the plugin host.',
      );
      return;
    }

    switch (plugin.id) {
      case kPushoverPluginId:
        await showDialog<void>(
          context: context,
          builder: (_) => _PushoverConfigDialog(
            plugin: instance as PushoverNotificationPlugin,
            storage: pluginContext.storage,
          ),
        );
      case kHomeAssistantPluginId:
        await showDialog<void>(
          context: context,
          builder: (_) => _HomeAssistantConfigDialog(
            plugin: instance as HomeAssistantPlugin,
            storage: pluginContext.storage,
          ),
        );
      case kDiscordPluginId:
        await showDialog<void>(
          context: context,
          builder: (_) => _DiscordConfigDialog(
            storage: pluginContext.storage,
            pluginContext: pluginContext,
            httpClientFactory: testHttpClientFactory,
          ),
        );
    }
  }
}

/// Status pill summarizing a plugin's state, in strict priority order:
/// error (red) > disabled (inactive) > last-fired (success) > enabled (active).
///
/// Disabled is checked BEFORE last-fired on purpose: a plugin the user has
/// turned off must read "Disabled" even if it fired earlier in the session.
/// Showing a green "Fired 3m ago" badge for an integration the user disabled
/// would misrepresent its state — the status pill is the at-a-glance truth of
/// the row, so it must never signal "actively working" for something that is
/// off. When a disabled plugin did fire earlier, the relative time is still
/// surfaced as secondary context.
class _PluginStatusPill extends StatelessWidget {
  const _PluginStatusPill({
    required this.enabled,
    required this.hasError,
    required this.error,
    required this.lastFiredAt,
  });

  final bool enabled;
  final bool hasError;
  final String? error;
  final DateTime? lastFiredAt;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const StatusPill(
        icon: LucideIcons.alertTriangle,
        label: '',
        value: 'Error',
        status: StatusPillStatus.error,
      );
    }

    if (!enabled) {
      // Off takes precedence over a stale "Fired" timestamp. If it did fire
      // before being disabled, keep the relative time as the pill value so the
      // operator still sees when it last did something, labelled "Disabled".
      return StatusPill(
        icon: LucideIcons.power,
        label: lastFiredAt != null ? 'Disabled' : '',
        value: lastFiredAt != null
            ? formatRelativeTime(lastFiredAt!)
            : 'Disabled',
        status: StatusPillStatus.inactive,
      );
    }

    if (lastFiredAt != null) {
      return StatusPill(
        icon: LucideIcons.activity,
        label: 'Fired',
        value: formatRelativeTime(lastFiredAt!),
        status: StatusPillStatus.success,
      );
    }

    return const StatusPill(
      icon: LucideIcons.check,
      label: '',
      value: 'Enabled',
      status: StatusPillStatus.active,
    );
  }
}

/// Formats a [timestamp] as a compact, human-relative string ("just now",
/// "3m ago", "2h ago", "5d ago"). Exposed for testability.
String formatRelativeTime(DateTime timestamp, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final delta = reference.difference(timestamp);

  if (delta.isNegative) {
    // Clock skew / future timestamp — clamp to "just now" rather than emitting
    // a nonsensical negative duration.
    return 'just now';
  }
  if (delta.inSeconds < 45) return 'just now';
  if (delta.inMinutes < 1) return '1m ago';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

/// The enable/disable switch bound to [pluginEnablementProvider.setEnabled],
/// which persists the choice AND drives the live host. Failures surface via
/// [ErrorDialog]; the toggle is never optimistically left in a wrong state.
class _PluginEnableSwitch extends ConsumerStatefulWidget {
  const _PluginEnableSwitch({
    required this.pluginId,
    required this.value,
    required this.enabled,
  });

  final String pluginId;
  final bool value;
  final bool enabled;

  @override
  ConsumerState<_PluginEnableSwitch> createState() =>
      _PluginEnableSwitchState();
}

class _PluginEnableSwitchState extends ConsumerState<_PluginEnableSwitch> {
  bool _busy = false;

  Future<void> _onChanged(bool next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(pluginEnablementProvider.notifier)
          .setEnabled(widget.pluginId, next);
    } catch (error, stackTrace) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Could not update plugin',
        message:
            'Nightshade could not ${next ? 'enable' : 'disable'} this plugin. '
            'Its current state is unchanged.',
        technicalDetails: '$error\n$stackTrace',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NightshadeSwitch(
      value: widget.value,
      enabled: widget.enabled && !_busy,
      onChanged: _onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Configuration dialogs
// ---------------------------------------------------------------------------

/// Pushover credentials dialog. Writes apiToken + userKey through the plugin's
/// public [PushoverNotificationPlugin.configureCredentials] (which persists to
/// plugin storage). Pre-fills from existing storage so re-opening shows the
/// current values.
class _PushoverConfigDialog extends StatefulWidget {
  const _PushoverConfigDialog({
    required this.plugin,
    required this.storage,
  });

  final PushoverNotificationPlugin plugin;
  final PluginStorage storage;

  @override
  State<_PushoverConfigDialog> createState() => _PushoverConfigDialogState();
}

class _PushoverConfigDialogState extends State<_PushoverConfigDialog> {
  final _apiTokenController = TextEditingController();
  final _userKeyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _validationError;

  static const _apiTokenKey = 'pushover.apiToken';
  static const _userKeyKey = 'pushover.userKey';

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final token = await widget.storage.getString(_apiTokenKey);
    final user = await widget.storage.getString(_userKeyKey);
    if (!mounted) return;
    setState(() {
      _apiTokenController.text = token ?? '';
      _userKeyController.text = user ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _userKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _apiTokenController.text.trim();
    final user = _userKeyController.text.trim();
    if (token.isEmpty || user.isEmpty) {
      setState(() => _validationError =
          'Both the application token and user/group key are required.');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      await widget.plugin.configureCredentials(apiToken: token, userKey: user);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _saving = false);
      await ErrorDialog.show(
        context,
        title: 'Could not save Pushover credentials',
        message: 'Nightshade could not write the Pushover credentials to '
            'plugin storage.',
        technicalDetails: '$error\n$stackTrace',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadeDialog(
      title: 'Configure Pushover',
      icon: LucideIcons.bell,
      width: 480,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: 'Save',
          icon: LucideIcons.save,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(NightshadeTokens.space2xl),
              child: Center(child: ShimmerLoading(child: SizedBox(height: 80))),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stored once per plugin so credentials never leak into saved '
                  'sequences. Add a Pushover Notification node to a sequence to '
                  'send pushes.',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                NightshadeTextField(
                  label: 'Application token',
                  hint: 'azGDORePK8gMaC0QOYAMyEEuzJnyUi',
                  controller: _apiTokenController,
                  obscureText: true,
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                NightshadeTextField(
                  label: 'User / group key',
                  hint: 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
                  controller: _userKeyController,
                  obscureText: true,
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  NightshadeInlineBanner(
                    message: _validationError!,
                    severity: NightshadeAlertSeverity.error,
                  ),
                ],
              ],
            ),
    );
  }
}

/// Home Assistant connection dialog. Writes baseUrl + token through the
/// plugin's public [HomeAssistantPlugin.configureConnection].
class _HomeAssistantConfigDialog extends StatefulWidget {
  const _HomeAssistantConfigDialog({
    required this.plugin,
    required this.storage,
  });

  final HomeAssistantPlugin plugin;
  final PluginStorage storage;

  @override
  State<_HomeAssistantConfigDialog> createState() =>
      _HomeAssistantConfigDialogState();
}

class _HomeAssistantConfigDialogState
    extends State<_HomeAssistantConfigDialog> {
  final _baseUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _validationError;

  static const _baseUrlKey = 'home_assistant.baseUrl';
  static const _tokenKey = 'home_assistant.token';

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final baseUrl = await widget.storage.getString(_baseUrlKey);
    final token = await widget.storage.getString(_tokenKey);
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl ?? '';
      _tokenController.text = token ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    final token = _tokenController.text.trim();
    if (baseUrl.isEmpty || token.isEmpty) {
      setState(() => _validationError =
          'Both the base URL and a long-lived access token are required.');
      return;
    }
    final parsed = Uri.tryParse(baseUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      setState(() => _validationError =
          'The base URL must be a full URL, e.g. http://homeassistant.local:8123');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      await widget.plugin
          .configureConnection(baseUrl: baseUrl, accessToken: token);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _saving = false);
      await ErrorDialog.show(
        context,
        title: 'Could not save Home Assistant connection',
        message: 'Nightshade could not write the Home Assistant connection '
            'details to plugin storage.',
        technicalDetails: '$error\n$stackTrace',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadeDialog(
      title: 'Configure Home Assistant',
      icon: LucideIcons.home,
      width: 480,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: 'Save',
          icon: LucideIcons.save,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(NightshadeTokens.space2xl),
              child: Center(child: ShimmerLoading(child: SizedBox(height: 80))),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect to your Home Assistant instance with a long-lived '
                  'access token. Sequence nodes can then turn entities on/off '
                  'to automate dew heaters, dome shutters, and lighting.',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                NightshadeTextField(
                  label: 'Base URL',
                  hint: 'http://homeassistant.local:8123',
                  controller: _baseUrlController,
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                NightshadeTextField(
                  label: 'Long-lived access token',
                  hint: 'eyJ0eXAiOiJKV1QiLCJhbGc…',
                  controller: _tokenController,
                  obscureText: true,
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  NightshadeInlineBanner(
                    message: _validationError!,
                    severity: NightshadeAlertSeverity.error,
                  ),
                ],
              ],
            ),
    );
  }
}

/// Discord configuration dialog.
///
/// The Discord plugin's real credential is per-NODE: each `discord.webhook`
/// sequence node carries its own URL. This dialog explains that, lets the user
/// persist a default/test webhook URL (to the plugin's storage), and runs a
/// "Test send" through the plugin's REAL node execute path (so it reuses the
/// plugin's validation + HTTP code and fires the `plugin.discord.sent` event
/// against the live context, updating "last fired").
class _DiscordConfigDialog extends StatefulWidget {
  const _DiscordConfigDialog({
    required this.storage,
    required this.pluginContext,
    required this.httpClientFactory,
  });

  final PluginStorage storage;
  final PluginContext pluginContext;

  /// Test seam: factory the test-send node uses to build its HTTP client.
  /// Null in production → a real [http.Client].
  final http.Client Function()? httpClientFactory;

  @override
  State<_DiscordConfigDialog> createState() => _DiscordConfigDialogState();
}

class _DiscordConfigDialogState extends State<_DiscordConfigDialog> {
  final _webhookController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final url =
        await widget.storage.getString(kDiscordDefaultWebhookStorageKey);
    if (!mounted) return;
    setState(() {
      _webhookController.text = url ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _webhookController.text.trim();
    // An empty default is allowed (each node can still carry its own URL), but
    // a non-empty value must be a plausible Discord webhook.
    if (url.isNotEmpty) {
      final problem = _webhookUrlProblem(url);
      if (problem != null) {
        setState(() => _validationError = problem);
        return;
      }
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      await widget.storage.setString(kDiscordDefaultWebhookStorageKey, url);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _saving = false);
      await ErrorDialog.show(
        context,
        title: 'Could not save Discord webhook',
        message:
            'Nightshade could not write the default webhook URL to plugin '
            'storage.',
        technicalDetails: '$error\n$stackTrace',
      );
    }
  }

  Future<void> _testSend() async {
    final url = _webhookController.text.trim();
    final problem =
        url.isEmpty ? 'Enter a webhook URL to send a test.' : _webhookUrlProblem(url);
    if (problem != null) {
      setState(() => _validationError = problem);
      return;
    }
    setState(() {
      _testing = true;
      _validationError = null;
    });

    // Build a node through the plugin's REAL definition so validation + HTTP
    // behaviour exactly match a sequence run. The plugin instance we build
    // here carries the (test) http client factory; in production the factory
    // is null and the node uses a real http.Client.
    final plugin = DiscordWebhookPlugin(clientBuilder: widget.httpClientFactory);
    final node = plugin.nodeDefinitions.first.createNode({
      'webhookUrl': url,
      'embedTitle': 'Nightshade test message',
      'embedDescription':
          'If you can read this, your Discord webhook is configured correctly.',
      'embedColor': 0x3498db,
    });

    bool success;
    Object? failure;
    StackTrace? failureStack;
    try {
      // The node's own validate() runs the same checks a sequence would; surface
      // a validation failure as a friendly message rather than POSTing garbage.
      final invalid = node?.validate();
      if (invalid != null) {
        setState(() {
          _testing = false;
          _validationError = invalid;
        });
        return;
      }
      // Execute against the LIVE plugin context so the success event fires on
      // the same bus the activity tracker listens to.
      success = await node!.execute(widget.pluginContext);
    } catch (error, stackTrace) {
      success = false;
      failure = error;
      failureStack = stackTrace;
    }

    if (!mounted) return;
    setState(() => _testing = false);

    if (success) {
      NightshadeToastHelper.show(
        context: context,
        message: 'Discord test message sent.',
        severity: NightshadeAlertSeverity.success,
      );
    } else {
      await ErrorDialog.show(
        context,
        title: 'Discord test failed',
        message: 'The test message was not accepted by Discord. Check that the '
            'webhook URL is correct and still active.',
        technicalDetails: failure == null
            ? 'The Discord webhook POST did not return a success status '
                '(expected 200/204).'
            : '$failure\n$failureStack',
      );
    }
  }

  /// Returns a problem string for an obviously-wrong webhook URL, or null if it
  /// looks plausible. Mirrors the plugin node's own validation so the dialog
  /// fails fast with the same rules.
  String? _webhookUrlProblem(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https') {
      return 'The webhook URL must be an https URL.';
    }
    if (!parsed.host.endsWith('discord.com') &&
        !parsed.host.endsWith('discordapp.com')) {
      return 'The host must be discord.com or discordapp.com (got '
          '${parsed.host}).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadeDialog(
      title: 'Configure Discord Webhook',
      icon: LucideIcons.messageSquare,
      width: 520,
      actions: [
        NightshadeButton(
          label: 'Test send',
          icon: LucideIcons.send,
          variant: ButtonVariant.outline,
          isLoading: _testing,
          onPressed: (_testing || _saving) ? null : _testSend,
        ),
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: (_testing || _saving) ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: 'Save',
          icon: LucideIcons.save,
          isLoading: _saving,
          onPressed: (_testing || _saving) ? null : _save,
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(NightshadeTokens.space2xl),
              child: Center(child: ShimmerLoading(child: SizedBox(height: 80))),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NightshadeAlert(
                  severity: NightshadeAlertSeverity.info,
                  title: 'Per-node webhooks',
                  message:
                      'This plugin adds a "Discord Webhook" sequence node. Each '
                      'node carries its own webhook URL, so the same sequence '
                      'can route different steps to different channels. The URL '
                      'below is a default/test webhook saved for convenience — '
                      'to fire on observatory events instead, use Notification '
                      'Routing.',
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                NightshadeTextField(
                  label: 'Default / test webhook URL',
                  hint: 'https://discord.com/api/webhooks/…',
                  controller: _webhookController,
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  'Use "Test send" to post a sample embed and confirm the '
                  'webhook works.',
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  NightshadeInlineBanner(
                    message: _validationError!,
                    severity: NightshadeAlertSeverity.error,
                  ),
                ],
              ],
            ),
    );
  }
}
