use nightshade_ascom::{AscomDeviceType, discover_devices, AscomCamera};

fn main() {
    // Initialize COM
    nightshade_ascom::init_com().expect("Failed to init COM");

    println!("Discovering cameras...");
    let devices = discover_devices(AscomDeviceType::Camera);
    
    for device in &devices {
        println!("Found: {} ({})", device.name, device.prog_id);
    }

    for device in &devices {
        println!("Attempting to connect to {} ({})", device.name, device.prog_id);
        match AscomCamera::new(&device.prog_id) {
            Ok(mut camera) => {
                println!("Created camera object for {}", device.name);
                match camera.connect() {
                    Ok(_) => {
                        println!("Connected successfully to {}!", device.name);
                        let _ = camera.disconnect();
                    },
                    Err(e) => println!("Failed to connect to {}: {}", device.name, e),
                }
            },
            Err(e) => println!("Failed to create camera object for {}: {}", device.name, e),
        }
        println!("---");
    }

    nightshade_ascom::uninit_com();
}
