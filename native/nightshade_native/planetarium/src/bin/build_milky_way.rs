//! Build `mw-intensity-v1.bin` (procedural galactic-band intensity raster).
//!
//! ```text
//! cargo run -p nightshade_planetarium --bin build_milky_way -- [repo_root]
//! ```
//!
//! Writes `apps/desktop/assets/planetarium/mw-intensity-v1.bin`.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use nightshade_planetarium::catalog::{
    build_milky_way_asset, default_mw_asset_path, find_repo_root, MILKY_WAY_FILE_LEN,
};

fn main() -> ExitCode {
    match run() {
        Ok(result) => {
            eprintln!(
                "mw-intensity-v1: {} bytes, {} nonzero pixels → {}",
                result.byte_len,
                result.nonzero_pixels,
                result.output_path.display()
            );
            if result.byte_len != MILKY_WAY_FILE_LEN {
                eprintln!(
                    "self-check FAILED: expected {} bytes, got {}",
                    MILKY_WAY_FILE_LEN,
                    result.byte_len
                );
                return ExitCode::from(2);
            }
            eprintln!("self-check OK");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("build_milky_way: {err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<nightshade_planetarium::catalog::MilkyWayBuildResult, Box<dyn std::error::Error>>
{
    let repo_root = resolve_repo_root()?;
    let output_path = default_mw_asset_path(&repo_root);

    eprintln!("output: {}", output_path.display());
    let result = build_milky_way_asset(&output_path)?;
    Ok(result)
}

fn resolve_repo_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        let root = PathBuf::from(&args[1]);
        if root.join("melos.yaml").is_file() || root.join("native/nightshade_native/Cargo.toml").is_file()
        {
            return Ok(root);
        }
        return Err(format!(
            "path does not look like a Nightshade repo root: {}",
            root.display()
        )
        .into());
    }

    let cwd = env::current_dir()?;
    find_repo_root(&cwd).ok_or_else(|| {
        format!(
            "could not find repository root from {}; pass repo_root explicitly",
            cwd.display()
        )
        .into()
    })
}
