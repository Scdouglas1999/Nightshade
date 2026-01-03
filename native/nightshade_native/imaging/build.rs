use std::env;
use std::path::PathBuf;

fn main() {
    // Get the workspace root (where libraw.dll/.lib lives)
    // CARGO_MANIFEST_DIR is native/nightshade_native/imaging
    // We need to go up 3 levels to reach the workspace root
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
    let workspace_root = PathBuf::from(&manifest_dir)
        .parent() // native/nightshade_native
        .and_then(|p| p.parent()) // native
        .and_then(|p| p.parent()) // workspace root
        .expect("Failed to find workspace root")
        .to_path_buf();

    // Also check for LIBRAW_DIR environment variable override
    let libraw_dir = env::var("LIBRAW_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| workspace_root.join("lib").join("libraw"));

    // Fall back to workspace root if lib/libraw doesn't exist
    let search_dir = if libraw_dir.exists() {
        libraw_dir
    } else {
        workspace_root.clone()
    };

    println!("cargo:rustc-link-search=native={}", search_dir.display());
    println!("cargo:rustc-link-lib=dylib=libraw");
    println!("cargo:rerun-if-changed={}", search_dir.join("libraw.dll").display());
    println!("cargo:rerun-if-env-changed=LIBRAW_DIR");

    // Check if libraw exists and warn if not
    let libraw_lib = search_dir.join("libraw.lib");
    if !libraw_lib.exists() {
        println!("cargo:warning=libraw.lib not found at: {}", libraw_lib.display());
        println!("cargo:warning=Set LIBRAW_DIR environment variable or place libraw.lib in workspace root");
    } else {
        println!("cargo:warning=LibRaw found at: {}", search_dir.display());
    }
}
