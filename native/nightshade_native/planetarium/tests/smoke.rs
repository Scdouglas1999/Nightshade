//! Smoke test: confirms the crate's error type works and the build is wired up.

use nightshade_planetarium::PlanetariumError;

#[test]
fn error_displays_platform_message() {
    let e = PlanetariumError::UnsupportedPlatform("haiku");
    assert_eq!(e.to_string(), "platform surface unsupported: haiku");
}
