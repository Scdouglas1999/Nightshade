use std::env;
use std::path::PathBuf;

fn main() {
    cc::Build::new()
        .file("src/libraw_shim.c")
        .include("vendor/libraw")
        .warnings(false)
        .compile("nightshade_libraw_shim");

    println!("cargo:rerun-if-changed=src/libraw_shim.c");
    println!("cargo:rerun-if-changed=vendor/libraw/libraw_const.h");
    println!("cargo:rerun-if-changed=vendor/libraw/libraw_types.h");
    println!("cargo:rerun-if-changed=vendor/libraw/libraw_version.h");

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

    // Why: version.yaml is the single source of truth for the user-facing
    // product version. Cargo.toml is pinned at 0.1.0 and would mislead
    // downstream consumers (XISF Creator field, FITS history, etc.).
    let version_yaml = workspace_root.join("version.yaml");
    println!("cargo:rerun-if-changed={}", version_yaml.display());
    let nightshade_version = read_nightshade_version(&version_yaml).unwrap_or_else(|err| {
        // Errors are a feature — refuse to silently fall back to a fake version.
        panic!(
            "build.rs: unable to determine Nightshade version from {}: {}",
            version_yaml.display(),
            err
        );
    });
    println!(
        "cargo:rustc-env=NIGHTSHADE_VERSION={}",
        nightshade_version
    );

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
        println!(
            "cargo:rerun-if-changed={}",
            search_dir.join("libraw.dll").display()
        );
        println!("cargo:rerun-if-env-changed=LIBRAW_DIR");

        let libraw_lib = search_dir.join("libraw.lib");
        if !libraw_lib.exists() {
            println!(
                "cargo:warning=libraw.lib not found at: {}",
                libraw_lib.display()
            );
            println!("cargo:warning=Set LIBRAW_DIR environment variable or place libraw.lib in workspace root");
        } else {
            println!("cargo:rustc-env=LIBRAW_PATH={}", search_dir.display());
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

/// Extract the `version: "X.Y.Z"` field from `version.yaml`.
///
/// Why: avoid pulling a YAML dependency into build.rs for one scalar string.
/// The format is fixed by the project (see `version.yaml` in repo root).
fn read_nightshade_version(path: &std::path::Path) -> Result<String, String> {
    let contents = std::fs::read_to_string(path)
        .map_err(|err| format!("failed to read {}: {}", path.display(), err))?;
    for raw_line in contents.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some(rest) = line.strip_prefix("version:") else {
            continue;
        };
        let value = rest.trim();
        // Tolerate both `"2.5.0"` and `2.5.0` (YAML allows unquoted scalars).
        let stripped = value
            .strip_prefix('"')
            .and_then(|s| s.strip_suffix('"'))
            .or_else(|| value.strip_prefix('\'').and_then(|s| s.strip_suffix('\'')))
            .unwrap_or(value);
        if stripped.is_empty() {
            return Err(format!("`version:` key in {} is empty", path.display()));
        }
        return Ok(stripped.to_string());
    }
    Err(format!(
        "`version:` key not found in {}",
        path.display()
    ))
}
