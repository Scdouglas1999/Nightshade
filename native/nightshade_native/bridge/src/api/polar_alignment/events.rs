use super::*;

/// Emit a polar alignment status update (JSON-serializable for Dart)
pub(crate) fn emit_polar_status(status: &str, phase: &str, point: i32) {
    tracing::info!(
        "Polar alignment: {} (phase={}, point={})",
        status,
        phase,
        point
    );
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentStatus(PolarAlignmentStatus {
            status: status.to_string(),
            phase: phase.to_string(),
            point,
        }),
    ));
}

/// Emit polar alignment error update
pub(crate) fn emit_polar_error(
    az: f64,
    alt: f64,
    total: f64,
    cur_ra: f64,
    cur_dec: f64,
    tgt_ra: f64,
    tgt_dec: f64,
) {
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignment(PolarAlignmentEvent {
            azimuth_error: az,
            altitude_error: alt,
            total_error: total,
            current_ra: cur_ra,
            current_dec: cur_dec,
            target_ra: tgt_ra,
            target_dec: tgt_dec,
        }),
    ));
}

/// Unit boundary for plate-solve output consumed by polar geometry. The
/// bridge result already reports RA in degrees; keep that explicit so this
/// path cannot silently reintroduce the historical hours-to-degrees multiply.
pub(crate) fn plate_solve_ra_degrees(ra_degrees: f64) -> f64 {
    ra_degrees
}

/// Emit polar alignment image for UI display
/// Encodes the display data to JPEG for efficient transmission
pub(crate) fn emit_polar_image(
    image: &CapturedImageResult,
    point: i32,
    phase: &str,
    solved_ra: Option<f64>,
    solved_dec: Option<f64>,
) {
    use image::ImageEncoder;

    // Encode display_data (RGBA) to JPEG
    let mut buffer = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut buffer);
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
        if let Err(e) = encoder.write_image(
            &image.display_data,
            image.width as u32,
            image.height as u32,
            image::ColorType::Rgba8,
        ) {
            tracing::warn!("Failed to encode polar alignment image: {}", e);
            return;
        }
    }
    let color_type = image::ColorType::Rgba8;
    let jpeg_data = buffer;

    tracing::debug!(
        "Emitting polar alignment image: {}x{}, {:?}, point={}, phase={}, solved={:?}",
        image.width,
        image.height,
        color_type,
        point,
        phase,
        solved_ra.is_some()
    );

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
            image_data: jpeg_data,
            width: image.width as u32,
            height: image.height as u32,
            solved_ra,
            solved_dec,
            point,
            phase: phase.to_string(),
        }),
    ));
}
