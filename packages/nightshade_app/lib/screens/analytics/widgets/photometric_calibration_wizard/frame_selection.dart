part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardFrameSelection
    on _PhotometricCalibrationWizardState {
  Widget _buildStep1SelectFrame(NightshadeColors colors) {
    final sessionsAsync = ref.watch(allSessionsProvider);

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
        sessionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusLg,
              border: Border.all(color: colors.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: NightshadeTokens.iconSm, color: colors.error),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Expanded(
                  child: Text(
                    'Could not load imaging sessions: $error',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.caption
                        .copyWith(color: colors.error),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(allSessionsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (sessions) => _buildFrameSourceControls(colors, sessions),
        ),
      ],
    );
  }

  Widget _buildFrameSourceControls(
    NightshadeColors colors,
    List<ImagingSession> sessions,
  ) {
    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(color: colors.border.withValues(alpha: 0.3)),
        ),
        child: Text(
          'No imaging sessions found. Capture frames with a standard '
          'star field first.',
          style: NightshadeTypography.caption.copyWith(color: colors.textMuted),
        ),
      );
    }

    final selectedSessionExists =
        sessions.any((session) => session.id == _selectedSessionId);
    final sessionId =
        selectedSessionExists ? _selectedSessionId! : sessions.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    value: sessionId.toString(),
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
                        _retireAsyncWork();
                        _selectedSessionId = id;
                        _selectedImageIds.clear();
                        _starMatches = const [];
                        _computedCoefficients = null;
                        _fitAttempted = false;
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
                onChanged: _changeFilter,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        _buildFrameSelector(colors, sessionId),
      ],
    );
  }

  void _changeFilter(String value) {
    final changed =
        value.trim().toLowerCase() != _filterName.trim().toLowerCase();
    _update(() {
      _filterName = value;
      if (changed && _selectedImageIds.isNotEmpty) {
        _selectedImageIds.clear();
      }
      if (changed) {
        _retireAsyncWork();
        _starMatches = const [];
        _computedCoefficients = null;
        _fitAttempted = false;
      }
    });
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
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            separatorBuilder: (_, __) =>
                const SizedBox(width: NightshadeTokens.spaceSm),
            itemBuilder: (_, __) => SizedBox(
              width: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: NightshadeTokens.borderRadiusMd,
                ),
              ),
            ),
          ),
        ),
      ),
      error: (error, _) => Row(
        children: [
          Expanded(
            child: Text(
              'Error loading images: $error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.error),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.invalidate(calibrationSessionImagesProvider(sessionId)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (imageList) {
        final solvedImages = imageList
            .where((img) =>
                img.isPlateSolved && img.frameType.toLowerCase() == 'light')
            .toList(growable: false);

        if (solvedImages.isEmpty) {
          return Text(
            'No plate-solved light frames found in the selected session.',
            style:
                NightshadeTypography.caption.copyWith(color: colors.textMuted),
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
              final frameFilter = img.filter?.trim();
              final filterMismatch = !isSelected &&
                  _filterName.trim().isNotEmpty &&
                  frameFilter != null &&
                  frameFilter.isNotEmpty &&
                  frameFilter.toLowerCase() != _filterName.trim().toLowerCase();
              return Material(
                type: MaterialType.transparency,
                child: ListTile(
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
                    if (filterMismatch) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${img.fileName} uses filter $frameFilter; this '
                            'calibration is for ${_filterName.trim()}.',
                          ),
                        ),
                      );
                      return;
                    }
                    _update(() {
                      _retireAsyncWork();
                      // Anchor the implicit default session as soon as the user
                      // selects a frame. A newly-started session may then move
                      // to the front of the history stream without hiding this
                      // selection under a different session.
                      _selectedSessionId = sessionId;
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
                      _fitAttempted = false;
                    });
                  },
                ),
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
