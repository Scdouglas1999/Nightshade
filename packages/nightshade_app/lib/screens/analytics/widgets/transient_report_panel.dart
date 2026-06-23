import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

/// Panel for submitting / exporting a confirmed First Light transient detection
/// to AAVSO, the MPC, or the TNS.
///
/// Honest per-format behaviour:
///   * TNS — a REAL bot-API submission (when bot credentials are configured).
///     The primary action is "Submit to TNS"; it creates a live, public AT
///     record. Local backend submits directly; a slave routes through the host.
///   * AAVSO — generates an ingestible Extended File Format report you upload
///     to WebObs manually (no per-observer upload API). Requires a calibrated
///     magnitude; disabled (never `na`-stuffed) otherwise.
///   * MPC — generates an ADES PSV astrometry report you submit via the MPC web
///     form. Requires a 3-char observatory code and a plausible mover.
///
/// The panel is the single place both the discovery card and the science export
/// hub route through, so the truth lives in exactly one place.
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
  String? _lastAtName;
  String? _preview;
  bool _submitting = false;

  final _reportService = TransientReportService();

  // The science calibration path does not (yet) join a per-frame photometric
  // zeropoint onto the detection row, so a calibrated AAVSO magnitude is not
  // available here. AAVSO is therefore disabled for current detections (the
  // honest STD-mag gate) rather than emitting a non-ingestible na-filled row.
  // When the MAGZP join lands, thread it in here and AAVSO enables itself.
  double? get _magZeroPoint => null;

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
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transient Discovery Report',
              style: NightshadeTypography.h6.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              'Submit a confirmed detection to the TNS live with your bot key, '
              'or export an ingestible AAVSO / MPC report to upload manually.',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            Text(
              'Detection',
              style: NightshadeTypography.h6.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
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
            const SizedBox(height: NightshadeTokens.spaceMd),
            Text(
              'Network',
              style: NightshadeTypography.h6.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              children: TransientReportFormat.values.map((fmt) {
                final enabled = _formatEnabled(fmt, selected, scienceSettings);
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
            if (!_formatEnabled(_format, selected, scienceSettings)) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                _disabledReason(_format, selected, scienceSettings),
                style: NightshadeTypography.labelQuiet.copyWith(
                  color: colors.warning,
                ),
              ),
            ],
            const SizedBox(height: NightshadeTokens.spaceMd),
            if (_preview != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: SelectableText(
                  _preview!,
                  style: NightshadeTypography.monoSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
            ],
            _buildActionRow(selected, scienceSettings, colors),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              _actionNote(_format),
              style: NightshadeTypography.labelQuiet.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (_lastAtName != null) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'Submitted as $_lastAtName',
                style: NightshadeTypography.labelQuiet.copyWith(
                  color: colors.success,
                ),
              ),
            ],
            if (_lastExportPath != null) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'Exported: $_lastExportPath',
                style: NightshadeTypography.labelQuiet.copyWith(
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

  Widget _buildActionRow(
    TransientDetectionRow d,
    ScienceSettings settings,
    NightshadeColors colors,
  ) {
    final enabled = _formatEnabled(_format, d, settings) && !_submitting;
    final canPreviewLocally = _format != TransientReportFormat.tns;

    final primary = _format == TransientReportFormat.tns
        ? NightshadeButton(
            label: _submitting ? 'Submitting…' : 'Submit to TNS',
            icon: LucideIcons.send,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: enabled ? () => _submitTns(d, settings) : null,
          )
        : NightshadeButton(
            label: 'Export report',
            icon: LucideIcons.download,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: enabled ? () => _export(d, settings) : null,
          );

    return Row(
      children: [
        // TNS has no local text preview (it's a JSON payload submitted live);
        // show a "Preview JSON" for transparency, Copy for AAVSO/MPC.
        Expanded(
          child: NightshadeButton(
            label: 'Preview',
            icon: LucideIcons.eye,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: _formatEnabled(_format, d, settings)
                ? () => setState(
                      () => _preview = _buildPreview(d, settings),
                    )
                : null,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        if (canPreviewLocally) ...[
          Expanded(
            child: NightshadeButton(
              label: 'Copy',
              icon: LucideIcons.clipboard,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: _formatEnabled(_format, d, settings)
                  ? () => _copy(d, settings)
                  : null,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
        ],
        Expanded(child: primary),
      ],
    );
  }

  /// Honest one-liner under the action row describing what the primary action
  /// actually does for the selected format.
  String _actionNote(TransientReportFormat fmt) {
    switch (fmt) {
      case TransientReportFormat.tns:
        return 'Submits live to the TNS via your bot API key — creates a '
            'public AT record.';
      case TransientReportFormat.aavso:
        return 'Exports an ingestible .txt — upload it to AAVSO WebObs '
            'manually.';
      case TransientReportFormat.mpc:
        return 'Exports an ADES .psv — submit it via the MPC web form.';
    }
  }

  bool _formatEnabled(
    TransientReportFormat fmt,
    TransientDetectionRow d,
    ScienceSettings settings,
  ) {
    // A low-confidence dipole / unreviewed candidate must never one-tap a TNS
    // "possible SN" false alarm. Gate every format on review + exclude dipoles.
    if (!d.reviewed) return false;
    if (TransientKind.fromWire(d.kind) == TransientKind.dipole) return false;

    switch (fmt) {
      case TransientReportFormat.aavso:
        return _reportService.aavsoAvailable(d, magZeroPoint: _magZeroPoint) &&
            settings.aavsoObserverCode.trim().isNotEmpty;
      case TransientReportFormat.mpc:
        // ADES astrometry needs the obs code; a stationary brightening is not a
        // minor planet, so gate on a plausible mover.
        return _reportService.mpcAdesAvailable(
              observatoryCode: settings.mpcObservatoryCode,
            ) &&
            TransientKind.fromWire(d.kind).isPlausibleMover;
      case TransientReportFormat.tns:
        return _tnsCreds(settings).isComplete;
    }
  }

  String _disabledReason(
    TransientReportFormat fmt,
    TransientDetectionRow d,
    ScienceSettings settings,
  ) {
    if (!d.reviewed) {
      return 'Not yet confirmed — mark this detection as confirmed before '
          'submitting, so an artefact cannot be reported as a discovery.';
    }
    if (TransientKind.fromWire(d.kind) == TransientKind.dipole) {
      return 'Dipole artefacts (registration/PSF mismatch) are not real '
          'transients and cannot be submitted.';
    }
    switch (fmt) {
      case TransientReportFormat.aavso:
        return _reportService.aavsoDisabledReason(
              d,
              observerCode: settings.aavsoObserverCode,
              magZeroPoint: _magZeroPoint,
            ) ??
            '';
      case TransientReportFormat.mpc:
        if (!TransientKind.fromWire(d.kind).isPlausibleMover) {
          return 'MPC astrometry is for moving objects — this detection is not '
              'a plausible mover.';
        }
        return 'Set your 3-character MPC observatory code in '
            'Settings > Science first.';
      case TransientReportFormat.tns:
        return 'TNS submission needs your bot id/name, reporting group, data '
            'source, reporter, and api key — configure them in '
            'Settings > Science.';
    }
  }

  TnsCredentials _tnsCreds(ScienceSettings settings) {
    // The secret api key is read async at submit time; for the gate we only
    // need the non-secret identifiers + the cached has-key flag. We optimistic-
    // enable on the non-secret fields and verify the key at submit time.
    return TnsCredentials(
      botId: settings.tnsBotId,
      botName: settings.tnsBotName,
      reportingGroupId: settings.tnsReportingGroupId,
      dataSourceId: settings.tnsDataSourceId,
      reporterName: settings.tnsReporterName.isNotEmpty
          ? settings.tnsReporterName
          : settings.observerName,
      // Placeholder so the gate passes on identifiers; the real key is loaded
      // at submit time and re-checked there.
      apiKey: 'pending',
    );
  }

  String _buildPreview(TransientDetectionRow d, ScienceSettings settings) {
    switch (_format) {
      case TransientReportFormat.aavso:
        return _reportService.generateAavsoReport(
          detection: d,
          observerCode: settings.aavsoObserverCode,
          magZeroPoint: _magZeroPoint ?? 0.0,
        );
      case TransientReportFormat.mpc:
        return _reportService.generateMpcAdesPsv(
          detection: d,
          observatoryCode: settings.mpcObservatoryCode,
          observerName: settings.observerName,
          astrometricCatalog: settings.mpcAstrometricCatalog,
        );
      case TransientReportFormat.tns:
        final creds = _tnsCreds(settings);
        final json = _reportService.buildTnsReportJson(
          detection: d,
          creds: creds,
        );
        return const JsonEncoderPretty().convert(json);
    }
  }

  Future<void> _copy(TransientDetectionRow d, ScienceSettings settings) async {
    try {
      final report = _buildPreview(d, settings);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        context.showSuccessSnackBar('${_formatLabel(_format)} report copied');
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Report failed: $e');
    }
  }

  Future<void> _export(
    TransientDetectionRow d,
    ScienceSettings settings,
  ) async {
    final backend = ref.read(backendProvider);
    try {
      String? path;
      if (backend is NetworkBackend) {
        // Slave: ask the host to generate the report and save the bytes.
        if (_format == TransientReportFormat.aavso) {
          final bytes = await backend.exportFirstLightAavso(
            d.id,
            magZeroPoint: _magZeroPoint ?? 0.0,
          );
          path = await _reportService.writeReport(
            content: String.fromCharCodes(bytes),
            fileName: 'aavso_transient_${d.id}.txt',
          );
        } else {
          final bytes = await backend.exportFirstLightMpc(d.id);
          path = await _reportService.writeReport(
            content: String.fromCharCodes(bytes),
            fileName: 'mpc_ades_transient_${d.id}.psv',
          );
        }
      } else {
        // Local host: generate directly.
        final submission = ref.read(transientSubmissionServiceProvider);
        if (_format == TransientReportFormat.aavso) {
          path = await submission.exportAavso(
            detection: d,
            observerCode: settings.aavsoObserverCode,
            magZeroPoint: _magZeroPoint ?? 0.0,
          );
        } else {
          path = await submission.exportMpcAdes(
            detection: d,
            observatoryCode: settings.mpcObservatoryCode,
            observerName: settings.observerName,
            astrometricCatalog: settings.mpcAstrometricCatalog,
          );
        }
      }
      if (mounted) {
        setState(() => _lastExportPath = path);
        context.showSuccessSnackBar('Report exported to: $path');
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Export failed: $e');
    }
  }

  Future<void> _submitTns(
    TransientDetectionRow d,
    ScienceSettings settings,
  ) async {
    final confirmed = await _confirmTnsSubmit(settings.tnsUseSandbox);
    if (confirmed != true) return;

    setState(() => _submitting = true);
    final backend = ref.read(backendProvider);
    try {
      if (backend is NetworkBackend) {
        // Slave: the host holds the credentials + api key.
        final result = await backend.submitFirstLightToTns(d.id);
        final success = result['success'] == true;
        final atName = result['atName'] as String?;
        final message = result['message']?.toString() ?? 'TNS submission done';
        if (success) {
          // Refresh the slave's feed so the persisted reviewed state / any
          // host-side change reflects after the round-trip.
          ref.invalidate(firstLightCandidatesProvider);
        }
        if (mounted) {
          setState(() => _lastAtName = success ? atName : null);
          if (success) {
            context.showSuccessSnackBar(message);
          } else {
            context.showErrorSnackBar(message);
          }
        }
      } else {
        // Local host: read the secret key, then submit directly.
        final apiKey =
            await ref.read(secretsStoreProvider).read(SecretField.tnsApiKey);
        final creds = TnsCredentials(
          botId: settings.tnsBotId,
          botName: settings.tnsBotName,
          reportingGroupId: settings.tnsReportingGroupId,
          dataSourceId: settings.tnsDataSourceId,
          reporterName: settings.tnsReporterName.isNotEmpty
              ? settings.tnsReporterName
              : settings.observerName,
          apiKey: apiKey,
          useSandbox: settings.tnsUseSandbox,
        );
        final result = await ref
            .read(transientSubmissionServiceProvider)
            .submitToTns(detection: d, creds: creds);
        if (mounted) {
          setState(() => _lastAtName = result.success ? result.atName : null);
          if (result.success) {
            context.showSuccessSnackBar(result.message);
          } else {
            context.showErrorSnackBar(result.message);
          }
        }
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('TNS submission failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool?> _confirmTnsSubmit(bool sandbox) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit to TNS?'),
        content: Text(
          sandbox
              ? 'This submits to the TNS SANDBOX (no public record).'
              : 'This submits a LIVE report to the TNS and creates a public, '
                  'permanent AT record visible to the worldwide network. Only '
                  'submit a genuine, confirmed discovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(sandbox ? 'Submit (sandbox)' : 'Submit live'),
          ),
        ],
      ),
    );
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

/// Minimal indenting JSON encoder for the TNS preview (avoids pulling a dep).
class JsonEncoderPretty {
  const JsonEncoderPretty();
  String convert(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
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
    final kindLabel = TransientKind.fromWire(detection.kind).label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceSm,
          vertical: NightshadeTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(color: selected ? colors.primary : colors.border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.checkCircle : LucideIcons.circle,
              size: NightshadeTokens.iconXs,
              color: selected ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: NightshadeTypography.labelStrongSm.copyWith(
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$kindLabel · SNR ${detection.snr.toStringAsFixed(1)}'
                    '${detection.reviewed ? ' · confirmed' : ''}',
                    style: NightshadeTypography.labelQuiet.copyWith(
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
