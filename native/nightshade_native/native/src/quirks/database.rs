//! Vendor Quirks Database
//!
//! This module contains the built-in database of known device quirks.
//! Quirks are organized by vendor and device model.
//!
//! ## Adding New Quirks
//!
//! To add quirks for a new device:
//! 1. Add a constant for the device pattern
//! 2. Add the quirks to the appropriate vendor function
//! 3. Document the source of the quirk (firmware version, SDK bug, etc.)

use super::types::*;
use crate::NativeVendor;

// ============================================================================
// ZWO QUIRKS
// ============================================================================

/// Get quirks for ZWO devices
fn zwo_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All ZWO cameras report temperature as 10x the actual value
        // Source: ASI SDK documentation and empirical testing
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Temperature(TemperatureQuirk::ScaleFactor(10.0)),
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                Quirk::Discovery(DiscoveryQuirk::RequiresSerializedDiscovery),
            ],
        ),
        // ASI294MC Pro specific quirks
        // Source: User reports of first temperature read being incorrect
        (
            QuirkMatcher::ModelContains("ASI294"),
            vec![Quirk::Temperature(TemperatureQuirk::SkipFirstRead)],
        ),
        // ASI533MC specific quirks
        // Source: User reports of connection timing issues
        (
            QuirkMatcher::ModelContains("ASI533"),
            vec![Quirk::Timing(TimingQuirk::DelayAfterConnect(200))],
        ),
        // ASI2600 series - higher bit depth sensor
        (
            QuirkMatcher::ModelContains("ASI2600"),
            vec![
                Quirk::Camera(CameraQuirk::ActualBitDepth(14)),
                Quirk::Camera(CameraQuirk::RoiMultiple(8)),
            ],
        ),
        // ASI6200MM Pro - full frame sensor
        (
            QuirkMatcher::ModelContains("ASI6200"),
            vec![
                Quirk::Camera(CameraQuirk::ActualBitDepth(16)),
                Quirk::Camera(CameraQuirk::RoiMultiple(8)),
                Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(30)),
            ],
        ),
        // ZWO EFW filter wheels may report wrong position immediately after move
        // Source: User reports and forum discussions
        (
            QuirkMatcher::ModelContains("EFW"),
            vec![Quirk::Position(PositionQuirk::DelayAfterMoveMs(500))],
        ),
        // ZWO EAF focuser step sizes — SDK does not expose mechanical travel per step,
        // so the value is declared per model from ZWO's published gear-ratio specs.
        // Order matters: more specific matchers (EAF-S, EAF-2) precede the generic EAF
        // entry so the first FocuserStepSizeMicrons quirk found is the model-correct one.
        //
        // EAF-S (compact, 7:1 internal reduction): 0.7 um/step.
        (
            QuirkMatcher::ModelContains("EAF-S"),
            vec![Quirk::Position(PositionQuirk::FocuserStepSizeMicrons(0.7))],
        ),
        // EAF-2 (second-generation, finer reduction stage): 1.5 um/step.
        (
            QuirkMatcher::ModelContains("EAF-2"),
            vec![Quirk::Position(PositionQuirk::FocuserStepSizeMicrons(1.5))],
        ),
        // ZWO EAF focusers (original): 8 um/step is ZWO's published mechanical travel.
        (
            QuirkMatcher::ModelContains("EAF"),
            vec![
                Quirk::Temperature(TemperatureQuirk::ScaleFactor(10.0)),
                Quirk::Position(PositionQuirk::BacklashSteps(50)),
                Quirk::Position(PositionQuirk::FocuserStepSizeMicrons(8.0)),
            ],
        ),
    ]
}

// ============================================================================
// QHY QUIRKS
// ============================================================================

/// Get quirks for QHY devices
fn qhy_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // QHY SDK can crash during discovery if called concurrently
        // Source: SDK documentation and empirical testing
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                Quirk::Discovery(DiscoveryQuirk::RequiresSerializedDiscovery),
                Quirk::Discovery(DiscoveryQuirk::RequiresSdkInit),
                // QHY SDK initialization can fail on first call
                Quirk::Discovery(DiscoveryQuirk::DiscoveryTimeoutMs(10000)),
            ],
        ),
        // QHY268M has specific cooling quirks
        // Source: User reports
        (
            QuirkMatcher::ModelContains("QHY268"),
            vec![
                Quirk::Camera(CameraQuirk::CoolerRange {
                    min_temp: -35.0,
                    max_temp: 25.0,
                }),
                Quirk::Temperature(TemperatureQuirk::RequiresDelayMs(100)),
            ],
        ),
        // QHY600 series - large sensor with specific quirks
        (
            QuirkMatcher::ModelContains("QHY600"),
            vec![
                Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(45)),
                Quirk::Camera(CameraQuirk::ActualBitDepth(16)),
                Quirk::Camera(CameraQuirk::RoiMultiple(8)),
            ],
        ),
        // QHY CFW3 filter wheels
        (
            QuirkMatcher::ModelContains("CFW"),
            vec![
                Quirk::Position(PositionQuirk::DelayAfterMoveMs(300)),
                Quirk::Timing(TimingQuirk::DelayBetweenCommands(50)),
            ],
        ),
        // QHY5III series guide cameras
        (
            QuirkMatcher::ModelContains("QHY5III"),
            vec![
                Quirk::Camera(CameraQuirk::UsbBandwidthLimit(80)),
                Quirk::Exposure(ExposureQuirk::MinExposureMs(1)),
            ],
        ),
    ]
}

// ============================================================================
// PLAYER ONE QUIRKS
// ============================================================================

/// Get quirks for Player One devices
fn player_one_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Player One cameras
        // Source: POA SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                Quirk::Discovery(DiscoveryQuirk::RequiresSerializedDiscovery),
                // Player One temperature is in proper degrees, but some models have issues
                Quirk::Temperature(TemperatureQuirk::RequiresDelayMs(50)),
            ],
        ),
        // Poseidon-C series
        (
            QuirkMatcher::ModelContains("Poseidon"),
            vec![
                Quirk::Camera(CameraQuirk::ActualBitDepth(14)),
                Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(20)),
            ],
        ),
        // Neptune-C II
        (
            QuirkMatcher::ModelContains("Neptune"),
            vec![Quirk::Camera(CameraQuirk::UsbBandwidthLimit(70))],
        ),
    ]
}

// ============================================================================
// SVBONY QUIRKS
// ============================================================================

/// Get quirks for SVBony devices
fn svbony_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All SVBony cameras report temperature * 10
        // Source: SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Temperature(TemperatureQuirk::ScaleFactor(10.0)),
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                // SVBony SDK can be slow to initialize
                Quirk::Timing(TimingQuirk::DelayAfterConnect(100)),
            ],
        ),
        // SV705C - newer sensor
        (
            QuirkMatcher::ModelContains("SV705"),
            vec![
                Quirk::Camera(CameraQuirk::ActualBitDepth(12)),
                Quirk::Camera(CameraQuirk::RoiMultiple(4)),
            ],
        ),
    ]
}

// ============================================================================
// ATIK QUIRKS
// ============================================================================

/// Get quirks for Atik devices
fn atik_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Atik cameras report temperature * 100
        // Source: Artemis SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Temperature(TemperatureQuirk::ScaleFactor(100.0)),
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
            ],
        ),
        // Atik 16200 - CCD sensor
        (
            QuirkMatcher::ModelContains("16200"),
            vec![
                Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(40)),
                Quirk::Camera(CameraQuirk::ActualBitDepth(16)),
            ],
        ),
        // Atik One series
        (
            QuirkMatcher::ModelContains("One"),
            vec![Quirk::Camera(CameraQuirk::CoolerRange {
                min_temp: -40.0,
                max_temp: 20.0,
            })],
        ),
    ]
}

// ============================================================================
// TOUPTEK QUIRKS
// ============================================================================

/// Get quirks for Touptek/Ogma devices
fn touptek_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Touptek cameras report temperature * 10
        // Source: Ogmacam SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Temperature(TemperatureQuirk::ScaleFactor(10.0)),
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
            ],
        ),
    ]
}

// ============================================================================
// MORAVIAN QUIRKS
// ============================================================================

/// Get quirks for Moravian devices
fn moravian_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Moravian cameras
        // Source: gXusb SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                Quirk::Exposure(ExposureQuirk::DarkFrameRequiresShutter),
            ],
        ),
        // G4 series
        (
            QuirkMatcher::ModelContains("G4"),
            vec![
                Quirk::Camera(CameraQuirk::ActualBitDepth(16)),
                Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(30)),
            ],
        ),
    ]
}

// ============================================================================
// FLI QUIRKS
// ============================================================================

/// Get quirks for FLI devices
fn fli_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All FLI cameras
        // Source: FLI SDK documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                Quirk::Exposure(ExposureQuirk::DarkFrameRequiresShutter),
            ],
        ),
        // ML series
        (
            QuirkMatcher::ModelContains("ML"),
            vec![Quirk::Exposure(ExposureQuirk::ExtendedDownloadTimeoutSecs(
                60,
            ))],
        ),
    ]
}

// ============================================================================
// SKY-WATCHER MOUNT QUIRKS
// ============================================================================

/// Get quirks for Sky-Watcher mounts
fn skywatcher_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Sky-Watcher mounts using EQMod protocol
        // Source: EQMod documentation and user reports
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Communication(CommunicationQuirk::RequiredBaudRate(9600)),
                Quirk::Timing(TimingQuirk::DelayBetweenCommands(50)),
            ],
        ),
        // EQ6-R Pro
        (
            QuirkMatcher::ModelContains("EQ6"),
            vec![
                Quirk::Mount(MountQuirk::GotoPrecisionArcsec(30.0)),
                Quirk::Mount(MountQuirk::GuideRateScale(0.5)),
            ],
        ),
        // AZ-GTi - needs specific handling for alt-az mode
        (
            QuirkMatcher::ModelContains("GTi"),
            vec![
                Quirk::Mount(MountQuirk::GotoPrecisionArcsec(60.0)),
                Quirk::Timing(TimingQuirk::DelayAfterConnect(1000)),
            ],
        ),
    ]
}

// ============================================================================
// IOPTRON MOUNT QUIRKS
// ============================================================================

/// Get quirks for iOptron mounts
fn ioptron_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All iOptron mounts
        // Source: iOptron command protocol documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Communication(CommunicationQuirk::RequiredBaudRate(115200)),
                Quirk::Communication(CommunicationQuirk::LineEnding("#".to_string())),
            ],
        ),
        // CEM series
        (
            QuirkMatcher::ModelContains("CEM"),
            vec![
                Quirk::Mount(MountQuirk::GotoPrecisionArcsec(15.0)),
                Quirk::Mount(MountQuirk::SyncRequiresAlignment),
            ],
        ),
        // GEM series
        (
            QuirkMatcher::ModelContains("GEM"),
            vec![Quirk::Mount(MountQuirk::GotoPrecisionArcsec(20.0))],
        ),
    ]
}

// ============================================================================
// LX200 MOUNT QUIRKS
// ============================================================================

/// Get quirks for LX200-compatible mounts
fn lx200_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All LX200-compatible mounts
        // Source: LX200 protocol documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Communication(CommunicationQuirk::RequiredBaudRate(9600)),
                Quirk::Communication(CommunicationQuirk::LineEnding("#".to_string())),
                // LX200 protocol has quirky response parsing
                Quirk::Timing(TimingQuirk::DelayBetweenCommands(100)),
            ],
        ),
        // Meade LX200 GPS
        (
            QuirkMatcher::ModelContains("LX200GPS"),
            vec![
                Quirk::Mount(MountQuirk::GotoPrecisionArcsec(30.0)),
                Quirk::Timing(TimingQuirk::ExtendedConnectionTimeout(5000)),
            ],
        ),
        // OnStep controllers emulating LX200
        (
            QuirkMatcher::ModelContains("OnStep"),
            vec![
                Quirk::Mount(MountQuirk::GotoPrecisionArcsec(5.0)),
                Quirk::Communication(CommunicationQuirk::RequiredBaudRate(115200)),
            ],
        ),
    ]
}

// ============================================================================
// ASCOM QUIRKS (for ASCOM drivers in general)
// ============================================================================

/// Get quirks for ASCOM devices
fn ascom_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All ASCOM devices
        // Source: ASCOM documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                Quirk::Discovery(DiscoveryQuirk::NotThreadSafe),
                // COM objects need proper apartment threading
                Quirk::Timing(TimingQuirk::DelayAfterDisconnect(100)),
            ],
        ),
    ]
}

// ============================================================================
// ALPACA QUIRKS (for Alpaca devices in general)
// ============================================================================

/// Get quirks for Alpaca devices
fn alpaca_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All Alpaca devices
        // Source: Alpaca documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                // HTTP-based protocol has inherent latency
                Quirk::Timing(TimingQuirk::DelayBetweenCommands(10)),
                // Alpaca devices may take time to respond during exposure
                Quirk::Timing(TimingQuirk::ExposurePollingIntervalMs(500)),
            ],
        ),
    ]
}

// ============================================================================
// INDI QUIRKS
// ============================================================================

/// Get quirks for INDI devices
fn indi_quirks() -> Vec<(QuirkMatcher, Vec<Quirk>)> {
    vec![
        // All INDI devices
        // Source: INDI protocol documentation
        (
            QuirkMatcher::VendorWide,
            vec![
                // INDI uses XML-based protocol
                Quirk::Timing(TimingQuirk::DelayBetweenCommands(10)),
                Quirk::Timing(TimingQuirk::ExposurePollingIntervalMs(500)),
            ],
        ),
    ]
}

// ============================================================================
// QUIRK MATCHER
// ============================================================================

/// How to match quirks to devices
#[derive(Debug, Clone, PartialEq)]
pub enum QuirkMatcher {
    /// Applies to all devices from this vendor
    VendorWide,
    /// Applies to devices whose model name contains this string (case-insensitive)
    ModelContains(&'static str),
    /// Applies to devices with this exact model name
    ModelExact(&'static str),
    /// Applies to devices whose ID contains this string
    IdContains(&'static str),
}

impl QuirkMatcher {
    /// Check if this matcher matches the given device info
    pub fn matches(&self, device_id: &str, model_name: &str) -> bool {
        match self {
            QuirkMatcher::VendorWide => true,
            QuirkMatcher::ModelContains(s) => model_name.to_lowercase().contains(&s.to_lowercase()),
            QuirkMatcher::ModelExact(s) => model_name == *s,
            QuirkMatcher::IdContains(s) => device_id.to_lowercase().contains(&s.to_lowercase()),
        }
    }
}

// ============================================================================
// PUBLIC API
// ============================================================================

/// Get all quirks for a device based on its ID.
///
/// The device ID format is expected to be: `protocol:vendor:model_or_id`
/// Examples:
/// - `native:zwo:ASI294MC Pro`
/// - `ascom:Simulator:Camera #1`
/// - `alpaca:10.0.0.5:camera:0`
///
/// # Arguments
/// * `device_id` - The full device identifier
///
/// # Returns
/// A vector of all quirks that should be applied to this device
pub fn get_device_quirks(device_id: &str) -> Vec<Quirk> {
    let mut quirks = Vec::new();

    // Parse the device ID to extract vendor and model
    let parts: Vec<&str> = device_id.split(':').collect();
    if parts.len() < 2 {
        tracing::debug!("Invalid device ID format: {}", device_id);
        return quirks;
    }

    let protocol = parts[0];
    let vendor_or_model = if parts.len() > 1 { parts[1] } else { "" };
    let model = if parts.len() > 2 {
        parts[2..].join(":")
    } else {
        String::new()
    };

    // Get vendor quirks based on protocol and vendor name
    let vendor_quirk_list = match protocol {
        "native" => match vendor_or_model.to_lowercase().as_str() {
            "zwo" => zwo_quirks(),
            "qhy" => qhy_quirks(),
            "playerone" | "player_one" => player_one_quirks(),
            "svbony" => svbony_quirks(),
            "atik" => atik_quirks(),
            "touptek" | "ogma" => touptek_quirks(),
            "moravian" => moravian_quirks(),
            "fli" => fli_quirks(),
            "skywatcher" | "sky-watcher" | "synta" => skywatcher_quirks(),
            "ioptron" => ioptron_quirks(),
            "lx200" | "meade" => lx200_quirks(),
            _ => Vec::new(),
        },
        "ascom" => ascom_quirks(),
        "alpaca" => alpaca_quirks(),
        "indi" => indi_quirks(),
        _ => Vec::new(),
    };

    // Apply matching quirks
    for (matcher, vendor_quirks) in vendor_quirk_list {
        if matcher.matches(device_id, &model) {
            quirks.extend(vendor_quirks);
        }
    }

    if !quirks.is_empty() {
        tracing::debug!(
            "Found {} quirks for device {}: {:?}",
            quirks.len(),
            device_id,
            quirks.iter().map(|q| q.category()).collect::<Vec<_>>()
        );
    }

    quirks
}

/// Get all quirks that apply vendor-wide.
///
/// # Arguments
/// * `vendor` - The vendor enum
///
/// # Returns
/// A vector of vendor-wide quirks
pub fn get_vendor_quirks(vendor: &NativeVendor) -> Vec<Quirk> {
    let vendor_quirk_list = match vendor {
        NativeVendor::Zwo => zwo_quirks(),
        NativeVendor::Qhy => qhy_quirks(),
        NativeVendor::PlayerOne => player_one_quirks(),
        NativeVendor::Svbony => svbony_quirks(),
        NativeVendor::Atik => atik_quirks(),
        NativeVendor::Touptek => touptek_quirks(),
        NativeVendor::Moravian => moravian_quirks(),
        NativeVendor::Fli => fli_quirks(),
        NativeVendor::Ascom => ascom_quirks(),
        NativeVendor::SkyWatcher => skywatcher_quirks(),
        NativeVendor::IOptron => ioptron_quirks(),
        NativeVendor::Meade => lx200_quirks(), // Meade uses LX200 protocol
        // Vendors without specific quirks
        NativeVendor::Fujifilm
        | NativeVendor::GPhoto2
        | NativeVendor::StarlightXpress
        | NativeVendor::Celestron
        | NativeVendor::Pegasus
        | NativeVendor::Other(_) => Vec::new(),
    };

    // Return only the vendor-wide quirks
    vendor_quirk_list
        .into_iter()
        .filter(|(matcher, _)| matches!(matcher, QuirkMatcher::VendorWide))
        .flat_map(|(_, quirks)| quirks)
        .collect()
}

/// List all known quirks for documentation purposes.
///
/// Returns a list of (vendor, model_pattern, quirk_descriptions)
pub fn list_all_quirks() -> Vec<(String, String, Vec<String>)> {
    let mut results = Vec::new();

    let vendors = [
        ("ZWO", zwo_quirks()),
        ("QHY", qhy_quirks()),
        ("Player One", player_one_quirks()),
        ("SVBony", svbony_quirks()),
        ("Atik", atik_quirks()),
        ("Touptek", touptek_quirks()),
        ("Moravian", moravian_quirks()),
        ("FLI", fli_quirks()),
        ("Sky-Watcher", skywatcher_quirks()),
        ("iOptron", ioptron_quirks()),
        ("LX200", lx200_quirks()),
        ("ASCOM", ascom_quirks()),
        ("Alpaca", alpaca_quirks()),
        ("INDI", indi_quirks()),
    ];

    for (vendor_name, quirk_list) in vendors {
        for (matcher, quirks) in quirk_list {
            let pattern = match matcher {
                QuirkMatcher::VendorWide => "All devices".to_string(),
                QuirkMatcher::ModelContains(s) => format!("Models containing '{}'", s),
                QuirkMatcher::ModelExact(s) => format!("Model '{}'", s),
                QuirkMatcher::IdContains(s) => format!("IDs containing '{}'", s),
            };

            let descriptions: Vec<String> = quirks.iter().map(|q| q.description()).collect();

            results.push((vendor_name.to_string(), pattern, descriptions));
        }
    }

    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_zwo_camera_quirks() {
        let quirks = get_device_quirks("native:zwo:ASI294MC Pro");
        assert!(!quirks.is_empty());

        // Should have temperature scale factor
        let has_temp_scale = quirks
            .iter()
            .any(|q| matches!(q, Quirk::Temperature(TemperatureQuirk::ScaleFactor(_))));
        assert!(has_temp_scale);

        // ASI294 should also have SkipFirstRead
        let has_skip_first = quirks
            .iter()
            .any(|q| matches!(q, Quirk::Temperature(TemperatureQuirk::SkipFirstRead)));
        assert!(has_skip_first);
    }

    #[test]
    fn test_get_qhy_vendor_quirks() {
        let quirks = get_vendor_quirks(&NativeVendor::Qhy);
        assert!(!quirks.is_empty());

        // Should have discovery quirks
        let has_discovery = quirks.iter().any(|q| matches!(q, Quirk::Discovery(_)));
        assert!(has_discovery);
    }

    #[test]
    fn test_matcher_case_insensitive() {
        let quirks1 = get_device_quirks("native:zwo:ASI294MC");
        let quirks2 = get_device_quirks("native:ZWO:asi294mc");

        // Both should have the same number of quirks
        assert_eq!(quirks1.len(), quirks2.len());
    }

    #[test]
    fn test_ascom_quirks() {
        let quirks = get_device_quirks("ascom:ASCOM.Simulator.Camera:Camera #1");
        assert!(!quirks.is_empty());
    }

    #[test]
    fn test_list_all_quirks() {
        let all = list_all_quirks();
        assert!(!all.is_empty());

        // Should have quirks for multiple vendors
        let vendors: std::collections::HashSet<_> =
            all.iter().map(|(v, _, _)| v.as_str()).collect();
        assert!(vendors.len() > 5);
    }
}
