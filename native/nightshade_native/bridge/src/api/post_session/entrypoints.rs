use super::*;

// =============================================================================
// Public FFI entry points
// =============================================================================

/// One-shot batch integration of a sub list into a linear FITS master.
///
/// Pipeline: optional calibration (dark/flat/bias) + cosmetic correction →
/// star-based registration to a reference → per-channel normalization →
/// per-sub quality weighting → batch integration with pixel rejection →
/// 16-bit/float linear FITS master + stretched preview PNG.
///
/// `args_json` is an [`IntegrateSessionArgs`]; the result is an
/// [`IntegrateSessionResult`]. All failure modes (no subs, unreadable frame,
/// no consistent geometry, write failure) surface as `Err(String)` — never a
/// silent partial stack.
pub fn api_integrate_session(args_json: String) -> Result<String, String> {
    let args: IntegrateSessionArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid integrate args: {e}"))?;
    let result = integrate_session(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Multi-night accumulating master. `op` selects the operation:
///
/// * `create`   `{ op, referencePath, sidecarPath, masterFitsPath?, settings?, filter?, target? }`
/// * `add`      `{ op, sidecarPath, lightPaths[], exposuresSec?, calibration?, settings? }`
/// * `finalize` `{ op, sidecarPath, masterFitsPath, previewPngPath? }`
/// * `info`     `{ op, sidecarPath }`
///
/// Returns a [`MasterAccumulateResult`]. The running accumulator state lives in
/// the `.nsmaster` sidecar; the FITS is the shareable artifact written on
/// `finalize` (and re-finalizable after more `add`s).
pub fn api_master_accumulate(args_json: String) -> Result<String, String> {
    let op: MasterOp =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid accumulate args: {e}"))?;
    let result = match op.op.as_str() {
        "create" => master_create(&args_json)?,
        "add" => master_add(&args_json)?,
        "finalize" => master_finalize(&args_json)?,
        "info" => master_info(&args_json)?,
        other => {
            return Err(format!(
                "unknown master op '{other}'; expected create/add/finalize/info"
            ))
        }
    };
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Build a unit-mean master flat from raw flats (+ optional bias / dark-flat
/// pedestal) and write it as a FITS master, wrapping
/// [`build_master_flat`](nightshade_imaging::calibration_masters::build_master_flat).
///
/// `args_json` is a [`BuildMasterFlatArgs`]; the result is a
/// [`BuildMasterFlatResult`].
pub fn api_build_master_flat(args_json: String) -> Result<String, String> {
    let args: BuildMasterFlatArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid flat args: {e}"))?;
    let result = build_master_flat_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Re-export an in-memory pixel buffer as a 16-bit or float FITS master with
/// provenance. The integration paths already write the FITS natively, so this
/// is for re-export from Dart-held buffers.
///
/// `args_json` is a [`SaveFitsMasterArgs`]; the result is a
/// [`SaveFitsMasterResult`].
pub fn api_save_fits_master(args_json: String) -> Result<String, String> {
    let args: SaveFitsMasterArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid save args: {e}"))?;
    let result = save_fits_master_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}
