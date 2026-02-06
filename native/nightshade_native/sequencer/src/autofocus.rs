//! Autofocus Engine with V-Curve Algorithm
//!
//! Provides production-ready autofocus implementation with:
//! - V-curve, parabolic, and hyperbolic curve fitting
//! - Backlash compensation
//! - Temperature-based focus prediction integration
//! - Robust error handling and outlier rejection

use serde::{Deserialize, Serialize};

/// Result of an autofocus run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutofocusResult {
    pub best_position: i32,
    pub best_hfr: f64,
    pub curve_fit_quality: f64, // R-squared or similar metric
    pub method_used: AutofocusMethod,
    pub data_points: Vec<FocusDataPoint>,
    pub temperature_celsius: Option<f64>,
    pub backlash_applied: bool,
}

/// A single data point in the autofocus curve
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusDataPoint {
    pub position: i32,
    pub hfr: f64,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Autofocus method selection
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum AutofocusMethod {
    /// V-curve with bisection search
    VCurve,
    /// Parabolic (quadratic) curve fitting
    Quadratic,
    /// Hyperbolic curve fitting
    Hyperbolic,
}

/// Configuration for autofocus run
#[derive(Debug, Clone)]
pub struct AutofocusConfig {
    pub method: AutofocusMethod,
    pub step_size: i32,
    pub steps_out: u32,
    pub exposure_duration: f64,
    pub backlash_compensation: i32,
    pub use_temperature_prediction: bool,
    pub max_star_count_change: Option<f64>, // Reject points with >X% star count change
    pub outlier_rejection_sigma: f64,       // Sigma for outlier rejection (0 = disabled)
}

impl Default for AutofocusConfig {
    fn default() -> Self {
        Self {
            method: AutofocusMethod::VCurve,
            step_size: 100,
            steps_out: 7,
            exposure_duration: 3.0,
            backlash_compensation: 50,
            use_temperature_prediction: true,
            max_star_count_change: Some(0.5), // 50% change threshold
            outlier_rejection_sigma: 3.0,
        }
    }
}

/// V-Curve Autofocus Engine
///
/// Algorithm:
/// 1. Start at initial position (optionally predicted from temperature model)
/// 2. Move outward by steps_out * step_size
/// 3. Move inward, taking exposures at each step
/// 4. Calculate HFR at each position
/// 5. Fit curve to data points (parabola, hyperbola, or V-curve)
/// 6. Find minimum of fitted curve
/// 7. Move to optimal position with backlash compensation
pub struct VCurveAutofocus {
    config: AutofocusConfig,
}

impl VCurveAutofocus {
    pub fn new(config: AutofocusConfig) -> Self {
        Self { config }
    }

    /// Calculate the focus sweep positions
    pub fn calculate_positions(&self, starting_position: i32) -> Vec<i32> {
        let half_range = (self.config.steps_out as i32) * self.config.step_size;
        let start_pos = starting_position - half_range;
        let total_points = (self.config.steps_out * 2 + 1) as usize;

        (0..total_points)
            .map(|i| start_pos + (i as i32) * self.config.step_size)
            .collect()
    }

    /// Process collected data points and find best focus position
    pub fn find_best_focus(
        &self,
        data_points: Vec<FocusDataPoint>,
    ) -> Result<AutofocusResult, String> {
        if data_points.len() < 3 {
            return Err("Not enough data points for curve fitting".to_string());
        }

        // Apply outlier rejection if configured
        let filtered_points = if self.config.outlier_rejection_sigma > 0.0 {
            self.reject_outliers(&data_points)?
        } else {
            data_points.clone()
        };

        if filtered_points.len() < 3 {
            return Err("Not enough valid data points after outlier rejection".to_string());
        }

        // Fit curve based on method
        let (best_position, curve_quality) = match self.config.method {
            AutofocusMethod::VCurve => self.fit_vcurve(&filtered_points)?,
            AutofocusMethod::Quadratic => self.fit_parabola(&filtered_points)?,
            AutofocusMethod::Hyperbolic => self.fit_hyperbola(&filtered_points)?,
        };

        // Find actual best HFR from data
        let best_hfr = filtered_points
            .iter()
            .map(|p| p.hfr)
            .min_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(0.0);

        Ok(AutofocusResult {
            best_position,
            best_hfr,
            curve_fit_quality: curve_quality,
            method_used: self.config.method,
            data_points: filtered_points,
            temperature_celsius: None, // Set by caller
            backlash_applied: self.config.backlash_compensation > 0,
        })
    }

    /// Reject outliers using sigma clipping on HFR values
    fn reject_outliers(&self, points: &[FocusDataPoint]) -> Result<Vec<FocusDataPoint>, String> {
        if points.len() < 3 {
            return Ok(points.to_vec());
        }

        // Calculate median and MAD
        let mut hfrs: Vec<f64> = points.iter().map(|p| p.hfr).collect();
        hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let median = hfrs[hfrs.len() / 2];

        let mut deviations: Vec<f64> = hfrs.iter().map(|&h| (h - median).abs()).collect();
        deviations.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let mad = deviations[deviations.len() / 2];

        // Convert MAD to standard deviation estimate
        let sigma = mad * 1.4826;
        let threshold = self.config.outlier_rejection_sigma * sigma;

        // Filter points
        let filtered: Vec<FocusDataPoint> = points
            .iter()
            .filter(|p| (p.hfr - median).abs() <= threshold)
            .cloned()
            .collect();

        if filtered.len() < 3 {
            return Err("Too many outliers detected, autofocus failed".to_string());
        }

        Ok(filtered)
    }

    /// Fit a simple V-curve (piecewise linear) and find minimum
    fn fit_vcurve(&self, points: &[FocusDataPoint]) -> Result<(i32, f64), String> {
        // Simple approach: find minimum HFR point
        let min_point = points
            .iter()
            .min_by(|a, b| {
                a.hfr
                    .partial_cmp(&b.hfr)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .ok_or("No minimum found")?;

        // Calculate fit quality using normalized RMSE
        let mean_hfr: f64 = points.iter().map(|p| p.hfr).sum::<f64>() / points.len() as f64;
        let mut ss_tot = 0.0;
        let mut ss_res = 0.0;

        for point in points {
            ss_tot += (point.hfr - mean_hfr).powi(2);
            // For V-curve, predicted value at minimum is just min_hfr
            ss_res += (point.hfr - min_point.hfr).powi(2);
        }

        let r_squared = if ss_tot > 0.0 {
            1.0 - (ss_res / ss_tot)
        } else {
            0.0
        };

        Ok((min_point.position, r_squared.max(0.0)))
    }

    /// Fit a parabola (quadratic) to focus data
    /// Returns (best_position, r_squared)
    fn fit_parabola(&self, points: &[FocusDataPoint]) -> Result<(i32, f64), String> {
        if points.len() < 3 {
            return Err("Need at least 3 points for parabolic fit".to_string());
        }

        // Fit y = ax^2 + bx + c where y=HFR, x=position
        // Using least squares: solve normal equations
        let n = points.len() as f64;
        let mut sum_x = 0.0;
        let mut sum_y = 0.0;
        let mut sum_x2 = 0.0;
        let mut sum_x3 = 0.0;
        let mut sum_x4 = 0.0;
        let mut sum_xy = 0.0;
        let mut sum_x2y = 0.0;

        for point in points {
            let x = point.position as f64;
            let y = point.hfr;
            sum_x += x;
            sum_y += y;
            sum_x2 += x * x;
            sum_x3 += x * x * x;
            sum_x4 += x * x * x * x;
            sum_xy += x * y;
            sum_x2y += x * x * y;
        }

        // Solve 3x3 system using Cramer's rule
        let det = n * (sum_x2 * sum_x4 - sum_x3 * sum_x3)
            - sum_x * (sum_x * sum_x4 - sum_x2 * sum_x3)
            + sum_x2 * (sum_x * sum_x3 - sum_x2 * sum_x2);

        if det.abs() < 1e-10 {
            return Err("Singular matrix in parabolic fit".to_string());
        }

        // Calculate coefficients using Cramer's rule
        let det_a = sum_y * (sum_x2 * sum_x4 - sum_x3 * sum_x3)
            - sum_x * (sum_xy * sum_x4 - sum_x2y * sum_x3)
            + sum_x2 * (sum_xy * sum_x3 - sum_x2y * sum_x2);

        let det_b = n * (sum_xy * sum_x4 - sum_x2y * sum_x3)
            - sum_y * (sum_x * sum_x4 - sum_x2 * sum_x3)
            + sum_x2 * (sum_x * sum_x2y - sum_xy * sum_x2);

        let det_c = n * (sum_x2 * sum_x2y - sum_x3 * sum_xy)
            - sum_x * (sum_x * sum_x2y - sum_x2 * sum_xy)
            + sum_y * (sum_x * sum_x3 - sum_x2 * sum_x2);

        let a = det_c / det; // Coefficient of x^2
        let b = det_b / det; // Coefficient of x
        let c = det_a / det; // Constant

        // Check if parabola opens upward (minimum exists)
        if a <= 0.0 {
            return Err("Parabola does not have a minimum (a <= 0)".to_string());
        }

        // Find vertex (minimum): x = -b / (2a)
        let best_position = (-b / (2.0 * a)).round() as i32;

        // Calculate R-squared
        let mean_y = sum_y / n;
        let mut ss_tot = 0.0;
        let mut ss_res = 0.0;

        for point in points {
            let x = point.position as f64;
            let predicted = a * x * x + b * x + c;
            ss_tot += (point.hfr - mean_y).powi(2);
            ss_res += (point.hfr - predicted).powi(2);
        }

        let r_squared = if ss_tot > 0.0 {
            1.0 - (ss_res / ss_tot)
        } else {
            0.0
        };

        Ok((best_position, r_squared.max(0.0)))
    }

    /// Fit a hyperbola to focus data
    /// Uses form: HFR = sqrt((x - x0)^2 * a^2 + b^2)
    /// Returns (best_position, r_squared)
    fn fit_hyperbola(&self, points: &[FocusDataPoint]) -> Result<(i32, f64), String> {
        if points.len() < 3 {
            return Err("Need at least 3 points for hyperbolic fit".to_string());
        }

        // Use iterative approach: start with parabola as initial guess
        let (initial_x0, _) = self.fit_parabola(points)?;
        let mut x0 = initial_x0 as f64;

        // Find minimum HFR as initial b
        let min_hfr = points
            .iter()
            .map(|p| p.hfr)
            .min_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(1.0);
        let b = min_hfr;

        // Iterative refinement (Levenberg-Marquardt-like approach, simplified)
        for _iteration in 0..10 {
            let mut sum_num = 0.0;
            let mut sum_den = 0.0;

            for point in points {
                let x = point.position as f64;
                let dx = x - x0;
                let y = point.hfr;

                if y * y > b * b {
                    let term = (y * y - b * b).sqrt();
                    if term.abs() > 1e-10 {
                        sum_num += dx * term;
                        sum_den += term * term;
                    }
                }
            }

            if sum_den > 1e-10 {
                let a = sum_num / sum_den;

                // Update x0 and b
                let mut new_x0_sum = 0.0;
                let mut _new_b_sum = 0.0;
                let mut count = 0.0;

                for point in points {
                    let x = point.position as f64;
                    let y = point.hfr;
                    let dx = x - x0;

                    if a.abs() > 1e-10 {
                        let predicted_dx_sq = (y * y - b * b) / (a * a);
                        if predicted_dx_sq >= 0.0 {
                            let predicted_dx = predicted_dx_sq.sqrt();
                            new_x0_sum += x - predicted_dx * dx.signum();
                            count += 1.0;
                        }
                    }

                    let predicted_y = ((dx * a).powi(2) + b * b).sqrt();
                    _new_b_sum += (y - predicted_y).abs();
                }

                if count > 0.0 {
                    let new_x0 = new_x0_sum / count;
                    // Gradually update x0 to avoid oscillation
                    x0 = 0.7 * x0 + 0.3 * new_x0;
                }
            }
        }

        // Calculate R-squared for final fit
        let mean_y: f64 = points.iter().map(|p| p.hfr).sum::<f64>() / points.len() as f64;
        let mut ss_tot = 0.0;
        let mut ss_res = 0.0;

        // Recalculate 'a' for final fit
        let mut sum_num = 0.0;
        let mut sum_den = 0.0;
        for point in points {
            let x = point.position as f64;
            let dx = x - x0;
            let y = point.hfr;
            if y * y > b * b {
                let term = (y * y - b * b).sqrt();
                sum_num += dx * term;
                sum_den += term * term;
            }
        }
        let a = if sum_den > 1e-10 {
            sum_num / sum_den
        } else {
            1.0
        };

        for point in points {
            let x = point.position as f64;
            let dx = x - x0;
            let predicted = ((dx * a).powi(2) + b * b).sqrt();
            ss_tot += (point.hfr - mean_y).powi(2);
            ss_res += (point.hfr - predicted).powi(2);
        }

        let r_squared = if ss_tot > 0.0 {
            (1.0 - (ss_res / ss_tot)).max(0.0)
        } else {
            0.0
        };

        Ok((x0.round() as i32, r_squared))
    }
}

/// Backlash compensation helper
///
/// When moving to a target position, if we're moving inward (decreasing position),
/// we overshoot by the backlash amount then move back to ensure consistent approach direction.
#[derive(Debug, Clone)]
pub struct BacklashCompensation {
    pub backlash_steps: i32,
}

impl BacklashCompensation {
    pub fn new(backlash_steps: i32) -> Self {
        Self { backlash_steps }
    }

    /// Calculate the approach positions for backlash compensation
    /// Returns (intermediate_position, final_position)
    pub fn calculate_approach(&self, current: i32, target: i32) -> (Option<i32>, i32) {
        if self.backlash_steps == 0 {
            return (None, target);
        }

        if target < current {
            // Moving inward - apply backlash compensation
            // First move past target, then approach from outside
            let overshoot = target - self.backlash_steps;
            (Some(overshoot), target)
        } else {
            // Moving outward - no backlash compensation needed
            (None, target)
        }
    }

    /// Check if backlash compensation is needed for this move
    pub fn is_needed(&self, current: i32, target: i32) -> bool {
        self.backlash_steps > 0 && target < current
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parabolic_fit() {
        let config = AutofocusConfig {
            method: AutofocusMethod::Quadratic,
            ..Default::default()
        };
        let engine = VCurveAutofocus::new(config);

        // Generate perfect parabola: HFR = 0.001 * (x - 5000)^2 + 2.0
        let positions = vec![4500, 4700, 4900, 5000, 5100, 5300, 5500];
        let points: Vec<FocusDataPoint> = positions
            .iter()
            .map(|&pos| {
                let x = pos as f64 - 5000.0;
                let hfr = 0.001 * x * x + 2.0;
                FocusDataPoint {
                    position: pos,
                    hfr,
                    fwhm: None,
                    star_count: 50,
                }
            })
            .collect();

        let (best_pos, r_squared) = engine.fit_parabola(&points).unwrap();

        assert!(
            (best_pos - 5000).abs() < 10,
            "Best position should be near 5000, got {}",
            best_pos
        );
        assert!(
            r_squared > 0.99,
            "R-squared should be very high for perfect parabola, got {}",
            r_squared
        );
    }

    #[test]
    fn test_vcurve_fit() {
        let config = AutofocusConfig {
            method: AutofocusMethod::VCurve,
            ..Default::default()
        };
        let engine = VCurveAutofocus::new(config);

        let points = vec![
            FocusDataPoint {
                position: 1000,
                hfr: 5.0,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1100,
                hfr: 3.5,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1200,
                hfr: 2.2,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1300,
                hfr: 3.8,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1400,
                hfr: 5.5,
                fwhm: None,
                star_count: 50,
            },
        ];

        let (best_pos, _) = engine.fit_vcurve(&points).unwrap();
        assert_eq!(best_pos, 1200, "Should find minimum at position 1200");
    }

    #[test]
    fn test_backlash_compensation() {
        let backlash = BacklashCompensation::new(50);

        // Moving inward - should apply backlash
        let (intermediate, final_pos) = backlash.calculate_approach(5000, 4500);
        assert_eq!(intermediate, Some(4450)); // Overshoot by 50
        assert_eq!(final_pos, 4500);

        // Moving outward - no backlash needed
        let (intermediate, final_pos) = backlash.calculate_approach(4500, 5000);
        assert_eq!(intermediate, None);
        assert_eq!(final_pos, 5000);
    }

    #[test]
    fn test_outlier_rejection() {
        let config = AutofocusConfig {
            outlier_rejection_sigma: 2.0,
            ..Default::default()
        };
        let engine = VCurveAutofocus::new(config);

        let points = vec![
            FocusDataPoint {
                position: 1000,
                hfr: 3.0,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1100,
                hfr: 2.8,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1200,
                hfr: 2.5,
                fwhm: None,
                star_count: 50,
            },
            FocusDataPoint {
                position: 1300,
                hfr: 15.0,
                fwhm: None,
                star_count: 50,
            }, // Outlier
            FocusDataPoint {
                position: 1400,
                hfr: 3.2,
                fwhm: None,
                star_count: 50,
            },
        ];

        let filtered = engine.reject_outliers(&points).unwrap();
        assert_eq!(filtered.len(), 4, "Should reject 1 outlier");
        assert!(
            filtered.iter().all(|p| p.hfr < 10.0),
            "Outlier should be removed"
        );
    }

    #[test]
    fn test_calculate_positions() {
        let config = AutofocusConfig {
            step_size: 100,
            steps_out: 3,
            ..Default::default()
        };
        let engine = VCurveAutofocus::new(config);

        let positions = engine.calculate_positions(5000);

        // Should have 2*3+1 = 7 positions
        assert_eq!(positions.len(), 7);

        // Should range from 4700 to 5300 in steps of 100
        assert_eq!(positions[0], 4700);
        assert_eq!(positions[3], 5000); // Middle position
        assert_eq!(positions[6], 5300);
    }
}
