import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';

/// Plugins settings screen
///
/// Displays all registered plugins with their status, description, and controls.
/// Allows users to enable/disable plugins and view plugin information.
class PluginsScreen extends ConsumerWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final pluginHost = ref.watch(pluginHostProvider);
    final plugins = pluginHost.pluginInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Plugins',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Extend Nightshade with additional functionality',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Plugin count
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.puzzle,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plugins.length} Plugin${plugins.length != 1 ? 's' : ''} Loaded',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plugins.where((p) => p.enabled).length} enabled, '
                      '${plugins.where((p) => !p.enabled).length} disabled',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Plugin list
          if (plugins.isEmpty)
            _EmptyState(colors: colors)
          else
            ...plugins.map((plugin) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PluginCard(
                    plugin: plugin,
                    colors: colors,
                    onToggle: (enabled) async {
                      try {
                        await pluginHost.setPluginEnabled(plugin.id, enabled);
                      } catch (e) {
                        if (context.mounted) {
                          context.showErrorSnackBar('Error: $e');
                        }
                      }
                    },
                  ),
                )),

          const SizedBox(height: 32),

          // Developer info
          _DeveloperInfo(colors: colors),
        ],
      ),
    );
  }
}

/// Empty state when no plugins are loaded
class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.package,
              size: 64,
              color: colors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No Plugins Loaded',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Plugins extend Nightshade with custom functionality.\n'
              'Check the documentation to learn how to create plugins.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying plugin information
class _PluginCard extends StatefulWidget {
  final PluginInfo plugin;
  final NightshadeColors colors;
  final Function(bool) onToggle;

  const _PluginCard({
    required this.plugin,
    required this.colors,
    required this.onToggle,
  });

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.plugin.error != null;

    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? widget.colors.error.withValues(alpha: 0.5)
              : widget.colors.border,
        ),
      ),
      child: Column(
        children: [
          // Main plugin info
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.plugin.enabled
                          ? widget.colors.primary.withValues(alpha: 0.1)
                          : widget.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.plugin.enabled
                            ? widget.colors.primary.withValues(alpha: 0.3)
                            : widget.colors.border,
                      ),
                    ),
                    child: Icon(
                      LucideIcons.puzzle,
                      color: widget.plugin.enabled
                          ? widget.colors.primary
                          : widget.colors.textMuted,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Name and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.plugin.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: widget.colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.colors.surfaceAlt,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: widget.colors.border),
                              ),
                              child: Text(
                                'v${widget.plugin.version}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.colors.textMuted,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.plugin.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.colors.textSecondary,
                          ),
                          maxLines: _expanded ? null : 2,
                          overflow:
                              _expanded ? null : TextOverflow.ellipsis,
                        ),
                        if (hasError) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.alertCircle,
                                size: 14,
                                color: widget.colors.error,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Error: ${widget.plugin.error}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.colors.error,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Enable/disable toggle
                  _PluginToggle(
                    enabled: widget.plugin.enabled,
                    onChanged: widget.onToggle,
                    colors: widget.colors,
                  ),
                  const SizedBox(width: 8),

                  // Expand button
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: widget.colors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Expanded details
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: widget.colors.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'ID',
                    value: widget.plugin.id,
                    colors: widget.colors,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Author',
                    value: widget.plugin.author,
                    colors: widget.colors,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Loaded',
                    value: _formatDateTime(widget.plugin.loadedAt),
                    colors: widget.colors,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Status',
                    value: widget.plugin.enabled ? 'Enabled' : 'Disabled',
                    colors: widget.colors,
                    valueColor: widget.plugin.enabled
                        ? widget.colors.success
                        : widget.colors.textMuted,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Toggle switch for enabling/disabling plugins
class _PluginToggle extends StatelessWidget {
  final bool enabled;
  final Function(bool) onChanged;
  final NightshadeColors colors;

  const _PluginToggle({
    required this.enabled,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: enabled ? colors.primary : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? colors.primary : colors.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Row displaying a plugin detail
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? colors.textSecondary,
              fontFamily: label == 'ID' ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Developer information section
class _DeveloperInfo extends StatelessWidget {
  final NightshadeColors colors;

  const _DeveloperInfo({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.code,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Plugin Development',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Plugins are loaded at application startup. To develop your own plugins, '
            'implement the NightshadePlugin interface and register your plugin in the app initialization code.',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Plugin Types Available:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _PluginTypeChip(
            label: 'Base Plugin',
            description: 'Core functionality',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _PluginTypeChip(
            label: 'UI Plugin',
            description: 'Add custom panels and widgets',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _PluginTypeChip(
            label: 'Device Plugin',
            description: 'Support new hardware',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _PluginTypeChip(
            label: 'Sequence Plugin',
            description: 'Custom automation nodes',
            colors: colors,
          ),
        ],
      ),
    );
  }
}

/// Chip displaying plugin type information
class _PluginTypeChip extends StatelessWidget {
  final String label;
  final String description;
  final NightshadeColors colors;

  const _PluginTypeChip({
    required this.label,
    required this.description,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          description,
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
