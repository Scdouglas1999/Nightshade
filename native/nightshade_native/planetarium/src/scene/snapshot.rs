//! Per-frame scene snapshot published for Dart overlay layers.
//!
//! The render thread writes via [`SnapshotSlot::publish`]; Flutter reads via
//! [`SnapshotSlot::load`] without locking the render thread.

use std::sync::Arc;

use arc_swap::ArcSwap;

use crate::types::ViewPose;

/// Stable identifier for a catalog object (HIP, NGC id hash, body id, etc.).
pub type ObjectId = u64;

/// Compact label text carried across the FFI boundary.
///
/// Uses inline storage for short names (typical star/DSO labels); longer names
/// spill to the heap without truncation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SmallString(String);

impl SmallString {
    /// Create a label string from any UTF-8 source.
    pub fn new(text: impl Into<String>) -> Self {
        Self(text.into())
    }

    /// Borrow the UTF-8 contents.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for SmallString {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for SmallString {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

/// Label category for overlap resolution and styling in Dart.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LabelCategory {
    /// Star catalog object.
    Star = 0,
    /// Deep-sky object.
    Dso = 1,
    /// Constellation name or identifier.
    Constellation = 2,
    /// Solar-system body.
    Body = 3,
    /// Earth-orbiting satellite.
    Satellite = 4,
    /// Minor planet (asteroid/comet).
    MinorPlanet = 5,
}

/// Screen-space hint for a single visible object label.
#[derive(Debug, Clone, PartialEq)]
pub struct LabelHint {
    /// Catalog object identifier.
    pub object_id: ObjectId,
    /// Normalized screen X in widget coordinates (0 = left).
    pub screen_x: f32,
    /// Normalized screen Y in widget coordinates (0 = top).
    pub screen_y: f32,
    /// Apparent magnitude for label sizing.
    pub apparent_mag: f32,
    /// Higher values win overlap resolution in Dart.
    pub priority: u8,
    /// Display text for the label widget.
    pub text: SmallString,
    /// Object kind for styling.
    pub category: LabelCategory,
}

/// Currently selected object projected to screen space.
#[derive(Debug, Clone, PartialEq)]
pub struct SelectedObject {
    /// Catalog object identifier.
    pub object_id: ObjectId,
    /// Projected screen X for selection ring / HUD.
    pub screen_x: f32,
    /// Projected screen Y for selection ring / HUD.
    pub screen_y: f32,
    /// ICRS right ascension (radians).
    pub ra_rad: f64,
    /// ICRS declination (radians).
    pub dec_rad: f64,
    /// Object kind.
    pub category: LabelCategory,
    /// Human-readable name for the info panel.
    pub display_name: SmallString,
}

/// Immutable snapshot of visible scene state for one rendered frame.
#[derive(Debug, Clone, PartialEq)]
pub struct SceneSnapshot {
    /// Monotonic frame counter incremented each publish.
    pub frame_id: u64,
    /// Camera pose used when this frame was rendered.
    pub view_pose: ViewPose,
    /// Visible object labels for the Dart overlay layer.
    pub labels: Vec<LabelHint>,
    /// Active selection, if any.
    pub selected: Option<SelectedObject>,
}

impl SceneSnapshot {
    /// Empty snapshot used before the first frame is published.
    pub fn empty() -> Self {
        Self {
            frame_id: 0,
            view_pose: ViewPose::default(),
            labels: Vec::new(),
            selected: None,
        }
    }
}

/// Lock-free publish slot: `Arc<ArcSwap<SceneSnapshot>>`.
pub type SnapshotSlot = Arc<ArcSwap<SceneSnapshot>>;

/// Creates a new snapshot slot pre-filled with [`SceneSnapshot::empty`].
pub fn new_snapshot_slot() -> SnapshotSlot {
    Arc::new(ArcSwap::from_pointee(SceneSnapshot::empty()))
}

/// Publish a new snapshot, replacing the previous one atomically.
pub fn publish(slot: &SnapshotSlot, snapshot: SceneSnapshot) {
    slot.store(Arc::new(snapshot));
}

/// Load the latest published snapshot (cheap atomic read).
pub fn load(slot: &SnapshotSlot) -> Arc<SceneSnapshot> {
    slot.load_full()
}
