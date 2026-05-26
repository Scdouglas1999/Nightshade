//! Bruneton LUT precompute smoke + reference sampling (Task 51).

use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use nightshade_planetarium::renderer::bruneton::{
    precompute_bruneton_luts, readback_texture_2d_rgba_f32, sample_transmittance_rgba,
    transmittance_uv_from_r_mu, PrecomputeConfig, TRANSMITTANCE_TEXTURE_HEIGHT,
    TRANSMITTANCE_TEXTURE_WIDTH,
};

const PRECOMPUTE_BUDGET_MS: u128 = 2000;
const TRANSMITTANCE_EPS: f32 = 0.02;

fn fixture_transmittance_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/bruneton/transmittance.dat")
}

#[test]
fn bruneton_precompute_smoke_under_two_seconds() {
    pollster::block_on(async {
        let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
        let start = Instant::now();
        let luts = precompute_bruneton_luts(device, queue).expect("precompute");
        let elapsed = start.elapsed().as_millis();
        assert!(
            elapsed < PRECOMPUTE_BUDGET_MS,
            "precompute took {elapsed} ms (budget {PRECOMPUTE_BUDGET_MS} ms)"
        );
        assert_eq!(luts.transmittance.width(), TRANSMITTANCE_TEXTURE_WIDTH);
        assert_eq!(luts.transmittance.height(), TRANSMITTANCE_TEXTURE_HEIGHT);
    });
}

#[test]
fn bruneton_transmittance_matches_reference_at_known_angles() {
    pollster::block_on(async {
        let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
        let luts = precompute_bruneton_luts(device.clone(), queue.clone()).expect("precompute");

        let ours = readback_texture_2d_rgba_f32(
            &device,
            &queue,
            &luts.transmittance,
            TRANSMITTANCE_TEXTURE_WIDTH,
            TRANSMITTANCE_TEXTURE_HEIGHT,
        )
        .expect("readback");

        let reference_bytes = fs::read(fixture_transmittance_path()).expect("reference.dat");
        assert_eq!(
            reference_bytes.len(),
            (TRANSMITTANCE_TEXTURE_WIDTH * TRANSMITTANCE_TEXTURE_HEIGHT * 16) as usize
        );
        let reference: Vec<f32> = bytemuck::cast_slice(&reference_bytes).to_vec();

        let config = PrecomputeConfig::earth_demo();
        let cases: [(f64, f64); 4] = [
            (config.bottom_radius_m / config.length_unit_in_meters, 1.0),
            (config.bottom_radius_m / config.length_unit_in_meters, 0.0),
            (
                config.top_radius_m / config.length_unit_in_meters - 0.01,
                0.5,
            ),
            (
                (config.bottom_radius_m + config.top_radius_m) * 0.5 / config.length_unit_in_meters,
                -0.2,
            ),
        ];

        for (r_km, mu) in cases {
            let (u, v) = transmittance_uv_from_r_mu(&config, r_km, mu);
            let got = sample_transmittance_rgba(
                &ours,
                TRANSMITTANCE_TEXTURE_WIDTH,
                TRANSMITTANCE_TEXTURE_HEIGHT,
                u,
                v,
            );
            let expected = sample_transmittance_rgba(
                &reference,
                TRANSMITTANCE_TEXTURE_WIDTH,
                TRANSMITTANCE_TEXTURE_HEIGHT,
                u,
                v,
            );
            for c in 0..3 {
                assert!(
                    (got[c] - expected[c]).abs() < TRANSMITTANCE_EPS,
                    "r={r_km} mu={mu} ch={c}: got {} expected {} (u={u} v={v})",
                    got[c],
                    expected[c]
                );
            }
        }
    });
}
