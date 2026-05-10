//! Session checkpoint for crash recovery
//!
//! This module provides functionality to save and restore sequence execution state
//! for recovery after unexpected crashes or restarts.

use crate::triggers::TriggerState;
use crate::{
    ExecutorState, MeridianTriggerMethod, NodeId, NodeStatus, PierSide, SafetyFailMode,
    SequenceDefinition,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;

/// Current checkpoint schema version.
pub const CHECKPOINT_VERSION: u32 = 2;

/// Serializable copy of trigger state needed to resume without repeating actions.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TriggerStateSnapshot {
    pub baseline_hfr: Option<f64>,
    pub current_hfr: Option<f64>,
    pub autofocus_invalidated: bool,
    pub autofocus_invalidation_reason: Option<String>,
    pub current_hour_angle: Option<f64>,
    pub pier_side: Option<PierSide>,
    pub mount_tracking_limit_time: Option<i64>,
    pub has_flipped_this_target: bool,
    pub current_target_name: Option<String>,
    pub next_meridian_flip_time: Option<i64>,
    pub guiding_enabled: bool,
    pub guide_star_lost: bool,
    pub current_humidity: Option<f64>,
    pub current_altitude: Option<f64>,
    pub weather_safe: bool,
    pub baseline_temperature: Option<f64>,
    pub current_temperature: Option<f64>,
    pub baseline_focuser_position: Option<i32>,
    pub filter_changed: bool,
    pub current_filter: Option<String>,
    pub dawn_time: Option<i64>,
    pub observer_latitude: Option<f64>,
    pub observer_longitude: Option<f64>,
    pub completed_exposures: u32,
    pub last_autofocus_frame: u32,
    pub last_dither_frame: u32,
    pub last_plate_solve_ra: Option<f64>,
    pub last_plate_solve_dec: Option<f64>,
    pub last_plate_solve_pixel_scale: Option<f64>,
    pub target_ra: Option<f64>,
    pub target_dec: Option<f64>,
    pub mount_is_tracking: Option<bool>,
    pub mount_tracking_expected: bool,
    pub mount_tracking_lost: bool,
    pub mount_slewing: Option<bool>,
    pub mount_parked: Option<bool>,
    pub mount_status_query_failed: bool,
    pub tracking_limit_detected_at: Option<i64>,
    pub meridian_trigger_method: Option<MeridianTriggerMethod>,
    pub dome_shutter_status: Option<String>,
    pub dome_shutter_open_expected: bool,
    pub grid_dither_index: u32,
    pub safety_fail_mode: SafetyFailMode,
    pub triggers_enabled: bool,
    pub filter_focus_offsets: HashMap<String, i32>,
}

impl TriggerStateSnapshot {
    pub fn from_state(
        state: &TriggerState,
        safety_fail_mode: SafetyFailMode,
        triggers_enabled: bool,
        filter_focus_offsets: HashMap<String, i32>,
    ) -> Self {
        Self {
            baseline_hfr: state.baseline_hfr,
            current_hfr: state.current_hfr,
            autofocus_invalidated: state.autofocus_invalidated,
            autofocus_invalidation_reason: state.autofocus_invalidation_reason.clone(),
            current_hour_angle: state.current_hour_angle,
            pier_side: state.pier_side,
            mount_tracking_limit_time: state.mount_tracking_limit_time,
            has_flipped_this_target: state.has_flipped_this_target,
            current_target_name: state.current_target_name.clone(),
            next_meridian_flip_time: state.next_meridian_flip_time,
            guiding_enabled: state.guiding_enabled,
            guide_star_lost: state.guide_star_lost,
            current_humidity: state.current_humidity,
            current_altitude: state.current_altitude,
            weather_safe: state.weather_safe,
            baseline_temperature: state.baseline_temperature,
            current_temperature: state.current_temperature,
            baseline_focuser_position: state.baseline_focuser_position,
            filter_changed: state.filter_changed,
            current_filter: state.current_filter.clone(),
            dawn_time: state.dawn_time,
            observer_latitude: state.observer_latitude,
            observer_longitude: state.observer_longitude,
            completed_exposures: state.completed_exposures,
            last_autofocus_frame: state.last_autofocus_frame,
            last_dither_frame: state.last_dither_frame,
            last_plate_solve_ra: state.last_plate_solve_ra,
            last_plate_solve_dec: state.last_plate_solve_dec,
            last_plate_solve_pixel_scale: state.last_plate_solve_pixel_scale,
            target_ra: state.target_ra,
            target_dec: state.target_dec,
            mount_is_tracking: state.mount_is_tracking,
            mount_tracking_expected: state.mount_tracking_expected,
            mount_tracking_lost: state.mount_tracking_lost,
            mount_slewing: state.mount_slewing,
            mount_parked: state.mount_parked,
            mount_status_query_failed: state.mount_status_query_failed,
            tracking_limit_detected_at: state.tracking_limit_detected_at,
            meridian_trigger_method: state.meridian_trigger_method,
            dome_shutter_status: state.dome_shutter_status.clone(),
            dome_shutter_open_expected: state.dome_shutter_open_expected,
            grid_dither_index: state.grid_dither_index,
            safety_fail_mode,
            triggers_enabled,
            filter_focus_offsets,
        }
    }

    pub fn restore_into(&self, state: &mut TriggerState) {
        state.baseline_hfr = self.baseline_hfr;
        state.current_hfr = self.current_hfr;
        state.autofocus_invalidated = self.autofocus_invalidated;
        state.autofocus_invalidation_reason = self.autofocus_invalidation_reason.clone();
        state.current_hour_angle = self.current_hour_angle;
        state.pier_side = self.pier_side;
        state.mount_tracking_limit_time = self.mount_tracking_limit_time;
        state.has_flipped_this_target = self.has_flipped_this_target;
        state.current_target_name = self.current_target_name.clone();
        state.next_meridian_flip_time = self.next_meridian_flip_time;
        state.guiding_enabled = self.guiding_enabled;
        state.guide_star_lost = self.guide_star_lost;
        state.current_humidity = self.current_humidity;
        state.current_altitude = self.current_altitude;
        state.weather_safe = self.weather_safe;
        state.baseline_temperature = self.baseline_temperature;
        state.current_temperature = self.current_temperature;
        state.baseline_focuser_position = self.baseline_focuser_position;
        state.filter_changed = self.filter_changed;
        state.current_filter = self.current_filter.clone();
        state.dawn_time = self.dawn_time;
        state.observer_latitude = self.observer_latitude;
        state.observer_longitude = self.observer_longitude;
        state.completed_exposures = self.completed_exposures;
        state.last_autofocus_frame = self.last_autofocus_frame;
        state.last_dither_frame = self.last_dither_frame;
        state.last_plate_solve_ra = self.last_plate_solve_ra;
        state.last_plate_solve_dec = self.last_plate_solve_dec;
        state.last_plate_solve_pixel_scale = self.last_plate_solve_pixel_scale;
        state.target_ra = self.target_ra;
        state.target_dec = self.target_dec;
        state.mount_is_tracking = self.mount_is_tracking;
        state.mount_tracking_expected = self.mount_tracking_expected;
        state.mount_tracking_lost = self.mount_tracking_lost;
        state.mount_slewing = self.mount_slewing;
        state.mount_parked = self.mount_parked;
        state.mount_status_query_failed = self.mount_status_query_failed;
        state.tracking_limit_detected_at = self.tracking_limit_detected_at;
        state.meridian_trigger_method = self.meridian_trigger_method;
        state.dome_shutter_status = self.dome_shutter_status.clone();
        state.dome_shutter_open_expected = self.dome_shutter_open_expected;
        state.grid_dither_index = self.grid_dither_index;
    }
}

/// Checkpoint containing all state needed to resume a sequence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionCheckpoint {
    /// Version for forward compatibility
    pub version: u32,
    /// When the checkpoint was created
    pub timestamp: DateTime<Utc>,
    /// The sequence definition
    pub sequence: SequenceDefinition,
    /// Status of each node
    pub node_statuses: HashMap<NodeId, NodeStatus>,
    /// Last completed node ID
    pub last_completed_node: Option<NodeId>,
    /// Current node being executed (if any)
    pub current_node: Option<NodeId>,
    /// Executor state when checkpoint was taken
    pub executor_state: ExecutorState,
    /// Connected device IDs
    pub camera_id: Option<String>,
    pub mount_id: Option<String>,
    pub focuser_id: Option<String>,
    pub filterwheel_id: Option<String>,
    pub rotator_id: Option<String>,
    /// Save path for images
    pub save_path: Option<PathBuf>,
    /// Observer location
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Total completed exposures
    pub completed_exposures: u32,
    /// Total completed integration time
    pub completed_integration_secs: f64,
    /// Whether this checkpoint is from an active session
    pub is_active: bool,
    /// Trigger state and runtime trigger settings for crash-safe resume.
    #[serde(default)]
    pub trigger_state: Option<TriggerStateSnapshot>,
}

impl SessionCheckpoint {
    /// Create a new checkpoint with the current version
    pub fn new(sequence: SequenceDefinition) -> Self {
        Self {
            version: CHECKPOINT_VERSION,
            timestamp: Utc::now(),
            sequence,
            node_statuses: HashMap::new(),
            last_completed_node: None,
            current_node: None,
            executor_state: ExecutorState::Idle,
            camera_id: None,
            mount_id: None,
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            save_path: None,
            latitude: None,
            longitude: None,
            completed_exposures: 0,
            completed_integration_secs: 0.0,
            is_active: false,
            trigger_state: None,
        }
    }

    /// Update the checkpoint with current progress
    pub fn update_progress(
        &mut self,
        node_statuses: HashMap<NodeId, NodeStatus>,
        current_node: Option<NodeId>,
        last_completed: Option<NodeId>,
        completed_exposures: u32,
        completed_integration_secs: f64,
    ) {
        self.timestamp = Utc::now();
        self.node_statuses = node_statuses;
        self.current_node = current_node;
        self.last_completed_node = last_completed;
        self.completed_exposures = completed_exposures;
        self.completed_integration_secs = completed_integration_secs;
    }

    /// Set device IDs
    pub fn set_devices(
        &mut self,
        camera: Option<String>,
        mount: Option<String>,
        focuser: Option<String>,
        filterwheel: Option<String>,
        rotator: Option<String>,
    ) {
        self.camera_id = camera;
        self.mount_id = mount;
        self.focuser_id = focuser;
        self.filterwheel_id = filterwheel;
        self.rotator_id = rotator;
    }

    /// Set observer location
    pub fn set_location(&mut self, lat: Option<f64>, lon: Option<f64>) {
        self.latitude = lat;
        self.longitude = lon;
    }

    /// Set save path
    pub fn set_save_path(&mut self, path: Option<PathBuf>) {
        self.save_path = path;
    }

    /// Mark checkpoint as active session
    pub fn set_active(&mut self, active: bool) {
        self.is_active = active;
        self.timestamp = Utc::now();
    }

    /// Store trigger state in the checkpoint.
    pub fn set_trigger_state(&mut self, trigger_state: TriggerStateSnapshot) {
        self.trigger_state = Some(trigger_state);
        self.timestamp = Utc::now();
    }

    /// Get the nodes that need to be skipped on resume (already completed)
    pub fn get_completed_nodes(&self) -> Vec<NodeId> {
        self.node_statuses
            .iter()
            .filter(|(_, status)| matches!(status, NodeStatus::Success))
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Check if this checkpoint can be resumed
    pub fn can_resume(&self) -> bool {
        // Can resume if we have a sequence and it was an active session
        self.is_active
            && matches!(
                self.executor_state,
                ExecutorState::Running | ExecutorState::Paused
            )
            && self.sequence.root_node_id.is_some()
    }

    /// Get time since checkpoint was created
    pub fn age_seconds(&self) -> i64 {
        Utc::now()
            .signed_duration_since(self.timestamp)
            .num_seconds()
    }
}

/// Manager for checkpoint persistence
pub struct CheckpointManager {
    checkpoint_dir: PathBuf,
    info_cache: Mutex<Option<CachedCheckpointInfo>>,
}

#[derive(Debug, Clone)]
struct CachedCheckpointInfo {
    primary_mtime: Option<SystemTime>,
    backup_mtime: Option<SystemTime>,
    info: Option<CheckpointInfo>,
}

impl CheckpointManager {
    const CHECKPOINT_FILENAME: &'static str = "nightshade_session.checkpoint";
    const CHECKPOINT_BACKUP: &'static str = "nightshade_session.checkpoint.bak";

    /// Get the checkpoint directory path
    pub fn checkpoint_dir(&self) -> &Path {
        &self.checkpoint_dir
    }

    /// Create a new checkpoint manager with the given directory
    pub fn new<P: AsRef<Path>>(checkpoint_dir: P) -> Self {
        Self {
            checkpoint_dir: checkpoint_dir.as_ref().to_path_buf(),
            info_cache: Mutex::new(None),
        }
    }

    /// Get the checkpoint file path
    fn checkpoint_path(&self) -> PathBuf {
        self.checkpoint_dir.join(Self::CHECKPOINT_FILENAME)
    }

    /// Get the backup checkpoint file path
    fn backup_path(&self) -> PathBuf {
        self.checkpoint_dir.join(Self::CHECKPOINT_BACKUP)
    }

    /// Save a checkpoint to disk
    pub fn save(&self, checkpoint: &SessionCheckpoint) -> Result<(), String> {
        // Ensure directory exists
        std::fs::create_dir_all(&self.checkpoint_dir)
            .map_err(|e| format!("Failed to create checkpoint directory: {}", e))?;

        let path = self.checkpoint_path();
        let backup = self.backup_path();

        // Backup existing checkpoint
        if path.exists() {
            let _ = std::fs::copy(&path, &backup);
        }

        // Write checkpoint atomically
        let json = serde_json::to_string_pretty(checkpoint)
            .map_err(|e| format!("Failed to serialize checkpoint: {}", e))?;

        let temp_path = path.with_extension("tmp");
        std::fs::write(&temp_path, &json)
            .map_err(|e| format!("Failed to write checkpoint: {}", e))?;

        std::fs::rename(&temp_path, &path)
            .map_err(|e| format!("Failed to finalize checkpoint: {}", e))?;

        self.invalidate_info_cache();
        tracing::debug!("Checkpoint saved: {}", path.display());
        Ok(())
    }

    /// Load a checkpoint from disk
    pub fn load(&self) -> Result<Option<SessionCheckpoint>, String> {
        let path = self.checkpoint_path();
        let backup = self.backup_path();
        let mut primary_error: Option<String> = None;

        if !path.exists() && !backup.exists() {
            return Ok(None);
        }

        if path.exists() {
            match Self::read_checkpoint_file(&path) {
                Ok(checkpoint) => return Ok(Some(checkpoint)),
                Err(primary_err) => {
                    tracing::warn!(
                        "Primary checkpoint load failed ({}), attempting backup",
                        primary_err
                    );
                    primary_error = Some(primary_err);
                }
            }
        }

        if backup.exists() {
            let checkpoint = Self::read_checkpoint_file(&backup)?;
            tracing::warn!(
                "Recovered checkpoint from backup file: {}",
                backup.display()
            );

            // Attempt to self-heal by restoring backup to primary path.
            if let Err(e) = std::fs::copy(&backup, &path) {
                tracing::warn!("Failed to restore primary checkpoint from backup: {}", e);
            }

            return Ok(Some(checkpoint));
        }

        if let Some(primary_err) = primary_error {
            return Err(primary_err);
        }

        Ok(None)
    }

    fn read_checkpoint_file(path: &Path) -> Result<SessionCheckpoint, String> {
        let json = std::fs::read_to_string(path)
            .map_err(|e| format!("Failed to read checkpoint {}: {}", path.display(), e))?;

        let checkpoint: SessionCheckpoint = serde_json::from_str(&json)
            .map_err(|e| format!("Failed to parse checkpoint {}: {}", path.display(), e))?;

        if checkpoint.version > CHECKPOINT_VERSION {
            return Err(format!(
                "Checkpoint {} has unsupported version {} (max supported: {})",
                path.display(),
                checkpoint.version,
                CHECKPOINT_VERSION
            ));
        }

        if checkpoint.version < CHECKPOINT_VERSION && checkpoint.trigger_state.is_none() {
            tracing::info!(
                "Checkpoint {} is version {} (pre-trigger-state); resume will use default trigger state",
                path.display(),
                checkpoint.version
            );
        }

        Ok(checkpoint)
    }

    fn checkpoint_signature(&self) -> Result<(Option<SystemTime>, Option<SystemTime>), String> {
        let path = self.checkpoint_path();
        let backup = self.backup_path();

        let primary_mtime = if path.exists() {
            Some(
                std::fs::metadata(&path)
                    .map_err(|e| format!("Failed to stat checkpoint {}: {}", path.display(), e))?
                    .modified()
                    .map_err(|e| {
                        format!("Failed to read checkpoint mtime {}: {}", path.display(), e)
                    })?,
            )
        } else {
            None
        };

        let backup_mtime = if backup.exists() {
            Some(
                std::fs::metadata(&backup)
                    .map_err(|e| {
                        format!(
                            "Failed to stat backup checkpoint {}: {}",
                            backup.display(),
                            e
                        )
                    })?
                    .modified()
                    .map_err(|e| {
                        format!(
                            "Failed to read backup checkpoint mtime {}: {}",
                            backup.display(),
                            e
                        )
                    })?,
            )
        } else {
            None
        };

        Ok((primary_mtime, backup_mtime))
    }

    fn build_checkpoint_info(&self) -> Result<Option<CheckpointInfo>, String> {
        match self.load()? {
            Some(checkpoint) => Ok(Some(CheckpointInfo {
                sequence_name: checkpoint.sequence.name.clone(),
                timestamp: checkpoint.timestamp,
                completed_exposures: checkpoint.completed_exposures,
                completed_integration_secs: checkpoint.completed_integration_secs,
                can_resume: checkpoint.can_resume(),
                age_seconds: checkpoint.age_seconds(),
            })),
            None => Ok(None),
        }
    }

    fn cached_checkpoint_info(&self) -> Result<Option<CheckpointInfo>, String> {
        let (primary_mtime, backup_mtime) = self.checkpoint_signature()?;
        let mut cache = self.info_cache.lock().unwrap_or_else(|e| e.into_inner());

        if let Some(cached) = &*cache {
            if cached.primary_mtime == primary_mtime && cached.backup_mtime == backup_mtime {
                return Ok(cached.info.clone());
            }
        }

        let info = self.build_checkpoint_info()?;
        *cache = Some(CachedCheckpointInfo {
            primary_mtime,
            backup_mtime,
            info: info.clone(),
        });
        Ok(info)
    }

    fn invalidate_info_cache(&self) {
        *self.info_cache.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }

    /// Check if a recoverable checkpoint exists
    pub fn has_recoverable_checkpoint(&self) -> bool {
        self.cached_checkpoint_info()
            .map(|info| info.is_some_and(|checkpoint| checkpoint.can_resume))
            .unwrap_or(false)
    }

    /// Delete the checkpoint (call when sequence completes normally)
    pub fn clear(&self) -> Result<(), String> {
        let path = self.checkpoint_path();
        let backup = self.backup_path();

        if path.exists() {
            std::fs::remove_file(&path)
                .map_err(|e| format!("Failed to remove checkpoint: {}", e))?;
        }

        if backup.exists() {
            let _ = std::fs::remove_file(&backup);
        }

        self.invalidate_info_cache();
        tracing::debug!("Checkpoint cleared");
        Ok(())
    }

    /// Mark checkpoint as inactive (sequence completed or was stopped gracefully)
    pub fn mark_completed(&self) -> Result<(), String> {
        if let Ok(Some(mut checkpoint)) = self.load() {
            checkpoint.is_active = false;
            checkpoint.executor_state = ExecutorState::Completed;
            self.save(&checkpoint)?;
        }
        self.invalidate_info_cache();
        Ok(())
    }

    /// Get checkpoint info without loading full checkpoint
    pub fn get_checkpoint_info(&self) -> Result<Option<CheckpointInfo>, String> {
        self.cached_checkpoint_info()
    }
}

/// Summary info about a checkpoint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckpointInfo {
    pub sequence_name: String,
    pub timestamp: DateTime<Utc>,
    pub completed_exposures: u32,
    pub completed_integration_secs: f64,
    pub can_resume: bool,
    pub age_seconds: i64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn test_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "nightshade_checkpoint_test_{}_{}",
            name,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_checkpoint_serialization() {
        let seq = SequenceDefinition::new("Test Sequence".to_string());
        let checkpoint = SessionCheckpoint::new(seq);

        let json = serde_json::to_string(&checkpoint).unwrap();
        let loaded: SessionCheckpoint = serde_json::from_str(&json).unwrap();

        assert_eq!(loaded.sequence.name, "Test Sequence");
    }

    #[test]
    fn test_load_corrupt_primary_without_backup_returns_error() {
        let dir = test_dir("corrupt_primary_no_backup");
        let manager = CheckpointManager::new(&dir);
        let primary = manager.checkpoint_path();
        fs::write(&primary, "{not valid json").unwrap();

        let result = manager.load();
        assert!(
            result.is_err(),
            "Expected error for corrupt primary checkpoint"
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_falls_back_to_backup_when_primary_corrupt() {
        let dir = test_dir("primary_corrupt_backup_ok");
        let manager = CheckpointManager::new(&dir);

        let seq = SequenceDefinition::new("Backup Sequence".to_string());
        let checkpoint = SessionCheckpoint::new(seq);
        manager.save(&checkpoint).unwrap();

        let primary = manager.checkpoint_path();
        let backup = manager.backup_path();
        fs::copy(&primary, &backup).unwrap();
        fs::write(&primary, "{not valid json").unwrap();

        let loaded = manager
            .load()
            .unwrap()
            .expect("Expected checkpoint from backup");
        assert_eq!(loaded.sequence.name, "Backup Sequence");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_checkpoint_info_cache_invalidates_when_file_disappears() {
        let dir = test_dir("info_cache_invalidation");
        let manager = CheckpointManager::new(&dir);
        let mut checkpoint = SessionCheckpoint::new(SequenceDefinition::new("Resume".to_string()));
        checkpoint.sequence.root_node_id = Some("root".to_string());
        checkpoint.is_active = true;
        checkpoint.executor_state = ExecutorState::Running;
        manager.save(&checkpoint).unwrap();

        let first = manager.get_checkpoint_info().unwrap();
        assert!(first.as_ref().is_some_and(|info| info.can_resume));

        fs::remove_file(manager.checkpoint_path()).unwrap();

        let second = manager.get_checkpoint_info().unwrap();
        assert!(second.is_none());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_trigger_state_snapshot_round_trip_preserves_every_field() {
        let mut original = TriggerState::new();
        original.baseline_hfr = Some(2.5);
        original.current_hfr = Some(2.7);
        original.autofocus_invalidated = true;
        original.autofocus_invalidation_reason = Some("filter changed".into());
        original.current_hour_angle = Some(0.75);
        original.pier_side = Some(PierSide::West);
        original.mount_tracking_limit_time = Some(1_700_000_000);
        original.has_flipped_this_target = true;
        original.current_target_name = Some("M31".into());
        original.guiding_enabled = true;
        original.guide_star_lost = false;
        original.current_humidity = Some(63.0);
        original.current_altitude = Some(58.4);
        original.weather_safe = true;
        original.baseline_temperature = Some(-3.5);
        original.current_temperature = Some(-2.0);
        original.baseline_focuser_position = Some(28000);
        original.filter_changed = true;
        original.current_filter = Some("Ha".into());
        original.dawn_time = Some(1_700_010_000);
        original.observer_latitude = Some(45.5);
        original.observer_longitude = Some(-122.6);
        original.completed_exposures = 42;
        original.last_autofocus_frame = 30;
        original.last_dither_frame = 41;
        original.tracking_limit_detected_at = Some(1_700_005_000);
        original.grid_dither_index = 7;

        let mut offsets = HashMap::new();
        offsets.insert("Ha".to_string(), 42);
        offsets.insert("OIII".to_string(), -17);

        let snapshot = TriggerStateSnapshot::from_state(
            &original,
            SafetyFailMode::WarnOnly,
            true,
            offsets.clone(),
        );

        let json = serde_json::to_string(&snapshot).expect("snapshot must serialize");
        let restored_snapshot: TriggerStateSnapshot =
            serde_json::from_str(&json).expect("snapshot must deserialize");
        assert_eq!(
            snapshot, restored_snapshot,
            "TriggerStateSnapshot serde round-trip must preserve every field"
        );
        assert_eq!(restored_snapshot.safety_fail_mode, SafetyFailMode::WarnOnly);
        assert!(restored_snapshot.triggers_enabled);
        assert_eq!(restored_snapshot.filter_focus_offsets, offsets);

        let mut restored = TriggerState::new();
        restored_snapshot.restore_into(&mut restored);
        assert_eq!(restored.baseline_hfr, original.baseline_hfr);
        assert_eq!(restored.current_hfr, original.current_hfr);
        assert_eq!(
            restored.autofocus_invalidated,
            original.autofocus_invalidated
        );
        assert_eq!(
            restored.autofocus_invalidation_reason,
            original.autofocus_invalidation_reason
        );
        assert_eq!(restored.current_hour_angle, original.current_hour_angle);
        assert_eq!(restored.pier_side, original.pier_side);
        assert_eq!(
            restored.mount_tracking_limit_time,
            original.mount_tracking_limit_time
        );
        assert_eq!(
            restored.has_flipped_this_target,
            original.has_flipped_this_target
        );
        assert_eq!(restored.current_target_name, original.current_target_name);
        assert_eq!(restored.guiding_enabled, original.guiding_enabled);
        assert_eq!(restored.guide_star_lost, original.guide_star_lost);
        assert_eq!(restored.current_humidity, original.current_humidity);
        assert_eq!(restored.current_altitude, original.current_altitude);
        assert_eq!(restored.weather_safe, original.weather_safe);
        assert_eq!(restored.baseline_temperature, original.baseline_temperature);
        assert_eq!(restored.current_temperature, original.current_temperature);
        assert_eq!(
            restored.baseline_focuser_position,
            original.baseline_focuser_position
        );
        assert_eq!(restored.filter_changed, original.filter_changed);
        assert_eq!(restored.current_filter, original.current_filter);
        assert_eq!(restored.dawn_time, original.dawn_time);
        assert_eq!(restored.observer_latitude, original.observer_latitude);
        assert_eq!(restored.observer_longitude, original.observer_longitude);
        assert_eq!(restored.completed_exposures, original.completed_exposures);
        assert_eq!(restored.last_autofocus_frame, original.last_autofocus_frame);
        assert_eq!(restored.last_dither_frame, original.last_dither_frame);
        assert_eq!(
            restored.tracking_limit_detected_at,
            original.tracking_limit_detected_at
        );
        assert_eq!(restored.grid_dither_index, original.grid_dither_index);
    }

    #[test]
    fn test_checkpoint_persists_has_flipped_this_target_across_save_load() {
        let dir = test_dir("trigger_state_persist");
        let manager = CheckpointManager::new(&dir);

        let mut state = TriggerState::new();
        state.has_flipped_this_target = true;
        state.current_target_name = Some("NGC7000".into());
        state.completed_exposures = 17;
        state.last_autofocus_frame = 10;
        state.last_dither_frame = 16;
        state.grid_dither_index = 4;
        state.baseline_hfr = Some(2.1);

        let snapshot = TriggerStateSnapshot::from_state(
            &state,
            SafetyFailMode::FailClosed,
            true,
            HashMap::new(),
        );

        let mut checkpoint =
            SessionCheckpoint::new(SequenceDefinition::new("Persist test".to_string()));
        checkpoint.is_active = true;
        checkpoint.executor_state = ExecutorState::Running;
        checkpoint.set_trigger_state(snapshot);

        manager.save(&checkpoint).expect("save");

        let loaded = manager
            .load()
            .expect("load")
            .expect("checkpoint must exist");
        let restored_snapshot = loaded
            .trigger_state
            .as_ref()
            .expect("trigger_state must round-trip via JSON");
        assert!(restored_snapshot.has_flipped_this_target);
        assert_eq!(
            restored_snapshot.current_target_name.as_deref(),
            Some("NGC7000")
        );
        assert_eq!(restored_snapshot.completed_exposures, 17);
        assert_eq!(restored_snapshot.last_autofocus_frame, 10);
        assert_eq!(restored_snapshot.last_dither_frame, 16);
        assert_eq!(restored_snapshot.grid_dither_index, 4);
        assert_eq!(restored_snapshot.baseline_hfr, Some(2.1));
        assert_eq!(loaded.version, CHECKPOINT_VERSION);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_legacy_v1_checkpoint_loads_with_no_trigger_state() {
        let dir = test_dir("legacy_v1_no_trigger_state");
        let manager = CheckpointManager::new(&dir);

        let v1_json = serde_json::json!({
            "version": 1,
            "timestamp": Utc::now(),
            "sequence": SequenceDefinition::new("v1".to_string()),
            "node_statuses": {},
            "last_completed_node": null,
            "current_node": null,
            "executor_state": "Running",
            "camera_id": null,
            "mount_id": null,
            "focuser_id": null,
            "filterwheel_id": null,
            "rotator_id": null,
            "save_path": null,
            "latitude": null,
            "longitude": null,
            "completed_exposures": 5,
            "completed_integration_secs": 600.0,
            "is_active": true
        });
        let primary = manager.checkpoint_path();
        fs::create_dir_all(&dir).unwrap();
        fs::write(&primary, v1_json.to_string()).unwrap();

        let loaded = manager
            .load()
            .expect("v1 checkpoint must load")
            .expect("checkpoint should be present");
        assert_eq!(loaded.version, 1);
        assert!(loaded.trigger_state.is_none());

        let _ = fs::remove_dir_all(&dir);
    }
}
