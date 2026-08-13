use super::*;

impl DeviceManager {
    /// Download image from camera
    pub async fn camera_download_image(&self, device_id: &str) -> Result<ImageData, DeviceOpError> {
        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.download_image().await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to download image from ASCOM camera {}: {}",
                                    device_id, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    // Use the new download_image_data method
                    let (width, height, pixels) =
                        camera.download_image_data().await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to download image from Alpaca camera {}: {}",
                                    device_id, e
                                ),
                            )
                        })?;

                    // Get camera metadata
                    // Same as the INDI path below: record a failed read as UNKNOWN
                    // rather than 0, so it cannot outrank the configured gain and
                    // mislabel the frame's FITS header.
                    let gain = match camera.gain().await {
                        Ok(g) => g,
                        Err(e) => {
                            warn!(
                                "Failed to read camera gain for {}: {}. Recording it as \
                                 unknown so the configured gain is used instead.",
                                device_id, e
                            );
                            UNKNOWN_CAMERA_SETTING
                        }
                    };
                    let offset = match camera.offset().await {
                        Ok(o) => o,
                        Err(e) => {
                            warn!(
                                "Failed to read camera offset for {}: {}. Recording it as \
                                 unknown so the configured offset is used instead.",
                                device_id, e
                            );
                            UNKNOWN_CAMERA_SETTING
                        }
                    };
                    let bin_x = match camera.bin_x().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!(
                                "Failed to read camera bin_x for {}: {}. Using default 1.",
                                device_id, e
                            );
                            1
                        }
                    };
                    let bin_y = match camera.bin_y().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!(
                                "Failed to read camera bin_y for {}: {}. Using default 1.",
                                device_id, e
                            );
                            1
                        }
                    };
                    let temp = camera.ccd_temperature().await.ok();
                    let exposure_time = match camera.last_exposure_duration().await {
                        Ok(d) => d,
                        Err(e) => {
                            warn!("Failed to read last exposure duration for {}: {}. Using default 0.0.", device_id, e);
                            0.0
                        }
                    };

                    // Determine if color camera (sensor_type: 0=Monochrome, 1=Color, etc.)
                    let sensor_type = match camera.sensor_type().await {
                        Ok(t) => t,
                        Err(e) => {
                            warn!(
                                "Failed to read sensor type for {}: {}. Marking sensor type unknown.",
                                device_id, e
                            );
                            -1
                        }
                    };
                    let bayer_pattern = if sensor_type == 1 {
                        // Both offsets must be READ, not assumed. Defaulting a failed
                        // read to 0 mapped to RGGB — indistinguishable from a genuine
                        // RGGB sensor — so a BGGR/GRBG one-shot-colour camera whose
                        // bayeroffsetx/y read failed got red and blue TRANSPOSED in
                        // every debayered frame and the wrong BAYERPAT written into
                        // the FITS header, which cannot be undone after the fact.
                        // `None` here means "pattern unknown", which leaves the frame
                        // undebayered rather than debayered wrongly.
                        let offsets =
                            match (camera.bayer_offset_x().await, camera.bayer_offset_y().await) {
                                (Ok(x), Ok(y)) => Some((x, y)),
                                (x, y) => {
                                    warn!(
                                        "Failed to read bayer offsets for {} (x: {:?}, y: {:?}). \
                                     Leaving the Bayer pattern UNKNOWN so the frame is not \
                                     debayered with a guessed pattern.",
                                        device_id,
                                        x.err(),
                                        y.err()
                                    );
                                    None
                                }
                            };
                        // Map offsets to bayer pattern. An offset pair outside the
                        // 2x2 grid is also "unknown" rather than silently RGGB.
                        offsets.and_then(|(offset_x, offset_y)| match (offset_x, offset_y) {
                            (0, 0) => Some(nightshade_native::camera::BayerPattern::Rggb),
                            (1, 0) => Some(nightshade_native::camera::BayerPattern::Grbg),
                            (0, 1) => Some(nightshade_native::camera::BayerPattern::Gbrg),
                            (1, 1) => Some(nightshade_native::camera::BayerPattern::Bggr),
                            _ => {
                                warn!(
                                    "Camera {} reported out-of-range bayer offsets \
                                         ({}, {}); Bayer pattern left unknown.",
                                    device_id, offset_x, offset_y
                                );
                                None
                            }
                        })
                    } else {
                        None
                    };

                    return Ok(ImageData {
                        width,
                        height,
                        data: pixels,
                        bits_per_pixel: 16,
                        bayer_pattern,
                        metadata: nightshade_native::camera::ImageMetadata {
                            exposure_time,
                            gain,
                            offset,
                            bin_x,
                            bin_y,
                            temperature: temp,
                            timestamp: chrono::Utc::now(),
                            subframe: None,
                            readout_mode: None,
                            vendor_data: nightshade_native::camera::VendorFeatures::default(),
                        },
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // For INDI, image download uses event-based BLOB handling
                if let Ok((host, port, device_name)) = Self::parse_indi_device_id(device_id) {
                    let server_key = format!("{host}:{port}");

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        // Create an IndiCamera wrapper to handle BLOB download
                        let camera =
                            nightshade_indi::IndiCamera::new(Arc::clone(client), &device_name);

                        // Subscribe to BLOB events BEFORE enable_blob + the
                        // metadata round-trips below: the exposure may already
                        // be completing, and a BLOB emitted during those reads
                        // would otherwise be missed by a later subscription.
                        let mut rx = {
                            let locked_client = client.read().await;
                            locked_client.subscribe()
                        };

                        // Enable BLOB transfer if not already enabled
                        let _ = camera.enable_blob().await;

                        // Get image metadata
                        let width = match camera.get_sensor_width().await {
                            Some(w) => w as u32,
                            None => {
                                warn!(
                                    "Failed to read INDI sensor width for {}. Using default 1920.",
                                    device_id
                                );
                                1920
                            }
                        };
                        let height = match camera.get_sensor_height().await {
                            Some(h) => h as u32,
                            None => {
                                warn!(
                                    "Failed to read INDI sensor height for {}. Using default 1080.",
                                    device_id
                                );
                                1080
                            }
                        };
                        let (bin_x, bin_y) = match camera
                            .get_binning_or_default(std::time::Duration::from_millis(0))
                            .await
                        {
                            Ok(b) => b,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI binning for {}: {}. Using default (1, 1).",
                                    device_id, e
                                );
                                (1, 1)
                            }
                        };
                        let temp = camera.get_temperature().await.ok();
                        // A FAILED read must not masquerade as "gain 0": that 0 was
                        // wrapped in Some() downstream, which short-circuited
                        // `image_data.gain.or(config.gain)` and let it BEAT the
                        // operator's configured gain — stamping GAIN=0 into every
                        // frame's FITS header for the run and permanently breaking
                        // dark/flat library matching, which keys on gain.
                        // UNKNOWN_CAMERA_SETTING is mapped back to None at the
                        // ImageMetadata boundary so the configured value wins.
                        let gain = match camera.get_gain().await {
                            Ok(g) => g,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI gain for {}: {}. Recording it as \
                                     unknown so the configured gain is used instead.",
                                    device_id, e
                                );
                                UNKNOWN_CAMERA_SETTING
                            }
                        };
                        let offset = match camera.get_offset().await {
                            Ok(o) => o,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI offset for {}: {}. Recording it as \
                                     unknown so the configured offset is used instead.",
                                    device_id, e
                                );
                                UNKNOWN_CAMERA_SETTING
                            }
                        };

                        // Build an ImageData from a raw INDI image BLOB (FITS or
                        // raw u16). Shared by the event path and the cached-BLOB
                        // fallback below so both decode identically.
                        let build_image = |data: Vec<u8>| -> ImageData {
                            // The FITS header carries the frame's TRUE geometry in
                            // the mandatory NAXIS1/NAXIS2 keywords; prefer them
                            // over the CCD_INFO-derived guess. CCD_MAX_X/Y is the
                            // full UNBINNED sensor, so at bin 2 the two disagree —
                            // verified against a live INDI CCD simulator: CCD_INFO
                            // said 1280x1024 while the BLOB said NAXIS1=640,
                            // NAXIS2=512. Using CCD_INFO there built an ImageData
                            // claiming 1280x1024 around a 640x512 frame, which
                            // failed validation outright (binned INDI capture was
                            // broken); and when CCD_INFO is unreadable the 1920x1080
                            // fallback below silently CROPPED and re-strided the
                            // frame instead, because the truncate() made the
                            // downstream size check pass tautologically.
                            let mut fits_dims: Option<(u32, u32)> = None;
                            let image_data = if data.starts_with(b"SIMPLE") {
                                let mut off = 0;
                                let mut naxis1: Option<u32> = None;
                                let mut naxis2: Option<u32> = None;
                                for chunk in data.chunks(80) {
                                    off += 80;
                                    if chunk.starts_with(b"NAXIS1") {
                                        naxis1 = parse_fits_card_u32(chunk);
                                    } else if chunk.starts_with(b"NAXIS2") {
                                        naxis2 = parse_fits_card_u32(chunk);
                                    }
                                    if chunk.starts_with(b"END") {
                                        off = ((off + 2879) / 2880) * 2880;
                                        break;
                                    }
                                }
                                if let (Some(w), Some(h)) = (naxis1, naxis2) {
                                    if w > 0 && h > 0 {
                                        fits_dims = Some((w, h));
                                    }
                                }
                                let binary_data = &data[off.min(data.len())..];
                                let mut pixels: Vec<u16> =
                                    Vec::with_capacity(binary_data.len() / 2);
                                for chunk in binary_data.chunks_exact(2) {
                                    pixels.push(u16::from_be_bytes([chunk[0], chunk[1]]));
                                }
                                pixels
                            } else {
                                let mut pixels: Vec<u16> = Vec::with_capacity(data.len() / 2);
                                for chunk in data.chunks_exact(2) {
                                    pixels.push(u16::from_le_bytes([chunk[0], chunk[1]]));
                                }
                                pixels
                            };
                            let (eff_width, eff_height) = match fits_dims {
                                Some((w, h)) => {
                                    if (w, h) != (width, height) {
                                        tracing::info!(
                                            "INDI {}: using FITS NAXIS {}x{} instead of \
                                             CCD_INFO-derived {}x{} (binning/subframe)",
                                            device_id,
                                            w,
                                            h,
                                            width,
                                            height
                                        );
                                    }
                                    (w, h)
                                }
                                None => (width, height),
                            };
                            // Trim FITS block padding beyond width*height. Only ever
                            // discards the tail padding now that the dimensions are
                            // the frame's own; a SHORT buffer is left short so
                            // validation can still catch it rather than being
                            // silently reshaped.
                            let expected_pixels = (eff_width as usize) * (eff_height as usize);
                            let mut image_data = image_data;
                            if image_data.len() > expected_pixels {
                                image_data.truncate(expected_pixels);
                            }
                            ImageData {
                                width: eff_width,
                                height: eff_height,
                                data: image_data,
                                bits_per_pixel: 16,
                                bayer_pattern: None,
                                metadata: nightshade_native::camera::ImageMetadata {
                                    exposure_time: 0.0,
                                    gain,
                                    offset,
                                    bin_x,
                                    bin_y,
                                    temperature: temp,
                                    timestamp: chrono::Utc::now(),
                                    subframe: None,
                                    readout_mode: None,
                                    vendor_data: nightshade_native::camera::VendorFeatures::default(
                                    ),
                                },
                            }
                        };

                        // Wait for BLOB data with timeout (30 seconds)
                        let timeout = std::time::Duration::from_secs(30);
                        let start_time = std::time::Instant::now();

                        loop {
                            if start_time.elapsed() > timeout {
                                return Err(DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Timeout waiting for INDI image BLOB",
                                ));
                            }

                            match tokio::time::timeout(std::time::Duration::from_secs(1), rx.recv())
                                .await
                            {
                                Ok(Ok(event)) => match event {
                                    nightshade_indi::IndiEvent::BlobReceived {
                                        device,
                                        element,
                                        data,
                                        ..
                                    } if device == device_name
                                        && (element == "CCD1" || element == "CCD2") =>
                                    {
                                        return Ok(build_image(data));
                                    }
                                    _ => {}
                                },
                                Ok(Err(_)) => {
                                    return Err(DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        "INDI event channel closed",
                                    ));
                                }
                                Err(_) => {
                                    // recv timed out; the reader may have stored
                                    // the BLOB before we subscribed. Poll the
                                    // cache before looping so a race can't hang.
                                    let cached = {
                                        let lc = client.read().await;
                                        match lc.take_blob(&device_name, "CCD1", "CCD1").await {
                                            Some(d) => Some(d),
                                            None => {
                                                lc.take_blob(&device_name, "CCD2", "CCD2").await
                                            }
                                        }
                                    };
                                    if let Some(data) = cached {
                                        return Ok(build_image(data));
                                    }
                                    continue;
                                }
                            }
                        }
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                // Project gain/offset/bin/temperature from the singleton so a
                // simulated download reflects whatever the test or UI
                // configured via set_gain / set_offset / set_binning /
                // set_cooler, and take the frame geometry from the SAME sensor
                // declaration the camera advertised.
                let sim = crate::device_manager::ops::sim_gate::read_camera_status().await?;
                let request =
                    crate::device_manager::ops::sim_gate::read_camera_last_exposure().await?;
                // Claim the finished frame, which both refuses a download the
                // camera cannot honestly satisfy and returns it to idle so a
                // caller that polls completion afterwards is not told to keep
                // waiting. Ungated, this synthesized a full frame stamped with
                // the requested EXPTIME mid-exposure and after an abort, so a
                // cancelled or raced capture still produced a saved light frame.
                crate::api::devices::simulation::take_sim_exposure_for_download()
                    .await
                    .map_err(|detail| {
                        DeviceOpError::hardware(Some(device_id.to_string()), detail)
                    })?;
                // Synthetic download: an electron-domain frame whose star PSF
                // tracks focuser defocus, painting the sky the mount is actually
                // on. Rendered by `crate::sim_capture`, which is also what the
                // Imaging screen's manual capture calls — the two paths used to
                // disagree, and the manual one scattered stars at random so
                // nothing captured through it could be plate-solved.
                let frame =
                    crate::sim_capture::render_sim_frame(crate::sim_capture::SimCaptureRequest {
                        exposure_secs: request.secs,
                        sensor_width: sim.sensor_width.max(1),
                        sensor_height: sim.sensor_height.max(1),
                        pixel_size_um: sim.pixel_size_x,
                        gain: sim.gain,
                        offset: sim.offset,
                        bin_x: sim.bin_x.max(1) as u32,
                        bin_y: sim.bin_y.max(1) as u32,
                        subframe: request.subframe,
                        frame_type: request.frame_type,
                        max_adu: sim.max_adu.clamp(1, u32::from(u16::MAX)) as u16,
                    })
                    .await;
                let (width, height) = (frame.width, frame.height);
                Ok(ImageData {
                    width,
                    height,
                    data: frame.data,
                    bits_per_pixel: 16,
                    bayer_pattern: None,
                    metadata: nightshade_native::camera::ImageMetadata {
                        exposure_time: request.secs,
                        gain: sim.gain,
                        offset: sim.offset,
                        bin_x: sim.bin_x,
                        bin_y: sim.bin_y,
                        temperature: sim.sensor_temp,
                        timestamp: chrono::Utc::now(),
                        subframe: request.subframe.map(|(start_x, start_y, width, height)| {
                            nightshade_native::camera::SubFrame {
                                start_x,
                                start_y,
                                width,
                                height,
                            }
                        }),
                        readout_mode: None,
                        vendor_data: nightshade_native::camera::VendorFeatures::default(),
                    },
                })
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.download_image().await.map_err(DeviceOpError::from);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found", device_id),
            )),
        }
    }

    /// Capture a live-view / preview JPEG frame when the connected driver supports it.
    pub async fn camera_capture_preview(&self, device_id: &str) -> Result<Vec<u8>, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera.capture_preview().await.map_err(DeviceOpError::from);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "camera preview",
                ),
            )),
            _ => Err(DeviceOpError::unsupported(format!(
                "Live view preview is not supported for driver {:?} on camera {}",
                driver_type, device_id
            ))),
        }
    }
}
