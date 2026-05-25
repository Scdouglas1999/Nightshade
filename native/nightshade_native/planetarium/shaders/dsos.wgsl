// DSO instanced sprites — design §5.4 (procedural ellipse / halo, type_id switch).
// Screen size and surface-brightness opacity mirror v1 SkyRenderer.

struct DsoUniforms {
    icrs_to_view: mat4x4<f32>,
    proj_scale: vec2<f32>,
    mag_limit: f32,
    pixels_per_deg: f32,
    viewport_pixels: vec2<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: DsoUniforms;

struct VsIn {
    @location(0) corner: vec2<f32>,
    @location(1) icrs_dir: vec3<f32>,
    @location(2) size_arcmin: vec2<f32>,
    @location(3) pa_deg: f32,
    @location(4) surface_mag: f32,
    @location(5) type_id: u32,
    @location(6) flags: u32,
}

struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) axis_ratio: f32,
    @location(2) pa_rad: f32,
    @location(3) surface_mag: f32,
    @location(4) type_id: u32,
    @location(5) sb_opacity: f32,
}

const MIN_COSC: f32 = 0.01;
const OFF_CLIP: vec4<f32> = vec4<f32>(0.0, 0.0, -2.0, 1.0);
const DSO_FLAG_HAS_MAG: u32 = 1u;

// Renderer type ids (catalog::dso_type).
const TYPE_GALAXY: u32 = 0u;
const TYPE_OPEN_CLUSTER: u32 = 1u;
const TYPE_GLOBULAR: u32 = 2u;
const TYPE_NEBULA: u32 = 3u;
const TYPE_PLANETARY: u32 = 4u;
const TYPE_SNR: u32 = 5u;
const TYPE_STELLAR: u32 = 6u;
const TYPE_CLUSTER_NEB: u32 = 7u;
const TYPE_NOVA: u32 = 8u;
const TYPE_OTHER: u32 = 9u;

fn display_radius_px(size_major_arcmin: f32, magnitude: f32) -> f32 {
    var major = size_major_arcmin;
    if (major <= 0.0) {
        major = 5.0;
    }
    let size_deg = major / 60.0;
    let dso_px = size_deg * uniforms.pixels_per_deg;
    var mag = magnitude;
    if (mag != mag) {
        mag = 14.0;
    }
    let mag_bonus = clamp((14.0 - mag) / 14.0 * 14.0, 0.0, 14.0);
    let display = clamp(dso_px, 6.0 + mag_bonus, 40.0);
    return display * 0.5;
}

fn surface_brightness(major_arcmin: f32, minor_arcmin: f32, magnitude: f32) -> f32 {
    if (magnitude != magnitude || major_arcmin <= 0.0) {
        return -1.0;
    }
    var minor = minor_arcmin;
    if (minor <= 0.0) {
        minor = major_arcmin;
    }
    let area_arcmin2 = 3.14159265 * (major_arcmin * 0.5) * (minor * 0.5);
    let area_arcsec2 = area_arcmin2 * 3600.0;
    if (area_arcsec2 <= 0.0) {
        return -1.0;
    }
    return magnitude + 2.5 * (log(area_arcsec2) / log(10.0));
}

fn surface_brightness_opacity(sb: f32) -> f32 {
    if (sb < 0.0) {
        return 0.7;
    }
    if (sb <= 22.0) {
        return 1.0;
    }
    if (sb >= 26.5) {
        return 0.15;
    }
    return 1.0 - (sb - 22.0) / (26.5 - 22.0) * 0.85;
}

fn axis_ratio_from_sizes(major_arcmin: f32, minor_arcmin: f32) -> f32 {
    if (major_arcmin > 0.0 && minor_arcmin > 0.0) {
        return clamp(minor_arcmin / major_arcmin, 0.2, 1.0);
    }
    return 0.5;
}

@vertex
fn vs_main(in: VsIn) -> VsOut {
    var out: VsOut;
    out.uv = in.corner;
    out.axis_ratio = axis_ratio_from_sizes(in.size_arcmin.x, in.size_arcmin.y);
    out.pa_rad = in.pa_deg * 0.0174532925;
    out.surface_mag = in.surface_mag;
    out.type_id = in.type_id;

    let sb = surface_brightness(in.size_arcmin.x, in.size_arcmin.y, in.surface_mag);
    out.sb_opacity = surface_brightness_opacity(sb);

    var mag = in.surface_mag;
    let has_mag = (in.flags & DSO_FLAG_HAS_MAG) != 0u;
    if (!has_mag || mag != mag) {
        mag = 99.0;
    }
    if (mag > uniforms.mag_limit) {
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

    let radius_px = display_radius_px(in.size_arcmin.x, mag);
    let radius_ndc = radius_px / min(uniforms.viewport_pixels.x, uniforms.viewport_pixels.y) * 2.0;

    var local = in.corner;
    let c = cos(out.pa_rad);
    let s = sin(out.pa_rad);
    let rot = mat2x2<f32>(c, -s, s, c);
    local.x *= 1.0;
    local.y *= out.axis_ratio;
    local = rot * (local * radius_ndc);

    out.clip = vec4<f32>(ndc + local, 0.0, 1.0);
    return out;
}

fn type_base_rgb(type_id: u32) -> vec3<f32> {
    switch (type_id) {
        case TYPE_GALAXY: { return vec3<f32>(0.39, 0.71, 0.96); }
        case TYPE_OPEN_CLUSTER: { return vec3<f32>(1.0, 0.92, 0.23); }
        case TYPE_GLOBULAR: { return vec3<f32>(1.0, 0.6, 0.0); }
        case TYPE_NEBULA: { return vec3<f32>(0.91, 0.12, 0.39); }
        case TYPE_PLANETARY: { return vec3<f32>(0.15, 0.65, 0.6); }
        case TYPE_SNR: { return vec3<f32>(0.96, 0.26, 0.21); }
        case TYPE_CLUSTER_NEB: { return vec3<f32>(0.91, 0.12, 0.39); }
        case TYPE_NOVA: { return vec3<f32>(0.96, 0.26, 0.21); }
        default: { return vec3<f32>(1.0, 1.0, 1.0); }
    }
}

fn ellipse_alpha(uv: vec2<f32>, axis_ratio: f32) -> f32 {
    let p = vec2<f32>(uv.x, uv.y / max(axis_ratio, 0.2));
    let r = length(p);
    if (r > 1.05) {
        return 0.0;
    }
    let body = exp(-r * r * 3.5);
    let core = 0.35 * exp(-r * r * 25.0);
    return clamp(body + core, 0.0, 1.0);
}

fn nebula_alpha(uv: vec2<f32>) -> f32 {
    let r = max(abs(uv.x) * 0.85, abs(uv.y));
    if (r > 1.1) {
        return 0.0;
    }
    return exp(-r * r * 2.8) * 0.85;
}

fn globular_alpha(uv: vec2<f32>) -> f32 {
    let r = length(uv);
    if (r > 1.05) {
        return 0.0;
    }
    let halo = exp(-r * r * 1.8) * 0.35;
    let core = exp(-r * r * 12.0) * 0.65;
    return clamp(halo + core, 0.0, 1.0);
}

fn open_cluster_alpha(uv: vec2<f32>) -> f32 {
    let r = length(uv);
    if (r > 1.02) {
        return 0.0;
    }
    let ring = smoothstep(1.0, 0.85, r) * 0.25;
    let dots = 0.0;
    let a1 = exp(-length(uv - vec2<f32>(0.25, 0.15)) * 40.0) * 0.5;
    let a2 = exp(-length(uv - vec2<f32>(-0.2, 0.22)) * 40.0) * 0.45;
    let a3 = exp(-length(uv - vec2<f32>(-0.1, -0.28)) * 40.0) * 0.4;
    let a4 = exp(-length(uv - vec2<f32>(0.18, -0.12)) * 40.0) * 0.35;
    return clamp(ring + a1 + a2 + a3 + a4 + dots, 0.0, 1.0);
}

fn planetary_alpha(uv: vec2<f32>) -> f32 {
    let r = length(uv);
    if (r > 1.05) {
        return 0.0;
    }
    let ring = smoothstep(0.95, 0.55, r) * smoothstep(0.35, 0.55, r);
    let star = exp(-length(uv) * length(uv) * 80.0);
    return clamp(ring * 0.7 + star, 0.0, 1.0);
}

fn snr_alpha(uv: vec2<f32>) -> f32 {
    let r = length(uv);
    if (r > 1.05) {
        return 0.0;
    }
    let core = exp(-r * r * 30.0);
    let spike = max(
        exp(-abs(uv.x) * 18.0) * exp(-abs(uv.y) * 80.0),
        exp(-abs(uv.y) * 18.0) * exp(-abs(uv.x) * 80.0),
    );
    return clamp(core + spike * 0.5, 0.0, 1.0);
}

fn shape_alpha(uv: vec2<f32>, axis_ratio: f32, type_id: u32) -> f32 {
    switch (type_id) {
        case TYPE_GALAXY: { return ellipse_alpha(uv, axis_ratio); }
        case TYPE_OPEN_CLUSTER, TYPE_STELLAR, TYPE_OTHER: {
            return open_cluster_alpha(uv);
        }
        case TYPE_GLOBULAR: { return globular_alpha(uv); }
        case TYPE_NEBULA, TYPE_CLUSTER_NEB: { return nebula_alpha(uv); }
        case TYPE_PLANETARY: { return planetary_alpha(uv); }
        case TYPE_SNR, TYPE_NOVA: { return snr_alpha(uv); }
        default: { return ellipse_alpha(uv, axis_ratio); }
    }
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let alpha = shape_alpha(in.uv, in.axis_ratio, in.type_id) * in.sb_opacity * 0.5;
    if (alpha < 0.004) {
        discard;
    }
    let rgb = type_base_rgb(in.type_id);
    return vec4<f32>(rgb * alpha, alpha);
}
