//! Synthetic frame generation for the simulator camera.
//!
//! Extracted from the `DriverType::Simulator` download arm so the frame can be
//! run through the REAL star detector in a unit test. That matters more than
//! usual here: every focus, HFR and grading result an operator sees while
//! evaluating Nightshade without hardware is measured against this buffer, so if
//! it is not detectable-star-bearing, those subsystems silently report nothing
//! and the simulator quietly teaches the wrong thing.
//!
//! History: the original buffer was all zeros, which `[IMAGE_VALIDATION]`
//! correctly rejected as a dead frame, so no simulated sequence could run. That
//! was replaced by a faint gradient plus four flat 6x6 blocks of 50,000 ADU —
//! enough to pass validation, but the detector found NONE of them (every frame
//! logged "no stars detected for HFR calculation", autofocus died with
//! "Insufficient stars detected. Only 0 stars found (minimum: 10)", and the
//! HFR-degradation / focus-drift triggers had nothing to measure). Hence the
//! Gaussian field below, plus the tests that hold it to the detector's bar.
//!
//! The gradient that replaced the zeros was itself a defect: `200 + ((x+y)%400)`
//! is a diagonal sawtooth, not noise, and nothing about it moved when exposure,
//! gain or offset changed — an 8 s / gain 0 frame and a 2 s / gain 120 frame were
//! 99.7% bit-identical, spanning 442 of 65,536 ADU. Saturation, clipping, well
//! depth, calibration-frame quality and defect maps therefore could not fire at
//! all, and subtracting such a frame as a master dark injected a diagonal ramp
//! into every calibrated light. The model below is instead built out of
//! electrons: a bias pedestal, dark current and sky that accumulate with
//! exposure, stars that accumulate only on light frames, shot and read noise,
//! and a hard clip at the sensor's advertised ceiling. Charge is collected
//! first and read out once, so binning sums WELLS rather than summing reads —
//! see [`read_out`] for what the earlier ordering cost.

use nightshade_native::camera::FrameType;

/// Simulated sensor dimensions.
///
/// This is THE sensor. `SimulatedCamera::default` and
/// `device_capabilities::get_simulator_capabilities` both declare these numbers,
/// so the frame a caller receives matches the geometry the camera advertised.
/// They previously disagreed three ways — a 4144x2822 declaration, a 4144x2822
/// randomised generator on the manual-capture path, and this 1920x1080
/// deterministic one on the sequencer path — which meant no measurement taken
/// through one path could be compared with the other.
pub const SIM_W: usize = 1920;
pub const SIM_H: usize = 1080;

/// Full-well ceiling of the simulated sensor, in ADU.
pub const SIM_MAX_ADU: u16 = 65_535;

/// Focuser position at which simulated stars are sharpest.
///
/// Chosen to sit INSIDE the default autofocus sweep but off its centre. The
/// focuser starts at 25000 and the default sweep spans roughly +/-200 steps, so:
///   * putting true focus at the centre (25000) would let an algorithm that never
///     moved appear to succeed, and
///   * putting it at the edge (25200, tried first) gives the sweep a monotonic
///     slope instead of a V — the parabola fit then degenerates and autofocus
///     correctly refuses it with "curve fit R² 0.000 is below 0.700".
///
/// 25075 brackets the minimum on both sides while still requiring real movement.
pub const SIM_TRUE_FOCUS: i32 = 25_075;

const SIM_STAR_COUNT: usize = 45;
/// Sharpest achievable star sigma, in pixels.
const SIM_MIN_SIGMA: f64 = 1.6;
/// Sigma growth per focuser step away from [`SIM_TRUE_FOCUS`].
///
/// Sized so the DEFAULT autofocus sweep sees enough HFR spread to satisfy the
/// routine's `MIN_HFR_VARIANCE` V-curve check. At 0.0025 the sweep produced only
/// 0.68 of spread and autofocus correctly refused it ("No valid V-curve
/// detected"), which made the whole routine untestable against the simulator.
const SIM_SIGMA_PER_STEP: f64 = 0.006;

/// Electrons per second collected from the brightest star in the field.
///
/// Sized so a short exposure is well above the noise and a long one drives the
/// core past [`SIM_MAX_ADU`], which is what gives saturation handling and frame
/// grading something true to react to.
const SIM_STAR_E_PER_SEC: f64 = 45_000.0;
/// Sky background electrons per second per pixel.
const SIM_SKY_E_PER_SEC: f64 = 30.0;
/// Dark current electrons per second per pixel at the sensor's nominal setpoint.
const SIM_DARK_E_PER_SEC: f64 = 0.6;
/// Read noise in electrons RMS, drawn once per READ-OUT pixel — so a binned
/// pixel carries the same read noise as an unbinned one, which is the whole
/// reason binning buys SNR.
const SIM_READ_NOISE_E: f64 = 3.2;
/// Illumination electrons per second per pixel on a flat frame.
const SIM_FLAT_E_PER_SEC: f64 = 9_000.0;
/// ADU of bias pedestal contributed by one unit of the camera's offset setting.
const SIM_OFFSET_ADU_PER_UNIT: f64 = 50.0;
/// Peak vignetting loss at the corners of a flat, as a fraction.
const SIM_VIGNETTE_DEPTH: f64 = 0.28;
/// Exposure used by the parameterless convenience constructor.
pub const SIM_DEFAULT_EXPOSURE_SECS: f64 = 10.0;

/// Total electrons per second from the FAINTEST star rendered in a real-sky
/// field.
///
/// Anchoring on the faintest rather than on an absolute zero point is what
/// `tools/sim_fidelity/plate_solve_probe.py` proved out, and it is deliberate:
/// the field is truncated to the brightest [`SIM_SKY_STAR_LIMIT`], so the faint
/// end is set by the truncation, not by the sky. Pinning it to a known SNR makes
/// every field solvable at every focal length, and the true magnitude scale
/// above it means bright stars still bloom and saturate exactly as they should.
/// Sized so the faintest star peaks around 20x the sky noise at the default 10 s
/// exposure and stays detectable down to about 1 s.
const SIM_SKY_FAINT_E_PER_SEC: f64 = 650.0;

/// How many catalogue stars a real-sky frame renders, brightest first.
pub const SIM_SKY_STAR_LIMIT: usize = 1500;

/// Extra field radius requested beyond the sensor's half-diagonal, so a star
/// just outside the corner still contributes its wings.
const SIM_SKY_RADIUS_MARGIN: f64 = 1.15;

/// A pointing to render instead of the pseudo-random field: the sky the mount
/// says it is looking at, projected onto the sensor.
#[derive(Debug, Clone)]
pub struct SimSkyView {
    pub centre_ra_deg: f64,
    pub centre_dec_deg: f64,
    /// Rotator angle, degrees, applied about the sensor centre.
    pub rotation_deg: f64,
    /// Unbinned plate scale. Binning is applied later, by [`read_out`], because
    /// charge is collected at sensor resolution.
    pub arcsec_per_px: f64,
    pub stars: Vec<crate::sim_sky::SkyStar>,
}

/// Everything the simulated sensor needs to produce one frame.
#[derive(Debug, Clone)]
pub struct SimFrameRequest {
    pub width: usize,
    pub height: usize,
    pub exposure_secs: f64,
    pub gain: i32,
    pub offset: i32,
    pub frame_type: FrameType,
    pub focus_position: Option<i32>,
    pub offset_x: f64,
    pub offset_y: f64,
    pub bin_x: u32,
    pub bin_y: u32,
    pub subframe: Option<(u32, u32, u32, u32)>,
    pub max_adu: u16,
    /// Seed for the per-frame noise draw. The star field itself is keyed off a
    /// separate fixed seed, so a given seed reproduces a given frame exactly
    /// while successive frames still differ the way real reads do.
    pub seed: u64,
    /// When set, paint the real sky at this pointing instead of the pseudo-random
    /// field. `None` is the default and reproduces the old frame byte for byte —
    /// see [`add_stars`] for why that matters to the sim's own test suite.
    pub sky: Option<SimSkyView>,
}

impl Default for SimFrameRequest {
    fn default() -> Self {
        Self {
            width: SIM_W,
            height: SIM_H,
            exposure_secs: SIM_DEFAULT_EXPOSURE_SECS,
            gain: 0,
            offset: 10,
            frame_type: FrameType::Light,
            focus_position: Some(SIM_TRUE_FOCUS),
            offset_x: 0.0,
            offset_y: 0.0,
            bin_x: 1,
            bin_y: 1,
            subframe: None,
            max_adu: SIM_MAX_ADU,
            seed: 0,
            sky: None,
        }
    }
}

/// Dimensions of the buffer [`synthesize_sim_frame`] will return for `request`.
pub fn sim_frame_dimensions(request: &SimFrameRequest) -> (u32, u32) {
    let (_, _, w, h) = resolved_region(request);
    (
        (w / request.bin_x.max(1)).max(1),
        (h / request.bin_y.max(1)).max(1),
    )
}

fn resolved_region(request: &SimFrameRequest) -> (u32, u32, u32, u32) {
    let sensor_w = request.width as u32;
    let sensor_h = request.height as u32;
    match request.subframe {
        Some((x, y, w, h)) => {
            let x = x.min(sensor_w.saturating_sub(1));
            let y = y.min(sensor_h.saturating_sub(1));
            (x, y, w.clamp(1, sensor_w - x), h.clamp(1, sensor_h - y))
        }
        None => (0, 0, sensor_w, sensor_h),
    }
}

/// ADU produced per electron at a given gain setting.
fn adu_per_electron(gain: i32) -> f64 {
    0.25 * (1.0 + f64::from(gain.max(0)) / 100.0)
}

/// Star sigma (pixels) for a given focuser position.
pub fn sim_star_sigma(focus_position: Option<i32>) -> f64 {
    // A camera-only rig has no focuser to defocus it: treat that as in-focus so
    // plain capture tests still get sharp stars.
    let position = focus_position.unwrap_or(SIM_TRUE_FOCUS);
    let defocus = (position - SIM_TRUE_FOCUS).abs() as f64;
    SIM_MIN_SIGMA + defocus * SIM_SIGMA_PER_STEP
}

struct Lcg(u64);

impl Lcg {
    fn new(seed: u64) -> Self {
        Self(seed ^ 0x9E37_79B9_7F4A_7C15)
    }

    fn next_f64(&mut self) -> f64 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (self.0 >> 33) as f64 / (1u64 << 31) as f64
    }

    /// Unit-variance zero-mean draw. Irwin-Hall over four uniforms: cheap enough
    /// to run per pixel on a full sensor and close enough to Gaussian for a
    /// noise floor.
    fn next_normal(&mut self) -> f64 {
        let sum = self.next_f64() + self.next_f64() + self.next_f64() + self.next_f64();
        (sum - 2.0) * 1.732_050_807_568_877_2
    }
}

/// Build the simulator's synthetic frame for `request`.
///
/// Two stages, in the order a real sensor does them: collect charge over the
/// whole exposure, then read that charge out once. Binning happens between the
/// two because on-chip binning sums CHARGE and reads the sum through a single
/// amplifier — see [`read_out`] for what went wrong while the read was folded
/// into the collection step.
pub fn synthesize_sim_frame(request: &SimFrameRequest) -> Vec<u16> {
    let (region_x, region_y, region_w, region_h) = resolved_region(request);
    // One RNG for the whole frame: shot noise is drawn per SENSOR pixel and read
    // noise per OUTPUT pixel, so both have to come off the same seeded stream to
    // keep a given seed reproducing a given frame.
    let mut noise = Lcg::new(request.seed);
    let electrons = collect_electrons(request, region_x, region_y, region_w, region_h, &mut noise);
    read_out(
        &electrons,
        region_w as usize,
        region_h as usize,
        request,
        &mut noise,
    )
}

/// Charge collected in each SENSOR pixel of the region, in electrons.
///
/// Shot noise belongs here rather than in the read: it is already in the well
/// when the charge is summed, so binning correctly adds it in quadrature. The
/// pedestal and read noise are not — they arrive once, at the amplifier.
fn collect_electrons(
    request: &SimFrameRequest,
    region_x: u32,
    region_y: u32,
    region_w: u32,
    region_h: u32,
    noise: &mut Lcg,
) -> Vec<f64> {
    let width = region_w as usize;
    let height = region_h as usize;
    let exposure = request.exposure_secs.max(0.0);
    let frame_type = request.frame_type;

    // A bias frame is a zero-length read: no dark current, no sky, no light.
    let integrating = !matches!(frame_type, FrameType::Bias);
    let effective_exposure = if integrating { exposure } else { 0.0 };
    let collects_sky = matches!(frame_type, FrameType::Light);
    let collects_stars = collects_sky;
    let is_flat = matches!(frame_type, FrameType::Flat);

    let dark_e = SIM_DARK_E_PER_SEC * effective_exposure;
    let sky_e = if collects_sky {
        SIM_SKY_E_PER_SEC * effective_exposure
    } else {
        0.0
    };

    let mut signal = vec![0.0f64; width * height];

    let sensor_w = request.width as f64;
    let sensor_h = request.height as f64;
    let centre_x = sensor_w / 2.0;
    let centre_y = sensor_h / 2.0;
    let max_radius_sq = centre_x * centre_x + centre_y * centre_y;

    for y in 0..height {
        let sensor_row_y = (region_y as usize + y) as f64;
        for x in 0..width {
            let sensor_col_x = (region_x as usize + x) as f64;
            let mut e = dark_e + sky_e;
            if is_flat {
                let dx = sensor_col_x - centre_x;
                let dy = sensor_row_y - centre_y;
                let vignette = 1.0 - SIM_VIGNETTE_DEPTH * (dx * dx + dy * dy) / max_radius_sq;
                e += SIM_FLAT_E_PER_SEC * effective_exposure * vignette;
            }
            signal[y * width + x] = e;
        }
    }

    if collects_stars {
        match &request.sky {
            Some(sky) => add_sky_stars(
                &mut signal,
                request,
                sky,
                region_x,
                region_y,
                region_w,
                region_h,
                effective_exposure,
            ),
            None => add_stars(
                &mut signal,
                request,
                region_x,
                region_y,
                region_w,
                region_h,
                effective_exposure,
            ),
        }
    }

    for value in signal.iter_mut() {
        let electrons = *value;
        *value = electrons + noise.next_normal() * electrons.max(0.0).sqrt();
    }

    signal
}

#[allow(clippy::too_many_arguments)]
fn add_stars(
    signal: &mut [f64],
    request: &SimFrameRequest,
    region_x: u32,
    region_y: u32,
    region_w: u32,
    region_h: u32,
    exposure: f64,
) {
    let sigma = sim_star_sigma(request.focus_position);
    let two_sigma_sq = 2.0 * sigma * sigma;
    let peak_e = SIM_STAR_E_PER_SEC * exposure / (std::f64::consts::TAU * sigma * sigma);
    if peak_e <= 0.0 {
        return;
    }
    let radius = (3.0 * sigma).ceil() as isize;
    let width = region_w as isize;
    let height = region_h as isize;

    // Fixed-seed LCG: the field is identical run to run, so tests can assert on
    // star counts and HFR without tolerating a reshuffled field. Only the noise
    // draw varies between frames.
    let mut field = Lcg::new(0x5EED_1234_ABCD_0001);

    for _ in 0..SIM_STAR_COUNT {
        // Inset from the edges so every star's full profile fits on the sensor.
        // The mount offset is added AFTER the inset so the field translates as a
        // rigid body: a star near the edge can clip off-sensor under a large
        // offset, exactly as it would on a real drifting mount (the per-pixel
        // bounds check below handles that).
        let margin = radius as f64 + 2.0;
        let sensor_cx =
            margin + field.next_f64() * (request.width as f64 - 2.0 * margin) + request.offset_x;
        let sensor_cy =
            margin + field.next_f64() * (request.height as f64 - 2.0 * margin) + request.offset_y;
        // Some brightness spread, so the detector sees a realistic magnitude
        // range rather than 45 identical stars.
        let star_peak = peak_e * (0.45 + 0.55 * field.next_f64());

        let cx = sensor_cx - f64::from(region_x);
        let cy = sensor_cy - f64::from(region_y);
        let cxi = cx as isize;
        let cyi = cy as isize;
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let px = cxi + dx;
                let py = cyi + dy;
                if px < 0 || py < 0 || px >= width || py >= height {
                    continue;
                }
                let r_sq = (px as f64 - cx).powi(2) + (py as f64 - cy).powi(2);
                let value = star_peak * (-r_sq / two_sigma_sq).exp();
                if value < 1.0 {
                    continue;
                }
                signal[py as usize * region_w as usize + px as usize] += value;
            }
        }
    }
}

/// Smallest `cos` of the angular distance from the tangent point that still
/// projects. Guards the gnomonic divide, which blows up at 90 degrees and
/// mirrors the sky onto the frame beyond it.
const TAN_HORIZON: f64 = 0.05;

/// Field radius, in degrees, that covers a sensor at a given plate scale.
///
/// The half-diagonal plus a margin, so a star just outside a corner still lands
/// its wings on the sensor.
pub fn sim_sky_field_radius_deg(width: usize, height: usize, arcsec_per_px: f64) -> f64 {
    let w_deg = width as f64 * arcsec_per_px / 3600.0;
    let h_deg = height as f64 * arcsec_per_px / 3600.0;
    w_deg.hypot(h_deg) / 2.0 * SIM_SKY_RADIUS_MARGIN
}

/// Gnomonic (TAN) projection of one catalogue star onto the simulated sensor.
///
/// Returns full-sensor pixel coordinates with the origin at the top-left corner,
/// before the subframe origin or the mount's guide offset are applied. `None`
/// when the star is too far from the tangent point to project.
///
/// TAN because that is the projection ASTAP writes into the WCS it solves for,
/// so a frame rendered this way and then solved is being measured against its
/// own geometry rather than against an approximation of it.
pub fn project_star(
    sky: &SimSkyView,
    sensor_w: f64,
    sensor_h: f64,
    star: &crate::sim_sky::SkyStar,
) -> Option<(f64, f64)> {
    let scale_rad = (sky.arcsec_per_px / 3600.0).to_radians();
    if !scale_rad.is_finite() || scale_rad <= 0.0 {
        return None;
    }
    let (sin_dec0, cos_dec0) = sky.centre_dec_deg.to_radians().sin_cos();
    let (sin_dec, cos_dec) = star.dec_deg.to_radians().sin_cos();
    let (sin_dra, cos_dra) = (star.ra_deg - sky.centre_ra_deg).to_radians().sin_cos();

    let cos_c = sin_dec0 * sin_dec + cos_dec0 * cos_dec * cos_dra;
    if cos_c <= TAN_HORIZON {
        return None;
    }
    // Standard coordinates about the tangent point, in radians on the sky.
    let xi = cos_dec * sin_dra / cos_c;
    let eta = (cos_dec0 * sin_dec - sin_dec0 * cos_dec * cos_dra) / cos_c;

    // RA increases to the LEFT of a sky-side-up frame and north (+eta) is up,
    // while raster rows run downward — so both standard coordinates negate on
    // the way into pixels.
    let px = -xi / scale_rad;
    let py = -eta / scale_rad;
    let (sin_rot, cos_rot) = sky.rotation_deg.to_radians().sin_cos();
    Some((
        sensor_w / 2.0 + px * cos_rot - py * sin_rot,
        sensor_h / 2.0 + px * sin_rot + py * cos_rot,
    ))
}

/// Paint the catalogue field described by `sky` into the collected charge.
///
/// Everything downstream of this is shared with the pseudo-random field: shot
/// noise, the read, the offset pedestal and the well clip are all applied by
/// [`collect_electrons`] and [`read_out`] afterwards, and the PSF width still
/// comes from [`sim_star_sigma`], so a real-sky frame defocuses on the focuser
/// and saturates at the ceiling exactly like the old one.
///
/// No RNG runs here: a given pointing and star list render a given frame, and
/// only the seeded noise draw varies between frames.
#[allow(clippy::too_many_arguments)]
fn add_sky_stars(
    signal: &mut [f64],
    request: &SimFrameRequest,
    sky: &SimSkyView,
    region_x: u32,
    region_y: u32,
    region_w: u32,
    region_h: u32,
    exposure: f64,
) {
    let sigma = sim_star_sigma(request.focus_position);
    let two_sigma_sq = 2.0 * sigma * sigma;
    // Peak electrons per electron/second of total flux.
    let unit_peak = exposure / (std::f64::consts::TAU * sigma * sigma);
    if unit_peak <= 0.0 {
        return;
    }
    // Four sigma, where the pseudo-random field uses three: a catalogue field is
    // dominated by stars near the detection floor, and clipping their wings a
    // sigma early costs exactly the flux the solver centroids on.
    let radius = (4.0 * sigma).ceil() as isize;

    let sensor_w = request.width as f64;
    let sensor_h = request.height as f64;
    let margin = radius as f64 + 2.0;

    let mut placed: Vec<(f64, f64, f64)> = Vec::with_capacity(sky.stars.len());
    for star in &sky.stars {
        let Some((x, y)) = project_star(sky, sensor_w, sensor_h, star) else {
            continue;
        };
        // The guide offset rides on top of the pointing: the simulated mount
        // accumulates guide-pulse and drift displacement that its reported
        // RA/Dec does not carry, so without this the built-in guider would see
        // its own pulses move nothing.
        let x = x + request.offset_x;
        let y = y + request.offset_y;
        if x < -margin || y < -margin || x > sensor_w + margin || y > sensor_h + margin {
            continue;
        }
        placed.push((x, y, star.mag));
    }
    if placed.is_empty() {
        return;
    }

    // Anchor the brightness scale on the faintest star that landed — see
    // [`SIM_SKY_FAINT_E_PER_SEC`]. Above that anchor the TRUE magnitude scale
    // applies, so the bright end blooms and saturates on its own.
    let faintest = placed
        .iter()
        .map(|(_, _, mag)| *mag)
        .fold(f64::MIN, f64::max);
    let faint_peak_e = SIM_SKY_FAINT_E_PER_SEC * unit_peak;

    let width = region_w as isize;
    let height = region_h as isize;
    for (sensor_cx, sensor_cy, mag) in placed {
        let peak_e = faint_peak_e * 10f64.powf(0.4 * (faintest - mag));
        let cx = sensor_cx - f64::from(region_x);
        let cy = sensor_cy - f64::from(region_y);
        let cxi = cx.round() as isize;
        let cyi = cy.round() as isize;
        for dy in -radius..=radius {
            let py = cyi + dy;
            if py < 0 || py >= height {
                continue;
            }
            for dx in -radius..=radius {
                let px = cxi + dx;
                if px < 0 || px >= width {
                    continue;
                }
                let r_sq = (px as f64 - cx).powi(2) + (py as f64 - cy).powi(2);
                let value = peak_e * (-r_sq / two_sigma_sq).exp();
                if value < 1.0 {
                    continue;
                }
                signal[py as usize * region_w as usize + px as usize] += value;
            }
        }
    }
}

/// Read the collected charge out: sum `bin_x` x `bin_y` blocks the way a real
/// sensor sums charge on chip, then apply ONE read per output pixel — one read
/// noise draw and one offset pedestal — and clip at the ADC ceiling.
///
/// The ordering is the whole point. While the pedestal and the read noise were
/// applied per sensor pixel and then summed by the binning loop, both scaled
/// with bin area: a bias frame read 499.5 ADU at bin 1 but 1999.5 ADU at bin 2,
/// and read noise grew by sqrt(bin area) instead of staying put. No camera
/// behaves that way — the offset is injected once at the amplifier — so a bias
/// or dark master captured binned sat four pedestals high, calibration that
/// subtracted an unbinned master from a binned light was wrong by 1500 ADU, and
/// any offset-derived check that passed against the simulator passed for a
/// reason the hardware does not share.
fn read_out(
    electrons: &[f64],
    width: usize,
    height: usize,
    request: &SimFrameRequest,
    noise: &mut Lcg,
) -> Vec<u16> {
    let bin_x = request.bin_x.max(1) as usize;
    let bin_y = request.bin_y.max(1) as usize;
    let out_w = (width / bin_x).max(1);
    let out_h = (height / bin_y).max(1);
    let adu_per_e = adu_per_electron(request.gain);
    let pedestal = f64::from(request.offset.max(0)) * SIM_OFFSET_ADU_PER_UNIT;
    let ceiling = f64::from(request.max_adu);
    let mut out = vec![0u16; out_w * out_h];

    for oy in 0..out_h {
        for ox in 0..out_w {
            let mut charge = 0.0;
            for by in 0..bin_y {
                let sy = oy * bin_y + by;
                if sy >= height {
                    continue;
                }
                for bx in 0..bin_x {
                    let sx = ox * bin_x + bx;
                    if sx >= width {
                        continue;
                    }
                    charge += electrons[sy * width + sx];
                }
            }
            let read = noise.next_normal() * SIM_READ_NOISE_E;
            out[oy * out_w + ox] =
                (pedestal + (charge + read) * adu_per_e).clamp(0.0, ceiling) as u16;
        }
    }
    out
}

/// Build a default light frame with the star field translated by
/// `(offset_x, offset_y)` pixels.
///
/// The offset is what makes guiding exercisable without a mount: the simulated
/// mount accumulates guide-pulse and drift displacement (see
/// `api::devices::simulation::sim_guide_offset_px`) and passes it here, so the
/// built-in guider sees its own pulses move the stars. Without it every
/// calibration attempt died on "Calibration response on east axis was too small
/// (0.000px)" — the pulse op returned `Ok` but nothing moved — which made
/// calibration, closed-loop correction and dithering untestable offline.
#[cfg(test)]
pub fn synthesize_sim_frame_with_offset(
    focus_position: Option<i32>,
    offset_x: f64,
    offset_y: f64,
) -> Vec<u16> {
    synthesize_sim_frame(&SimFrameRequest {
        focus_position,
        offset_x,
        offset_y,
        ..SimFrameRequest::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use nightshade_imaging::{detect_stars_with_stats, ImageData, StarDetectionConfig};

    fn frame(request: &SimFrameRequest) -> Vec<u16> {
        synthesize_sim_frame(request)
    }

    fn mean(buffer: &[u16]) -> f64 {
        buffer.iter().map(|&v| f64::from(v)).sum::<f64>() / buffer.len() as f64
    }

    fn stddev(buffer: &[u16]) -> f64 {
        let mean = mean(buffer);
        (buffer
            .iter()
            .map(|&v| (f64::from(v) - mean).powi(2))
            .sum::<f64>()
            / buffer.len() as f64)
            .sqrt()
    }

    fn detect(focus_position: Option<i32>) -> (usize, Option<f64>) {
        let buffer = synthesize_sim_frame_with_offset(focus_position, 0.0, 0.0);
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        let hfrs: Vec<f64> = result.stars.iter().map(|s| s.hfr).collect();
        let median = if hfrs.is_empty() {
            None
        } else {
            let mut sorted = hfrs.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
            Some(sorted[sorted.len() / 2])
        };
        (result.stars.len(), median)
    }

    /// The bar that matters: the DEFAULT detector config, and the 10-star
    /// minimum the autofocus routine enforces.
    #[test]
    fn in_focus_frame_yields_enough_detectable_stars_for_autofocus() {
        let (count, hfr) = detect(Some(SIM_TRUE_FOCUS));
        assert!(
            count >= 10,
            "in-focus simulated frame produced {count} detectable stars; autofocus \
             requires at least 10 and previously failed with 0"
        );
        let hfr = hfr.expect("stars were detected, so an HFR must be measurable");
        assert!(
            hfr.is_finite() && hfr > 0.5 && hfr < 12.0,
            "in-focus HFR {hfr} is not a plausible measurement"
        );
    }

    /// A camera-only rig (no focuser connected) must still get sharp stars.
    #[test]
    fn frame_without_a_focuser_is_in_focus() {
        let (count, _) = detect(None);
        assert!(count >= 10, "no-focuser frame produced only {count} stars");
    }

    /// The V-curve: defocusing must RAISE measured HFR, or an autofocus sweep
    /// has no minimum to find and the whole routine is untestable.
    #[test]
    fn defocus_increases_measured_hfr() {
        let (_, focused) = detect(Some(SIM_TRUE_FOCUS));
        let (_, defocused) = detect(Some(SIM_TRUE_FOCUS + 900));
        let focused = focused.expect("in-focus stars detected");
        let defocused = defocused.expect("defocused stars still detected");
        assert!(
            defocused > focused,
            "defocused HFR {defocused} must exceed in-focus HFR {focused} for an \
             autofocus sweep to converge"
        );
    }

    /// Defocus must be symmetric about true focus, so the sweep sees a genuine
    /// V rather than a monotonic slope it can walk off the end of.
    #[test]
    fn defocus_is_symmetric_about_true_focus() {
        let inside = sim_star_sigma(Some(SIM_TRUE_FOCUS - 800));
        let outside = sim_star_sigma(Some(SIM_TRUE_FOCUS + 800));
        assert!((inside - outside).abs() < 1e-9);
        assert!(inside > sim_star_sigma(Some(SIM_TRUE_FOCUS)));
    }

    /// Centroid of the brightest detected star, for offset assertions.
    fn brightest_centroid(offset_x: f64, offset_y: f64) -> (f64, f64) {
        let buffer = synthesize_sim_frame_with_offset(Some(SIM_TRUE_FOCUS), offset_x, offset_y);
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        let star = result
            .stars
            .iter()
            .max_by(|a, b| a.flux.partial_cmp(&b.flux).unwrap())
            .expect("stars detected");
        (star.x, star.y)
    }

    /// A guide pulse has to MOVE the field, and move it the way it was asked to.
    /// The built-in guider derives its calibration from exactly this measurement,
    /// and while the simulated pulse was a no-op it always aborted with
    /// "Calibration response on east axis was too small (0.000px)".
    #[test]
    fn offset_translates_the_star_field() {
        let (base_x, base_y) = brightest_centroid(0.0, 0.0);
        let (east_x, east_y) = brightest_centroid(6.0, 0.0);
        assert!(
            (east_x - base_x - 6.0).abs() < 0.5,
            "east offset moved the centroid from {base_x:.2} to {east_x:.2}; expected +6px"
        );
        assert!(
            (east_y - base_y).abs() < 0.5,
            "an x-only offset must not move the centroid in y ({base_y:.2} -> {east_y:.2})"
        );

        let (north_x, north_y) = brightest_centroid(0.0, 6.0);
        assert!(
            (north_y - base_y - 6.0).abs() < 0.5,
            "north offset moved the centroid from {base_y:.2} to {north_y:.2}; expected +6px"
        );
        assert!(
            (north_x - base_x).abs() < 0.5,
            "a y-only offset must not move the centroid in x ({base_x:.2} -> {north_x:.2})"
        );
    }

    /// The offset must not cost the frame its detectability: the guider needs a
    /// star field at every point of a calibration, not just at the origin.
    #[test]
    fn offset_frame_still_yields_detectable_stars() {
        for (dx, dy) in [(0.0, 0.0), (12.0, -8.0), (-60.0, 60.0), (60.0, -60.0)] {
            let buffer = synthesize_sim_frame_with_offset(Some(SIM_TRUE_FOCUS), dx, dy);
            let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
            let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
            assert!(
                result.stars.len() >= 10,
                "offset ({dx}, {dy}) left only {} detectable stars; the guider needs a \
                 usable field across its whole excursion range",
                result.stars.len()
            );
        }
    }

    /// A pulse response has to clear the guider's 0.2px "too small" floor while
    /// staying well inside its 20px star-match radius — outside that band
    /// calibration either refuses the response or matches the wrong star.
    #[test]
    fn calibration_pulse_response_is_measurable_and_matchable() {
        // Mirrors the simulated mount's 6 px/sec at the guider's default 250 ms
        // calibration pulse.
        let per_pulse = 6.0 * 0.250;
        assert!(
            per_pulse > 0.2,
            "per-pulse response {per_pulse}px is below the guider's 0.2px floor"
        );
        // Dec calibration issues two forward pulses before measuring.
        assert!(
            per_pulse * 2.0 < 20.0,
            "two-pulse Dec response {}px exceeds the 20px match radius",
            per_pulse * 2.0
        );
        let (base_x, _) = brightest_centroid(0.0, 0.0);
        let (moved_x, _) = brightest_centroid(per_pulse, 0.0);
        assert!(
            (moved_x - base_x) > 0.2,
            "a single calibration pulse shifted the measured centroid only {:.3}px",
            moved_x - base_x
        );
    }

    /// The autofocus routine rejects a sweep whose HFR spread is below its
    /// `MIN_HFR_VARIANCE` (1.0) as "no valid V-curve". The simulated focus
    /// response therefore has to produce more spread than that across the
    /// DEFAULT sweep window, or autofocus is untestable without hardware —
    /// which is exactly how it failed before this was tuned (spread 0.68).
    #[test]
    fn default_sweep_window_spans_enough_hfr_for_a_v_curve() {
        // The focuser starts at 25000 and the default sweep covers about
        // +/-200 steps around it in 50-step increments.
        let positions: Vec<i32> = (24_800..=25_200).step_by(50).collect();
        let hfrs: Vec<f64> = positions
            .iter()
            .map(|p| {
                detect(Some(*p))
                    .1
                    .expect("stars detected at every sweep point")
            })
            .collect();

        let min = hfrs.iter().cloned().fold(f64::INFINITY, f64::min);
        let max = hfrs.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        assert!(
            max - min > 1.0,
            "sweep HFR spread {:.2} (min {:.2}, max {:.2}) must exceed the \
             routine's MIN_HFR_VARIANCE of 1.0",
            max - min,
            min,
            max
        );

        // And the minimum must fall INSIDE the window rather than at an edge, so
        // the parabola fit has points on both sides.
        let argmin = hfrs
            .iter()
            .enumerate()
            .min_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap();
        assert!(
            argmin > 0 && argmin < hfrs.len() - 1,
            "best focus landed at sweep edge index {argmin} of {}; the fit \
             degenerates to a slope and autofocus refuses it",
            hfrs.len()
        );
    }

    /// Exposure has to move pixels. An 8 s frame and a 2 s frame were previously
    /// 99.73% bit-identical, which is what made every exposure-dependent
    /// behaviour untestable.
    #[test]
    fn longer_exposure_collects_more_signal() {
        // The bias pedestal is a fixed electronic offset and does not integrate,
        // so the collected signal is what has to scale with time.
        let pedestal = 10.0 * SIM_OFFSET_ADU_PER_UNIT;
        let short = mean(&frame(&SimFrameRequest {
            exposure_secs: 2.0,
            ..Default::default()
        })) - pedestal;
        let long = mean(&frame(&SimFrameRequest {
            exposure_secs: 60.0,
            ..Default::default()
        })) - pedestal;
        let ratio = long / short;
        assert!(
            (ratio - 30.0).abs() < 3.0,
            "30x the exposure should collect ~30x the signal; got {ratio:.1}x \
             ({short:.1} -> {long:.1} ADU above pedestal)"
        );
    }

    /// Gain amplifies and offset raises the pedestal, independently.
    #[test]
    fn gain_and_offset_move_the_frame() {
        let base = SimFrameRequest {
            exposure_secs: 10.0,
            ..Default::default()
        };
        let high_gain = frame(&SimFrameRequest {
            gain: 300,
            ..base.clone()
        });
        let high_offset = frame(&SimFrameRequest {
            offset: 60,
            ..base.clone()
        });
        let baseline = frame(&base);

        assert!(
            mean(&high_gain) > mean(&baseline),
            "gain 300 mean {:.1} should exceed gain 0 mean {:.1}",
            mean(&high_gain),
            mean(&baseline)
        );
        let pedestal_step = mean(&high_offset) - mean(&baseline);
        assert!(
            (pedestal_step - 2500.0).abs() < 50.0,
            "offset 10 -> 60 should raise the pedestal by 2500 ADU, moved {pedestal_step:.1}"
        );
    }

    /// The background must be noise, not the old diagonal sawtooth: a master
    /// dark built from a ramp injects that ramp into every calibrated light.
    /// Lag-1 autocorrelation along a row was 0.9835 and row 500 literally read
    /// 300, 301, 302, ...
    #[test]
    fn background_is_noise_rather_than_a_ramp() {
        let buffer = frame(&SimFrameRequest {
            frame_type: FrameType::Dark,
            exposure_secs: 30.0,
            ..Default::default()
        });
        let row: Vec<f64> = buffer[500 * SIM_W..500 * SIM_W + SIM_W]
            .iter()
            .map(|&v| f64::from(v))
            .collect();
        let mean_row = row.iter().sum::<f64>() / row.len() as f64;
        let var = row.iter().map(|v| (v - mean_row).powi(2)).sum::<f64>() / row.len() as f64;
        let cov = row
            .windows(2)
            .map(|w| (w[0] - mean_row) * (w[1] - mean_row))
            .sum::<f64>()
            / (row.len() - 1) as f64;
        let lag1 = cov / var;
        assert!(
            lag1.abs() < 0.2,
            "row lag-1 autocorrelation {lag1:.4} indicates a ramp, not noise"
        );
        assert!(var > 0.0, "a dark frame with zero variance is a dead frame");
    }

    /// Saturation must be reachable, and must clip at the advertised ceiling
    /// rather than wrapping. Without this, saturation handling, clipping and
    /// `maxAdu` behaviour have nothing true to react to.
    #[test]
    fn long_exposure_saturates_star_cores_at_the_ceiling() {
        let buffer = frame(&SimFrameRequest {
            exposure_secs: 600.0,
            gain: 100,
            ..Default::default()
        });
        let peak = *buffer.iter().max().unwrap();
        assert_eq!(
            peak, SIM_MAX_ADU,
            "a 600 s exposure must drive star cores to the {SIM_MAX_ADU} ADU ceiling"
        );
        let saturated = buffer.iter().filter(|&&v| v >= 65_024).count();
        assert!(
            saturated > 0,
            "no pixel reached the validator's 65024 saturation threshold"
        );
    }

    /// A short exposure must NOT saturate, or every frame reads as clipped and
    /// grading can never distinguish a good one.
    #[test]
    fn short_exposure_does_not_saturate() {
        let buffer = frame(&SimFrameRequest {
            exposure_secs: 1.0,
            gain: 0,
            ..Default::default()
        });
        let peak = *buffer.iter().max().unwrap();
        assert!(
            peak < 65_024,
            "a 1 s gain-0 frame peaked at {peak}; it should be far from saturation"
        );
    }

    /// Darks, biases and flats must not contain stars. A DARK previously held 45
    /// compact peaks above 1000 ADU, brightest 33,780 — subtract that as a master
    /// dark and it punches holes in every light frame.
    #[test]
    fn calibration_frames_contain_no_stars() {
        for frame_type in [FrameType::Dark, FrameType::Bias, FrameType::Flat] {
            let buffer = frame(&SimFrameRequest {
                frame_type,
                exposure_secs: 30.0,
                ..Default::default()
            });
            let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
            let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
            assert!(
                result.stars.len() < 5,
                "{frame_type:?} frame contained {} detected stars; calibration frames \
                 see no sky",
                result.stars.len()
            );
        }
    }

    /// A bias frame is a zero-length read: it must sit at the pedestal and not
    /// accumulate dark current, however long the requested exposure was.
    #[test]
    fn bias_frame_ignores_exposure_time() {
        let short = frame(&SimFrameRequest {
            frame_type: FrameType::Bias,
            exposure_secs: 0.0,
            ..Default::default()
        });
        let long = frame(&SimFrameRequest {
            frame_type: FrameType::Bias,
            exposure_secs: 600.0,
            seed: 1,
            ..Default::default()
        });
        assert!(
            (mean(&short) - mean(&long)).abs() < 2.0,
            "bias mean moved from {:.2} to {:.2} with exposure time",
            mean(&short),
            mean(&long)
        );
        // 500 ADU pedestal from the default offset of 10.
        assert!(
            (mean(&short) - 500.0).abs() < 5.0,
            "bias pedestal {:.1} should sit at the offset-derived 500 ADU",
            mean(&short)
        );
    }

    /// A dark must accumulate dark current with exposure, or dark scaling and
    /// dark-tolerance matching have nothing to measure.
    #[test]
    fn dark_frame_accumulates_with_exposure() {
        let short = frame(&SimFrameRequest {
            frame_type: FrameType::Dark,
            exposure_secs: 1.0,
            ..Default::default()
        });
        let long = frame(&SimFrameRequest {
            frame_type: FrameType::Dark,
            exposure_secs: 600.0,
            ..Default::default()
        });
        assert!(
            mean(&long) > mean(&short) + 50.0,
            "600 s dark mean {:.1} barely exceeds 1 s dark mean {:.1}",
            mean(&long),
            mean(&short)
        );
    }

    /// Same seed, same frame. Different seed, different noise — a stack of
    /// identical frames cannot exercise sigma-clipping.
    #[test]
    fn seed_controls_determinism() {
        let a = frame(&SimFrameRequest {
            seed: 7,
            ..Default::default()
        });
        let b = frame(&SimFrameRequest {
            seed: 7,
            ..Default::default()
        });
        let c = frame(&SimFrameRequest {
            seed: 8,
            ..Default::default()
        });
        assert_eq!(a, b, "the same seed must reproduce the same frame exactly");
        assert_ne!(a, c, "a different seed must produce a different noise draw");
    }

    /// Binning sums charge, so a 2x2 binned frame is a quarter of the pixels and
    /// roughly four times the per-pixel signal.
    #[test]
    fn binning_shrinks_the_frame_and_sums_charge() {
        let unbinned = SimFrameRequest {
            frame_type: FrameType::Dark,
            exposure_secs: 60.0,
            offset: 0,
            ..Default::default()
        };
        let binned = SimFrameRequest {
            bin_x: 2,
            bin_y: 2,
            ..unbinned.clone()
        };
        assert_eq!(sim_frame_dimensions(&binned), (960, 540));
        let plain = frame(&unbinned);
        let two_by_two = frame(&binned);
        assert_eq!(two_by_two.len(), plain.len() / 4);
        let ratio = mean(&two_by_two) / mean(&plain);
        assert!(
            (ratio - 4.0).abs() < 0.2,
            "2x2 binning should quadruple per-pixel signal, ratio was {ratio:.2}"
        );
    }

    /// The bias pedestal is injected once at the amplifier, so it must not move
    /// when the sensor bins. It previously scaled with bin area — 499.5 ADU at
    /// bin 1 but 1999.5 ADU at bin 2 — because the offset was added per sensor
    /// pixel and then carried into the sum by the binning loop. Binning sums
    /// charge; the offset is not charge. A camera that reported four pedestals
    /// on a binned bias would have every binned calibration master, every
    /// offset-derived check and every "is this pedestal sane" heuristic
    /// agreeing with the simulator and disagreeing with the hardware.
    #[test]
    fn bias_level_is_independent_of_binning() {
        // 500 ADU from the default offset of 10, at every binning the simulated
        // camera advertises — including the asymmetric ones, which is where a
        // per-pixel pedestal would scale by only one of the two factors.
        for (bin_x, bin_y) in [(1u32, 1u32), (2, 2), (3, 3), (4, 4), (1, 2), (2, 1)] {
            let bias = mean(&frame(&SimFrameRequest {
                frame_type: FrameType::Bias,
                bin_x,
                bin_y,
                ..Default::default()
            }));
            assert!(
                (bias - 500.0).abs() < 5.0,
                "bin {bin_x}x{bin_y} bias frame sat at {bias:.1} ADU; one read \
                 applies the offset-derived 500 ADU pedestal once, whatever the \
                 binning"
            );
        }
    }

    /// ...and the charge underneath the pedestal must still sum, or binning
    /// would have stopped meaning anything. Measured ABOVE the pedestal, since
    /// that is the only part binning is entitled to multiply.
    #[test]
    fn binned_signal_scales_with_bin_area_above_the_pedestal() {
        let base = SimFrameRequest {
            frame_type: FrameType::Dark,
            exposure_secs: 600.0,
            ..Default::default()
        };
        let pedestal = f64::from(base.offset) * SIM_OFFSET_ADU_PER_UNIT;
        let unbinned = mean(&frame(&base)) - pedestal;
        for (bin_x, bin_y) in [(2u32, 2u32), (4, 4), (2, 1)] {
            let binned = mean(&frame(&SimFrameRequest {
                bin_x,
                bin_y,
                ..base.clone()
            })) - pedestal;
            let area = f64::from(bin_x * bin_y);
            let ratio = binned / unbinned;
            assert!(
                (ratio - area).abs() < 0.15 * area,
                "bin {bin_x}x{bin_y} collected {ratio:.2}x the unbinned signal \
                 ({unbinned:.1} -> {binned:.1} ADU above pedestal); summing \
                 {area:.0} wells collects {area:.0}x the charge"
            );
        }
    }

    /// One read means one read-noise draw. Summing a draw per sensor pixel
    /// inflated binned read noise by sqrt(bin area), so a binned simulated frame
    /// was noisier than the hardware it stands in for — the direction that lets
    /// a real noise regression hide inside the simulator's own noise floor, and
    /// that makes binning look like it buys less SNR than it does.
    #[test]
    fn read_noise_does_not_grow_with_binning() {
        // A bias frame collects no charge, so its spread is read noise alone.
        // Gain 300 puts the conversion at 1 ADU/e-, clear of the quantisation
        // floor that would otherwise swamp a 3.2 e- measurement.
        let bias_noise = |bin_x, bin_y| {
            stddev(&frame(&SimFrameRequest {
                frame_type: FrameType::Bias,
                gain: 300,
                bin_x,
                bin_y,
                ..Default::default()
            }))
        };
        let unbinned = bias_noise(1, 1);
        assert!(
            (unbinned - SIM_READ_NOISE_E).abs() < 0.5,
            "unbinned bias spread {unbinned:.2} ADU should sit at the sensor's \
             {SIM_READ_NOISE_E} e- read noise at 1 ADU/e-"
        );
        for (bin_x, bin_y) in [(2u32, 2u32), (4, 4)] {
            let binned = bias_noise(bin_x, bin_y);
            assert!(
                (binned - unbinned).abs() < 0.25 * unbinned,
                "bin {bin_x}x{bin_y} bias spread {binned:.2} ADU against {unbinned:.2} \
                 unbinned; a binned pixel is read once, not {} times",
                bin_x * bin_y
            );
        }
    }

    /// A subframe returns exactly the requested region.
    #[test]
    fn subframe_returns_the_requested_region() {
        let request = SimFrameRequest {
            subframe: Some((100, 200, 640, 480)),
            ..Default::default()
        };
        assert_eq!(sim_frame_dimensions(&request), (640, 480));
        assert_eq!(frame(&request).len(), 640 * 480);
    }

    // =====================================================================
    // Real-sky rendering
    // =====================================================================

    fn digest(buffer: &[u16]) -> u64 {
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        for value in buffer {
            hash ^= u64::from(*value);
            hash = hash.wrapping_mul(0x100_0000_01b3);
        }
        hash
    }

    /// The pseudo-random field is untouched by the real-sky path.
    ///
    /// These digests were taken from a build with `add_sky_stars` and the `sky`
    /// field deleted outright, so they pin the frame as it stood BEFORE real-sky
    /// rendering existed rather than merely pinning it against itself. That
    /// matters because the sim's own suite asserts star counts, HFR and the
    /// autofocus V-curve against this exact field: if the default frame moves,
    /// every one of those numbers silently means something else.
    ///
    /// A digest that fails here is a REGRESSION, not a golden to re-bless,
    /// unless the pseudo-random field was deliberately changed.
    #[test]
    fn no_sky_view_reproduces_the_original_field_byte_for_byte() {
        let cases: [(&str, SimFrameRequest, u64); 7] = [
            ("light", SimFrameRequest::default(), 0x9c63_c844_c0e1_10de),
            (
                "dark",
                SimFrameRequest {
                    exposure_secs: 30.0,
                    frame_type: FrameType::Dark,
                    ..Default::default()
                },
                0x2842_208c_5180_d708,
            ),
            (
                "flat",
                SimFrameRequest {
                    exposure_secs: 2.0,
                    frame_type: FrameType::Flat,
                    gain: 90,
                    offset: 25,
                    ..Default::default()
                },
                0xa185_4d18_04e7_0657,
            ),
            (
                "bias",
                SimFrameRequest {
                    frame_type: FrameType::Bias,
                    ..Default::default()
                },
                0xb6de_c7f0_0293_c0b1,
            ),
            (
                "defocused",
                SimFrameRequest {
                    focus_position: Some(25_250),
                    seed: 42,
                    ..Default::default()
                },
                0xcfe0_bec5_606a_0b37,
            ),
            (
                "guide-offset",
                SimFrameRequest {
                    offset_x: 13.5,
                    offset_y: -7.25,
                    seed: 9,
                    ..Default::default()
                },
                0x3b9e_3b8c_6829_e5eb,
            ),
            (
                "binned-subframe",
                SimFrameRequest {
                    bin_x: 2,
                    bin_y: 2,
                    subframe: Some((100, 60, 640, 480)),
                    seed: 3,
                    ..Default::default()
                },
                0xe73a_6a13_2dc0_4fcb,
            ),
        ];
        for (name, request, expected) in cases {
            assert!(request.sky.is_none(), "{name} must not carry a sky view");
            assert_eq!(
                digest(&frame(&request)),
                expected,
                "{name} frame changed; the pseudo-random field must stay identical \
                 when no catalogue is configured"
            );
        }
    }

    fn sky_view(stars: Vec<crate::sim_sky::SkyStar>) -> SimSkyView {
        SimSkyView {
            centre_ra_deg: 83.822,
            centre_dec_deg: -5.391,
            rotation_deg: 0.0,
            // 3.76 um pixels at 1000 mm, the simulated rig's declared geometry.
            arcsec_per_px: 0.7756,
            stars,
        }
    }

    /// Detected position of the brightest star in a full-sensor frame.
    fn brightest_star_in(buffer: &[u16]) -> (f64, f64) {
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, buffer);
        let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        let star = result
            .stars
            .iter()
            .max_by(|a, b| a.flux.partial_cmp(&b.flux).unwrap())
            .expect("stars detected");
        (star.x, star.y)
    }

    fn star(ra_deg: f64, dec_deg: f64, mag: f64) -> crate::sim_sky::SkyStar {
        crate::sim_sky::SkyStar {
            ra_deg,
            dec_deg,
            mag,
        }
    }

    /// A star at the tangent point lands on the sensor's centre pixel.
    #[test]
    fn tan_projection_puts_the_pointing_at_the_frame_centre() {
        let sky = sky_view(Vec::new());
        let centre = project_star(
            &sky,
            SIM_W as f64,
            SIM_H as f64,
            &star(sky.centre_ra_deg, sky.centre_dec_deg, 8.0),
        )
        .expect("the tangent point always projects");
        assert!((centre.0 - SIM_W as f64 / 2.0).abs() < 1e-6, "{centre:?}");
        assert!((centre.1 - SIM_H as f64 / 2.0).abs() < 1e-6, "{centre:?}");
    }

    /// A known angular offset lands on the pixel the plate scale predicts, in
    /// the orientation a sky-side-up frame has: north up, east (increasing RA)
    /// to the LEFT.
    #[test]
    fn tan_projection_places_a_known_offset_on_the_predicted_pixel() {
        let sky = sky_view(Vec::new());
        // 100 pixels' worth of declination, straight north.
        let north_deg = 100.0 * sky.arcsec_per_px / 3600.0;
        let north = project_star(
            &sky,
            SIM_W as f64,
            SIM_H as f64,
            &star(sky.centre_ra_deg, sky.centre_dec_deg + north_deg, 8.0),
        )
        .unwrap();
        assert!((north.0 - SIM_W as f64 / 2.0).abs() < 0.05, "{north:?}");
        assert!(
            (north.1 - (SIM_H as f64 / 2.0 - 100.0)).abs() < 0.05,
            "north must be UP (smaller row): {north:?}"
        );

        // 100 pixels' worth of RA east, which shrinks by cos(dec) on the sky.
        let east_deg = 100.0 * sky.arcsec_per_px / 3600.0 / sky.centre_dec_deg.to_radians().cos();
        let east = project_star(
            &sky,
            SIM_W as f64,
            SIM_H as f64,
            &star(sky.centre_ra_deg + east_deg, sky.centre_dec_deg, 8.0),
        )
        .unwrap();
        assert!(
            (east.0 - (SIM_W as f64 / 2.0 - 100.0)).abs() < 0.05,
            "east must be LEFT (smaller column): {east:?}"
        );
        assert!((east.1 - SIM_H as f64 / 2.0).abs() < 0.05, "{east:?}");
    }

    /// A rotator angle turns the field about the sensor centre.
    #[test]
    fn rotation_turns_the_field_about_the_frame_centre() {
        let mut sky = sky_view(Vec::new());
        let north_deg = 100.0 * sky.arcsec_per_px / 3600.0;
        let target = star(sky.centre_ra_deg, sky.centre_dec_deg + north_deg, 8.0);
        sky.rotation_deg = 90.0;
        let rotated = project_star(&sky, SIM_W as f64, SIM_H as f64, &target).unwrap();
        // What was 100 px above the centre is now 100 px to one side of it, at
        // the same radius.
        let dx = rotated.0 - SIM_W as f64 / 2.0;
        let dy = rotated.1 - SIM_H as f64 / 2.0;
        assert!(dx.hypot(dy) - 100.0 < 0.05, "radius must be preserved");
        assert!(dy.abs() < 0.05, "{rotated:?}");
        assert!((dx.abs() - 100.0).abs() < 0.05, "{rotated:?}");
    }

    /// The far side of the sky does not fold back onto the frame.
    #[test]
    fn stars_beyond_the_tangent_horizon_do_not_project() {
        let sky = sky_view(Vec::new());
        assert!(project_star(
            &sky,
            SIM_W as f64,
            SIM_H as f64,
            &star(sky.centre_ra_deg + 180.0, -sky.centre_dec_deg, 8.0),
        )
        .is_none());
    }

    /// A catalogue field renders stars the REAL detector finds, which is the
    /// whole bar: a frame the detector cannot measure is one the solver cannot
    /// solve either.
    #[test]
    fn a_sky_field_yields_detectable_stars() {
        // A synthetic grid rather than a real catalogue, so the test does not
        // need a star database installed.
        let sky = sky_view(grid_field(0.7756));
        let request = SimFrameRequest {
            sky: Some(sky),
            ..Default::default()
        };
        let buffer = frame(&request);
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let found = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        assert!(
            found.stars.len() >= 10,
            "sky field produced only {} detectable stars; autofocus alone needs 10",
            found.stars.len()
        );
    }

    /// Stars are placed where the projection says, not merely somewhere.
    #[test]
    fn the_brightest_sky_star_lands_at_its_projected_pixel() {
        let sky = sky_view(vec![star(83.822, -5.391, 8.0)]);
        let (want_x, want_y) =
            project_star(&sky, SIM_W as f64, SIM_H as f64, &sky.stars[0]).unwrap();
        let buffer = frame(&SimFrameRequest {
            sky: Some(sky),
            ..Default::default()
        });
        let (got_x, got_y) = brightest_star_in(&buffer);
        assert!(
            (got_x - want_x).abs() < 1.0 && (got_y - want_y).abs() < 1.0,
            "star rendered at ({got_x:.1}, {got_y:.1}), projection said \
             ({want_x:.1}, {want_y:.1})"
        );
    }

    /// A pointing change moves the field, which is what makes Slew & Center and
    /// the centring loop exercisable offline.
    #[test]
    fn moving_the_pointing_moves_the_rendered_field() {
        let stars = vec![star(83.822, -5.391, 8.0)];
        let centred = frame(&SimFrameRequest {
            sky: Some(sky_view(stars.clone())),
            ..Default::default()
        });
        let mut nudged_view = sky_view(stars);
        // 200 pixels' worth of declination.
        nudged_view.centre_dec_deg -= 200.0 * nudged_view.arcsec_per_px / 3600.0;
        let nudged = frame(&SimFrameRequest {
            sky: Some(nudged_view),
            ..Default::default()
        });

        let before = brightest_star_in(&centred);
        let after = brightest_star_in(&nudged);
        // The star is fixed on the sky, so dropping the pointing south puts it
        // further north of centre — UP the frame, at a smaller row.
        assert!(
            (before.1 - after.1 - 200.0).abs() < 2.0,
            "dropping the pointing 200 px south should move the star 200 px up \
             the frame: {before:?} -> {after:?}"
        );
        assert!(
            (after.0 - before.0).abs() < 2.0,
            "a declination-only move must not shift the star in x: \
             {before:?} -> {after:?}"
        );
    }

    /// Same pointing and same seed, same frame.
    #[test]
    fn sky_rendering_is_deterministic() {
        let request = || SimFrameRequest {
            sky: Some(sky_view(grid_field(0.7756))),
            seed: 1234,
            ..Default::default()
        };
        assert_eq!(digest(&frame(&request())), digest(&frame(&request())));
    }

    /// A field with nothing in it falls back to a clean sky rather than a
    /// division by an empty magnitude range.
    #[test]
    fn an_empty_sky_field_renders_a_starless_frame() {
        let buffer = frame(&SimFrameRequest {
            sky: Some(sky_view(Vec::new())),
            ..Default::default()
        });
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let found = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        assert!(found.stars.is_empty(), "got {} stars", found.stars.len());
    }

    /// The sky path still defocuses on the focuser, so autofocus keeps working
    /// against a real-sky frame.
    #[test]
    fn sky_stars_defocus_with_the_focuser() {
        let hfr = |position: i32| {
            let buffer = frame(&SimFrameRequest {
                sky: Some(sky_view(grid_field(0.7756))),
                focus_position: Some(position),
                ..Default::default()
            });
            let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
            let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
            let mut hfrs: Vec<f64> = result.stars.iter().map(|s| s.hfr).collect();
            assert!(!hfrs.is_empty(), "no stars at focuser {position}");
            hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap());
            hfrs[hfrs.len() / 2]
        };
        let sharp = hfr(SIM_TRUE_FOCUS);
        let blurred = hfr(SIM_TRUE_FOCUS + 200);
        assert!(
            blurred > sharp * 1.3,
            "defocused HFR {blurred:.2} should exceed in-focus {sharp:.2}"
        );
    }

    /// A field radius covers the sensor's corners, not just its centre.
    #[test]
    fn field_radius_covers_the_sensor_diagonal() {
        let scale = 0.7756;
        let radius = sim_sky_field_radius_deg(SIM_W, SIM_H, scale);
        let half_diagonal =
            (SIM_W as f64 * scale / 3600.0).hypot(SIM_H as f64 * scale / 3600.0) / 2.0;
        assert!(radius > half_diagonal, "{radius} vs {half_diagonal}");
        assert!(radius < half_diagonal * 1.5, "{radius} vs {half_diagonal}");
    }

    /// A grid of stars spanning the sensor, spaced far enough apart that the
    /// detector resolves them individually.
    fn grid_field(arcsec_per_px: f64) -> Vec<crate::sim_sky::SkyStar> {
        let centre_ra: f64 = 83.822;
        let centre_dec: f64 = -5.391;
        let step_deg = 90.0 * arcsec_per_px / 3600.0;
        let mut stars = Vec::new();
        for row in -4i32..=4 {
            for col in -8i32..=8 {
                stars.push(star(
                    centre_ra + f64::from(col) * step_deg / centre_dec.to_radians().cos(),
                    centre_dec + f64::from(row) * step_deg,
                    // A spread wide enough that the brightness ladder is
                    // exercised rather than 153 identical stars.
                    9.0 + f64::from((row + col).rem_euclid(5)),
                ));
            }
        }
        stars
    }
}
