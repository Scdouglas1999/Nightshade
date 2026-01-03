
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
            
            // Calculate final RA accounting for declination compression
            // RA offset needs to be divided by cos(dec) to account for projection
            let dec_rad = config.center_dec.to_radians();
            let ra_correction = if dec_rad.cos().abs() > 0.001 {
                1.0 / dec_rad.cos()
            } else {
                1.0
            };
            
            let panel_dec = config.center_dec + rotated_dec_offset;
            let panel_ra = config.center_ra + (rotated_ra_offset * ra_correction / 15.0); // Convert deg to hours
            
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
pub fn estimate_mosaic_time(config: &MosaicConfig, exposure_secs: f64, exposures_per_panel: u32) -> f64 {
    let total_panels = config.panels_horizontal * config.panels_vertical;
    let time_per_panel = exposure_secs * exposures_per_panel as f64;
    let overhead_per_panel = 60.0; // Slew + center + settle time estimate
    
    total_panels as f64 * (time_per_panel + overhead_per_panel)
}
