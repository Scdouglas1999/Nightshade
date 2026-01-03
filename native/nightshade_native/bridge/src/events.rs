//! Global event bus for the sequencer and UI communication

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// Event severity level
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EventSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

/// Global event types
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GlobalEvent {
    // Sequence events
    SequenceStarted { sequence_name: String },
    SequencePaused { reason: String },
    SequenceResumed,
    SequenceCompleted { total_exposures: i32 },
    SequenceError { message: String },
    
    // Equipment events
    DeviceConnected { device_type: String, device_name: String },
    DeviceDisconnected { device_type: String, device_name: String },
    DeviceError { device_type: String, message: String },
    
    // Imaging events
    ExposureStarted { filter: Option<String>, duration: f64 },
    ExposureProgress { progress: f64 },
    ExposureCompleted { file_path: String },
    ExposureFailed { reason: String },
    
    // Mount events
    SlewStarted { ra: f64, dec: f64 },
    SlewCompleted,
    TrackingLost,
    MeridianFlipRequired { minutes_until: f64 },
    
    // Guiding events
    GuidingStarted,
    GuidingStopped,
    GuideStarLost,
    GuidingError { rms: f64 },
    DitherStarted,
    DitherSettled,
    
    // Focus events
    AutofocusStarted,
    AutofocusCompleted { position: i32, hfr: f64 },
    AutofocusFailed { reason: String },
    
    // Safety events
    SafetyAlert { message: String, severity: EventSeverity },
    WeatherUnsafe { reason: String },
    WeatherSafe,
    
    // General
    Notification { title: String, message: String, severity: EventSeverity },
}

/// Event with timestamp
#[frb]
#[derive(Debug, Clone)]
pub struct TimestampedEvent {
    pub timestamp_ms: i64,
    pub event: GlobalEvent,
}

/// Create a new event stream for Flutter to listen to
#[frb]
pub fn create_event_stream() -> impl futures::Stream<Item = TimestampedEvent> {
    // TODO: Implement actual event stream from sequencer
    futures::stream::empty()
}





