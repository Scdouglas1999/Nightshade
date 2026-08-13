//! LX200 Mount Protocol Implementation
//!
//! Implements the Meade LX200 serial command protocol, which is the de-facto
//! standard for many telescope mounts including:
//! - Meade LX200, LX600, LX850
//! - OnStep-based mounts (Pegasus NYX-101, DIY builds)
//! - Losmandy Gemini (LX200 mode)
//! - 10Micron mounts
//! - Many other compatible mounts

use crate::traits::*;
use crate::NativeVendor;
use async_trait::async_trait;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::Notify;

mod discovery;
mod mount;
mod mount_ops;
mod protocol;

pub use discovery::*;
pub use mount::*;
pub use protocol::*;
#[cfg(test)]
mod onstep_status_tests {
    use super::*;

    #[test]
    fn parse_typical_tracking_parked_idle() {
        // N + P + home + GEM + pier east + rate digits + error 0 (no leading n)
        let (tracking, slewing, parked, homed, pier) = parse_onstep_status_fields("NPHET050");
        assert!(tracking, "N without leading n means tracking");
        assert!(!slewing, "N means no goto (not slewing)");
        assert!(parked);
        assert!(homed);
        assert_eq!(pier, PierSide::East);
    }

    #[test]
    fn parse_not_tracking_idle_unparked() {
        // n + N + p per OnStep wiki example (not tracking, not slewing, not parked)
        let (tracking, slewing, parked, homed, pier) = parse_onstep_status_fields("nNpPH");
        assert!(!tracking);
        assert!(!slewing);
        assert!(!parked);
        assert!(homed);
        assert_eq!(pier, PierSide::Unknown);
    }

    #[test]
    fn parse_slewing_without_no_goto_flag() {
        // No 'N' at prefix position 0/1 => slewing per MountStatus.h
        let (tracking, slewing, _, _, _) = parse_onstep_status_fields("pHET050");
        assert!(tracking);
        assert!(slewing);
    }

    #[test]
    fn leading_n_is_not_slewing_n_flag() {
        // Old bug: contains('N') is false for "n..." but inverted logic treated N as slewing.
        // Positional: 'n' at 0 is not-tracking; next char is park 'p', not slewing.
        let (tracking, slewing, parked, _, _) = parse_onstep_status_fields("np");
        assert!(!tracking);
        assert!(slewing, "no N in prefix means goto/slew active");
        assert!(!parked);
    }

    #[test]
    fn gem_mount_type_e_is_not_pier_east() {
        let (_, _, _, _, pier) = parse_onstep_status_fields("NPE");
        assert_eq!(
            pier,
            PierSide::Unknown,
            "E is mount type GEM, not pier side"
        );
    }

    #[test]
    fn pier_t_is_not_tracking_flag() {
        let (tracking, _, _, _, pier) = parse_onstep_status_fields("NpPHET000");
        assert!(tracking);
        assert_eq!(pier, PierSide::East, "T is pier east, not tracking");
    }

    #[test]
    fn strips_hash_terminator() {
        let (tracking, slewing, parked, homed, pier) = parse_onstep_status_fields("nNpKW000#");
        assert!(!tracking);
        assert!(!slewing);
        assert!(!parked);
        assert!(!homed);
        assert_eq!(pier, PierSide::West);
    }

    #[test]
    fn parking_in_progress_is_not_parked() {
        let (_, _, parked, _, _) = parse_onstep_status_fields("nNI");
        assert!(!parked);
    }

    #[test]
    fn slewing_goto_without_n_or_n_is_still_tracking() {
        let (tracking, slewing, parked, _, pier) = parse_onstep_status_fields("pET000#");
        assert!(tracking);
        assert!(slewing);
        assert!(!parked);
        assert_eq!(pier, PierSide::East);
    }

    #[test]
    fn optional_waiting_flag_w_is_not_pier_west() {
        let (_, _, _, _, pier) = parse_onstep_status_fields("NpHwEo000#");
        assert_eq!(
            pier,
            PierSide::Unknown,
            "lowercase waiting-home flag is not pier west"
        );
    }

    #[test]
    fn format_lx200_firmware_version_combines_number_date_and_time() {
        assert_eq!(
            format_firmware_version(Some("4.2g"), Some("Oct 10 2010"), Some("12:34:56")).as_deref(),
            Some("LX200 firmware v4.2g (Oct 10 2010 12:34:56)")
        );
    }

    #[test]
    fn format_lx200_firmware_version_accepts_partial_metadata() {
        assert_eq!(
            format_firmware_version(Some("4.2g"), None, None).as_deref(),
            Some("LX200 firmware v4.2g")
        );
        assert_eq!(
            format_firmware_version(None, Some("Oct 10 2010"), None).as_deref(),
            Some("LX200 firmware Oct 10 2010")
        );
    }

    #[test]
    fn format_lx200_firmware_version_rejects_empty_metadata() {
        assert_eq!(format_firmware_version(Some(""), Some(""), Some("")), None);
    }
}
