import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sequencer/widgets/run_dashboard/frame_detail_dialog.dart';
import 'session_review_controller.dart';
import 'widgets/integration_settings_panel.dart';
import 'widgets/master_library_panel.dart';
import 'widgets/master_preview_view.dart';
import 'widgets/sub_gallery_panel.dart';

/// Session Review / Morning Report.
///
/// The cohesive "review the night" surface: a sub gallery with quality badges +
/// culling, an advanced integration-settings panel with a Re-integrate action,
/// the finished-master viewer, and the multi-night master library. Reached from
/// the run/session/analytics context via the `/session-review` route with a
/// `?session=<id>` or `?target=<id>` query.
class SessionReviewScreen extends ConsumerStatefulWidget {
  final SessionReviewScope scope;

  const SessionReviewScreen({super.key, required this.scope});

  @override
  ConsumerState<SessionReviewScreen> createState() =>
      _SessionReviewScreenState();
}

class _SessionReviewScreenState extends ConsumerState<SessionReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  SessionReviewController get _controller =>
      ref.read(sessionReviewControllerProvider(widget.scope).notifier);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(sessionReviewControllerProvider(widget.scope));

    // Surface controller errors as a toast, once each.
    if (state.error != null && state.error != _lastShownError) {
      _lastShownError = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NightshadeToastHelper.show(
          context: context,
          message: state.error!,
          severity: NightshadeAlertSeverity.error,
        );
      });
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          ScreenHeader(
            title: state.title,
            subtitle: state.loading
                ? 'Loading…'
                : '${state.acceptedCount} accepted · ${state.rejectedCount} rejected',
            icon: NightshadeIcons.image,
            trailing: state.integrating
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Text(
                        'Integrating…',
                        style: NightshadeTypography.bodySm
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                  )
                : NightshadeButton(
                    label: 'Refresh',
                    icon: NightshadeIcons.refresh,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () => _controller.refresh(),
                  ),
          ),
          if (state.lastOutcome != null) _ReadyBanner(outcome: state.lastOutcome!),
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colors.textPrimary,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: colors.primary,
              tabs: const [
                Tab(text: 'Subs'),
                Tab(text: 'Integrate'),
                Tab(text: 'Masters'),
              ],
            ),
          ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildSubsTab(state),
                      _buildIntegrateTab(state),
                      _buildMastersTab(state),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubsTab(SessionReviewState state) {
    return SubGalleryPanel(
      subs: state.lights,
      onTapSub: (image) => FrameDetailDialog.showForFrame(
        context,
        imageId: image.id,
      ),
      onSetAccepted: (id, accepted) => _controller.setAccepted(id, accepted),
      onBulkCull: ({hfrThreshold, qualityThreshold}) async {
        final n = await _controller.bulkReject(
          hfrThreshold: hfrThreshold,
          qualityThreshold: qualityThreshold,
        );
        if (!mounted) return;
        NightshadeToastHelper.show(
          context: context,
          message: n == 0
              ? 'No subs matched the cull threshold.'
              : 'Rejected $n sub${n == 1 ? '' : 's'}.',
          severity: NightshadeAlertSeverity.info,
        );
      },
    );
  }

  Widget _buildIntegrateTab(SessionReviewState state) {
    final colors = NightshadeColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeCard(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: IntegrationSettingsPanel(
              settings: state.settings,
              subCount: state.acceptedCount,
              onChanged: (s) => _controller.updateSettings(s),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: state.lastOutcome == null
                      ? 'Integrate now'
                      : 'Re-integrate',
                  icon: NightshadeIcons.play,
                  isLoading: state.integrating,
                  onPressed: (state.integrating || state.acceptedCount == 0)
                      ? null
                      : () => _controller.integrate(),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              NightshadeButton(
                label: 'Save as default',
                icon: NightshadeIcons.settings,
                variant: ButtonVariant.outline,
                onPressed: state.integrating
                    ? null
                    : () async {
                        await _controller.updateSettings(
                          state.settings,
                          persistAsDefault: true,
                        );
                        if (!mounted) return;
                        NightshadeToastHelper.show(
                          context: context,
                          message: 'Saved as default integration profile.',
                          severity: NightshadeAlertSeverity.success,
                        );
                      },
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          if (state.lastOutcome != null) ...[
            const SectionHeader(title: 'Finished master'),
            const SizedBox(height: NightshadeTokens.spaceSm),
            NightshadeCard(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 460,
                child: MasterPreviewView.fromOutcome(state.lastOutcome!),
              ),
            ),
          ] else
            NightshadeCard(
              variant: CardVariant.subtle,
              padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
              child: Row(
                children: [
                  Icon(NightshadeIcons.info, size: 16, color: colors.info),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      'Run an integration to produce the linear master and '
                      'preview it here.',
                      style: NightshadeTypography.bodySm
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMastersTab(SessionReviewState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: MasterLibraryPanel(
        masters: state.masters,
        acceptedSubCount: state.acceptedCount,
        busy: state.integrating,
        onOpen: (m) => _openMaster(m),
        onAddTonight: (m) async {
          await _controller.addToAccumulatingMaster(master: m);
          if (!mounted) return;
          NightshadeToastHelper.show(
            context: context,
            message: 'Folded tonight\'s subs into ${m.name}.',
            severity: NightshadeAlertSeverity.success,
          );
        },
        onFinalize: (m) async {
          await _controller.finalizeMaster(m);
          if (!mounted) return;
          NightshadeToastHelper.show(
            context: context,
            message: 'Finalized ${m.name}.',
            severity: NightshadeAlertSeverity.success,
          );
        },
        onDelete: (m) => _confirmDelete(m),
        onCreateAccumulating: () => _createAccumulating(state),
      ),
    );
  }

  void _openMaster(IntegratedMaster master) {
    final colors = NightshadeColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        child: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            ctx,
            designMaxWidth: 900,
            designMaxHeight: 700,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScreenHeader(
                title: master.name,
                subtitle:
                    '${master.frameCount} frames · ${formatHms(master.totalIntegrationSeconds)}',
                icon: NightshadeIcons.image,
                trailing: IconButton(
                  icon: Icon(NightshadeIcons.close, color: colors.textPrimary),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              Expanded(child: MasterPreviewView.fromMaster(master)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createAccumulating(SessionReviewState state) async {
    // Offer one master per distinct filter present in the accepted subs.
    final filters = <String?>{
      for (final s in state.acceptedLights) s.filter,
    }.toList();
    String? chosenFilter;
    if (filters.length > 1) {
      chosenFilter = await showDialog<String?>(
        context: context,
        builder: (ctx) => _FilterPickerDialog(filters: filters),
      );
      if (chosenFilter == _kCancelSentinel) return;
    } else {
      chosenFilter = filters.isNotEmpty ? filters.first : null;
    }
    final id = await _controller.createAccumulatingMaster(filter: chosenFilter);
    if (!mounted || id == null) return;
    NightshadeToastHelper.show(
      context: context,
      message: 'Started a new accumulating master.',
      severity: NightshadeAlertSeverity.success,
    );
  }

  Future<void> _confirmDelete(IntegratedMaster master) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete master?'),
        content: Text(
          'Delete "${master.name}" and its fold records? The on-disk FITS / '
          'preview files are left untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteMaster(master);
  }
}

const String _kCancelSentinel = '__cancel__';

class _FilterPickerDialog extends StatelessWidget {
  final List<String?> filters;
  const _FilterPickerDialog({required this.filters});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Master for which filter?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: filters
            .map(
              (f) => ListTile(
                title: Text(f ?? 'No filter'),
                onTap: () => Navigator.of(context).pop(f),
              ),
            )
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_kCancelSentinel),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// "Your image is ready" banner shown after a successful integration.
class _ReadyBanner extends StatelessWidget {
  final PostSessionIntegrationOutcome outcome;
  const _ReadyBanner({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final r = outcome.result;
    return Container(
      width: double.infinity,
      color: colors.success.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.check, size: 18, color: colors.success),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              'Your image is ready — ${r.framesIntegrated} frames integrated, '
              '${r.framesRejected} rejected. See the Integrate tab.',
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
