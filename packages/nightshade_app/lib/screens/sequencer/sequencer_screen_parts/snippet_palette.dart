part of '../sequencer_screen.dart';

class _SnippetPaletteContent extends ConsumerWidget {
  final NightshadeColors colors;

  const _SnippetPaletteContent({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnippetPalette(
      colors: colors,
      onSnippetTap: (snippet) {
        // Trust-patch §B: insertSnippet can throw
        // SnippetDeserializationException for unknown node types and
        // SequenceLockedException while a run is in flight. Both must
        // be caught with user-visible feedback — pre-patch they would
        // pop a red Flutter error overlay. The mutator helper handles
        // both as a structured dialog + snackbar.
        withSequenceMutation(
          context,
          ref,
          operationName: 'Insert Snippet',
          action: () async {
            final selectedId = ref.read(selectedNodeIdProvider);
            final profile = ref.read(activeEquipmentProfileProvider);
            ref.read(currentSequenceProvider.notifier).insertSnippet(
                  snippet,
                  parentId: selectedId,
                  profileFilterNames: profile?.filterNames,
                );
          },
        );
      },
    );
  }
}

/// A panel that can collapse to a thin icon strip or expand to full content
