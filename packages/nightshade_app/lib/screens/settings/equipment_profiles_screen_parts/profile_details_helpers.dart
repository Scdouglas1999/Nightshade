part of '../equipment_profiles_screen.dart';

extension _ProfileDetailsHelpers on _ProfileDetailsState {
bool _hasDeviceAssignments() {
    return widget.profile.cameraId != null ||
        widget.profile.mountId != null ||
        widget.profile.focuserId != null ||
        widget.profile.filterWheelId != null ||
        widget.profile.guiderId != null ||
        widget.profile.rotatorId != null ||
        widget.profile.domeId != null ||
        widget.profile.weatherId != null;
  }

  bool _hasDeviceAssignmentsForEdit() {
    if (widget.isEditing) {
      return _cameraId != null ||
          _mountId != null ||
          _focuserId != null ||
          _filterWheelId != null ||
          _guiderId != null ||
          _rotatorId != null ||
          _domeId != null ||
          _weatherId != null;
    }
    return _hasDeviceAssignments();
  }

  Widget? _buildDeviceAssignment(
      String type, String? deviceId, void Function(String?) onClear) {
    if (deviceId == null) return null;

    final displayId = formatDeviceId(deviceId);

    if (widget.isEditing) {
      return _EditableDeviceChip(
        type: type,
        id: displayId,
        fullId: deviceId,
        onClear: () => onClear(null),
      );
    }

    return _DeviceChip(type: type, id: displayId);
  }

  bool _hasFilters() {
    if (widget.isEditing) {
      return _filterControllers.any((c) => c.text.trim().isNotEmpty);
    }
    return widget.profile.filterNames.isNotEmpty;
  }

  List<Widget> _buildFilterOffsetRows() {
    // Get current filter names (from controllers if editing, otherwise from profile)
    final filterNames = widget.isEditing
        ? _filterControllers
            .map((c) => c.text.trim())
            .where((f) => f.isNotEmpty)
            .toList()
        : widget.profile.filterNames;

    final filterNameWidth = widget.isMobile ? 100.0 : 120.0;
    final inputWidth = widget.isMobile ? 90.0 : 100.0;

    return filterNames.map((filterName) {
      // Ensure we have a controller for this filter
      if (!_filterOffsetControllers.containsKey(filterName)) {
        _filterOffsetControllers[filterName] = TextEditingController(text: '0');
      }
      final controller = _filterOffsetControllers[filterName]!;
      final offset = widget.profile.filterFocusOffsets[filterName] ?? 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              flex: widget.isMobile ? 2 : 1,
              child: Container(
                constraints: BoxConstraints(minWidth: filterNameWidth),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isMobile ? 10 : 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: NightshadeColors.of(context).surfaceAlt,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
                child: Text(
                  filterName,
                  style: TextStyle(
                    color: NightshadeColors.of(context).textPrimary,
                    fontSize: widget.isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: widget.isMobile ? 10 : 12),
            if (widget.isEditing)
              SizedBox(
                width: inputWidth,
                child: TextFormField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                  ],
                  style: TextStyle(
                    color: NightshadeColors.of(context).textPrimary,
                    fontSize: widget.isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize14,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: widget.isMobile ? 6 : 8,
                      vertical: 8,
                    ),
                    suffixText: widget.isMobile ? 'st' : 'steps',
                    suffixStyle: TextStyle(
                      color: NightshadeColors.of(context).textMuted,
                      fontSize: widget.isMobile ? NightshadeTypography.fontSize11 : NightshadeTypography.fontSize12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide: BorderSide(color: NightshadeColors.of(context).border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide: BorderSide(color: NightshadeColors.of(context).border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide:
                          BorderSide(color: NightshadeColors.of(context).primary, width: 2),
                    ),
                  ),
                ),
              )
            else
              Text(
                '$offset steps',
                style: TextStyle(
                  color: NightshadeColors.of(context).textSecondary,
                  fontSize: widget.isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize14,
                ),
              ),
          ],
        ),
      );
    }).toList();
  }
}
