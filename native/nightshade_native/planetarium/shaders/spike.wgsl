struct Uniforms {
    rotation: f32,
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

struct VsIn {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec3<f32>,
};
struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vs_main(in: VsIn) -> VsOut {
    let c = cos(uniforms.rotation);
    let s = sin(uniforms.rotation);
    let rotated = vec2<f32>(
        in.pos.x * c - in.pos.y * s,
        in.pos.x * s + in.pos.y * c,
    );
    var out: VsOut;
    out.clip = vec4<f32>(rotated, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
