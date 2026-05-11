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
    ///
    /// Why §5.13: prefer the binary `imagearrayvariant` endpoint with
    /// `Accept: application/imagebytes`. A 24 MP frame is ~50 MB binary vs
    /// ~150 MB JSON; binary path is ~10x faster end-to-end. We send `Accept`
    /// for both binary and JSON so older servers that only know
    /// `application/json` still return a usable response, which we then parse
    /// on the JSON path.
    pub async fn download_image_array_full_typed(&self) -> Result<ImageArrayResult, AlpacaError> {
        // Why: subframe geometry tells us the expected shape; we cross-check
        // the parsed array against this so a server that reports inconsistent
        // sizes can't slip past as a partially-filled frame.
        let width = self.num_x().await.map_err(AlpacaError::OperationFailed)? as u32;
        let height = self.num_y().await.map_err(AlpacaError::OperationFailed)? as u32;

        // Why: at minimum 10MB/s network speed plus extra margin; the configured
        // very-long timeout (camera preset = 15 min) covers a 24 MP frame in
        // the worst-case JSON-encoded path. Binary is ~3x smaller, but the
        // timeout budgets the worst case so the same value works for both.
        let timeout_ms = self.client.timeout_config().very_long_operation_ms;

        let (client_id, transaction_id) = crate::client::get_client_transaction();
        // Why §5.13: `imagearrayvariant` is the v3 endpoint that may return
        // `application/imagebytes`. ASCOM mandates servers advertising binary
        // accept it here; servers that only know JSON still respond with their
        // standard JSON envelope on the same endpoint, so it is safe to prefer.
        let url = format!(
            "{}?ClientID={}&ClientTransactionID={}",
            self.client.build_url("imagearrayvariant"),
            client_id,
            transaction_id
        );

        // Why §5.12: reuse the pooled HTTP client so successive frames share
        // the keep-alive connection; only override the timeout per request.
        let http_client = self.client.http_client()?;

        // Why: estimate is for the timeout-error message, not for allocation.
        let estimated_bytes = (width as u64) * (height as u64) * 2 * 3;

        // Why §5.13: include `application/json` as the fallback alternative so
        // servers that do not speak ImageBytes can still satisfy the request
        // without a 406. q=0.9 nudges binary-capable servers to pick binary.
        let response = http_client
            .get(&url)
            .header(
                reqwest::header::ACCEPT,
                "application/imagebytes, application/json;q=0.9",
            )
            .timeout(Duration::from_millis(timeout_ms))
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    AlpacaError::timeout(
                        format!(
                            "imagearrayvariant download ({}x{}, ~{} MB est)",
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
            // Why §5.13: a 406 Not Acceptable means the server rejected our
            // Accept header set. Per ASCOM, that should not happen for these
            // media types — propagate as a hard error so it is diagnosable.
            let body = response.text().await.unwrap_or_default();
            return Err(AlpacaError::HttpError {
                status: status.as_u16(),
                message: body,
            });
        }

        // Why §5.13: parse `Content-Type` once. ImageBytes is signaled
        // server-side; the spec allows parameters (charset, etc.) so we match
        // by prefix, not equality.
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_ascii_lowercase();

        if content_type.starts_with("application/imagebytes") {
            let bytes = response.bytes().await.map_err(|e| {
                AlpacaError::RequestFailed(format!(
                    "Failed to read ImageBytes binary response: {}",
                    e
                ))
            })?;
            return parse_image_bytes(&bytes, width, height);
        }

        // Why §5.13: JSON fallback for older Alpaca servers that do not support
        // ImageBytes. Identical to the previous behavior on `imagearray`.
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
// ImageBytes binary parser (§5.13)
// -----------------------------------------------------------------------------

/// Fixed-size of the Alpaca v3 ImageBytes metadata header in bytes.
///
/// Layout (all little-endian; see ASCOM Alpaca v3 spec):
/// ```text
/// offset  0  i32  MetadataVersion
/// offset  4  i32  ErrorNumber
/// offset  8  u32  ClientTransactionID
/// offset 12  u32  ServerTransactionID
/// offset 16  i32  DataStart (byte offset to pixel payload)
/// offset 20  i32  ImageElementType (what the client requested)
/// offset 24  i32  TransmissionElementType (what is actually on the wire)
/// offset 28  i32  Rank (2 = mono, 3 = color)
/// offset 32  i32  Dimension1
/// offset 36  i32  Dimension2
/// offset 40  i32  Dimension3 (ignored when Rank == 2)
/// ```
const IMAGE_BYTES_HEADER_SIZE: usize = 44;

/// Parsed Alpaca ImageBytes metadata header.
///
/// Why a struct (not inline parsing): the unit test for §5.13 builds these
/// fields synthetically, so a named layout is much easier to reason about than
/// raw byte slicing in two places.
///
/// Why `#[allow(dead_code)]`: every field is part of the canonical Alpaca v3
/// header layout and the unit tests construct/inspect them. The fields that
/// the production decode path does not yet branch on (metadata_version,
/// client/server transaction IDs) are kept so callers can diagnose mismatched
/// transaction IDs or future-versioned wire formats without re-parsing.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub(crate) struct ImageBytesHeader {
    pub metadata_version: i32,
    pub error_number: i32,
    pub client_transaction_id: u32,
    pub server_transaction_id: u32,
    pub data_start: i32,
    pub image_element_type: i32,
    pub transmission_element_type: i32,
    pub rank: i32,
    pub dim1: i32,
    pub dim2: i32,
    pub dim3: i32,
}

/// Read a little-endian `i32` from `buf` at `offset`. Returns a structured
/// error (not a panic) when the buffer is too short — that is the "truncated"
/// case §5.13 calls out as a propagatable failure.
fn read_i32_le(buf: &[u8], offset: usize) -> Result<i32, AlpacaError> {
    let end = offset
        .checked_add(4)
        .ok_or_else(|| AlpacaError::ParseError(format!("i32 offset overflow at {}", offset)))?;
    if end > buf.len() {
        return Err(AlpacaError::BinaryHeaderTruncated {
            offset,
            needed: 4,
            got: buf.len(),
        });
    }
    // Why unwrap is sound: we just bounds-checked the slice length above.
    let arr: [u8; 4] = buf[offset..end].try_into().unwrap();
    Ok(i32::from_le_bytes(arr))
}

/// Read a little-endian `u32` from `buf` at `offset`.
fn read_u32_le(buf: &[u8], offset: usize) -> Result<u32, AlpacaError> {
    let end = offset
        .checked_add(4)
        .ok_or_else(|| AlpacaError::ParseError(format!("u32 offset overflow at {}", offset)))?;
    if end > buf.len() {
        return Err(AlpacaError::BinaryHeaderTruncated {
            offset,
            needed: 4,
            got: buf.len(),
        });
    }
    let arr: [u8; 4] = buf[offset..end].try_into().unwrap();
    Ok(u32::from_le_bytes(arr))
}

/// Parse the 44-byte Alpaca ImageBytes header.
pub(crate) fn parse_image_bytes_header(buf: &[u8]) -> Result<ImageBytesHeader, AlpacaError> {
    if buf.len() < IMAGE_BYTES_HEADER_SIZE {
        return Err(AlpacaError::BinaryHeaderTruncated {
            offset: 0,
            needed: IMAGE_BYTES_HEADER_SIZE,
            got: buf.len(),
        });
    }
    Ok(ImageBytesHeader {
        metadata_version: read_i32_le(buf, 0)?,
        error_number: read_i32_le(buf, 4)?,
        client_transaction_id: read_u32_le(buf, 8)?,
        server_transaction_id: read_u32_le(buf, 12)?,
        data_start: read_i32_le(buf, 16)?,
        image_element_type: read_i32_le(buf, 20)?,
        transmission_element_type: read_i32_le(buf, 24)?,
        rank: read_i32_le(buf, 28)?,
        dim1: read_i32_le(buf, 32)?,
        dim2: read_i32_le(buf, 36)?,
        dim3: read_i32_le(buf, 40)?,
    })
}

/// Convert the transmission element type code into the `ImageArrayElementType`
/// enum we already use for the JSON path. The on-the-wire enum is the canonical
/// ASCOM `ImageArrayElementTypes`: Unknown=0, Int16=1, Int32=2, Double=3,
/// Single=4, UInt64=5, Byte=6, Int64=7, UInt16=8 — same numbering as JSON
/// `Type`, so we can share the mapping.
fn transmission_type_from_code(code: i32) -> Result<ImageArrayElementType, AlpacaError> {
    match code {
        1 => Ok(ImageArrayElementType::Int16),
        2 => Ok(ImageArrayElementType::Int32),
        3 => Ok(ImageArrayElementType::Double),
        4 => Ok(ImageArrayElementType::Single),
        5 => Ok(ImageArrayElementType::UInt64),
        6 => Ok(ImageArrayElementType::Byte),
        7 => Ok(ImageArrayElementType::Int64),
        8 => Ok(ImageArrayElementType::UInt16),
        // Why: Type 0 (Unknown) is only valid for `image_element_type` (client
        // request semantics). For *transmission* it means the server did not
        // populate the field — we cannot decode payload bytes safely.
        _ => Err(AlpacaError::UnsupportedTransmissionType { code }),
    }
}

/// Size, in bytes, of one wire-encoded sample for the given transmission type.
fn transmission_element_size(t: ImageArrayElementType) -> Result<usize, AlpacaError> {
    match t {
        ImageArrayElementType::Byte => Ok(1),
        ImageArrayElementType::Int16 | ImageArrayElementType::UInt16 => Ok(2),
        ImageArrayElementType::Int32 | ImageArrayElementType::Single => Ok(4),
        ImageArrayElementType::Int64
        | ImageArrayElementType::UInt64
        | ImageArrayElementType::Double => Ok(8),
        // Why: caught earlier by `transmission_type_from_code`, but defense in
        // depth — we never want to silently treat Unknown as a 0-byte sample.
        ImageArrayElementType::Unknown => Err(AlpacaError::UnsupportedTransmissionType { code: 0 }),
    }
}

/// Decode a single wire sample at `payload[offset]` to `u16`.
///
/// Why centralized: identical clamping/rounding semantics to the JSON
/// `decode_pixel` path keep both wire formats producing the same output for
/// the same camera frame. Out-of-range integer samples clamp to `u16::MAX`;
/// non-finite floats produce a structured error (no silent zero).
fn decode_wire_sample(
    payload: &[u8],
    offset: usize,
    elem: ImageArrayElementType,
    linear_pixel: usize,
) -> Result<u16, AlpacaError> {
    let size = transmission_element_size(elem)?;
    let end = offset
        .checked_add(size)
        .ok_or_else(|| AlpacaError::ParseError(format!("payload offset overflow at {}", offset)))?;
    if end > payload.len() {
        return Err(AlpacaError::BinaryHeaderTruncated {
            offset,
            needed: size,
            got: payload.len(),
        });
    }
    let bytes = &payload[offset..end];
    match elem {
        ImageArrayElementType::Byte => Ok(bytes[0] as u16),
        ImageArrayElementType::Int16 => {
            let v = i16::from_le_bytes([bytes[0], bytes[1]]);
            Ok(clamp_i64_to_u16(v as i64))
        }
        ImageArrayElementType::UInt16 => {
            let v = u16::from_le_bytes([bytes[0], bytes[1]]);
            Ok(v)
        }
        ImageArrayElementType::Int32 => {
            let v = i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            Ok(clamp_i64_to_u16(v as i64))
        }
        ImageArrayElementType::UInt64 => {
            let v = u64::from_le_bytes([
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            ]);
            // Why: u64 max exceeds i64 range, so route through saturating cast.
            Ok(if v > u16::MAX as u64 { u16::MAX } else { v as u16 })
        }
        ImageArrayElementType::Int64 => {
            let v = i64::from_le_bytes([
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            ]);
            Ok(clamp_i64_to_u16(v))
        }
        ImageArrayElementType::Single => {
            let v = f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            if !v.is_finite() {
                return Err(AlpacaError::PixelParseError {
                    offset: linear_pixel,
                    found: format!("{}", v),
                    reason: "non-finite ImageBytes sample (NaN or infinity)".to_string(),
                });
            }
            Ok(clamp_f64_to_u16(v as f64))
        }
        ImageArrayElementType::Double => {
            let v = f64::from_le_bytes([
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            ]);
            if !v.is_finite() {
                return Err(AlpacaError::PixelParseError {
                    offset: linear_pixel,
                    found: format!("{}", v),
                    reason: "non-finite ImageBytes sample (NaN or infinity)".to_string(),
                });
            }
            Ok(clamp_f64_to_u16(v))
        }
        // Why: filtered out by `transmission_element_size`, but defense in depth.
        ImageArrayElementType::Unknown => Err(AlpacaError::UnsupportedTransmissionType { code: 0 }),
    }
}

/// Parse a complete Alpaca v3 ImageBytes payload (header + pixel bytes).
///
/// Wire-side layout (after the 44-byte header) is column-major to match the
/// JSON `imagearrayvariant` semantics: pixels are stored as `[NumX][NumY]`
/// (rank 2) or `[NumX][NumY][NumPlanes]` (rank 3) flattened in that iteration
/// order. We materialize the output into the same column-major flat layout
/// already produced by `parse_image_array_json`, so downstream consumers see
/// identical pixel ordering regardless of which transport returned the frame.
pub(crate) fn parse_image_bytes(
    payload: &[u8],
    expected_width: u32,
    expected_height: u32,
) -> Result<ImageArrayResult, AlpacaError> {
    let header = parse_image_bytes_header(payload)?;

    // Why: device-side errors flow in-band on the ImageBytes wire too — the
    // ErrorNumber field replaces the JSON ErrorNumber/ErrorMessage pair. The
    // optional UTF-8 error message lives between offset 44 and `data_start`.
    if header.error_number != 0 {
        let msg_start = IMAGE_BYTES_HEADER_SIZE;
        let msg_end = header.data_start.max(0) as usize;
        let message = if msg_end > msg_start && msg_end <= payload.len() {
            String::from_utf8_lossy(&payload[msg_start..msg_end]).into_owned()
        } else {
            String::new()
        };
        return Err(AlpacaError::DeviceError {
            code: header.error_number,
            message: if message.is_empty() {
                format!("Alpaca ImageBytes error {}", header.error_number)
            } else {
                message
            },
        });
    }

    let element_type = transmission_type_from_code(header.transmission_element_type)?;
    let image_element_type = match header.image_element_type {
        // Why: when the server has not filled image_element_type, fall back to
        // transmission so callers still get a useful type tag on the result.
        0 => element_type,
        other => match ImageArrayElementType::from_i64(other as i64) {
            ImageArrayElementType::Unknown => {
                return Err(AlpacaError::UnsupportedImageArray {
                    rank: header.rank as i64,
                    image_type: other as i64,
                    reason: format!(
                        "unrecognised ImageBytes ImageElementType {}",
                        header.image_element_type
                    ),
                })
            }
            t => t,
        },
    };

    let (width_from_header, height_from_header, planes) = match header.rank {
        2 => {
            // Why: dim3 must be 0 (or 1) for rank-2; a non-trivial dim3 means
            // the rank/dims pair is inconsistent.
            if header.dim3 > 1 {
                return Err(AlpacaError::MalformedDimensions {
                    rank: header.rank,
                    dim1: header.dim1,
                    dim2: header.dim2,
                    dim3: header.dim3,
                    expected_width,
                    expected_height,
                    reason: "rank=2 but dim3 > 1".to_string(),
                });
            }
            (header.dim1, header.dim2, 1i32)
        }
        3 => (header.dim1, header.dim2, header.dim3),
        other => {
            return Err(AlpacaError::UnsupportedImageArray {
                rank: other as i64,
                image_type: header.image_element_type as i64,
                reason: "only rank 2 (mono) and rank 3 (color) are supported".to_string(),
            })
        }
    };

    if width_from_header <= 0
        || height_from_header <= 0
        || planes <= 0
        || width_from_header as u32 != expected_width
        || height_from_header as u32 != expected_height
    {
        return Err(AlpacaError::MalformedDimensions {
            rank: header.rank,
            dim1: header.dim1,
            dim2: header.dim2,
            dim3: header.dim3,
            expected_width,
            expected_height,
            reason: "dimensions inconsistent with subframe (NumX, NumY)".to_string(),
        });
    }

    let data_start = header.data_start;
    if data_start < IMAGE_BYTES_HEADER_SIZE as i32 || (data_start as usize) > payload.len() {
        return Err(AlpacaError::ParseError(format!(
            "ImageBytes DataStart {} outside payload (header={}, payload={} bytes)",
            data_start,
            IMAGE_BYTES_HEADER_SIZE,
            payload.len()
        )));
    }
    let data_start = data_start as usize;
    let pixel_bytes = &payload[data_start..];

    let elem_size = transmission_element_size(element_type)?;
    let width = expected_width as usize;
    let height = expected_height as usize;
    let planes_us = planes as usize;
    let pixels_per_plane = width
        .checked_mul(height)
        .ok_or_else(|| AlpacaError::ParseError("width*height overflow".to_string()))?;
    let total_samples = pixels_per_plane
        .checked_mul(planes_us)
        .ok_or_else(|| AlpacaError::ParseError("width*height*planes overflow".to_string()))?;
    let total_bytes = total_samples
        .checked_mul(elem_size)
        .ok_or_else(|| AlpacaError::ParseError("payload byte total overflow".to_string()))?;

    if pixel_bytes.len() < total_bytes {
        return Err(AlpacaError::BinaryHeaderTruncated {
            offset: data_start,
            needed: total_bytes,
            got: pixel_bytes.len(),
        });
    }

    let mut planar: Vec<u16> = vec![0u16; total_samples];
    let mut linear: usize = 0;

    // Wire ordering for `imagearrayvariant` matches JSON: column-major over
    // (x, y), and for rank 3 the innermost varies plane index. We decode in
    // that order and reshuffle into our planar output layout so plane p is a
    // contiguous slice of `pixels_per_plane` samples starting at
    // `p * pixels_per_plane`.
    if planes_us == 1 {
        // Why fast path: rank-2 does not need per-pixel plane indexing; the
        // sample sequence directly fills the single output plane in order.
        for (sample_idx, slot) in planar.iter_mut().enumerate().take(total_samples) {
            let byte_off = sample_idx * elem_size;
            *slot = decode_wire_sample(pixel_bytes, byte_off, element_type, sample_idx)?;
            linear += 1;
        }
    } else {
        for x in 0..width {
            for y in 0..height {
                for p in 0..planes_us {
                    let byte_off = linear * elem_size;
                    let v = decode_wire_sample(pixel_bytes, byte_off, element_type, linear)?;
                    let dest = (p * pixels_per_plane) + (x * height) + y;
                    planar[dest] = v;
                    linear += 1;
                }
            }
        }
    }

    if linear != total_samples {
        return Err(AlpacaError::ParseError(format!(
            "ImageBytes sample count mismatch: expected {}, decoded {}",
            total_samples, linear
        )));
    }

    Ok(ImageArrayResult {
        width: expected_width,
        height: expected_height,
        planes: planes as u32,
        pixels: planar,
        element_type: image_element_type,
    })
}

// -----------------------------------------------------------------------------
// Tests (§5.3, §5.13)
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

// -----------------------------------------------------------------------------
// ImageBytes binary protocol tests (§5.13)
// -----------------------------------------------------------------------------

#[cfg(test)]
mod image_bytes_tests {
    use super::*;

    /// Build a synthetic ImageBytes payload from a header description plus
    /// raw pixel bytes. Returns the wire bytes a server would emit.
    fn build_payload(
        error_number: i32,
        data_start: i32,
        image_element_type: i32,
        transmission_element_type: i32,
        rank: i32,
        dim1: i32,
        dim2: i32,
        dim3: i32,
        between_header_and_data: &[u8],
        pixel_bytes: &[u8],
    ) -> Vec<u8> {
        let mut buf = Vec::with_capacity(
            IMAGE_BYTES_HEADER_SIZE + between_header_and_data.len() + pixel_bytes.len(),
        );
        // MetadataVersion = 1
        buf.extend_from_slice(&1i32.to_le_bytes());
        // ErrorNumber
        buf.extend_from_slice(&error_number.to_le_bytes());
        // ClientTransactionID = 42, ServerTransactionID = 4242
        buf.extend_from_slice(&42u32.to_le_bytes());
        buf.extend_from_slice(&4242u32.to_le_bytes());
        // DataStart
        buf.extend_from_slice(&data_start.to_le_bytes());
        // ImageElementType
        buf.extend_from_slice(&image_element_type.to_le_bytes());
        // TransmissionElementType
        buf.extend_from_slice(&transmission_element_type.to_le_bytes());
        // Rank
        buf.extend_from_slice(&rank.to_le_bytes());
        // Dim1, Dim2, Dim3
        buf.extend_from_slice(&dim1.to_le_bytes());
        buf.extend_from_slice(&dim2.to_le_bytes());
        buf.extend_from_slice(&dim3.to_le_bytes());
        assert_eq!(buf.len(), IMAGE_BYTES_HEADER_SIZE);
        // Optional bytes (error message) between header and DataStart
        buf.extend_from_slice(between_header_and_data);
        // Pad to DataStart if there is a gap
        if (buf.len() as i32) < data_start {
            buf.resize(data_start as usize, 0);
        }
        buf.extend_from_slice(pixel_bytes);
        buf
    }

    #[test]
    fn rank2_uint16_decodes_clean() {
        // 2x3 mono UInt16 image. Wire order is column-major: x outer, y inner.
        // Pixel values: (0,0)=10 (0,1)=20 (0,2)=30 (1,0)=40 (1,1)=50 (1,2)=60
        let pixels: [u16; 6] = [10, 20, 30, 40, 50, 60];
        let mut pixel_bytes: Vec<u8> = Vec::with_capacity(12);
        for p in &pixels {
            pixel_bytes.extend_from_slice(&p.to_le_bytes());
        }
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            8, // ImageElementType = UInt16
            8, // TransmissionElementType = UInt16
            2,
            2,
            3,
            0,
            &[],
            &pixel_bytes,
        );

        let r = parse_image_bytes(&payload, 2, 3).expect("rank-2 UInt16 parse");
        assert_eq!(r.width, 2);
        assert_eq!(r.height, 3);
        assert_eq!(r.planes, 1);
        assert_eq!(r.pixels, vec![10u16, 20, 30, 40, 50, 60]);
        assert_eq!(r.element_type, ImageArrayElementType::UInt16);
    }

    #[test]
    fn rank2_int32_clamps_to_u16() {
        // Int32 sample stream containing negative + overflow values.
        let samples: [i32; 4] = [-5, 0, 70_000, 12_345];
        let mut pixel_bytes: Vec<u8> = Vec::with_capacity(16);
        for v in &samples {
            pixel_bytes.extend_from_slice(&v.to_le_bytes());
        }
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            2, // Int32
            2,
            2,
            2,
            2,
            0,
            &[],
            &pixel_bytes,
        );

        let r = parse_image_bytes(&payload, 2, 2).expect("rank-2 Int32 parse");
        assert_eq!(r.pixels, vec![0u16, 0, u16::MAX, 12_345]);
        assert_eq!(r.element_type, ImageArrayElementType::Int32);
    }

    #[test]
    fn rank3_color_image_planar_layout() {
        // 2x2x3 image, UInt16 wire. Column-major over (x, y, p):
        // (0,0,0..2)=10,20,30  (0,1,0..2)=11,21,31
        // (1,0,0..2)=12,22,32  (1,1,0..2)=13,23,33
        let samples: [u16; 12] = [10, 20, 30, 11, 21, 31, 12, 22, 32, 13, 23, 33];
        let mut pixel_bytes: Vec<u8> = Vec::with_capacity(24);
        for s in &samples {
            pixel_bytes.extend_from_slice(&s.to_le_bytes());
        }
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            8,
            8,
            3,
            2,
            2,
            3,
            &[],
            &pixel_bytes,
        );

        let r = parse_image_bytes(&payload, 2, 2).expect("rank-3 UInt16 parse");
        assert_eq!(r.width, 2);
        assert_eq!(r.height, 2);
        assert_eq!(r.planes, 3);
        // Plane 0: [10, 11, 12, 13] (column-major over x,y)
        // Plane 1: [20, 21, 22, 23]
        // Plane 2: [30, 31, 32, 33]
        assert_eq!(
            r.pixels,
            vec![10u16, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33]
        );
    }

    #[test]
    fn header_truncated_payload_returns_structured_error() {
        // Only 20 bytes — far short of the 44-byte header.
        let payload = vec![0u8; 20];
        let err = parse_image_bytes(&payload, 1, 1).expect_err("must reject truncated header");
        match err {
            AlpacaError::BinaryHeaderTruncated {
                needed,
                got,
                offset,
            } => {
                assert_eq!(needed, IMAGE_BYTES_HEADER_SIZE);
                assert_eq!(got, 20);
                assert_eq!(offset, 0);
            }
            other => panic!("expected BinaryHeaderTruncated, got {:?}", other),
        }
    }

    #[test]
    fn payload_shorter_than_declared_pixels_errors() {
        // Header says 2x2 UInt16 = 8 bytes pixels, but we provide only 4.
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            8,
            8,
            2,
            2,
            2,
            0,
            &[],
            &[0u8, 0, 0, 0],
        );
        let err = parse_image_bytes(&payload, 2, 2).expect_err("must reject short pixel payload");
        assert!(matches!(err, AlpacaError::BinaryHeaderTruncated { .. }));
    }

    #[test]
    fn unsupported_transmission_type_errors() {
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            2,
            99, // unknown transmission type
            2,
            1,
            1,
            0,
            &[],
            &[0u8, 0, 0, 0],
        );
        let err =
            parse_image_bytes(&payload, 1, 1).expect_err("must reject unknown transmission type");
        match err {
            AlpacaError::UnsupportedTransmissionType { code } => assert_eq!(code, 99),
            other => panic!("expected UnsupportedTransmissionType, got {:?}", other),
        }
    }

    #[test]
    fn malformed_dimensions_rank2_with_dim3_errors() {
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            8,
            8,
            2,    // rank 2
            2,    // dim1
            2,    // dim2
            3,    // dim3 > 1 — inconsistent with rank=2
            &[],
            &[0u8; 8],
        );
        let err = parse_image_bytes(&payload, 2, 2).expect_err("rank-2 with dim3 must error");
        match err {
            AlpacaError::MalformedDimensions {
                rank,
                dim3,
                expected_width,
                expected_height,
                ..
            } => {
                assert_eq!(rank, 2);
                assert_eq!(dim3, 3);
                assert_eq!(expected_width, 2);
                assert_eq!(expected_height, 2);
            }
            other => panic!("expected MalformedDimensions, got {:?}", other),
        }
    }

    #[test]
    fn dimension_mismatch_with_subframe_errors() {
        // Header says 3x3, but caller expects 2x2 — must error, not silently
        // truncate.
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            8,
            8,
            2,
            3,
            3,
            0,
            &[],
            &[0u8; 18],
        );
        let err = parse_image_bytes(&payload, 2, 2).expect_err("dim mismatch must error");
        assert!(matches!(err, AlpacaError::MalformedDimensions { .. }));
    }

    #[test]
    fn device_error_number_propagates_with_message() {
        // ErrorNumber != 0, with a UTF-8 message between header and DataStart.
        let msg = b"camera not connected";
        let data_start = (IMAGE_BYTES_HEADER_SIZE + msg.len()) as i32;
        let payload = build_payload(
            1031, // device error code
            data_start,
            2,
            2,
            2,
            0,
            0,
            0,
            msg,
            &[], // no pixel payload when reporting an error
        );
        let err = parse_image_bytes(&payload, 1, 1).expect_err("device error must propagate");
        match err {
            AlpacaError::DeviceError { code, message } => {
                assert_eq!(code, 1031);
                assert!(
                    message.contains("camera not connected"),
                    "got message: {}",
                    message
                );
            }
            other => panic!("expected DeviceError, got {:?}", other),
        }
    }

    #[test]
    fn nan_float_sample_errors_not_zero() {
        // Single (f32) NaN must propagate, not silently emit 0.
        let nan: f32 = f32::NAN;
        let mut pixel_bytes: Vec<u8> = Vec::new();
        pixel_bytes.extend_from_slice(&0.0f32.to_le_bytes());
        pixel_bytes.extend_from_slice(&nan.to_le_bytes());
        let payload = build_payload(
            0,
            IMAGE_BYTES_HEADER_SIZE as i32,
            4,
            4,
            2,
            1,
            2,
            0,
            &[],
            &pixel_bytes,
        );
        let err = parse_image_bytes(&payload, 1, 2).expect_err("NaN must error");
        assert!(matches!(err, AlpacaError::PixelParseError { .. }));
    }

    #[test]
    fn data_start_inside_header_errors() {
        // DataStart < 44 is a protocol violation.
        let payload = build_payload(
            0,
            10,
            8,
            8,
            2,
            1,
            1,
            0,
            &[],
            &[0u8, 0],
        );
        let err = parse_image_bytes(&payload, 1, 1).expect_err("DataStart < header must error");
        assert!(matches!(err, AlpacaError::ParseError(_)));
    }
}
