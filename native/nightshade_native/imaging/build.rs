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

    // Platform-specific library configuration
    #[cfg(target_os = "windows")]
    {
        // Windows: use bundled libraw.dll/.lib
        let libraw_dir = env::var("LIBRAW_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| workspace_root.join("lib").join("libraw"));

        let search_dir = if libraw_dir.exists() {
            libraw_dir
        } else {
            workspace_root.clone()
        };

        println!("cargo:rustc-link-search=native={}", search_dir.display());
        println!("cargo:rustc-link-lib=dylib=libraw");
        println!("cargo:rerun-if-changed={}", search_dir.join("libraw.dll").display());
        println!("cargo:rerun-if-env-changed=LIBRAW_DIR");

        let libraw_lib = search_dir.join("libraw.lib");
        if !libraw_lib.exists() {
            println!("cargo:warning=libraw.lib not found at: {}", libraw_lib.display());
            println!("cargo:warning=Set LIBRAW_DIR environment variable or place libraw.lib in workspace root");
        } else {
            println!("cargo:warning=LibRaw found at: {}", search_dir.display());
        }
    }

    #[cfg(target_os = "linux")]
    {
        // Linux: use system libraw from package manager
        // The library is named libraw.so, so we link with -lraw
        println!("cargo:rustc-link-lib=dylib=raw");

        // Also check common system library paths
        println!("cargo:rustc-link-search=native=/usr/lib");
        println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
        println!("cargo:rustc-link-search=native=/usr/local/lib");
    }

    #[cfg(target_os = "macos")]
    {
        // macOS: use system libraw (via Homebrew or similar)
        println!("cargo:rustc-link-lib=dylib=raw");

        // Homebrew paths
        println!("cargo:rustc-link-search=native=/usr/local/lib");
        println!("cargo:rustc-link-search=native=/opt/homebrew/lib");
    }
}
