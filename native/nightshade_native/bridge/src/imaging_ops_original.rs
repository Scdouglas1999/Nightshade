//! Imaging Operations API
//!
//! High-level API for camera control and imaging operations.
//! Exposed to Flutter via flutter_rust_bridge.

use crate::{SharedAppState, RealDeviceOps};
use crate::device::{DeviceType, ExposureParams};
use crate::event::{EventPayload, EventSeverity, create_event, EventCategory};
use nightshade_imaging::{ImageData, write_fits, FitsHeader, generate_simulated_image};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::RwLock;

/// Imaging session handle
pub struct ImagingSession {
    app_state: SharedAppState,
    device_ops: Arc<RealDeviceOps>,
    is_running: Arc<AtomicBool>,
    should_stop: Arc<AtomicBool>,
}

impl ImagingSession {
    pub fn new(app_state: SharedAppState, device_ops: Arc<RealDeviceOps>) -> Self {
        Self {
            app_state,
            device_ops,
            is_running: Arc::new(AtomicBool::new(false)),
            should_stop: Arc::new(AtomicBool::new(false)),
        }
    }
    
    /// Start a single exposure
    pub async fn start_single_exposure(
        &self,
        camera_id: String,
        params: ExposureParams,
    ) -> Result<String, String> {
        if self.is_running.load(Ordering::SeqCst) {
            return Err("Imaging session already running".to_string());
        }
        
        self.is_running.store(true, Ordering::SeqCst);
        
        tracing::info!(
            "Starting single exposure: {}s, gain={:?}, offset={:?}",
            params.duration_secs, params.gain, params.offset
        );
        
        // Publish exposure started event
        self.publish_exposure_started(&params);
        
        // Take exposure
        let image_result = self.device_ops.camera_start_exposure(
            &camera_id,
            params.duration_secs,
            params.gain,
            params.offset,
            params.binning.unwrap_or(1),
            params.binning.unwrap_or(1),
        ).await;
        
        self.is_running.store(false, Ordering::SeqCst);
        
        match image_result {
            Ok(seq_image_data) => {
                // Convert to imaging crate ImageData
                let image = ImageData::from_u16(
                    seq_image_data.width,
                    seq_image_data.height,
                    1,
                    &seq_image_data.data,
                );
                
                // Calculate stats (HFR, etc.)
                let stats = nightshade_imaging::calculate_statistics(&image);
                let hfr = nightshade_imaging::calculate_hfr(&image);
                
                tracing::info!(
                    "Exposure completed: {} stars detected, HFR={:.2}",
                    stats.star_count, hfr
                );
                
                // Save to file if save path provided
                let file_path = if let Some(ref base_path) = params.save_path {
                    let path = self.generate_filename(base_path, &params, 1);
                    self.save_image(&image, &path, &params, &seq_image_data).await?;
                    Some(path)
                } else {
                    None
                };
                
                // Publish completion event
                self.publish_exposure_completed(file_path.as_deref(), hfr, stats.star_count as u32);
                
                Ok(file_path.unwrap_or_else(|| "In-memory image".to_string()))
            }
            Err(e) => {
                self.publish_exposure_failed(&e);
                Err(e)
            }
        }
    }
    
    /// Start looping exposures
    pub async fn start_looping_exposure(
        &self,
        camera_id: String,
        params: ExposureParams,
    ) -> Result<(), String> {
        if self.is_running.load(Ordering::SeqCst) {
            return Err("Imaging session already running".to_string());
        }
        
        self.is_running.store(true, Ordering::SeqCst);
        self.should_stop.store(false, Ordering::SeqCst);
        
        tracing::info!(
            "Starting looping exposure: {}s, gain={:?}",
            params.duration_secs, params.gain
        );
        
        let mut frame_number = 1u32;
        
        while !self.should_stop.load(Ordering::SeqCst) {
            // Publish exposure started event with frame number
            self.publish_exposure_started_with_frame(&params, frame_number, None);
            
            // Take exposure
            let image_result = self.device_ops.camera_start_exposure(
                &camera_id,
                params.duration_secs,
                params.gain,
                params.offset,
                params.binning.unwrap_or(1),
                params.binning.unwrap_or(1),
            ).await;
            
            match image_result {
                Ok(seq_image_data) => {
                    let image = ImageData::from_u16(
                        seq_image_data.width,
                        seq_image_data.height,
                        1,
                        &seq_image_data.data,
                    );
                    
                    let stats = nightshade_imaging::calculate_statistics(&image);
                    let hfr = nightshade_imaging::calculate_hfr(&image);
                    
                    // Save to file if save path provided
                    if let Some(ref base_path) = params.save_path {
                        let path = self.generate_filename(base_path, &params, frame_number);
                        if let Err(e) = self.save_image(&image, &path, &params, &seq_image_data).await {
                            tracing::error!("Failed to save frame {}: {}", frame_number, e);
                        }
                    }
                    
                    self.publish_exposure_completed_with_frame(frame_number, None, hfr, stats.star_count as u32);
                    
                    frame_number += 1;
                }
                Err(e) => {
                    tracing::error!("Exposure {} failed: {}", frame_number, e);
                    self.publish_exposure_failed(&e);
                    break;
                }
            }
        }
        
        self.is_running.store(false, Ordering::SeqCst);
        tracing::info!("Looping exposure stopped after {} frames", frame_number - 1);
        
        Ok(())
    }
    
    /// Stop looping exposure
    pub fn stop_looping(&self) {
        self.should_stop.store(true, Ordering::SeqCst);
        tracing::info!("Stop requested for looping exposure");
    }
    
    /// Abort current exposure
    pub async fn abort_exposure(&self, camera_id: String) -> Result<(), String> {
        self.device_ops.camera_abort_exposure(&camera_id).await?;
        self.should_stop.store(true, Ordering::SeqCst);
        tracing::info!("Exposure aborted");
        Ok(())
    }
    
    /// Check if imaging is currently running
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }
    
    // =========================================================================
    // HELPER METHODS
    // =========================================================================
    
    /// Generate filename using pattern
    fn generate_filename(&self, base_path: &str, params: &ExposureParams, frame_number: u32) -> String {
        use nightshade_imaging::apply_naming_pattern;
        
        let pattern = params.naming_pattern.as_deref().unwrap_or("$TARGET_$FILTER_$FRAME");
        
        let metadata = std::collections::HashMap::from([
            ("TARGET".to_string(), params.target_name.clone().unwrap_or_else(|| "Unknown".to_string())),
            ("FILTER".to_string(), params.filter.clone().unwrap_or_else(|| "L".to_string())),
            ("FRAME".to_string(), format!("{:04}", frame_number)),
            ("EXPOSURE".to_string(), format!("{:.0}s", params.duration_secs)),
            ("GAIN".to_string(), params.gain.map(|g| g.to_string()).unwrap_or_else(|| "0".to_string())),
            ("BINNING".to_string(), format!("{}x{}", params.binning.unwrap_or(1), params.binning.unwrap_or(1))),
            ("TYPE".to_string(), format!("{:?}", params.frame_type)),
        ]);
        
        let filename = apply_naming_pattern(pattern, &metadata);
        format!("{}/{}.fits", base_path, filename)
    }
    
    /// Save image to FITS file
    async fn save_image(
        &self,
        image: &ImageData,
        file_path: &str,
        params: &ExposureParams,
        seq_data: &nightshade_sequencer::ImageData,
    ) -> Result<(), String> {
        tracing::info!("Saving image to: {}", file_path);
        
        // Build FITS header
        let mut header = FitsHeader::new();
        
        // Standard keywords
        header.set_float("EXPTIME", params.duration_secs);
        if let Some(gain) = params.gain {
            header.set_int("GAIN", gain as i64);
        }
        if let Some(offset) = params.offset {
            header.set_int("OFFSET", offset as i64);
        }
        if let Some(binning) = params.binning {
            header.set_int("XBINNING", binning as i64);
            header.set_int("YBINNING", binning as i64);
        }
        if let Some(ref target) = params.target_name {
            header.set_string("OBJECT", target);
        }
        if let Some(ref filter) = params.filter {
            header.set_string("FILTER", filter);
        }
        if let Some(temp) = seq_data.temperature {
            header.set_float("CCD-TEMP", temp);
        }
        
        header.set_string("IMAGETYP", &format!("{:?}", params.frame_type));
        header.set_string("DATE-OBS", &chrono::Utc::now().to_rfc3339());
        
        // Create directory if it doesn't exist
        if let Some(parent) = std::path::Path::new(file_path).parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create directory: {}", e))?;
        }
        
        // Write FITS file
        write_fits(std::path::Path::new(file_path), image, &header)
            .map_err(|e| format!("Failed to write FITS: {}", e))?;
        
        tracing::info!("Image saved successfully");
        Ok(())
    }
    
    // =========================================================================
    // EVENT PUBLISHING
    // =========================================================================
    
    fn publish_exposure_started(&self, params: &ExposureParams) {
        let event = create_event(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureStarted {
                duration_secs: params.duration_secs,
                frame_type: params.frame_type,
            }),
        );
        self.app_state.event_bus.publish(event);
    }
    
    fn publish_exposure_started_with_frame(&self, params: &ExposureParams, frame: u32, total: Option<u32>) {
        let event = create_event(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureStartedWithFrame {
                duration_secs: params.duration_secs,
                frame_type: params.frame_type,
                frame_number: frame,
                total_frames: total,
            }),
        );
        self.app_state.event_bus.publish(event);
    }
    
    fn publish_exposure_completed(&self, file_path: Option<&str>, hfr: f64, stars: u32) {
        let event = create_event(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureCompleted {
                file_path: file_path.map(|s| s.to_string()),
                hfr,
                stars_detected: stars,
            }),
        );
        self.app_state.event_bus.publish(event);
    }
    
    fn publish_exposure_completed_with_frame(&self, frame: u32, total: Option<u32>, hfr: f64, stars: u32) {
        let event = create_event(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureCompletedWithFrame {
                frame_number: frame,
                total_frames: total,
                hfr,
                stars_detected: stars,
            }),
        );
        self.app_state.event_bus.publish(event);
    }
    
    fn publish_exposure_failed(&self, error: &str) {
        let event = create_event(
            EventSeverity::Error,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureFailed {
                error: error.to_string(),
            }),
        );
        self.app_state.event_bus.publish(event);
    }
}

/// Global imaging session (singleton)
static IMAGING_SESSION: RwLock<Option<Arc<ImagingSession>>> = RwLock::const_new(None);

/// Initialize imaging session
pub async fn init_imaging_session(app_state: SharedAppState, device_ops: Arc<RealDeviceOps>) {
    let session = Arc::new(ImagingSession::new(app_state, device_ops));
    *IMAGING_SESSION.write().await = Some(session);
}

/// Get the imaging session
async fn get_imaging_session() -> Result<Arc<ImagingSession>, String> {
    IMAGING_SESSION
        .read()
        .await
        .clone()
        .ok_or_else(|| "Imaging session not initialized".to_string())
}

// =========================================================================
// PUBLIC API (exposed to Flutter via flutter_rust_bridge)
// =========================================================================

/// Start a single exposure
pub async fn imaging_start_single_exposure(
    camera_id: String,
    params: ExposureParams,
) -> Result<String, String> {
    let session = get_imaging_session().await?;
    session.start_single_exposure(camera_id, params).await
}

/// Start looping exposures
pub async fn imaging_start_looping(
    camera_id: String,
    params: ExposureParams,
) -> Result<(), String> {
    let session = get_imaging_session().await?;
    
    // Spawn background task for looping
    let session_clone = session.clone();
    tokio::spawn(async move {
        if let Err(e) = session_clone.start_looping_exposure(camera_id, params).await {
            tracing::error!("Looping exposure failed: {}", e);
        }
    });
    
    Ok(())
}

/// Stop looping exposures
pub async fn imaging_stop_looping() -> Result<(), String> {
    let session = get_imaging_session().await?;
    session.stop_looping();
    Ok(())
}

/// Abort current exposure
pub async fn imaging_abort_exposure(camera_id: String) -> Result<(), String> {
    let session = get_imaging_session().await?;
    session.abort_exposure(camera_id).await
}

/// Check if imaging is currently running
pub async fn imaging_is_running() -> Result<bool, String> {
    let session = get_imaging_session().await?;
    Ok(session.is_running())
}
