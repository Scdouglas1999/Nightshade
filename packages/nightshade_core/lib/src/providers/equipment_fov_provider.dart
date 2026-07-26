import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/optical_config.dart';
import 'equipment/rotator_state_provider.dart';
import 'profiles_provider.dart';

const Object _equipmentFovUnset = Object();

/// Equipment sensor field of view for sky/planetarium overlays.
class EquipmentFovState {
  const EquipmentFovState({
    this.widthDegrees,
    this.heightDegrees,
    this.rotationDegrees = 0,
  });

  /// Sensor FOV width in degrees, or null when unknown.
  final double? widthDegrees;

  /// Sensor FOV height in degrees, or null when unknown.
  final double? heightDegrees;

  /// Camera rotation in degrees (field derotation / manual framing).
  final double rotationDegrees;

  bool get hasFov =>
      widthDegrees != null &&
      heightDegrees != null &&
      widthDegrees! > 0 &&
      heightDegrees! > 0;

  EquipmentFovState copyWith({
    Object? widthDegrees = _equipmentFovUnset,
    Object? heightDegrees = _equipmentFovUnset,
    double? rotationDegrees,
  }) {
    return EquipmentFovState(
      widthDegrees: identical(widthDegrees, _equipmentFovUnset)
          ? this.widthDegrees
          : widthDegrees as double?,
      heightDegrees: identical(heightDegrees, _equipmentFovUnset)
          ? this.heightDegrees
          : heightDegrees as double?,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EquipmentFovState &&
          widthDegrees == other.widthDegrees &&
          heightDegrees == other.heightDegrees &&
          rotationDegrees == other.rotationDegrees;

  @override
  int get hashCode => Object.hash(widthDegrees, heightDegrees, rotationDegrees);
}

class EquipmentFovNotifier extends StateNotifier<EquipmentFovState> {
  EquipmentFovNotifier(this._ref, {bool bindSources = true})
    : super(const EquipmentFovState()) {
    if (!bindSources) {
      return;
    }
    _ref.listen<OpticalConfig?>(opticalConfigProvider, (_, config) {
      _applyOpticalConfig(config);
    }, fireImmediately: true);
    _ref.listen(rotatorStateProvider, (_, rotator) {
      final position = rotator.position;
      if (position != null) {
        state = state.copyWith(rotationDegrees: position % 360);
      }
    });
  }

  final Ref _ref;

  void _applyOpticalConfig(OpticalConfig? config) {
    final fov = config?.fieldOfView;
    if (fov == null) {
      state = state.copyWith(widthDegrees: null, heightDegrees: null);
      return;
    }
    state = state.copyWith(widthDegrees: fov.$1, heightDegrees: fov.$2);
  }

  /// Override rotation (for example framing assistant slider).
  void setRotation(double rotationDegrees) {
    state = state.copyWith(rotationDegrees: rotationDegrees % 360);
  }
}

/// Active equipment FOV dimensions and rotation for planetarium overlays.
final equipmentFovProvider =
    StateNotifierProvider<EquipmentFovNotifier, EquipmentFovState>((ref) {
      return EquipmentFovNotifier(ref);
    });
