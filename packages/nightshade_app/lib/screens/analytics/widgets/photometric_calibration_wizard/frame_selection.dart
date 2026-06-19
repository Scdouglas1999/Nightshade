part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardFrameSelection
    on _PhotometricCalibrationWizardState {
  Widget _buildStep1SelectFrame(NightshadeColors colors) {
    final sessions = ref.watch(allSessionsProvider).valueOrNull ?? const [];
    final sessionId = _selectedSessionId ??
        (sessions.isNotEmpty ? sessions.first.id : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select plate-solved frames from a standard star field',
          style: NightshadeTypography.bodyMedium
              .copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          'Choose one or more plate-solved frames captured in a field with '
          'known standard stars (e.g., Landolt fields, Stetson standards). '
          'One frame fits the zero point and color term; selecting frames of '
          'the same field at different altitudes adds airmass spread, which '
          'lets the fit also recover the atmospheric extinction coefficient.',
          style: NightshadeTypography.caption
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        Wrap(
          spacing: NightshadeTokens.spaceLg,
          runSpacing: NightshadeTokens.spaceMd,
          children: [
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Session',
                      style: NightshadeTypography.labelSm
                          .copyWith(color: colors.textSecondary)),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  NightshadeDropdown(
                    isExpanded: true,
                    isDense: true,
                    value: sessionId?.toString(),
                    hint: 'Select session',
                    items: sessions.map((s) => s.id.toString()).toList(),
                    itemLabels: sessions
                        .map((s) => s.name ?? 'Session ${s.id}')
                        .toList(),
                    onChanged: (value) {
                      final id = value == null ? null : int.tryParse(value);
                      if (id == null || id == sessionId) {
                        return;
                      }
                      _update(() {
                        _selectedSessionId = id;
                        _selectedImageIds.clear();
                        _starMatches = const [];
                        _computedCoefficients = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: NightshadeTextField(
                label: 'Filter',
                controller: _filterController,
                hint: 'e.g., V, B, R',
                onChanged: (value) => _update(() => _filterName = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        if (sessionId != null)
          _buildFrameSelector(colors, sessionId)
        else
          Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusLg,
              border: Border.all(color: colors.border.withValues(alpha: 0.3)),
            ),
            child: Text(
              'No imaging sessions found. Capture frames with a standard '
              'star field first.',
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildFrameSelector(NightshadeColors colors, int sessionId) {
    final images = ref.watch(calibrationSessionImagesProvider(sessionId));

    return images.when(
      // Shimmer thumbnail strip matches the frame selector height so the
      // wizard doesn't reflow when the image list resolves.
      loading: () => AdaptiveChartContainer.fixed(
        height:
            _PhotometricCalibrationWizardState._frameSelectorPreferredHeight,
        child: ShimmerLoading(
          child: Row(
            children: List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(
                    right: i == 4 ? 0 : NightshadeTokens.spaceSm),
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      error: (error, _) => Text('Error loading images: $error',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.error)),
      data: (imageList) {
        final solvedImages = imageList
            .where((img) =>
                img.isPlateSolved && img.frameType.toLowerCase() == 'light')
            .toList(growable: false);

        if (solvedImages.isEmpty) {
          return Text(
            'No plate-solved light frames found in the latest session.',
            style: NightshadeTypography.caption
                .copyWith(color: colors.textMuted),
          );
        }

        return AdaptiveChartContainer(
          preferredHeight:
              _PhotometricCalibrationWizardState._frameSelectorPreferredHeight,
          minHeight: 140,
          child: ListView.builder(
            itemCount: solvedImages.length,
            itemBuilder: (context, index) {
              final img = solvedImages[index];
              final isSelected = _selectedImageIds.contains(img.id);
              return ListTile(
                dense: true,
                selected: isSelected,
                selectedColor: colors.primary,
                selectedTileColor:
                    NightshadeDecorations.tintedBadge(colors.primary).color,
                title: Text(
                  img.fileName,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: isSelected ? colors.primary : colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${img.filter ?? "No filter"} | '
                  '${img.exposureDuration.toStringAsFixed(1)}s | '
                  'Stars: ${img.starCount ?? "?"} | '
                  'RA: ${img.solvedRa?.toStringAsFixed(4) ?? "?"} '
                  'Dec: ${img.solvedDec?.toStringAsFixed(4) ?? "?"}',
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                ),
                leading: Icon(
                  isSelected ? LucideIcons.checkCircle2 : LucideIcons.image,
                  color: isSelected ? colors.primary : colors.textMuted,
                  size: NightshadeTokens.iconSm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: NightshadeTokens.borderRadiusLg,
                ),
                onTap: () {
                  _update(() {
                    if (!_selectedImageIds.remove(img.id)) {
                      _selectedImageIds.add(img.id);
                    }
                    if (_filterName.isEmpty && img.filter != null) {
                      _filterName = img.filter!;
                      _filterController.text = img.filter!;
                    }
                    // New frame selection invalidates downstream products.
                    _starMatches = const [];
                    _computedCoefficients = null;
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================================
  // Step 2: Auto-match detected stars to catalog
  // =========================================================================
}
