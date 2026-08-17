//! Round-trip tests for the Darkroom surface: every entry point against a
//! synthetic master written to a temporary FITS, plus the cross-check that keeps
//! the published parameter schema honest against each operation's own
//! validation.

use std::path::{Path, PathBuf};

use nightshade_imaging::recipe::{
    canonical_json, fingerprint_hex, OpRegistry, RECIPE_SCHEMA_VERSION,
};
use nightshade_imaging::{read_fits, write_fits, FitsHeader, ImageData};
use serde_json::{json, Value};

use super::export::recipe_from_history;
use super::schema::{example_params, ParamKind, OP_DOCS};
use super::{
    api_darkroom_cancel, api_darkroom_registry, api_darkroom_render_export,
    api_darkroom_render_preview, api_darkroom_validate,
};

// ---------------------------------------------------------------------------
// Synthetic master
// ---------------------------------------------------------------------------

/// A deterministic linear congruential generator, so a test image is
/// reproducible without a random dependency.
struct Lcg(u64);

impl Lcg {
    fn next_unit(&mut self) -> f64 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        ((self.0 >> 11) as f64) / ((1u64 << 53) as f64)
    }
}

/// A synthetic linear master: a pedestal, Gaussian-ish noise and a lattice of
/// round stars, in `F32` ADU, carrying a complete CD-only WCS.
fn write_master(dir: &Path, name: &str, width: u32, height: u32, channels: u32) -> PathBuf {
    let mut rng = Lcg(0x51ED_2701_C0FF_EE01);
    let pedestal = 1000.0_f32;
    let mut data = vec![0.0_f32; (width * height * channels) as usize];
    for sample in data.iter_mut() {
        let noise = (rng.next_unit() + rng.next_unit() + rng.next_unit() - 1.5) * 60.0;
        *sample = pedestal + noise as f32;
    }
    for star_y in (8..height).step_by(19) {
        for star_x in (8..width).step_by(23) {
            for dy in -3i32..=3 {
                for dx in -3i32..=3 {
                    let x = star_x as i32 + dx;
                    let y = star_y as i32 + dy;
                    if x < 0 || y < 0 || x >= width as i32 || y >= height as i32 {
                        continue;
                    }
                    let radius2 = (dx * dx + dy * dy) as f64;
                    let flux = 4000.0 * (-radius2 / 2.5).exp();
                    for channel in 0..channels {
                        let index = ((y as u32 * width + x as u32) * channels + channel) as usize;
                        data[index] += flux as f32;
                    }
                }
            }
        }
    }

    let mut header = FitsHeader::new();
    header.set_string("OBJECT", "NGC 7000");
    header.set_string("FILTER", "L");
    header.set_string("DATE-OBS", "2026-08-16T03:14:15");
    header.set_float("EXPTIME", 300.0);
    header.set_float("CRVAL1", 314.75);
    header.set_float("CRVAL2", 44.5);
    header.set_float("CRPIX1", (width as f64 + 1.0) / 2.0);
    header.set_float("CRPIX2", (height as f64 + 1.0) / 2.0);
    header.set_float("CD1_1", -0.000_5);
    header.set_float("CD1_2", 0.0);
    header.set_float("CD2_1", 0.0);
    header.set_float("CD2_2", 0.000_5);
    header.set_string("CTYPE1", "RA---TAN");
    header.set_string("CTYPE2", "DEC--TAN");

    let image = ImageData::from_f32(width, height, channels, &data);
    let path = dir.join(name);
    write_fits(&path, &image, &header).expect("the synthetic master must write");
    path
}

/// A recipe payload in the wire form the engine reads.
fn recipe_json(id: &str, base_ref: &str, steps: Value) -> String {
    json!({
        "id": id,
        "schemaVersion": RECIPE_SCHEMA_VERSION,
        "baseMasterRef": base_ref,
        "createdBy": "user",
        "steps": steps,
    })
    .to_string()
}

/// A stretch step whose points bracket the synthetic master's own range.
fn stretch_step() -> Value {
    json!({
        "opId": "stretch",
        "opVersion": 1,
        "params": {"blackPoint": 800.0, "whitePoint": 3000.0, "d": 1.5},
        "enabled": true,
    })
}

fn parse(text: &str) -> Value {
    serde_json::from_str(text).expect("the reply must be JSON")
}

// ---------------------------------------------------------------------------
// validate
// ---------------------------------------------------------------------------

#[test]
fn validate_accepts_a_registered_recipe_and_reports_the_master() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "validate.fits", 64, 64, 1);
    let recipe = recipe_json("r-validate", "master:validate", json!([stretch_step()]));

    let reply = parse(
        &api_darkroom_validate(
            recipe,
            json!({"masterPath": master.to_string_lossy()}).to_string(),
        )
        .expect("validation must run"),
    );

    assert_eq!(reply["ok"], json!(true), "reply: {reply}");
    assert!(reply["error"].is_null());
    assert_eq!(reply["steps"][0]["registered"], json!(true));
    assert_eq!(reply["steps"][0]["stage"], json!("stretched"));
    assert_eq!(reply["base"]["channels"], json!(1));
    assert_eq!(reply["base"]["hasWcs"], json!(true));
}

#[test]
fn validate_names_every_bad_step_rather_than_only_the_first() {
    let recipe = recipe_json(
        "r-bad",
        "master:bad",
        json!([
            {"opId": "no_such_op", "opVersion": 1, "params": {}, "enabled": true},
            {"opId": "denoise", "opVersion": 1, "params": {"strength": 9.0}, "enabled": true},
        ]),
    );

    let reply =
        parse(&api_darkroom_validate(recipe, "{}".to_string()).expect("validation must run"));

    assert_eq!(reply["ok"], json!(false));
    assert_eq!(reply["steps"][0]["registered"], json!(false));
    assert_eq!(reply["steps"][1]["registered"], json!(true));
    assert_eq!(reply["steps"][1]["valid"], json!(false));
    assert!(
        reply["steps"][1]["error"]
            .as_str()
            .is_some_and(|text| text.contains("strength")),
        "reply: {reply}"
    );
}

#[test]
fn validate_rejects_a_linear_step_after_a_stretch() {
    let recipe = recipe_json(
        "r-order",
        "master:order",
        json!([
            stretch_step(),
            {"opId": "denoise", "opVersion": 1, "params": {}, "enabled": true},
        ]),
    );

    let reply =
        parse(&api_darkroom_validate(recipe, "{}".to_string()).expect("validation must run"));

    assert_eq!(reply["ok"], json!(false));
    assert!(
        reply["error"]
            .as_str()
            .is_some_and(|text| text.contains("linear-stage")),
        "reply: {reply}"
    );
}

#[test]
fn a_disabled_step_this_build_cannot_run_is_flagged_yet_still_renders() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "disabled-unknown.fits", 64, 64, 1);
    let recipe = recipe_json(
        "r-disabled-unknown",
        "master:disabled-unknown",
        json!([
            stretch_step(),
            {"opId": "no_such_op", "opVersion": 7, "params": {}, "enabled": false},
        ]),
    );

    let reply = parse(
        &api_darkroom_validate(recipe.clone(), "{}".to_string()).expect("validation must run"),
    );
    assert_eq!(
        reply["ok"],
        json!(true),
        "a step that will not run blocks no render: {reply}"
    );
    assert!(reply["error"].is_null(), "reply: {reply}");
    assert_eq!(reply["steps"][0]["registered"], json!(true));
    assert_eq!(
        reply["steps"][1]["registered"],
        json!(false),
        "the step is still named as one this build cannot run: {reply}"
    );
    assert_eq!(reply["steps"][1]["enabled"], json!(false));

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy()}).to_string(),
    )
    .expect("the enabled prefix renders over the disabled step");

    let report = parse(&preview.report_json);
    assert_eq!(report["report"]["steps"][0]["outcome"], json!("applied"));
    assert_eq!(report["report"]["steps"][1]["outcome"], json!("disabled"));
    assert_eq!(report["report"]["hasSkips"], json!(false));
}

#[test]
fn validate_refuses_a_payload_that_is_not_a_recipe() {
    let error = api_darkroom_validate("{\"nope\": 1}".to_string(), "{}".to_string())
        .expect_err("a payload with no schema version is not a recipe");
    assert!(error.contains("schemaVersion"), "error: {error}");
}

// ---------------------------------------------------------------------------
// preview
// ---------------------------------------------------------------------------

#[test]
fn preview_returns_the_rgba_buffer_the_viewer_takes() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "preview.fits", 64, 64, 1);
    let recipe = recipe_json("r-preview", "master:preview", json!([stretch_step()]));

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy()}).to_string(),
    )
    .expect("the preview must render");

    assert_eq!(preview.width, 64);
    assert_eq!(preview.height, 64);
    assert!(!preview.is_color);
    assert_eq!(preview.rgba.len(), 64 * 64 * 4);
    assert!(
        preview.rgba.chunks_exact(4).all(|pixel| pixel[3] == 255),
        "every pixel is opaque"
    );
    assert!(
        preview.rgba.chunks_exact(4).any(|pixel| pixel[0] > 0),
        "a stretched star field is not black"
    );

    let report = parse(&preview.report_json);
    assert_eq!(report["report"]["steps"][0]["outcome"], json!("applied"));
    assert_eq!(report["encoding"]["applied"], json!("unit"));
    assert_eq!(report["encoding"]["sourceDomain"], json!("stretched"));
    assert_eq!(report["level"]["level"], json!(0));
}

#[test]
fn preview_renders_the_pyramid_level_a_viewport_needs() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "level.fits", 256, 192, 1);
    let recipe = recipe_json("r-level", "master:level", json!([stretch_step()]));

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy(), "maxDimension": 128}).to_string(),
    )
    .expect("the preview must render");

    let report = parse(&preview.report_json);
    assert_eq!(report["level"]["level"], json!(1));
    assert_eq!(preview.width, 128);
    assert_eq!(preview.height, 96);
    assert_eq!(report["level"]["scaleFromMaster"], json!(0.5));
}

#[test]
fn preview_stopping_after_a_step_renders_only_that_prefix() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "stop.fits", 64, 64, 1);
    let recipe = recipe_json(
        "r-stop",
        "master:stop",
        json!([
            {"opId": "denoise", "opVersion": 1, "params": {}, "enabled": true},
            stretch_step(),
        ]),
    );

    let preview = api_darkroom_render_preview(
        recipe,
        json!({
            "masterPath": master.to_string_lossy(),
            "stopAfter": 0,
            "encoding": "screen",
        })
        .to_string(),
    )
    .expect("the preview must render");

    let report = parse(&preview.report_json);
    assert_eq!(report["report"]["steps"].as_array().map(Vec::len), Some(1));
    assert_eq!(report["report"]["steps"][0]["opId"], json!("denoise"));
    assert_eq!(report["stopAfter"], json!(0));
    assert_eq!(report["encoding"]["sourceDomain"], json!("linear"));
}

#[test]
fn preview_of_a_linear_stack_names_the_screen_transfer_it_applied() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "linear.fits", 64, 64, 1);
    let recipe = recipe_json("r-linear", "master:linear", json!([]));

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy()}).to_string(),
    )
    .expect("the preview must render");

    let report = parse(&preview.report_json);
    assert_eq!(report["encoding"]["applied"], json!("screen"));
    assert_eq!(report["encoding"]["sourceDomain"], json!("linear"));
    assert_eq!(
        report["encoding"]["screenTransferAffectsRecipe"],
        json!(false)
    );
    assert!(
        report["encoding"]["screenTransfer"]["blackPoint"].is_number(),
        "the transfer names its own parameters: {report}"
    );
}

#[test]
fn preview_records_a_skipped_step_with_the_reason_it_could_not_run() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "skip.fits", 64, 64, 3);
    let recipe = recipe_json(
        "r-skip",
        "master:skip",
        json!([{"opId": "color_calibrate", "opVersion": 1, "params": {}, "enabled": true}]),
    );

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy()}).to_string(),
    )
    .expect("a skipped step is not a failed render");

    assert!(preview.is_color);
    let report = parse(&preview.report_json);
    assert_eq!(report["report"]["steps"][0]["outcome"], json!("skipped"));
    assert_eq!(report["report"]["hasSkips"], json!(true));
    assert_eq!(report["catalogStars"], json!(0));
    assert!(
        report["report"]["steps"][0]["reason"]
            .as_str()
            .is_some_and(|reason| !reason.is_empty()),
        "a skip states its reason: {report}"
    );
}

#[test]
fn preview_reports_the_channel_scales_a_colour_step_applied() {
    // The read-back the draft pins from. A pinned step reads no catalogue and no
    // plate solve, so this exercises the whole path — entry point, engine, step
    // report — with nothing to fit and nothing to be flaky about.
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "pinned.fits", 64, 64, 3);
    let recipe = recipe_json(
        "r-pinned",
        "master:pinned",
        json!([
            {"opId": "denoise", "opVersion": 1, "params": {}, "enabled": true},
            {
                "opId": "color_calibrate",
                "opVersion": 1,
                "params": {"channelScale": [1.5, 1.0, 0.8]},
                "enabled": true,
            },
        ]),
    );

    let preview = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy()}).to_string(),
    )
    .expect("a pinned balance renders with no photometry");

    let report = parse(&preview.report_json);
    let colour = &report["report"]["steps"][1];
    assert_eq!(colour["opId"], json!("color_calibrate"));
    assert_eq!(colour["outcome"], json!("applied"));
    assert_eq!(colour["measured"]["source"], json!("pinned"));
    assert_eq!(colour["measured"]["channelScale"], json!([1.5, 1.0, 0.8]));
    assert!(
        report["report"]["steps"][0].get("measured").is_none(),
        "an operation whose parameters describe its result reports no measurement: {report}"
    );
}

#[test]
fn preview_refuses_an_encoding_it_does_not_know() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "encoding.fits", 64, 64, 1);
    let recipe = recipe_json("r-encoding", "master:encoding", json!([]));

    let error = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy(), "encoding": "eyeball"}).to_string(),
    )
    .expect_err("an unknown encoding is refused, never defaulted");
    assert!(error.contains("eyeball"), "error: {error}");
}

// ---------------------------------------------------------------------------
// cancellation
// ---------------------------------------------------------------------------

#[test]
fn a_cancelled_preview_returns_the_typed_cancelled_shape() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "cancel.fits", 64, 64, 1);
    let render_id = "darkroom-test-cancel-preview";

    let armed = parse(
        &api_darkroom_cancel(json!({"renderId": render_id}).to_string())
            .expect("pre-arming must succeed"),
    );
    assert_eq!(armed["cancelRequested"], json!(true));
    assert_eq!(armed["running"], json!(false));

    let recipe = recipe_json("r-cancel", "master:cancel", json!([stretch_step()]));
    let error = api_darkroom_render_preview(
        recipe,
        json!({"masterPath": master.to_string_lossy(), "renderId": render_id}).to_string(),
    )
    .expect_err("a pre-armed render stops at its first check");

    let outcome = parse(&error);
    assert_eq!(outcome["kind"], json!("cancelled"));
    assert_eq!(outcome["renderId"], json!(render_id));
    assert!(outcome["phase"].is_string(), "outcome: {outcome}");
}

#[test]
fn a_cancelled_export_writes_nothing_and_says_it_was_cancelled() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "cancel-export.fits", 64, 64, 1);
    let out = dir.path().join("cancelled.fits");
    let render_id = "darkroom-test-cancel-export";
    api_darkroom_cancel(json!({"renderId": render_id}).to_string()).expect("pre-arm");

    let recipe = recipe_json("r-cancel-x", "master:cancel-x", json!([stretch_step()]));
    let error = api_darkroom_render_export(
        recipe,
        json!({
            "masterPath": master.to_string_lossy(),
            "renderId": render_id,
            "stage": {"kind": "final"},
            "outputs": [{"format": "fits", "path": out.to_string_lossy()}],
        })
        .to_string(),
    )
    .expect_err("a pre-armed export stops before it writes");

    let outcome = parse(&error);
    assert_eq!(outcome["kind"], json!("cancelled"));
    assert!(!out.exists(), "a cancelled export leaves no file behind");
}

#[test]
fn cancel_status_and_clear_round_trip() {
    let render_id = "darkroom-test-status";
    api_darkroom_cancel(json!({"renderId": render_id}).to_string()).expect("cancel");

    let status = parse(
        &api_darkroom_cancel(json!({"op": "status", "renderId": render_id}).to_string())
            .expect("status"),
    );
    assert_eq!(status["cancelRequested"], json!(true));

    let cleared = parse(
        &api_darkroom_cancel(json!({"op": "clear", "renderId": render_id}).to_string())
            .expect("clear"),
    );
    assert_eq!(cleared["cancelRequested"], json!(false));

    let after = parse(
        &api_darkroom_cancel(json!({"op": "status", "renderId": render_id}).to_string())
            .expect("status"),
    );
    assert_eq!(after["cancelRequested"], json!(false));

    let error = api_darkroom_cancel(json!({"op": "levitate", "renderId": render_id}).to_string())
        .expect_err("an unknown op is refused");
    assert!(error.contains("levitate"), "error: {error}");
}

// ---------------------------------------------------------------------------
// export
// ---------------------------------------------------------------------------

#[test]
fn export_writes_the_recipe_into_the_fits_and_beside_it() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "export.fits", 64, 64, 1);
    let out = dir.path().join("final.fits");
    let recipe = recipe_json("r-export", "master:export", json!([stretch_step()]));

    let reply = parse(
        &api_darkroom_render_export(
            recipe.clone(),
            json!({
                "masterPath": master.to_string_lossy(),
                "stage": {"kind": "final"},
                "outputs": [{"format": "fits", "path": out.to_string_lossy()}],
            })
            .to_string(),
        )
        .expect("the export must run"),
    );

    assert_eq!(reply["stage"]["kind"], json!("final"));
    assert_eq!(reply["outputs"][0]["format"], json!("fits"));
    assert_eq!(reply["outputs"][0]["pixelType"], json!("f32"));
    assert!(out.exists());

    let (_, header) = read_fits(&out).expect("the exported master must read back");
    assert_eq!(header.get_string("NSSTAGE"), Some("final"));
    assert_eq!(
        header.get_string("NSRECIPE"),
        reply["recipeFingerprint"].as_str()
    );
    assert_eq!(header.get_int("NSRECSTP"), Some(1));
    assert_eq!(
        header.get_int("NSRECVER"),
        Some(i64::from(RECIPE_SCHEMA_VERSION))
    );
    assert_eq!(header.get_string("OBJECT"), Some("NGC 7000"));
    assert_eq!(header.get_float("CRVAL1"), Some(314.75));

    let recovered = recipe_from_history(&header.history)
        .expect("the recipe reads back out of the HISTORY cards");
    let expected = canonical_json(&parse(&recipe));
    assert_eq!(recovered, expected);
    assert_eq!(
        fingerprint_hex(recovered.as_bytes()),
        reply["recipeFingerprint"]
            .as_str()
            .expect("the reply names the recipe fingerprint")
    );
    assert!(
        header
            .history
            .iter()
            .any(|line| line.contains("stretch@1 applied")),
        "the readable lines name each step: {:?}",
        header.history
    );

    let sidecar_path = reply["sidecarPath"]
        .as_str()
        .expect("a sidecar is written beside the FITS");
    assert!(sidecar_path.ends_with("final.fits.nsrecipe"));
    let sidecar = parse(&std::fs::read_to_string(sidecar_path).expect("sidecar reads"));
    assert_eq!(sidecar["kind"], json!("nsrecipe"));
    assert_eq!(
        sidecar["fingerprint"].as_str(),
        reply["recipeFingerprint"].as_str()
    );
    assert_eq!(sidecar["canonicalRecipe"], json!(expected));
}

#[test]
fn export_of_the_linear_stage_writes_the_masters_own_pixels() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "linear-source.fits", 64, 64, 1);
    let out = dir.path().join("linear-master.fits");
    let recipe = recipe_json("r-linear-x", "master:linear-x", json!([stretch_step()]));

    let reply = parse(
        &api_darkroom_render_export(
            recipe,
            json!({
                "masterPath": master.to_string_lossy(),
                "stage": {"kind": "linear"},
                "outputs": [{"format": "fits", "path": out.to_string_lossy()}],
            })
            .to_string(),
        )
        .expect("the export must run"),
    );

    assert_eq!(reply["stage"]["kind"], json!("linear"));
    assert_eq!(reply["report"]["steps"], json!([]));

    let (source, _) = read_fits(&master).expect("master reads");
    let (written, header) = read_fits(&out).expect("export reads");
    assert_eq!(written.data, source.data, "linear export is a passthrough");
    assert_eq!(header.get_string("NSSTAGE"), Some("linear"));
    assert!(
        header
            .history
            .iter()
            .any(|line| line.contains("Linear master passthrough")),
        "the export says no step ran: {:?}",
        header.history
    );
}

#[test]
fn export_after_a_step_stops_the_stack_there() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "stage-source.fits", 64, 64, 1);
    let out = dir.path().join("stage.fits");
    let recipe = recipe_json(
        "r-stage",
        "master:stage",
        json!([
            {"opId": "denoise", "opVersion": 1, "params": {}, "enabled": true},
            stretch_step(),
        ]),
    );

    let reply = parse(
        &api_darkroom_render_export(
            recipe,
            json!({
                "masterPath": master.to_string_lossy(),
                "stage": {"kind": "afterStep", "index": 0},
                "outputs": [{"format": "fits", "path": out.to_string_lossy()}],
            })
            .to_string(),
        )
        .expect("the export must run"),
    );

    assert_eq!(reply["stage"], json!({"kind": "afterStep", "index": 0}));
    assert_eq!(reply["report"]["steps"].as_array().map(Vec::len), Some(1));
    assert_eq!(reply["sourceDomain"], json!("linear"));

    let (_, header) = read_fits(&out).expect("export reads");
    assert_eq!(header.get_string("NSSTAGE"), Some("afterStep:0"));
}

#[test]
fn export_refuses_an_eight_bit_file_of_linear_pixels() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "refuse-source.fits", 64, 64, 1);
    let out = dir.path().join("refused.png");
    let recipe = recipe_json("r-refuse", "master:refuse", json!([]));

    let error = api_darkroom_render_export(
        recipe,
        json!({
            "masterPath": master.to_string_lossy(),
            "stage": {"kind": "final"},
            "outputs": [{"format": "png", "path": out.to_string_lossy()}],
        })
        .to_string(),
    )
    .expect_err("linear pixels have no display mapping");

    assert!(error.contains("screenTransfer"), "error: {error}");
    assert!(!out.exists());
}

#[test]
fn export_writes_every_raster_format_from_the_engines_own_pixels() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "raster-source.fits", 64, 64, 1);
    let png = dir.path().join("out.png");
    let jpeg = dir.path().join("out.jpg");
    let tiff = dir.path().join("out.tif");
    let recipe = recipe_json("r-raster", "master:raster", json!([stretch_step()]));

    let reply = parse(
        &api_darkroom_render_export(
            recipe,
            json!({
                "masterPath": master.to_string_lossy(),
                "stage": {"kind": "final"},
                "outputs": [
                    {"format": "png", "path": png.to_string_lossy()},
                    {"format": "jpeg", "path": jpeg.to_string_lossy(), "quality": 85},
                    {"format": "tiff", "path": tiff.to_string_lossy()},
                ],
            })
            .to_string(),
        )
        .expect("the export must run"),
    );

    for path in [&png, &jpeg, &tiff] {
        assert!(path.exists(), "{} must exist", path.display());
        let size = std::fs::metadata(path).expect("stat").len();
        assert!(size > 0, "{} must carry bytes", path.display());
    }
    assert_eq!(reply["outputs"][0]["bitsPerSample"], json!(16));
    assert_eq!(reply["outputs"][1]["quality"], json!(85));
    assert_eq!(reply["sourceDomain"], json!("stretched"));
    assert!(reply["screenTransfer"].is_null());
    assert_eq!(
        reply["sidecarSkippedReason"],
        json!("no FITS output to place the sidecar beside and no sidecarPath given")
    );
}

#[test]
fn export_with_a_screen_transfer_names_the_transfer_it_used() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "screen-source.fits", 64, 64, 1);
    let png = dir.path().join("screen.png");
    let sidecar = dir.path().join("screen.nsrecipe");
    let recipe = recipe_json("r-screen", "master:screen", json!([]));

    let reply = parse(
        &api_darkroom_render_export(
            recipe,
            json!({
                "masterPath": master.to_string_lossy(),
                "stage": {"kind": "final"},
                "screenTransfer": true,
                "sidecarPath": sidecar.to_string_lossy(),
                "outputs": [{"format": "png", "path": png.to_string_lossy()}],
            })
            .to_string(),
        )
        .expect("the export must run"),
    );

    assert!(png.exists());
    assert!(sidecar.exists());
    assert_eq!(reply["sourceDomain"], json!("linear"));
    assert!(
        reply["screenTransfer"]["whitePoint"].is_number(),
        "reply: {reply}"
    );
    assert_eq!(reply["screenTransferAffectsRecipe"], json!(false));
}

#[test]
fn export_refuses_a_request_that_writes_nothing() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "empty-out.fits", 64, 64, 1);
    let recipe = recipe_json("r-empty", "master:empty", json!([]));

    let error = api_darkroom_render_export(
        recipe,
        json!({"masterPath": master.to_string_lossy(), "outputs": []}).to_string(),
    )
    .expect_err("an export with no output is refused");
    assert!(error.contains("outputs"), "error: {error}");
}

// ---------------------------------------------------------------------------
// registry
// ---------------------------------------------------------------------------

#[test]
fn registry_publishes_every_registered_operation() {
    let reply = parse(&api_darkroom_registry("{}".to_string()).expect("the catalogue must build"));
    let registry = OpRegistry::builtin().expect("the builtin registry must build");

    let ops = reply["ops"].as_array().expect("ops is a list");
    assert_eq!(ops.len(), registry.len());
    for op in ops {
        let id = op["id"].as_str().expect("id");
        let version = op["version"].as_u64().expect("version") as u32;
        let registered = registry
            .get(id, version)
            .unwrap_or_else(|| panic!("{id}@{version} is documented and must be registered"));
        assert_eq!(op["stage"], json!(registered.stage().as_wire()));
        assert!(op["params"].is_array());
        assert!(op["defaults"].is_object());
    }
    assert_eq!(
        reply["cacheBudget"]["renderBytes"],
        json!(super::state::RENDER_CACHE_CAPACITY_BYTES)
    );
}

#[test]
fn every_registered_operation_is_documented() {
    let registry = OpRegistry::builtin().expect("the builtin registry must build");
    for (id, version) in registry.keys() {
        assert!(
            OP_DOCS
                .iter()
                .any(|doc| doc.id == id && doc.version == version),
            "{id}@{version} is registered and must carry a schema row"
        );
    }
}

#[test]
fn the_published_schema_matches_each_operations_own_validation() {
    let registry = OpRegistry::builtin().expect("the builtin registry must build");
    for doc in OP_DOCS {
        let op = registry
            .get(doc.id, doc.version)
            .unwrap_or_else(|| panic!("{}@{} must be registered", doc.id, doc.version));
        let example = example_params(doc).expect("the example payload must parse");
        op.validate_params(&example).unwrap_or_else(|error| {
            panic!(
                "{}@{} rejects its own example: {error}",
                doc.id, doc.version
            )
        });

        let mut unknown = example.clone();
        unknown["notAParameterOfThisOperation"] = json!(1);
        assert!(
            op.validate_params(&unknown).is_err(),
            "{}@{} must reject an undeclared key",
            doc.id,
            doc.version
        );

        for param in doc.params {
            let mut without = example.clone();
            let object = without.as_object_mut().expect("example is an object");
            object.remove(param.name);
            let verdict = op.validate_params(&without);
            if param.required {
                assert!(
                    verdict.is_err(),
                    "{}@{}: '{}' is documented as required and must be rejected when absent",
                    doc.id,
                    doc.version,
                    param.name
                );
            } else {
                verdict.unwrap_or_else(|error| {
                    panic!(
                        "{}@{}: '{}' is documented as optional and must be accepted when absent: {error}",
                        doc.id, doc.version, param.name
                    )
                });
            }

            if !param.independent {
                continue;
            }
            if let (Some(min), Some(max)) = (param.min, param.max) {
                for (value, accepted) in [
                    (bounded(param, min), true),
                    (bounded(param, max), true),
                    (bounded(param, min - 1.0), false),
                    (bounded(param, max + 1.0), false),
                ] {
                    let mut probe = example.clone();
                    probe[param.name] = value.clone();
                    let verdict = op.validate_params(&probe);
                    assert_eq!(
                        verdict.is_ok(),
                        accepted,
                        "{}@{}: '{}' at {value} must be {}",
                        doc.id,
                        doc.version,
                        param.name,
                        if accepted { "accepted" } else { "rejected" }
                    );
                }
            }
            if param.kind == ParamKind::Enumerated {
                for token in param.allowed {
                    let mut probe = example.clone();
                    probe[param.name] = json!(token);
                    op.validate_params(&probe).unwrap_or_else(|error| {
                        panic!(
                            "{}@{}: '{token}' is documented as allowed: {error}",
                            doc.id, doc.version
                        )
                    });
                }
                let mut probe = example.clone();
                probe[param.name] = json!("notAnAllowedToken");
                assert!(
                    op.validate_params(&probe).is_err(),
                    "{}@{}: an undocumented token must be rejected",
                    doc.id,
                    doc.version
                );
            }
        }
    }
}

/// One probe value in the shape the parameter's kind takes.
fn bounded(param: &super::schema::ParamDoc, value: f64) -> Value {
    match param.kind {
        ParamKind::Integer => {
            if value < 0.0 {
                json!(value)
            } else {
                json!(value as u64)
            }
        }
        ParamKind::NumberArray => {
            let length = param
                .length
                .expect("a numberArray parameter documents its element count");
            json!(vec![value; length])
        }
        _ => json!(value),
    }
}

#[test]
fn registry_drafts_a_recipe_that_validates_against_this_build() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "draft.fits", 512, 512, 1);

    let reply = parse(
        &api_darkroom_registry(
            json!({
                "masterPath": master.to_string_lossy(),
                "recipeId": "draft-1",
                "baseMasterRef": "master:draft",
            })
            .to_string(),
        )
        .expect("the draft must build"),
    );

    let draft = &reply["draft"]["recipe"];
    assert_eq!(draft["createdBy"], json!("autopilot"));
    assert_eq!(draft["id"], json!("draft-1"));
    let steps = draft["steps"].as_array().expect("steps");
    assert!(!steps.is_empty(), "reply: {reply}");
    assert_eq!(
        steps.last().map(|step| step["opId"].clone()),
        Some(json!("stretch")),
        "the draft ends in the stretch it measured: {reply}"
    );
    assert!(reply["draft"]["autoParams"]["cropRect"]["width"].is_number());
    assert!(reply["draft"]["autoParams"]["stretch"]["blackPoint"].is_number());
    assert!(reply["draft"]["autoParams"]["defaults"]["denoise"]["strength"].is_number());
    assert!(
        reply["draft"]["notes"].as_array().is_some_and(|notes| notes
            .iter()
            .any(|note| note["opId"] == json!("color_calibrate"))),
        "a mono master records why the colour fit is left out: {reply}"
    );

    let verdict = parse(
        &api_darkroom_validate(draft.to_string(), "{}".to_string()).expect("validation must run"),
    );
    assert_eq!(verdict["ok"], json!(true), "verdict: {verdict}");
}

#[test]
fn a_drafted_recipe_renders_over_its_own_master() {
    let dir = tempfile::tempdir().expect("temp dir");
    let master = write_master(dir.path(), "draft-render.fits", 512, 512, 1);
    let reply = parse(
        &api_darkroom_registry(
            json!({"masterPath": master.to_string_lossy(), "recipeId": "draft-2"}).to_string(),
        )
        .expect("the draft must build"),
    );

    let preview = api_darkroom_render_preview(
        reply["draft"]["recipe"].to_string(),
        json!({"masterPath": master.to_string_lossy(), "maxDimension": 256}).to_string(),
    )
    .expect("the drafted recipe must render");

    let report = parse(&preview.report_json);
    let steps = report["report"]["steps"].as_array().expect("steps");
    assert!(
        steps
            .iter()
            .all(|step| step["outcome"] != json!("skipped") || step["reason"].is_string()),
        "every skip carries its reason: {report}"
    );
    assert_eq!(report["encoding"]["sourceDomain"], json!("stretched"));
}
