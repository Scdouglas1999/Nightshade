//! Nightshade Sequencer Engine
//!
//! Implements a behavior tree-based sequencer for automated imaging.

pub mod all_sky_polar;
pub mod autofocus;
pub mod checkpoint;
mod device_ops;
mod executor;
pub mod flat_wizard;
pub mod focus_prediction;
pub mod instructions;
pub mod meridian;
pub mod meridian_events;
pub mod meridian_flip_executor;
pub mod mosaic;
mod node;
mod polar_align;
pub mod temperature_compensation;
mod triggers;

pub use checkpoint::*;
pub use device_ops::*;
pub use executor::*;
pub use instructions::*;
pub use meridian_events::*;
pub use meridian_flip_executor::*;
pub use mosaic::*;
pub use node::*;
pub use all_sky_polar::*;
pub use polar_align::*;
pub use triggers::*;

// Re-export focus prediction types
pub use focus_prediction::{FilterOffset, FocusModel, FocusPredictionEngine, PredictionResult};

// Re-export autofocus types (with alias to avoid conflict)
pub use autofocus::{
    AutofocusMethod as AfMethod, AutofocusResult, BacklashCompensation,
    FocusDataPoint as AfDataPoint, VCurveAutofocus,
};

// Re-export temperature compensation types
pub use temperature_compensation::{CompensationMode, TemperatureCompensationConfig};

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Unique identifier for a sequence node
pub type NodeId = String;

/// Defines how the safety system behaves when weather/safety devices fail or are unavailable.
/// This mirrors the Dart-side SafetyFailMode enum in app_settings.dart.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum SafetyFailMode {
    /// Treat unavailable safety data as unsafe (required production behavior).
    #[default]
    FailClosed,
    /// Legacy mode retained for backward compatibility.
    /// Runtime logic coerces this to fail-closed behavior.
    FailOpen,
    /// Legacy mode retained for backward compatibility.
    /// Runtime logic coerces this to fail-closed behavior.
    WarnOnly,
}

/// Status of a node execution
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NodeStatus {
    /// Node has not started
    Pending,
    /// Node is currently running
    Running,
    /// Node completed successfully
    Success,
    /// Node failed
    Failure,
    /// Node was skipped
    Skipped,
    /// Node was cancelled
    Cancelled,
}

impl NodeStatus {
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            NodeStatus::Success | NodeStatus::Failure | NodeStatus::Skipped | NodeStatus::Cancelled
        )
    }
}

/// A sequence definition that can be saved/loaded
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceDefinition {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    pub root_node_id: Option<NodeId>,
    pub nodes: Vec<NodeDefinition>,
    #[serde(default)]
    pub metadata: HashMap<String, String>,
}

impl SequenceDefinition {
    pub fn new(name: String) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            description: None,
            root_node_id: None,
            nodes: Vec::new(),
            metadata: HashMap::new(),
        }
    }
}

/// Definition of a node that can be serialized
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeDefinition {
    pub id: NodeId,
    #[serde(default)]
    pub name: String,
    pub node_type: NodeType,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default)]
    pub children: Vec<NodeId>,
}

fn default_enabled() -> bool {
    true
}

/// Types of nodes in the sequencer
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum NodeType {
    // Container/Logic nodes
    TargetHeader(TargetHeaderConfig),
    /// Legacy alias - deserializes to TargetHeader
    #[serde(alias = "TargetGroup")]
    TargetGroup(TargetHeaderConfig),
    Loop(LoopConfig),
    Parallel(ParallelConfig),
    Conditional(ConditionalConfig),
    Recovery(RecoveryConfig),

    // Instruction nodes
    SlewToTarget(SlewConfig),
    CenterTarget(CenterConfig),
    TakeExposure(ExposureConfig),
    Autofocus(AutofocusConfig),
    TemperatureCompensation(TemperatureCompensationConfig),
    Dither(DitherConfig),
    StartGuiding(StartGuidingConfig),
    StopGuiding,
    ChangeFilter(FilterConfig),
    CoolCamera(CoolConfig),
    WarmCamera(WarmConfig),
    MoveRotator(RotatorConfig),
    Park,
    Unpark,
    WaitForTime(WaitTimeConfig),
    Delay(DelayConfig),
    Notification(NotificationConfig),
    RunScript(ScriptConfig),
    PolarAlignment(PolarAlignConfig),
    MeridianFlip(MeridianFlipConfig),
    OpenDome(DomeConfig),
    CloseDome(DomeConfig),
    ParkDome(DomeConfig),
    Mosaic(MosaicConfig),
    FlatWizard(FlatWizardConfig),
    // Cover Calibrator / Flat Panel instructions
    OpenCover(CoverCalibratorConfig),
    CloseCover(CoverCalibratorConfig),
    CalibratorOn(CalibratorOnConfig),
    CalibratorOff(CoverCalibratorConfig),
}

// Configuration structs for each node type

/// Information about a mosaic panel for multi-panel imaging
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MosaicPanelInfo {
    pub mosaic_name: String,
    pub panel_index: i32,
    pub total_panels: i32,
    pub row: i32,
    pub column: i32,
}

impl MosaicPanelInfo {
    pub fn display_label(&self) -> String {
        format!("Panel {}/{}", self.panel_index + 1, self.total_panels)
    }
}

/// Target header configuration - the root node for each target in the sequence.
/// Contains coordinates, scheduling constraints, and optional mosaic panel info.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TargetHeaderConfig {
    pub target_name: String,
    pub ra_hours: f64,
    pub dec_degrees: f64,
    pub rotation: Option<f64>,
    pub priority: i32,
    pub min_altitude: Option<f64>,
    pub max_altitude: Option<f64>,
    /// Time constraint: don't start imaging before this Unix timestamp
    #[serde(default)]
    pub start_after: Option<i64>,
    /// Time constraint: stop imaging by this Unix timestamp
    #[serde(default)]
    pub end_before: Option<i64>,
    /// Mosaic panel info if this target is part of a mosaic
    #[serde(default)]
    pub mosaic_panel: Option<MosaicPanelInfo>,
}

impl TargetHeaderConfig {
    /// Check if this target has time constraints
    pub fn has_time_constraints(&self) -> bool {
        self.start_after.is_some() || self.end_before.is_some()
    }

    /// Check if this target has altitude constraints
    pub fn has_altitude_constraints(&self) -> bool {
        self.min_altitude.is_some() || self.max_altitude.is_some()
    }

    /// Get display name including mosaic panel info if applicable
    pub fn display_name(&self) -> String {
        if let Some(ref panel) = self.mosaic_panel {
            format!("{} ({})", self.target_name, panel.display_label())
        } else {
            self.target_name.clone()
        }
    }
}

/// Legacy type alias for backward compatibility
pub type TargetGroupConfig = TargetHeaderConfig;

// ============================================================================
// PRIORITY 2: Advanced Features Configuration
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MosaicConfig {
    pub center_ra: f64,
    pub center_dec: f64,
    pub panel_width_arcmin: f64,
    pub panel_height_arcmin: f64,
    pub overlap_percent: f64,
    pub rotation: f64,
    pub panels_horizontal: u32,
    pub panels_vertical: u32,
    #[serde(default = "default_mosaic_panel_overhead_secs")]
    pub panel_overhead_secs: f64,
}

impl Default for MosaicConfig {
    fn default() -> Self {
        Self {
            center_ra: 0.0,
            center_dec: 0.0,
            panel_width_arcmin: 60.0,
            panel_height_arcmin: 40.0,
            overlap_percent: 10.0,
            rotation: 0.0,
            panels_horizontal: 3,
            panels_vertical: 3,
            panel_overhead_secs: default_mosaic_panel_overhead_secs(),
        }
    }
}

fn default_mosaic_panel_overhead_secs() -> f64 {
    60.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlatWizardConfig {
    /// Target ADU value for flats
    pub target_adu: u16,
    /// Minimum exposure time to try (seconds)
    pub min_exposure: f64,
    /// Maximum exposure time to try (seconds)
    pub max_exposure: f64,
    /// ADU tolerance percentage (default: 5%)
    pub tolerance_percent: f64,
    /// Where flats are taken from (panel, dawn sky, dusk sky)
    pub panel_location: PanelLocation,
    /// Filter to use (optional)
    pub filter: Option<String>,
    /// Filter position (0-based index). When specified, used instead of filter name.
    #[serde(default)]
    pub filter_index: Option<i32>,
    /// Initial brightness for flat panel (0-255, ignored for sky flats)
    #[serde(default = "default_brightness")]
    pub brightness: i32,
    /// Whether to auto-adjust brightness if target ADU can't be reached
    #[serde(default)]
    pub auto_adjust_brightness: bool,
    /// Minimum brightness to try when auto-adjusting
    #[serde(default = "default_min_brightness")]
    pub min_brightness: i32,
    /// Maximum brightness to try when auto-adjusting
    #[serde(default = "default_max_brightness")]
    pub max_brightness: i32,
    /// Number of flat frames to take after finding optimal exposure
    #[serde(default = "default_flat_count")]
    pub flat_count: u32,
}

fn default_brightness() -> i32 {
    128
}
fn default_min_brightness() -> i32 {
    10
}
fn default_max_brightness() -> i32 {
    255
}
fn default_flat_count() -> u32 {
    30
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PanelLocation {
    DawnSky,
    DuskSky,
    FlatPanel,
}

impl Default for FlatWizardConfig {
    fn default() -> Self {
        Self {
            target_adu: 32000,
            min_exposure: 0.001,
            max_exposure: 10.0,
            tolerance_percent: 5.0,
            panel_location: PanelLocation::DuskSky,
            filter: None,
            filter_index: None,
            brightness: 128,
            auto_adjust_brightness: false,
            min_brightness: 10,
            max_brightness: 255,
            flat_count: default_flat_count(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExposureTrigger {
    pub condition: TriggerCondition,
    pub action: TriggerAction,
    pub debounce_secs: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TriggerCondition {
    GuidingRmsAbove(f64),
    HfrAbove(f64),
    DriftAbove { ra_px: f64, dec_px: f64 },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TriggerAction {
    PauseAndRecalibrate,
    Autofocus,
    Abort,
}

// ============================================================================
// Existing Configurations
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoopConfig {
    pub iterations: Option<u32>,
    pub condition: LoopCondition,
    pub condition_value: Option<f64>,
}

impl Default for LoopConfig {
    fn default() -> Self {
        Self {
            iterations: Some(1),
            condition: LoopCondition::Count,
            condition_value: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ParallelConfig {
    pub required_successes: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConditionalConfig {
    pub condition: ConditionalCheck,
}

impl Default for ConditionalConfig {
    fn default() -> Self {
        Self {
            condition: ConditionalCheck::Always,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryConfig {
    pub trigger: Option<TriggerType>,
    pub recovery_action: RecoveryAction,
    pub max_retries: u32,
}

impl Default for RecoveryConfig {
    fn default() -> Self {
        Self {
            trigger: None,
            recovery_action: RecoveryAction::default(),
            max_retries: 3,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlewConfig {
    pub use_target_coords: bool,
    pub custom_ra: Option<f64>,
    pub custom_dec: Option<f64>,
}

impl Default for SlewConfig {
    fn default() -> Self {
        Self {
            use_target_coords: true,
            custom_ra: None,
            custom_dec: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CenterConfig {
    pub use_target_coords: bool,
    pub custom_ra: Option<f64>,
    pub custom_dec: Option<f64>,
    pub accuracy_arcsec: f64,
    pub max_attempts: u32,
    pub exposure_duration: f64,
    pub filter: Option<String>,
}

impl Default for CenterConfig {
    fn default() -> Self {
        Self {
            use_target_coords: true,
            custom_ra: None,
            custom_dec: None,
            accuracy_arcsec: 5.0,
            max_attempts: 5,
            exposure_duration: 5.0,
            filter: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExposureConfig {
    pub duration_secs: f64,
    pub count: u32,
    pub filter: Option<String>,
    /// Filter position (0-based index). When specified, this is used instead of filter name
    /// for more reliable filter changes that don't depend on name matching.
    #[serde(default)]
    pub filter_index: Option<i32>,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub binning: Binning,
    pub dither_every: Option<u32>,
    #[serde(default = "default_dither_pixels")]
    pub dither_pixels: f64,
    #[serde(default = "default_dither_settle_pixels")]
    pub dither_settle_pixels: f64,
    #[serde(default = "default_dither_settle_time")]
    pub dither_settle_time: f64,
    #[serde(default = "default_dither_settle_timeout")]
    pub dither_settle_timeout: f64,
    #[serde(default)]
    pub dither_ra_only: bool,
    pub save_to: Option<String>,
    #[serde(default)]
    pub triggers: Vec<ExposureTrigger>,
}

impl Default for ExposureConfig {
    fn default() -> Self {
        Self {
            duration_secs: 60.0,
            count: 10,
            filter: None,
            filter_index: None,
            gain: None,
            offset: None,
            binning: Binning::One,
            dither_every: Some(1),
            dither_pixels: default_dither_pixels(),
            dither_settle_pixels: default_dither_settle_pixels(),
            dither_settle_time: default_dither_settle_time(),
            dither_settle_timeout: default_dither_settle_timeout(),
            dither_ra_only: false,
            save_to: None,
            triggers: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum Binning {
    #[default]
    One,
    Two,
    Three,
    Four,
}

impl Binning {
    pub fn as_str(&self) -> &'static str {
        match self {
            Binning::One => "1x1",
            Binning::Two => "2x2",
            Binning::Three => "3x3",
            Binning::Four => "4x4",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutofocusConfig {
    #[serde(default)]
    pub method: AutofocusMethod,
    #[serde(default = "default_af_step_size")]
    pub step_size: i32,
    #[serde(default = "default_af_steps_out")]
    pub steps_out: u32,
    #[serde(default = "default_af_exposure_duration")]
    pub exposure_duration: f64,
    #[serde(default)]
    pub filter: Option<String>,
    #[serde(default)]
    pub binning: Binning,
    /// Backlash compensation in focuser steps.
    #[serde(default = "default_af_backlash_compensation")]
    pub backlash_compensation: i32,
    /// Whether the autofocus engine may use temperature prediction.
    #[serde(default = "default_af_use_temperature_prediction")]
    pub use_temperature_prediction: bool,
    /// Reject autofocus points when star count changes beyond this fraction.
    #[serde(default = "default_af_max_star_count_change")]
    pub max_star_count_change: Option<f64>,
    /// Sigma threshold for autofocus outlier rejection. Use 0 to disable.
    #[serde(default = "default_af_outlier_rejection_sigma")]
    pub outlier_rejection_sigma: f64,
    /// Maximum duration in seconds before the autofocus run is aborted.
    /// Default 600s (10 minutes).
    #[serde(default = "default_af_max_duration")]
    pub max_duration_secs: f64,
    /// Minimum number of stars per V-curve frame for the result to count as
    /// a valid sample (audit §1.21). Frames with fewer stars are rejected;
    /// if more than half the frames are rejected the autofocus run fails.
    /// Default 10 — matches the previous hardcoded `MIN_STAR_COUNT` constant.
    #[serde(default = "default_af_min_star_count")]
    pub min_star_count: u32,
}

fn default_af_max_duration() -> f64 {
    600.0
}

fn default_af_step_size() -> i32 {
    100
}

fn default_af_steps_out() -> u32 {
    7
}

fn default_af_exposure_duration() -> f64 {
    3.0
}

fn default_af_backlash_compensation() -> i32 {
    50
}

fn default_af_use_temperature_prediction() -> bool {
    true
}

fn default_af_max_star_count_change() -> Option<f64> {
    Some(0.5)
}

fn default_af_outlier_rejection_sigma() -> f64 {
    3.0
}

fn default_af_min_star_count() -> u32 {
    10
}

impl Default for AutofocusConfig {
    fn default() -> Self {
        Self {
            method: AutofocusMethod::VCurve,
            step_size: default_af_step_size(),
            steps_out: default_af_steps_out(),
            exposure_duration: default_af_exposure_duration(),
            filter: None,
            binning: Binning::One,
            backlash_compensation: default_af_backlash_compensation(),
            use_temperature_prediction: default_af_use_temperature_prediction(),
            max_star_count_change: default_af_max_star_count_change(),
            outlier_rejection_sigma: default_af_outlier_rejection_sigma(),
            max_duration_secs: default_af_max_duration(),
            min_star_count: default_af_min_star_count(),
        }
    }
}

impl From<&AutofocusConfig> for crate::autofocus::AutofocusConfig {
    fn from(config: &AutofocusConfig) -> Self {
        Self {
            method: match config.method {
                AutofocusMethod::VCurve => crate::autofocus::AutofocusMethod::VCurve,
                AutofocusMethod::Quadratic => crate::autofocus::AutofocusMethod::Quadratic,
                AutofocusMethod::Hyperbolic => crate::autofocus::AutofocusMethod::Hyperbolic,
            },
            step_size: config.step_size,
            steps_out: config.steps_out,
            exposure_duration: config.exposure_duration,
            backlash_compensation: config.backlash_compensation,
            use_temperature_prediction: config.use_temperature_prediction,
            max_star_count_change: config.max_star_count_change,
            outlier_rejection_sigma: config.outlier_rejection_sigma,
            max_duration_secs: config.max_duration_secs,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum AutofocusMethod {
    #[default]
    VCurve,
    Quadratic,
    Hyperbolic,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum DitherPattern {
    /// Random offsets (classic dither)
    #[default]
    Random,
    /// Walk through an NxN grid, cycling back to start after all positions visited
    Grid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DitherConfig {
    pub pixels: f64,
    pub settle_pixels: f64,
    pub settle_time: f64,
    pub settle_timeout: f64,
    pub ra_only: bool,
    /// Dither pattern: Random (classic) or Grid (systematic NxN walk)
    #[serde(default)]
    pub pattern: DitherPattern,
    /// Grid size N for Grid pattern (NxN grid). Ignored for Random pattern.
    /// Default is 3 (3x3 = 9 positions).
    #[serde(default = "default_grid_size")]
    pub grid_size: u32,
}

fn default_grid_size() -> u32 {
    3
}

impl Default for DitherConfig {
    fn default() -> Self {
        Self {
            pixels: default_dither_pixels(),
            settle_pixels: default_dither_settle_pixels(),
            settle_time: default_dither_settle_time(),
            settle_timeout: default_dither_settle_timeout(),
            ra_only: false,
            pattern: DitherPattern::default(),
            grid_size: default_grid_size(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartGuidingConfig {
    /// Settle threshold in pixels
    pub settle_pixels: f64,
    /// Time to remain settled (seconds)
    pub settle_time: f64,
    /// Maximum time to wait for settling (seconds)
    pub settle_timeout: f64,
    /// Whether to auto-select a guide star if none selected
    pub auto_select_star: bool,
}

impl Default for StartGuidingConfig {
    fn default() -> Self {
        Self {
            settle_pixels: 1.5,
            settle_time: 10.0,
            settle_timeout: 60.0,
            auto_select_star: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FilterConfig {
    pub filter_name: String,
    pub filter_index: Option<i32>,
    /// Timeout in seconds for filter wheel change operation.
    /// If None, uses default of 120 seconds.
    /// Some filter wheels (especially those with many positions or motorized covers)
    /// may require longer timeouts.
    #[serde(default)]
    pub timeout_secs: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoolConfig {
    pub target_temp: f64,
    pub duration_mins: Option<f64>,
}

impl Default for CoolConfig {
    fn default() -> Self {
        Self {
            target_temp: -10.0,
            duration_mins: Some(10.0),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WarmConfig {
    pub rate_per_min: f64,
    #[serde(default)]
    pub target_temp: Option<f64>,
}

impl Default for WarmConfig {
    fn default() -> Self {
        Self {
            rate_per_min: 2.0,
            target_temp: None,
        }
    }
}

const fn default_dither_pixels() -> f64 {
    5.0
}

const fn default_dither_settle_pixels() -> f64 {
    1.5
}

const fn default_dither_settle_time() -> f64 {
    30.0
}

const fn default_dither_settle_timeout() -> f64 {
    120.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RotatorConfig {
    pub target_angle: f64,
    pub relative: bool,
}

impl Default for RotatorConfig {
    fn default() -> Self {
        Self {
            target_angle: 0.0,
            relative: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WaitTimeConfig {
    pub wait_until: Option<i64>, // Unix timestamp
    pub wait_for_twilight: Option<TwilightType>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum TwilightType {
    Civil,
    Nautical,
    Astronomical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DelayConfig {
    pub seconds: f64,
}

impl Default for DelayConfig {
    fn default() -> Self {
        Self { seconds: 5.0 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NotificationConfig {
    pub title: String,
    pub message: String,
    pub level: NotificationLevel,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum NotificationLevel {
    #[default]
    Info,
    Warning,
    Error,
    Success,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScriptConfig {
    pub script_path: String,
    pub arguments: Vec<String>,
    pub timeout_secs: Option<u32>,
}

/// Method to determine when meridian flip should trigger
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
pub enum MeridianTriggerMethod {
    #[default]
    MinutesPastMeridian,
    MinutesBeforeLimit,
    HourAngleThreshold,
    /// Flip when mount stops tracking due to hitting its custom tracking limits.
    /// Uses a heuristic (connected, not slewing/parked, pre-flip pier side, HA > 0)
    /// to distinguish limit hits from actual errors.
    OnTrackingLimitHit,
}

/// Action when flip fails after all retries
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
pub enum FlipFailureAction {
    #[default]
    PauseAndAlert,
    AbortAndPark,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeridianFlipConfig {
    // Trigger conditions
    pub trigger_method: MeridianTriggerMethod,
    pub minutes_past_meridian: f64,
    pub minutes_before_limit: f64,
    pub hour_angle_threshold: f64,
    /// Minutes to wait after tracking limit is detected before flipping (0 = immediate).
    /// Only used with OnTrackingLimitHit trigger method.
    #[serde(default)]
    pub tracking_limit_wait_minutes: f64,

    // Flip sequence options
    pub pause_guiding: bool,
    pub auto_center: bool,
    pub refocus_after: bool,
    pub settle_time: f64,
    pub resume_guiding: bool,

    // Error handling
    pub max_retries: u32,
    pub retry_delays_secs: Vec<f64>,
    pub failure_action: FlipFailureAction,
}

impl Default for MeridianFlipConfig {
    fn default() -> Self {
        Self {
            trigger_method: MeridianTriggerMethod::MinutesPastMeridian,
            minutes_past_meridian: 5.0,
            minutes_before_limit: 10.0,
            hour_angle_threshold: 0.5,
            tracking_limit_wait_minutes: 0.0,
            pause_guiding: true,
            auto_center: true,
            refocus_after: false,
            settle_time: 10.0,
            resume_guiding: true,
            max_retries: 3,
            retry_delays_secs: vec![30.0, 60.0, 120.0],
            failure_action: FlipFailureAction::PauseAndAlert,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DomeConfig {
    pub shutter_only: bool, // If true, only open/close shutter, don't park/unpark dome
}

/// Cover calibrator configuration (for dust cover / flat panel devices)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CoverCalibratorConfig {
    /// Timeout in seconds for cover movement (default: 60)
    #[serde(default = "default_cover_timeout")]
    pub timeout_secs: u32,
}

fn default_cover_timeout() -> u32 {
    60
}

/// Calibrator on configuration (for flat panel brightness control)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalibratorOnConfig {
    /// Brightness level (0-max, typically 0-255)
    pub brightness: i32,
    /// Timeout in seconds for calibrator to reach ready state (default: 30)
    #[serde(default = "default_calibrator_timeout")]
    pub timeout_secs: u32,
}

fn default_calibrator_timeout() -> u32 {
    30
}

impl Default for CalibratorOnConfig {
    fn default() -> Self {
        Self {
            brightness: 128,
            timeout_secs: 30,
        }
    }
}

/// Loop conditions
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum LoopCondition {
    /// Loop N times (use iterations field)
    Count,
    /// Loop until time (condition_value = Unix timestamp)
    UntilTime,
    /// Loop until altitude below threshold (condition_value = altitude degrees)
    AltitudeBelow,
    /// Loop until altitude above threshold (condition_value = altitude degrees)
    AltitudeAbove,
    /// Loop until integration time reached (condition_value = seconds)
    IntegrationTime,
    /// Loop forever (until stopped)
    Forever,
    /// Loop while sky is dark
    WhileDark,
}

/// Conditions for conditional nodes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConditionalCheck {
    /// Always execute
    Always,
    /// Check if altitude is above threshold
    AltitudeAbove(f64),
    /// Check if time is after
    TimeAfter(i64),
    /// Check if guiding RMS is below threshold
    GuidingRmsBelow(f64),
    /// Check if HFR is below threshold
    HfrBelow(f64),
    /// Check if weather is safe
    WeatherSafe,
    /// Check if moon separation is above degrees
    MoonSeparationAbove(f64),
    /// Check if safety monitor is safe
    SafetyMonitorSafe,
}

/// Trigger types that run in parallel
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TriggerType {
    /// Trigger when HFR degrades beyond acceptable limits.
    ///
    /// Two modes of operation:
    /// - **Relative mode** (`threshold_percent`): Triggers when HFR increases by
    ///   more than this percentage above the baseline HFR (set after autofocus).
    /// - **Absolute mode** (`absolute_threshold`): Triggers when HFR exceeds a
    ///   fixed value in arcseconds/pixels, regardless of baseline.
    ///
    /// `consecutive_frames` prevents false positives from momentary seeing spikes
    /// by requiring multiple consecutive frames above the threshold before firing.
    HfrDegraded {
        /// Percentage above baseline HFR that triggers (e.g., 20.0 = 20% above baseline).
        /// Used in relative mode. Set to 0.0 or leave at default to disable relative check.
        threshold_percent: f64,
        /// Absolute HFR threshold in arcseconds/pixels. When current HFR exceeds this
        /// value, the trigger fires regardless of baseline. Set to 0.0 to disable.
        #[serde(default)]
        absolute_threshold: f64,
        /// Number of consecutive frames that must exceed the threshold before triggering.
        /// Prevents false positives from momentary seeing spikes. Default is 1 (trigger immediately).
        #[serde(default = "default_consecutive_frames")]
        consecutive_frames: u32,
    },
    /// Trigger when meridian flip is needed
    MeridianFlip { config: MeridianFlipConfig },
    /// Trigger when guiding fails
    GuidingFailed {
        rms_threshold: f64,
        duration_secs: f64,
        /// Audit §1.21: how many seconds of guiding-RMS history to retain.
        /// `update_guiding_rms` trims the rolling window to this duration so
        /// older (stale) samples cannot mask a recent spike. Default 300s
        /// (5 minutes) — preserves the previous hardcoded behaviour.
        #[serde(default = "default_guiding_rms_retention_secs")]
        rms_retention_secs: u64,
    },
    /// Trigger when altitude too low
    AltitudeLimit { min_altitude: f64 },
    /// Trigger when weather unsafe
    WeatherUnsafe,
    /// Trigger when temperature changes
    TemperatureShift { degrees: f64 },
    /// Trigger on filter change
    FilterChange,
    /// Trigger when dawn is approaching (astronomical twilight)
    DawnApproaching { minutes_before: f64 },
    /// Trigger autofocus every N exposures
    AutofocusInterval { every_n_frames: u32 },
    /// Trigger dither every N exposures
    DitherInterval { every_n_frames: u32 },
    /// Mount tracking was lost during exposure
    MountTrackingLost,
    /// Dome shutter is not open when expected
    DomeShutterNotOpen,
    /// Guide star lost - guider reports no star or lost lock
    GuideStarLost,
    /// Focus drift detection - monotonically increasing HFR moving average over N frames
    /// Unlike HfrDegraded which catches sudden spikes, this detects gradual drift
    FocusDrift {
        /// Number of HFR samples to track in the moving window
        window_size: usize,
        /// Minimum number of consecutive increases before triggering (must be >= 2)
        min_increasing_count: usize,
        /// Minimum total HFR increase (last - first in the increasing run) to fire
        min_total_increase: f64,
    },
    /// Humidity threshold - fire when humidity exceeds max_percent
    HumidityThreshold {
        /// Maximum humidity percentage before triggering (e.g., 85.0)
        max_percent: f64,
    },
    /// Plate-solve drift trigger (audit §1.11). Fires when the most recent
    /// plate-solve reports an accumulated drift from the target exceeding
    /// `max_pixels`. The drift is computed by `TriggerState::calculate_drift_pixels`
    /// using the last plate-solve coordinates, the target coordinates, and the
    /// solver-reported pixel scale; both the RA and Dec axes are summed in
    /// quadrature so a small drift in either axis cannot mask a large drift
    /// in the other. Default standard recovery is `Recenter`.
    DriftLimit {
        /// Maximum drift in pixels before the trigger fires.
        max_pixels: f64,
    },
}

fn default_consecutive_frames() -> u32 {
    1
}

/// Default rolling-window length (seconds) for guiding-RMS history retained
/// in `TriggerState::guiding_rms_history`. Audit §1.21.
pub fn default_guiding_rms_retention_secs() -> u64 {
    300
}

/// Default focus-drift window size (samples) for the standard `FocusDrift`
/// trigger. Audit §1.21 — moved out of the magic-number site so config
/// loaders and the standard-trigger builder share the same default.
pub fn default_focus_drift_window_size() -> usize {
    10
}

/// Default minimum-consecutive-increasing-frame count for the standard
/// `FocusDrift` trigger. Audit §1.21.
pub fn default_focus_drift_min_increasing_count() -> usize {
    5
}

/// Default minimum total HFR increase across the increasing run for the
/// standard `FocusDrift` trigger. Audit §1.21.
pub fn default_focus_drift_min_total_increase() -> f64 {
    0.5
}

/// Recovery action to take when a trigger fires or error occurs.
///
/// Audit §1.5:
/// - `Dither(DitherConfig)` was added so the standard `DitherInterval` trigger
///   has a real action to run; without it the trigger would silently drop into
///   the catch-all match arm.
/// - `CustomBranch` is retained for serialised on-disk compatibility with
///   stored sequences but is rejected as a configuration error at runtime
///   (the executor emits an error event and pauses the sequence) until a
///   child-node recovery branch is wired. Treating it as a no-op was the
///   silent-drop bug §1.5 called out — refusing it loudly is the policy.
/// - `Recenter` was added (audit §1.11) so the new `DriftLimit` trigger has
///   a non-destructive recovery path: re-slew to the target and plate-solve
///   instead of pausing the whole sequence.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub enum RecoveryAction {
    /// Continue execution (ignore error)
    #[default]
    Continue,
    /// Pause the sequence
    Pause,
    /// Run autofocus
    Autofocus,
    /// Skip to next target
    NextTarget,
    /// Retry the failed node
    Retry { max_attempts: u32 },
    /// Park and abort
    ParkAndAbort,
    /// Reserved variant — see the enum-level rustdoc. Stored sequences may
    /// still contain this value, so it must round-trip; the executor refuses
    /// it at runtime instead of silently treating it as a no-op.
    CustomBranch,
    /// Execute meridian flip with given config
    MeridianFlip(MeridianFlipConfig),
    /// Run a dither using the supplied config. Used by the standard
    /// `DitherInterval` trigger so periodic dithering is honoured even when
    /// no explicit Dither instruction node is in the sequence. Audit §1.5.
    Dither(DitherConfig),
    /// Re-slew to the target and plate-solve. Used by the `DriftLimit` trigger
    /// (audit §1.11) when accumulated drift exceeds the configured pixel
    /// budget — a recenter is the lowest-risk recovery (no flip, no abort).
    Recenter,
}
