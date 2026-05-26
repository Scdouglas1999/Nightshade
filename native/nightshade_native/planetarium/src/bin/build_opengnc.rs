//! Build `dso-opengnc-v1.bin` from the bundled OpenNGC CSV.
//!
//! ```text
//! cargo run -p nightshade_planetarium --bin build_opengnc -- [repo_root]
//! ```
//!
//! Reads `packages/nightshade_planetarium/assets/opengnc/NGC.csv` and writes
//! `apps/desktop/assets/planetarium/catalogs/core/dso-opengnc-v1.bin`.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use nightshade_planetarium::catalog::{
    build_opengnc_catalog, default_opengnc_csv_path, default_output_path, find_repo_root,
    OPENNGC_V1_EXPECTED_RECORDS,
};

fn main() -> ExitCode {
    match run() {
        Ok(stats) => {
            eprintln!(
                "dso-opengnc-v1: {} records ({} rows skipped)",
                stats.records_written, stats.records_skipped
            );
            if stats.records_written != OPENNGC_V1_EXPECTED_RECORDS {
                eprintln!(
                    "self-check FAILED: expected {} records, got {}",
                    OPENNGC_V1_EXPECTED_RECORDS, stats.records_written
                );
                return ExitCode::from(2);
            }
            eprintln!("self-check OK");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("build_opengnc: {err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<nightshade_planetarium::catalog::OpenNgcBuildStats, Box<dyn std::error::Error>> {
    let repo_root = resolve_repo_root()?;
    let csv_path = default_opengnc_csv_path(&repo_root);
    let output_path = default_output_path(&repo_root);

    if !csv_path.is_file() {
        return Err(format!(
            "OpenNGC CSV not found at {} — place NGC.csv under packages/nightshade_planetarium/assets/opengnc/",
            csv_path.display()
        )
        .into());
    }

    eprintln!("input:  {}", csv_path.display());
    eprintln!("output: {}", output_path.display());

    let result = build_opengnc_catalog(&csv_path, &output_path)?;
    Ok(result.stats)
}

fn resolve_repo_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        let root = PathBuf::from(&args[1]);
        if root
            .join(nightshade_planetarium::catalog::OPENNGC_CSV_REL_PATH)
            .is_file()
        {
            return Ok(root);
        }
        return Err(format!(
            "no OpenNGC CSV under {}",
            default_opengnc_csv_path(&root).display()
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
