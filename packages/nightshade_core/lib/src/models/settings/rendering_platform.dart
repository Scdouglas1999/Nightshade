/// Planetarium rendering stack selected in app settings.
///
/// v1 is the legacy `nightshade_planetarium` CustomPainter path (default).
/// v2 is the Rust+wgpu renderer in `nightshade_planetarium_v2`.
enum RenderingPlatform {
  v1,
  v2;

  /// Value persisted in the `app_settings` key-value table (`rendering_platform`).
  String get storageValue => switch (this) {
        RenderingPlatform.v1 => 'v1',
        RenderingPlatform.v2 => 'v2',
      };

  /// Whether planetarium screens should mount the v2 widget tree.
  bool get isV2 => this == RenderingPlatform.v2;

  /// Parse a stored setting value; unknown or missing values default to [v1].
  static RenderingPlatform parseStored(String? value) {
    if (value == null) return RenderingPlatform.v1;
    return switch (value.trim().toLowerCase()) {
      'v2' => RenderingPlatform.v2,
      'v1' => RenderingPlatform.v1,
      _ => RenderingPlatform.v1,
    };
  }
}
