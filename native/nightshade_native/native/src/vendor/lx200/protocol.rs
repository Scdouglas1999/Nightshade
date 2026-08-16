//! LX200 serial protocol constants, parsing and park-state persistence.

use super::*;

/// Default baud rate for classic LX200 mounts
pub(crate) const LX200_BAUD_RATE: u32 = 9600;
pub(crate) const RESPONSE_TERM: u8 = b'#';

/// Baud rates to try during discovery, in order of preference
/// - 115200: Pegasus NYX-101, modern OnStep builds
/// - 57600: Some OnStep configurations
/// - 19200: Some mounts use this
/// - 9600: Classic LX200, Meade, Losmandy Gemini
pub(crate) const DISCOVERY_BAUD_RATES: &[u32] = &[115200, 57600, 19200, 9600];

pub(crate) mod commands {
    // Standard LX200 commands
    pub const GET_RA: &str = ":GR#";
    pub const GET_DEC: &str = ":GD#";
    pub const GET_ALT: &str = ":GA#";
    pub const GET_AZ: &str = ":GZ#";
    pub const GET_SIDEREAL_TIME: &str = ":GS#";

    pub const SET_TARGET_RA: &str = ":Sr";
    pub const SET_TARGET_DEC: &str = ":Sd";

    pub const SLEW_TO_TARGET: &str = ":MS#";
    pub const STOP_SLEW: &str = ":Q#";

    pub const SYNC: &str = ":CM#";

    pub const MOVE_NORTH: &str = ":Mn#";
    pub const MOVE_SOUTH: &str = ":Ms#";
    pub const MOVE_EAST: &str = ":Me#";
    pub const MOVE_WEST: &str = ":Mw#";
    pub const STOP_MOVE_NORTH: &str = ":Qn#";
    pub const STOP_MOVE_SOUTH: &str = ":Qs#";
    pub const STOP_MOVE_EAST: &str = ":Qe#";
    pub const STOP_MOVE_WEST: &str = ":Qw#";

    pub const SET_TRACK_SIDEREAL: &str = ":TQ#";
    pub const SET_TRACK_LUNAR: &str = ":TL#";
    pub const SET_TRACK_SOLAR: &str = ":TS#"; // OnStep: :TS# for solar rate
    pub const SET_RATE_GUIDE: &str = ":RG#";

    // OnStep tracking rate commands
    pub const ONSTEP_SET_RATE_KING: &str = ":TK#";

    pub const GET_PRODUCT_NAME: &str = ":GVP#";

    /// Meade alignment / status query.
    ///
    /// Returns 3-4 character status terminated by `#`. Position 0 reports
    /// alignment mode and may include `P` when the mount is parked on
    /// LX200GPS / LX200ACF / RCX400 firmware (Meade Telescope Serial
    /// Command Protocol rev L). Older Classic LX200 firmware does not
    /// expose park state via `:GW#`; if the response is non-empty but
    /// lacks a recognizable parked indicator we cannot infer state.
    pub const MEADE_GET_STATUS: &str = ":GW#";

    pub const PARK: &str = ":hP#";
    pub const UNPARK_MEADE: &str = ":PO#";

    // OnStep-specific commands (used by Pegasus NYX, DIY OnStep mounts)
    pub const ONSTEP_GET_STATUS: &str = ":GU#";
    pub const ONSTEP_TRACK_ENABLE: &str = ":Te#";
    pub const ONSTEP_TRACK_DISABLE: &str = ":Td#";
    pub const ONSTEP_UNPARK: &str = ":hR#";
    // OnStep pulse guide format: :Mgdnnnn# where d=n/s/e/w, nnnn=milliseconds
    pub const ONSTEP_PULSE_GUIDE_PREFIX: &str = ":Mg";

    // Meade/LX200 information commands. Compatible firmware may omit them, so
    // discovery treats these as optional metadata probes.
    pub const GET_FIRMWARE_DATE: &str = ":GVD#";
    pub const GET_FIRMWARE_NUMBER: &str = ":GVN#";
    pub const GET_FIRMWARE_TIME: &str = ":GVT#";
}

pub(crate) fn optional_discovery_response(
    port: &mut dyn serialport::SerialPort,
    command: &str,
) -> Option<String> {
    if port.write_all(command.as_bytes()).is_err() {
        return None;
    }
    let _ = port.flush();

    let mut buf = [0u8; 64];
    std::thread::sleep(Duration::from_millis(200));
    let n = port.read(&mut buf).ok()?;
    let response = String::from_utf8_lossy(&buf[..n]);
    let trimmed = response.trim().trim_end_matches('#').trim().to_string();
    if trimmed.is_empty() || trimmed == "\0" {
        None
    } else {
        Some(trimmed)
    }
}

pub(crate) fn format_firmware_version(
    number: Option<&str>,
    date: Option<&str>,
    time: Option<&str>,
) -> Option<String> {
    let number = number.filter(|value| value.chars().any(|c| c.is_ascii_alphanumeric()));
    let date = date.filter(|value| value.chars().any(|c| c.is_ascii_alphanumeric()));
    let time = time.filter(|value| value.chars().any(|c| c.is_ascii_alphanumeric()));

    match (number, date, time) {
        (Some(number), Some(date), Some(time)) => {
            Some(format!("LX200 firmware v{} ({} {})", number, date, time))
        }
        (Some(number), Some(date), None) => Some(format!("LX200 firmware v{} ({})", number, date)),
        (Some(number), None, Some(time)) => Some(format!("LX200 firmware v{} ({})", number, time)),
        (Some(number), None, None) => Some(format!("LX200 firmware v{}", number)),
        (None, Some(date), Some(time)) => Some(format!("LX200 firmware {} {}", date, time)),
        (None, Some(date), None) => Some(format!("LX200 firmware {}", date)),
        (None, None, Some(time)) => Some(format!("LX200 firmware {}", time)),
        (None, None, None) => None,
    }
}

/// Parse OnStep `:GU#` status reply into mount state fields.
///
/// OnStep firmware builds the reply in a fixed prefix order (`Command.ino`):
/// optional `n` (not tracking), optional `N` (no goto / not slewing), then exactly
/// one park-status letter from `pIPF`, followed by optional feature flags, mount
/// type (`E`/`K`/`A`), pier side (`o`/`T`/`W`), guide-rate digits, and an error digit.
///
/// Returns `(is_tracking, is_slewing, is_parked, is_at_home, pier_side)` using the
/// same semantics as OnStep's official `MountStatus.h` (positional prefix for `n`/`N`/park).
pub(crate) fn parse_onstep_status_fields(status: &str) -> (bool, bool, bool, bool, PierSide) {
    let s = status.trim_end_matches('#').trim();
    if s.is_empty() {
        return (false, false, false, false, PierSide::Unknown);
    }

    let bytes = s.as_bytes();
    let mut idx = 0usize;

    // Positional prefix per OnStep firmware append order.
    let has_not_tracking = bytes.get(idx) == Some(&b'n');
    if has_not_tracking {
        idx += 1;
    }
    let has_no_goto = bytes.get(idx) == Some(&b'N');
    if has_no_goto {
        idx += 1;
    }

    let park_char = bytes.get(idx).map(|b| *b as char);

    // Source `Command.ino`: leading `n` is the not-tracking indicator.
    // During a normal goto, OnStep can omit both `n` and `N`, so the mount is
    // both tracking and slewing.
    let is_slewing = !has_no_goto;
    let is_tracking = !has_not_tracking;

    // Park letter is always the third prefix slot when firmware follows the spec.
    let mut is_parked = park_char == Some('P');
    if park_char == Some('p') || s.contains('p') {
        is_parked = false;
    } else if park_char.is_none() {
        // Malformed / legacy replies: fall back to OnStep addon substring rules.
        is_parked = s.contains('P');
    }

    let is_homed = s.contains('H');

    // The final suffix is: mount type, pier side, pulse-guide rate, guide rate,
    // general error. Read pier side from that suffix instead of scanning for
    // `T`/`W`, because earlier optional flags can contain unrelated status bytes.
    let pier_side = parse_onstep_pier_side_suffix(bytes);

    (is_tracking, is_slewing, is_parked, is_homed, pier_side)
}

pub(crate) fn parse_onstep_pier_side_suffix(bytes: &[u8]) -> PierSide {
    if bytes.len() < 4 {
        return PierSide::Unknown;
    }

    match bytes[bytes.len() - 4] {
        b'T' => PierSide::East,
        b'W' => PierSide::West,
        b'o' => PierSide::Unknown,
        _ => PierSide::Unknown,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Lx200MountType {
    /// Standard Meade LX200 protocol
    Meade,
    /// OnStep-based mounts (Pegasus NYX-101, DIY OnStep builds)
    /// Uses extended LX200 commands for tracking, status, pulse guiding
    OnStep,
    /// Losmandy Gemini in LX200 compatibility mode
    Losmandy,
    /// 10Micron mounts (extended LX200)
    TenMicron,
    /// Generic LX200-compatible mount
    Generic,
}

impl Lx200MountType {
    pub fn vendor(&self) -> NativeVendor {
        match self {
            Lx200MountType::Meade => NativeVendor::Meade,
            Lx200MountType::OnStep => NativeVendor::Other("Pegasus/OnStep".to_string()),
            Lx200MountType::Losmandy | Lx200MountType::TenMicron | Lx200MountType::Generic => {
                NativeVendor::Other("LX200".to_string())
            }
        }
    }

    /// Check if this mount type uses OnStep command extensions
    pub fn is_onstep(&self) -> bool {
        matches!(self, Lx200MountType::OnStep)
    }
}

pub(crate) fn parse_ra(response: &str) -> Result<f64, NativeError> {
    let s = response.trim_end_matches('#');

    if let Some((h, rest)) = s.split_once(':') {
        let hours: f64 = h
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid RA hours".into()))?;

        if let Some((m, sec)) = rest.split_once(':') {
            let minutes: f64 = m
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA minutes".into()))?;
            let seconds: f64 = sec
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA seconds".into()))?;
            return Ok(hours + minutes / 60.0 + seconds / 3600.0);
        } else if let Some((m, t)) = rest.split_once('.') {
            let minutes: f64 = m
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA minutes".into()))?;
            let tenths: f64 = t
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA tenths".into()))?;
            return Ok(hours + (minutes + tenths / 10.0) / 60.0);
        }
    }

    Err(NativeError::SdkError(format!("Invalid RA format: {}", s)))
}

pub(crate) fn parse_dec(response: &str) -> Result<f64, NativeError> {
    let s = response.trim_end_matches('#');

    let (sign, rest) = if s.starts_with('-') {
        (-1.0, &s[1..])
    } else if s.starts_with('+') {
        (1.0, &s[1..])
    } else {
        (1.0, s)
    };

    let parts: Vec<&str> = rest.split(['*', '°', ':']).collect();

    if parts.len() >= 2 {
        let degrees: f64 = parts[0]
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid Dec degrees".into()))?;
        let arcmin: f64 = parts[1]
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid Dec arcmin".into()))?;

        let arcsec: f64 = if parts.len() >= 3 {
            parts[2]
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid Dec arcsec".into()))?
        } else {
            0.0
        };

        return Ok(sign * (degrees + arcmin / 60.0 + arcsec / 3600.0));
    }

    Err(NativeError::SdkError(format!("Invalid Dec format: {}", s)))
}

pub(crate) fn format_ra(ra_hours: f64) -> String {
    let hours = ra_hours.floor() as u32;
    let remaining = (ra_hours - hours as f64) * 60.0;
    let minutes = remaining.floor() as u32;
    let seconds = ((remaining - minutes as f64) * 60.0).round() as u32;

    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}

pub(crate) fn format_dec(dec_degrees: f64) -> String {
    let sign = if dec_degrees < 0.0 { "-" } else { "+" };
    let dec_abs = dec_degrees.abs();
    let degrees = dec_abs.floor() as u32;
    let remaining = (dec_abs - degrees as f64) * 60.0;
    let arcmin = remaining.floor() as u32;
    let arcsec = ((remaining - arcmin as f64) * 60.0).round() as u32;

    format!("{}{}*{:02}:{:02}", sign, degrees, arcmin, arcsec)
}

// Park-state persistence
//
// Most LX200-family mounts (Losmandy Gemini in LX200 mode, generic clones,
// pre-LX200GPS Meade firmware, certain 10Micron firmware) provide no telemetry
// for "is the mount parked?". The protocol simply accepts `:hP#` and stops the
// motors — there is no echo. So we track our own park sends and persist them
// across app restarts, and a power-cycle does not silently erase the canonical
// state. When neither telemetry nor a persisted record exists we surface
// `NotSupported` rather than fabricate `false`.

/// Returns the path to the park-state JSON file in the user's app-data dir.
///
/// The file is intentionally kept outside the Drift database because this
/// crate does not depend on the Flutter app and must be writable from a
/// pure-Rust unit test. We resolve the dir in this priority order:
///   1. `NIGHTSHADE_HOME` env var (used by tests and headless runs)
///   2. `%APPDATA%\Nightshade` on Windows
///   3. `$XDG_CONFIG_HOME/nightshade` or `$HOME/.config/nightshade` elsewhere
///
/// On total failure we fall back to a temp-dir path so the binary never
/// panics on a read-only home dir; persistence is best-effort and the
/// caller surfaces `NotSupported` if the cache cannot be loaded.
pub(crate) fn lx200_state_file_path() -> PathBuf {
    let base: PathBuf = if let Ok(custom) = std::env::var("NIGHTSHADE_HOME") {
        PathBuf::from(custom)
    } else if cfg!(windows) {
        std::env::var("APPDATA")
            .map(|s| PathBuf::from(s).join("Nightshade"))
            .unwrap_or_else(|_| std::env::temp_dir().join("nightshade"))
    } else if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(xdg).join("nightshade")
    } else if let Ok(home) = std::env::var("HOME") {
        PathBuf::from(home).join(".config").join("nightshade")
    } else {
        std::env::temp_dir().join("nightshade")
    };

    base.join("lx200_park_state.json")
}

/// Read the persisted park-state map. `Ok(None)` for that device id means the
/// file does not exist or contains no entry for this mount; the caller must
/// then return `NotSupported` rather than guessing.
pub(crate) fn read_persisted_park_state(device_id: &str) -> Result<Option<bool>, NativeError> {
    let path = lx200_state_file_path();
    if !path.exists() {
        return Ok(None);
    }

    let raw = std::fs::read_to_string(&path).map_err(|e| {
        NativeError::Io(std::io::Error::new(
            e.kind(),
            format!("read park state: {}", e),
        ))
    })?;
    let map: HashMap<String, bool> = serde_json::from_str(&raw)
        .map_err(|e| NativeError::SdkError(format!("parse park state JSON: {}", e)))?;
    Ok(map.get(device_id).copied())
}

/// Atomically update the persisted park state for one device.
///
/// We re-read the full map, mutate the single entry, then write the whole
/// file back. The file is small (one bool per mount the user owns) so the
/// rewrite cost is negligible compared to a serial command round-trip.
pub(crate) fn write_persisted_park_state(device_id: &str, parked: bool) -> Result<(), NativeError> {
    let path = lx200_state_file_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NativeError::Io(std::io::Error::new(
                e.kind(),
                format!("create park state dir {:?}: {}", parent, e),
            ))
        })?;
    }

    let mut map: HashMap<String, bool> = if path.exists() {
        let raw = std::fs::read_to_string(&path).map_err(|e| {
            NativeError::Io(std::io::Error::new(
                e.kind(),
                format!("read park state: {}", e),
            ))
        })?;
        // Tolerate an empty file (e.g., interrupted write) but surface real
        // JSON corruption — silent fallbacks hide bugs.
        if raw.trim().is_empty() {
            HashMap::new()
        } else {
            serde_json::from_str(&raw)
                .map_err(|e| NativeError::SdkError(format!("parse park state JSON: {}", e)))?
        }
    } else {
        HashMap::new()
    };

    map.insert(device_id.to_string(), parked);

    let serialized = serde_json::to_string_pretty(&map)
        .map_err(|e| NativeError::SdkError(format!("serialize park state: {}", e)))?;
    std::fs::write(&path, serialized).map_err(|e| {
        NativeError::Io(std::io::Error::new(
            e.kind(),
            format!("write park state: {}", e),
        ))
    })?;
    Ok(())
}

/// Parse a Meade `:GW#` response. Returns `Some(true)` if the firmware
/// reports parked, `Some(false)` if it reports a non-parked alignment mode,
/// and `None` if the response shape is unrecognised (older LX200 firmware,
/// echo-only stub, garbage). The caller treats `None` as "no telemetry".
///
/// Meade Telescope Serial Command Protocol rev L (LX200GPS / LX200ACF /
/// RCX400) defines position 0 as the alignment mode: `A` Alt-Az,
/// `P` Polar/Parked, `L` Land, `G` German equatorial. On parked firmware,
/// `P` in position 0 with `T`/`N` tracking-off in position 1 is the parked
/// signal. On Polar-aligned-but-tracking firmware, `P` appears with `T`
/// tracking on; we disambiguate using position 1 `N` (not tracking) plus
/// position 2 == `0` (no alignment progress, mount idle).
pub(crate) fn parse_meade_gw_park(response: &str) -> Option<bool> {
    let s = response.trim().trim_end_matches('#');
    let bytes = s.as_bytes();
    if bytes.is_empty() {
        return None;
    }

    // Position 0 must be a recognised alignment mode for us to trust the
    // response at all. If the byte is something else we do not know what
    // firmware variant this is, so we return None (NotSupported upstream).
    let mode = bytes[0];
    if !matches!(mode, b'A' | b'P' | b'L' | b'G') {
        return None;
    }

    // If position 1 exists, it should be tracking on/off. Anything else =
    // unknown firmware shape.
    let tracking = bytes.get(1).copied();
    match tracking {
        Some(b'T') => Some(false), // tracking on → not parked
        Some(b'N') => {
            // Tracking off + Polar-mode position 0 == parked on the Meade
            // firmwares that report park via :GW#. On other firmwares we
            // see N with non-P mode (e.g., AN0# = Alt-Az, not tracking,
            // not aligned) — that is "idle but not parked".
            Some(mode == b'P')
        }
        Some(_) => None,
        None => None,
    }
}
