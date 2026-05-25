// Wave 8 — Conversational sequence builder dialog.
//
// Reachable from the sequencer toolbar's accent sparkle icon (next to
// the green Smart Night sparkle). Flow:
//
//   1. Empty state — if no provider is configured, the dialog shows a
//      "Configure an AI provider in Settings" CTA + an explanation of
//      the feature.
//   2. Input state — large multi-line prompt textarea + a row of
//      toggles (restrict to candidates, max hours cap, include flats,
//      use scheduler). User clicks Submit.
//   3. Working state — spinner + round-counter ("Asking the model…
//      round 1 of up to 4"). The service performs the self-correction
//      loop here.
//   4. Result state — shows the generated sequence's high-level
//      summary (target list + integration time + node count) plus a
//      validation badge. Three actions:
//        a. Refine — text input + re-run with the prior context.
//        b. Accept — load the sequence into the editor and close.
//        c. Discard — close without loading.
//
// All wire-level errors raise a snackbar inline with a Retry button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

class ConversationalBuilderDialog extends ConsumerStatefulWidget {
  /// Optional candidate suggestions to seed the prompt with — the
  /// dialog forwards these to the LLM so it has a list of "things the
  /// user cares about tonight" to draw from.
  final List<TargetSuggestion> seedCandidates;

  const ConversationalBuilderDialog({
    super.key,
    this.seedCandidates = const [],
  });

  @override
  ConsumerState<ConversationalBuilderDialog> createState() =>
      _ConversationalBuilderDialogState();
}

enum _DialogStage { input, working, result }

class _ConversationalBuilderDialogState
    extends ConsumerState<ConversationalBuilderDialog> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _refineController = TextEditingController();

  _DialogStage _stage = _DialogStage.input;
  ConversationalBuildResult? _result;
  ConversationalHistoryEntry? _historyEntry;
  String? _error;
  int _activeRound = 0;

  /// Options reflected in the dialog toggles.
  ConversationalBuilderOptions _options = const ConversationalBuilderOptions();

  @override
  void dispose() {
    _promptController.dispose();
    _refineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 880,
          designMaxHeight: 720,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(colors),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Row(
      children: [
        Icon(LucideIcons.wand2, size: 22, color: colors.primary),
        const SizedBox(width: 10),
        Text(
          'Conversational Builder',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'AI',
            style: TextStyle(
              fontSize: 10,
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 18),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildBody(NightshadeColors colors) {
    final configuredAsync = ref.watch(llmAssistantConfiguredProvider);
    return configuredAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          'Failed to load AI configuration: $err',
          style: TextStyle(color: colors.error),
        ),
      ),
      data: (configured) {
        if (!configured) return _buildUnconfiguredEmptyState(colors);
        switch (_stage) {
          case _DialogStage.input:
            return _buildInputStage(colors);
          case _DialogStage.working:
            return _buildWorkingStage(colors);
          case _DialogStage.result:
            return _buildResultStage(colors);
        }
      },
    );
  }

  // -------------------------------------------------------------------------
  // Empty / configured states
  // -------------------------------------------------------------------------

  Widget _buildUnconfiguredEmptyState(NightshadeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cpu, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No AI provider configured',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The conversational builder uses a Large Language Model to '
              'turn a free-text request like "Plan 4 hours on the Heart '
              'Nebula tonight, narrowband HOO" into a fully-formed '
              'Nightshade sequence.\n\n'
              'Configure a provider in Settings → AI Assistant to enable '
              'this feature. You can use a cloud service (OpenAI, '
              'Anthropic) or run a local model (Ollama) for full privacy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(LucideIcons.settings, size: 14),
              label: const Text('Open AI Assistant Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Input stage
  // -------------------------------------------------------------------------

  Widget _buildInputStage(NightshadeColors colors) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Describe what you want to image tonight…',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            minLines: 5,
            maxLines: 10,
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. "Plan a 4-hour session on the Heart Nebula '
                  'tonight, narrowband HOO with my Ha + OIII filters, '
                  'autofocus every 30 minutes, dither every 2 frames."',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(2000),
            ],
          ),
          const SizedBox(height: 16),
          _buildOptionsRow(colors),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: NightshadeDecorations.iconChip(
                colors.error,
                borderRadius: BorderRadius.circular(6),
                borderAlpha: 0.3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.alertCircle, size: 14, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                          fontSize: 12, color: colors.error, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(LucideIcons.send, size: 14),
                label: const Text('Build sequence'),
                onPressed:
                    _promptController.text.trim().isEmpty ? null : _submit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.seedCandidates.isNotEmpty) _buildCandidatePreview(colors),
        ],
      ),
    );
  }

  Widget _buildOptionsRow(NightshadeColors colors) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _OptionChip(
          colors: colors,
          icon: LucideIcons.listFilter,
          label: 'Restrict to my observing list',
          selected: _options.restrictToCandidates,
          onTap: () => setState(() {
            _options = _options.copyWith(
                restrictToCandidates: !_options.restrictToCandidates);
          }),
        ),
        _OptionChip(
          colors: colors,
          icon: LucideIcons.aperture,
          label: 'Append flats',
          selected: _options.includeFlatsAtEnd,
          onTap: () => setState(() {
            _options = _options.copyWith(
                includeFlatsAtEnd: !_options.includeFlatsAtEnd);
          }),
        ),
        _OptionChip(
          colors: colors,
          icon: LucideIcons.layers,
          label: 'Use Target Scheduler',
          selected: _options.useSchedulerForMultiTarget,
          onTap: () => setState(() {
            _options = _options.copyWith(
                useSchedulerForMultiTarget:
                    !_options.useSchedulerForMultiTarget);
          }),
        ),
        _MaxHoursPicker(
          colors: colors,
          value: _options.maxSessionHours,
          onChanged: (v) => setState(() {
            _options = _options.copyWith(maxSessionHours: v);
          }),
        ),
      ],
    );
  }

  Widget _buildCandidatePreview(NightshadeColors colors) {
    final preview =
        widget.seedCandidates.take(5).map((c) => c.targetName).join(', ');
    final more = widget.seedCandidates.length > 5
        ? ' (+${widget.seedCandidates.length - 5} more)'
        : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.list, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Candidate targets the AI will see: $preview$more',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Working stage
  // -------------------------------------------------------------------------

  Widget _buildWorkingStage(NightshadeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _activeRound <= 1
                ? 'Asking the model…'
                : 'Asking the model (round $_activeRound of up to 4)…',
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'This can take 10–60s. Self-correction rounds run when the '
            'first reply fails validation.',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Result stage
  // -------------------------------------------------------------------------

  Widget _buildResultStage(NightshadeColors colors) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultHeader(colors, result),
          const SizedBox(height: 16),
          if (result.sequence != null)
            _buildSequenceSummary(colors, result.sequence!),
          if (result.validationIssues.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildIssuesPanel(colors, result),
          ],
          const SizedBox(height: 16),
          _buildRefinePanel(colors, result),
          const SizedBox(height: 16),
          _buildResultActions(colors, result),
          const SizedBox(height: 16),
          _buildRawDetails(colors, result),
        ],
      ),
    );
  }

  Widget _buildResultHeader(
      NightshadeColors colors, ConversationalBuildResult result) {
    final color = result.isValid ? colors.success : colors.warning;
    final icon =
        result.isValid ? LucideIcons.checkCircle : LucideIcons.alertTriangle;
    final headline =
        result.isValid ? 'Sequence ready' : 'Sequence built with warnings';
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          headline,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        if (result.totalUsage != null)
          Text(
            formatUsage(result.totalUsage!),
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            '${result.rounds} ${result.rounds == 1 ? "round" : "rounds"}',
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceSummary(NightshadeColors colors, Sequence sequence) {
    final estimate = sequence.estimateWithOverhead();
    final targets =
        sequence.nodes.values.whereType<TargetHeaderNode>().toList();
    final smartExposures =
        sequence.nodes.values.whereType<SmartExposureNode>().toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sequence.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          if (sequence.description.isNotEmpty)
            Text(
              sequence.description,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _summaryStat(
                colors: colors,
                icon: LucideIcons.target,
                label: 'Targets',
                value: targets.length.toString(),
              ),
              _summaryStat(
                colors: colors,
                icon: LucideIcons.camera,
                label: 'Frames',
                value: sequence.totalExposures.toString(),
              ),
              _summaryStat(
                colors: colors,
                icon: LucideIcons.clock,
                label: 'Integration',
                value:
                    '${(sequence.totalIntegrationSecs / 3600).toStringAsFixed(1)}h',
              ),
              _summaryStat(
                colors: colors,
                icon: LucideIcons.timer,
                label: 'Wall clock',
                value:
                    '${(estimate.totalEstimatedSecs / 3600).toStringAsFixed(1)}h',
              ),
              _summaryStat(
                colors: colors,
                icon: LucideIcons.layers,
                label: 'Nodes',
                value: sequence.nodes.length.toString(),
              ),
            ],
          ),
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Targets',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            for (final t in targets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(LucideIcons.dot, size: 14, color: colors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${t.targetName}'
                        '${t.minAltitude != null ? " (min alt ${t.minAltitude!.toStringAsFixed(0)}°)" : ""}',
                        style:
                            TextStyle(fontSize: 12, color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (smartExposures.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Smart Exposures',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            for (final se in smartExposures)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  se.plans
                      .map((p) =>
                          '${p.filterName}: ${p.count}x${p.durationSecs.toStringAsFixed(0)}s')
                      .join('  /  '),
                  style: TextStyle(fontSize: 12, color: colors.textPrimary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _summaryStat({
    required NightshadeColors colors,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildIssuesPanel(
      NightshadeColors colors, ConversationalBuildResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Validation issues (${result.validationIssues.length})',
        ),
        const SizedBox(height: 8),
        for (final issue in result.validationIssues.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• [${issue.severity.name}] ${issue.title} — ${issue.description}',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
        if (result.validationIssues.length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '… and ${result.validationIssues.length - 8} more',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildRefinePanel(
      NightshadeColors colors, ConversationalBuildResult result) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.messageCircle,
                  size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Refine',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _refineController,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. "Use 300s subs instead of 180s" or "Drop SII '
                  'and rebalance the budget".',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(LucideIcons.rotateCcw, size: 14),
              label: const Text('Refine'),
              onPressed: _refineController.text.trim().isEmpty
                  ? null
                  : () => _submit(refineFrom: result),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultActions(
      NightshadeColors colors, ConversationalBuildResult result) {
    final canAccept = result.sequence != null;
    return Row(
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              _stage = _DialogStage.input;
              _result = null;
              _historyEntry = null;
            });
          },
          child: const Text('Start over'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Discard'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          icon: const Icon(LucideIcons.download, size: 14),
          label: const Text('Accept and load'),
          onPressed: canAccept ? () => _accept(result) : null,
        ),
      ],
    );
  }

  Widget _buildRawDetails(
      NightshadeColors colors, ConversationalBuildResult result) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          'Show conversation',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        tilePadding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < result.rawReplies.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Round ${i + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                result.rawReplies[i].length > 4000
                    ? '${result.rawReplies[i].substring(0, 4000)}\n…(truncated)…'
                    : result.rawReplies[i],
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Submit / accept handlers
  // -------------------------------------------------------------------------

  Future<void> _submit({ConversationalBuildResult? refineFrom}) async {
    final userPrompt = refineFrom == null
        ? _promptController.text.trim()
        : _refineController.text.trim();
    if (userPrompt.isEmpty) return;

    final profile = ref.read(activeEquipmentProfileProvider);
    if (profile == null) {
      setState(() => _error =
          'No active equipment profile — select one on the Equipment screen.');
      return;
    }

    setState(() {
      _stage = _DialogStage.working;
      _error = null;
      _activeRound = 1;
    });

    // Build the runtime provider.
    final settings = ref.read(llmSettingsServiceProvider);
    final factory = ref.read(llmProviderFactoryProvider);
    final provider = await settings.buildActiveProvider(factory: factory);
    if (provider == null) {
      if (!mounted) return;
      setState(() {
        _stage = _DialogStage.input;
        _error = 'AI provider is not configured. Open Settings to set up.';
      });
      return;
    }

    final settingsAsync = ref.read(appSettingsProvider).valueOrNull;
    final latitude = settingsAsync?.latitude;
    final longitude = settingsAsync?.longitude;

    final fileService = ref.read(sequenceFileServiceProvider);
    final logging = ref.read(loggingServiceProvider);

    final builder = ConversationalBuilderService(
      provider: provider,
      fileService: fileService,
      logging: logging,
    );

    final context = ConversationalBuilderContext(
      profile: profile,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
      candidates: widget.seedCandidates,
      options: _options,
      refineFrom: refineFrom,
    );

    ConversationalBuildResult? result;
    String? error;
    try {
      result = await builder.buildSequenceFromPrompt(
        userPrompt: userPrompt,
        context: context,
      );
    } on ConversationalBuilderUnconfigured catch (e) {
      error = e.message;
    } on ConversationalBuilderException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Unexpected error: $e';
    } finally {
      provider.close();
    }

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _stage = _DialogStage.input;
        _error = error ?? 'Unknown error.';
      });
      return;
    }

    // Persist a history entry — also when validation failed, so the
    // user can see what they asked.
    final history = ref.read(conversationalHistoryServiceProvider);
    final settingsRecord = await settings.load();
    final entry = await history.record(
      userPrompt: userPrompt,
      providerName: provider.name,
      providerKind: settingsRecord.activeKind,
      rounds: result.rounds,
      successful: result.isValid,
      usage: result.totalUsage,
      issueRecords: result.validationIssues
          .map((i) => {
                'severity': i.severity.name,
                'category': i.category.name,
                'title': i.title,
                'description': i.description,
                if (i.resolutionHint != null)
                  'resolution_hint': i.resolutionHint,
              })
          .toList(),
      acceptedSequenceId: null,
      systemPrompt: result.systemPrompt,
      rawReplies: result.rawReplies,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _historyEntry = entry;
      _stage = _DialogStage.result;
    });
  }

  Future<void> _accept(ConversationalBuildResult result) async {
    final sequence = result.sequence;
    if (sequence == null) return;
    try {
      final notifier = ref.read(currentSequenceProvider.notifier);
      notifier.loadSequence(sequence, discardUnsaved: true);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not load sequence: $e');
      return;
    }
    // Update history with the accepted sequence id.
    final entry = _historyEntry;
    if (entry != null) {
      try {
        await ref
            .read(conversationalHistoryServiceProvider)
            .markAccepted(entry.id, sequence.id);
      } catch (_) {
        // History update is best-effort.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    context.showSuccessSnackBar(
      'Sequence "${sequence.name}" loaded — ${sequence.totalExposures} '
      'frames, ${(sequence.totalIntegrationSecs / 3600).toStringAsFixed(1)}h '
      'integration.',
    );
  }
}

class _OptionChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? colors.primary : colors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusXl),
                ).color
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.4)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaxHoursPicker extends StatelessWidget {
  final NightshadeColors colors;
  final double? value;
  final ValueChanged<double?> onChanged;

  const _MaxHoursPicker({
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = <double?>[null, 2.0, 3.0, 4.0, 6.0, 8.0];
    return Wrap(
      spacing: 4,
      children: [
        for (final opt in options)
          ChoiceChip(
            label: Text(
              opt == null ? 'No cap' : '${opt.toStringAsFixed(0)}h',
              style: const TextStyle(fontSize: 11),
            ),
            selected: value == opt,
            onSelected: (_) => onChanged(opt),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
