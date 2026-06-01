part of '../science_provider.dart';

class ScienceVisualizationPrefsNotifier
    extends AsyncNotifier<ScienceVisualizationPrefs> {
  static const _overlayOpacityKey = 'science.overlay.opacity';
  static const _liveGridRowsKey = 'science.overlay.live_grid_rows';
  static const _liveGridColsKey = 'science.overlay.live_grid_cols';
  static const _analysisGridRowsKey = 'science.overlay.analysis_grid_rows';
  static const _analysisGridColsKey = 'science.overlay.analysis_grid_cols';

  @override
  Future<ScienceVisualizationPrefs> build() async {
    final raw = await _loadScienceSettingsMap(ref);

    return ScienceVisualizationPrefs(
      overlayOpacity: _parseDouble(raw[_overlayOpacityKey], 0.35)
          .clamp(0.05, 0.95)
          .toDouble(),
      liveGridRows: _parseInt(raw[_liveGridRowsKey], 12).clamp(4, 64),
      liveGridCols: _parseInt(raw[_liveGridColsKey], 16).clamp(4, 64),
      analysisGridRows: _parseInt(raw[_analysisGridRowsKey], 24).clamp(4, 96),
      analysisGridCols: _parseInt(raw[_analysisGridColsKey], 32).clamp(4, 96),
    );
  }

  Future<void> savePrefs(ScienceVisualizationPrefs prefs) async {
    await _writeScienceSettings(ref, {
      _overlayOpacityKey: prefs.overlayOpacity.toString(),
      _liveGridRowsKey: prefs.liveGridRows.toString(),
      _liveGridColsKey: prefs.liveGridCols.toString(),
      _analysisGridRowsKey: prefs.analysisGridRows.toString(),
      _analysisGridColsKey: prefs.analysisGridCols.toString(),
    });
    state = AsyncData(prefs);
  }

  double _parseDouble(String? value, double fallback) {
    final parsed = value == null ? null : double.tryParse(value);
    return parsed ?? fallback;
  }

  int _parseInt(String? value, int fallback) {
    final parsed = value == null ? null : int.tryParse(value);
    return parsed ?? fallback;
  }
}

final scienceVisualizationPrefsProvider = AsyncNotifierProvider<
    ScienceVisualizationPrefsNotifier, ScienceVisualizationPrefs>(
  ScienceVisualizationPrefsNotifier.new,
);
