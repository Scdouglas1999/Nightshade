//! Build `stars-hyg-v1` HEALPix tiles from the bundled HYG CSV.
//!
//! ```text
//! cargo run -p nightshade_planetarium --bin build_hyg_tiles -- [repo_root]
//! ```
//!
//! Reads `packages/nightshade_planetarium/assets/hyg/hyg_v42.csv` and writes
//! `apps/desktop/assets/planetarium/catalogs/stars-hyg-v1/tiles/*.bin`.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use nightshade_planetarium::catalog::{
    build_hyg_tiles, default_hyg_csv_path, default_output_dir, find_repo_root,
    HYG_V42_EXPECTED_STARS, HYG_V42_EXPECTED_TILES,
};

fn main() -> ExitCode {
    match run() {
        Ok(stats) => {
            eprintln!(
                "stars-hyg-v1: {} tiles, {} stars ({} rows skipped)",
                stats.tiles_written, stats.stars_written, stats.stars_skipped
            );
            if stats.tiles_written != HYG_V42_EXPECTED_TILES
                || stats.stars_written != HYG_V42_EXPECTED_STARS
            {
                eprintln!(
                    "self-check FAILED: expected {} tiles and {} stars, got {} and {}",
                    HYG_V42_EXPECTED_TILES,
                    HYG_V42_EXPECTED_STARS,
                    stats.tiles_written,
                    stats.stars_written
                );
                return ExitCode::from(2);
            }
            eprintln!("self-check OK");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("build_hyg_tiles: {err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<nightshade_planetarium::catalog::HygBuildStats, Box<dyn std::error::Error>> {
    let repo_root = resolve_repo_root()?;
    let csv_path = default_hyg_csv_path(&repo_root);
    let output_dir = default_output_dir(&repo_root);

    if !csv_path.is_file() {
        return Err(format!(
            "HYG CSV not found at {} — place hyg_v42.csv under packages/nightshade_planetarium/assets/hyg/",
            csv_path.display()
        )
        .into());
    }

    eprintln!("input:  {}", csv_path.display());
    eprintln!("output: {}", output_dir.display());

    let result = build_hyg_tiles(&csv_path, &output_dir)?;
    Ok(result.stats)
}

fn resolve_repo_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        let root = PathBuf::from(&args[1]);
        if root.join(nightshade_planetarium::catalog::HYG_CSV_REL_PATH).is_file() {
            return Ok(root);
        }
        return Err(format!(
            "no HYG CSV under {}",
            default_hyg_csv_path(&root).display()
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
