//! Session checkpoint for crash recovery
//!
//! This module provides functionality to save and restore sequence execution state
//! for recovery after unexpected crashes or restarts.

use crate::{SequenceDefinition, NodeId, NodeStatus, ExecutorState};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use chrono::{DateTime, Utc};

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
}

impl SessionCheckpoint {
    /// Create a new checkpoint with the current version
    pub fn new(sequence: SequenceDefinition) -> Self {
        Self {
            version: 1,
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
        self.is_active &&
        self.executor_state == ExecutorState::Running &&
        self.last_completed_node.is_some()
    }

    /// Get time since checkpoint was created
    pub fn age_seconds(&self) -> i64 {
        Utc::now().signed_duration_since(self.timestamp).num_seconds()
    }
}

/// Manager for checkpoint persistence
pub struct CheckpointManager {
    checkpoint_dir: PathBuf,
}

impl CheckpointManager {
    const CHECKPOINT_FILENAME: &'static str = "nightshade_session.checkpoint";
    const CHECKPOINT_BACKUP: &'static str = "nightshade_session.checkpoint.bak";

    /// Create a new checkpoint manager with the given directory
    pub fn new<P: AsRef<Path>>(checkpoint_dir: P) -> Self {
        Self {
            checkpoint_dir: checkpoint_dir.as_ref().to_path_buf(),
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

        tracing::debug!("Checkpoint saved: {}", path.display());
        Ok(())
    }

    /// Load a checkpoint from disk
    pub fn load(&self) -> Result<Option<SessionCheckpoint>, String> {
        let path = self.checkpoint_path();

        if !path.exists() {
            return Ok(None);
        }

        let json = std::fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read checkpoint: {}", e))?;

        let checkpoint: SessionCheckpoint = serde_json::from_str(&json)
            .map_err(|e| format!("Failed to parse checkpoint: {}", e))?;

        // Validate version
        if checkpoint.version > 1 {
            return Err(format!("Checkpoint version {} not supported", checkpoint.version));
        }

        Ok(Some(checkpoint))
    }

    /// Check if a recoverable checkpoint exists
    pub fn has_recoverable_checkpoint(&self) -> bool {
        match self.load() {
            Ok(Some(checkpoint)) => checkpoint.can_resume(),
            _ => false,
        }
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
        Ok(())
    }

    /// Get checkpoint info without loading full checkpoint
    pub fn get_checkpoint_info(&self) -> Result<Option<CheckpointInfo>, String> {
        match self.load() {
            Ok(Some(checkpoint)) => Ok(Some(CheckpointInfo {
                sequence_name: checkpoint.sequence.name.clone(),
                timestamp: checkpoint.timestamp,
                completed_exposures: checkpoint.completed_exposures,
                completed_integration_secs: checkpoint.completed_integration_secs,
                can_resume: checkpoint.can_resume(),
                age_seconds: checkpoint.age_seconds(),
            })),
            Ok(None) => Ok(None),
            Err(e) => Err(e),
        }
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

    #[test]
    fn test_checkpoint_serialization() {
        let seq = SequenceDefinition::new("Test Sequence".to_string());
        let checkpoint = SessionCheckpoint::new(seq);

        let json = serde_json::to_string(&checkpoint).unwrap();
        let loaded: SessionCheckpoint = serde_json::from_str(&json).unwrap();

        assert_eq!(loaded.sequence.name, "Test Sequence");
    }
}
