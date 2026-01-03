import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

class NightshadeTextField extends StatelessWidget {
  final String? initialValue;
  final String? hint;
  final IconData? prefixIcon;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;

  const NightshadeTextField({
    super.key,
    this.initialValue,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 12,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 12,
          color: colors.textMuted,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 16, color: colors.textSecondary)
            : null,
        suffixText: suffix,
        suffixStyle: TextStyle(
          fontSize: 12,
          color: colors.textSecondary,
        ),
        filled: true,
        fillColor: colors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
    );
  }
}





