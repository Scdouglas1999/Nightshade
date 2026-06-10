import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../dashboard_layout_provider.dart';
import 'dashboard_widget_registry.dart';

/// Opens the dashboard widget picker as an adaptive modal: a centered,
/// viewport-capped dialog on tablet/desktop and a bottom sheet on a phone.
///
/// This replaces the old `showDialog(WidgetPickerDialog())` call so the picker
/// never renders as a fixed desktop-sized dialog on a narrow phone (rule 9 of
/// the mobile responsive standard).
Future<void> showWidgetPickerModal(BuildContext context) {
  return showAdaptiveModal<void>(
    context: context,
    designWidth: 420,
    designHeight: 640,
    builder: (context) => const WidgetPickerDialog(),
  );
}

/// The dashboard widget picker body.
///
/// Rendered inside [showWidgetPickerModal] which supplies the surrounding
/// chrome (Dialog frame on tablet/desktop, bottom sheet on phone). The body is
/// a titled, scrollable checkbox list that toggles each tile's enabled flag.
class WidgetPickerDialog extends ConsumerWidget {
  const WidgetPickerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final layoutAsync = ref.watch(dashboardLayoutProvider);
    final isPhone = Responsive.isPhone(context);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 16 : 24,
        isPhone ? 8 : 20,
        isPhone ? 16 : 24,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Dashboard Widgets',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: isPhone ? 16 : 20,
              ),
            ),
          ),
          IconButton(
            icon: Icon(NightshadeIcons.close,
                color: colors.textSecondary, size: 20),
            tooltip: 'Close',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );

    final body = layoutAsync.when(
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
            children.add(Divider(color: colors.border, height: 1));
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
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12),
              ),
            ),
          );
        }

        return ListView(
          padding: EdgeInsets.only(bottom: isPhone ? 8 : 12),
          shrinkWrap: true,
          children: children,
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load widgets: $error',
          style: TextStyle(color: colors.textSecondary),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Flexible(child: body),
      ],
    );
  }
}
