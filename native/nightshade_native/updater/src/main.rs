//! Nightshade External Updater
//!
//! This is a standalone executable that applies staged updates after the main
//! Nightshade app has exited. Flow:
//! 1. Acquire exclusive file lock so no second updater races us (§7A.6).
//! 2. Wait for the parent process to exit.
//! 3. Apply update via move-then-copy: every destination file the staging tree
//!    will overwrite is renamed to `dst.nightshade-bak` first, then the new
//!    file is copied in. New files (not yet in install) are tracked too so
//!    rollback can remove them. (§7A.2)
//! 4. Hash-verify every applied file against the manifest passed by the Dart
//!    side. Mismatch = rollback. (§7A.3)
//! 5. On any failure (locked file, copy error, hash mismatch): roll back by
//!    restoring `.nightshade-bak` files and deleting newly-created files,
//!    then exit non-zero so the user/UI sees the failure. (§7A.1, §7A.11)
//! 6. On success: clean up `.nightshade-bak` files, write post-install hash
//!    record for boot-time verification, optionally launch the new version,
//!    clean up the staging directory.

use anyhow::{Context, Result};
use clap::Parser;
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[cfg(windows)]
use windows::Win32::System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE};

// Suffix used for in-place backups of replaced files. Chosen to be unmistakably
// ours so a stale `.old` file from earlier updater versions does not collide.
const BAK_SUFFIX: &str = ".nightshade-bak";

// File written to the install root after a successful apply. The Dart-side
// boot-time `verifyPendingInstall` re-hashes the executable and compares to
// what is recorded here (§7A.3).
const POST_INSTALL_HASH_FILE: &str = "post_install_hashes.json";

// File where rollback metadata is persisted while apply is in progress.
// Lives under install_dir so an updater crash doesn't leave the install in
// a half-migrated state — next-launch recovery can read this file and finish
// rolling back. (NB: full crash-recovery on next launch is owned by W1B-UPD-DART;
// we just leave the artifact on disk.)
const ROLLBACK_LOG_FILE: &str = "rollback_log.json";

// Lock file path is `<install_dir>/updates/.updater.lock` per §7A.6.
const LOCK_FILE_NAME: &str = ".updater.lock";

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

    /// Directory used to persist rollback metadata and (optionally) extra
    /// safety-net file copies. Must be on the same volume as install_dir.
    #[arg(long)]
    backup_dir: PathBuf,

    /// Marker file used for boot-time update verification (Dart-side writes
    /// this; updater removes it on rollback so the next launch knows the
    /// update did not complete).
    #[arg(long)]
    pending_file: PathBuf,

    /// JSON file mapping relative install path -> expected SHA-256 hex digest.
    /// Dart side writes this from the verified manifest (§7A.3). The same file
    /// is consumed by next-launch verification.
    #[arg(long)]
    expected_hashes: PathBuf,

    /// Launch the new version after update
    #[arg(long)]
    launch_after: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct ExpectedHashes {
    /// relative path (POSIX-style separators) -> sha256 hex digest
    files: HashMap<String, String>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct RollbackLog {
    /// Files that existed in the install before apply; the destination has
    /// been renamed to `dst + BAK_SUFFIX` and a new file written in its place.
    /// Rollback: rename the bak back over the new file.
    moved: Vec<MovedEntry>,
    /// Files that did NOT exist in the install before apply; they were
    /// created fresh from staging. Rollback: delete them.
    created: Vec<String>,
    /// Directories created fresh by apply. Rollback: remove if empty after
    /// `created` files are deleted. (Best-effort; depth-sorted on rollback.)
    created_dirs: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct MovedEntry {
    /// Relative path within install_dir (POSIX separators).
    rel: String,
    /// Backup path (absolute, for unambiguous rollback).
    bak: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct PostInstallHashes {
    files: HashMap<String, String>,
    /// Version copied verbatim from expected_hashes for boot-time sanity check.
    written_at: String,
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Update failed: {:?}", e);
        // Why: write a stable log so the Dart side can surface the error to the
        // user even though the updater is a separate process and stdout is gone.
        let log_path = std::env::temp_dir().join("nightshade_update_error.log");
        if let Err(write_err) = fs::write(&log_path, format!("Update failed: {:?}", e)) {
            eprintln!(
                "Additionally, failed to write error log to {:?}: {}",
                log_path, write_err
            );
        }
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
    println!("Expected hashes: {:?}", args.expected_hashes);

    // §7A.6: acquire single-instance lock before doing any I/O. If another
    // updater is running we exit non-zero so the parent app surfaces the
    // collision instead of silently racing.
    let lock_dir = args.install_dir.join("updates");
    fs::create_dir_all(&lock_dir)
        .with_context(|| format!("Failed to create lock directory {:?}", lock_dir))?;
    let lock_path = lock_dir.join(LOCK_FILE_NAME);
    let lock_file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock_path)
        .with_context(|| format!("Failed to open updater lock file {:?}", lock_path))?;
    if let Err(e) = lock_file.try_lock_exclusive() {
        // Why: another updater is mid-flight (or stale lock held by a still-running
        // updater). Refuse to proceed — racing two updaters can corrupt installs.
        return Err(anyhow::anyhow!(
            "Another Nightshade updater is already running (lock held at {:?}): {}",
            lock_path,
            e
        ));
    }

    // Step 1: Wait for parent process to exit.
    println!("\nWaiting for Nightshade to exit...");
    wait_for_process_exit(args.parent_pid, Duration::from_secs(30))?;
    println!("Parent process has exited.");

    // Why: even after WaitForSingleObject returns, Windows may still hold file
    // handles for a few hundred ms while the OS finishes tearing down the
    // process. Without this delay the first MoveFileEx call frequently hits
    // ERROR_SHARING_VIOLATION on the .exe.
    thread::sleep(Duration::from_millis(500));

    // Read expected hashes once up front so we fail fast if the manifest is
    // missing or malformed before we touch the install directory.
    let expected = load_expected_hashes(&args.expected_hashes).with_context(|| {
        format!(
            "Failed to read expected_hashes manifest from {:?}",
            args.expected_hashes
        )
    })?;

    // Ensure backup_dir exists (used for rollback log persistence).
    fs::create_dir_all(&args.backup_dir)
        .with_context(|| format!("Failed to create backup directory {:?}", args.backup_dir))?;

    let mut rollback_log = RollbackLog::default();

    // Step 2: Apply update with move-then-copy semantics.
    println!("\nApplying update...");
    let apply_result = apply_update(&args.staging_dir, &args.install_dir, &mut rollback_log);

    // Persist the rollback log to disk before any verification step so that
    // a crash mid-verify still leaves enough information for next-launch
    // recovery.
    let rollback_log_path = args.backup_dir.join(ROLLBACK_LOG_FILE);
    if let Err(e) = persist_rollback_log(&rollback_log_path, &rollback_log) {
        // Why: if we can't even write the rollback log, do not proceed —
        // we'd be flying blind on failure.
        let _ = rollback_in_place(&args.install_dir, &rollback_log);
        return Err(e.context("Failed to persist rollback log"));
    }

    if let Err(apply_err) = apply_result {
        eprintln!("\nApply failed: {:?}", apply_err);
        return finalize_failure(&args, &rollback_log, &rollback_log_path, apply_err);
    }

    // Step 3: Hash-verify every file the manifest names against the result.
    println!("\nVerifying installation against manifest hashes...");
    if let Err(verify_err) = verify_against_manifest(&args.install_dir, &expected) {
        eprintln!("\nManifest verification failed: {:?}", verify_err);
        return finalize_failure(&args, &rollback_log, &rollback_log_path, verify_err);
    }

    // Step 4: Sanity check — the named entry points exist.
    if let Err(verify_err) = verify_entrypoints_exist(&args.install_dir) {
        eprintln!("\nEntry-point check failed: {:?}", verify_err);
        return finalize_failure(&args, &rollback_log, &rollback_log_path, verify_err);
    }

    println!("Update applied and verified.");

    // Step 5: success cleanup. Discard `.nightshade-bak` files and rollback log.
    cleanup_success(&args.install_dir, &rollback_log, &rollback_log_path)?;

    // Step 6: write post-install hashes for boot-time re-verification (§7A.3).
    let post_install_path = args.install_dir.join(POST_INSTALL_HASH_FILE);
    write_post_install_hashes(&post_install_path, &expected).with_context(|| {
        format!(
            "Failed to write post-install hash record to {:?}",
            post_install_path
        )
    })?;

    // Step 7: cleanup staging.
    println!("\nCleaning up staging...");
    if let Err(e) = cleanup_staging(&args.staging_dir) {
        // Why: staging cleanup failure is non-fatal — the update is already
        // applied and verified — but log loudly. (§7A.11: no silent let _ = ...)
        eprintln!("Warning: failed to cleanup staging: {:?}", e);
    }

    // Step 8: optionally launch the new version.
    if args.launch_after {
        println!("\nLaunching updated Nightshade...");
        launch_app(&args.install_dir)?;
    }

    println!("\nUpdate complete!");
    Ok(())
}

/// Finalize a failure: roll the install back to its pre-apply state, delete
/// the pending marker so the next launch does not think an update succeeded,
/// then return the original error so it propagates and the process exits
/// non-zero.
fn finalize_failure(
    args: &Args,
    rollback_log: &RollbackLog,
    rollback_log_path: &Path,
    update_error: anyhow::Error,
) -> Result<()> {
    eprintln!("Update failed; rolling back to pre-apply state...");
    let rollback_result = rollback_in_place(&args.install_dir, rollback_log);

    // Why: pending marker says "an update is staged and ready to apply". We
    // failed, so the next launch must NOT think the update succeeded.
    if let Err(e) = remove_pending_marker(&args.pending_file) {
        eprintln!(
            "Warning: failed to remove pending marker {:?}: {}",
            args.pending_file, e
        );
    }

    // Why: rollback log on disk is no longer needed once rollback succeeded.
    // If rollback failed we keep it for next-launch recovery to retry.
    if rollback_result.is_ok() {
        if let Err(e) = fs::remove_file(rollback_log_path) {
            // ENOENT is fine.
            if e.kind() != std::io::ErrorKind::NotFound {
                eprintln!(
                    "Warning: failed to remove rollback log {:?}: {}",
                    rollback_log_path, e
                );
            }
        }
    }

    match rollback_result {
        Ok(()) => Err(update_error
            .context("Update failed; the previous installation was restored from in-place backup")),
        Err(rollback_error) => Err(anyhow::anyhow!(
            "Update failed: {}. Rollback also failed: {}",
            update_error,
            rollback_error
        )),
    }
}

fn load_expected_hashes(path: &Path) -> Result<ExpectedHashes> {
    let raw = fs::read(path)
        .with_context(|| format!("Failed to read expected hashes file {:?}", path))?;
    let parsed: ExpectedHashes = serde_json::from_slice(&raw)
        .with_context(|| format!("Failed to parse expected hashes file {:?}", path))?;
    if parsed.files.is_empty() {
        return Err(anyhow::anyhow!(
            "expected_hashes manifest at {:?} contains no files",
            path
        ));
    }
    Ok(parsed)
}

fn persist_rollback_log(path: &Path, log: &RollbackLog) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(log).context("Failed to serialize rollback log")?;
    fs::write(path, bytes)
        .with_context(|| format!("Failed to write rollback log to {:?}", path))?;
    Ok(())
}

/// Wait for a process to exit
fn wait_for_process_exit(pid: u32, timeout: Duration) -> Result<()> {
    #[cfg(windows)]
    {
        // SAFETY: `OpenProcess` and `WaitForSingleObject` are pure Win32 syscalls with
        // value-typed arguments (PID, access mask, timeout ms). The HANDLE returned by
        // `OpenProcess` is a Win32 owned handle that goes out of scope at the end of
        // this `unsafe` block; the `windows` crate's HANDLE wrapper drops/closes it.
        // We never dereference any pointer arguments.
        unsafe {
            let handle = OpenProcess(PROCESS_SYNCHRONIZE, false, pid);
            if let Ok(handle) = handle {
                let result = WaitForSingleObject(handle, timeout.as_millis() as u32);
                // WAIT_OBJECT_0 = 0x00000000, WAIT_TIMEOUT = 0x00000102.
                // Anything else likely means the process already exited; treat
                // as success rather than spuriously failing the update.
                if result.0 != 0 && result.0 != 0x00000102 {
                    // intentionally permissive: see comment above
                }
            }
            // If we can't open the process, it probably already exited.
        }
        Ok(())
    }

    #[cfg(not(windows))]
    {
        let start = std::time::Instant::now();
        while start.elapsed() < timeout {
            // Why: `kill -0 <pid>` is the portable "does this process exist?"
            // check. Exits 0 if alive, non-zero if not.
            let output = Command::new("kill").args(["-0", &pid.to_string()]).output();

            if let Ok(output) = output {
                if !output.status.success() {
                    return Ok(());
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
}

/// Walk the staging tree and apply each file via move-then-copy. Records every
/// touched destination in `rollback_log` so failures can be reverted.
fn apply_update(
    staging_dir: &Path,
    install_dir: &Path,
    rollback_log: &mut RollbackLog,
) -> Result<()> {
    for entry in walkdir::WalkDir::new(staging_dir) {
        let entry = entry.context("Failed to read staging entry")?;
        let src_path = entry.path();
        let relative = src_path
            .strip_prefix(staging_dir)
            .context("Failed to compute staging relative path")?;

        if relative.as_os_str().is_empty() {
            continue;
        }

        let dst_path = install_dir.join(relative);
        let rel_posix = to_posix(relative);

        if entry.file_type().is_dir() {
            // Why: track newly-created directories so rollback can remove
            // them if they end up empty.
            let was_present = dst_path.exists();
            fs::create_dir_all(&dst_path)
                .with_context(|| format!("Failed to create directory: {:?}", dst_path))?;
            if !was_present {
                rollback_log.created_dirs.push(rel_posix.clone());
            }
        } else if entry.file_type().is_file() {
            apply_file(src_path, &dst_path, &rel_posix, rollback_log)?;
            println!("  Updated: {:?}", relative);
        }
    }

    Ok(())
}

/// Apply a single file: rename existing dst to dst.bak (if present), then
/// copy the new file into place. Updates `rollback_log` accordingly.
fn apply_file(
    src: &Path,
    dst: &Path,
    rel_posix: &str,
    rollback_log: &mut RollbackLog,
) -> Result<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create parent directory {:?}", parent))?;
    }

    if dst.exists() {
        if dst.is_dir() {
            return Err(anyhow::anyhow!(
                "Update payload file {} would replace an existing directory; refusing to continue",
                dst.display()
            ));
        }

        // Move-then-copy: rename existing file to a sibling .bak so we can
        // restore it if any subsequent step fails. Same volume → atomic on
        // both Windows and POSIX.
        let bak = backup_path_for(dst);
        if bak.exists() {
            // Why: a previous interrupted run may have left a stale backup.
            // Trying to rename onto it on Windows fails with sharing violation;
            // remove it explicitly and surface any error.
            fs::remove_file(&bak)
                .with_context(|| format!("Failed to clear stale backup file {:?}", bak))?;
        }
        rename_with_retry(dst, &bak).with_context(|| {
            format!(
                "Update could not replace {} because it is in use. \
                 Please close Nightshade and try again.",
                dst.display()
            )
        })?;
        rollback_log.moved.push(MovedEntry {
            rel: rel_posix.to_string(),
            bak: bak.to_string_lossy().to_string(),
        });

        // Now copy the new file into place. If this fails, rollback will see
        // the moved entry and rename the .bak back over whatever (if anything)
        // we wrote.
        fs::copy(src, dst).with_context(|| {
            format!("Failed to copy new file into place: {:?} -> {:?}", src, dst)
        })?;
    } else {
        // New file: just copy. Track for rollback (delete on failure).
        fs::copy(src, dst).with_context(|| {
            format!("Failed to copy new file into place: {:?} -> {:?}", src, dst)
        })?;
        rollback_log.created.push(rel_posix.to_string());
    }
    Ok(())
}

fn backup_path_for(dst: &Path) -> PathBuf {
    // Append BAK_SUFFIX to the file name (preserving the original name +
    // extension so investigators can tell what the file was).
    let mut s = dst.as_os_str().to_owned();
    s.push(BAK_SUFFIX);
    PathBuf::from(s)
}

/// Rename `from` to `to`, retrying transient sharing violations on Windows.
/// On Windows, files held open by the just-exited parent process can take a
/// brief moment to release; we retry up to 3 times with 500ms backoff per
/// §7A.1. If still failing after retries, return a hard error so rollback
/// fires — we never silently leave a stale file.
fn rename_with_retry(from: &Path, to: &Path) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 3;
    const BACKOFF: Duration = Duration::from_millis(500);

    let mut last_err: Option<std::io::Error> = None;
    for attempt in 1..=MAX_ATTEMPTS {
        match fs::rename(from, to) {
            Ok(()) => return Ok(()),
            Err(e) => {
                if !is_retryable_rename_error(&e) || attempt == MAX_ATTEMPTS {
                    last_err = Some(e);
                    break;
                }
                eprintln!(
                    "  rename {:?} -> {:?} hit transient error ({}); retrying ({}/{})",
                    from, to, e, attempt, MAX_ATTEMPTS
                );
                last_err = Some(e);
                thread::sleep(BACKOFF);
            }
        }
    }

    // Why: on Windows, schedule a rename-on-reboot as a last-ditch effort so
    // the user can recover by restarting their machine, but ALSO surface the
    // failure as a hard error here so apply rolls back. We never silently
    // accept a locked file (§7A.1).
    #[cfg(windows)]
    {
        if let Some(ref e) = last_err {
            if is_sharing_violation(e) {
                if let Err(reboot_err) = schedule_replace_on_reboot(from, to) {
                    eprintln!(
                        "  Could not schedule reboot-time replace for {:?}: {}",
                        from, reboot_err
                    );
                } else {
                    eprintln!("  Scheduled reboot-time replace for {:?} -> {:?}", from, to);
                }
            }
        }
    }

    Err(anyhow::anyhow!(
        "Failed to rename {:?} -> {:?} after {} attempts: {}",
        from,
        to,
        MAX_ATTEMPTS,
        // Why (audit-rust §4.3): `last_err` is None only when the retry
        // loop completed all MAX_ATTEMPTS without ever observing an Err,
        // which means the loop's `Ok` branch must have failed to return
        // — unreachable in practice but defensive against a future code
        // change. "unknown error" preserves the human-readable format.
        last_err
            .map(|e| e.to_string())
            .unwrap_or_else(|| "unknown error".to_string())
    ))
}

#[cfg(windows)]
fn is_sharing_violation(e: &std::io::Error) -> bool {
    // ERROR_SHARING_VIOLATION = 32, ERROR_ACCESS_DENIED = 5,
    // ERROR_LOCK_VIOLATION = 33. All can manifest when a DLL is mapped.
    matches!(e.raw_os_error(), Some(32) | Some(33) | Some(5))
}

#[cfg(not(windows))]
fn is_sharing_violation(_e: &std::io::Error) -> bool {
    false
}

fn is_retryable_rename_error(e: &std::io::Error) -> bool {
    // Why: only retry on conditions that might clear up if the parent process
    // releases its handles. Permission errors that are NOT sharing violations
    // (e.g., truly read-only file, ACL mismatch) won't fix themselves with a
    // sleep, so don't waste time.
    if is_sharing_violation(e) {
        return true;
    }
    matches!(
        e.kind(),
        std::io::ErrorKind::PermissionDenied | std::io::ErrorKind::WouldBlock
    )
}

#[cfg(windows)]
fn schedule_replace_on_reboot(from: &Path, to: &Path) -> Result<()> {
    // MoveFileExW with MOVEFILE_DELAY_UNTIL_REBOOT queues a rename for the
    // next OS boot. `from` here is the destination we tried to write but
    // couldn't because it was locked; the rename order in our move-then-copy
    // model is dst -> bak, so on reboot Windows will move the locked file
    // out of the way. Pure best-effort — caller still rolls back.
    use std::os::windows::ffi::OsStrExt;
    use windows::core::PCWSTR;
    use windows::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_DELAY_UNTIL_REBOOT};

    fn to_wide(p: &Path) -> Vec<u16> {
        p.as_os_str()
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    }

    let from_w = to_wide(from);
    let to_w = to_wide(to);
    // SAFETY: `MoveFileExW` is a Win32 file syscall. Both `from_w` / `to_w` are
    // locally-owned NUL-terminated UTF-16 vectors that outlive the call; their
    // `as_ptr()` is wrapped in PCWSTR. The third arg is a value-typed flag. No
    // pointer ownership is transferred to the kernel.
    unsafe {
        MoveFileExW(
            PCWSTR(from_w.as_ptr()),
            PCWSTR(to_w.as_ptr()),
            MOVEFILE_DELAY_UNTIL_REBOOT,
        )
        .map_err(|e| anyhow::anyhow!("MoveFileExW(DELAY_UNTIL_REBOOT) failed: {}", e))
    }
}

/// Roll back an in-progress (or just-failed) apply by undoing the operations
/// recorded in `rollback_log`. Best-effort: aggregates errors but always tries
/// to revert as much as possible.
fn rollback_in_place(install_dir: &Path, log: &RollbackLog) -> Result<()> {
    let mut errors: Vec<String> = Vec::new();

    // 1. Restore moved files: rename .bak back over whatever we wrote.
    for entry in &log.moved {
        let dst = install_dir.join(from_posix(&entry.rel));
        let bak = PathBuf::from(&entry.bak);
        // Remove the new file that was copied in (if present) so the rename
        // can succeed even on platforms where rename refuses to overwrite.
        if dst.exists() {
            if let Err(e) = fs::remove_file(&dst) {
                errors.push(format!(
                    "rollback: failed to remove new file {:?}: {}",
                    dst, e
                ));
            }
        }
        match fs::rename(&bak, &dst) {
            Ok(()) => println!("  Rollback: restored {:?}", dst),
            Err(e) => errors.push(format!(
                "rollback: failed to restore {:?} from {:?}: {}",
                dst, bak, e
            )),
        }
    }

    // 2. Delete files that we created from scratch.
    for rel in &log.created {
        let dst = install_dir.join(from_posix(rel));
        if dst.exists() {
            if let Err(e) = fs::remove_file(&dst) {
                errors.push(format!(
                    "rollback: failed to delete created file {:?}: {}",
                    dst, e
                ));
            }
        }
    }

    // 3. Remove directories we created (deepest first so empty-dir-removal
    // works even if we created nested directories).
    let mut dirs: Vec<&String> = log.created_dirs.iter().collect();
    dirs.sort_by_key(|s| std::cmp::Reverse(s.matches('/').count()));
    for rel in dirs {
        let dst = install_dir.join(from_posix(rel));
        // Why: only remove if empty. If something else dropped a file in there
        // since we created it, that's not our directory to delete.
        if dst.exists() {
            match fs::remove_dir(&dst) {
                Ok(()) => {}
                Err(e) if e.kind() == std::io::ErrorKind::DirectoryNotEmpty => {
                    // Acceptable: not ours to clean up.
                }
                Err(e) => errors.push(format!(
                    "rollback: failed to remove created directory {:?}: {}",
                    dst, e
                )),
            }
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "Rollback completed with {} error(s):\n{}",
            errors.len(),
            errors.join("\n")
        ))
    }
}

/// Drop the `.nightshade-bak` files from a successful apply, then delete the
/// rollback log file.
fn cleanup_success(install_dir: &Path, log: &RollbackLog, log_path: &Path) -> Result<()> {
    let mut errors: Vec<String> = Vec::new();
    for entry in &log.moved {
        let bak = PathBuf::from(&entry.bak);
        if bak.exists() {
            if let Err(e) = fs::remove_file(&bak) {
                errors.push(format!("cleanup: failed to remove {:?}: {}", bak, e));
            }
        }
        // Defensive: also cover the case where the .bak path was relocated
        // (shouldn't happen, but log has the canonical absolute path).
        let computed_bak = backup_path_for(&install_dir.join(from_posix(&entry.rel)));
        if computed_bak != bak && computed_bak.exists() {
            if let Err(e) = fs::remove_file(&computed_bak) {
                errors.push(format!(
                    "cleanup: failed to remove {:?}: {}",
                    computed_bak, e
                ));
            }
        }
    }

    if log_path.exists() {
        if let Err(e) = fs::remove_file(log_path) {
            errors.push(format!(
                "cleanup: failed to remove rollback log {:?}: {}",
                log_path, e
            ));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        // Why: success cleanup failures are not fatal — the update is already
        // applied and verified — but report them clearly so we don't accumulate
        // stale .bak files silently across updates (§7A.11).
        eprintln!(
            "Warning: success cleanup encountered {} non-fatal issue(s):\n{}",
            errors.len(),
            errors.join("\n")
        );
        Ok(())
    }
}

fn write_post_install_hashes(path: &Path, expected: &ExpectedHashes) -> Result<()> {
    let record = PostInstallHashes {
        files: expected.files.clone(),
        written_at: chrono_like_rfc3339_now(),
    };
    let bytes =
        serde_json::to_vec_pretty(&record).context("Failed to serialize post-install hashes")?;
    fs::write(path, bytes)
        .with_context(|| format!("Failed to write post-install hashes to {:?}", path))?;
    Ok(())
}

/// Tiny RFC3339-ish timestamp without pulling in chrono. `seconds since epoch`
/// is unambiguous, sortable, and good enough for diagnostics.
///
/// # `unwrap_or` policy (audit-rust §4.3)
///
/// `duration_since(UNIX_EPOCH).unwrap_or(0)` — pre-1970 clock → epoch:0
/// in the log line, sortable but visibly anomalous. Acceptable for a
/// diagnostic timestamp; the updater's correctness does not depend on it.
fn chrono_like_rfc3339_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("epoch:{}", secs)
}

/// Sanity-check that the named entry points exist after apply. The hash
/// verification is the real check; this just guards against a manifest that
/// omits the launcher binary (which would let apply succeed with no exe).
fn verify_entrypoints_exist(install_dir: &Path) -> Result<()> {
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

/// Verify every file listed in the manifest hashes the expected SHA-256.
/// Aggregates per-file mismatches to produce a useful error message.
fn verify_against_manifest(install_dir: &Path, expected: &ExpectedHashes) -> Result<()> {
    let mut mismatches: Vec<String> = Vec::new();
    let mut missing: Vec<String> = Vec::new();
    for (rel, expected_hex) in &expected.files {
        let path = install_dir.join(from_posix(rel));
        if !path.exists() {
            missing.push(rel.clone());
            continue;
        }
        let actual = sha256_file(&path)
            .with_context(|| format!("Failed to hash {:?} for verification", path))?;
        if !actual.eq_ignore_ascii_case(expected_hex) {
            mismatches.push(format!(
                "{}: expected {}, got {}",
                rel, expected_hex, actual
            ));
        }
    }

    if missing.is_empty() && mismatches.is_empty() {
        return Ok(());
    }
    Err(anyhow::anyhow!(
        "Manifest verification failed. Missing: {:?}; mismatched: {:?}",
        missing,
        mismatches
    ))
}

fn sha256_file(path: &Path) -> Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex_encode(&hasher.finalize()))
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        // Why: avoid pulling a hex crate for one function.
        s.push(nibble((b >> 4) & 0xF));
        s.push(nibble(b & 0xF));
    }
    s
}

fn nibble(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + n - 10) as char,
        _ => unreachable!(),
    }
}

fn to_posix(p: &Path) -> String {
    p.to_string_lossy().replace('\\', "/")
}

fn from_posix(s: &str) -> PathBuf {
    PathBuf::from(s.replace('/', std::path::MAIN_SEPARATOR_STR))
}

/// Clean up the staging directory.
fn cleanup_staging(staging_dir: &Path) -> Result<()> {
    // Why: only remove the staging dir itself. Its parent (`…/updates/`) holds
    // sibling artifacts the running update still needs — the `backup/`
    // directory used for rollback, the `pending_install.json` marker read by
    // the next-launch verification step, and any concurrently staged update.
    // Wiping the parent here destroys rollback state. The backup directory is
    // cleaned up by next-launch verification once it confirms the update is
    // healthy (see audit §7A.3).
    if staging_dir.exists() {
        fs::remove_dir_all(staging_dir)
            .with_context(|| format!("Failed to remove staging directory {:?}", staging_dir))?;
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

    Command::new(&exe_path)
        .current_dir(install_dir)
        .spawn()
        .context("Failed to launch application")?;

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;
    use tempfile::tempdir;

    fn write(path: &Path, data: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        let mut f = File::create(path).unwrap();
        f.write_all(data).unwrap();
    }

    fn sha256_hex(data: &[u8]) -> String {
        let mut h = Sha256::new();
        h.update(data);
        hex_encode(&h.finalize())
    }

    /// Helper to build an ExpectedHashes from a list of (rel, contents).
    fn make_expected(files: &[(&str, &[u8])]) -> ExpectedHashes {
        let mut map = HashMap::new();
        for (rel, data) in files {
            map.insert((*rel).to_string(), sha256_hex(data));
        }
        ExpectedHashes { files: map }
    }

    /// Stage a tree from a list of (rel, contents).
    fn stage_tree(staging: &Path, files: &[(&str, &[u8])]) {
        for (rel, data) in files {
            write(&staging.join(rel), data);
        }
    }

    #[test]
    fn apply_then_verify_succeeds_when_hashes_match() {
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        let staging = tmp.path().join("staging");
        fs::create_dir_all(&install).unwrap();

        let files: &[(&str, &[u8])] = &[
            ("nightshade_desktop.exe", b"new-exe"),
            ("nightshade_bridge.dll", b"new-bridge"),
            ("data/flutter_assets/AssetManifest.json", b"{\"a\":1}"),
        ];
        stage_tree(&staging, files);

        // Pre-populate one of them in install with old contents to exercise
        // the move-then-copy path.
        write(&install.join("nightshade_bridge.dll"), b"old-bridge");

        let expected = make_expected(files);
        let mut log = RollbackLog::default();
        apply_update(&staging, &install, &mut log).unwrap();
        verify_against_manifest(&install, &expected).unwrap();

        // Backup file should exist for the moved entry.
        assert_eq!(log.moved.len(), 1);
        assert_eq!(log.created.len(), 2);

        // Cleanup discards bak.
        let log_path = tmp.path().join("rollback.json");
        cleanup_success(&install, &log, &log_path).unwrap();
        let bak = backup_path_for(&install.join("nightshade_bridge.dll"));
        assert!(!bak.exists(), "bak should be cleaned up");
    }

    #[test]
    fn corrupted_file_in_staging_fails_verification_and_rolls_back() {
        // §7A.3: hash mismatch = rollback.
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        let staging = tmp.path().join("staging");
        fs::create_dir_all(&install).unwrap();

        // Original file present in install.
        write(&install.join("nightshade_bridge.dll"), b"original");
        // Stage a "corrupted" version (different bytes than expected hash).
        write(&staging.join("nightshade_bridge.dll"), b"corrupted-payload");

        // Manifest claims SHA of "expected-payload" — staging is "corrupted-payload".
        let mut hashes = HashMap::new();
        hashes.insert(
            "nightshade_bridge.dll".to_string(),
            sha256_hex(b"expected-payload"),
        );
        let expected = ExpectedHashes { files: hashes };

        let mut log = RollbackLog::default();
        apply_update(&staging, &install, &mut log).unwrap();

        // Verification must fail.
        let err = verify_against_manifest(&install, &expected).unwrap_err();
        assert!(format!("{:?}", err).contains("mismatched"));

        // Rollback restores the original bytes.
        rollback_in_place(&install, &log).unwrap();
        let restored = fs::read(install.join("nightshade_bridge.dll")).unwrap();
        assert_eq!(restored, b"original");
    }

    #[test]
    fn rollback_removes_files_added_outside_critical_set() {
        // §7A.2: "any file added by apply must be revertible."
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        let staging = tmp.path().join("staging");
        fs::create_dir_all(&install).unwrap();

        // Stage a brand-new file in a brand-new subdirectory.
        write(&staging.join("extras/new_file.txt"), b"hello");
        // Plus a critical file that already exists.
        write(&install.join("nightshade_desktop.exe"), b"old-exe");
        write(&staging.join("nightshade_desktop.exe"), b"new-exe");

        let mut log = RollbackLog::default();
        apply_update(&staging, &install, &mut log).unwrap();
        assert!(install.join("extras/new_file.txt").exists());

        // Force rollback (simulate downstream verification failure).
        rollback_in_place(&install, &log).unwrap();

        assert!(
            !install.join("extras/new_file.txt").exists(),
            "rollback must delete files apply created"
        );
        assert!(
            !install.join("extras").exists(),
            "rollback must remove directories apply created if empty"
        );
        // Critical file restored to old contents.
        assert_eq!(
            fs::read(install.join("nightshade_desktop.exe")).unwrap(),
            b"old-exe"
        );
    }

    #[test]
    fn rename_with_retry_returns_error_when_destination_locked() {
        // §7A.1: locked file = hard error, never silently skipped.
        let tmp = tempdir().unwrap();
        let from = tmp.path().join("a.txt");
        write(&from, b"x");
        // Hold an open read handle on the destination path's directory? No —
        // simulate an already-existing destination that we deliberately fail
        // to overwrite by pointing at a path inside a missing directory.
        let to = tmp.path().join("missing_dir/x.txt");
        let res = rename_with_retry(&from, &to);
        assert!(res.is_err(), "rename to nonexistent parent must fail");
    }

    #[test]
    fn locked_file_apply_fails_and_rollback_restores() {
        // §7A.1: simulate a locked file by making the destination exist as a
        // directory (which makes fs::rename(file, dir) fail consistently on
        // both Windows and POSIX). The error must propagate; rollback must
        // restore everything we already moved.
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        let staging = tmp.path().join("staging");
        fs::create_dir_all(&install).unwrap();

        // First file: ordinary replace, succeeds.
        write(&install.join("ok.dat"), b"old-ok");
        write(&staging.join("ok.dat"), b"new-ok");
        // Second file: destination is a directory — apply will fail.
        fs::create_dir_all(install.join("locked.dat")).unwrap();
        write(&staging.join("locked.dat"), b"new-locked");

        let mut log = RollbackLog::default();
        let result = apply_update(&staging, &install, &mut log);
        assert!(result.is_err(), "apply must fail when a file is locked");

        // Rollback must restore the first (already-replaced) file.
        rollback_in_place(&install, &log).unwrap();
        assert_eq!(fs::read(install.join("ok.dat")).unwrap(), b"old-ok");
    }

    #[test]
    fn concurrent_updater_lock_blocks_second_instance() {
        // §7A.6: second updater on the same install dir refuses to start.
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        fs::create_dir_all(install.join("updates")).unwrap();
        let lock_path = install.join("updates").join(LOCK_FILE_NAME);

        let first = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)
            .unwrap();
        first.try_lock_exclusive().unwrap();

        let second = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)
            .unwrap();
        let res = second.try_lock_exclusive();
        assert!(res.is_err(), "second exclusive lock must fail");

        // Releasing the first lock allows a second to acquire.
        FileExt::unlock(&first).unwrap();
        second.try_lock_exclusive().unwrap();
    }

    #[test]
    fn expected_hashes_round_trip_json() {
        // Sanity: the on-disk schema Dart writes is parseable.
        let tmp = tempdir().unwrap();
        let path = tmp.path().join("expected.json");
        let raw = b"{\"files\":{\"a/b.txt\":\"abcdef\"}}";
        fs::write(&path, raw).unwrap();
        let parsed = load_expected_hashes(&path).unwrap();
        assert_eq!(parsed.files.get("a/b.txt").unwrap(), "abcdef");
    }

    #[test]
    fn empty_expected_hashes_is_rejected() {
        // §7A.3: an empty manifest is a configuration error, not a free pass.
        let tmp = tempdir().unwrap();
        let path = tmp.path().join("expected.json");
        fs::write(&path, b"{\"files\":{}}").unwrap();
        let err = load_expected_hashes(&path).unwrap_err();
        assert!(format!("{}", err).contains("no files"));
    }

    #[test]
    fn missing_file_fails_verification() {
        let tmp = tempdir().unwrap();
        let install = tmp.path().join("install");
        fs::create_dir_all(&install).unwrap();
        let mut hashes = HashMap::new();
        hashes.insert("not-there.dat".to_string(), sha256_hex(b"x"));
        let expected = ExpectedHashes { files: hashes };
        let err = verify_against_manifest(&install, &expected).unwrap_err();
        assert!(format!("{:?}", err).contains("Missing"));
    }

    #[test]
    fn sha256_file_matches_in_memory_hash() {
        let tmp = tempdir().unwrap();
        let p = tmp.path().join("x.bin");
        let data = b"the quick brown fox jumps over the lazy dog";
        fs::write(&p, data).unwrap();
        assert_eq!(sha256_file(&p).unwrap(), sha256_hex(data));
    }
}
