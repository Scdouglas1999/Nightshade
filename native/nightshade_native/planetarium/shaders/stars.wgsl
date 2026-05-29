// Star instanced quads — design §5.2 (ICRS→view→projection, PSF, B−V color).
// PSF size + tone mapping ported from v1 SkyRenderer (_magnitudeToRadius / _magnitudeToBrightness).
// Twinkle: sin perturbation in the fragment shader (v1 sky_renderer), gated by config + altitude.

struct StarUniforms {
    icrs_to_view: mat4x4<f32>,
    proj_scale: vec2<f32>,
    mag_limit: f32,
    psf_scale: f32,
    twinkle_phase: f32,
    twinkle_enabled: f32,
    viewport_pixels: vec2<f32>,
    icrs_to_horizontal: mat3x3<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: StarUniforms;

struct VsIn {
    @location(0) corner: vec2<f32>,
    @location(1) icrs_dir: vec3<f32>,
    @location(2) mag: f32,
    @location(3) bv: f32,
    @location(4) flags: u32,
}

struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) mag: f32,
    @location(2) bv: f32,
    @location(3) flags: u32,
    @location(4) alt_rad: f32,
    @location(5) star_phase: f32,
}

const MIN_COSC: f32 = 0.01;
const OFF_CLIP: vec4<f32> = vec4<f32>(0.0, 0.0, -2.0, 1.0);
// Minimum on-screen radius for a star quad. 0.5 px (the previous floor)
// produces a sub-pixel quad for any star fainter than ~mag 4 — the
// Gaussian PSF then falls below the alpha-discard threshold for every
// fragment, so the star renders to nothing even though it's in the
// instance buffer. Bumping the floor to 1.4 keeps every visible star
// at >=1 pixel of coverage, matching Stellarium's "always at least one
// pixel" behaviour at default zoom.
const PSF_RADIUS_MIN: f32 = 1.4;
const PSF_RADIUS_MAX: f32 = 25.0;
const TWINKLE_MAG_CUTOFF: f32 = 4.0;
const TWINKLE_ALT_DEG: f32 = 30.0;
const TAU: f32 = 6.283185307;

fn psf_base_radius_px(magnitude: f32) -> f32 {
    if (magnitude < 0.0) {
        return 6.0 + (0.0 - magnitude) * 2.5;
    } else if (magnitude < 2.0) {
        return 3.0 + (2.0 - magnitude) * 1.5;
    } else if (magnitude < 4.0) {
        return 1.5 + (4.0 - magnitude) * 0.75;
    }
    return max(0.5, (6.5 - magnitude) * 0.3);
}

fn psf_radius_px(magnitude: f32) -> f32 {
    let base = psf_base_radius_px(magnitude);
    return clamp(base * uniforms.psf_scale, PSF_RADIUS_MIN, PSF_RADIUS_MAX);
}

fn magnitude_to_tone(magnitude: f32) -> f32 {
    // Brightness curve: (7 - mag) / 6 → 1.0 at mag 1, 0.0 at mag 7.
    // The previous 0.3 floor meant every star fainter than ~mag 5 rendered
    // at identical brightness — and at zoom-in we upload mag 10-12 stars
    // (from LOD boost) that all paint with that same 0.3 tone × min-PSF
    // sprite. The result is a grey haze that crowds out the bright stars
    // and makes the scene look DARKER as you zoom (the user's "becomes
    // more black" report). A 0.04 floor lets faint stars actually fade
    // out so bright ones remain visually dominant.
    return clamp((7.0 - magnitude) / 6.0, 0.04, 1.0);
}

/// Scintillation increases toward the horizon (0 above 30° altitude).
fn twinkle_altitude_gate(alt_rad: f32) -> f32 {
    let alt_deg = alt_rad * 57.2957795;
    if (alt_deg >= TWINKLE_ALT_DEG) {
        return 0.0;
    }
    return 1.0 - clamp(alt_deg / TWINKLE_ALT_DEG, 0.0, 1.0);
}

/// v1 star-specific phase from equatorial coordinates.
fn star_twinkle_phase(icrs_dir: vec3<f32>) -> f32 {
    let dir = normalize(icrs_dir);
    return fract(atan2(dir.y, dir.x) * 1000.0 + asin(clamp(dir.z, -1.0, 1.0)) * 100.0);
}

@vertex
fn vs_main(in: VsIn) -> VsOut {
    var out: VsOut;
    out.mag = in.mag;
    out.bv = in.bv;
    out.flags = in.flags;
    out.uv = in.corner;

    let dir = normalize(in.icrs_dir);
    let enu = uniforms.icrs_to_horizontal * dir;
    out.alt_rad = asin(clamp(enu.z, -1.0, 1.0));
    out.star_phase = star_twinkle_phase(in.icrs_dir);

    if (in.mag > uniforms.mag_limit) {
        out.clip = OFF_CLIP;
        return out;
    }

    let view4 = uniforms.icrs_to_view * vec4<f32>(dir, 0.0);
    let v = view4.xyz;
    if (v.z < MIN_COSC) {
        out.clip = OFF_CLIP;
        return out;
    }

    let k = 2.0 / (1.0 + v.z);
    let tan_x = k * v.x;
    let tan_y = k * v.y;
    let ndc = vec2<f32>(tan_x, tan_y) * uniforms.proj_scale;

    let radius_px = psf_radius_px(in.mag);
    // NDC spans 2.0 per axis regardless of aspect — scale per-axis so the rendered
    // PSF stays circular on non-square surfaces. Using a single scalar collapses to
    // a horizontal ellipse on widescreen targets.
    let radius_ndc = vec2<f32>(
        radius_px * 2.0 / uniforms.viewport_pixels.x,
        radius_px * 2.0 / uniforms.viewport_pixels.y,
    );
    let offset = in.corner * radius_ndc;

    out.clip = vec4<f32>(ndc + offset, 0.0, 1.0);
    return out;
}

fn bv_to_rgb(bv: f32) -> vec3<f32> {
    if (bv != bv) {
        return vec3<f32>(0.95, 0.95, 1.0);
    }
    let t = clamp((bv + 0.4) / 2.0, 0.0, 1.0);
    let warm = vec3<f32>(1.0, 0.88, 0.72);
    let cool = vec3<f32>(0.72, 0.84, 1.0);
    return mix(warm, cool, t);
}

fn psf_alpha(r: f32, mag: f32) -> f32 {
    // Sharp Gaussian core — the hot pixel at the star's center.
    let core = exp(-r * r * 12.0);
    // Soft outer halo: bright stars read as a glowy disc, not a sharp
    // dot. Halo width scales with brightness (mag < 4) so faint stars
    // stay pinpoint and bright stars bloom.
    let halo_width = mix(2.0, 5.5, clamp((4.0 - mag) * 0.25, 0.0, 1.0));
    let halo = exp(-r * r * halo_width) * 0.45;
    // Soft glow ring at r≈0.5 — perceived softness without painting a fat blob.
    // `pow(x, 2.0)` is NaN for x < 0 on some backends, so square directly.
    let ring_arg = (r - 0.5) * 5.0;
    let ring = 0.18 * exp(-(ring_arg * ring_arg));
    var a = core + halo + ring;
    if (mag < 1.5) {
        // Brightest stars: add a tighter central spike approximating
        // the inner column of a diffraction pattern (full 4-pointed
        // spikes would need the per-corner UV which isn't currently in
        // scope — radial approximation reads convincingly at this size).
        let spike_arg = r * 14.0;
        let spike = 0.22 * exp(-(spike_arg * spike_arg));
        a = a + spike * (1.5 - mag);
    }
    return clamp(a, 0.0, 1.0);
}

/// Brightness delta from twinkle (v1 magnitudes < 4, scaled by altitude gate).
fn twinkle_brightness_delta(
    phase_rad: f32,
    star_phase: f32,
    magnitude: f32,
    alt_rad: f32,
    enabled: f32,
) -> f32 {
    if (enabled < 0.5 || magnitude >= TWINKLE_MAG_CUTOFF) {
        return 0.0;
    }
    let gate = twinkle_altitude_gate(alt_rad);
    if (gate <= 0.0) {
        return 0.0;
    }
    let t = fract(phase_rad / TAU + star_phase);
    let factor = select(0.08, 0.15, magnitude < 2.0);
    return sin(t * TAU) * factor * gate;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let r = length(in.uv);
    if (r > 1.05) {
        discard;
    }

    var alpha = psf_alpha(r, in.mag);
    let tw = twinkle_brightness_delta(
        uniforms.twinkle_phase,
        in.star_phase,
        in.mag,
        in.alt_rad,
        uniforms.twinkle_enabled,
    );
    let tone = clamp(magnitude_to_tone(in.mag) + tw, 0.0, 1.0);

    let rgb = bv_to_rgb(in.bv);
    let col = rgb * tone;
    return vec4<f32>(col * alpha, alpha);
}
