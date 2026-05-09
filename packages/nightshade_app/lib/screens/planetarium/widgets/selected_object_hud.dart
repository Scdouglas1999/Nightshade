import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../planetarium_screen.dart';
import 'object_info_popup.dart';

class SelectedObjectHud extends ConsumerWidget {
  final NightshadeColors colors;
  final VoidCallback onSlew;

  const SelectedObjectHud({
    super.key,
    required this.colors,
    required this.onSlew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedState = ref.watch(selectedObjectProvider);
    final selectedObject = selectedState.object;

    if (selectedObject == null || selectedObject is! DeepSkyObject) {
      return const SizedBox.shrink();
    }

    final (displayName, catalogTag) = getDsoDisplayInfo(selectedObject);
    final typeName = selectedObject.type.toString().split('.').last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Object Info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: colors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      catalogTag,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                typeName.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // Slew Button
          PopupActionButton(
            icon: LucideIcons.crosshair,
            label: 'Slew',
            isPrimary: true,
            colors: colors,
            onTap: onSlew,
          ),
        ],
      ),
    );
  }
}
