
import sys

filepath = "native/nightshade_native/bridge/src/device_capabilities.rs"

with open(filepath, "r") as f:
    c = f.read()

old = """    } else {
        Err(NightshadeError::not_supported(device_id, "Unknown ASCOM device type"))
    }
}

#[cfg(not(windows))]
async fn get_ascom_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {"""

if old not in c:
    print("ERROR: Could not find target text")
    sys.exit(1)

print("Found target text, replacing...")
