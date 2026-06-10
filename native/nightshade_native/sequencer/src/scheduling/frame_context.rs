//! Wave 3 Image Grading: per-frame metadata bundle carried into `save_fits`.
//!
//! Audit complaint: the pre-existing `save_fits` took only four positional
//! fields (target name, filter, RA, Dec). Standard astrophotography FITS
//! headers want session ID, panel index, observer, focuser position, sensor
//! temp, rotator angle, guide RMS, plate-solve coords, Bayer pattern, observer
//! site coordinates, telescope/camera identification. The
//! [`MosaicPanelInfo`](crate::MosaicPanelInfo) config was already present but
//! never made it into FITS headers — so mosaic panels merged in tools like
//! PixInsight have no way to know which panel a sub belongs to.
//!
//! `FrameContext` is the single bundle that flows from the executor through
//! `expose.rs` into `DeviceOps::save_fits`. Every Option<_> field is honestly
//! optional — if the corresponding device isn't connected or the telemetry
//! isn't available, the keyword is simply omitted from the FITS header rather
//! than written with a sentinel value (silent fallbacks are bugs; an absent
//! keyword is the honest answer).
//!
//! The bridge-side `api_save_fits_file` reads this struct and emits the
//! corresponding FITS keywords. Custom Nightshade-specific keywords use the
//! `NS-*` prefix (NS-MOSNM, NS-PIDX, NS-PROW, NS-PCOL, NS-SESID, NS-FIDX,
//! NS-NPLN) to stay clear of standard astrophotography conventions while
//! still being readable in any FITS viewer.

use crate::MosaicPanelInfo;
use serde::{Deserialize, Serialize};

/// Wave 7 Agent 3 — defect-map correction record attached to every
/// frame that had cosmetic-pixel correction applied. The FITS writer
/// converts this into a HISTORY card so the calibration provenance is
/// visible in any FITS viewer.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DefectMapCorrectionRecord {
    /// Camera identifier the map was built for (`native:zwo:ASI2600MC`,
    /// `ascom:ZWO.ASICamera2`, etc.). Recorded for re-stacking workflows
    /// that want to verify the map applies to the camera that produced
    /// the frame.
    pub camera_id: String,
    /// Total number of defective pixels in the loaded map.
    pub defect_count: u32,
    /// Number of pixels actually rewritten in this frame. Equal to
    /// `defect_count` in the common case, but smaller when some
    /// defects had no healthy neighbours inside the expanded kernel.
    pub corrected_count: u32,
    /// Kernel diameter (3, 5, or 7).
    pub kernel_diameter: u8,
    /// Replacement method wire-form identifier ("median" / "mean" /
    /// "gaussian"). Centralised here so downstream readers see the
    /// same string the Dart settings UI emitted.
    pub method: String,
}

/// All metadata about a single captured frame, used to populate the FITS
/// header at save time.
///
/// Construction site: `expose.rs` builds this just before the `save_fits`
/// call, pulling target info from `ExecutionContext`, exposure settings
/// from the active `ExposureConfig`, and live telemetry from the most
/// recent device reads (sensor temp, focuser position, rotator angle,
/// guide RMS, plate-solve result).
///
/// Why a struct instead of growing the `save_fits` signature: 25+ optional
/// fields as positional args would be a maintenance nightmare and every
/// new field would require updating every implementor of `DeviceOps`.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FrameContext {
    // -------------------------------------------------------------------
    // SESSION / RUN IDENTIFICATION
    // -------------------------------------------------------------------
    /// Unique session identifier so frames captured in the same run can
    /// be linked back to a logical session row in the database. Generated
    /// once per executor start. Surfaced as the FITS keyword `NS-SESID`.
    pub session_id: String,

    /// Stable identifier of the target being imaged. Distinct from
    /// `target_name` because targets can be renamed mid-session — the id
    /// remains the join key for the captured_images database row.
    pub target_id: Option<String>,

    // -------------------------------------------------------------------
    // TARGET INFORMATION (OBJECT, RA, DEC keywords)
    // -------------------------------------------------------------------
    pub target_name: Option<String>,
    /// Target RA in hours (0–24). FITS `RA` keyword.
    pub target_ra_hours: Option<f64>,
    /// Target Dec in degrees (-90 to +90). FITS `DEC` keyword.
    pub target_dec_degrees: Option<f64>,

    // -------------------------------------------------------------------
    // FILTER (FILTER keyword)
    // -------------------------------------------------------------------
    pub filter_name: Option<String>,
    /// Filter position (1-based index, matches FITS convention). Surfaced
    /// as the FITS keyword `FILTPOS`.
    pub filter_index: Option<i32>,

    // -------------------------------------------------------------------
    // CAMERA SETTINGS (XBINNING/YBINNING/GAIN/OFFSET keywords)
    // -------------------------------------------------------------------
    pub binning_x: u32,
    pub binning_y: u32,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    /// Exposure duration in seconds. Mirrors `EXPTIME` in the FITS header.
    pub duration_secs: f64,

    // -------------------------------------------------------------------
    // FRAME ACCOUNTING (custom NS-* keywords)
    // -------------------------------------------------------------------
    /// 1-based frame index within the current TakeExposure burst.
    /// Surfaced as the FITS keyword `NS-FIDX`.
    pub frame_index: u32,
    /// Total planned frames in the burst (1-based). Surfaced as `NS-NPLN`.
    pub total_planned_frames: Option<u32>,

    // -------------------------------------------------------------------
    // LIVE DEVICE TELEMETRY (CCD-TEMP / SET-TEMP / FOCUSPOS / ROTATPOS / GUIDERMS)
    // -------------------------------------------------------------------
    /// Sensor temperature at capture time. FITS `CCD-TEMP`.
    pub sensor_temp_c: Option<f64>,
    /// Target temperature the cooler was set to. FITS `SET-TEMP`.
    pub set_temp_c: Option<f64>,
    /// Focuser absolute position. FITS `FOCUSPOS`.
    pub focuser_position: Option<i32>,
    /// Focuser temperature (sometimes used for offset prediction). FITS
    /// `FOCTEMP`.
    pub focuser_temperature_c: Option<f64>,
    /// Rotator mechanical angle in degrees. FITS `ROTATPOS`. (Distinct from
    /// `CROTA{1,2}` which describe the WCS rotation of the solved field.)
    pub rotator_angle_deg: Option<f64>,
    /// Total guiding RMS in arcseconds at the moment of capture. FITS
    /// `GUIDERMS`.
    pub guide_rms_arcsec: Option<f64>,

    // -------------------------------------------------------------------
    // PLATE-SOLVE RESULT (SOLVED-RA / SOLVED-DEC / PIXSCALE / CROTA1 keywords)
    // -------------------------------------------------------------------
    /// Plate-solved RA in hours (if the frame was solved). FITS
    /// `SOLVED-RA`.
    pub plate_solve_ra_hours: Option<f64>,
    /// Plate-solved Dec in degrees. FITS `SOLVED-DEC`.
    pub plate_solve_dec_degrees: Option<f64>,
    /// Solved pixel scale in arcseconds/pixel. FITS `PIXSCALE`.
    pub plate_solve_pixel_scale_arcsec: Option<f64>,
    /// Solved field rotation in degrees. FITS `CROTA1`/`CROTA2`.
    pub plate_solve_rotation_deg: Option<f64>,

    // -------------------------------------------------------------------
    // BAYER PATTERN (OSC cameras) — FITS `BAYERPAT` keyword
    // -------------------------------------------------------------------
    /// Bayer pattern string like "RGGB", "BGGR", etc. None for monochrome
    /// sensors.
    pub bayer_pattern: Option<String>,

    // -------------------------------------------------------------------
    // MOSAIC PANEL (custom NS-MOSNM / NS-PIDX / NS-PROW / NS-PCOL)
    // -------------------------------------------------------------------
    /// Mosaic panel information when this target is one panel of a
    /// multi-panel mosaic. The audit's specific complaint: this field
    /// existed in `MosaicPanelInfo` but was never written to FITS headers.
    pub mosaic_panel: Option<MosaicPanelInfo>,

    // -------------------------------------------------------------------
    // OBSERVER / SITE (OBSERVER / SITELAT / SITELONG / SITEELEV keywords)
    // -------------------------------------------------------------------
    /// Observer name as configured in app settings. FITS `OBSERVER`.
    pub observer_name: Option<String>,
    /// Latitude in decimal degrees (+ = north). FITS `SITELAT`.
    pub site_latitude_deg: Option<f64>,
    /// Longitude in decimal degrees (+ = east). FITS `SITELONG`.
    pub site_longitude_deg: Option<f64>,
    /// Elevation in metres above sea level. FITS `SITEELEV`.
    pub site_elevation_m: Option<f64>,

    // -------------------------------------------------------------------
    // EQUIPMENT IDENTIFICATION
    // -------------------------------------------------------------------
    /// Camera manufacturer (e.g., "ZWO"). Concatenated with model into
    /// the FITS `INSTRUME` keyword.
    pub camera_make: Option<String>,
    /// Camera model (e.g., "ASI2600MM Pro").
    pub camera_model: Option<String>,
    /// Telescope name (e.g., "Askar 65PHQ"). FITS `TELESCOP`.
    pub telescope_name: Option<String>,
    /// Telescope focal length in millimetres. FITS `FOCALLEN`.
    pub telescope_focal_length_mm: Option<f64>,
    /// Telescope aperture diameter in millimetres. FITS `APTDIA`.
    pub telescope_aperture_mm: Option<f64>,

    // -------------------------------------------------------------------
    // IMAGE TYPE — already conveyed but now centralised here.
    // -------------------------------------------------------------------
    /// "Light", "Dark", "Flat", "Bias", etc. FITS `IMAGETYP`.
    /// Defaults to "Light" when constructed from a TakeExposure node.
    pub frame_type: String,

    // -------------------------------------------------------------------
    // Wave 7 Agent 3 — defect-map correction record.
    //
    // When defect correction ran for this frame, the FITS writer
    // emits a HISTORY card recording the camera id the map was built
    // for, the number of corrected pixels, the kernel diameter, and
    // the replacement method. None means no correction was applied
    // (no map configured, or it was skipped because the camera id
    // mismatched).
    // -------------------------------------------------------------------
    pub defect_map_correction: Option<DefectMapCorrectionRecord>,

    // -------------------------------------------------------------------
    // Wave 7 Science — Photometry FITS keywords.
    //
    // Populated by the `SciencePhotometryInstruction` for frames
    // captured under a photometry burst. All fields are Option<_>:
    // for non-photometry captures (the overwhelming majority) every
    // field is None and the FITS writer simply omits the keyword.
    //
    //   * `OBJCAT`   — target catalogue designation
    //   * `REFSTARS` — comma-separated reference star catalogue IDs
    //   * `MJD-OBS`  — Modified Julian Date at exposure midpoint
    //   * `INSTRMAG` — instrumental magnitude (live-reduced)
    //   * `DIFFMAG`  — differential magnitude (against reference stars)
    //   * `FWHM`     — measured FWHM in arcseconds
    //   * `SNR`      — measured target SNR
    //
    // `AIRMASS` is intentionally NOT added here — the bridge writer
    // already computes it from the altitude when present.
    // -------------------------------------------------------------------
    pub photometry_object_catalog: Option<String>,
    pub photometry_reference_stars: Option<Vec<String>>,
    pub photometry_mjd_obs: Option<f64>,
    pub photometry_instrumental_mag: Option<f64>,
    pub photometry_differential_mag: Option<f64>,
    pub photometry_fwhm_arcsec: Option<f64>,
    pub photometry_snr: Option<f64>,

    // -------------------------------------------------------------------
    // Dual-rig — frame attribution by rig.
    //
    // When set, identifies which optical train / camera produced this
    // frame in a multi-camera (primary + secondary piggyback) session.
    // `None` for the (overwhelmingly common) single-rig case, in which
    // the FITS writer omits the keyword entirely. The secondary capture
    // loop ([`crate::dual_rig`]) stamps its `rig_label` here so subs are
    // attributable to the right rig and the session stats can be split.
    // Surfaced as the custom FITS keyword `NS-RIG`.
    // -------------------------------------------------------------------
    pub rig_label: Option<String>,
}

impl FrameContext {
    /// Convenience constructor for the common case in `expose.rs`: a Light
    /// frame in a TakeExposure burst, with the target and exposure settings
    /// known but most telemetry still pending.
    ///
    /// Callers then fill in the live telemetry via the field accessors
    /// before passing to `save_fits`. Marker fields like `session_id`,
    /// `binning_*`, and `duration_secs` are required and must be supplied.
    pub fn new_light(
        session_id: impl Into<String>,
        binning_x: u32,
        binning_y: u32,
        duration_secs: f64,
        frame_index: u32,
    ) -> Self {
        Self {
            session_id: session_id.into(),
            binning_x,
            binning_y,
            duration_secs,
            frame_index,
            frame_type: "Light".to_string(),
            ..Default::default()
        }
    }

    /// Display label suitable for log lines. Used by the FITS writer to
    /// produce a one-line "captured: <label>" summary.
    pub fn log_label(&self) -> String {
        let target = self
            .target_name
            .as_deref()
            .filter(|s| !s.is_empty())
            .unwrap_or("(no-target)");
        let filter = self
            .filter_name
            .as_deref()
            .filter(|s| !s.is_empty())
            .unwrap_or("(no-filter)");
        match &self.mosaic_panel {
            Some(panel) => format!(
                "{} [{}] frame {} ({:.1}s, {})",
                target,
                panel.display_label(),
                self.frame_index,
                self.duration_secs,
                filter
            ),
            None => format!(
                "{} frame {} ({:.1}s, {})",
                target, self.frame_index, self.duration_secs, filter
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_light_sets_required_fields() {
        let ctx = FrameContext::new_light("sess-abc", 1, 1, 60.0, 3);
        assert_eq!(ctx.session_id, "sess-abc");
        assert_eq!(ctx.binning_x, 1);
        assert_eq!(ctx.binning_y, 1);
        assert!((ctx.duration_secs - 60.0).abs() < f64::EPSILON);
        assert_eq!(ctx.frame_index, 3);
        assert_eq!(ctx.frame_type, "Light");
        // Optional fields default to None / empty.
        assert!(ctx.target_name.is_none());
        assert!(ctx.mosaic_panel.is_none());
    }

    #[test]
    fn log_label_renders_mosaic_panel_when_present() {
        let mut ctx = FrameContext::new_light("s", 1, 1, 60.0, 1);
        ctx.target_name = Some("M31".to_string());
        ctx.filter_name = Some("L".to_string());
        ctx.mosaic_panel = Some(MosaicPanelInfo {
            mosaic_name: "M31 Mosaic".to_string(),
            panel_index: 2,
            total_panels: 9,
            row: 0,
            column: 2,
        });
        let label = ctx.log_label();
        // Panel index is 0-based internally; display_label adds 1.
        assert!(label.contains("M31"));
        assert!(label.contains("Panel 3/9"));
        assert!(label.contains("L"));
    }

    #[test]
    fn log_label_falls_back_when_target_or_filter_missing() {
        let ctx = FrameContext::new_light("s", 1, 1, 60.0, 1);
        let label = ctx.log_label();
        assert!(label.contains("(no-target)"));
        assert!(label.contains("(no-filter)"));
    }

    #[test]
    fn serde_roundtrip_preserves_all_fields() {
        let mut ctx = FrameContext::new_light("sess-123", 2, 2, 30.5, 5);
        ctx.target_id = Some("tgt-uuid".to_string());
        ctx.target_name = Some("NGC 7000".to_string());
        ctx.target_ra_hours = Some(20.967);
        ctx.target_dec_degrees = Some(44.333);
        ctx.filter_name = Some("Ha".to_string());
        ctx.filter_index = Some(5);
        ctx.gain = Some(100);
        ctx.offset = Some(50);
        ctx.total_planned_frames = Some(20);
        ctx.sensor_temp_c = Some(-10.5);
        ctx.set_temp_c = Some(-10.0);
        ctx.focuser_position = Some(25_400);
        ctx.focuser_temperature_c = Some(12.3);
        ctx.rotator_angle_deg = Some(123.7);
        ctx.guide_rms_arcsec = Some(0.78);
        ctx.plate_solve_ra_hours = Some(20.9669);
        ctx.plate_solve_dec_degrees = Some(44.3322);
        ctx.plate_solve_pixel_scale_arcsec = Some(1.42);
        ctx.plate_solve_rotation_deg = Some(-1.3);
        ctx.bayer_pattern = Some("RGGB".to_string());
        ctx.mosaic_panel = Some(MosaicPanelInfo {
            mosaic_name: "NGC 7000 Mosaic".to_string(),
            panel_index: 1,
            total_panels: 4,
            row: 0,
            column: 1,
        });
        ctx.observer_name = Some("Test Observer".to_string());
        ctx.site_latitude_deg = Some(40.0);
        ctx.site_longitude_deg = Some(-75.0);
        ctx.site_elevation_m = Some(200.0);
        ctx.camera_make = Some("ZWO".to_string());
        ctx.camera_model = Some("ASI2600MM Pro".to_string());
        ctx.telescope_name = Some("Askar 65PHQ".to_string());
        ctx.telescope_focal_length_mm = Some(416.0);
        ctx.telescope_aperture_mm = Some(65.0);

        let json = serde_json::to_string(&ctx).expect("serialize");
        let back: FrameContext = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(back.session_id, ctx.session_id);
        assert_eq!(back.target_id, ctx.target_id);
        assert_eq!(back.target_name, ctx.target_name);
        assert_eq!(back.target_ra_hours, ctx.target_ra_hours);
        assert_eq!(back.target_dec_degrees, ctx.target_dec_degrees);
        assert_eq!(back.filter_name, ctx.filter_name);
        assert_eq!(back.filter_index, ctx.filter_index);
        assert_eq!(back.binning_x, ctx.binning_x);
        assert_eq!(back.binning_y, ctx.binning_y);
        assert_eq!(back.gain, ctx.gain);
        assert_eq!(back.offset, ctx.offset);
        assert!((back.duration_secs - ctx.duration_secs).abs() < f64::EPSILON);
        assert_eq!(back.frame_index, ctx.frame_index);
        assert_eq!(back.total_planned_frames, ctx.total_planned_frames);
        assert_eq!(back.sensor_temp_c, ctx.sensor_temp_c);
        assert_eq!(back.set_temp_c, ctx.set_temp_c);
        assert_eq!(back.focuser_position, ctx.focuser_position);
        assert_eq!(back.rotator_angle_deg, ctx.rotator_angle_deg);
        assert_eq!(back.guide_rms_arcsec, ctx.guide_rms_arcsec);
        assert_eq!(back.plate_solve_ra_hours, ctx.plate_solve_ra_hours);
        assert_eq!(back.plate_solve_dec_degrees, ctx.plate_solve_dec_degrees);
        assert_eq!(
            back.plate_solve_pixel_scale_arcsec,
            ctx.plate_solve_pixel_scale_arcsec
        );
        assert_eq!(back.bayer_pattern, ctx.bayer_pattern);
        let panel_back = back.mosaic_panel.as_ref().expect("mosaic preserved");
        let panel_orig = ctx.mosaic_panel.as_ref().unwrap();
        assert_eq!(panel_back.mosaic_name, panel_orig.mosaic_name);
        assert_eq!(panel_back.panel_index, panel_orig.panel_index);
        assert_eq!(panel_back.total_panels, panel_orig.total_panels);
        assert_eq!(panel_back.row, panel_orig.row);
        assert_eq!(panel_back.column, panel_orig.column);
        assert_eq!(back.observer_name, ctx.observer_name);
        assert_eq!(back.site_latitude_deg, ctx.site_latitude_deg);
        assert_eq!(back.site_longitude_deg, ctx.site_longitude_deg);
        assert_eq!(back.site_elevation_m, ctx.site_elevation_m);
        assert_eq!(back.camera_make, ctx.camera_make);
        assert_eq!(back.camera_model, ctx.camera_model);
        assert_eq!(back.telescope_name, ctx.telescope_name);
        assert_eq!(
            back.telescope_focal_length_mm,
            ctx.telescope_focal_length_mm
        );
        assert_eq!(back.telescope_aperture_mm, ctx.telescope_aperture_mm);
        assert_eq!(back.frame_type, ctx.frame_type);
    }
}
