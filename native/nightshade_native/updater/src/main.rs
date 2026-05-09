//! Nightshade External Updater
//!
//! This is a standalone executable that applies staged updates after the main
//! Nightshade app has exited. It:
//! 1. Waits for the parent process to exit
//! 2. Backs up the current installation
//! 3. Copies staged files to the installation directory
//! 4. Launches the new version
//! 5. Cleans up staging directory

use anyhow::{Context, Result};
use clap::Parser;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[cfg(windows)]
use windows::Win32::System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE};

/// Nightshade Update Applier
#[derive(Parser, Debug)]
#[command(name = "updater")]
#[command(about = "Applies staged Nightshade updates")]
struct Args {
    /// Parent process ID to wait for
    #[arg(long)]
    parent_pid: u32,

    /// Directory containing staged update files
    #[arg(long)]
    staging_dir: PathBuf,

    /// Installation directory to update
    #[arg(long)]
    install_dir: PathBuf,

    /// Directory to backup current installation
    #[arg(long)]
    backup_dir: PathBuf,

    /// Marker file used for boot-time update verification
    #[arg(long)]
    pending_file: PathBuf,

    /// Launch the new version after update
    #[arg(long)]
    launch_after: bool,
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Update failed: {}", e);
        // Write error to log file for diagnosis
        let log_path = std::env::temp_dir().join("nightshade_update_error.log");
        let _ = fs::write(&log_path, format!("Update failed: {:?}", e));
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = Args::parse();

    println!("Nightshade Updater");
    println!("==================");
    println!("Parent PID: {}", args.parent_pid);
    println!("Staging: {:?}", args.staging_dir);
    println!("Install: {:?}", args.install_dir);
    println!("Backup: {:?}", args.backup_dir);
    println!("Pending marker: {:?}", args.pending_file);

    // Step 1: Wait for parent process to exit
    println!("\nWaiting for Nightshade to exit...");
    wait_for_process_exit(args.parent_pid, Duration::from_secs(30))?;
    println!("Parent process has exited.");

    // Small delay to ensure file handles are released
    thread::sleep(Duration::from_millis(500));

    // Step 2: Backup current installation
    println!("\nBacking up current installation...");
    backup_installation(&args.install_dir, &args.backup_dir)?;
    println!("Backup complete.");

    // Step 3: Apply update
    println!("\nApplying update...");
    let apply_result = (|| -> Result<()> {
        apply_update(&args.staging_dir, &args.install_dir)?;
        verify_installation(&args.install_dir)?;
        println!("Update applied successfully.");

        // Step 4: Cleanup staging
        println!("\nCleaning up...");
        if let Err(e) = cleanup_staging(&args.staging_dir) {
            eprintln!("Warning: Failed to cleanup staging: {}", e);
        }

        // Step 5: Launch new version
        if args.launch_after {
            println!("\nLaunching updated Nightshade...");
            launch_app(&args.install_dir)?;
        }

        Ok(())
    })();

    match apply_result {
        Ok(()) => {
            println!("\nUpdate complete!");
            Ok(())
        }
        Err(update_error) => {
            eprintln!(
                "\nUpdate failed, attempting rollback from backup: {}",
                update_error
            );
            let rollback_result = restore_backup(&args.backup_dir, &args.install_dir);
            let _ = remove_pending_marker(&args.pending_file);

            match rollback_result {
                Ok(()) => Err(update_error.context(
                    "Update failed, but the previous installation was restored from backup",
                )),
                Err(rollback_error) => Err(anyhow::anyhow!(
                    "Update failed: {}. Rollback also failed: {}",
                    update_error,
                    rollback_error
                )),
            }
        }
    }
}

/// Wait for a process to exit
fn wait_for_process_exit(pid: u32, timeout: Duration) -> Result<()> {
    #[cfg(windows)]
    {
        unsafe {
            let handle = OpenProcess(PROCESS_SYNCHRONIZE, false, pid);
            if let Ok(handle) = handle {
                let result = WaitForSingleObject(handle, timeout.as_millis() as u32);
                // WAIT_OBJECT_0 = 0x00000000
                if result.0 != 0 && result.0 != 0x00000102 {
                    // Not signaled and not timeout (process might not exist)
                    // This is actually OK - process already exited
                }
            }
            // If we can't open the process, it probably already exited
        }
        Ok(())
    }

    #[cfg(not(windows))]
    {
        // On Unix, we can use kill(pid, 0) to check if process exists
        use std::os::unix::process::CommandExt;

        let start = std::time::Instant::now();
        while start.elapsed() < timeout {
            // Check if process exists
            let output = Command::new("kill").args(["-0", &pid.to_string()]).output();

            if let Ok(output) = output {
                if !output.status.success() {
                    // Process doesn't exist
                    return Ok(());
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
}

/// Backup the current installation
fn backup_installation(install_dir: &Path, backup_dir: &Path) -> Result<()> {
    // Clear previous backup
    if backup_dir.exists() {
        fs::remove_dir_all(backup_dir).context("Failed to clear previous backup")?;
    }
    fs::create_dir_all(backup_dir).context("Failed to create backup directory")?;

    // Copy critical files (not the whole installation, just what we'll replace)
    let critical_files = [
        "nightshade_desktop.exe",
        "nightshade_bridge.dll",
        "flutter_windows.dll",
    ];

    for file in &critical_files {
        let src = install_dir.join(file);
        let dst = backup_dir.join(file);

        if src.exists() {
            fs::copy(&src, &dst).with_context(|| format!("Failed to backup {}", file))?;
        }
    }

    // Also backup the data folder if it exists
    let data_src = install_dir.join("data");
    let data_dst = backup_dir.join("data");
    if data_src.exists() {
        copy_dir_recursive(&data_src, &data_dst).context("Failed to backup data directory")?;
    }

    Ok(())
}

/// Apply the staged update
fn apply_update(staging_dir: &Path, install_dir: &Path) -> Result<()> {
    let mut skipped_files: Vec<String> = Vec::new();

    // Walk through staging directory and copy all files
    for entry in walkdir::WalkDir::new(staging_dir) {
        let entry = entry.context("Failed to read staging entry")?;
        let src_path = entry.path();
        let relative = src_path
            .strip_prefix(staging_dir)
            .context("Failed to get relative path")?;

        if relative.as_os_str().is_empty() {
            continue;
        }

        let dst_path = install_dir.join(relative);

        if entry.file_type().is_dir() {
            fs::create_dir_all(&dst_path)
                .with_context(|| format!("Failed to create directory: {:?}", dst_path))?;
        } else if entry.file_type().is_file() {
            // Ensure parent directory exists
            if let Some(parent) = dst_path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("Failed to create parent: {:?}", parent))?;
            }

            // Check if files are identical (skip if same size - quick check)
            if dst_path.exists() {
                let src_size = fs::metadata(src_path).map(|m| m.len()).unwrap_or(0);
                let dst_size = fs::metadata(&dst_path).map(|m| m.len()).unwrap_or(0);

                if src_size == dst_size {
                    // Files are likely identical, try to update but skip if locked
                    if let Err(_) = try_update_file(src_path, &dst_path) {
                        println!("  Skipping unchanged file: {:?}", relative);
                        skipped_files.push(relative.to_string_lossy().to_string());
                        continue;
                    }
                } else {
                    // Files are different, must update
                    try_update_file(src_path, &dst_path).with_context(|| {
                        format!("Failed to update critical file: {:?}", dst_path)
                    })?;
                }
            } else {
                // New file, just copy
                fs::copy(src_path, &dst_path)
                    .with_context(|| format!("Failed to copy {:?} to {:?}", src_path, dst_path))?;
            }

            println!("  Updated: {:?}", relative);
        }
    }

    if !skipped_files.is_empty() {
        println!("\nSkipped {} unchanged/locked files", skipped_files.len());
    }

    Ok(())
}

fn verify_installation(install_dir: &Path) -> Result<()> {
    let exe_path = install_dir.join("nightshade_desktop.exe");
    if !exe_path.exists() {
        return Err(anyhow::anyhow!(
            "Updated application executable not found after install: {:?}",
            exe_path
        ));
    }

    let bridge_path = install_dir.join("nightshade_bridge.dll");
    if !bridge_path.exists() {
        return Err(anyhow::anyhow!(
            "Updated bridge library not found after install: {:?}",
            bridge_path
        ));
    }

    Ok(())
}

/// Try to update a file, using rename-and-replace strategy
fn try_update_file(src: &Path, dst: &Path) -> Result<()> {
    // Strategy 1: Try direct delete and copy
    if let Ok(_) = fs::remove_file(dst) {
        fs::copy(src, dst)?;
        return Ok(());
    }

    // Strategy 2: Try rename to .old, then copy new
    let old_path = dst.with_extension("dll.old");
    if old_path.exists() {
        let _ = fs::remove_file(&old_path); // Try to clean up old backup
    }

    if let Ok(_) = fs::rename(dst, &old_path) {
        if let Ok(_) = fs::copy(src, dst) {
            let _ = fs::remove_file(&old_path); // Clean up
            return Ok(());
        } else {
            // Restore original
            let _ = fs::rename(&old_path, dst);
        }
    }

    // Strategy 3: Just try to overwrite in place
    if let Ok(_) = fs::copy(src, dst) {
        return Ok(());
    }

    Err(anyhow::anyhow!("Could not update file: {:?}", dst))
}

/// Copy a directory recursively
fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());

        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }

    Ok(())
}

fn restore_backup(backup_dir: &Path, install_dir: &Path) -> Result<()> {
    if !backup_dir.exists() {
        return Err(anyhow::anyhow!(
            "Backup directory does not exist: {:?}",
            backup_dir
        ));
    }

    for entry in walkdir::WalkDir::new(backup_dir) {
        let entry = entry.context("Failed to read backup entry")?;
        let src_path = entry.path();
        let relative = src_path
            .strip_prefix(backup_dir)
            .context("Failed to compute backup relative path")?;

        if relative.as_os_str().is_empty() {
            continue;
        }

        let dst_path = install_dir.join(relative);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&dst_path)
                .with_context(|| format!("Failed to recreate directory {:?}", dst_path))?;
        } else if entry.file_type().is_file() {
            if let Some(parent) = dst_path.parent() {
                fs::create_dir_all(parent).with_context(|| {
                    format!("Failed to create rollback parent directory {:?}", parent)
                })?;
            }
            fs::copy(src_path, &dst_path).with_context(|| {
                format!(
                    "Failed to restore backup file {:?} to {:?}",
                    src_path, dst_path
                )
            })?;
        }
    }

    Ok(())
}

/// Clean up the staging directory
fn cleanup_staging(staging_dir: &Path) -> Result<()> {
    // Why: only remove the staging dir itself. Its parent (`…/updates/`) holds
    // sibling artifacts the running update still needs — the `backup/`
    // directory used for rollback, the `pending_install.json` marker read by
    // the next-launch verification step, and any concurrently staged update.
    // Wiping the parent here destroys rollback state. The backup directory is
    // cleaned up by next-launch verification once it confirms the update is
    // healthy (see audit §7A.3).
    if staging_dir.exists() {
        fs::remove_dir_all(staging_dir).with_context(|| {
            format!("Failed to remove staging directory {:?}", staging_dir)
        })?;
    }
    Ok(())
}

fn remove_pending_marker(pending_file: &Path) -> Result<()> {
    if pending_file.exists() {
        fs::remove_file(pending_file)
            .with_context(|| format!("Failed to remove pending marker {:?}", pending_file))?;
    }
    Ok(())
}

/// Launch the updated application
fn launch_app(install_dir: &Path) -> Result<()> {
    let exe_path = install_dir.join("nightshade_desktop.exe");

    if !exe_path.exists() {
        return Err(anyhow::anyhow!(
            "Application executable not found: {:?}",
            exe_path
        ));
    }

    #[cfg(windows)]
    {
        Command::new(&exe_path)
            .current_dir(install_dir)
            .spawn()
            .context("Failed to launch application")?;
    }

    #[cfg(not(windows))]
    {
        Command::new(&exe_path)
            .current_dir(install_dir)
            .spawn()
            .context("Failed to launch application")?;
    }

    Ok(())
}
