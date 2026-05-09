import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Search bar widget for filtering annotation objects by name or catalog ID.
class AnnotationSearchBar extends StatelessWidget {
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  const AnnotationSearchBar({
    super.key,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search objects...',
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
          prefixIcon: Icon(
            LucideIcons.search,
            size: 16,
            color: colors.textMuted,
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: colors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.primary),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
