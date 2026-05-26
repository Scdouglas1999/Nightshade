import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Search bar widget for filtering annotation objects by name or catalog ID.
class AnnotationSearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const AnnotationSearchBar({
    super.key,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: NightshadeTextField(
        hint: 'Search objects...',
        prefixIcon: LucideIcons.search,
        onChanged: onChanged,
      ),
    );
  }
}
