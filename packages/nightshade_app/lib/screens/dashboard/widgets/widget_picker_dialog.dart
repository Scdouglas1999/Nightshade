import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../dashboard_layout_provider.dart';
import 'dashboard_widget_registry.dart';

class WidgetPickerDialog extends ConsumerWidget {
  const WidgetPickerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final layoutAsync = ref.watch(dashboardLayoutProvider);
    final screenSize = MediaQuery.of(context).size;
    // Responsive dialog width: 90% of screen on small screens, max 420px on larger
    final dialogWidth = screenSize.width < 500
        ? screenSize.width * 0.9
        : 420.0;

    return AlertDialog(
      backgroundColor: colors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width < 400 ? 16 : 40,
        vertical: 24,
      ),
      title: Text(
        'Dashboard Widgets',
        style: TextStyle(color: colors.textPrimary, fontSize: screenSize.width < 400 ? 16 : 20),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          minWidth: 280,
          maxHeight: screenSize.height * 0.7,
        ),
        child: layoutAsync.when(
          data: (layout) {
            final tilesById = {
              for (final tile in layout.tiles) tile.widgetId: tile,
            };

            final children = <Widget>[];
            for (var i = 0; i < dashboardWidgetRegistry.length; i++) {
              final definition = dashboardWidgetRegistry[i];
              final tile = tilesById[definition.id];
              final enabled = tile?.enabled ?? false;

              if (i > 0) {
                children.add(Divider(color: colors.border));
              }

              children.add(
                CheckboxListTile(
                  value: enabled,
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(dashboardLayoutProvider.notifier)
                        .setTileEnabled(definition.id, value);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    definition.title,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    definition.subtitle,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            'Failed to load widgets: $error',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}
