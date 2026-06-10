part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardFrameSelection
    on _PhotometricCalibrationWizardState {
  Widget _buildStep1SelectFrame(NightshadeColors colors) {
    final sessions = ref.watch(allSessionsProvider).valueOrNull ?? const [];
    final sessionId = sessions.isNotEmpty ? sessions.first.id : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a plate-solved frame from a standard star field',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: NightshadeTypography.fontSize14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a frame captured in a field with known standard stars '
          '(e.g., Landolt fields, Stetson standards). The frame must be '
          'plate-solved so star positions can be matched to catalog entries.',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Filter: ', style: TextStyle(color: colors.textSecondary)),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize13),
                decoration: InputDecoration(
                  hintText: 'e.g., V, B, R',
                  hintStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: NightshadeTypography.fontSize13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                onChanged: (value) => _update(() => _filterName = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessionId != null)
          _buildFrameSelector(colors, sessionId)
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border.withValues(alpha: 0.3)),
            ),
            child: Text(
              'No imaging sessions found. Capture frames with a standard '
              'star field first.',
              style: TextStyle(
                  color: colors.textMuted,
                  fontSize: NightshadeTypography.fontSize12),
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
                padding: EdgeInsets.only(right: i == 4 ? 0 : 8),
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
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
            style: TextStyle(
                color: colors.textMuted,
                fontSize: NightshadeTypography.fontSize12),
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
              final isSelected = _selectedImageId == img.id;
              return ListTile(
                dense: true,
                selected: isSelected,
                selectedColor: colors.primary,
                selectedTileColor:
                    NightshadeDecorations.tintedBadge(colors.primary).color,
                title: Text(
                  img.fileName,
                  style: TextStyle(
                    color: isSelected ? colors.primary : colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize13,
                  ),
                ),
                subtitle: Text(
                  '${img.filter ?? "No filter"} | '
                  '${img.exposureDuration.toStringAsFixed(1)}s | '
                  'Stars: ${img.starCount ?? "?"} | '
                  'RA: ${img.solvedRa?.toStringAsFixed(4) ?? "?"} '
                  'Dec: ${img.solvedDec?.toStringAsFixed(4) ?? "?"}',
                  style: TextStyle(
                      color: colors.textMuted,
                      fontSize: NightshadeTypography.fontSize11),
                ),
                leading: Icon(
                  isSelected ? LucideIcons.checkCircle2 : LucideIcons.image,
                  color: isSelected ? colors.primary : colors.textMuted,
                  size: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                onTap: () {
                  _update(() {
                    _selectedImageId = img.id;
                    if (_filterName.isEmpty && img.filter != null) {
                      _filterName = img.filter!;
                    }
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
