part of '../science_provider.dart';

class SciencePhotometrySelectionNotifier
    extends AsyncNotifier<SciencePhotometrySelection> {
  static const _enabledKey = 'science.photometry.differential_active';
  static const _targetKey = 'science.photometry.target_anchor';
  static const _comparisonsKey = 'science.photometry.comparison_anchors';

  @override
  Future<SciencePhotometrySelection> build() async {
    final settings = await _loadScienceSettingsMap(ref);
    final enabled = _parseBool(settings[_enabledKey], false);
    final target = _decodeAnchor(settings[_targetKey]);
    final comparisons = _decodeAnchors(settings[_comparisonsKey], maxItems: 8);

    return SciencePhotometrySelection(
      differentialEnabled: enabled,
      target: target,
      comparisons: comparisons,
    );
  }

  Future<void> setDifferentialEnabled(bool enabled) async {
    await _writeScienceSettings(ref, {_enabledKey: enabled.toString()});
    state = AsyncData(
      (state.value ?? const SciencePhotometrySelection())
          .copyWith(differentialEnabled: enabled),
    );
  }

  Future<void> setTarget(PhotometryAnchor? target) async {
    final value = target == null ? '' : jsonEncode(target.toJson());

    final current = state.value ?? const SciencePhotometrySelection();
    final comparisons = current.comparisons
        .where((entry) => entry.objectId != target?.objectId)
        .toList(growable: false);

    await _writeScienceSettings(ref, {
      _targetKey: value,
      _comparisonsKey:
          jsonEncode(comparisons.map((entry) => entry.toJson()).toList()),
    });

    state = AsyncData(
      current.copyWith(
        target: target,
        clearTarget: target == null,
        comparisons: comparisons,
      ),
    );
  }

  Future<void> toggleComparison(
    PhotometryAnchor anchor, {
    int maxComparisons = 8,
  }) async {
    final current = state.value ?? const SciencePhotometrySelection();
    final mutable = current.comparisons.toList(growable: true);

    final existingIndex =
        mutable.indexWhere((entry) => entry.objectId == anchor.objectId);
    if (existingIndex >= 0) {
      mutable.removeAt(existingIndex);
    } else if (mutable.length < maxComparisons) {
      mutable.add(anchor);
    }

    final filtered = mutable
        .where((entry) => entry.objectId != current.target?.objectId)
        .toList(growable: false);

    await _writeScienceSettings(ref, {
      _comparisonsKey:
          jsonEncode(filtered.map((entry) => entry.toJson()).toList()),
    });
    state = AsyncData(current.copyWith(comparisons: filtered));
  }

  Future<void> clearComparisons() async {
    await _writeScienceSettings(ref, {_comparisonsKey: '[]'});
    final current = state.value ?? const SciencePhotometrySelection();
    state = AsyncData(current.copyWith(comparisons: const []));
  }

  Future<void> clearAll() async {
    await _writeScienceSettings(ref, {
      _enabledKey: 'false',
      _targetKey: '',
      _comparisonsKey: '[]',
    });
    state = const AsyncData(SciencePhotometrySelection());
  }

  bool _parseBool(String? value, bool fallback) {
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value.toLowerCase() == 'true';
  }

  PhotometryAnchor? _decodeAnchor(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PhotometryAnchor.fromJson(decoded);
      }
      if (decoded is Map) {
        return PhotometryAnchor.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (error, stack) {
      developer.log(
        'SciencePhotometrySelectionNotifier: failed to decode target anchor '
        'from persisted JSON "$raw": $error',
        name: 'SciencePhotometrySelectionNotifier',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
    }
    return null;
  }

  List<PhotometryAnchor> _decodeAnchors(
    String? raw, {
    int maxItems = 8,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final anchors = <PhotometryAnchor>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          anchors.add(PhotometryAnchor.fromJson(item));
        } else if (item is Map) {
          anchors.add(PhotometryAnchor.fromJson(item.cast<String, dynamic>()));
        }
        if (anchors.length >= maxItems) {
          break;
        }
      }
      return anchors;
    } catch (error, stack) {
      developer.log(
        'SciencePhotometrySelectionNotifier: failed to decode comparison anchors '
        'from persisted JSON "$raw": $error',
        name: 'SciencePhotometrySelectionNotifier',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return const [];
    }
  }
}

final sciencePhotometrySelectionProvider = AsyncNotifierProvider<
    SciencePhotometrySelectionNotifier, SciencePhotometrySelection>(
  SciencePhotometrySelectionNotifier.new,
);

final activePhotometryTargetObjectIdProvider = Provider<String>((ref) {
  final selection = ref.watch(sciencePhotometrySelectionProvider).valueOrNull;
  return selection?.target?.objectId ?? 'target_primary';
});

final scienceModeStateProvider =
    StateProvider<ScienceModeState>((_) => const ScienceModeState());

final scienceOverlayStateProvider =
    StateProvider<ScienceOverlayState>((_) => const ScienceOverlayState());
