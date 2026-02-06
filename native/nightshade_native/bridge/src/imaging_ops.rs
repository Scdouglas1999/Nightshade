//! Imaging Operations API
//!
//! High-level API for camera control and imaging operations.
//! Exposed to Flutter via flutter_rust_bridge.
//!
//! Implements pipeline parallelism:
//! Capture -> Download -> [Queue] -> Processing (Stats/Save)

use crate::device::ExposureParams;
use crate::device::ImageFileFormat;
use crate::event::{create_event_auto_id, EventCategory, EventPayload, EventSeverity};
use crate::{RealDeviceOps, SharedAppState};
use nightshade_imaging::{
    apply_stretch, auto_stretch_stf, calculate_stats_u16, debayer, detect_stars, write_fits,
    write_jpeg, write_png, write_tiff, write_xisf, BayerPattern, DebayerAlgorithm, FitsHeader,
    FrameType as NamingFrameType, ImageData, ImageStats, NamingContext, NamingPattern,
    StarDetectionConfig, XisfMetadata,
};
use nightshade_sequencer::DeviceOps;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};

/// Job to be processed by the background worker
struct ProcessingJob {
    image: ImageData,
    seq_image_data: nightshade_sequencer::ImageData,
    params: ExposureParams,
    frame_number: u32,
    file_path: Option<String>,
}

/// Imaging session handle
pub struct ImagingSession {
    app_state: SharedAppState,
    device_ops: Arc<RealDeviceOps>,
    is_running: Arc<AtomicBool>,
    should_stop: Arc<AtomicBool>,
    // Channel for sending jobs to the processing task
    processing_tx: mpsc::Sender<ProcessingJob>,
    // Handle to the processing task (to await it on shutdown)
    _processing_handle: Arc<RwLock<Option<tokio::task::JoinHandle<()>>>>,
}

impl ImagingSession {
    pub fn new(app_state: SharedAppState, device_ops: Arc<RealDeviceOps>) -> Self {
        // Create the processing channel (bounded to avoid OOM)
        let (tx, mut rx) = mpsc::channel::<ProcessingJob>(5); // Buffer 5 frames

        let session = Self {
            app_state: app_state.clone(),
            device_ops,
            is_running: Arc::new(AtomicBool::new(false)),
            should_stop: Arc::new(AtomicBool::new(false)),
            processing_tx: tx,
            _processing_handle: Arc::new(RwLock::new(None)),
        };

        // Spawn the processing worker
        let app_state_clone = app_state.clone();
        let _handle = tokio::spawn(async move {
            tracing::info!("Imaging processing worker started");

            while let Some(job) = rx.recv().await {
                tracing::info!("Processing frame {}", job.frame_number);

                // 1. Calculate stats (CPU intensive)
                let _stats = calculate_stats_u16(&job.image);
                let hfr = Self::calculate_hfr_avg(&job.image);
                let star_count = detect_stars(&job.image, &StarDetectionConfig::default()).len();

                // 2. Save to file (I/O intensive)
                if let Some(ref path) = job.file_path {
                    if let Err(e) =
                        Self::save_image_static(&job.image, path, &job.params, &job.seq_image_data)
                            .await
                    {
                        tracing::error!("Failed to save frame {}: {}", job.frame_number, e);
                        Self::publish_exposure_failed_static(&app_state_clone, &e);
                        continue;
                    }
                }

                // 3. Publish completion event
                Self::publish_exposure_completed_static(
                    &app_state_clone,
                    job.frame_number,
                    None, // Total frames unknown in loop
                    hfr,
                    star_count as u32,
                );

                tracing::info!("Frame {} processed successfully", job.frame_number);
            }

            tracing::info!("Imaging processing worker stopped");
        });

        session
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
            params.duration_secs,
            params.gain,
            params.offset
        );

        // Publish exposure started event
        self.publish_exposure_started(&params);

        // Take exposure
        let image_result = self
            .device_ops
            .camera_start_exposure(
                &camera_id,
                params.duration_secs,
                params.gain,
                params.offset,
                params.bin_x,
                params.bin_y,
            )
            .await;

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

                // For single exposure, we process inline to return the result immediately
                // This preserves the existing behavior for single shots

                let _stats = calculate_stats_u16(&image);
                let hfr = Self::calculate_hfr_avg(&image);
                let star_count = detect_stars(&image, &StarDetectionConfig::default()).len();

                tracing::info!(
                    "Exposure completed: {} stars detected, HFR={:.2}",
                    star_count,
                    hfr
                );

                // Save to file if save path provided
                let file_path = if let Some(ref base_path) = params.save_path {
                    let path = self.generate_filename(base_path, &params, 1);
                    Self::save_image_static(&image, &path, &params, &seq_image_data).await?;
                    Some(path)
                } else {
                    None
                };

                // Publish completion event
                self.publish_exposure_completed(file_path.as_deref(), hfr, star_count as u32);

                Ok(file_path.unwrap_or_else(|| "In-memory image".to_string()))
            }
            Err(e) => {
                self.publish_exposure_failed(&e);
                Err(e)
            }
        }
    }

    /// Start looping exposures (Pipelined)
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
            "Starting looping exposure (pipelined): {}s, gain={:?}",
            params.duration_secs,
            params.gain
        );

        let mut frame_number = 1u32;

        while !self.should_stop.load(Ordering::SeqCst) {
            // Publish exposure started event with frame number
            self.publish_exposure_started_with_frame(&params, frame_number, None);

            // Take exposure (Blocks until download completes)
            let image_result = self
                .device_ops
                .camera_start_exposure(
                    &camera_id,
                    params.duration_secs,
                    params.gain,
                    params.offset,
                    params.bin_x,
                    params.bin_y,
                )
                .await;

            match image_result {
                Ok(seq_image_data) => {
                    // Convert to imaging crate ImageData (fast, just a copy/move)
                    let image = ImageData::from_u16(
                        seq_image_data.width,
                        seq_image_data.height,
                        1,
                        &seq_image_data.data,
                    );

                    // Generate filename if needed
                    let file_path = if let Some(ref base_path) = params.save_path {
                        Some(self.generate_filename(base_path, &params, frame_number))
                    } else {
                        None
                    };

                    // Create job
                    let job = ProcessingJob {
                        image,
                        seq_image_data,
                        params: params.clone(),
                        frame_number,
                        file_path,
                    };

                    // Send to processing queue
                    // If queue is full, this will wait (backpressure)
                    if let Err(e) = self.processing_tx.send(job).await {
                        tracing::error!(
                            "Failed to send frame {} to processing queue: {}",
                            frame_number,
                            e
                        );
                        break;
                    }

                    tracing::info!("Frame {} sent to processing queue", frame_number);

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

    /// Save image to file (supports multiple formats)
    async fn save_image_static(
        image: &ImageData,
        file_path: &str,
        params: &ExposureParams,
        seq_data: &nightshade_sequencer::ImageData,
    ) -> Result<(), String> {
        tracing::info!(
            "Saving image to: {} (format: {:?})",
            file_path,
            params.file_format
        );

        // Create directory if it doesn't exist
        if let Some(parent) = std::path::Path::new(file_path).parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create directory: {}", e))?;
        }

        let path = std::path::Path::new(file_path);

        match params.file_format {
            ImageFileFormat::Fits => {
                // Build FITS header with full metadata
                let mut header = FitsHeader::new();

                header.set_float("EXPTIME", params.duration_secs);
                if let Some(gain) = params.gain {
                    header.set_int("GAIN", gain as i64);
                }
                if let Some(offset) = params.offset {
                    header.set_int("OFFSET", offset as i64);
                }
                if params.bin_x > 1 || params.bin_y > 1 {
                    header.set_int("XBINNING", params.bin_x as i64);
                    header.set_int("YBINNING", params.bin_y as i64);
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

                write_fits(path, image, &header)
                    .map_err(|e| format!("Failed to write FITS: {}", e))?;
            }
            ImageFileFormat::Xisf => {
                // Build XISF metadata with FITS keywords for compatibility
                let mut metadata = XisfMetadata::default();

                // Add FITS keywords for interoperability
                metadata
                    .fits_keywords
                    .insert("EXPTIME".to_string(), params.duration_secs.to_string());
                if let Some(gain) = params.gain {
                    metadata
                        .fits_keywords
                        .insert("GAIN".to_string(), gain.to_string());
                }
                if let Some(offset) = params.offset {
                    metadata
                        .fits_keywords
                        .insert("OFFSET".to_string(), offset.to_string());
                }
                if params.bin_x > 1 || params.bin_y > 1 {
                    metadata
                        .fits_keywords
                        .insert("XBINNING".to_string(), params.bin_x.to_string());
                    metadata
                        .fits_keywords
                        .insert("YBINNING".to_string(), params.bin_y.to_string());
                }
                if let Some(ref target) = params.target_name {
                    metadata
                        .fits_keywords
                        .insert("OBJECT".to_string(), target.clone());
                }
                if let Some(ref filter) = params.filter {
                    metadata
                        .fits_keywords
                        .insert("FILTER".to_string(), filter.clone());
                }
                if let Some(temp) = seq_data.temperature {
                    metadata
                        .fits_keywords
                        .insert("CCD-TEMP".to_string(), temp.to_string());
                }
                metadata
                    .fits_keywords
                    .insert("IMAGETYP".to_string(), format!("{:?}", params.frame_type));
                metadata
                    .fits_keywords
                    .insert("DATE-OBS".to_string(), chrono::Utc::now().to_rfc3339());

                // Add XISF-specific properties
                use nightshade_imaging::XisfProperty;
                metadata.properties.insert(
                    "Instrument:ExposureTime".to_string(),
                    XisfProperty::Float64(params.duration_secs),
                );
                if let Some(gain) = params.gain {
                    metadata.properties.insert(
                        "Instrument:Camera:Gain".to_string(),
                        XisfProperty::Int32(gain),
                    );
                }
                if let Some(temp) = seq_data.temperature {
                    metadata.properties.insert(
                        "Instrument:Sensor:Temperature".to_string(),
                        XisfProperty::Float64(temp),
                    );
                }
                metadata.properties.insert(
                    "Observation:Time:Start".to_string(),
                    XisfProperty::TimePoint(chrono::Utc::now().to_rfc3339()),
                );

                write_xisf(path, image, &metadata)
                    .map_err(|e| format!("Failed to write XISF: {}", e))?;
            }
            ImageFileFormat::Tiff => {
                // TIFF preserves 16-bit data but has limited metadata support
                write_tiff(path, image).map_err(|e| format!("Failed to write TIFF: {}", e))?;
            }
            ImageFileFormat::Png => {
                // PNG preserves 16-bit data, lossless compression
                write_png(path, image).map_err(|e| format!("Failed to write PNG: {}", e))?;
            }
            ImageFileFormat::Jpeg => {
                // JPEG is lossy and 8-bit only - use for previews
                write_jpeg(path, image, 90) // Quality 90
                    .map_err(|e| format!("Failed to write JPEG: {}", e))?;
            }
        }

        tracing::info!("Image saved successfully as {:?}", params.file_format);
        Ok(())
    }

    // =========================================================================
    // EVENT PUBLISHING
    // =========================================================================

    fn publish_exposure_started(&self, params: &ExposureParams) {
        let event = create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureStarted {
                duration_secs: params.duration_secs,
                frame_type: params.frame_type,
            }),
        );
        self.app_state.event_bus.publish(event);
    }

    fn publish_exposure_started_with_frame(
        &self,
        params: &ExposureParams,
        frame: u32,
        total: Option<u32>,
    ) {
        let event = create_event_auto_id(
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
        Self::publish_exposure_completed_static(&self.app_state, 0, file_path, hfr, stars);
    }

    fn publish_exposure_completed_static(
        app_state: &SharedAppState,
        frame: u32,
        file_path: Option<&str>,
        hfr: f64,
        stars: u32,
    ) {
        let event = if frame > 0 {
            create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Imaging,
                EventPayload::Imaging(crate::event::ImagingEvent::ExposureCompletedWithFrame {
                    frame_number: frame,
                    total_frames: None,
                    hfr,
                    stars_detected: stars,
                }),
            )
        } else {
            create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Imaging,
                EventPayload::Imaging(crate::event::ImagingEvent::ExposureCompleted {
                    file_path: file_path.map(|s| s.to_string()),
                    hfr,
                    stars_detected: stars,
                }),
            )
        };
        app_state.event_bus.publish(event);
    }

    fn publish_exposure_failed(&self, error: &str) {
        Self::publish_exposure_failed_static(&self.app_state, error);
    }

    fn publish_exposure_failed_static(app_state: &SharedAppState, error: &str) {
        let event = create_event_auto_id(
            EventSeverity::Error,
            EventCategory::Imaging,
            EventPayload::Imaging(crate::event::ImagingEvent::ExposureFailed {
                error: error.to_string(),
            }),
        );
        app_state.event_bus.publish(event);
    }

    fn generate_filename(
        &self,
        base_path: &str,
        params: &ExposureParams,
        frame_num: u32,
    ) -> String {
        let pattern_str = params
            .naming_pattern
            .as_deref()
            .unwrap_or("$TARGET/$FRAMETYPE/$TARGET_$FILTER_$EXPTIME_$FRAMENUM");
        let pattern = NamingPattern::new(pattern_str)
            .with_base_dir(base_path)
            .with_extension(params.file_format.extension());

        let naming_frame_type = match params.frame_type {
            crate::device::FrameType::Light => NamingFrameType::Light,
            crate::device::FrameType::Dark => NamingFrameType::Dark,
            crate::device::FrameType::Flat => NamingFrameType::Flat,
            crate::device::FrameType::Bias => NamingFrameType::Bias,
            crate::device::FrameType::DarkFlat => NamingFrameType::DarkFlat,
        };

        let mut context = NamingContext::new()
            .with_frame_type(naming_frame_type)
            .with_frame_number(frame_num)
            .with_exposure(params.duration_secs)
            .with_binning(params.bin_x as u32, params.bin_y as u32);

        if let Some(ref target) = params.target_name {
            context = context.with_target(target);
        }
        if let Some(ref filter) = params.filter {
            context = context.with_filter(filter);
        }
        if let Some(gain) = params.gain {
            context = context.with_gain(gain);
        }
        if let Some(offset) = params.offset {
            context = context.with_offset(offset);
        }

        pattern.generate(&context).to_string_lossy().to_string()
    }

    fn calculate_hfr_avg(image: &ImageData) -> f64 {
        let config = StarDetectionConfig::default();
        let stars = detect_stars(image, &config);
        if stars.is_empty() {
            0.0
        } else {
            let sum: f64 = stars.iter().map(|s| s.hfr).sum();
            sum / stars.len() as f64
        }
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
        if let Err(e) = session_clone
            .start_looping_exposure(camera_id, params)
            .await
        {
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

// =========================================================================
// IMAGE PROCESSING
// =========================================================================

/// Calculate image statistics
/// Internal function - not exposed to Dart
pub(crate) fn get_image_stats(width: u32, height: u32, data: Vec<u16>) -> ImageStats {
    let image = ImageData::from_u16(width, height, 1, &data);
    calculate_stats_u16(&image)
}

/// Auto-stretch image for display
pub fn auto_stretch_image(width: u32, height: u32, data: Vec<u16>) -> Vec<u8> {
    let image = ImageData::from_u16(width, height, 1, &data);
    let params = auto_stretch_stf(&image);
    apply_stretch(&image, &params)
}

/// Debayer image to RGBA8
pub fn debayer_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
    pattern: BayerPattern,
    algorithm: DebayerAlgorithm,
) -> Vec<u8> {
    // Convert u16 vec to u8 slice (little endian)
    let bytes: Vec<u8> = data.iter().flat_map(|&v| v.to_le_bytes()).collect();

    let rgb = debayer(&bytes, width, height, pattern, algorithm);
    rgb.to_rgba8()
}

// =========================================================================
// IMAGE DOWNLOAD API (for Mobile)
// =========================================================================

use std::sync::RwLock as StdRwLock;

/// Global image directory for file-based image listing
static IMAGE_DIRECTORY: StdRwLock<Option<String>> = StdRwLock::new(None);

/// Set the image directory for scanning (call this on session start)
pub fn set_image_directory(path: String) {
    if let Ok(mut dir) = IMAGE_DIRECTORY.write() {
        *dir = Some(path);
    }
}

/// Get the current image directory
fn get_image_directory() -> Option<String> {
    IMAGE_DIRECTORY.read().ok().and_then(|d| d.clone())
}

/// Image metadata for mobile client
#[derive(Debug, Clone)]
pub struct ImageInfo {
    pub image_id: i64,
    pub session_id: Option<i64>,
    pub file_path: String,
    pub file_name: String,
    pub file_format: String,
    pub file_size: Option<i64>,
    pub frame_type: String,
    pub exposure_duration: f64,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub bin_x: i32,
    pub bin_y: i32,
    pub filter: Option<String>,
    pub hfr: Option<f64>,
    pub star_count: Option<i32>,
    pub captured_at: i64,
    pub is_accepted: bool,
}

/// Get all images from a directory (scans for FITS files)
pub async fn get_session_images(session_id: i64) -> Result<Vec<ImageInfo>, String> {
    use nightshade_imaging::read_fits;
    use std::fs;
    use std::path::Path;

    let image_dir = get_image_directory().ok_or_else(|| "Image directory not set".to_string())?;

    let dir_path = Path::new(&image_dir);
    if !dir_path.exists() {
        return Ok(Vec::new());
    }

    let mut images = Vec::new();
    let mut id_counter = 0i64;

    // Recursively find all FITS files
    fn scan_directory(
        dir: &Path,
        images: &mut Vec<ImageInfo>,
        id_counter: &mut i64,
        session_id: i64,
    ) {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    scan_directory(&path, images, id_counter, session_id);
                } else if let Some(ext) = path.extension() {
                    let ext_lower = ext.to_string_lossy().to_lowercase();
                    if ext_lower == "fits" || ext_lower == "fit" {
                        if let Ok(metadata) = fs::metadata(&path) {
                            let file_name = path
                                .file_name()
                                .map(|n| n.to_string_lossy().to_string())
                                .unwrap_or_default();

                            // Try to extract info from FITS header
                            let (exposure, gain, offset, frame_type, filter) =
                                if let Ok((_, header)) = read_fits(&path) {
                                    (
                                        header.get_float("EXPTIME").unwrap_or(0.0),
                                        header.get_int("GAIN").map(|v| v as i32),
                                        header.get_int("OFFSET").map(|v| v as i32),
                                        header
                                            .get_string("IMAGETYP")
                                            .unwrap_or("Light")
                                            .to_string(),
                                        header.get_string("FILTER").map(|s| s.to_string()),
                                    )
                                } else {
                                    (
                                        0.0f64,
                                        None::<i32>,
                                        None::<i32>,
                                        "Light".to_string(),
                                        None::<String>,
                                    )
                                };

                            *id_counter += 1;
                            images.push(ImageInfo {
                                image_id: *id_counter,
                                session_id: Some(session_id),
                                file_path: path.to_string_lossy().to_string(),
                                file_name,
                                file_format: "FITS".to_string(),
                                file_size: Some(metadata.len() as i64),
                                frame_type,
                                exposure_duration: exposure,
                                gain,
                                offset,
                                bin_x: 1,
                                bin_y: 1,
                                filter,
                                hfr: None,
                                star_count: None,
                                captured_at: metadata
                                    .modified()
                                    .map(|t| {
                                        t.duration_since(std::time::UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_secs()
                                            as i64
                                    })
                                    .unwrap_or(0),
                                is_accepted: true,
                            });
                        }
                    }
                }
            }
        }
    }

    scan_directory(dir_path, &mut images, &mut id_counter, session_id);

    // Sort by capture time
    images.sort_by_key(|i| i.captured_at);

    tracing::info!("Found {} images in directory {}", images.len(), image_dir);
    Ok(images)
}

/// Get thumbnail data for an image by file path (JPEG, 512x512 max)
pub async fn get_image_thumbnail_by_path(file_path: String) -> Result<Vec<u8>, String> {
    use nightshade_imaging::read_fits;
    use std::path::Path;

    tracing::info!("Generating thumbnail for: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(format!("Image file not found: {}", file_path));
    }

    let (image, _header) = read_fits(path).map_err(|e| format!("Failed to read FITS: {}", e))?;

    let thumbnail = downsample_image(&image, 512, 512);
    let params = auto_stretch_stf(&thumbnail);
    let stretched = apply_stretch(&thumbnail, &params);

    encode_jpeg(&stretched, thumbnail.width, thumbnail.height)
}

/// Get full image data for download by file path
pub async fn get_image_data_by_path(file_path: String) -> Result<Vec<u8>, String> {
    use std::path::Path;

    tracing::info!("Loading full image data: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(format!("Image file not found: {}", file_path));
    }

    std::fs::read(path).map_err(|e| format!("Failed to read image file: {}", e))
}

fn downsample_image(image: &ImageData, max_width: u32, max_height: u32) -> ImageData {
    let scale = f32::min(
        max_width as f32 / image.width as f32,
        max_height as f32 / image.height as f32,
    );

    if scale >= 1.0 {
        return image.clone();
    }

    let new_width = (image.width as f32 * scale) as u32;
    let new_height = (image.height as f32 * scale) as u32;

    // For U16 images, each pixel is 2 bytes in little-endian format
    let bytes_per_pixel = 2usize;
    let mut downsampled = vec![0u16; (new_width * new_height) as usize];

    for y in 0..new_height {
        for x in 0..new_width {
            let src_x = (x as f32 / scale) as u32;
            let src_y = (y as f32 / scale) as u32;
            let src_pixel_idx = (src_y * image.width + src_x) as usize;
            let src_byte_idx = src_pixel_idx * bytes_per_pixel;
            let dst_idx = (y * new_width + x) as usize;

            // Read u16 from byte array (little-endian)
            if src_byte_idx + 1 < image.data.len() {
                let lo = image.data[src_byte_idx] as u16;
                let hi = image.data[src_byte_idx + 1] as u16;
                downsampled[dst_idx] = lo | (hi << 8);
            }
        }
    }

    ImageData::from_u16(new_width, new_height, 1, &downsampled)
}

fn encode_jpeg(data: &[u8], width: u32, height: u32) -> Result<Vec<u8>, String> {
    use image::{ImageBuffer, ImageEncoder, Luma};

    let img_buffer = ImageBuffer::<Luma<u8>, _>::from_raw(width, height, data.to_vec())
        .ok_or_else(|| "Failed to create image buffer".to_string())?;

    let mut jpeg_data = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut jpeg_data);
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
        encoder
            .write_image(img_buffer.as_raw(), width, height, image::ColorType::L8)
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
    }

    Ok(jpeg_data)
}
