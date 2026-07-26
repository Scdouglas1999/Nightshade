part of '../flat_wizard_screen.dart';

class _ActionButtons extends ConsumerWidget {
  final FlatWizardMode mode;

  const _ActionButtons({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

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
              children: [
                Icon(LucideIcons.alertCircle, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        color: colors.error),
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
        if (state.isCapturing)
          NightshadeButton(
            label: 'Stop Capture',
            onPressed: notifier.requestCancel,
            variant: ButtonVariant.destructive,
          )
        else
          NightshadeButton(
            key: FlatWizardTutorialKeys.startBtn,
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
