import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Log viewer settings page with live-tailing, filtering, and export.
class LogViewer extends ConsumerStatefulWidget {
  final bool isMobile;

  const LogViewer({super.key, this.isMobile = false});

  @override
  ConsumerState<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends ConsumerState<LogViewer>
    with WidgetsBindingObserver {
  LogLevel _minLevel = LogLevel.debug;
  String? _sourceFilter;
  String _searchQuery = '';
  bool _autoScroll = true;
  // 1 Hz live-tail timer. Suspended when the app is backgrounded so a
  // hidden settings tab doesn't keep polling the log buffer (§4.33).
  Timer? _refreshTimer;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<LogEntry> _filteredLogs = [];
  List<LogEntry> _allLogs = [];
  Set<String> _availableSources = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLogs();
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    // Refresh every second for live tailing
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLogs();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_refreshTimer == null || !_refreshTimer!.isActive) {
        _refreshLogs();
        _startRefreshTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshLogs() {
    // [Wave 6E log tail] — when the active backend is a NetworkBackend we
    // pull from /api/logs/recent so a remote session shows the host's
    // logs, not the local (empty) ring buffer. The local LoggingService
    // path is preserved for FFI / disconnected backends.
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      // Fire-and-forget refresh; the user's filters apply once the
      // response lands. Errors silently fall back to whatever was last
      // rendered — surfaced via the SnackBars on Clear/Export so the
      // operator still gets feedback when the action they triggered
      // failed.
      backend.fetchRecentServerLogs(limit: 500).then((logs) {
        if (!mounted) return;
        setState(() {
          _allLogs = logs;
          _availableSources = logs
              .where((e) => e.source != null)
              .map((e) => e.source!)
              .toSet();
          _applyFilters();
        });
        if (_autoScroll && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }).catchError((Object e) {
        // Keep the previous frame on-screen. The 1-Hz refresh timer will
        // retry on the next tick.
      });
      return;
    }

    final loggingService = ref.read(loggingServiceProvider);
    final logs = loggingService.getRecentLogs();

    if (!mounted) return;

    setState(() {
      _allLogs = logs;
      _availableSources =
          logs.where((e) => e.source != null).map((e) => e.source!).toSet();
      _applyFilters();
    });

    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _applyFilters() {
    _filteredLogs = _allLogs.where((entry) {
      if (entry.level.index < _minLevel.index) return false;
      if (_sourceFilter != null && entry.source != _sourceFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesMessage = entry.message.toLowerCase().contains(query);
        final matchesSource =
            entry.source?.toLowerCase().contains(query) ?? false;
        if (!matchesMessage && !matchesSource) return false;
      }
      return true;
    }).toList();
  }

  Color _levelColor(LogLevel level) {
    final colors = NightshadeColors.of(context);
    switch (level) {
      case LogLevel.debug:
        return colors.textMuted;
      case LogLevel.info:
        return colors.info;
      case LogLevel.warning:
        return colors.warning;
      case LogLevel.error:
        return colors.error;
      case LogLevel.critical:
        return colors.error;
    }
  }

  String _levelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DBG';
      case LogLevel.info:
        return 'INF';
      case LogLevel.warning:
        return 'WRN';
      case LogLevel.error:
        return 'ERR';
      case LogLevel.critical:
        return 'CRT';
    }
  }

  Future<void> _copyAllToClipboard() async {
    final text = _filteredLogs.map((e) => e.toString()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${_filteredLogs.length} log entries copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _exportLogs() async {
    final loggingService = ref.read(loggingServiceProvider);
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final outputPath =
          '${docsDir.path}${Platform.pathSeparator}nightshade_logs_$timestamp.txt';

      await loggingService.exportLogs(outputPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logs exported to: $outputPath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: NightshadeColors.of(context).error,
          ),
        );
      }
    }
  }

  Future<void> _clearLogs() async {
    // [Wave 6E log tail] — Clear on a remote session must target the
    // server's log files; otherwise the operator presses Clear and sees
    // no change because we're clearing the local (already-empty) buffer.
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      try {
        await backend.clearServerLogs();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Clear failed: $e'),
              backgroundColor: NightshadeColors.of(context).error,
            ),
          );
        }
        return;
      }
      _refreshLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server log files cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final loggingService = ref.read(loggingServiceProvider);
    await loggingService.clearLogs();
    _refreshLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Old log files cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = widget.isMobile;
    final padding =
        isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(32);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMobile) ...[
            Text(
              'Logs',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'View application logs with filtering and export',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
          ],
          // Filter bar
          _buildFilterBar(colors, isMobile),
          const SizedBox(height: 12),
          // Action buttons
          _buildActionBar(colors, isMobile),
          const SizedBox(height: 12),
          // Log count indicator
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_filteredLogs.length} of ${_allLogs.length} entries',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ),
          // Log entries list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                border: Border.all(color: colors.border),
              ),
              child: _filteredLogs.isEmpty
                  ? Center(
                      child: Text(
                        _allLogs.isEmpty
                            ? 'No log entries yet'
                            : 'No entries match current filters',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize13,
                          color: colors.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _filteredLogs.length,
                      itemBuilder: (context, index) {
                        return _buildLogEntry(
                            _filteredLogs[index], colors, isMobile);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(NightshadeColors colors, bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Level filter buttons
        _LevelFilterButton(
          label: 'All',
          isSelected: _minLevel == LogLevel.debug,
          onTap: () => setState(() {
            _minLevel = LogLevel.debug;
            _applyFilters();
          }),
        ),
        _LevelFilterButton(
          label: 'Warn+',
          isSelected: _minLevel == LogLevel.warning,
          color: colors.warning,
          onTap: () => setState(() {
            _minLevel = LogLevel.warning;
            _applyFilters();
          }),
        ),
        _LevelFilterButton(
          label: 'Error+',
          isSelected: _minLevel == LogLevel.error,
          color: colors.error,
          onTap: () => setState(() {
            _minLevel = LogLevel.error;
            _applyFilters();
          }),
        ),
        // Source dropdown
        if (_availableSources.isNotEmpty) _buildSourceDropdown(colors),
        // Search field
        SizedBox(
          width: isMobile ? 160 : 200,
          height: 32,
          child: TextField(
            controller: _searchController,
            style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search logs...',
              hintStyle: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: colors.textMuted),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, maxWidth: 32),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                borderSide: BorderSide(color: colors.primary),
              ),
              filled: true,
              fillColor: colors.surfaceAlt,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            onChanged: (value) => setState(() {
              _searchQuery = value;
              _applyFilters();
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceDropdown(NightshadeColors colors) {
    final sortedSources = _availableSources.toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _sourceFilter,
          isDense: true,
          hint: Text(
            'All sources',
            style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
          ),
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          dropdownColor: colors.surface,
          style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textPrimary),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('All sources',
                  style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textPrimary)),
            ),
            ...sortedSources.map((s) => DropdownMenuItem<String?>(
                  value: s,
                  child: Text(s,
                      style:
                          TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textPrimary)),
                )),
          ],
          onChanged: (value) => setState(() {
            _sourceFilter = value;
            _applyFilters();
          }),
        ),
      ),
    );
  }

  Widget _buildActionBar(NightshadeColors colors, bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Auto-scroll toggle
        _ActionToggle(
          icon: LucideIcons.arrowDownToLine,
          label: 'Auto-scroll',
          isActive: _autoScroll,
          onTap: () => setState(() => _autoScroll = !_autoScroll),
        ),
        NightshadeButton(
          label: 'Copy All',
          icon: LucideIcons.copy,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: _filteredLogs.isEmpty ? null : _copyAllToClipboard,
        ),
        NightshadeButton(
          label: 'Export',
          icon: LucideIcons.download,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: _exportLogs,
        ),
        NightshadeButton(
          label: 'Clear',
          icon: LucideIcons.trash2,
          variant: ButtonVariant.destructive,
          size: ButtonSize.small,
          onPressed: _clearLogs,
        ),
      ],
    );
  }

  Widget _buildLogEntry(
      LogEntry entry, NightshadeColors colors, bool isMobile) {
    final levelColor = _levelColor(entry.level);
    final levelLabel = _levelLabel(entry.level);
    final timeStr = _formatTimestamp(entry.timestamp);
    final fontSize = isMobile ? 11.0 : 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            timeStr,
            style: TextStyle(
              fontSize: fontSize,
              fontFamily: 'monospace',
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: NightshadeDecorations.statusChip(
              levelColor,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
              bordered: false,
            ),
            child: Text(
              levelLabel,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: levelColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Source tag
          if (entry.source != null) ...[
            Text(
              '[${entry.source}]',
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: 'monospace',
                color: colors.primary.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
          ],
          // Message
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: 'monospace',
                color: entry.level.index >= LogLevel.error.index
                    ? levelColor
                    : colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

class _LevelFilterButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _LevelFilterButton({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final effectiveColor = color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: isSelected
            ? NightshadeDecorations.selectedSurface(
                effectiveColor,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              )
            : BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                border: Border.all(color: colors.border),
              ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? effectiveColor : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActionToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ActionToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: isActive
            ? NightshadeDecorations.selectedSurface(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              )
            : BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                border: Border.all(color: colors.border),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
