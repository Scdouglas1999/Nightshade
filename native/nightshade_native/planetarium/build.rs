//! Compile Bruneton GLSL precompute shaders to SPIR-V for wgpu.

use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let out_dir = env::var("OUT_DIR").expect("OUT_DIR");
    let manifest = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR");
    let shader_dir = Path::new(&manifest).join("shaders/bruneton");

    println!("cargo:rerun-if-changed=shaders/bruneton");
    println!("cargo:rerun-if-changed=build.rs");

    let common = read(&shader_dir.join("precompute_common.glsl"));
    let definitions = read(&shader_dir.join("definitions.glsl"));
    let functions = read(&shader_dir.join("functions.glsl"));
    let atmosphere = read(&shader_dir.join("atmosphere_header.glsl"));
    let uniforms = read(&shader_dir.join("precompute_uniforms.glsl"));
    let header = format!(
        "{common}\n{definitions}\n{atmosphere}\n{uniforms}\n",
        common = common,
        definitions = definitions,
        atmosphere = atmosphere,
        uniforms = uniforms
    );

    let mut compiler = shaderc::Compiler::new().expect("shaderc compiler");
    let mut options = shaderc::CompileOptions::new().expect("shaderc options");
    options.set_optimization_level(shaderc::OptimizationLevel::Performance);
    options.set_target_env(
        shaderc::TargetEnv::Vulkan,
        shaderc::EnvVersion::Vulkan1_2 as u32,
    );

    let vertex_src = read(&shader_dir.join("precompute_vertex.glsl"));
    compile(
        &mut compiler,
        &options,
        &out_dir,
        "bruneton_precompute_vertex",
        shaderc::ShaderKind::Vertex,
        &vertex_src,
        "precompute_vertex.glsl",
    );

    let fragments = [
        ("bruneton_precompute_transmittance", "precompute_transmittance.frag"),
        (
            "bruneton_precompute_direct_irradiance",
            "precompute_direct_irradiance.frag",
        ),
        (
            "bruneton_precompute_single_scattering",
            "precompute_single_scattering.frag",
        ),
        (
            "bruneton_precompute_scattering_density",
            "precompute_scattering_density.frag",
        ),
        (
            "bruneton_precompute_indirect_irradiance",
            "precompute_indirect_irradiance.frag",
        ),
        (
            "bruneton_precompute_multiple_scattering",
            "precompute_multiple_scattering.frag",
        ),
    ];

    for (out_name, frag_file) in fragments {
        let body = read(&shader_dir.join(frag_file));
        let src = format!(
            "{header}\n{functions}\n{body}",
            header = header,
            functions = functions,
            body = body
        );
        compile(
            &mut compiler,
            &options,
            &out_dir,
            out_name,
            shaderc::ShaderKind::Fragment,
            &src,
            frag_file,
        );
    }
}

fn read(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn compile(
    compiler: &mut shaderc::Compiler,
    options: &shaderc::CompileOptions,
    out_dir: &str,
    out_name: &str,
    kind: shaderc::ShaderKind,
    source: &str,
    file_name: &str,
) {
    let compiled = compiler
        .compile_into_spirv(source, kind, file_name, "main", Some(options))
        .unwrap_or_else(|e| panic!("shader compile {file_name}: {e}"));
    let out_path = Path::new(out_dir).join(format!("{out_name}.spv"));
    fs::write(&out_path, compiled.as_binary_u8()).expect("write spv");
}
