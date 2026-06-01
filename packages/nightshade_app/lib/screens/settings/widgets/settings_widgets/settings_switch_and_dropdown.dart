part of '../settings_widgets.dart';

class SettingsSwitch extends StatefulWidget {
  final bool value;

  final ValueChanged<bool> onChanged;

  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    // If there's a pending write, fire it now so the last toggle isn't lost

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();

      // The pending value is the opposite of the current widget value,

      // since the timer was set to flip it

      widget.onChanged(!widget.value);
    }

    super.dispose();
  }

  void _onTap() {
    final newValue = !widget.value;

    // Cancel any previous pending write

    _debounceTimer?.cancel();

    // Delay the DB write by 300ms; rapid toggles coalesce to the final value

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NightshadeSwitch(
      value: widget.value,
      onChanged: (_) => _onTap(),
    );
  }
}

/// Dropdown selector for settings.

///

/// Compact trailing control sized for [SettingRow]. Styling mirrors

/// [NightshadeDropdown] / theme [InputDecorationTheme] but uses fixed widths

/// for settings layout — migrate to [NightshadeDropdown] when row sizing allows.

/// Dropdown selector for settings rows.
///
/// Compact trailing control for [SettingRow]. Styling mirrors
/// [NightshadeDropdown] (surfaceAlt fill, border, chevron) with fixed widths
/// and optional [itemLabels] for value/label pairs.
class SettingsDropdown extends StatelessWidget {
  final String value;

  final List<String> items;

  final ValueChanged<String?> onChanged;

  final double? width;

  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)

  final bool flexible;

  /// Optional display labels for items. When provided, must have same length

  /// as [items]. The dropdown shows these labels but emits the corresponding

  /// value from [items].

  final List<String>? itemLabels;

  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.isMobile = false,
    this.flexible = false,
    this.itemLabels,
  });

  @override
  Widget build(BuildContext context) {
    final designWidth = width ?? (isMobile ? 120.0 : 140.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);
    final effectiveValue = items.contains(value) ? value : items.first;

    Widget dropdown = NightshadeDropdown(
      value: effectiveValue,
      items: items,
      itemLabels: itemLabels,
      onChanged: onChanged,
      isExpanded: true,
      isDense: true,
    );

    if (flexible) {
      return dropdown;
    }

    return SizedBox(
      width: effectiveWidth,
      child: dropdown,
    );
  }
}

/// Text input field for settings.

///

/// Compact trailing control for [SettingRow]. Styling mirrors

/// [NightshadeTextField] / theme [InputDecorationTheme] with fixed widths.
