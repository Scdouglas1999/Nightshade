import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../planetarium_screen.dart';
import 'sidebar_shared_widgets.dart';

class CatalogTab extends ConsumerWidget {
  final NightshadeColors colors;

  const CatalogTab({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dsos = ref.watch(loadedDsosProvider);

    return dsos.when(
      data: (objects) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: objects.length,
        itemBuilder: (context, index) {
          final dso = objects[index];
          final (displayName, catalogTag) = getDsoDisplayInfo(dso);
          return TargetCard(
            name: displayName,
            catalog: catalogTag,
            type: dsoTypeName(dso.type),
            altitude: dso.magnitude?.toStringAsFixed(1) ?? '-',
            transit: 'mag',
            colors: colors,
            onTap: () {
              ref.read(selectedObjectProvider.notifier).selectObject(dso);
              ref.read(skyViewStateProvider.notifier).lookAt(dso.coordinates);
            },
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: colors.error)),
      ),
    );
  }
}
