//! Focus Prediction Engine
//!
//! Provides temperature-based focus position prediction and filter offset management.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A single focus data point from an autofocus run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusDataPoint {
    pub timestamp_secs: i64,
    pub temperature_celsius: f64,
    pub focus_position: i32,
    pub hfr: f64,
    pub filter_name: Option<String>,
}

/// Linear regression model for temperature-focus correlation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusModel {
    pub slope: f64,     // Steps per degree C
    pub intercept: f64, // Base focus position at 0°C
    pub r_squared: f64, // Correlation coefficient
    pub data_point_count: usize,
}

impl FocusModel {
    /// Predict focus position for a given temperature
    pub fn predict_position(&self, temperature: f64) -> i32 {
        (self.intercept + self.slope * temperature).round() as i32
    }

    /// Check if model is reliable enough to use
    pub fn is_reliable(&self) -> bool {
        self.r_squared >= 0.7 && self.data_point_count >= 5
    }
}

/// Filter focus offset relative to a reference filter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterOffset {
    pub filter_name: String,
    pub reference_filter: String,
    pub offset_steps: i32,
    pub measurement_count: usize,
    pub confidence: f64,
}

/// Focus prediction engine with temperature compensation
#[derive(Debug, Clone, Default)]
pub struct FocusPredictionEngine {
    data_points: Vec<FocusDataPoint>,
    temperature_model: Option<FocusModel>,
    filter_offsets: HashMap<String, FilterOffset>,
    reference_filter: Option<String>,
    max_data_points: usize,
}

impl FocusPredictionEngine {
    pub fn new() -> Self {
        Self {
            data_points: Vec::new(),
            temperature_model: None,
            filter_offsets: HashMap::new(),
            reference_filter: None,
            max_data_points: 100,
        }
    }

    /// Add a data point from an autofocus run
    pub fn add_datapoint(&mut self, point: FocusDataPoint) {
        self.data_points.push(point);
        self.trim_data_points();

        // Recalculate model
        self.recalculate_model();
    }

    fn trim_data_points(&mut self) {
        if self.data_points.len() <= self.max_data_points {
            return;
        }
        if self.max_data_points == 0 {
            self.data_points.clear();
            return;
        }
        if self.max_data_points == 1 {
            if let Some(last) = self
                .data_points
                .iter()
                .max_by_key(|point| point.timestamp_secs)
                .cloned()
            {
                self.data_points = vec![last];
            }
            return;
        }

        self.data_points
            .sort_by(|a, b| a.timestamp_secs.cmp(&b.timestamp_secs));

        let last_index = self.data_points.len() - 1;
        let target_last_index = self.max_data_points - 1;
        let mut retained = Vec::with_capacity(self.max_data_points);

        for slot in 0..self.max_data_points {
            let idx = if slot == target_last_index {
                last_index
            } else {
                ((slot as f64 * last_index as f64) / target_last_index as f64).round() as usize
            };

            if retained
                .last()
                .map(|point: &FocusDataPoint| {
                    point.timestamp_secs == self.data_points[idx].timestamp_secs
                })
                .unwrap_or(false)
            {
                continue;
            }

            retained.push(self.data_points[idx].clone());
        }

        self.data_points = retained;
    }

    /// Recalculate the temperature-focus model using linear regression
    fn recalculate_model(&mut self) {
        if self.data_points.len() < 3 {
            self.temperature_model = None;
            if let Some(ref_filter) = &self.reference_filter {
                self.update_filter_offsets(ref_filter.clone());
            }
            return;
        }

        // Group by temperature buckets and take best HFR from each
        let mut buckets: HashMap<i32, Vec<&FocusDataPoint>> = HashMap::new();
        for point in &self.data_points {
            let bucket = point.temperature_celsius.round() as i32;
            buckets.entry(bucket).or_default().push(point);
        }

        // Take best (lowest HFR) from each bucket
        let mut best_points: Vec<&FocusDataPoint> = Vec::new();
        for points in buckets.values() {
            if let Some(best) = points.iter().min_by(|a, b| {
                a.hfr
                    .partial_cmp(&b.hfr)
                    .unwrap_or(std::cmp::Ordering::Equal)
            }) {
                best_points.push(best);
            }
        }

        if best_points.len() < 3 {
            self.temperature_model = None;
        } else {
            // Linear regression: y = mx + b
            let n = best_points.len() as f64;
            let (mut sum_x, mut sum_y, mut sum_xy, mut sum_x2) = (0.0, 0.0, 0.0, 0.0);

            for point in &best_points {
                let x = point.temperature_celsius;
                let y = point.focus_position as f64;
                sum_x += x;
                sum_y += y;
                sum_xy += x * y;
                sum_x2 += x * x;
            }

            let denom = n * sum_x2 - sum_x * sum_x;
            if denom.abs() < 1e-10 {
                self.temperature_model = None;
            } else {
                let slope = (n * sum_xy - sum_x * sum_y) / denom;
                let intercept = (sum_y - slope * sum_x) / n;

                // Calculate R-squared
                let mean_y = sum_y / n;
                let mut ss_tot = 0.0;
                let mut ss_res = 0.0;

                for point in &best_points {
                    let predicted = intercept + slope * point.temperature_celsius;
                    ss_tot += (point.focus_position as f64 - mean_y).powi(2);
                    ss_res += (point.focus_position as f64 - predicted).powi(2);
                }

                let r_squared = if ss_tot > 0.0 {
                    1.0 - (ss_res / ss_tot)
                } else {
                    0.0
                };

                self.temperature_model = Some(FocusModel {
                    slope,
                    intercept,
                    r_squared,
                    data_point_count: best_points.len(),
                });
            }
        }

        // Update filter offsets if we have a reference
        if let Some(ref_filter) = &self.reference_filter {
            self.update_filter_offsets(ref_filter.clone());
        }
    }

    /// Update filter offsets based on collected data
    fn update_filter_offsets(&mut self, reference_filter: String) {
        self.filter_offsets.clear();

        // Group by filter
        let mut by_filter: HashMap<String, Vec<&FocusDataPoint>> = HashMap::new();
        for point in &self.data_points {
            if let Some(filter) = &point.filter_name {
                by_filter.entry(filter.clone()).or_default().push(point);
            }
        }

        // Get reference filter average
        let ref_points = match by_filter.get(&reference_filter) {
            Some(points) if !points.is_empty() => points,
            _ => return,
        };

        let ref_avg: f64 = ref_points
            .iter()
            .map(|p| p.focus_position as f64)
            .sum::<f64>()
            / ref_points.len() as f64;

        // Calculate offsets for each filter
        for (filter_name, points) in &by_filter {
            if filter_name == &reference_filter || points.is_empty() {
                continue;
            }

            let filter_avg: f64 =
                points.iter().map(|p| p.focus_position as f64).sum::<f64>() / points.len() as f64;

            let offset_steps = (filter_avg - ref_avg).round() as i32;

            // Calculate confidence based on variance and count
            let variance: f64 = points
                .iter()
                .map(|p| (p.focus_position as f64 - filter_avg).powi(2))
                .sum::<f64>()
                / points.len() as f64;

            let std_dev = variance.sqrt();
            let consistency = if std_dev < 50.0 { 1.0 } else { 50.0 / std_dev };
            let count_factor = (points.len() as f64 / 5.0).min(1.0);
            let confidence = (consistency * count_factor).clamp(0.0, 1.0);

            self.filter_offsets.insert(
                filter_name.clone(),
                FilterOffset {
                    filter_name: filter_name.clone(),
                    reference_filter: reference_filter.clone(),
                    offset_steps,
                    measurement_count: points.len(),
                    confidence,
                },
            );
        }
    }

    /// Predict optimal focus position based on current conditions
    pub fn predict_position(
        &self,
        temperature: f64,
        filter: Option<&str>,
    ) -> Option<PredictionResult> {
        let model = self.temperature_model.as_ref()?;
        if !model.is_reliable() {
            return None;
        }

        let mut predicted_position = model.predict_position(temperature);
        let mut confidence = model.r_squared;
        let mut filter_offset = 0;

        // Apply filter offset if applicable
        if let Some(filter_name) = filter {
            if let Some(offset) = self.filter_offsets.get(filter_name) {
                if offset.confidence >= 0.5 {
                    filter_offset = offset.offset_steps;
                    predicted_position += filter_offset;
                    confidence *= offset.confidence;
                }
            }
        }

        Some(PredictionResult {
            position: predicted_position,
            confidence,
            based_on_temperature: temperature,
            filter_offset,
            slope: model.slope,
        })
    }

    /// Check if autofocus should be triggered based on temperature drift
    pub fn should_refocus(
        &self,
        current_temp: f64,
        last_focus_temp: f64,
        max_drift_steps: f64,
    ) -> bool {
        let model = match &self.temperature_model {
            Some(m) if m.is_reliable() => m,
            _ => return false,
        };

        let temp_delta = (current_temp - last_focus_temp).abs();
        let expected_drift = temp_delta * model.slope.abs();

        expected_drift >= max_drift_steps
    }

    /// Set the reference filter for offset calculations
    pub fn set_reference_filter(&mut self, filter: String) {
        self.reference_filter = Some(filter.clone());
        self.update_filter_offsets(filter);
    }

    /// Get the current temperature model
    pub fn get_model(&self) -> Option<&FocusModel> {
        self.temperature_model.as_ref()
    }

    /// Get filter offset for a specific filter
    pub fn get_filter_offset(&self, filter: &str) -> Option<&FilterOffset> {
        self.filter_offsets.get(filter)
    }

    /// Clear all data
    pub fn clear(&mut self) {
        self.data_points.clear();
        self.temperature_model = None;
        self.filter_offsets.clear();
    }

    /// Get data point count
    pub fn data_point_count(&self) -> usize {
        self.data_points.len()
    }
}

/// Result of focus position prediction
#[derive(Debug, Clone)]
pub struct PredictionResult {
    pub position: i32,
    pub confidence: f64,
    pub based_on_temperature: f64,
    pub filter_offset: i32,
    pub slope: f64, // For display: steps per °C
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear_model() {
        let mut engine = FocusPredictionEngine::new();

        // Add data points with clear linear relationship
        // Focus moves 100 steps per degree C
        for i in 0..10 {
            let temp = 10.0 + i as f64;
            let pos = 10000 + (i * 100);
            engine.add_datapoint(FocusDataPoint {
                timestamp_secs: i as i64,
                temperature_celsius: temp,
                focus_position: pos,
                hfr: 2.0,
                filter_name: None,
            });
        }

        let model = engine.get_model().expect("Model should exist");
        assert!(model.is_reliable());
        assert!((model.slope - 100.0).abs() < 1.0);
        assert!(model.r_squared > 0.99);

        // Test prediction
        let prediction = engine.predict_position(15.0, None).expect("Should predict");
        assert!((prediction.position - 10500).abs() < 10);
    }

    #[test]
    fn test_filter_offsets() {
        let mut engine = FocusPredictionEngine::new();
        engine.set_reference_filter("L".to_string());

        // Add L filter data
        for i in 0..5 {
            engine.add_datapoint(FocusDataPoint {
                timestamp_secs: i as i64,
                temperature_celsius: 15.0,
                focus_position: 10000,
                hfr: 2.0,
                filter_name: Some("L".to_string()),
            });
        }

        // Add Ha filter data with offset
        for i in 0..5 {
            engine.add_datapoint(FocusDataPoint {
                timestamp_secs: (i + 10) as i64,
                temperature_celsius: 15.0,
                focus_position: 10200,
                hfr: 2.0,
                filter_name: Some("Ha".to_string()),
            });
        }

        let offset = engine.get_filter_offset("Ha").expect("Offset should exist");
        assert_eq!(offset.offset_steps, 200);
        assert!(offset.confidence > 0.5);
    }

    #[test]
    fn test_trim_data_points_preserves_history_span() {
        let mut engine = FocusPredictionEngine::new();
        engine.max_data_points = 5;

        for i in 0..10 {
            engine.add_datapoint(FocusDataPoint {
                timestamp_secs: i,
                temperature_celsius: 10.0 + i as f64,
                focus_position: 10000 + i as i32,
                hfr: 2.0,
                filter_name: None,
            });
        }

        let timestamps: Vec<i64> = engine
            .data_points
            .iter()
            .map(|p| p.timestamp_secs)
            .collect();
        assert_eq!(timestamps.len(), 5);
        assert_eq!(timestamps.first().copied(), Some(0));
        assert_eq!(timestamps.last().copied(), Some(9));
    }
}
