import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/planetarium_driver.dart';
import '../providers/planetarium_handle_provider.dart';

/// Minimal v2 sky viewport hosting the Rust-rendered [Texture].
///
/// Watches [planetariumHandleProvider] and resizes the native render target
/// when layout constraints change.
class InteractiveSkyView extends ConsumerStatefulWidget {
  const InteractiveSkyView({super.key});

  @override
  ConsumerState<InteractiveSkyView> createState() => _InteractiveSkyViewState();
}

class _InteractiveSkyViewState extends ConsumerState<InteractiveSkyView> {
  Size? _lastLayoutSize;
  double? _lastDevicePixelRatio;
  int _textureId = 0;

  void _scheduleResize(
    PlanetariumDriver driver,
    Size layoutSize,
    double devicePixelRatio,
  ) {
    if (layoutSize.width <= 0 ||
        layoutSize.height <= 0 ||
        !layoutSize.isFinite) {
      return;
    }
    if (_lastLayoutSize == layoutSize &&
        _lastDevicePixelRatio == devicePixelRatio) {
      return;
    }
    _lastLayoutSize = layoutSize;
    _lastDevicePixelRatio = devicePixelRatio;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final tex = driver.resize(
        width: layoutSize.width.round(),
        height: layoutSize.height.round(),
        devicePixelRatio: devicePixelRatio,
      );
      if (tex != _textureId) {
        setState(() => _textureId = tex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncHandle = ref.watch(planetariumHandleProvider);

    return asyncHandle.when(
      loading: () => const ColoredBox(color: Colors.black),
      error: (error, _) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            '$error',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (driver) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final layoutSize = constraints.biggest;
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            _scheduleResize(driver, layoutSize, devicePixelRatio);

            final textureId =
                _textureId != 0 ? _textureId : driver.textureId;
            if (textureId <= 0) {
              return const ColoredBox(color: Colors.black);
            }
            return Texture(textureId: textureId);
          },
        );
      },
    );
  }
}
