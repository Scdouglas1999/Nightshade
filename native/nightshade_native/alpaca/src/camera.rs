//! Alpaca Camera API implementation

use crate::{
    AlpacaClient, AlpacaClientBuilder, AlpacaDevice, AlpacaDeviceType, AlpacaError, RetryConfig,
    TimeoutConfig,
};
use std::time::Duration;

/// Camera state enum matching ASCOM CameraState
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CameraState {
    Idle = 0,
    Waiting = 1,
    Exposing = 2,
    Reading = 3,
    Download = 4,
    Error = 5,
}

impl From<i32> for CameraState {
    fn from(value: i32) -> Self {
        match value {
            0 => CameraState::Idle,
            1 => CameraState::Waiting,
            2 => CameraState::Exposing,
            3 => CameraState::Reading,
            4 => CameraState::Download,
            _ => CameraState::Error,
        }
    }
}

impl std::fmt::Display for CameraState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CameraState::Idle => write!(f, "Idle"),
            CameraState::Waiting => write!(f, "Waiting"),
            CameraState::Exposing => write!(f, "Exposing"),
            CameraState::Reading => write!(f, "Reading"),
            CameraState::Download => write!(f, "Downloading"),
            CameraState::Error => write!(f, "Error"),
        }
    }
}

/// Sensor type enum matching ASCOM SensorType
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensorType {
    Monochrome = 0,
    Color = 1,
    RGGB = 2,
    CMYG = 3,
    CMYG2 = 4,
    LRGB = 5,
}

impl From<i32> for SensorType {
    fn from(value: i32) -> Self {
        match value {
            0 => SensorType::Monochrome,
            1 => SensorType::Color,
            2 => SensorType::RGGB,
            3 => SensorType::CMYG,
            4 => SensorType::CMYG2,
            5 => SensorType::LRGB,
            _ => SensorType::Monochrome,
        }
    }
}

/// Camera status aggregate for parallel status query
#[derive(Debug, Clone)]
pub struct CameraStatus {
    pub state: CameraState,
    pub connected: bool,
    pub image_ready: bool,
    pub percent_completed: Option<i32>,
    pub ccd_temperature: Option<f64>,
    pub cooler_on: Option<bool>,
    pub cooler_power: Option<f64>,
    pub bin_x: i32,
    pub bin_y: i32,
}

/// Camera capabilities for determining what features are available
#[derive(Debug, Clone)]
pub struct CameraCapabilities {
    pub can_abort_exposure: bool,
    pub can_stop_exposure: bool,
    pub can_asymmetric_bin: bool,
    pub can_pulse_guide: bool,
    pub can_fast_readout: bool,
    pub can_set_ccd_temperature: bool,
    pub can_get_cooler_power: bool,
    pub has_shutter: bool,
    pub max_bin_x: i32,
    pub max_bin_y: i32,
}

/// Camera sensor information
#[derive(Debug, Clone)]
pub struct CameraSensorInfo {
    pub camera_x_size: i32,
    pub camera_y_size: i32,
    pub pixel_size_x: f64,
    pub pixel_size_y: f64,
    pub max_adu: i32,
    pub sensor_type: SensorType,
    pub sensor_name: String,
    pub bayer_offset_x: Option<i32>,
    pub bayer_offset_y: Option<i32>,
}

/// Camera subframe settings
#[derive(Debug, Clone)]
pub struct CameraSubframe {
    pub start_x: i32,
    pub start_y: i32,
    pub num_x: i32,
    pub num_y: i32,
}

/// Comprehensive camera status aggregate for parallel status query
/// Includes all status, gain/offset, binning, and subframe in a single query
#[derive(Debug, Clone)]
pub struct CameraFullStatus {
    // Core state
    pub state: CameraState,
    pub connected: bool,
    pub image_ready: bool,
    pub percent_completed: Option<i32>,
    // Temperature/cooling
    pub ccd_temperature: Option<f64>,
    pub cooler_on: Option<bool>,
    pub cooler_power: Option<f64>,
    pub heat_sink_temperature: Option<f64>,
    // Gain and offset
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    // Binning
    pub bin_x: i32,
    pub bin_y: i32,
    // Subframe
    pub start_x: i32,
    pub start_y: i32,
    pub num_x: i32,
    pub num_y: i32,
}

/// Alpaca image-array element types as carried in the JSON `Type` field.
///
/// Why §5.3: previously the loop ignored `Type` entirely and assumed the JSON
/// number could be coerced to `i64` or `f64` — which silently zero-filled on
/// any unexpected token. We now branch on `Type` so the parser knows whether a
/// fractional pixel is legitimate (Double/Single) or a corruption signal
/// (any integer Type).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageArrayElementType {
    /// Type 0 - server omitted/unknown
    Unknown = 0,
    /// Type 1 - Int16
    Int16 = 1,
    /// Type 2 - Int32
    Int32 = 2,
    /// Type 3 - Double
    Double = 3,
    /// Type 4 - Single (float32)
    Single = 4,
    /// Type 5 - UInt64
    UInt64 = 5,
    /// Type 6 - Byte (UInt8)
    Byte = 6,
    /// Type 7 - Int64
    Int64 = 7,
    /// Type 8 - UInt16
    UInt16 = 8,
}

impl ImageArrayElementType {
    fn from_i64(v: i64) -> Self {
        match v {
            0 => Self::Unknown,
            1 => Self::Int16,
            2 => Self::Int32,
            3 => Self::Double,
            4 => Self::Single,
            5 => Self::UInt64,
            6 => Self::Byte,
            7 => Self::Int64,
            8 => Self::UInt16,
            // Why: an unknown Type is a deliberate hard fail — see
            // `parse_image_array_json` which converts this branch to
            // `AlpacaError::UnsupportedImageArray`.
            _ => Self::Unknown,
        }
    }

    fn is_floating(self) -> bool {
        matches!(self, Self::Double | Self::Single)
    }
}

/// Result of a successful Alpaca image-array download.
///
/// `pixels` is laid out **planar**: `[plane_0_pixels..., plane_1_pixels..., ...]`,
/// each plane stored row-major (`y * width + x`). For rank-2 monochrome,
/// `planes == 1` and the layout is identical to the historical `Vec<u16>`
/// produced by `download_image_data_typed`.
#[derive(Debug, Clone)]
pub struct ImageArrayResult {
    pub width: u32,
    pub height: u32,
    pub planes: u32,
    pub pixels: Vec<u16>,
    pub element_type: ImageArrayElementType,
}

/// Alpaca Camera client
pub struct AlpacaCamera {
    client: AlpacaClient,
}

impl AlpacaCamera {
    /// Create a new Alpaca camera client
    pub fn new(device: &AlpacaDevice) -> Self {
        assert_eq!(device.device_type, AlpacaDeviceType::Camera);
        Self {
            client: AlpacaClient::new(device),
        }
    }

    /// Create a camera client with custom configuration
    pub fn with_config(
        device: &AlpacaDevice,
        timeout_config: TimeoutConfig,
        retry_config: RetryConfig,
    ) -> Self {
        assert_eq!(device.device_type, AlpacaDeviceType::Camera);
        Self {
            client: AlpacaClient::with_config(device, timeout_config, retry_config),
        }
    }

    /// Create from server details
    pub fn from_server(base_url: &str, device_number: u32) -> Self {
        let device = AlpacaDevice {
            device_type: AlpacaDeviceType::Camera,
            device_number,
            server_name: String::new(),
            manufacturer: String::new(),
            device_name: String::new(),
            unique_id: String::new(),
            base_url: base_url.to_string(),
        };
        Self::new(&device)
    }

    /// Create a builder for custom configuration
    pub fn builder(device: AlpacaDevice) -> AlpacaClientBuilder {
        AlpacaClientBuilder::new(device)
    }

    /// Get access to the underlying client
    pub fn client(&self) -> &AlpacaClient {
        &self.client
    }

    /// Get the base URL for this device
    pub fn base_url(&self) -> &str {
        self.client.base_url()
    }

    /// Get the device number for this device
    pub fn device_number(&self) -> u32 {
        self.client.device_number()
    }

    // Connection methods

    pub async fn connect(&self) -> Result<(), String> {
        self.client.connect().await
    }

    pub async fn disconnect(&self) -> Result<(), String> {
        self.client.disconnect().await
    }

    pub async fn is_connected(&self) -> Result<bool, String> {
        self.client.is_connected().await
    }

    /// Validate connection is alive
    pub async fn validate_connection(&self) -> Result<bool, AlpacaError> {
        self.client.validate_connection().await
    }

    /// Send heartbeat and get round-trip time
    pub async fn heartbeat(&self) -> Result<u64, AlpacaError> {
        self.client.heartbeat().await
    }

    // Camera information

    pub async fn name(&self) -> Result<String, String> {
        self.client.get_name().await
    }

    pub async fn description(&self) -> Result<String, String> {
        self.client.get_description().await
    }

    /// Get the driver version string
    pub async fn driver_version(&self) -> Result<String, String> {
        self.client.get_driver_version().await
    }

    /// Get the driver info string
    pub async fn driver_info(&self) -> Result<String, String> {
        self.client.get_driver_info().await
    }

    /// Get the interface version number
    pub async fn interface_version(&self) -> Result<i32, String> {
        self.client.get_interface_version().await
    }

    /// Get the list of supported custom actions
    pub async fn supported_actions(&self) -> Result<Vec<String>, String> {
        self.client.get_supported_actions().await
    }

    pub async fn camera_x_size(&self) -> Result<i32, String> {
        self.client.get("cameraxsize").await
    }

    pub async fn camera_y_size(&self) -> Result<i32, String> {
        self.client.get("cameraysize").await
    }

    pub async fn pixel_size_x(&self) -> Result<f64, String> {
        self.client.get("pixelsizex").await
    }

    pub async fn pixel_size_y(&self) -> Result<f64, String> {
        self.client.get("pixelsizey").await
    }

    pub async fn max_adu(&self) -> Result<i32, String> {
        self.client.get("maxadu").await
    }

    pub async fn sensor_type(&self) -> Result<i32, String> {
        self.client.get("sensortype").await
    }

    pub async fn sensor_name(&self) -> Result<String, String> {
        self.client.get("sensorname").await
    }

    // Binning

    pub async fn max_bin_x(&self) -> Result<i32, String> {
        self.client.get("maxbinx").await
    }

    pub async fn max_bin_y(&self) -> Result<i32, String> {
        self.client.get("maxbiny").await
    }

    pub async fn bin_x(&self) -> Result<i32, String> {
        self.client.get("binx").await
    }

    pub async fn bin_y(&self) -> Result<i32, String> {
        self.client.get("biny").await
    }

    pub async fn set_bin_x(&self, value: i32) -> Result<(), String> {
        self.client
            .put("binx", &[("BinX", &value.to_string())])
            .await
    }

    pub async fn set_bin_y(&self, value: i32) -> Result<(), String> {
        self.client
            .put("biny", &[("BinY", &value.to_string())])
            .await
    }

    // Cooling

    pub async fn can_set_ccd_temperature(&self) -> Result<bool, String> {
        self.client.get("cansetccdtemperature").await
    }

    pub async fn ccd_temperature(&self) -> Result<f64, String> {
        self.client.get("ccdtemperature").await
    }

    pub async fn set_ccd_temperature(&self, temp: f64) -> Result<(), String> {
        self.client
            .put(
                "setccdtemperature",
                &[("SetCCDTemperature", &temp.to_string())],
            )
            .await
    }

    pub async fn cooler_on(&self) -> Result<bool, String> {
        self.client.get("cooleron").await
    }

    pub async fn set_cooler_on(&self, on: bool) -> Result<(), String> {
        self.client
            .put("cooleron", &[("CoolerOn", &on.to_string())])
            .await
    }

    pub async fn cooler_power(&self) -> Result<f64, String> {
        self.client.get("coolerpower").await
    }

    pub async fn heat_sink_temperature(&self) -> Result<f64, String> {
        self.client.get("heatsinktemperature").await
    }

    // Gain and offset

    pub async fn can_get_cooler_power(&self) -> Result<bool, String> {
        self.client.get("cangetcoolerpower").await
    }

    pub async fn gain(&self) -> Result<i32, String> {
        self.client.get("gain").await
    }

    pub async fn set_gain(&self, gain: i32) -> Result<(), String> {
        self.client
            .put("gain", &[("Gain", &gain.to_string())])
            .await
    }

    pub async fn gain_min(&self) -> Result<i32, String> {
        self.client.get("gainmin").await
    }

    pub async fn gain_max(&self) -> Result<i32, String> {
        self.client.get("gainmax").await
    }

    pub async fn offset(&self) -> Result<i32, String> {
        self.client.get("offset").await
    }

    pub async fn set_offset(&self, offset: i32) -> Result<(), String> {
        self.client
            .put("offset", &[("Offset", &offset.to_string())])
            .await
    }

    pub async fn offset_min(&self) -> Result<i32, String> {
        self.client.get("offsetmin").await
    }

    pub async fn offset_max(&self) -> Result<i32, String> {
        self.client.get("offsetmax").await
    }

    pub async fn bayer_offset_x(&self) -> Result<i32, String> {
        self.client.get("bayeroffsetx").await
    }

    pub async fn bayer_offset_y(&self) -> Result<i32, String> {
        self.client.get("bayeroffsety").await
    }

    // Exposure state

    pub async fn camera_state(&self) -> Result<CameraState, String> {
        let state: i32 = self.client.get("camerastate").await?;
        Ok(CameraState::from(state))
    }

    pub async fn image_ready(&self) -> Result<bool, String> {
        self.client.get("imageready").await
    }

    pub async fn is_pulse_guiding(&self) -> Result<bool, String> {
        self.client.get("ispulseguiding").await
    }

    pub async fn percent_completed(&self) -> Result<i32, String> {
        self.client.get("percentcompleted").await
    }

    // Exposure control

    pub async fn start_exposure(&self, duration: f64, light: bool) -> Result<(), String> {
        self.client
            .put(
                "startexposure",
                &[
                    ("Duration", &duration.to_string()),
                    ("Light", &light.to_string()),
                ],
            )
            .await
    }

    pub async fn abort_exposure(&self) -> Result<(), String> {
        self.client.put("abortexposure", &[]).await
    }

    pub async fn stop_exposure(&self) -> Result<(), String> {
        self.client.put("stopexposure", &[]).await
    }

    // Readout mode

    pub async fn readout_mode(&self) -> Result<i32, String> {
        self.client.get("readoutmode").await
    }

    pub async fn set_readout_mode(&self, mode: i32) -> Result<(), String> {
        self.client
            .put("readoutmode", &[("ReadoutMode", &mode.to_string())])
            .await
    }

    pub async fn readout_modes(&self) -> Result<Vec<String>, String> {
        self.client.get("readoutmodes").await
    }

    // Subframe

    pub async fn start_x(&self) -> Result<i32, String> {
        self.client.get("startx").await
    }

    pub async fn start_y(&self) -> Result<i32, String> {
        self.client.get("starty").await
    }

    pub async fn num_x(&self) -> Result<i32, String> {
        self.client.get("numx").await
    }

    pub async fn num_y(&self) -> Result<i32, String> {
        self.client.get("numy").await
    }

    pub async fn set_start_x(&self, value: i32) -> Result<(), String> {
        self.client
            .put("startx", &[("StartX", &value.to_string())])
            .await
    }

    pub async fn set_start_y(&self, value: i32) -> Result<(), String> {
        self.client
            .put("starty", &[("StartY", &value.to_string())])
            .await
    }

    pub async fn set_num_x(&self, value: i32) -> Result<(), String> {
        self.client
            .put("numx", &[("NumX", &value.to_string())])
            .await
    }

    pub async fn set_num_y(&self, value: i32) -> Result<(), String> {
        self.client
            .put("numy", &[("NumY", &value.to_string())])
            .await
    }

    // Last exposure info

    pub async fn last_exposure_start_time(&self) -> Result<String, String> {
        self.client.get("lastexposurestarttime").await
    }

    pub async fn last_exposure_duration(&self) -> Result<f64, String> {
        self.client.get("lastexposureduration").await
    }

    // Capabilities

    pub async fn can_abort_exposure(&self) -> Result<bool, String> {
        self.client.get("canabortexposure").await
    }

    pub async fn can_stop_exposure(&self) -> Result<bool, String> {
        self.client.get("canstopexposure").await
    }

    pub async fn can_asymmetric_bin(&self) -> Result<bool, String> {
        self.client.get("canasymmetricbin").await
    }

    pub async fn can_pulse_guide(&self) -> Result<bool, String> {
        self.client.get("canpulseguide").await
    }

    pub async fn can_fast_readout(&self) -> Result<bool, String> {
        self.client.get("canfastreadout").await
    }

    pub async fn has_shutter(&self) -> Result<bool, String> {
        self.client.get("hasshutter").await
    }

    // Image retrieval - returns 2D array of pixel values
    // The Alpaca imagearray endpoint returns a JSON object with:
    // - Value: 2D/3D array of i32 pixel values
    // - Type: data type (1=Int16, 2=Int32, 3=Double, etc.)
    // - Rank: 2 for mono, 3 for color
    pub async fn image_array(&self) -> Result<String, String> {
        self.client.get("imagearray").await
    }

    /// Download image as parsed pixel data
    /// Returns (width, height, data as u16 vec)
    /// Uses very long timeout (configurable, defaults to 15 minutes for large images)
    pub async fn download_image_data(&self) -> Result<(u32, u32, Vec<u16>), String> {
        self.download_image_data_typed()
            .await
            .map_err(|e| e.to_string())
    }

    /// Download image with typed error handling.
    ///
    /// Returns `(width, height, pixels)` for **rank 2 (monochrome)** Alpaca
    /// image arrays only. For rank-3 color frames the function fails fast with
    /// `AlpacaError::ColorImageUnsupported` so callers cannot silently lose the
    /// channel dimension; use [`download_image_array_full_typed`] for those.
    ///
    /// Why §5.3: previously any pixel that failed `as_i64`/`as_f64` was
    /// substituted with `0`, corrupting whole frames on any JSON anomaly. We
    /// now propagate `AlpacaError::PixelParseError` with the exact offset and
    /// offending JSON token. Rank 3 used to be flattened silently; we now
    /// reject it explicitly until a multi-plane consumer lands.
    ///
    /// Why §5.12: this used to build a fresh `reqwest::Client` per image; we
    /// now reuse the pooled client from `AlpacaClient::http_client()` and set
    /// the per-request timeout via `RequestBuilder::timeout(...)`.
    pub async fn download_image_data_typed(&self) -> Result<(u32, u32, Vec<u16>), AlpacaError> {
        let result = self.download_image_array_full_typed().await?;

        if result.planes != 1 {
            return Err(AlpacaError::ColorImageUnsupported {
                width: result.width,
                height: result.height,
                planes: result.planes,
            });
        }

        Ok((result.width, result.height, result.pixels))
    }

    /// Download image preserving the channel dimension (rank 2 OR rank 3).
    ///
    /// Why §5.3: callers that genuinely want color image arrays need access to
    /// the third dimension. Pixels are returned in **planar** order — all of
    /// plane 0, then all of plane 1, etc. — matching the on-the-wire Alpaca
    /// shape `[NumX][NumY][NumPlanes]` after the Y-then-X iteration order.
    pub async fn download_image_array_full_typed(&self) -> Result<ImageArrayResult, AlpacaError> {
        // Why: subframe geometry tells us the expected shape; we cross-check
        // the parsed array against this so a server that reports inconsistent
        // sizes can't slip past as a partially-filled frame.
        let width = self.num_x().await.map_err(AlpacaError::OperationFailed)? as u32;
        let height = self.num_y().await.map_err(AlpacaError::OperationFailed)? as u32;

        // Why: at minimum 10MB/s network speed plus extra margin; the configured
        // very-long timeout (camera preset = 15 min) covers a 24 MP frame in
        // the worst-case JSON-encoded path.
        let timeout_ms = self.client.timeout_config().very_long_operation_ms;

        let (client_id, transaction_id) = crate::client::get_client_transaction();
        let url = format!(
            "{}?ClientID={}&ClientTransactionID={}",
            self.client.build_url("imagearray"),
            client_id,
            transaction_id
        );

        // Why §5.12: reuse the pooled HTTP client so successive frames share
        // the keep-alive connection; only override the timeout per request.
        let http_client = self.client.http_client()?;

        // Why: estimate is for the timeout-error message, not for allocation.
        let estimated_bytes = (width as u64) * (height as u64) * 2 * 3;

        let response = http_client
            .get(&url)
            .timeout(Duration::from_millis(timeout_ms))
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    AlpacaError::timeout(
                        format!(
                            "imagearray download ({}x{}, ~{} MB)",
                            width,
                            height,
                            estimated_bytes / 1_000_000
                        ),
                        timeout_ms,
                    )
                } else {
                    AlpacaError::from(e)
                }
            })?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(AlpacaError::HttpError {
                status: status.as_u16(),
                message: body,
            });
        }

        let response_text = response.text().await.map_err(|e| {
            AlpacaError::RequestFailed(format!("Failed to read image array response: {}", e))
        })?;

        parse_image_array_json(&response_text, width, height)
    }

    /// Wait for image to be ready with configurable timeout
    /// Polls image_ready until true or timeout expires
    pub async fn wait_for_image_ready(
        &self,
        poll_interval: Duration,
        timeout: Duration,
    ) -> Result<bool, AlpacaError> {
        let deadline = std::time::Instant::now() + timeout;

        loop {
            match self.image_ready().await {
                Ok(true) => return Ok(true),
                Ok(false) => {
                    if std::time::Instant::now() >= deadline {
                        return Ok(false);
                    }
                    tokio::time::sleep(poll_interval).await;
                }
                Err(e) => return Err(AlpacaError::OperationFailed(e)),
            }
        }
    }

    /// Wait for camera to become idle with configurable timeout
    pub async fn wait_for_idle(
        &self,
        poll_interval: Duration,
        timeout: Duration,
    ) -> Result<bool, AlpacaError> {
        let deadline = std::time::Instant::now() + timeout;

        loop {
            match self.camera_state().await {
                Ok(CameraState::Idle) => return Ok(true),
                Ok(CameraState::Error) => {
                    return Err(AlpacaError::OperationFailed(
                        "Camera in error state".to_string(),
                    ))
                }
                Ok(_) => {
                    if std::time::Instant::now() >= deadline {
                        return Ok(false);
                    }
                    tokio::time::sleep(poll_interval).await;
                }
                Err(e) => return Err(AlpacaError::OperationFailed(e)),
            }
        }
    }

    /// Pulse guide in a direction
    pub async fn pulse_guide(&self, direction: i32, duration_ms: i32) -> Result<(), String> {
        self.client
            .put(
                "pulseguide",
                &[
                    ("Direction", &direction.to_string()),
                    ("Duration", &duration_ms.to_string()),
                ],
            )
            .await
    }

    // Parallel status methods

    /// Get comprehensive camera status in a single parallel query
    pub async fn get_status(&self) -> Result<CameraStatus, String> {
        let (
            state,
            connected,
            image_ready,
            percent_completed,
            ccd_temperature,
            cooler_on,
            cooler_power,
            bin_x,
            bin_y,
        ) = tokio::join!(
            self.camera_state(),
            self.is_connected(),
            self.image_ready(),
            self.percent_completed(),
            self.ccd_temperature(),
            self.cooler_on(),
            self.cooler_power(),
            self.bin_x(),
            self.bin_y(),
        );

        Ok(CameraStatus {
            state: state?,
            connected: connected?,
            image_ready: image_ready?,
            percent_completed: percent_completed.ok(),
            ccd_temperature: ccd_temperature.ok(),
            cooler_on: cooler_on.ok(),
            cooler_power: cooler_power.ok(),
            bin_x: bin_x?,
            bin_y: bin_y?,
        })
    }

    /// Get camera capabilities in a single parallel query
    pub async fn get_capabilities(&self) -> Result<CameraCapabilities, String> {
        let (
            can_abort_exposure,
            can_stop_exposure,
            can_asymmetric_bin,
            can_pulse_guide,
            can_fast_readout,
            can_set_ccd_temperature,
            can_get_cooler_power,
            has_shutter,
            max_bin_x,
            max_bin_y,
        ) = tokio::join!(
            self.can_abort_exposure(),
            self.can_stop_exposure(),
            self.can_asymmetric_bin(),
            self.can_pulse_guide(),
            self.can_fast_readout(),
            self.can_set_ccd_temperature(),
            self.can_get_cooler_power(),
            self.has_shutter(),
            self.max_bin_x(),
            self.max_bin_y(),
        );

        Ok(CameraCapabilities {
            can_abort_exposure: can_abort_exposure?,
            can_stop_exposure: can_stop_exposure?,
            can_asymmetric_bin: can_asymmetric_bin?,
            can_pulse_guide: can_pulse_guide?,
            can_fast_readout: can_fast_readout?,
            can_set_ccd_temperature: can_set_ccd_temperature?,
            can_get_cooler_power: can_get_cooler_power?,
            has_shutter: has_shutter?,
            max_bin_x: max_bin_x?,
            max_bin_y: max_bin_y?,
        })
    }

    /// Get camera sensor information in a single parallel query
    pub async fn get_sensor_info(&self) -> Result<CameraSensorInfo, String> {
        let (
            camera_x_size,
            camera_y_size,
            pixel_size_x,
            pixel_size_y,
            max_adu,
            sensor_type,
            sensor_name,
            bayer_offset_x,
            bayer_offset_y,
        ) = tokio::join!(
            self.camera_x_size(),
            self.camera_y_size(),
            self.pixel_size_x(),
            self.pixel_size_y(),
            self.max_adu(),
            self.sensor_type(),
            self.sensor_name(),
            self.bayer_offset_x(),
            self.bayer_offset_y(),
        );

        Ok(CameraSensorInfo {
            camera_x_size: camera_x_size?,
            camera_y_size: camera_y_size?,
            pixel_size_x: pixel_size_x?,
            pixel_size_y: pixel_size_y?,
            max_adu: max_adu?,
            sensor_type: SensorType::from(sensor_type?),
            sensor_name: sensor_name?,
            bayer_offset_x: bayer_offset_x.ok(),
            bayer_offset_y: bayer_offset_y.ok(),
        })
    }

    /// Get camera subframe settings in a single parallel query
    pub async fn get_subframe(&self) -> Result<CameraSubframe, String> {
        let (start_x, start_y, num_x, num_y) =
            tokio::join!(self.start_x(), self.start_y(), self.num_x(), self.num_y(),);

        Ok(CameraSubframe {
            start_x: start_x?,
            start_y: start_y?,
            num_x: num_x?,
            num_y: num_y?,
        })
    }

    /// Get comprehensive camera status in a single parallel query
    /// This includes state, temperature, cooling, gain/offset, binning, and subframe
    /// Use this for efficient status polling instead of making multiple individual calls
    pub async fn get_full_status(&self) -> Result<CameraFullStatus, String> {
        // Query all status properties in parallel for maximum efficiency
        // This reduces the number of network round-trips from ~16 to 1
        let (
            state,
            connected,
            image_ready,
            percent_completed,
            ccd_temperature,
            cooler_on,
            cooler_power,
            heat_sink_temperature,
            gain,
            offset,
            bin_x,
            bin_y,
            start_x,
            start_y,
            num_x,
            num_y,
        ) = tokio::join!(
            self.camera_state(),
            self.is_connected(),
            self.image_ready(),
            self.percent_completed(),
            self.ccd_temperature(),
            self.cooler_on(),
            self.cooler_power(),
            self.heat_sink_temperature(),
            self.gain(),
            self.offset(),
            self.bin_x(),
            self.bin_y(),
            self.start_x(),
            self.start_y(),
            self.num_x(),
            self.num_y(),
        );

        Ok(CameraFullStatus {
            // Core state - these are critical and should propagate errors
            state: state?,
            connected: connected?,
            image_ready: image_ready?,
            percent_completed: percent_completed.ok(),
            // Temperature/cooling - may not be available on all cameras
            ccd_temperature: ccd_temperature.ok(),
            cooler_on: cooler_on.ok(),
            cooler_power: cooler_power.ok(),
            heat_sink_temperature: heat_sink_temperature.ok(),
            // Gain and offset - may not be available on all cameras
            gain: gain.ok(),
            offset: offset.ok(),
            // Binning - critical settings
            bin_x: bin_x?,
            bin_y: bin_y?,
            // Subframe - critical settings
            start_x: start_x?,
            start_y: start_y?,
            num_x: num_x?,
            num_y: num_y?,
        })
    }
}

// -----------------------------------------------------------------------------
// Image-array JSON parser (§5.3)
// -----------------------------------------------------------------------------

/// Parse an Alpaca `imagearray` JSON response into `ImageArrayResult`.
///
/// Why this is a free function (not a method): isolating the pure parser
/// makes §5.3 directly unit-testable without spinning up an HTTP server.
///
/// # Error semantics
///
/// * Any pixel that is not a JSON number — or, for an integer `Type`, a
///   fractional number — yields `AlpacaError::PixelParseError` carrying the
///   linear pixel offset and the offending JSON token. **No silent
///   zero-substitution** (the bug the audit calls out).
/// * Unknown `Type` or unsupported `(Rank, Type)` combinations yield
///   `AlpacaError::UnsupportedImageArray` instead of guessing.
/// * Mismatched array shape vs. `(width, height)` is `AlpacaError::ParseError`.
pub(crate) fn parse_image_array_json(
    body: &str,
    width: u32,
    height: u32,
) -> Result<ImageArrayResult, AlpacaError> {
    let json: serde_json::Value = serde_json::from_str(body)
        .map_err(|e| AlpacaError::ParseError(format!("Failed to parse image array JSON: {}", e)))?;

    // Why: surface device-reported errors before attempting to parse Value;
    // the array may be absent or junk when ErrorNumber != 0.
    if let Some(error_num) = json.get("ErrorNumber").and_then(|v| v.as_i64()) {
        if error_num != 0 {
            let error_msg = json
                .get("ErrorMessage")
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown error")
                .to_string();
            return Err(AlpacaError::DeviceError {
                code: error_num as i32,
                message: error_msg,
            });
        }
    }

    // Why: Type/Rank are required for §5.3 dispatch. The Alpaca spec mandates
    // them; a missing field is a server bug we should report, not paper over.
    let element_type_raw = json
        .get("Type")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| AlpacaError::ParseError("Missing or non-integer Type field".to_string()))?;
    let element_type = ImageArrayElementType::from_i64(element_type_raw);
    if matches!(element_type, ImageArrayElementType::Unknown) {
        return Err(AlpacaError::UnsupportedImageArray {
            rank: json.get("Rank").and_then(|v| v.as_i64()).unwrap_or(0),
            image_type: element_type_raw,
            reason: format!("unrecognised Type {}", element_type_raw),
        });
    }

    let rank = json
        .get("Rank")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| AlpacaError::ParseError("Missing or non-integer Rank field".to_string()))?;

    let value = json.get("Value").ok_or_else(|| {
        AlpacaError::ParseError("Missing Value field in image array response".to_string())
    })?;

    let outer = value
        .as_array()
        .ok_or_else(|| AlpacaError::ParseError("Image array Value is not an array".to_string()))?;

    match rank {
        2 => parse_rank2(outer, element_type, width, height),
        3 => parse_rank3(outer, element_type, width, height),
        other => Err(AlpacaError::UnsupportedImageArray {
            rank: other,
            image_type: element_type_raw,
            reason: "only rank 2 (mono) and rank 3 (color) are supported".to_string(),
        }),
    }
}

/// Parse a `[NumX][NumY]` rank-2 image into a single-plane `ImageArrayResult`.
fn parse_rank2(
    outer: &[serde_json::Value],
    element_type: ImageArrayElementType,
    width: u32,
    height: u32,
) -> Result<ImageArrayResult, AlpacaError> {
    let expected = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| AlpacaError::ParseError("width*height overflow".to_string()))?;
    let mut pixels: Vec<u16> = Vec::with_capacity(expected);

    // Alpaca rank-2 layout is [NumX][NumY] (column-major). We iterate the
    // outer (X) dimension then the inner (Y) dimension; the resulting flat
    // vector is column-major in (x, y) — identical to the historical layout
    // produced by the buggy loop, so existing consumers keep working.
    let mut offset: usize = 0;
    for inner in outer.iter() {
        let inner_arr = inner.as_array().ok_or_else(|| {
            AlpacaError::ParseError(format!(
                "Image array row at offset {} is not an array",
                offset
            ))
        })?;
        for pixel in inner_arr.iter() {
            let v = decode_pixel(pixel, element_type, offset)?;
            pixels.push(v);
            offset += 1;
        }
    }

    if pixels.len() != expected {
        return Err(AlpacaError::ParseError(format!(
            "Image size mismatch: expected {} pixels ({}x{}), got {}",
            expected,
            width,
            height,
            pixels.len()
        )));
    }

    Ok(ImageArrayResult {
        width,
        height,
        planes: 1,
        pixels,
        element_type,
    })
}

/// Parse a `[NumX][NumY][NumPlanes]` rank-3 image into a planar
/// `ImageArrayResult`.
///
/// Why planar (not interleaved): keeps each channel a contiguous slice for
/// downstream debayer/demosaic consumers, and matches what the Alpaca spec
/// stores on the wire when `NumPlanes` is the innermost dimension.
fn parse_rank3(
    outer: &[serde_json::Value],
    element_type: ImageArrayElementType,
    width: u32,
    height: u32,
) -> Result<ImageArrayResult, AlpacaError> {
    if outer.is_empty() {
        return Err(AlpacaError::ParseError(
            "Rank-3 image array has zero columns".to_string(),
        ));
    }

    // Why: detect planes from the first innermost array; we validate every
    // pixel matches this width to catch truncation/corruption.
    let first_col = outer[0]
        .as_array()
        .ok_or_else(|| AlpacaError::ParseError("Rank-3 outer[0] is not an array".to_string()))?;
    if first_col.is_empty() {
        return Err(AlpacaError::ParseError(
            "Rank-3 image array has zero rows".to_string(),
        ));
    }
    let first_pixel = first_col[0]
        .as_array()
        .ok_or_else(|| AlpacaError::ParseError("Rank-3 outer[0][0] is not an array".to_string()))?;
    let planes = first_pixel.len() as u32;
    if planes == 0 {
        return Err(AlpacaError::ParseError(
            "Rank-3 image array has zero planes".to_string(),
        ));
    }

    // Why: scratch buffer in column-major (x, y) order per plane; we transpose
    // to planar at the end so each plane is contiguous.
    let pixels_per_plane = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| AlpacaError::ParseError("width*height overflow".to_string()))?;
    let total = pixels_per_plane
        .checked_mul(planes as usize)
        .ok_or_else(|| AlpacaError::ParseError("width*height*planes overflow".to_string()))?;
    let mut planar: Vec<u16> = vec![0u16; total];

    let mut linear: usize = 0;
    for (xi, inner) in outer.iter().enumerate() {
        let inner_arr = inner.as_array().ok_or_else(|| {
            AlpacaError::ParseError(format!("Rank-3 outer[{}] is not an array", xi))
        })?;
        for (yi, pix) in inner_arr.iter().enumerate() {
            let pix_arr = pix.as_array().ok_or_else(|| {
                AlpacaError::ParseError(format!(
                    "Rank-3 outer[{}][{}] pixel is not an array",
                    xi, yi
                ))
            })?;
            if pix_arr.len() as u32 != planes {
                return Err(AlpacaError::ParseError(format!(
                    "Rank-3 plane-count mismatch at ({},{}): expected {}, got {}",
                    xi,
                    yi,
                    planes,
                    pix_arr.len()
                )));
            }
            for (pi, channel) in pix_arr.iter().enumerate() {
                let v = decode_pixel(channel, element_type, linear)?;
                // Place into planar layout: plane pi, then column-major (xi, yi)
                let dest = (pi * pixels_per_plane) + (xi * (height as usize)) + yi;
                planar[dest] = v;
                linear += 1;
            }
        }
    }

    // Why: cross-check geometry; mismatched array dimensions vs. NumX/NumY
    // would silently produce a partially-zero plane otherwise.
    let expected_linear = pixels_per_plane.saturating_mul(planes as usize);
    if linear != expected_linear {
        return Err(AlpacaError::ParseError(format!(
            "Rank-3 image size mismatch: expected {} pixels ({}x{}x{}), got {}",
            expected_linear, width, height, planes, linear
        )));
    }

    Ok(ImageArrayResult {
        width,
        height,
        planes,
        pixels: planar,
        element_type,
    })
}

/// Decode a single JSON pixel into `u16`, dispatching on `element_type`.
///
/// Why this function exists: §5.3 mandates that we **never** silently turn an
/// unparseable JSON token into `0`. Every failure path here returns a
/// `PixelParseError` carrying enough context to find the bad pixel.
fn decode_pixel(
    pixel: &serde_json::Value,
    element_type: ImageArrayElementType,
    offset: usize,
) -> Result<u16, AlpacaError> {
    let number = pixel
        .as_number()
        .ok_or_else(|| AlpacaError::PixelParseError {
            offset,
            found: shorten_json(pixel),
            reason: "pixel is not a JSON number".to_string(),
        })?;

    if element_type.is_floating() {
        let f = number
            .as_f64()
            .ok_or_else(|| AlpacaError::PixelParseError {
                offset,
                found: number.to_string(),
                reason: format!("pixel not representable as f64 (Type {:?})", element_type),
            })?;
        if !f.is_finite() {
            return Err(AlpacaError::PixelParseError {
                offset,
                found: number.to_string(),
                reason: "non-finite pixel value (NaN or infinity)".to_string(),
            });
        }
        Ok(clamp_f64_to_u16(f))
    } else {
        // Why: integer Types must arrive as integers — a fractional value is a
        // server bug or wire corruption, not something we should round away.
        let i = number
            .as_i64()
            .ok_or_else(|| AlpacaError::PixelParseError {
                offset,
                found: number.to_string(),
                reason: format!(
                    "pixel not representable as i64 (Type {:?}); fractional or out-of-range",
                    element_type
                ),
            })?;
        Ok(clamp_i64_to_u16(i))
    }
}

/// Clamp a 64-bit signed integer pixel to the `u16` range.
fn clamp_i64_to_u16(v: i64) -> u16 {
    if v < 0 {
        0
    } else if v > u16::MAX as i64 {
        u16::MAX
    } else {
        v as u16
    }
}

/// Round-and-clamp a finite `f64` to `u16`. Caller must reject non-finite.
fn clamp_f64_to_u16(v: f64) -> u16 {
    let r = v.round();
    if r < 0.0 {
        0
    } else if r > u16::MAX as f64 {
        u16::MAX
    } else {
        r as u16
    }
}

/// Truncate a JSON value's string representation for inclusion in an error
/// message; we don't want to drag a 24 MP frame into a panic log.
fn shorten_json(v: &serde_json::Value) -> String {
    let mut s = v.to_string();
    const MAX: usize = 64;
    if s.len() > MAX {
        s.truncate(MAX);
        s.push_str("...");
    }
    s
}

// -----------------------------------------------------------------------------
// Tests (§5.3)
// -----------------------------------------------------------------------------

#[cfg(test)]
mod image_array_tests {
    use super::*;

    fn ok_response(rank: u32, type_code: i64, value: serde_json::Value) -> String {
        serde_json::json!({
            "Rank": rank,
            "Type": type_code,
            "Value": value,
            "ErrorNumber": 0,
            "ErrorMessage": "",
            "ClientTransactionID": 1,
            "ServerTransactionID": 1,
        })
        .to_string()
    }

    #[test]
    fn rank2_int32_parses_clean() {
        // 2x3 image, type 2 (Int32), column-major.
        let body = ok_response(2, 2, serde_json::json!([[1, 2, 3], [4, 5, 6],]));
        let r = parse_image_array_json(&body, 2, 3).expect("rank-2 parse");
        assert_eq!(r.width, 2);
        assert_eq!(r.height, 3);
        assert_eq!(r.planes, 1);
        assert_eq!(r.pixels, vec![1u16, 2, 3, 4, 5, 6]);
        assert_eq!(r.element_type, ImageArrayElementType::Int32);
    }

    #[test]
    fn malformed_pixel_string_yields_pixel_parse_error_not_zero() {
        // A pixel string instead of a number; previously this became 0.
        let body = ok_response(2, 2, serde_json::json!([[1, 2, "oops"], [4, 5, 6],]));
        let err = parse_image_array_json(&body, 2, 3).expect_err("must reject malformed pixel");
        match err {
            AlpacaError::PixelParseError {
                offset,
                found,
                reason,
            } => {
                // Why: offset 2 is the third pixel scanned in column-major order.
                assert_eq!(offset, 2, "offset should pinpoint the bad pixel");
                assert!(found.contains("oops"), "found token should echo input");
                assert!(
                    !reason.is_empty(),
                    "reason should describe why parse failed"
                );
            }
            other => panic!("expected PixelParseError, got {:?}", other),
        }
    }

    #[test]
    fn malformed_pixel_null_yields_pixel_parse_error_not_zero() {
        let body = ok_response(2, 2, serde_json::json!([[1, 2, null], [4, 5, 6],]));
        let err = parse_image_array_json(&body, 2, 3).expect_err("null pixel must error");
        assert!(matches!(err, AlpacaError::PixelParseError { .. }));
    }

    #[test]
    fn fractional_pixel_with_integer_type_errors() {
        // Type 2 = Int32; a fractional value is a server bug, not a rounding
        // opportunity. §5.3 mandates failing closed.
        let body = ok_response(2, 2, serde_json::json!([[1, 2, 3.5], [4, 5, 6],]));
        let err = parse_image_array_json(&body, 2, 3).expect_err("fractional Int32 must error");
        match err {
            AlpacaError::PixelParseError { offset, .. } => assert_eq!(offset, 2),
            other => panic!("expected PixelParseError, got {:?}", other),
        }
    }

    #[test]
    fn fractional_pixel_with_double_type_rounds() {
        // Type 3 = Double; fractional is legitimate and rounds to nearest.
        let body = ok_response(2, 3, serde_json::json!([[1.0, 2.4, 3.6], [4.5, 5.0, 6.0],]));
        let r = parse_image_array_json(&body, 2, 3).expect("Double rank-2 parse");
        // 2.4 -> 2, 3.6 -> 4, 4.5 -> 5 (banker's? no: f64::round() rounds half away from zero -> 5)
        assert_eq!(r.pixels, vec![1u16, 2, 4, 5, 5, 6]);
    }

    #[test]
    fn nan_pixel_with_double_type_errors() {
        // serde_json will encode NaN as null, but a server might serialize it
        // as a string; either way we must NOT silently emit 0.
        let body = ok_response(
            2,
            3,
            serde_json::json!([[1.0, 2.0, "NaN"], [4.0, 5.0, 6.0],]),
        );
        let err = parse_image_array_json(&body, 2, 3).expect_err("NaN must error");
        assert!(matches!(err, AlpacaError::PixelParseError { .. }));
    }

    #[test]
    fn rank3_color_image_preserves_channel_dimension() {
        // 2x2x3 RGB image. Column-major outer (x), then y, then plane.
        // Layout on the wire: outer[x][y][p]
        //   (0,0): [10, 20, 30]
        //   (0,1): [11, 21, 31]
        //   (1,0): [12, 22, 32]
        //   (1,1): [13, 23, 33]
        let body = ok_response(
            3,
            2,
            serde_json::json!([[[10, 20, 30], [11, 21, 31]], [[12, 22, 32], [13, 23, 33]],]),
        );
        let r = parse_image_array_json(&body, 2, 2).expect("rank-3 parse");
        assert_eq!(r.width, 2);
        assert_eq!(r.height, 2);
        assert_eq!(r.planes, 3, "channel dimension must NOT be flattened");
        // Plane 0 (R), planar layout, column-major (x, y): [10, 11, 12, 13]
        // Plane 1 (G):                                   [20, 21, 22, 23]
        // Plane 2 (B):                                   [30, 31, 32, 33]
        assert_eq!(
            r.pixels,
            vec![10u16, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33]
        );
    }

    #[test]
    fn rank3_plane_mismatch_errors() {
        let body = ok_response(
            3,
            2,
            serde_json::json!([
                [[10, 20, 30], [11, 21]], // second pixel only has 2 planes
                [[12, 22, 32], [13, 23, 33]],
            ]),
        );
        let err = parse_image_array_json(&body, 2, 2).expect_err("plane mismatch must error");
        assert!(matches!(err, AlpacaError::ParseError(_)));
    }

    #[test]
    fn unknown_type_errors() {
        let body = ok_response(2, 99, serde_json::json!([[1, 2], [3, 4]]));
        let err = parse_image_array_json(&body, 2, 2).expect_err("unknown type must error");
        match err {
            AlpacaError::UnsupportedImageArray {
                image_type, rank, ..
            } => {
                assert_eq!(image_type, 99);
                assert_eq!(rank, 2);
            }
            other => panic!("expected UnsupportedImageArray, got {:?}", other),
        }
    }

    #[test]
    fn unsupported_rank_errors() {
        let body = ok_response(4, 2, serde_json::json!([]));
        let err = parse_image_array_json(&body, 1, 1).expect_err("rank 4 must error");
        assert!(matches!(
            err,
            AlpacaError::UnsupportedImageArray { rank: 4, .. }
        ));
    }

    #[test]
    fn device_error_propagates() {
        let body = serde_json::json!({
            "Rank": 2,
            "Type": 2,
            "Value": [],
            "ErrorNumber": 1031,
            "ErrorMessage": "Method unavailable",
        })
        .to_string();
        let err = parse_image_array_json(&body, 2, 2).expect_err("device error must propagate");
        match err {
            AlpacaError::DeviceError { code, message } => {
                assert_eq!(code, 1031);
                assert!(message.contains("Method unavailable"));
            }
            other => panic!("expected DeviceError, got {:?}", other),
        }
    }

    #[test]
    fn negative_int_clamps_to_zero() {
        let body = ok_response(2, 2, serde_json::json!([[-5, 0], [70000, 12345]]));
        let r = parse_image_array_json(&body, 2, 2).expect("clamping parse");
        assert_eq!(r.pixels, vec![0u16, 0, u16::MAX, 12345]);
    }

    #[test]
    fn rank2_size_mismatch_errors() {
        // Only 2 pixels supplied for a 2x3 frame.
        let body = ok_response(2, 2, serde_json::json!([[1, 2]]));
        let err = parse_image_array_json(&body, 2, 3).expect_err("size mismatch must error");
        assert!(matches!(err, AlpacaError::ParseError(_)));
    }
}
