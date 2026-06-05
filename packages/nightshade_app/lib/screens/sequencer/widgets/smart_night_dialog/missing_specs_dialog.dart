part of '../smart_night_dialog.dart';

class SmartNightMissingSpecsDialog extends ConsumerStatefulWidget {
  final String? cameraName;
  final int? defaultGain;
  final NightshadeColors colors;

  const SmartNightMissingSpecsDialog({
    super.key,
    required this.colors,
    this.cameraName,
    this.defaultGain,
  });

  @override
  ConsumerState<SmartNightMissingSpecsDialog> createState() =>
      _SmartNightMissingSpecsDialogState();
}

class _SmartNightMissingSpecsDialogState
    extends ConsumerState<SmartNightMissingSpecsDialog> {
  late final TextEditingController _modelController;
  late final TextEditingController _gainController;
  final _pixelSizeController = TextEditingController();
  final _readNoiseController = TextEditingController();
  final _fullWellController = TextEditingController();
  final _qeController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(
      text: widget.cameraName?.trim().isNotEmpty == true
          ? widget.cameraName!.trim()
          : '',
    );
    _gainController = TextEditingController(
      text: (widget.defaultGain ?? 100).toString(),
    );
  }

  @override
  void dispose() {
    _modelController.dispose();
    _gainController.dispose();
    _pixelSizeController.dispose();
    _readNoiseController.dispose();
    _fullWellController.dispose();
    _qeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Camera specs needed',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 460,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Smart Night can make better exposure recommendations with the camera values below.',
                style: TextStyle(color: colors.textSecondary, fontSize: NightshadeTypography.fontSize13),
              ),
              const SizedBox(height: 16),
              _specField(
                controller: _modelController,
                label: 'Camera model',
                keyName: 'smart-night-spec-model',
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _gainController,
                label: 'Gain',
                keyName: 'smart-night-spec-gain',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _pixelSizeController,
                label: 'Pixel size (microns)',
                keyName: 'smart-night-spec-pixel-size',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _readNoiseController,
                label: 'Read noise (e-)',
                keyName: 'smart-night-spec-read-noise',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _fullWellController,
                label: 'Full well (e-)',
                keyName: 'smart-night-spec-full-well',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _qeController,
                label: 'QE peak (0-1)',
                keyName: 'smart-night-spec-qe',
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: NightshadeTypography.fontSize12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save specs'),
        ),
      ],
    );
  }

  Widget _specField({
    required TextEditingController controller,
    required String label,
    required String keyName,
    TextInputType? keyboardType,
  }) {
    return TextField(
      key: Key(keyName),
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _save() async {
    final model = _modelController.text.trim();
    final gain = int.tryParse(_gainController.text.trim());
    final pixelSize = double.tryParse(_pixelSizeController.text.trim());
    final readNoise = double.tryParse(_readNoiseController.text.trim());
    final fullWell = double.tryParse(_fullWellController.text.trim());
    final qe = double.tryParse(_qeController.text.trim());

    if (model.isEmpty ||
        gain == null ||
        pixelSize == null ||
        pixelSize <= 0 ||
        readNoise == null ||
        readNoise <= 0 ||
        fullWell == null ||
        fullWell <= 0 ||
        qe == null ||
        qe <= 0 ||
        qe > 1) {
      setState(() {
        _error =
            'Enter a model plus positive gain, pixel size, read noise, full well, and QE between 0 and 1.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final dao = ref.read(settingsDaoProvider);
      final raw =
          await dao.getSetting(HardwareSpecsService.cameraOverridesSettingKey);
      final existing = raw == null || raw.trim().isEmpty
          ? <CameraHardwareSpec>[]
          : HardwareSpecsService.cameraOverridesFromJson(jsonDecode(raw))
              .toList();
      final alias = widget.cameraName?.trim();
      final spec = CameraHardwareSpec(
        model: model,
        aliases: alias == null ||
                alias.isEmpty ||
                alias.toLowerCase() == model.toLowerCase()
            ? const []
            : [alias],
        pixelSizeMicrons: pixelSize,
        qePeak: qe,
        defaultGain: gain,
        gainPoints: [
          CameraGainPoint(
            gain: gain,
            readNoiseE: readNoise,
            fullWellE: fullWell,
          ),
        ],
      );
      existing.removeWhere(
        (entry) => entry.model.toLowerCase() == model.toLowerCase(),
      );
      existing.add(spec);
      await dao.setSetting(
        HardwareSpecsService.cameraOverridesSettingKey,
        jsonEncode(existing.map((entry) => entry.toJson()).toList()),
      );
      ref.invalidate(smartNightExposureContextProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save camera specs: $e';
      });
    }
  }
}
