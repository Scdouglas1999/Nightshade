part of '../settings_widgets.dart';

class SettingsTextInput extends StatefulWidget {
  final TextEditingController controller;

  final String? hint;

  final double? width;

  final bool obscure;

  final ValueChanged<String>? onChanged;

  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)

  final bool flexible;

  const SettingsTextInput({
    super.key,
    required this.controller,
    this.hint,
    this.width,
    this.obscure = false,
    this.onChanged,
    this.isMobile = false,
    this.flexible = false,
  });

  @override
  State<SettingsTextInput> createState() => _SettingsTextInputState();
}

class _SettingsTextInputState extends State<SettingsTextInput> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final designWidth = widget.width ?? (widget.isMobile ? 140.0 : 160.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);

    Widget input = NightshadeTextField(
      controller: widget.controller,
      hint: widget.hint,
      onChanged: widget.onChanged,
      obscureText: widget.obscure && _obscured,
      suffixWidget: widget.obscure
          ? GestureDetector(
              onTap: () => setState(() => _obscured = !_obscured),
              child: Padding(
                padding: const EdgeInsets.only(right: NightshadeTokens.spaceSm),
                child: Icon(
                  _obscured ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: NightshadeTokens.iconXs,
                  color: context.nightshadeColors.textMuted,
                ),
              ),
            )
          : null,
    );

    if (widget.flexible) {
      return input;
    }

    return SizedBox(
      width: effectiveWidth,
      child: input,
    );
  }
}

/// Number input field for settings.

class SettingsNumberInput extends StatelessWidget {
  final TextEditingController controller;

  final String suffix;

  final double min;

  final double max;

  final int decimals;

  final ValueChanged<double> onChanged;

  final double? width;

  final bool isMobile;

  const SettingsNumberInput({
    super.key,
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    this.width,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final designWidth = width ?? (isMobile ? 100.0 : 120.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);

    return SizedBox(
      width: effectiveWidth,
      child: NightshadeTextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        textAlign: TextAlign.right,
        suffix: suffix,
        onChanged: (value) {
          final parsed = double.tryParse(value);

          if (parsed != null) {
            final clamped = parsed.clamp(min, max);

            onChanged(clamped);
          }
        },
      ),
    );
  }
}

/// Color picker for accent color selection.
