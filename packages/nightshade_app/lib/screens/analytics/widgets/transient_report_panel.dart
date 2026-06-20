import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

/// Panel for exporting a confirmed First Light transient detection as an
/// AAVSO / MPC / TNS discovery report.
///
/// One detection is selected, one network format is chosen, and the panel emits
/// a properly-formatted report (real file formats — see
/// [TransientReportService]) that can be copied to the clipboard or written to
/// the exports directory. Reviewed (confirmed) detections sort first; a network
/// whose format the selected detection cannot satisfy (AAVSO needs a magnitude
/// change) is disabled with an explanatory tooltip.
class TransientReportPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final List<TransientDetectionRow> detections;

  const TransientReportPanel({
    super.key,
    required this.colors,
    required this.detections,
  });

  @override
  ConsumerState<TransientReportPanel> createState() =>
      _TransientReportPanelState();
}

class _TransientReportPanelState extends ConsumerState<TransientReportPanel> {
  int? _selectedId;
  TransientReportFormat _format = TransientReportFormat.tns;
  String? _lastExportPath;
  String? _preview;

  final _reportService = TransientReportService();

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    if (widget.detections.isEmpty) {
      return const SizedBox.shrink();
    }

    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();

    // Reviewed (confirmed) detections first, then newest.
    final sorted = [...widget.detections]..sort((a, b) {
        if (a.reviewed != b.reviewed) return a.reviewed ? -1 : 1;
        return b.detectedAt.compareTo(a.detectedAt);
      });
    final selected = sorted.firstWhere(
      (d) => d.id == _selectedId,
      orElse: () => sorted.first,
    );
    _selectedId = selected.id;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transient Discovery Report',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Submit a confirmed difference-image detection to AAVSO, the MPC, '
              'or the TNS in the network\'s real submission format.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Detection',
              style:
                  NightshadeTypography.h6.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 6),
            ...sorted.map(
              (d) => _DetectionTile(
                colors: colors,
                detection: d,
                selected: d.id == _selectedId,
                onTap: () => setState(() {
                  _selectedId = d.id;
                  _preview = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Network',
              style:
                  NightshadeTypography.h6.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              children: TransientReportFormat.values.map((fmt) {
                final enabled = _formatEnabled(fmt, selected);
                return NightshadeChip(
                  label: _formatLabel(fmt),
                  selected: _format == fmt,
                  onTap: enabled
                      ? () => setState(() {
                            _format = fmt;
                            _preview = null;
                          })
                      : null,
                );
              }).toList(),
            ),
            if (!_formatEnabled(_format, selected)) ...[
              const SizedBox(height: 6),
              Text(
                _disabledReason(_format),
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.warning,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_preview != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: SelectableText(
                  _preview!,
                  style: NightshadeTypography.monoSm
                      .copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    label: 'Preview',
                    icon: LucideIcons.eye,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: _formatEnabled(_format, selected)
                        ? () => setState(
                              () => _preview =
                                  _buildReport(selected, scienceSettings),
                            )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    label: 'Copy',
                    icon: LucideIcons.clipboard,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: _formatEnabled(_format, selected)
                        ? () => _copy(selected, scienceSettings)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    label: 'Export',
                    icon: LucideIcons.download,
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                    onPressed: _formatEnabled(_format, selected)
                        ? () => _export(selected, scienceSettings)
                        : null,
                  ),
                ),
              ],
            ),
            if (_lastExportPath != null) ...[
              const SizedBox(height: 6),
              Text(
                'Exported: $_lastExportPath',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _formatEnabled(TransientReportFormat fmt, TransientDetectionRow d) {
    switch (fmt) {
      case TransientReportFormat.aavso:
        // AAVSO photometry needs a magnitude change.
        final dm = d.deltaMag;
        return dm != null && dm.isFinite;
      case TransientReportFormat.mpc:
        return ref
                .read(scienceSettingsProvider)
                .valueOrNull
                ?.mpcObservatoryCode
                .length ==
            3;
      case TransientReportFormat.tns:
        return true;
    }
  }

  String _disabledReason(TransientReportFormat fmt) {
    switch (fmt) {
      case TransientReportFormat.aavso:
        return 'AAVSO needs a magnitude change — this is a brand-new source. '
            'Use the TNS report instead.';
      case TransientReportFormat.mpc:
        return 'Set your 3-character MPC observatory code in '
            'Settings > Science > MPC first.';
      case TransientReportFormat.tns:
        return '';
    }
  }

  String _buildReport(TransientDetectionRow d, ScienceSettings settings) {
    switch (_format) {
      case TransientReportFormat.aavso:
        return _reportService.generateAavsoReport(
          detection: d,
          observerCode: settings.aavsoObserverCode.isNotEmpty
              ? settings.aavsoObserverCode
              : 'NSOBS',
        );
      case TransientReportFormat.mpc:
        return _reportService.generateMpcReport(
          detection: d,
          observatoryCode: settings.mpcObservatoryCode,
        );
      case TransientReportFormat.tns:
        return _reportService.generateTnsReport(
          detection: d,
          reporterName: settings.aavsoObserverCode.isNotEmpty
              ? settings.aavsoObserverCode
              : 'Nightshade observer',
        );
    }
  }

  Future<void> _copy(TransientDetectionRow d, ScienceSettings settings) async {
    try {
      final report = _buildReport(d, settings);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        context.showSuccessSnackBar('${_formatLabel(_format)} report copied');
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Report failed: $e');
    }
  }

  Future<void> _export(
      TransientDetectionRow d, ScienceSettings settings) async {
    try {
      final report = _buildReport(d, settings);
      final ext = _format == TransientReportFormat.mpc ? 'txt' : 'tsv';
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = await _reportService.writeReport(
        content: report,
        fileName: '${_format.name}_transient_${d.id}_$stamp.$ext',
      );
      if (mounted) {
        setState(() => _lastExportPath = filePath);
        context.showSuccessSnackBar('Report exported to: $filePath');
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Export failed: $e');
    }
  }

  String _formatLabel(TransientReportFormat fmt) {
    switch (fmt) {
      case TransientReportFormat.aavso:
        return 'AAVSO';
      case TransientReportFormat.mpc:
        return 'MPC';
      case TransientReportFormat.tns:
        return 'TNS';
    }
  }
}

class _DetectionTile extends StatelessWidget {
  final NightshadeColors colors;
  final TransientDetectionRow detection;
  final bool selected;
  final VoidCallback onTap;

  const _DetectionTile({
    required this.colors,
    required this.detection,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = detection.catalogMatch ?? 'Unnamed source';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.checkCircle : LucideIcons.circle,
              size: 14,
              color: selected ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${detection.kind} · SNR ${detection.snr.toStringAsFixed(1)}'
                    '${detection.reviewed ? ' · confirmed' : ''}',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize9,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
