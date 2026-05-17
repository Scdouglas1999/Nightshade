import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';

/// Bug-report attachment screen.
///
/// One button: produces a zip containing recent logs, the active equipment
/// profile, the currently loaded sequence, system info, and a snapshot of
/// device connection state. The dump is written via a native save dialog so
/// users can drop it directly into a GitHub issue without hunting through
/// the app-data directory.
///
/// Wired into [audit-observe.md §4c] / CQ-W6-DIAG-DUMP. The optical-train
/// `DiagnosticsScreen` lives next to this file but covers a different scope;
/// keep them visually distinct (different titles, different icons).
class DiagnosticDumpScreen extends ConsumerStatefulWidget {
  const DiagnosticDumpScreen({super.key});

  @override
  ConsumerState<DiagnosticDumpScreen> createState() =>
      _DiagnosticDumpScreenState();
}

class _DiagnosticDumpScreenState extends ConsumerState<DiagnosticDumpScreen> {
  bool _busy = false;
  String? _lastOutputPath;
  int? _lastOutputBytes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMobile = Responsive.isMobile(context);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to help',
                icon: const Icon(LucideIcons.arrowLeft),
                color: colors.textSecondary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/settings');
                  }
                },
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.fileArchive, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                'Diagnostic Dump',
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bundle recent logs, the active equipment profile, the currently '
            'loaded sequence, and system info into a single .zip suitable '
            'for attaching to bug reports. No telemetry is sent — the file '
            'stays on your machine until you share it.',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _ContentsCard(colors: colors),
          const SizedBox(height: 16),
          if (_lastOutputPath != null) ...[
            _LastResultCard(
              path: _lastOutputPath!,
              bytes: _lastOutputBytes,
              colors: colors,
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              NightshadeButton(
                label: _busy ? 'Building dump…' : 'Create dump',
                icon: LucideIcons.fileArchive,
                onPressed: _busy ? null : _createDump,
                isLoading: _busy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createDump() async {
    setState(() {
      _busy = true;
    });
    try {
      // Why suggest a timestamped filename: the user is encouraged to keep
      // multiple dumps (one per repro attempt) without overwriting earlier
      // attachments. Colons get rejected on Windows, hence the replace.
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final suggested = 'nightshade_diagnostic_$stamp.zip';

      final location = await file_selector.getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'Zip archive',
            extensions: ['zip'],
          ),
        ],
      );

      // Fall back to the documents directory when the picker is unavailable
      // or the user cancels. The dump is intentionally cheap; producing it
      // even when the user backed out of the dialog is acceptable only if
      // we *do not* silently invent a path — instead we cancel.
      if (location == null) {
        if (mounted) {
          context.showInfoSnackBar('Diagnostic dump cancelled.');
        }
        return;
      }

      final service = ref.read(diagnosticDumpServiceProvider);
      final file = await service.createDump(outputPath: location.path);
      final size = await file.length();

      if (!mounted) return;
      setState(() {
        _lastOutputPath = file.path;
        _lastOutputBytes = size;
      });
      context.showSuccessSnackBar(
        'Diagnostic dump written: ${file.path} (${_formatBytes(size)})',
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      if (!mounted) return;
      // Surface the failure rather than swallowing it (CLAUDE.md: errors
      // are a feature). The service has already logged the structured
      // stack trace via LoggingService.
      context.showErrorSnackBar('Diagnostic dump failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}

class _ContentsCard extends StatelessWidget {
  final NightshadeColors colors;

  const _ContentsCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Recent log files', 'logs/exported_logs.txt — concatenated and rotated'),
      ('Active equipment profile', 'profile.json — devices, optics, defaults'),
      ('Current sequence', 'sequence.json — name, tree shape, node metadata'),
      ('System info', 'system_info.json — OS, Dart version, app version'),
      (
        'Device connection list',
        'devices.json — role + connection state per device'
      ),
      ('Manifest', 'manifest.json — bundle version and per-entry status'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Will include',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in items) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.checkCircle2,
                      size: 16, color: colors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.$2,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LastResultCard extends StatelessWidget {
  final String path;
  final int? bytes;
  final NightshadeColors colors;

  const _LastResultCard({
    required this.path,
    required this.bytes,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.success),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.checkCircle2, size: 18, color: colors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last dump',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  path,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                if (bytes != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Size: ${_formatBytes(bytes!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
