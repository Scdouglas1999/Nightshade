import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/hardware/hardware_preset_picker_dialog.dart';
import '../../../widgets/help/field_help_label.dart';
import '../utils/profile_save_errors.dart';
import '../../accessible_dropdown.dart';
import '../../../utils/count_label.dart';

part 'profile_editor_dialog/profile_data_operations.dart';
part 'profile_editor_dialog/shell_and_identity.dart';
part 'profile_editor_dialog/optical_and_devices.dart';
part 'profile_editor_dialog/filters_and_camera_defaults.dart';
part 'profile_editor_dialog/helper_widgets.dart';

/// Stable keys for the profile editor's inline field errors.
///
/// Kept as constants (not an enum) because they double as the map keys the
/// section builders read, and widget tests match on them.
abstract final class ProfileEditorField {
  static const focalLength = 'focalLength';
  static const reducer = 'reducer';
  static const aperture = 'aperture';
  static const gain = 'gain';
  static const offset = 'offset';
  static const coolingTarget = 'coolingTarget';
  static const centeringExposure = 'centeringExposure';
}

/// Single-page profile editor dialog replacing the multi-step wizard.
/// Allows creating new profiles or editing existing ones.
class ProfileEditorDialog extends ConsumerStatefulWidget {
  /// The profile to edit, or null to create a new profile.
  final EquipmentProfileModel? profile;

  const ProfileEditorDialog({super.key, this.profile});

  /// Show the profile editor.
  ///
  /// On a phone (`width < 600`) this is a full-screen route — the editor is a
  /// long, multi-section form, so a centered dialog would be cramped. On
  /// tablet/desktop it stays the centered, viewport-capped dialog.
  /// Returns true if a profile was created/updated, false/null if cancelled.
  static Future<bool?> show(BuildContext context,
      {EquipmentProfileModel? profile}) {
    if (Responsive.isPhone(context)) {
      return Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => ProfileEditorDialog(profile: profile),
        ),
      );
    }
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProfileEditorDialog(profile: profile),
    );
  }

  @override
  ConsumerState<ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<ProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Inline validation error for the Profile Name field. Set by [_validateForm]
  // when the trimmed name is blank or too long, cleared as soon as the user
  // edits the field.
  String? _nameError;

  /// Per-field inline validation errors, keyed by the constants in
  /// [ProfileEditorField]. Every field's error renders inline: a snackbar sits
  /// OUTSIDE and BELOW the dialog, dimmed by the modal barrier to ~2.00:1
  /// contrast against the 4.5:1 WCAG AA wants for body text, so it is not a
  /// readable way to report which field is wrong.
  final Map<String, String?> _fieldErrors = <String, String?>{};

  /// Errors that belong to no single field (optical-train cross-check, per-filter
  /// row problems). Rendered as a persistent banner INSIDE the dialog so the
  /// feedback cannot be dismissed by a timeout or dimmed by the scrim.
  List<String> _formErrors = const <String>[];

  /// Clears the inline error for [field] as soon as the user edits it, matching
  /// the name field's existing behaviour.
  void clearFieldError(String field) {
    if (_fieldErrors[field] == null) return;
    setState(() => _fieldErrors.remove(field));
  }

  // Track which sections are expanded
  final Map<String, bool> _expandedSections = {
    'identity': true,
    'optical': true,
    'devices': true,
    'filters': true,
    'camera': true,
  };

  // Section 1: Profile Identity
  final _nameController = TextEditingController();
  String _selectedIcon = '';
  Color? _selectedColor;
  bool _isDefault = false;

  // Section 2: Optical Train
  //
  // `_focalLengthController` holds the OTA's NATIVE focal length and
  // `_reducerController` the reducer/barlow multiplier; the profile's
  // `focalLength` column is their product (see [_effectiveFocalLengthMm]).
  final _telescopeNameController = TextEditingController();
  final _focalLengthController = TextEditingController();
  final _reducerController = TextEditingController();
  final _apertureController = TextEditingController();

  // Section 3: Devices
  final _cameraNameController = TextEditingController();
  final _mountNameController = TextEditingController();
  final _focuserNameController = TextEditingController();
  final _filterWheelNameController = TextEditingController();
  final _guiderNameController = TextEditingController();
  final _rotatorNameController = TextEditingController();
  // Dome/weather/cover-calibrator have no persisted friendly-name column, so
  // their rows show only the device id (no name controller).
  final _safetyMonitorNameController = TextEditingController();
  final _switchNameController = TextEditingController();

  String? _cameraId;
  String? _mountId;
  String? _focuserId;
  String? _filterWheelId;
  String? _guiderId;
  String? _rotatorId;
  String? _domeId;
  String? _weatherId;
  String? _safetyMonitorId;
  String? _switchId;
  String? _coverCalibratorId;

  // Section 4: Filters (dynamic list)
  final List<_FilterControllerPair> _filterControllers = [];

  // Section 5: Camera Defaults
  final _gainController = TextEditingController();
  final _offsetController = TextEditingController();
  int _binning = 1;
  final _coolingTargetController = TextEditingController();
  bool _coolOnConnect = false;
  final _centeringExposureController = TextEditingController();

  // Auto-detect state for the camera's SDK-reported gain/offset.
  // `null` means "not queried yet". An empty struct (all-None) means
  // "SDK reported nothing" and is displayed as such.
  CameraRecommendedSettings? _recommendedSettings;
  bool _isQueryingRecommendation = false;

  // Available icons for profile customization
  static const List<String> _availableIcons = [
    '',
    '\u{1F52D}', // Telescope emoji
    '\u{1F319}', // Moon emoji
    '\u{1FA90}', // Ringed planet emoji
    '\u{2B50}', // Star emoji
    '\u{1F4F7}', // Camera emoji
    '\u{1F534}', // Red circle
    '\u{1F535}', // Blue circle
    '\u{1F7E2}', // Green circle
    '\u{1F7E1}', // Yellow circle
  ];

  // Available accent colors
  static const List<Color> _accentColors = [
    Color(0xFF5B9EC4), // Cyan-blue (default)
    Color(0xFF3A9BC4), // Sky
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFEAB308), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFF4A7FB8), // Blue
  ];

  @override
  void initState() {
    super.initState();
    _initializeFromProfile();
  }

  void _initializeFromProfile() {
    final profile = widget.profile;
    if (profile != null) {
      // Section 1: Identity
      _nameController.text = profile.name;
      _selectedIcon = profile.profileIcon ?? '';
      _selectedColor =
          profile.profileColor != null ? Color(profile.profileColor!) : null;
      _isDefault = profile.isDefault;

      // Section 2: Optical Train
      //
      // The profile carries the optical train as a PAIR: `telescopeFocalLength`
      // is the OTA's native focal length and `focalLength` is what the rig
      // actually images at (post reducer/barlow) — it is `focalLength` that
      // reaches the FITS FOCALLEN card, the plate-solve scale hint, the framing
      // FOV and the guider px->arcsec conversion. The two must stay distinct:
      // writing one number into both collapses a reducer'd profile back to its
      // native focal length on any save. The row has no reducer column, so the
      // reducer is reconstructed from the ratio the pair already encodes and
      // the pair round-trips.
      _telescopeNameController.text = profile.telescopeName ?? '';
      final nativeFocalLength = profile.telescopeFocalLength != null &&
              profile.telescopeFocalLength! > 0
          ? profile.telescopeFocalLength!
          : (profile.focalLength > 0 ? profile.focalLength : null);
      if (nativeFocalLength != null) {
        _focalLengthController.text = nativeFocalLength.toString();
      }
      _reducerController.text = _formatReducer(
        nativeFocalLength != null && profile.focalLength > 0
            ? _roundOptic(profile.focalLength / nativeFocalLength)
            : 1.0,
      );
      if (profile.telescopeAperture != null && profile.telescopeAperture! > 0) {
        _apertureController.text = profile.telescopeAperture!.toString();
      } else if (profile.aperture > 0) {
        _apertureController.text = profile.aperture.toString();
      }

      // Section 3: Devices
      _cameraId = profile.cameraId;
      _cameraNameController.text = profile.cameraName ?? '';
      _mountId = profile.mountId;
      _mountNameController.text = profile.mountName ?? '';
      _focuserId = profile.focuserId;
      _focuserNameController.text = profile.focuserName ?? '';
      _filterWheelId = profile.filterWheelId;
      _filterWheelNameController.text = profile.filterWheelName ?? '';
      _guiderId = profile.guiderId;
      _guiderNameController.text = profile.guiderName ?? '';
      _rotatorId = profile.rotatorId;
      _rotatorNameController.text = profile.rotatorName ?? '';
      _domeId = profile.domeId;
      _weatherId = profile.weatherId;
      _safetyMonitorId = profile.safetyMonitorId;
      _safetyMonitorNameController.text = profile.safetyMonitorName ?? '';
      _switchId = profile.switchId;
      _switchNameController.text = profile.switchName ?? '';
      _coverCalibratorId = profile.coverCalibratorId;

      // Section 4: Filters
      for (int i = 0; i < profile.filterNames.length; i++) {
        final offset = profile.filterFocusOffsets[profile.filterNames[i]] ?? 0;
        _filterControllers.add(_FilterControllerPair(
          nameController: TextEditingController(text: profile.filterNames[i]),
          offsetController: TextEditingController(text: offset.toString()),
        ));
      }

      // Section 5: Camera Defaults
      if (profile.defaultGain != null) {
        _gainController.text = profile.defaultGain!.toString();
      }
      if (profile.defaultOffset != null) {
        _offsetController.text = profile.defaultOffset!.toString();
      }
      _binning = profile.defaultBinX;
      if (profile.defaultCoolingTemp != null) {
        _coolingTargetController.text = profile.defaultCoolingTemp!.toString();
      }
      _coolOnConnect = profile.coolOnConnect;
      if (profile.defaultCenteringExposure != null) {
        _centeringExposureController.text =
            profile.defaultCenteringExposure!.toString();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _telescopeNameController.dispose();
    _focalLengthController.dispose();
    _reducerController.dispose();
    _apertureController.dispose();
    _cameraNameController.dispose();
    _mountNameController.dispose();
    _focuserNameController.dispose();
    _filterWheelNameController.dispose();
    _guiderNameController.dispose();
    _rotatorNameController.dispose();
    _safetyMonitorNameController.dispose();
    _switchNameController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    _coolingTargetController.dispose();
    _centeringExposureController.dispose();
    for (final pair in _filterControllers) {
      pair.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final isEditing = widget.profile != null;
    final isPhone = Responsive.isPhone(context);

    final content = Column(
      mainAxisSize: isPhone ? MainAxisSize.max : MainAxisSize.min,
      children: [
        // Header
        _buildHeader(colors, theme, isEditing),

        // Scrollable content
        Flexible(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildValidationBanner(colors),
                  _buildIdentitySection(colors, theme),
                  const SizedBox(height: 16),
                  _buildOpticalTrainSection(colors, theme),
                  const SizedBox(height: 16),
                  _buildDevicesSection(colors, theme),
                  if (_filterWheelId != null) ...[
                    const SizedBox(height: 16),
                    _buildFiltersSection(colors, theme),
                  ],
                  const SizedBox(height: 16),
                  _buildCameraDefaultsSection(colors, theme),
                ],
              ),
            ),
          ),
        ),

        // Footer
        _buildFooter(colors),
      ],
    );

    // Phone: the editor is presented as a full-screen route (see [show]). Fill
    // the screen with a Scaffold + SafeArea instead of a small centered card.
    if (isPhone) {
      return PopScope(
        canPop: !_isSaving,
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(child: content),
        ),
      );
    }

    // Tablet/desktop: a centered, viewport-capped dialog card.
    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: dialogMaxWidth(context, 600),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                // absolute: drop-shadow tone is a theme-independent black scrim
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}
