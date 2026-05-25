// Milky Way pass 2 — equirectangular intensity map on the celestial sphere (design §8.2).
// Full-screen triangle: invert stereographic view ray, sample R8 MW texture at equatorial UV.
// Brightness fades with sky_brightness (Bruneton twilight) and lp_factor (Bortle wash).

// Field order matches the Rust `MwUniforms` (planetarium::renderer::pipelines::milky_way).
// Layout: mat4x4 (64) | vec2 proj (8) | vec2 viewport (8) | f32 sky | f32 lp | f32 enabled | f32 pad = 96 bytes.
struct MwUniforms {
    view_to_icrs: mat4x4<f32>,
    proj_scale: vec2<f32>,
    viewport_pixels: vec2<f32>,
    sky_brightness: f32,
    lp_factor: f32,
    mw_enabled: f32,
    _pad: f32,
}

@group(0) @binding(0) var<uniform> uniforms: MwUniforms;
@group(0) @binding(1) var mw_sampler: sampler;
@group(0) @binding(2) var mw_texture: texture_2d<f32>;

struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) ndc: vec2<f32>,
}

const MIN_COSC: f32 = 0.01;
const MW_BASE_COLOR: vec3<f32> = vec3<f32>(0.502, 0.565, 0.659); // v1 0xFF8090A8
const MW_ALPHA_SCALE: f32 = 0.22;

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VsOut {
    var out: VsOut;
    let x = f32((vi << 1u) & 2u) * 2.0 - 1.0;
    let y = f32(vi & 2u) * 2.0 - 1.0;
    out.ndc = vec2<f32>(x, y);
    out.clip = vec4<f32>(x, y, 0.0, 1.0);
    return out;
}

/// Invert stars/lines stereographic: NDC → unit view direction (+Z boresight).
fn ndc_to_view_dir(ndc: vec2<f32>) -> vec3<f32> {
    let tan_x = ndc.x / uniforms.proj_scale.x;
    let tan_y = ndc.y / uniforms.proj_scale.y;
    let r2 = tan_x * tan_x + tan_y * tan_y;
    let vz = (1.0 - r2) / (1.0 + r2);
    let k = 1.0 + vz;
    let vx = tan_x * k * 0.5;
    let vy = tan_y * k * 0.5;
    return normalize(vec3<f32>(vx, vy, vz));
}

fn icrs_dir_to_uv(dir: vec3<f32>) -> vec2<f32> {
    let d = normalize(dir);
    var ra_deg = atan2(d.y, d.x) * 57.2957795;
    if (ra_deg < 0.0) {
        ra_deg = ra_deg + 360.0;
    }
    let dec_deg = asin(clamp(d.z, -1.0, 1.0)) * 57.2957795;
    let u = ra_deg / 360.0;
    let v = (90.0 - dec_deg) / 180.0;
    return vec2<f32>(u, v);
}

/// MW fades as the sky brightens (Bruneton output; 0 = night, 1 = day/twilight).
fn sky_visibility() -> f32 {
    let b = clamp(uniforms.sky_brightness, 0.0, 1.0);
    return (1.0 - b) * (1.0 - b);
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    if (uniforms.mw_enabled < 0.5) {
        discard;
    }

    let view_dir = ndc_to_view_dir(in.ndc);
    if (view_dir.z < MIN_COSC) {
        discard;
    }

    let icrs4 = uniforms.view_to_icrs * vec4<f32>(view_dir, 0.0);
    let uv = icrs_dir_to_uv(icrs4.xyz);
    let intensity = textureSample(mw_texture, mw_sampler, uv).r;
    if (intensity < 0.02) {
        discard;
    }

    let vis = sky_visibility() * clamp(uniforms.lp_factor, 0.0, 1.0);
    let alpha = intensity * MW_ALPHA_SCALE * vis;
    if (alpha < 0.001) {
        discard;
    }

    let rgb = MW_BASE_COLOR * alpha;
    return vec4<f32>(rgb, alpha);
}
