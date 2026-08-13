use super::*;

// =============================================================================
// INDI device-id parsing parity
// =============================================================================
//
// Every INDI branch under `device_manager/ops/` used to hand-roll
// `device_id.split(':')`, and the copies had drifted: some accepted
// `parts.len() >= 4` and fell through, some rejected `< 4`, some parsed the
// port and some carried it as a raw string into the `indi_clients` key. They
// now all go through `DeviceManager::parse_indi_device_id`. These pin the
// inputs where the copies disagreed.

/// A device name containing colons is not truncated: `splitn(3, ':')` keeps
/// everything after the port, exactly as `parts[3..].join(":")` did.
#[test]
fn indi_id_keeps_a_device_name_that_contains_colons() {
    let (host, port, device_name) =
        DeviceManager::parse_indi_device_id("indi:localhost:7624:ZWO CCD: ASI2600MM")
            .expect("a colon in the device name is legal");
    assert_eq!(host, "localhost");
    assert_eq!(port, 7624);
    assert_eq!(device_name, "ZWO CCD: ASI2600MM");
}

/// The `indi_clients` map is keyed on the port the CONNECT path parsed
/// (`connect_indi` does `parts[2].parse::<u16>()`), so a reader that carried
/// the raw text through would look up "localhost:07624" and miss a client
/// registered as "localhost:7624". Going through the parser makes both sides
/// produce the same key.
#[test]
fn indi_server_key_is_the_parsed_port_not_the_raw_text() {
    let (host, port, _) = DeviceManager::parse_indi_device_id("indi:localhost:07624:Camera")
        .expect("a zero-padded port is still a port");
    assert_eq!(format!("{host}:{port}"), "localhost:7624");
}

/// Malformed ids the `parts.len() >= 4` copies used to wave through: a
/// non-numeric port, an empty host and an empty device name all name nothing
/// that could be connected.
#[test]
fn indi_id_rejects_what_the_hand_rolled_copies_waved_through() {
    for id in [
        "indi:localhost:not-a-port:Camera",
        "indi::7624:Camera",
        "indi:localhost:7624:",
        "indi:localhost:7624",
        "indi:",
        "alpaca:localhost:11111:0",
    ] {
        assert!(
            DeviceManager::parse_indi_device_id(id).is_err(),
            "{id} must not parse as an INDI device id"
        );
    }
}
