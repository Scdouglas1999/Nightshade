//! Small hard-coded star table for dev snapshot publishing until catalog tiles land.

/// J2000 star used by the snapshot pipeline before real catalog queries exist.
#[derive(Debug, Clone, Copy)]
pub struct DevStar {
    /// HIP catalog id (stable [`ObjectId`](super::ObjectId)).
    pub hip: u64,
    /// ICRS right ascension (radians).
    pub ra_rad: f64,
    /// ICRS declination (radians).
    pub dec_rad: f64,
    /// Apparent V magnitude.
    pub mag: f32,
    /// Display name for label overlays.
    pub name: &'static str,
}

/// Bright reference stars with IAU-standard approximate J2000 coordinates.
pub const DEV_STARS: &[DevStar] = &[
    DevStar {
        hip: 11767,
        ra_rad: 0.662_062,
        dec_rad: 1.557_896,
        mag: 1.98,
        name: "Polaris",
    },
    DevStar {
        hip: 91262,
        ra_rad: 4.872_013,
        dec_rad: 0.676_757,
        mag: 0.03,
        name: "Vega",
    },
    DevStar {
        hip: 32349,
        ra_rad: 1.767_015,
        dec_rad: -0.291_808,
        mag: -1.46,
        name: "Sirius",
    },
    DevStar {
        hip: 69673,
        ra_rad: 3.733_271,
        dec_rad: 0.326_741,
        mag: -0.05,
        name: "Arcturus",
    },
    DevStar {
        hip: 27989,
        ra_rad: 1.549_558,
        dec_rad: 0.158_137,
        mag: 0.42,
        name: "Betelgeuse",
    },
];
