part of '../flat_wizard_screen.dart';

class _ActionButtons extends ConsumerWidget {
  final FlatWizardMode mode;

  const _ActionButtons({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    // The terminal error is a verdict ("no frames were saved"); on its own it
    // names no cause and no next step. Pair it with the measured diagnosis and
    // with the per-filter reason the solver already produced.
    final diagnosis =
        state.errorMessage != null ? diagnoseFlatFailure(state) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertCircle, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.errorMessage!,
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize13,
                            color: colors.error),
                      ),
                      if (diagnosis != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          diagnosis.reason,
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          diagnosis.nextStep,
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: notifier.clearError,
                  icon: const Icon(LucideIcons.x, size: 16),
                  color: colors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // The solver's own per-filter reason. It was written to
        // FlatWizardState.warningMessage and never read by anything, so a run
        // that partly failed showed no explanation at all.
        if (state.warningMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 18, color: colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.warningMessage!,
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        color: colors.warning),
                  ),
                ),
                IconButton(
                  onPressed: notifier.clearWarning,
                  icon: const Icon(LucideIcons.x, size: 16),
                  color: colors.warning,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (state.isCapturing)
          // The stop is cooperative: the run aborts the exposure in flight and
          // finishes the frame it is on, which is seconds of a screen that
          // otherwise looks exactly like a click that never landed.
          NightshadeButton(
            label: notifier.cancelRequested ? 'Stopping…' : 'Stop Capture',
            onPressed: notifier.cancelRequested ? null : notifier.requestCancel,
            variant: ButtonVariant.destructive,
          )
        else
          NightshadeButton(
            // A tutorial key is a GlobalKey, so it may be attached to at most
            // ONE live element. All three mode tabs mount this widget (the
            // TabBarView keeps the outgoing tab alive across a switch), which
            // duplicated the key and threw "specified multiple times in the
            // widget tree" the moment the operator changed tab. The selected
            // mode is the one the tour should spotlight, so only it claims it.
            key: mode == state.mode ? FlatWizardTutorialKeys.startBtn : null,
            label:
                mode == FlatWizardMode.quick ? 'Start Capture' : 'Start Batch',
            onPressed: () => _startCapture(context, ref),
          ),
      ],
    );
  }

  Future<void> _startCapture(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(flatWizardProvider.notifier);
    final state = ref.read(flatWizardProvider);
    if (state.isCapturing || !notifier.reserveStartPrompt()) return;
    final authority = ref.read(backendProvider);

    try {
      // Ensure a save path is set — prompt for one if missing.
      if (state.globalSettings.savePath == null ||
          state.globalSettings.savePath!.isEmpty) {
        final result = await SavePathDialog.show(
          context,
          currentPath: state.globalSettings.savePath,
          createDateSubfolder: state.globalSettings.createDateSubfolder,
          createFilterSubfolders: state.globalSettings.createFilterSubfolders,
        );

        if (result == null || !context.mounted) return;
        if (!identical(ref.read(backendProvider), authority)) {
          notifier.setWarningMessage(
            'The imaging host changed while choosing the flat-frame folder. '
            'Choose it again for the current host.',
          );
          return;
        }

        final latest = ref.read(flatWizardProvider).globalSettings;
        notifier.updateGlobalSettings(
          latest.copyWith(
            savePath: result.path,
            createDateSubfolder: result.createDateSubfolder,
            createFilterSubfolders: result.createFilterSubfolders,
          ),
        );
      }

      if (!context.mounted ||
          !identical(ref.read(backendProvider), authority)) {
        return;
      }

      // Hand the reservation directly to runCapture. Releasing immediately
      // before the call is safe because runCapture takes its own latch
      // synchronously before its first await.
      notifier.releaseStartPrompt();
      await notifier.runCapture();
    } catch (error) {
      if (context.mounted && identical(ref.read(backendProvider), authority)) {
        notifier.setErrorMessage('Could not start flat capture: $error');
      }
    } finally {
      notifier.releaseStartPrompt();
    }
  }
}
