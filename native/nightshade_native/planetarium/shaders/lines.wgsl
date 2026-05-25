// Grids, constellation stick figures, ecliptic / galactic overlays (design §5.1 pass 5).
// Vertex: unit ICRS direction + packed RGBA + style id + along-segment param for dashing.

struct LineUniforms {
    icrs_to_view: mat4x4<f32>,
    proj_scale: vec2<f32>,
    viewport_pixels: vec2<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: LineUniforms;

struct VsIn {
    @location(0) icrs_dir: vec3<f32>,
    @location(1) color: u32,
    @location(2) style_id: u32,
    @location(3) along: f32,
}

struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) style_id: u32,
    @location(2) along: f32,
}

const MIN_COSC: f32 = 0.01;
const OFF_CLIP: vec4<f32> = vec4<f32>(0.0, 0.0, -2.0, 1.0);

const STYLE_CONSTELLATION: u32 = 0u;
const STYLE_GRID_SOLID: u32 = 1u;
const STYLE_GRID_DASHED: u32 = 2u;
const STYLE_ECLIPTIC: u32 = 3u;
const STYLE_GALACTIC: u32 = 4u;

fn unpack_rgba(packed: u32) -> vec4<f32> {
    let r = f32(packed & 0xffu) / 255.0;
    let g = f32((packed >> 8u) & 0xffu) / 255.0;
    let b = f32((packed >> 16u) & 0xffu) / 255.0;
    let a = f32((packed >> 24u) & 0xffu) / 255.0;
    return vec4<f32>(r, g, b, a);
}

@vertex
fn vs_main(in: VsIn) -> VsOut {
    var out: VsOut;
    out.color = unpack_rgba(in.color);
    out.style_id = in.style_id;
    out.along = in.along;

    let dir = normalize(in.icrs_dir);
    let view4 = uniforms.icrs_to_view * vec4<f32>(dir, 0.0);
    let v = view4.xyz;
    if (v.z < MIN_COSC) {
        out.clip = OFF_CLIP;
        return out;
    }

    let k = 2.0 / (1.0 + v.z);
    let ndc = vec2<f32>(k * v.x, k * v.y) * uniforms.proj_scale;
    out.clip = vec4<f32>(ndc, 0.0, 1.0);
    return out;
}

fn dash_keep(style_id: u32, along: f32) -> bool {
    if (style_id != STYLE_GRID_DASHED) {
        return true;
    }
    // Eight dashes per segment (alt-az grid uses lower alpha in the color; dashes thin further).
    let t = along * 8.0;
    return fract(t) < 0.55;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    if (!dash_keep(in.style_id, in.along)) {
        discard;
    }

    var alpha = in.color.a;
    if (in.style_id == STYLE_GRID_DASHED) {
        alpha = alpha * 0.85;
    }

    let rgb = in.color.rgb * alpha;
    return vec4<f32>(rgb, alpha);
}
