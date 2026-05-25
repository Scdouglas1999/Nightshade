// Star instanced quads — design §5.2 (ICRS→view→projection, PSF, B−V color).
// PSF size + tone mapping ported from v1 SkyRenderer (_magnitudeToRadius / _magnitudeToBrightness).

struct StarUniforms {
    icrs_to_view: mat4x4<f32>,
    proj_scale: vec2<f32>,
    mag_limit: f32,
    psf_scale: f32,
    twinkle_seed: f32,
    viewport_pixels: vec2<f32>,
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
}

const MIN_COSC: f32 = 0.01;
const OFF_CLIP: vec4<f32> = vec4<f32>(0.0, 0.0, -2.0, 1.0);
const PSF_RADIUS_MIN: f32 = 0.5;
const PSF_RADIUS_MAX: f32 = 25.0;

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
    return clamp((7.0 - magnitude) / 6.0, 0.3, 1.0);
}

@vertex
fn vs_main(in: VsIn) -> VsOut {
    var out: VsOut;
    out.mag = in.mag;
    out.bv = in.bv;
    out.flags = in.flags;
    out.uv = in.corner;

    if (in.mag > uniforms.mag_limit) {
        out.clip = OFF_CLIP;
        return out;
    }

    let dir = normalize(in.icrs_dir);
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
    let radius_ndc = radius_px / min(uniforms.viewport_pixels.x, uniforms.viewport_pixels.y) * 2.0;
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
    let core = exp(-r * r * 10.0);
    let ring = 0.12 * exp(-pow((r - 0.4) * 6.0, 2.0));
    var a = core + ring;
    if (mag < 1.0) {
        let spike = 0.06 * exp(-pow(r * 18.0, 2.0));
        a = a + spike * (1.0 - mag);
    }
    return clamp(a, 0.0, 1.0);
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let r = length(in.uv);
    if (r > 1.05) {
        discard;
    }

    var alpha = psf_alpha(r, in.mag);
    let tw = 1.0 + 0.04 * sin(uniforms.twinkle_seed + in.mag * 3.7);
    alpha = alpha * tw;

    let rgb = bv_to_rgb(in.bv);
    let tone = magnitude_to_tone(in.mag);
    let col = rgb * tone;
    return vec4<f32>(col * alpha, alpha);
}
