// Part of ../quick_start_wizard_dialog.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../quick_start_wizard_dialog.dart';

extension _ReviewStep on _QuickStartWizardDialogState {
  // ===========================================================================
  // STEP 5: REVIEW
  // ===========================================================================

  Widget _buildReviewStep(NightshadeColors colors) {
    final enabledFilters = _filterConfigs.where((f) => f.enabled).toList();
    final totalSecs = _estimatedTotalSecs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review your sequence before creating it.',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13),
        ),
        const SizedBox(height: 16),

        // Target summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.target,
          title: 'Target',
          children: [
            _reviewRow(colors, 'Name', _targetNameController.text),
            _reviewRow(colors, 'RA', _raController.text),
            _reviewRow(colors, 'Dec', _decController.text),
          ],
        ),

        const SizedBox(height: 12),

        // Filters summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.camera,
          title:
              'Exposures (${enabledFilters.length} filter${enabledFilters.length != 1 ? "s" : ""})',
          children: enabledFilters.map((f) {
            return _reviewRow(
              colors,
              f.filterName,
              '${f.count}x ${f.exposureSecs.round()}s (${f.binning.label})',
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // Loop summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.repeat,
          title: 'Loop',
          children: [
            _reviewRow(
              colors,
              'Type',
              _loopType == LoopConditionType.count
                  ? '$_loopCount iterations'
                  : _loopType == LoopConditionType.forever
                      ? 'Run forever'
                      : 'While dark',
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Automation summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.settings,
          title: 'Automation',
          children: [
            _reviewRow(colors, 'Autofocus',
                _enableAutofocus ? 'Enabled (HFR-based)' : 'Disabled'),
            _reviewRow(colors, 'Dithering',
                _enableDithering ? '${_ditherPixels.round()}px' : 'Disabled'),
            _reviewRow(colors, 'Meridian Flip',
                _enableMeridianFlip ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Auto-Guide',
                _enableAutoGuide ? 'Enabled' : 'Disabled'),
          ],
        ),

        const SizedBox(height: 12),

        // Safety summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.shield,
          title: 'Safety',
          children: [
            _reviewRow(colors, 'Cool Camera',
                _coolCamera ? '${_coolingTemp.round()}C' : 'Disabled'),
            _reviewRow(
                colors, 'Park on Error', _parkOnError ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Weather Abort',
                _weatherAbort ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Dawn Shutdown',
                _dawnShutdown ? 'Enabled' : 'Disabled'),
          ],
        ),

        const SizedBox(height: 16),

        // Estimated time
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.emphasisSurface(
            colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, color: colors.primary, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated Duration',
                    style:
                        NightshadeTypography.h6.copyWith(color: colors.primary),
                  ),
                  Text(
                    _formatDuration(totalSecs),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: NightshadeTypography.fontSize16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Tree preview
        _buildTreePreview(colors, enabledFilters),
      ],
    );
  }

  Widget _buildReviewSection({
    required NightshadeColors colors,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: NightshadeTypography.labelStrong
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _reviewRow(NightshadeColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTreePreview(
      NightshadeColors colors, List<_FilterExposureConfig> enabledFilters) {
    // Build a visual tree preview of what will be created
    final treeLines = <_TreeLine>[];

    treeLines.add(_TreeLine(
      'Target: ${_targetNameController.text}',
      LucideIcons.target,
      0,
    ));

    if (_coolCamera) {
      treeLines.add(_TreeLine(
          'Cool Camera (${_coolingTemp.round()}C)', LucideIcons.snowflake, 1));
    }
    treeLines.add(_TreeLine('Slew to Target', LucideIcons.compass, 1));
    treeLines.add(_TreeLine('Plate Solve & Center', LucideIcons.crosshair, 1));
    if (_enableAutofocus) {
      treeLines.add(_TreeLine('Autofocus', LucideIcons.focus, 1));
    }
    if (_enableAutoGuide) {
      treeLines.add(_TreeLine('Start Guiding', LucideIcons.crosshair, 1));
    }

    final loopLabel = _loopType == LoopConditionType.count
        ? 'Capture Loop (x$_loopCount)'
        : _loopType == LoopConditionType.forever
            ? 'Capture Loop (forever)'
            : 'Capture Loop (while dark)';
    treeLines.add(_TreeLine(loopLabel, LucideIcons.repeat, 1));

    for (final f in enabledFilters) {
      treeLines.add(_TreeLine(
        '${f.filterName}: ${f.exposureSecs.round()}s',
        LucideIcons.camera,
        2,
      ));
    }
    if (_enableDithering && _enableAutoGuide) {
      treeLines.add(_TreeLine('Dither', LucideIcons.shuffle, 2));
    }

    if (_enableAutoGuide) {
      treeLines.add(_TreeLine('Stop Guiding', LucideIcons.xCircle, 1));
    }
    if (_coolCamera) {
      treeLines.add(_TreeLine('Warm Camera', LucideIcons.flame, 1));
    }
    if (_parkOnError || _dawnShutdown) {
      treeLines.add(_TreeLine('Park Mount', LucideIcons.parkingCircle, 1));
    }

    // Triggers
    if (_enableAutofocus) {
      treeLines
          .add(_TreeLine('HFR Refocus Trigger', LucideIcons.shieldCheck, 1));
    }
    if (_enableMeridianFlip) {
      treeLines.add(_TreeLine('Meridian Flip', LucideIcons.refreshCw, 1));
    }
    if (_weatherAbort) {
      treeLines.add(_TreeLine('Weather Safety', LucideIcons.cloudRain, 1));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sequence Tree Preview',
            style: NightshadeTypography.labelStrongSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          ...treeLines.map((line) {
            return Padding(
              padding: EdgeInsets.only(left: line.depth * 20.0, bottom: 2),
              child: Row(
                children: [
                  Icon(line.icon, color: colors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    line.label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: NightshadeTypography.fontSize12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TreeLine {
  final String label;
  final IconData icon;
  final int depth;

  _TreeLine(this.label, this.icon, this.depth);
}
