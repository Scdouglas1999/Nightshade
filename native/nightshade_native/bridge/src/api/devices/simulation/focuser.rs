use super::*;

/// Simulated focuser state
pub(crate) static SIM_FOCUSER: OnceLock<Arc<RwLock<SimulatedFocuser>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedFocuser {
    pub status: FocuserStatus,
}

impl Default for SimulatedFocuser {
    fn default() -> Self {
        Self {
            status: FocuserStatus {
                connected: false,
                position: 25000,
                moving: false,
                temperature: Some(20.0),
                max_position: 50000,
                step_size: 1.0,
                is_absolute: true,
                has_temperature: true,
            },
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn get_sim_focuser() -> &'static Arc<RwLock<SimulatedFocuser>> {
    SIM_FOCUSER.get_or_init(|| Arc::new(RwLock::new(SimulatedFocuser::default())))
}

/// Get focuser status
pub async fn api_get_focuser_status(device_id: String) -> Result<FocuserStatus, NightshadeError> {
    let mgr = get_device_manager();

    // Get all focuser status components
    let position = mgr
        .focuser_get_position(&device_id)
        .await
        .map_err(NightshadeError::from)?;
    let moving = mgr
        .focuser_is_moving(&device_id)
        .await
        .map_err(NightshadeError::from)?;
    let temperature = mgr.focuser_get_temp(&device_id).await.unwrap_or(None);
    let (max_position, step_size) = match mgr.focuser_get_details(&device_id).await {
        Ok(details) => details,
        Err(e) => {
            tracing::warn!(
                "Failed to get focuser details for {}: {:?}. Returning unknown max/step values.",
                device_id,
                e
            );
            (0, 0.0)
        }
    };
    let is_absolute = mgr
        .focuser_is_absolute(&device_id)
        .await
        .map_err(NightshadeError::from)?;

    Ok(FocuserStatus {
        connected: true,
        position,
        moving,
        temperature,
        max_position,
        step_size,
        is_absolute,
        has_temperature: temperature.is_some(),
    })
}

/// Move focuser to position
pub async fn api_focuser_move_to(device_id: String, position: i32) -> Result<(), NightshadeError> {
    // Real device - use DeviceManager for proper driver routing
    let mgr = get_device_manager();
    mgr.focuser_move_abs(&device_id, position)
        .await
        .map_err(NightshadeError::from)
}

/// Move focuser by relative amount
pub async fn api_focuser_move_relative(
    device_id: String,
    delta: i32,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_rel(&device_id, delta)
        .await
        .map_err(NightshadeError::from)
}

/// Halt focuser
pub async fn api_focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_halt(&device_id)
        .await
        .map_err(NightshadeError::from)
}
