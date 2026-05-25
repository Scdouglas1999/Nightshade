import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/settings/rendering_platform.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

void main() {
  test('AppSettingsState defaults rendering platform to v1', () {
    const settings = AppSettingsState();
    expect(settings.renderingPlatform, RenderingPlatform.v1);
  });

  test('RenderingPlatform.parseStored accepts v1 and v2', () {
    expect(RenderingPlatform.parseStored('v1'), RenderingPlatform.v1);
    expect(RenderingPlatform.parseStored('v2'), RenderingPlatform.v2);
    expect(RenderingPlatform.parseStored('V2'), RenderingPlatform.v2);
    expect(RenderingPlatform.parseStored(null), RenderingPlatform.v1);
    expect(RenderingPlatform.parseStored('unknown'), RenderingPlatform.v1);
  });

  test('storageValue round-trips parseStored', () {
    for (final platform in RenderingPlatform.values) {
      expect(
        RenderingPlatform.parseStored(platform.storageValue),
        platform,
      );
    }
  });

  test('copyWith updates renderingPlatform', () {
    const initial = AppSettingsState();
    final v2 = initial.copyWith(renderingPlatform: RenderingPlatform.v2);
    expect(v2.renderingPlatform, RenderingPlatform.v2);
    expect(initial.renderingPlatform, RenderingPlatform.v1);
  });
}
