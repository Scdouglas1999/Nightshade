//! Mosaic Panel Calculation Helper
//!
//! Calculates the grid of panel positions for mosaic imaging

use crate::MosaicConfig;

/// Represents a single panel in a mosaic
#[derive(Debug, Clone)]
pub struct MosaicPanel {
    pub ra_hours: f64,
    pub dec_degrees: f64,
    pub panel_index: u32,
    pub row: u32,
    pub col: u32,
}

/// Calculate all panel positions for a mosaic configuration
pub fn calculate_mosaic_panels(config: &MosaicConfig) -> Vec<MosaicPanel> {
    let mut panels = Vec::new();

    // Calculate effective panel size with overlap
    let overlap_factor = 1.0 - (config.overlap_percent / 100.0);
    let effective_width = config.panel_width_arcmin * overlap_factor;
    let effective_height = config.panel_height_arcmin * overlap_factor;

    // Convert to degrees
    let width_deg = effective_width / 60.0;
    let height_deg = effective_height / 60.0;

    // Calculate panel grid
    let total_rows = config.panels_vertical;
    let total_cols = config.panels_horizontal;

    // Center the grid - calculate offsets from center
    let center_row_offset = (total_rows as f64 - 1.0) / 2.0;
    let center_col_offset = (total_cols as f64 - 1.0) / 2.0;

    let mut panel_index = 0;

    for row in 0..total_rows {
        for col in 0..total_cols {
            // Calculate offset from center in degrees
            let dec_offset = (row as f64 - center_row_offset) * height_deg;
            let ra_offset_deg = (col as f64 - center_col_offset) * width_deg;

            // Apply rotation if specified
            let (rotated_ra_offset, rotated_dec_offset) = if config.rotation != 0.0 {
                let angle_rad = config.rotation.to_radians();
                let cos_angle = angle_rad.cos();
                let sin_angle = angle_rad.sin();

                (
                    ra_offset_deg * cos_angle - dec_offset * sin_angle,
                    ra_offset_deg * sin_angle + dec_offset * cos_angle,
                )
            } else {
                (ra_offset_deg, dec_offset)
            };

            let panel_dec = config.center_dec + rotated_dec_offset;

            // Calculate final RA accounting for declination compression
            // RA offset needs to be divided by the panel declination cosine,
            // not the mosaic center declination, to keep spacing consistent.
            let dec_rad = panel_dec.to_radians();
            let ra_correction = if dec_rad.cos().abs() > 0.001 {
                1.0 / dec_rad.cos()
            } else {
                1.0
            };

            let panel_ra =
                (config.center_ra + (rotated_ra_offset * ra_correction / 15.0)).rem_euclid(24.0);

            panels.push(MosaicPanel {
                ra_hours: panel_ra,
                dec_degrees: panel_dec,
                panel_index,
                row,
                col,
            });

            panel_index += 1;
        }
    }

    panels
}

/// Calculate total mosaic coverage area in square arcminutes
pub fn calculate_mosaic_area(config: &MosaicConfig) -> f64 {
    let total_width_arcmin = config.panel_width_arcmin * config.panels_horizontal as f64;
    let total_height_arcmin = config.panel_height_arcmin * config.panels_vertical as f64;
    total_width_arcmin * total_height_arcmin
}

/// Estimate total imaging time for mosaic in seconds
pub fn estimate_mosaic_time(
    config: &MosaicConfig,
    exposure_secs: f64,
    exposures_per_panel: u32,
) -> f64 {
    let total_panels = config.panels_horizontal * config.panels_vertical;
    let time_per_panel = exposure_secs * exposures_per_panel as f64;
    let overhead_per_panel = config.panel_overhead_secs;

    total_panels as f64 * (time_per_panel + overhead_per_panel)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panel_spacing_uses_panel_declination_for_ra_correction() {
        let config = MosaicConfig {
            center_ra: 12.0,
            center_dec: 70.0,
            panel_width_arcmin: 120.0,
            panel_height_arcmin: 120.0,
            overlap_percent: 0.0,
            rotation: 45.0,
            panels_horizontal: 2,
            panels_vertical: 2,
            panel_overhead_secs: 30.0,
        };

        let panels = calculate_mosaic_panels(&config);
        assert_eq!(panels.len(), 4);
        assert_ne!(panels[0].ra_hours, panels[1].ra_hours);
        assert_ne!(panels[0].dec_degrees, panels[1].dec_degrees);
    }

    #[test]
    fn mosaic_time_uses_configured_panel_overhead() {
        let config = MosaicConfig {
            panels_horizontal: 2,
            panels_vertical: 3,
            panel_overhead_secs: 12.5,
            ..MosaicConfig::default()
        };

        let estimate = estimate_mosaic_time(&config, 30.0, 4);
        assert_eq!(estimate, 6.0 * (120.0 + 12.5));
    }
}
