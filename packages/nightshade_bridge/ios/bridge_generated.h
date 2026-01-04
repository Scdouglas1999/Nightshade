#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
// EXTRA BEGIN
typedef struct DartCObject *WireSyncRust2DartDco;
typedef struct WireSyncRust2DartSse {
  uint8_t *ptr;
  int32_t len;
} WireSyncRust2DartSse;

typedef int64_t DartPort;
typedef bool (*DartPostCObjectFnType)(DartPort port_id, void *message);
void store_dart_post_cobject(DartPostCObjectFnType ptr);
// EXTRA END
typedef struct _Dart_Handle* Dart_Handle;

/**
 * Default event buffer size.
 *
 * This is sized to handle burst scenarios like:
 * - Rapid autofocus loops (100+ events in seconds)
 * - High-frequency guiding corrections (10+ per second)
 * - Multiple simultaneous device state changes
 *
 * The buffer uses a broadcast channel, so if any receiver falls behind by more than
 * this many events, it will receive a `Lagged` error and skip to the latest events.
 * Increasing this value uses more memory but reduces the chance of dropping events
 * when the Dart side is slow to consume them.
 */
#define DEFAULT_EVENT_BUFFER_SIZE 4096

typedef struct wire_cst_list_prim_u_8_strict {
  uint8_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_8_strict;

typedef struct wire_cst_stretch_params_api {
  double shadows;
  double highlights;
  double midtones;
} wire_cst_stretch_params_api;

typedef struct wire_cst_list_prim_u_16_loose {
  uint16_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_16_loose;

typedef struct wire_cst_list_String {
  struct wire_cst_list_prim_u_8_strict **ptr;
  int32_t len;
} wire_cst_list_String;

typedef struct wire_cst_star_detection_config_api {
  double detection_sigma;
  uint32_t min_area;
  uint32_t max_area;
  double max_eccentricity;
  uint32_t saturation_limit;
  uint32_t hfr_radius;
  double *min_hfr;
  double *min_snr;
  double *max_sharpness;
} wire_cst_star_detection_config_api;

typedef struct wire_cst_autofocus_config_api {
  double exposure_time;
  int32_t step_size;
  int32_t steps_out;
  struct wire_cst_list_prim_u_8_strict *method;
  int32_t binning;
} wire_cst_autofocus_config_api;

typedef struct wire_cst_indi_autofocus_config_api {
  struct wire_cst_list_prim_u_8_strict *method;
  int32_t step_size;
  uint32_t steps_out;
  double exposure_duration;
  int32_t backlash_compensation;
  bool use_temperature_prediction;
  double *max_star_count_change;
  double outlier_rejection_sigma;
  int32_t binning;
  uint64_t move_timeout_secs;
  uint64_t settling_time_ms;
} wire_cst_indi_autofocus_config_api;

typedef struct wire_cst_fits_write_header {
  struct wire_cst_list_prim_u_8_strict *object_name;
  double exposure_time;
  struct wire_cst_list_prim_u_8_strict *capture_timestamp;
  struct wire_cst_list_prim_u_8_strict *frame_type;
  struct wire_cst_list_prim_u_8_strict *filter;
  int32_t *gain;
  int32_t *offset;
  double *ccd_temp;
  double *ra;
  double *dec;
  double *altitude;
  struct wire_cst_list_prim_u_8_strict *telescope;
  struct wire_cst_list_prim_u_8_strict *instrument;
  struct wire_cst_list_prim_u_8_strict *observer;
  int32_t bin_x;
  int32_t bin_y;
  double *focal_length;
  double *aperture;
  double *pixel_size_x;
  double *pixel_size_y;
  double *site_latitude;
  double *site_longitude;
  double *site_elevation;
} wire_cst_fits_write_header;

typedef struct wire_cst_equipment_profile {
  struct wire_cst_list_prim_u_8_strict *id;
  struct wire_cst_list_prim_u_8_strict *name;
  struct wire_cst_list_prim_u_8_strict *camera_id;
  struct wire_cst_list_prim_u_8_strict *mount_id;
  struct wire_cst_list_prim_u_8_strict *focuser_id;
  struct wire_cst_list_prim_u_8_strict *filter_wheel_id;
  struct wire_cst_list_prim_u_8_strict *guider_id;
  struct wire_cst_list_prim_u_8_strict *rotator_id;
  struct wire_cst_list_prim_u_8_strict *dome_id;
  struct wire_cst_list_prim_u_8_strict *weather_id;
  struct wire_cst_list_prim_u_8_strict *cover_calibrator_id;
  double telescope_focal_length;
  double telescope_aperture;
} wire_cst_equipment_profile;

typedef struct wire_cst_record_string_string {
  struct wire_cst_list_prim_u_8_strict *field0;
  struct wire_cst_list_prim_u_8_strict *field1;
} wire_cst_record_string_string;

typedef struct wire_cst_list_record_string_string {
  struct wire_cst_record_string_string *ptr;
  int32_t len;
} wire_cst_list_record_string_string;

typedef struct wire_cst_node_definition_api {
  struct wire_cst_list_prim_u_8_strict *id;
  struct wire_cst_list_prim_u_8_strict *name;
  struct wire_cst_list_prim_u_8_strict *node_type;
  bool enabled;
  struct wire_cst_list_String *children;
  struct wire_cst_list_prim_u_8_strict *config_json;
} wire_cst_node_definition_api;

typedef struct wire_cst_list_node_definition_api {
  struct wire_cst_node_definition_api *ptr;
  int32_t len;
} wire_cst_list_node_definition_api;

typedef struct wire_cst_sequence_definition_api {
  struct wire_cst_list_prim_u_8_strict *id;
  struct wire_cst_list_prim_u_8_strict *name;
  struct wire_cst_list_prim_u_8_strict *description;
  struct wire_cst_list_node_definition_api *nodes;
  struct wire_cst_list_prim_u_8_strict *root_node_id;
} wire_cst_sequence_definition_api;

typedef struct wire_cst_observer_location {
  double latitude;
  double longitude;
  double elevation;
} wire_cst_observer_location;

typedef struct wire_cst_app_settings {
  struct wire_cst_observer_location *location;
  struct wire_cst_list_prim_u_8_strict *theme;
  struct wire_cst_list_prim_u_8_strict *language;
  bool auto_connect;
} wire_cst_app_settings;

typedef struct wire_cst_camera_capabilities {
  uint32_t max_width;
  uint32_t max_height;
  uint32_t bit_depth;
  bool has_shutter;
  bool can_set_ccd_temperature;
  bool can_set_cooler;
  bool can_get_cooler_power;
  bool can_bin;
  int32_t max_bin_x;
  int32_t max_bin_y;
  bool can_asymmetric_bin;
  bool can_set_gain;
  int32_t *gain_min;
  int32_t *gain_max;
  bool can_set_offset;
  int32_t *offset_min;
  int32_t *offset_max;
  bool can_abort_exposure;
  bool can_stop_exposure;
  bool can_subframe;
  double *pixel_size_x;
  double *pixel_size_y;
  bool is_color;
  struct wire_cst_list_prim_u_8_strict *bayer_pattern;
  struct wire_cst_list_prim_u_8_strict *sensor_type;
  bool has_fast_readout;
  struct wire_cst_list_String *readout_modes;
  double *exposure_min;
  double *exposure_max;
  double *ccd_temperature;
  double *set_ccd_temperature;
  double *cooler_power;
  bool *cooler_on;
} wire_cst_camera_capabilities;

typedef struct wire_cst_list_prim_u_32_strict {
  uint32_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_32_strict;

typedef struct wire_cst_image_stats_result {
  double min;
  double max;
  double mean;
  double median;
  double std_dev;
  double *hfr;
  uint32_t star_count;
} wire_cst_image_stats_result;

typedef struct wire_cst_captured_image_result {
  uint32_t width;
  uint32_t height;
  struct wire_cst_list_prim_u_8_strict *display_data;
  struct wire_cst_list_prim_u_32_strict *histogram;
  struct wire_cst_image_stats_result stats;
  double exposure_time;
  struct wire_cst_list_prim_u_8_strict *timestamp;
  bool is_color;
} wire_cst_captured_image_result;

typedef struct wire_cst_checkpoint_info_api {
  struct wire_cst_list_prim_u_8_strict *sequence_name;
  struct wire_cst_list_prim_u_8_strict *timestamp;
  uint32_t completed_exposures;
  double completed_integration_secs;
  bool can_resume;
  int64_t age_seconds;
} wire_cst_checkpoint_info_api;

typedef struct wire_cst_cover_calibrator_capabilities {
  int32_t max_brightness;
  bool cover_present;
  bool calibrator_present;
  int32_t *cover_state;
  int32_t *calibrator_state;
  int32_t *brightness;
} wire_cst_cover_calibrator_capabilities;

typedef struct wire_cst_dome_capabilities {
  bool can_set_azimuth;
  bool can_park;
  bool can_find_home;
  bool can_set_shutter;
  bool can_sync_azimuth;
  double *azimuth;
  bool slewing;
  bool at_home;
  bool at_park;
  int32_t *shutter_status;
  bool can_slave;
  bool slaved;
  bool can_abort;
} wire_cst_dome_capabilities;

typedef struct wire_cst_EquipmentEvent_Connecting {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
} wire_cst_EquipmentEvent_Connecting;

typedef struct wire_cst_EquipmentEvent_Connected {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
} wire_cst_EquipmentEvent_Connected;

typedef struct wire_cst_EquipmentEvent_Disconnected {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
} wire_cst_EquipmentEvent_Disconnected;

typedef struct wire_cst_EquipmentEvent_PropertyChanged {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *property;
  struct wire_cst_list_prim_u_8_strict *value;
} wire_cst_EquipmentEvent_PropertyChanged;

typedef struct wire_cst_EquipmentEvent_Error {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_EquipmentEvent_Error;

typedef struct wire_cst_EquipmentEvent_MountSlewStarted {
  double ra;
  double dec;
} wire_cst_EquipmentEvent_MountSlewStarted;

typedef struct wire_cst_EquipmentEvent_MountSlewCompleted {
  double ra;
  double dec;
} wire_cst_EquipmentEvent_MountSlewCompleted;

typedef struct wire_cst_EquipmentEvent_FocuserMoveStarted {
  int32_t target_position;
} wire_cst_EquipmentEvent_FocuserMoveStarted;

typedef struct wire_cst_EquipmentEvent_FocuserMoveCompleted {
  int32_t position;
} wire_cst_EquipmentEvent_FocuserMoveCompleted;

typedef struct wire_cst_EquipmentEvent_FocuserTemperatureChanged {
  double temperature;
} wire_cst_EquipmentEvent_FocuserTemperatureChanged;

typedef struct wire_cst_EquipmentEvent_FilterChanging {
  int32_t from_position;
  int32_t to_position;
  struct wire_cst_list_prim_u_8_strict *filter_name;
} wire_cst_EquipmentEvent_FilterChanging;

typedef struct wire_cst_EquipmentEvent_FilterChanged {
  int32_t position;
  struct wire_cst_list_prim_u_8_strict *filter_name;
} wire_cst_EquipmentEvent_FilterChanged;

typedef struct wire_cst_EquipmentEvent_RotatorMoveStarted {
  double target_angle;
} wire_cst_EquipmentEvent_RotatorMoveStarted;

typedef struct wire_cst_EquipmentEvent_RotatorMoveCompleted {
  double angle;
} wire_cst_EquipmentEvent_RotatorMoveCompleted;

typedef struct wire_cst_EquipmentEvent_CameraCoolingStarted {
  double target_temp;
} wire_cst_EquipmentEvent_CameraCoolingStarted;

typedef struct wire_cst_EquipmentEvent_CameraCoolingReached {
  double temperature;
} wire_cst_EquipmentEvent_CameraCoolingReached;

typedef struct wire_cst_EquipmentEvent_HeartbeatStarted {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  uint64_t interval_secs;
} wire_cst_EquipmentEvent_HeartbeatStarted;

typedef struct wire_cst_EquipmentEvent_HeartbeatStopped {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
} wire_cst_EquipmentEvent_HeartbeatStopped;

typedef struct wire_cst_EquipmentEvent_HeartbeatStatusChanged {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  int32_t status;
  uint32_t consecutive_failures;
  uint64_t *last_rtt_ms;
} wire_cst_EquipmentEvent_HeartbeatStatusChanged;

typedef struct wire_cst_EquipmentEvent_HeartbeatReconnecting {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  uint32_t attempt;
  uint32_t max_attempts;
} wire_cst_EquipmentEvent_HeartbeatReconnecting;

typedef struct wire_cst_EquipmentEvent_HeartbeatReconnected {
  struct wire_cst_list_prim_u_8_strict *device_type;
  struct wire_cst_list_prim_u_8_strict *device_id;
  uint32_t after_attempts;
} wire_cst_EquipmentEvent_HeartbeatReconnected;

typedef union EquipmentEventKind {
  struct wire_cst_EquipmentEvent_Connecting Connecting;
  struct wire_cst_EquipmentEvent_Connected Connected;
  struct wire_cst_EquipmentEvent_Disconnected Disconnected;
  struct wire_cst_EquipmentEvent_PropertyChanged PropertyChanged;
  struct wire_cst_EquipmentEvent_Error Error;
  struct wire_cst_EquipmentEvent_MountSlewStarted MountSlewStarted;
  struct wire_cst_EquipmentEvent_MountSlewCompleted MountSlewCompleted;
  struct wire_cst_EquipmentEvent_FocuserMoveStarted FocuserMoveStarted;
  struct wire_cst_EquipmentEvent_FocuserMoveCompleted FocuserMoveCompleted;
  struct wire_cst_EquipmentEvent_FocuserTemperatureChanged FocuserTemperatureChanged;
  struct wire_cst_EquipmentEvent_FilterChanging FilterChanging;
  struct wire_cst_EquipmentEvent_FilterChanged FilterChanged;
  struct wire_cst_EquipmentEvent_RotatorMoveStarted RotatorMoveStarted;
  struct wire_cst_EquipmentEvent_RotatorMoveCompleted RotatorMoveCompleted;
  struct wire_cst_EquipmentEvent_CameraCoolingStarted CameraCoolingStarted;
  struct wire_cst_EquipmentEvent_CameraCoolingReached CameraCoolingReached;
  struct wire_cst_EquipmentEvent_HeartbeatStarted HeartbeatStarted;
  struct wire_cst_EquipmentEvent_HeartbeatStopped HeartbeatStopped;
  struct wire_cst_EquipmentEvent_HeartbeatStatusChanged HeartbeatStatusChanged;
  struct wire_cst_EquipmentEvent_HeartbeatReconnecting HeartbeatReconnecting;
  struct wire_cst_EquipmentEvent_HeartbeatReconnected HeartbeatReconnected;
} EquipmentEventKind;

typedef struct wire_cst_equipment_event {
  int32_t tag;
  union EquipmentEventKind kind;
} wire_cst_equipment_event;

typedef struct wire_cst_list_prim_i_32_strict {
  int32_t *ptr;
  int32_t len;
} wire_cst_list_prim_i_32_strict;

typedef struct wire_cst_filter_wheel_capabilities {
  int32_t position_count;
  int32_t *current_position;
  struct wire_cst_list_String *filter_names;
  struct wire_cst_list_prim_i_32_strict *focus_offsets;
  bool is_moving;
  bool can_set_filter_names;
  bool can_set_focus_offsets;
} wire_cst_filter_wheel_capabilities;

typedef struct wire_cst_focuser_capabilities {
  int32_t max_position;
  int32_t max_increment;
  double *step_size;
  bool absolute;
  bool temp_comp_available;
  bool temp_comp;
  double *temperature;
  bool is_moving;
  int32_t *position;
  bool can_halt;
  bool can_reverse;
  bool *reverse;
} wire_cst_focuser_capabilities;

typedef struct wire_cst_GuidingEvent_Settled {
  double rms;
} wire_cst_GuidingEvent_Settled;

typedef struct wire_cst_GuidingEvent_DitherStarted {
  double pixels;
} wire_cst_GuidingEvent_DitherStarted;

typedef struct wire_cst_GuidingEvent_Correction {
  double ra;
  double dec;
  double ra_raw;
  double dec_raw;
} wire_cst_GuidingEvent_Correction;

typedef union GuidingEventKind {
  struct wire_cst_GuidingEvent_Settled Settled;
  struct wire_cst_GuidingEvent_DitherStarted DitherStarted;
  struct wire_cst_GuidingEvent_Correction Correction;
} GuidingEventKind;

typedef struct wire_cst_guiding_event {
  int32_t tag;
  union GuidingEventKind kind;
} wire_cst_guiding_event;

typedef struct wire_cst_ImagingEvent_ExposureStarted {
  double duration_secs;
  int32_t frame_type;
} wire_cst_ImagingEvent_ExposureStarted;

typedef struct wire_cst_ImagingEvent_ExposureStartedWithFrame {
  double duration_secs;
  int32_t frame_type;
  uint32_t frame_number;
  uint32_t *total_frames;
} wire_cst_ImagingEvent_ExposureStartedWithFrame;

typedef struct wire_cst_ImagingEvent_ExposureProgress {
  double progress;
  double remaining_secs;
} wire_cst_ImagingEvent_ExposureProgress;

typedef struct wire_cst_ImagingEvent_ExposureCompleted {
  struct wire_cst_list_prim_u_8_strict *file_path;
  double hfr;
  uint32_t stars_detected;
} wire_cst_ImagingEvent_ExposureCompleted;

typedef struct wire_cst_ImagingEvent_ExposureCompletedWithFrame {
  uint32_t frame_number;
  uint32_t *total_frames;
  double hfr;
  uint32_t stars_detected;
} wire_cst_ImagingEvent_ExposureCompletedWithFrame;

typedef struct wire_cst_ImagingEvent_ExposureFailed {
  struct wire_cst_list_prim_u_8_strict *error;
} wire_cst_ImagingEvent_ExposureFailed;

typedef struct wire_cst_ImagingEvent_ImageReady {
  uint32_t width;
  uint32_t height;
} wire_cst_ImagingEvent_ImageReady;

typedef struct wire_cst_ImagingEvent_ImageSaved {
  struct wire_cst_list_prim_u_8_strict *file_path;
} wire_cst_ImagingEvent_ImageSaved;

typedef struct wire_cst_ImagingEvent_TemperatureChanged {
  double temp_celsius;
  double cooler_power;
} wire_cst_ImagingEvent_TemperatureChanged;

typedef struct wire_cst_ImagingEvent_ExposureComplete {
  bool success;
} wire_cst_ImagingEvent_ExposureComplete;

typedef struct wire_cst_ImagingEvent_ExposureFailedOld {
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_ImagingEvent_ExposureFailedOld;

typedef union ImagingEventKind {
  struct wire_cst_ImagingEvent_ExposureStarted ExposureStarted;
  struct wire_cst_ImagingEvent_ExposureStartedWithFrame ExposureStartedWithFrame;
  struct wire_cst_ImagingEvent_ExposureProgress ExposureProgress;
  struct wire_cst_ImagingEvent_ExposureCompleted ExposureCompleted;
  struct wire_cst_ImagingEvent_ExposureCompletedWithFrame ExposureCompletedWithFrame;
  struct wire_cst_ImagingEvent_ExposureFailed ExposureFailed;
  struct wire_cst_ImagingEvent_ImageReady ImageReady;
  struct wire_cst_ImagingEvent_ImageSaved ImageSaved;
  struct wire_cst_ImagingEvent_TemperatureChanged TemperatureChanged;
  struct wire_cst_ImagingEvent_ExposureComplete ExposureComplete;
  struct wire_cst_ImagingEvent_ExposureFailedOld ExposureFailedOld;
} ImagingEventKind;

typedef struct wire_cst_imaging_event {
  int32_t tag;
  union ImagingEventKind kind;
} wire_cst_imaging_event;

typedef struct wire_cst_list_tracking_rate {
  int32_t *ptr;
  int32_t len;
} wire_cst_list_tracking_rate;

typedef struct wire_cst_mount_capabilities {
  bool can_slew;
  bool can_slew_async;
  bool can_sync;
  bool can_park;
  bool can_unpark;
  bool can_set_park;
  bool can_pulse_guide;
  bool can_get_side_of_pier;
  bool can_set_side_of_pier;
  bool can_set_tracking;
  bool can_set_tracking_rate;
  struct wire_cst_list_tracking_rate *supported_tracking_rates;
  bool is_equatorial;
  bool supports_alt_az;
  bool can_get_pointing_state;
  bool can_find_home;
  bool *tracking;
  int32_t *tracking_rate;
  bool can_abort_slew;
  double *max_slew_rate;
  bool can_move_axis;
  uint32_t axis_count;
} wire_cst_mount_capabilities;

typedef struct wire_cst_polar_alignment_event {
  double azimuth_error;
  double altitude_error;
  double total_error;
  double current_ra;
  double current_dec;
  double target_ra;
  double target_dec;
} wire_cst_polar_alignment_event;

typedef struct wire_cst_polar_alignment_image_event {
  struct wire_cst_list_prim_u_8_strict *image_data;
  uint32_t width;
  uint32_t height;
  double *solved_ra;
  double *solved_dec;
  int32_t point;
  struct wire_cst_list_prim_u_8_strict *phase;
} wire_cst_polar_alignment_image_event;

typedef struct wire_cst_polar_alignment_status {
  struct wire_cst_list_prim_u_8_strict *status;
  struct wire_cst_list_prim_u_8_strict *phase;
  int32_t point;
} wire_cst_polar_alignment_status;

typedef struct wire_cst_rotator_capabilities {
  bool can_reverse;
  bool reverse;
  double *step_size;
  bool is_moving;
  double *mechanical_position;
  double *position;
  bool can_move_absolute;
  bool can_halt;
  bool can_sync;
} wire_cst_rotator_capabilities;

typedef struct wire_cst_SafetyEvent_WeatherUnsafe {
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_SafetyEvent_WeatherUnsafe;

typedef struct wire_cst_SafetyEvent_EmergencyStop {
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_SafetyEvent_EmergencyStop;

typedef struct wire_cst_SafetyEvent_ParkInitiated {
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_SafetyEvent_ParkInitiated;

typedef union SafetyEventKind {
  struct wire_cst_SafetyEvent_WeatherUnsafe WeatherUnsafe;
  struct wire_cst_SafetyEvent_EmergencyStop EmergencyStop;
  struct wire_cst_SafetyEvent_ParkInitiated ParkInitiated;
} SafetyEventKind;

typedef struct wire_cst_safety_event {
  int32_t tag;
  union SafetyEventKind kind;
} wire_cst_safety_event;

typedef struct wire_cst_safety_monitor_capabilities {
  bool is_safe;
  struct wire_cst_list_prim_u_8_strict *safety_description;
} wire_cst_safety_monitor_capabilities;

typedef struct wire_cst_SequencerEvent_Started {
  struct wire_cst_list_prim_u_8_strict *sequence_name;
} wire_cst_SequencerEvent_Started;

typedef struct wire_cst_SequencerEvent_NodeStarted {
  struct wire_cst_list_prim_u_8_strict *node_id;
  struct wire_cst_list_prim_u_8_strict *node_type;
} wire_cst_SequencerEvent_NodeStarted;

typedef struct wire_cst_SequencerEvent_NodeCompleted {
  struct wire_cst_list_prim_u_8_strict *node_id;
  bool success;
} wire_cst_SequencerEvent_NodeCompleted;

typedef struct wire_cst_SequencerEvent_Progress {
  uint32_t current;
  uint32_t total;
} wire_cst_SequencerEvent_Progress;

typedef struct wire_cst_SequencerEvent_TargetChanged {
  struct wire_cst_list_prim_u_8_strict *target_name;
} wire_cst_SequencerEvent_TargetChanged;

typedef struct wire_cst_SequencerEvent_TargetCompleted {
  struct wire_cst_list_prim_u_8_strict *target_name;
} wire_cst_SequencerEvent_TargetCompleted;

typedef struct wire_cst_SequencerEvent_ExposureStarted {
  uint32_t frame;
  uint32_t total;
  struct wire_cst_list_prim_u_8_strict *filter;
  double duration_secs;
} wire_cst_SequencerEvent_ExposureStarted;

typedef struct wire_cst_SequencerEvent_ExposureCompleted {
  uint32_t frame;
  uint32_t total;
  double duration_secs;
} wire_cst_SequencerEvent_ExposureCompleted;

typedef struct wire_cst_SequencerEvent_Error {
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_SequencerEvent_Error;

typedef struct wire_cst_SequencerEvent_InstructionProgress {
  struct wire_cst_list_prim_u_8_strict *node_id;
  struct wire_cst_list_prim_u_8_strict *instruction;
  double progress_percent;
  struct wire_cst_list_prim_u_8_strict *detail;
} wire_cst_SequencerEvent_InstructionProgress;

typedef union SequencerEventKind {
  struct wire_cst_SequencerEvent_Started Started;
  struct wire_cst_SequencerEvent_NodeStarted NodeStarted;
  struct wire_cst_SequencerEvent_NodeCompleted NodeCompleted;
  struct wire_cst_SequencerEvent_Progress Progress;
  struct wire_cst_SequencerEvent_TargetChanged TargetChanged;
  struct wire_cst_SequencerEvent_TargetCompleted TargetCompleted;
  struct wire_cst_SequencerEvent_ExposureStarted ExposureStarted;
  struct wire_cst_SequencerEvent_ExposureCompleted ExposureCompleted;
  struct wire_cst_SequencerEvent_Error Error;
  struct wire_cst_SequencerEvent_InstructionProgress InstructionProgress;
} SequencerEventKind;

typedef struct wire_cst_sequencer_event {
  int32_t tag;
  union SequencerEventKind kind;
} wire_cst_sequencer_event;

typedef struct wire_cst_switch_info {
  int32_t index;
  struct wire_cst_list_prim_u_8_strict *name;
  struct wire_cst_list_prim_u_8_strict *description;
  bool is_boolean;
  double min_value;
  double max_value;
  double step;
  bool can_write;
  double value;
} wire_cst_switch_info;

typedef struct wire_cst_list_switch_info {
  struct wire_cst_switch_info *ptr;
  int32_t len;
} wire_cst_list_switch_info;

typedef struct wire_cst_switch_capabilities {
  int32_t switch_count;
  struct wire_cst_list_switch_info *switches;
} wire_cst_switch_capabilities;

typedef struct wire_cst_SystemEvent_Error {
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_SystemEvent_Error;

typedef struct wire_cst_SystemEvent_DiskSpaceLow {
  double available_gb;
} wire_cst_SystemEvent_DiskSpaceLow;

typedef struct wire_cst_SystemEvent_Notification {
  struct wire_cst_list_prim_u_8_strict *title;
  struct wire_cst_list_prim_u_8_strict *message;
  struct wire_cst_list_prim_u_8_strict *level;
} wire_cst_SystemEvent_Notification;

typedef struct wire_cst_SystemEvent_EventsDropped {
  uint64_t dropped_count;
  uint64_t total_dropped;
} wire_cst_SystemEvent_EventsDropped;

typedef union SystemEventKind {
  struct wire_cst_SystemEvent_Error Error;
  struct wire_cst_SystemEvent_DiskSpaceLow DiskSpaceLow;
  struct wire_cst_SystemEvent_Notification Notification;
  struct wire_cst_SystemEvent_EventsDropped EventsDropped;
} SystemEventKind;

typedef struct wire_cst_system_event {
  int32_t tag;
  union SystemEventKind kind;
} wire_cst_system_event;

typedef struct wire_cst_weather_capabilities {
  bool has_cloud_cover;
  bool has_dew_point;
  bool has_humidity;
  bool has_pressure;
  bool has_rain_rate;
  bool has_sky_brightness;
  bool has_sky_quality;
  bool has_sky_temperature;
  bool has_seeing;
  bool has_temperature;
  bool has_wind_direction;
  bool has_wind_gust;
  bool has_wind_speed;
  double *average_period;
} wire_cst_weather_capabilities;

typedef struct wire_cst_detected_star_info {
  double x;
  double y;
  double flux;
  double hfr;
  double fwhm;
  double peak;
  double background;
  double snr;
  double eccentricity;
  double sharpness;
} wire_cst_detected_star_info;

typedef struct wire_cst_list_detected_star_info {
  struct wire_cst_detected_star_info *ptr;
  int32_t len;
} wire_cst_list_detected_star_info;

typedef struct wire_cst_device_info {
  struct wire_cst_list_prim_u_8_strict *id;
  struct wire_cst_list_prim_u_8_strict *name;
  int32_t device_type;
  int32_t driver_type;
  struct wire_cst_list_prim_u_8_strict *description;
  struct wire_cst_list_prim_u_8_strict *driver_version;
  struct wire_cst_list_prim_u_8_strict *serial_number;
  struct wire_cst_list_prim_u_8_strict *unique_id;
  struct wire_cst_list_prim_u_8_strict *display_name;
} wire_cst_device_info;

typedef struct wire_cst_list_device_info {
  struct wire_cst_device_info *ptr;
  int32_t len;
} wire_cst_list_device_info;

typedef struct wire_cst_list_equipment_profile {
  struct wire_cst_equipment_profile *ptr;
  int32_t len;
} wire_cst_list_equipment_profile;

typedef struct wire_cst_focus_data_point {
  int32_t position;
  double hfr;
  double *fwhm;
  uint32_t star_count;
} wire_cst_focus_data_point;

typedef struct wire_cst_list_focus_data_point {
  struct wire_cst_focus_data_point *ptr;
  int32_t len;
} wire_cst_list_focus_data_point;

typedef struct wire_cst_focus_data_point_api {
  int32_t position;
  double hfr;
  double *fwhm;
  uint32_t star_count;
} wire_cst_focus_data_point_api;

typedef struct wire_cst_list_focus_data_point_api {
  struct wire_cst_focus_data_point_api *ptr;
  int32_t len;
} wire_cst_list_focus_data_point_api;

typedef struct wire_cst_mosaic_panel_result {
  double ra_hours;
  double dec_degrees;
  uint32_t panel_index;
  uint32_t row;
  uint32_t col;
} wire_cst_mosaic_panel_result;

typedef struct wire_cst_list_mosaic_panel_result {
  struct wire_cst_mosaic_panel_result *ptr;
  int32_t len;
} wire_cst_list_mosaic_panel_result;

typedef struct wire_cst_phd_2_algo_param {
  struct wire_cst_list_prim_u_8_strict *name;
  double value;
} wire_cst_phd_2_algo_param;

typedef struct wire_cst_list_phd_2_algo_param {
  struct wire_cst_phd_2_algo_param *ptr;
  int32_t len;
} wire_cst_list_phd_2_algo_param;

typedef struct wire_cst_list_prim_f_32_strict {
  float *ptr;
  int32_t len;
} wire_cst_list_prim_f_32_strict;

typedef struct wire_cst_list_prim_u_16_strict {
  uint16_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_16_strict;

typedef struct wire_cst_autofocus_result_api {
  int32_t best_position;
  double best_hfr;
  struct wire_cst_list_focus_data_point *focus_data;
  struct wire_cst_list_prim_u_8_strict *method;
  double *temperature;
  int64_t timestamp;
  double curve_fit_quality;
  bool backlash_applied;
} wire_cst_autofocus_result_api;

typedef struct wire_cst_camera_status {
  bool connected;
  int32_t state;
  double *sensor_temp;
  double *cooler_power;
  double *target_temp;
  bool cooler_on;
  int32_t gain;
  int32_t offset;
  int32_t bin_x;
  int32_t bin_y;
  uint32_t sensor_width;
  uint32_t sensor_height;
  double pixel_size_x;
  double pixel_size_y;
  uint32_t max_adu;
  bool can_cool;
  bool can_set_gain;
  bool can_set_offset;
} wire_cst_camera_status;

typedef struct wire_cst_cover_calibrator_status {
  bool connected;
  int32_t cover_state;
  int32_t calibrator_state;
  int32_t brightness;
  int32_t max_brightness;
} wire_cst_cover_calibrator_status;

typedef struct wire_cst_device_api_version {
  struct wire_cst_list_prim_u_8_strict *device_id;
  int32_t driver_type;
  uint32_t *interface_version;
  struct wire_cst_list_prim_u_8_strict *protocol_version;
  struct wire_cst_list_prim_u_8_strict *driver_version;
  struct wire_cst_list_prim_u_8_strict *driver_info;
  struct wire_cst_list_String *supported_actions;
  int64_t queried_at;
} wire_cst_device_api_version;

typedef struct wire_cst_DeviceCapabilities_Mount {
  struct wire_cst_mount_capabilities *field0;
} wire_cst_DeviceCapabilities_Mount;

typedef struct wire_cst_DeviceCapabilities_Camera {
  struct wire_cst_camera_capabilities *field0;
} wire_cst_DeviceCapabilities_Camera;

typedef struct wire_cst_DeviceCapabilities_Focuser {
  struct wire_cst_focuser_capabilities *field0;
} wire_cst_DeviceCapabilities_Focuser;

typedef struct wire_cst_DeviceCapabilities_FilterWheel {
  struct wire_cst_filter_wheel_capabilities *field0;
} wire_cst_DeviceCapabilities_FilterWheel;

typedef struct wire_cst_DeviceCapabilities_Rotator {
  struct wire_cst_rotator_capabilities *field0;
} wire_cst_DeviceCapabilities_Rotator;

typedef struct wire_cst_DeviceCapabilities_Dome {
  struct wire_cst_dome_capabilities *field0;
} wire_cst_DeviceCapabilities_Dome;

typedef struct wire_cst_DeviceCapabilities_CoverCalibrator {
  struct wire_cst_cover_calibrator_capabilities *field0;
} wire_cst_DeviceCapabilities_CoverCalibrator;

typedef struct wire_cst_DeviceCapabilities_Weather {
  struct wire_cst_weather_capabilities *field0;
} wire_cst_DeviceCapabilities_Weather;

typedef struct wire_cst_DeviceCapabilities_SafetyMonitor {
  struct wire_cst_safety_monitor_capabilities *field0;
} wire_cst_DeviceCapabilities_SafetyMonitor;

typedef struct wire_cst_DeviceCapabilities_Switch {
  struct wire_cst_switch_capabilities *field0;
} wire_cst_DeviceCapabilities_Switch;

typedef union DeviceCapabilitiesKind {
  struct wire_cst_DeviceCapabilities_Mount Mount;
  struct wire_cst_DeviceCapabilities_Camera Camera;
  struct wire_cst_DeviceCapabilities_Focuser Focuser;
  struct wire_cst_DeviceCapabilities_FilterWheel FilterWheel;
  struct wire_cst_DeviceCapabilities_Rotator Rotator;
  struct wire_cst_DeviceCapabilities_Dome Dome;
  struct wire_cst_DeviceCapabilities_CoverCalibrator CoverCalibrator;
  struct wire_cst_DeviceCapabilities_Weather Weather;
  struct wire_cst_DeviceCapabilities_SafetyMonitor SafetyMonitor;
  struct wire_cst_DeviceCapabilities_Switch Switch;
} DeviceCapabilitiesKind;

typedef struct wire_cst_device_capabilities {
  int32_t tag;
  union DeviceCapabilitiesKind kind;
} wire_cst_device_capabilities;

typedef struct wire_cst_device_heartbeat_info {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *device_type;
  bool heartbeat_active;
  int64_t *last_successful_comm_ms;
  uint64_t interval_secs;
  uint64_t max_interval_secs;
  uint32_t failure_threshold;
  bool auto_reconnect;
  uint32_t max_reconnect_attempts;
} wire_cst_device_heartbeat_info;

typedef struct wire_cst_dome_status {
  bool connected;
  double azimuth;
  double *altitude;
  int32_t shutter_status;
  bool slewing;
  bool at_home;
  bool at_park;
  bool can_set_altitude;
  bool can_set_azimuth;
  bool can_set_shutter;
  bool can_slave;
  bool is_slaved;
} wire_cst_dome_status;

typedef struct wire_cst_EventPayload_Equipment {
  struct wire_cst_equipment_event *field0;
} wire_cst_EventPayload_Equipment;

typedef struct wire_cst_EventPayload_Imaging {
  struct wire_cst_imaging_event *field0;
} wire_cst_EventPayload_Imaging;

typedef struct wire_cst_EventPayload_Guiding {
  struct wire_cst_guiding_event *field0;
} wire_cst_EventPayload_Guiding;

typedef struct wire_cst_EventPayload_Sequencer {
  struct wire_cst_sequencer_event *field0;
} wire_cst_EventPayload_Sequencer;

typedef struct wire_cst_EventPayload_Safety {
  struct wire_cst_safety_event *field0;
} wire_cst_EventPayload_Safety;

typedef struct wire_cst_EventPayload_System {
  struct wire_cst_system_event *field0;
} wire_cst_EventPayload_System;

typedef struct wire_cst_EventPayload_PolarAlignment {
  struct wire_cst_polar_alignment_event *field0;
} wire_cst_EventPayload_PolarAlignment;

typedef struct wire_cst_EventPayload_PolarAlignmentStatus {
  struct wire_cst_polar_alignment_status *field0;
} wire_cst_EventPayload_PolarAlignmentStatus;

typedef struct wire_cst_EventPayload_PolarAlignmentImage {
  struct wire_cst_polar_alignment_image_event *field0;
} wire_cst_EventPayload_PolarAlignmentImage;

typedef union EventPayloadKind {
  struct wire_cst_EventPayload_Equipment Equipment;
  struct wire_cst_EventPayload_Imaging Imaging;
  struct wire_cst_EventPayload_Guiding Guiding;
  struct wire_cst_EventPayload_Sequencer Sequencer;
  struct wire_cst_EventPayload_Safety Safety;
  struct wire_cst_EventPayload_System System;
  struct wire_cst_EventPayload_PolarAlignment PolarAlignment;
  struct wire_cst_EventPayload_PolarAlignmentStatus PolarAlignmentStatus;
  struct wire_cst_EventPayload_PolarAlignmentImage PolarAlignmentImage;
} EventPayloadKind;

typedef struct wire_cst_event_payload {
  int32_t tag;
  union EventPayloadKind kind;
} wire_cst_event_payload;

typedef struct wire_cst_filter_wheel_status {
  bool connected;
  int32_t position;
  bool moving;
  int32_t filter_count;
  struct wire_cst_list_String *filter_names;
} wire_cst_filter_wheel_status;

typedef struct wire_cst_fits_read_result {
  uint32_t width;
  uint32_t height;
  int32_t bitpix;
  struct wire_cst_list_prim_u_8_strict *display_data;
  struct wire_cst_list_prim_u_32_strict *histogram;
  struct wire_cst_image_stats_result stats;
  struct wire_cst_list_prim_u_8_strict *object_name;
  double *exposure_time;
  struct wire_cst_list_prim_u_8_strict *filter;
  double *ra;
  double *dec;
  struct wire_cst_list_prim_u_8_strict *date_obs;
  struct wire_cst_list_prim_u_8_strict *bayer_pattern;
} wire_cst_fits_read_result;

typedef struct wire_cst_focuser_status {
  bool connected;
  int32_t position;
  bool moving;
  double *temperature;
  int32_t max_position;
  double step_size;
  bool is_absolute;
  bool has_temperature;
} wire_cst_focuser_status;

typedef struct wire_cst_indi_autofocus_result_api {
  int32_t best_position;
  double best_hfr;
  double curve_fit_quality;
  struct wire_cst_list_prim_u_8_strict *method_used;
  struct wire_cst_list_focus_data_point_api *data_points;
  double *temperature_celsius;
  bool backlash_applied;
  bool success;
  struct wire_cst_list_prim_u_8_strict *error_message;
} wire_cst_indi_autofocus_result_api;

typedef struct wire_cst_mount_status {
  bool connected;
  bool tracking;
  bool slewing;
  bool parked;
  bool at_home;
  int32_t side_of_pier;
  double right_ascension;
  double declination;
  double altitude;
  double azimuth;
  double sidereal_time;
  int32_t tracking_rate;
  bool can_park;
  bool can_slew;
  bool can_sync;
  bool can_pulse_guide;
  bool can_set_tracking_rate;
} wire_cst_mount_status;

typedef struct wire_cst_NightshadeError_DeviceNotFound {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_DeviceNotFound;

typedef struct wire_cst_NightshadeError_ConnectionFailed {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_NightshadeError_ConnectionFailed;

typedef struct wire_cst_NightshadeError_AlreadyConnected {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_AlreadyConnected;

typedef struct wire_cst_NightshadeError_NotConnected {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_NotConnected;

typedef struct wire_cst_NightshadeError_DeviceDisconnected {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_NightshadeError_DeviceDisconnected;

typedef struct wire_cst_NightshadeError_HardwareError {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *message;
  int32_t *error_code;
} wire_cst_NightshadeError_HardwareError;

typedef struct wire_cst_NightshadeError_CommunicationError {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_NightshadeError_CommunicationError;

typedef struct wire_cst_NightshadeError_Timeout {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_Timeout;

typedef struct wire_cst_NightshadeError_DeviceTimeout {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *operation;
  double timeout_secs;
} wire_cst_NightshadeError_DeviceTimeout;

typedef struct wire_cst_NightshadeError_ConnectionTimeout {
  struct wire_cst_list_prim_u_8_strict *device_id;
  double timeout_secs;
} wire_cst_NightshadeError_ConnectionTimeout;

typedef struct wire_cst_NightshadeError_InvalidParameter {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_InvalidParameter;

typedef struct wire_cst_NightshadeError_InvalidInput {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_InvalidInput;

typedef struct wire_cst_NightshadeError_InvalidDeviceId {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_NightshadeError_InvalidDeviceId;

typedef struct wire_cst_NightshadeError_ParameterOutOfRange {
  struct wire_cst_list_prim_u_8_strict *param_name;
  struct wire_cst_list_prim_u_8_strict *value;
  struct wire_cst_list_prim_u_8_strict *min;
  struct wire_cst_list_prim_u_8_strict *max;
} wire_cst_NightshadeError_ParameterOutOfRange;

typedef struct wire_cst_NightshadeError_OperationFailed {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_OperationFailed;

typedef struct wire_cst_NightshadeError_NotSupported {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *operation;
} wire_cst_NightshadeError_NotSupported;

typedef struct wire_cst_NightshadeError_DeviceBusy {
  struct wire_cst_list_prim_u_8_strict *device_id;
  struct wire_cst_list_prim_u_8_strict *current_operation;
} wire_cst_NightshadeError_DeviceBusy;

typedef struct wire_cst_NightshadeError_ImageError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_ImageError;

typedef struct wire_cst_NightshadeError_CameraError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_CameraError;

typedef struct wire_cst_NightshadeError_ExposureFailed {
  struct wire_cst_list_prim_u_8_strict *camera_id;
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_NightshadeError_ExposureFailed;

typedef struct wire_cst_NightshadeError_DownloadFailed {
  struct wire_cst_list_prim_u_8_strict *camera_id;
  struct wire_cst_list_prim_u_8_strict *reason;
} wire_cst_NightshadeError_DownloadFailed;

typedef struct wire_cst_NightshadeError_IoError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_IoError;

typedef struct wire_cst_NightshadeError_PlateSolveError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_PlateSolveError;

typedef struct wire_cst_NightshadeError_SequenceError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_SequenceError;

typedef struct wire_cst_NightshadeError_AscomError {
  struct wire_cst_list_prim_u_8_strict *prog_id;
  struct wire_cst_list_prim_u_8_strict *message;
  int32_t error_code;
} wire_cst_NightshadeError_AscomError;

typedef struct wire_cst_NightshadeError_AlpacaError {
  struct wire_cst_list_prim_u_8_strict *base_url;
  uint32_t device_number;
  struct wire_cst_list_prim_u_8_strict *message;
  int32_t error_code;
} wire_cst_NightshadeError_AlpacaError;

typedef struct wire_cst_NightshadeError_IndiError {
  struct wire_cst_list_prim_u_8_strict *server;
  uint16_t port;
  struct wire_cst_list_prim_u_8_strict *device_name;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_NightshadeError_IndiError;

typedef struct wire_cst_NightshadeError_NativeError {
  struct wire_cst_list_prim_u_8_strict *vendor;
  struct wire_cst_list_prim_u_8_strict *message;
  int32_t error_code;
} wire_cst_NightshadeError_NativeError;

typedef struct wire_cst_NightshadeError_ComError {
  struct wire_cst_list_prim_u_8_strict *message;
  uint32_t hresult;
} wire_cst_NightshadeError_ComError;

typedef struct wire_cst_NightshadeError_Internal {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_Internal;

typedef struct wire_cst_NightshadeError_RuntimeInitFailed {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_NightshadeError_RuntimeInitFailed;

typedef struct wire_cst_NightshadeError_ResourceExhausted {
  struct wire_cst_list_prim_u_8_strict *resource;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_NightshadeError_ResourceExhausted;

typedef union NightshadeErrorKind {
  struct wire_cst_NightshadeError_DeviceNotFound DeviceNotFound;
  struct wire_cst_NightshadeError_ConnectionFailed ConnectionFailed;
  struct wire_cst_NightshadeError_AlreadyConnected AlreadyConnected;
  struct wire_cst_NightshadeError_NotConnected NotConnected;
  struct wire_cst_NightshadeError_DeviceDisconnected DeviceDisconnected;
  struct wire_cst_NightshadeError_HardwareError HardwareError;
  struct wire_cst_NightshadeError_CommunicationError CommunicationError;
  struct wire_cst_NightshadeError_Timeout Timeout;
  struct wire_cst_NightshadeError_DeviceTimeout DeviceTimeout;
  struct wire_cst_NightshadeError_ConnectionTimeout ConnectionTimeout;
  struct wire_cst_NightshadeError_InvalidParameter InvalidParameter;
  struct wire_cst_NightshadeError_InvalidInput InvalidInput;
  struct wire_cst_NightshadeError_InvalidDeviceId InvalidDeviceId;
  struct wire_cst_NightshadeError_ParameterOutOfRange ParameterOutOfRange;
  struct wire_cst_NightshadeError_OperationFailed OperationFailed;
  struct wire_cst_NightshadeError_NotSupported NotSupported;
  struct wire_cst_NightshadeError_DeviceBusy DeviceBusy;
  struct wire_cst_NightshadeError_ImageError ImageError;
  struct wire_cst_NightshadeError_CameraError CameraError;
  struct wire_cst_NightshadeError_ExposureFailed ExposureFailed;
  struct wire_cst_NightshadeError_DownloadFailed DownloadFailed;
  struct wire_cst_NightshadeError_IoError IoError;
  struct wire_cst_NightshadeError_PlateSolveError PlateSolveError;
  struct wire_cst_NightshadeError_SequenceError SequenceError;
  struct wire_cst_NightshadeError_AscomError AscomError;
  struct wire_cst_NightshadeError_AlpacaError AlpacaError;
  struct wire_cst_NightshadeError_IndiError IndiError;
  struct wire_cst_NightshadeError_NativeError NativeError;
  struct wire_cst_NightshadeError_ComError ComError;
  struct wire_cst_NightshadeError_Internal Internal;
  struct wire_cst_NightshadeError_RuntimeInitFailed RuntimeInitFailed;
  struct wire_cst_NightshadeError_ResourceExhausted ResourceExhausted;
} NightshadeErrorKind;

typedef struct wire_cst_nightshade_error {
  int32_t tag;
  union NightshadeErrorKind kind;
} wire_cst_nightshade_error;

typedef struct wire_cst_nightshade_event {
  uint64_t event_id;
  int64_t timestamp;
  int32_t severity;
  int32_t category;
  struct wire_cst_event_payload payload;
  uint64_t *caused_by;
  struct wire_cst_list_prim_u_8_strict *correlation_id;
  struct wire_cst_list_prim_u_8_strict *device_id;
} wire_cst_nightshade_event;

typedef struct wire_cst_phd_2_calibration_data {
  bool is_calibrated;
  double *ra_angle;
  double *dec_angle;
  double *ra_rate;
  double *dec_rate;
} wire_cst_phd_2_calibration_data;

typedef struct wire_cst_phd_2_star_image {
  uint32_t frame;
  uint32_t width;
  uint32_t height;
  double star_x;
  double star_y;
  struct wire_cst_list_prim_u_8_strict *pixels;
} wire_cst_phd_2_star_image;

typedef struct wire_cst_phd_2_status {
  bool connected;
  struct wire_cst_list_prim_u_8_strict *state;
  double rms_ra;
  double rms_dec;
  double rms_total;
  double snr;
  double star_mass;
  double pixel_scale;
} wire_cst_phd_2_status;

typedef struct wire_cst_plate_solve_result {
  bool success;
  double ra;
  double dec;
  double pixel_scale;
  double rotation;
  double field_width;
  double field_height;
  double solve_time_secs;
  struct wire_cst_list_prim_u_8_strict *error;
} wire_cst_plate_solve_result;

typedef struct wire_cst_qhy_discovery_status {
  bool sdk_available;
  bool discovery_enabled;
  uint64_t timeout_ms;
} wire_cst_qhy_discovery_status;

typedef struct wire_cst_record_f_64_f_64 {
  double field0;
  double field1;
} wire_cst_record_f_64_f_64;

typedef struct wire_cst_record_i_32_f_64 {
  int32_t field0;
  double field1;
} wire_cst_record_i_32_f_64;

typedef struct wire_cst_record_i_32_list_string {
  int32_t field0;
  struct wire_cst_list_String *field1;
} wire_cst_record_i_32_list_string;

typedef struct wire_cst_record_i_64_bool {
  int64_t field0;
  bool field1;
} wire_cst_record_i_64_bool;

typedef struct wire_cst_record_u_64_u_64_u_32_bool {
  uint64_t field0;
  uint64_t field1;
  uint32_t field2;
  bool field3;
} wire_cst_record_u_64_u_64_u_32_bool;

typedef struct wire_cst_rotator_status {
  bool connected;
  double position;
  bool moving;
  double mechanical_position;
  bool is_moving;
  bool can_reverse;
} wire_cst_rotator_status;

typedef struct wire_cst_sequencer_state {
  struct wire_cst_list_prim_u_8_strict *state;
  struct wire_cst_list_prim_u_8_strict *current_node_id;
  struct wire_cst_list_prim_u_8_strict *current_node_name;
  uint32_t total_exposures;
  uint32_t completed_exposures;
  double total_integration_secs;
  double elapsed_secs;
  double *estimated_remaining_secs;
  struct wire_cst_list_prim_u_8_strict *current_target;
  struct wire_cst_list_prim_u_8_strict *current_filter;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_sequencer_state;

typedef struct wire_cst_session_state {
  bool is_active;
  int64_t *start_time;
  struct wire_cst_list_prim_u_8_strict *target_name;
  double *target_ra;
  double *target_dec;
  uint32_t total_exposures;
  uint32_t completed_exposures;
  double total_integration_secs;
  struct wire_cst_list_prim_u_8_strict *current_filter;
  bool is_guiding;
  bool is_capturing;
  bool is_dithering;
} wire_cst_session_state;

typedef struct wire_cst_simulated_camera {
  struct wire_cst_camera_status status;
} wire_cst_simulated_camera;

typedef struct wire_cst_simulated_filter_wheel {
  struct wire_cst_filter_wheel_status status;
} wire_cst_simulated_filter_wheel;

typedef struct wire_cst_simulated_focuser {
  struct wire_cst_focuser_status status;
} wire_cst_simulated_focuser;

typedef struct wire_cst_simulated_mount {
  struct wire_cst_mount_status status;
} wire_cst_simulated_mount;

typedef struct wire_cst_simulated_rotator {
  struct wire_cst_rotator_status status;
} wire_cst_simulated_rotator;

typedef struct wire_cst_star_detection_result_api {
  struct wire_cst_list_detected_star_info *stars;
  uint32_t star_count;
  double median_hfr;
  double median_fwhm;
  double median_snr;
  double background;
  double noise;
} wire_cst_star_detection_result_api;

typedef struct wire_cst_xisf_read_result {
  uint32_t width;
  uint32_t height;
  uint32_t channels;
  struct wire_cst_list_prim_u_8_strict *display_data;
  struct wire_cst_list_prim_u_32_strict *histogram;
  struct wire_cst_image_stats_result stats;
  struct wire_cst_list_record_string_string *properties;
} wire_cst_xisf_read_result;

void frbgen_nightshade_bridge_wire__crate__api__api_apply_stretch(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *file_path,
                                                                  struct wire_cst_stretch_params_api *params);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_auto_stretch_image(uint32_t width,
                                                                                       uint32_t height,
                                                                                       struct wire_cst_list_prim_u_16_loose *data);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_build_sequence(struct wire_cst_list_prim_u_8_strict *id,
                                                                                   struct wire_cst_list_prim_u_8_strict *name,
                                                                                   struct wire_cst_list_prim_u_8_strict *description,
                                                                                   struct wire_cst_list_String *node_jsons,
                                                                                   struct wire_cst_list_prim_u_8_strict *root_node_id);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_calculate_altitude(double ra_hours,
                                                                                       double dec_degrees,
                                                                                       double latitude,
                                                                                       double longitude,
                                                                                       int64_t time_unix_millis);

void frbgen_nightshade_bridge_wire__crate__api__api_calculate_auto_stretch(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *file_path);

void frbgen_nightshade_bridge_wire__crate__api__api_calculate_hfr(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *file_path);

void frbgen_nightshade_bridge_wire__crate__api__api_calculate_histogram(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *file_path,
                                                                        uint32_t _bins,
                                                                        uint8_t logarithmic);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_calculate_mosaic_area(double panel_width_arcmin,
                                                                                          double panel_height_arcmin,
                                                                                          uint32_t panels_horizontal,
                                                                                          uint32_t panels_vertical);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_calculate_mosaic_panels(double center_ra,
                                                                                            double center_dec,
                                                                                            double panel_width_arcmin,
                                                                                            double panel_height_arcmin,
                                                                                            double overlap_percent,
                                                                                            double rotation,
                                                                                            uint32_t panels_horizontal,
                                                                                            uint32_t panels_vertical);

void frbgen_nightshade_bridge_wire__crate__api__api_camera_cancel_exposure(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_camera_start_exposure(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id,
                                                                          double duration_secs,
                                                                          int32_t gain,
                                                                          int32_t offset,
                                                                          int32_t bin_x,
                                                                          int32_t bin_y);

void frbgen_nightshade_bridge_wire__crate__api__api_cancel_autofocus(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_connect_device(int64_t port_,
                                                                   int32_t device_type,
                                                                   struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_calibrator_off(int64_t port_,
                                                                                    struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_calibrator_on(int64_t port_,
                                                                                   struct wire_cst_list_prim_u_8_strict *device_id,
                                                                                   int32_t brightness);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_close_cover(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_brightness(int64_t port_,
                                                                                    struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_calibrator_state(int64_t port_,
                                                                                          struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_cover_state(int64_t port_,
                                                                                     struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_max_brightness(int64_t port_,
                                                                                        struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_status(int64_t port_,
                                                                                struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_halt_cover(int64_t port_,
                                                                                struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_open_cover(int64_t port_,
                                                                                struct wire_cst_list_prim_u_8_strict *device_id);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_autofocus_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                          struct wire_cst_list_prim_u_8_strict *name,
                                                                                          int32_t step_size,
                                                                                          uint32_t steps_out,
                                                                                          double exposure_duration,
                                                                                          struct wire_cst_list_prim_u_8_strict *method);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_center_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       uint8_t use_target_coords,
                                                                                       double accuracy_arcsec,
                                                                                       uint32_t max_attempts,
                                                                                       double exposure_duration);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_cool_camera_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                            struct wire_cst_list_prim_u_8_strict *name,
                                                                                            double target_temp,
                                                                                            double *duration_mins);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_delay_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                      struct wire_cst_list_prim_u_8_strict *name,
                                                                                      double seconds);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_dither_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       double pixels,
                                                                                       double settle_pixels,
                                                                                       double settle_time,
                                                                                       double settle_timeout,
                                                                                       uint8_t ra_only);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_exposure_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                         struct wire_cst_list_prim_u_8_strict *name,
                                                                                         double duration_secs,
                                                                                         uint32_t count,
                                                                                         struct wire_cst_list_prim_u_8_strict *filter,
                                                                                         int32_t *gain,
                                                                                         int32_t *offset,
                                                                                         int32_t binning,
                                                                                         uint32_t *dither_every);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_filter_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       struct wire_cst_list_prim_u_8_strict *filter_name);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_loop_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                     struct wire_cst_list_prim_u_8_strict *name,
                                                                                     uint32_t *iterations,
                                                                                     struct wire_cst_list_prim_u_8_strict *condition,
                                                                                     struct wire_cst_list_String *children);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_notification_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                             struct wire_cst_list_prim_u_8_strict *name,
                                                                                             struct wire_cst_list_prim_u_8_strict *title,
                                                                                             struct wire_cst_list_prim_u_8_strict *message,
                                                                                             struct wire_cst_list_prim_u_8_strict *level);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_park_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                     struct wire_cst_list_prim_u_8_strict *name);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_rotator_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                        struct wire_cst_list_prim_u_8_strict *name,
                                                                                        double target_angle,
                                                                                        uint8_t relative);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_script_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       struct wire_cst_list_prim_u_8_strict *script_path,
                                                                                       struct wire_cst_list_String *arguments,
                                                                                       uint32_t *timeout_secs);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_slew_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                     struct wire_cst_list_prim_u_8_strict *name,
                                                                                     uint8_t use_target_coords,
                                                                                     double *custom_ra,
                                                                                     double *custom_dec);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_target_group_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                             struct wire_cst_list_prim_u_8_strict *name,
                                                                                             struct wire_cst_list_prim_u_8_strict *target_name,
                                                                                             double ra_hours,
                                                                                             double dec_degrees,
                                                                                             double *rotation,
                                                                                             double *min_altitude,
                                                                                             double *max_altitude,
                                                                                             int32_t priority,
                                                                                             struct wire_cst_list_String *children);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_target_header_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                              struct wire_cst_list_prim_u_8_strict *name,
                                                                                              struct wire_cst_list_prim_u_8_strict *target_name,
                                                                                              double ra_hours,
                                                                                              double dec_degrees,
                                                                                              double *rotation,
                                                                                              double *min_altitude,
                                                                                              double *max_altitude,
                                                                                              int32_t priority,
                                                                                              int64_t *start_after,
                                                                                              int64_t *end_before,
                                                                                              struct wire_cst_list_prim_u_8_strict *mosaic_panel_json,
                                                                                              struct wire_cst_list_String *children);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_unpark_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                       struct wire_cst_list_prim_u_8_strict *name);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_wait_time_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                          struct wire_cst_list_prim_u_8_strict *name,
                                                                                          int64_t *wait_until,
                                                                                          struct wire_cst_list_prim_u_8_strict *twilight_type);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_create_warm_camera_node(struct wire_cst_list_prim_u_8_strict *id,
                                                                                            struct wire_cst_list_prim_u_8_strict *name,
                                                                                            double rate_per_min);

void frbgen_nightshade_bridge_wire__crate__api__api_debayer_fits_file(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *file_path,
                                                                      int32_t pattern,
                                                                      int32_t algorithm);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_debayer_image(uint32_t width,
                                                                                  uint32_t height,
                                                                                  struct wire_cst_list_prim_u_16_loose *data,
                                                                                  struct wire_cst_list_prim_u_8_strict *pattern_str,
                                                                                  struct wire_cst_list_prim_u_8_strict *algo_str);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_delete_profile(struct wire_cst_list_prim_u_8_strict *profile_id);

void frbgen_nightshade_bridge_wire__crate__api__api_detect_stars_in_file(int64_t port_,
                                                                         struct wire_cst_list_prim_u_8_strict *file_path,
                                                                         struct wire_cst_star_detection_config_api *config);

void frbgen_nightshade_bridge_wire__crate__api__api_device_supports_action(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id,
                                                                           struct wire_cst_list_prim_u_8_strict *action);

void frbgen_nightshade_bridge_wire__crate__api__api_device_supports_version(int64_t port_,
                                                                            struct wire_cst_list_prim_u_8_strict *device_id,
                                                                            uint32_t required_version);

void frbgen_nightshade_bridge_wire__crate__api__api_disconnect_device(int64_t port_,
                                                                      int32_t device_type,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_alpaca_at_address(int64_t port_,
                                                                               struct wire_cst_list_prim_u_8_strict *host,
                                                                               uint16_t port);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_alpaca_devices(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_devices(int64_t port_,
                                                                     int32_t device_type);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_at_address(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *host,
                                                                             uint16_t port);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_common_hosts(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_localhost(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_network(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_close_shutter(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_get_azimuth(int64_t port_,
                                                                     struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_get_shutter_status(int64_t port_,
                                                                            struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_is_slewing(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_open_shutter(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_park(int64_t port_,
                                                              struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_dome_slew_to_azimuth(int64_t port_,
                                                                         struct wire_cst_list_prim_u_8_strict *device_id,
                                                                         double azimuth);

void frbgen_nightshade_bridge_wire__crate__api__api_end_session(int64_t port_);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_estimate_mosaic_time(uint32_t total_panels,
                                                                                         double exposure_secs,
                                                                                         uint32_t exposures_per_panel,
                                                                                         double overhead_per_panel_secs);

void frbgen_nightshade_bridge_wire__crate__api__api_event_stream(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_nightshade_bridge_wire__crate__api__api_export_logs(int64_t port_,
                                                                struct wire_cst_list_prim_u_8_strict *output_path);

void frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_get_names(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_by_name(int64_t port_,
                                                                            struct wire_cst_list_prim_u_8_strict *device_id,
                                                                            struct wire_cst_list_prim_u_8_strict *name);

void frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_filter_names(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *device_id,
                                                                                 struct wire_cst_list_String *names);

void frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_position(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *device_id,
                                                                             int32_t position);

void frbgen_nightshade_bridge_wire__crate__api__api_focuser_halt(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_focuser_move_relative(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id,
                                                                          int32_t delta);

void frbgen_nightshade_bridge_wire__crate__api__api_focuser_move_to(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id,
                                                                    int32_t position);

void frbgen_nightshade_bridge_wire__crate__api__api_generate_filename(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *pattern,
                                                                      struct wire_cst_list_prim_u_8_strict *base_dir,
                                                                      struct wire_cst_list_prim_u_8_strict *target,
                                                                      struct wire_cst_list_prim_u_8_strict *filter,
                                                                      double exposure_time,
                                                                      int32_t frame_type,
                                                                      uint32_t frame_number,
                                                                      int32_t *gain,
                                                                      int32_t *offset,
                                                                      double *temperature,
                                                                      uint32_t binning_x,
                                                                      uint32_t binning_y,
                                                                      struct wire_cst_list_prim_u_8_strict *camera,
                                                                      struct wire_cst_list_prim_u_8_strict *telescope,
                                                                      struct wire_cst_list_prim_u_8_strict *extension);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_generate_fits_thumbnail(struct wire_cst_list_prim_u_8_strict *file_path,
                                                                                            uint32_t max_size);

void frbgen_nightshade_bridge_wire__crate__api__api_get_active_profile(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_get_camera_capabilities(int64_t port_,
                                                                            struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_camera_status(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_connected_devices(int64_t port_);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_current_log_file(void);

void frbgen_nightshade_bridge_wire__crate__api__api_get_device_api_version(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_device_capabilities(int64_t port_,
                                                                            struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_device_health(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_device_heartbeat_info(int64_t port_,
                                                                              struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_dome_status(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_dropped_event_count(void);

void frbgen_nightshade_bridge_wire__crate__api__api_get_filterwheel_capabilities(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_filterwheel_status(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_focuser_capabilities(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_focuser_status(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_heartbeat_config_for_type(int64_t port_,
                                                                                  int32_t device_type);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_image_stats(uint32_t width,
                                                                                    uint32_t height,
                                                                                    struct wire_cst_list_prim_u_16_loose *data);

void frbgen_nightshade_bridge_wire__crate__api__api_get_last_image(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_get_last_raw_image_data(int64_t port_);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_location(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_log_directory(void);

void frbgen_nightshade_bridge_wire__crate__api__api_get_mount_capabilities(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_mount_status(int64_t port_,
                                                                     struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_next_frame_number(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *base_dir,
                                                                          struct wire_cst_list_prim_u_8_strict *pattern,
                                                                          struct wire_cst_list_prim_u_8_strict *target,
                                                                          struct wire_cst_list_prim_u_8_strict *filter,
                                                                          int32_t frame_type);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_plate_solver_path(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_profiles(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_qhy_discovery_status(void);

void frbgen_nightshade_bridge_wire__crate__api__api_get_rotator_status(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_get_session_state(int64_t port_);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_settings(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_get_version(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_init(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_init_profile_storage(struct wire_cst_list_prim_u_8_strict *storage_path);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_init_settings_storage(struct wire_cst_list_prim_u_8_strict *storage_path);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_init_with_logging(struct wire_cst_list_prim_u_8_strict *log_directory);

void frbgen_nightshade_bridge_wire__crate__api__api_invalidate_discovery_cache(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_is_device_connected(int64_t port_,
                                                                        int32_t device_type,
                                                                        struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_is_heartbeat_active(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *device_id);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_is_phd2_running(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_is_plate_solver_available(void);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_is_qhy_discovery_enabled(void);

void frbgen_nightshade_bridge_wire__crate__api__api_launch_phd2(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_list_log_files(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_load_profile(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *profile_id);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_park(int64_t port_,
                                                               struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_pulse_guide(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id,
                                                                      struct wire_cst_list_prim_u_8_strict *direction,
                                                                      int32_t duration_ms);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_set_tracking(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *device_id,
                                                                       uint8_t enabled);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_slew_to_coordinates(int64_t port_,
                                                                              struct wire_cst_list_prim_u_8_strict *device_id,
                                                                              double ra,
                                                                              double dec);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_sync_to_coordinates(int64_t port_,
                                                                              struct wire_cst_list_prim_u_8_strict *device_id,
                                                                              double ra,
                                                                              double dec);

void frbgen_nightshade_bridge_wire__crate__api__api_mount_unpark(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_clear_calibration(int64_t port_,
                                                                           struct wire_cst_list_prim_u_8_strict *which);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_connect(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *host,
                                                                 uint16_t *port);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_deselect_star(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_disconnect(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_dither(int64_t port_,
                                                                double amount,
                                                                uint8_t ra_only,
                                                                double settle_pixels,
                                                                double settle_time,
                                                                double settle_timeout);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_find_star(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_flip_calibration(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_algo_param(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *axis,
                                                                        struct wire_cst_list_prim_u_8_strict *name);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_algo_param_names(int64_t port_,
                                                                              struct wire_cst_list_prim_u_8_strict *axis);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_all_algo_params(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *axis);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_calibration_data(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_exposure(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_lock_position(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_profile(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_star_image(int64_t port_,
                                                                        uint32_t size);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_status(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_loop(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_algo_param(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *axis,
                                                                        struct wire_cst_list_prim_u_8_strict *name,
                                                                        double value);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_exposure(int64_t port_,
                                                                      uint32_t exposure_ms);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_lock_position(int64_t port_,
                                                                           double x,
                                                                           double y,
                                                                           bool exact);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_paused(int64_t port_, bool paused);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_start_guiding(int64_t port_,
                                                                       double settle_pixels,
                                                                       double settle_time,
                                                                       double settle_timeout);

void frbgen_nightshade_bridge_wire__crate__api__api_phd2_stop_guiding(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_plate_solve_blind(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *file_path);

void frbgen_nightshade_bridge_wire__crate__api__api_plate_solve_near(int64_t port_,
                                                                     struct wire_cst_list_prim_u_8_strict *file_path,
                                                                     double hint_ra,
                                                                     double hint_dec,
                                                                     double search_radius);

void frbgen_nightshade_bridge_wire__crate__api__api_read_fits_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path);

void frbgen_nightshade_bridge_wire__crate__api__api_read_log_file(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *path);

void frbgen_nightshade_bridge_wire__crate__api__api_read_xisf_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path);

void frbgen_nightshade_bridge_wire__crate__api__api_rotator_halt(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_rotator_move_relative(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id,
                                                                          double delta);

void frbgen_nightshade_bridge_wire__crate__api__api_rotator_move_to(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id,
                                                                    double angle);

void frbgen_nightshade_bridge_wire__crate__api__api_run_autofocus(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *device_id,
                                                                  struct wire_cst_list_prim_u_8_strict *camera_id,
                                                                  struct wire_cst_autofocus_config_api *config);

void frbgen_nightshade_bridge_wire__crate__api__api_run_indi_autofocus(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *camera_id,
                                                                       struct wire_cst_list_prim_u_8_strict *focuser_id,
                                                                       struct wire_cst_indi_autofocus_config_api *config);

void frbgen_nightshade_bridge_wire__crate__api__api_save_fits_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path,
                                                                   uint32_t width,
                                                                   uint32_t height,
                                                                   struct wire_cst_list_prim_u_16_loose *data,
                                                                   struct wire_cst_fits_write_header *header_data);

void frbgen_nightshade_bridge_wire__crate__api__api_save_jpeg_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path,
                                                                   uint32_t width,
                                                                   uint32_t height,
                                                                   struct wire_cst_list_prim_u_16_loose *data,
                                                                   uint8_t quality);

void frbgen_nightshade_bridge_wire__crate__api__api_save_png_file(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *file_path,
                                                                  uint32_t width,
                                                                  uint32_t height,
                                                                  struct wire_cst_list_prim_u_16_loose *data);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_save_profile(struct wire_cst_equipment_profile *profile);

void frbgen_nightshade_bridge_wire__crate__api__api_save_tiff_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path,
                                                                   uint32_t width,
                                                                   uint32_t height,
                                                                   struct wire_cst_list_prim_u_16_loose *data);

void frbgen_nightshade_bridge_wire__crate__api__api_save_xisf_file(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *file_path,
                                                                   uint32_t width,
                                                                   uint32_t height,
                                                                   struct wire_cst_list_prim_u_16_loose *data,
                                                                   struct wire_cst_list_record_string_string *properties);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_clear_checkpoint(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_get_checkpoint_info(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_get_state(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_has_checkpoint(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_load(int64_t port_,
                                                                   struct wire_cst_sequence_definition_api *definition);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_load_json(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *json);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_pause(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_reset(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_resume(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_resume_from_checkpoint(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_save_checkpoint(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_checkpoint_dir(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *path);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_devices(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *camera_id,
                                                                          struct wire_cst_list_prim_u_8_strict *mount_id,
                                                                          struct wire_cst_list_prim_u_8_strict *focuser_id,
                                                                          struct wire_cst_list_prim_u_8_strict *filterwheel_id,
                                                                          struct wire_cst_list_prim_u_8_strict *rotator_id,
                                                                          struct wire_cst_list_String *filter_names);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_simulation_mode(int64_t port_,
                                                                                  bool enabled);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_skip(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_start(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_stop(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_sequencer_subscribe_events(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__api_set_camera_binning(int64_t port_,
                                                                       struct wire_cst_list_prim_u_8_strict *device_id,
                                                                       int32_t bin_x,
                                                                       int32_t bin_y);

void frbgen_nightshade_bridge_wire__crate__api__api_set_camera_cooler(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id,
                                                                      uint8_t enabled,
                                                                      double *target_temp);

void frbgen_nightshade_bridge_wire__crate__api__api_set_camera_gain(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id,
                                                                    int32_t gain);

void frbgen_nightshade_bridge_wire__crate__api__api_set_camera_offset(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id,
                                                                      int32_t offset);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_set_location(struct wire_cst_observer_location *location);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_set_qhy_discovery_enabled(bool enabled);

void frbgen_nightshade_bridge_wire__crate__api__api_start_device_heartbeat(int64_t port_,
                                                                           int32_t device_type,
                                                                           struct wire_cst_list_prim_u_8_strict *device_id,
                                                                           uint64_t interval_ms);

void frbgen_nightshade_bridge_wire__crate__api__api_start_device_heartbeat_with_config(int64_t port_,
                                                                                       struct wire_cst_list_prim_u_8_strict *device_id,
                                                                                       uint64_t interval_secs,
                                                                                       uint32_t failure_threshold,
                                                                                       bool auto_reconnect,
                                                                                       uint32_t max_reconnect_attempts);

void frbgen_nightshade_bridge_wire__crate__api__api_start_polar_alignment(int64_t port_,
                                                                          double exposure_time,
                                                                          double step_size,
                                                                          int32_t binning,
                                                                          bool is_north,
                                                                          bool manual_rotation,
                                                                          bool rotate_east);

void frbgen_nightshade_bridge_wire__crate__api__api_start_session(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *target_name,
                                                                  double *ra,
                                                                  double *dec);

void frbgen_nightshade_bridge_wire__crate__api__api_stop_device_heartbeat(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__api_stop_polar_alignment(int64_t port_);

WireSyncRust2DartDco frbgen_nightshade_bridge_wire__crate__api__api_update_settings(struct wire_cst_app_settings *settings);

void frbgen_nightshade_bridge_wire__crate__api__cancel_exposure(int64_t port_,
                                                                struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__connect_alpaca_device(int64_t port_,
                                                                                          int32_t device_type,
                                                                                          struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_camera(int64_t port_,
                                                                                        struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_focuser(int64_t port_,
                                                                                         struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_mount(int64_t port_,
                                                                                       struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__disconnect_alpaca_device(int64_t port_,
                                                                                             struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__filter_wheel_get_config(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__filter_wheel_get_position(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__filter_wheel_set_position(int64_t port_,
                                                                          struct wire_cst_list_prim_u_8_strict *device_id,
                                                                          int32_t position);

void frbgen_nightshade_bridge_wire__crate__api__focuser_get_details(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__focuser_get_position(int64_t port_,
                                                                     struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__focuser_get_temp(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__focuser_halt(int64_t port_,
                                                             struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__focuser_move_abs(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id,
                                                                 int32_t position);

void frbgen_nightshade_bridge_wire__crate__api__focuser_move_rel(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id,
                                                                 int32_t steps);

void frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__get_alpaca_client(int64_t port_,
                                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_camera_temp(int64_t port_,
                                                                                         struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_focuser_position(int64_t port_,
                                                                                              struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_mount_coords(int64_t port_,
                                                                                          struct wire_cst_list_prim_u_8_strict *prog_id);

void frbgen_nightshade_bridge_wire__crate__api__get_camera_status(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__get_last_image(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__indi_autofocus_config_api_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__is_connected(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_abort(int64_t port_,
                                                            struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_get_coordinates(int64_t port_,
                                                                      struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_get_status(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_get_tracking_rate(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_move_axis(int64_t port_,
                                                                struct wire_cst_list_prim_u_8_strict *device_id,
                                                                int32_t axis,
                                                                double rate);

void frbgen_nightshade_bridge_wire__crate__api__mount_park(int64_t port_,
                                                           struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__mount_pulse_guide(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *device_id,
                                                                  struct wire_cst_list_prim_u_8_strict *direction,
                                                                  uint32_t duration_ms);

void frbgen_nightshade_bridge_wire__crate__api__mount_set_tracking(int64_t port_,
                                                                   struct wire_cst_list_prim_u_8_strict *device_id,
                                                                   uint8_t enabled);

void frbgen_nightshade_bridge_wire__crate__api__mount_set_tracking_rate(int64_t port_,
                                                                        struct wire_cst_list_prim_u_8_strict *device_id,
                                                                        int32_t rate);

void frbgen_nightshade_bridge_wire__crate__api__mount_slew(int64_t port_,
                                                           struct wire_cst_list_prim_u_8_strict *device_id,
                                                           double ra,
                                                           double dec);

void frbgen_nightshade_bridge_wire__crate__api__mount_sync(int64_t port_,
                                                           struct wire_cst_list_prim_u_8_strict *device_id,
                                                           double ra,
                                                           double dec);

void frbgen_nightshade_bridge_wire__crate__api__mount_unpark(int64_t port_,
                                                             struct wire_cst_list_prim_u_8_strict *device_id);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__move_ascom_focuser(int64_t port_,
                                                                                      struct wire_cst_list_prim_u_8_strict *prog_id,
                                                                                      int32_t position);

void frbgen_nightshade_bridge_wire__crate__api__set_camera_cooler(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *device_id,
                                                                  uint8_t enabled,
                                                                  double *target_temp);

void frbgen_nightshade_bridge_wire__crate__api__set_camera_gain(int64_t port_,
                                                                struct wire_cst_list_prim_u_8_strict *device_id,
                                                                int32_t gain);

void frbgen_nightshade_bridge_wire__crate__api__set_camera_offset(int64_t port_,
                                                                  struct wire_cst_list_prim_u_8_strict *device_id,
                                                                  int32_t offset);

void frbgen_nightshade_bridge_wire__crate__api__simulated_camera_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__simulated_filter_wheel_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__simulated_focuser_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__simulated_mount_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__simulated_rotator_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__ascom_connections__slew_ascom_mount(int64_t port_,
                                                                                    struct wire_cst_list_prim_u_8_strict *prog_id,
                                                                                    double ra,
                                                                                    double dec);

void frbgen_nightshade_bridge_wire__crate__api__star_detection_config_api_default(int64_t port_);

void frbgen_nightshade_bridge_wire__crate__api__start_exposure(int64_t port_,
                                                               struct wire_cst_list_prim_u_8_strict *device_id,
                                                               double duration_secs,
                                                               int32_t gain,
                                                               int32_t offset,
                                                               int32_t bin_x,
                                                               int32_t bin_y);

void frbgen_nightshade_bridge_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient(const void *ptr);

void frbgen_nightshade_bridge_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient(const void *ptr);

uintptr_t *frbgen_nightshade_bridge_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient(uintptr_t value);

struct wire_cst_app_settings *frbgen_nightshade_bridge_cst_new_box_autoadd_app_settings(void);

struct wire_cst_autofocus_config_api *frbgen_nightshade_bridge_cst_new_box_autoadd_autofocus_config_api(void);

bool *frbgen_nightshade_bridge_cst_new_box_autoadd_bool(bool value);

int32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_calibrator_state(int32_t value);

struct wire_cst_camera_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_camera_capabilities(void);

struct wire_cst_captured_image_result *frbgen_nightshade_bridge_cst_new_box_autoadd_captured_image_result(void);

struct wire_cst_checkpoint_info_api *frbgen_nightshade_bridge_cst_new_box_autoadd_checkpoint_info_api(void);

struct wire_cst_cover_calibrator_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_cover_calibrator_capabilities(void);

int32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_cover_state(int32_t value);

struct wire_cst_dome_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_dome_capabilities(void);

struct wire_cst_equipment_event *frbgen_nightshade_bridge_cst_new_box_autoadd_equipment_event(void);

struct wire_cst_equipment_profile *frbgen_nightshade_bridge_cst_new_box_autoadd_equipment_profile(void);

double *frbgen_nightshade_bridge_cst_new_box_autoadd_f_64(double value);

struct wire_cst_filter_wheel_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_filter_wheel_capabilities(void);

struct wire_cst_fits_write_header *frbgen_nightshade_bridge_cst_new_box_autoadd_fits_write_header(void);

struct wire_cst_focuser_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_focuser_capabilities(void);

struct wire_cst_guiding_event *frbgen_nightshade_bridge_cst_new_box_autoadd_guiding_event(void);

int32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_i_32(int32_t value);

int64_t *frbgen_nightshade_bridge_cst_new_box_autoadd_i_64(int64_t value);

struct wire_cst_imaging_event *frbgen_nightshade_bridge_cst_new_box_autoadd_imaging_event(void);

struct wire_cst_indi_autofocus_config_api *frbgen_nightshade_bridge_cst_new_box_autoadd_indi_autofocus_config_api(void);

struct wire_cst_mount_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_mount_capabilities(void);

struct wire_cst_observer_location *frbgen_nightshade_bridge_cst_new_box_autoadd_observer_location(void);

struct wire_cst_polar_alignment_event *frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_event(void);

struct wire_cst_polar_alignment_image_event *frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_image_event(void);

struct wire_cst_polar_alignment_status *frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_status(void);

struct wire_cst_rotator_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_rotator_capabilities(void);

struct wire_cst_safety_event *frbgen_nightshade_bridge_cst_new_box_autoadd_safety_event(void);

struct wire_cst_safety_monitor_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_safety_monitor_capabilities(void);

struct wire_cst_sequence_definition_api *frbgen_nightshade_bridge_cst_new_box_autoadd_sequence_definition_api(void);

struct wire_cst_sequencer_event *frbgen_nightshade_bridge_cst_new_box_autoadd_sequencer_event(void);

int32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_shutter_status(int32_t value);

struct wire_cst_star_detection_config_api *frbgen_nightshade_bridge_cst_new_box_autoadd_star_detection_config_api(void);

struct wire_cst_stretch_params_api *frbgen_nightshade_bridge_cst_new_box_autoadd_stretch_params_api(void);

struct wire_cst_switch_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_switch_capabilities(void);

struct wire_cst_system_event *frbgen_nightshade_bridge_cst_new_box_autoadd_system_event(void);

int32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_tracking_rate(int32_t value);

uint16_t *frbgen_nightshade_bridge_cst_new_box_autoadd_u_16(uint16_t value);

uint32_t *frbgen_nightshade_bridge_cst_new_box_autoadd_u_32(uint32_t value);

uint64_t *frbgen_nightshade_bridge_cst_new_box_autoadd_u_64(uint64_t value);

struct wire_cst_weather_capabilities *frbgen_nightshade_bridge_cst_new_box_autoadd_weather_capabilities(void);

struct wire_cst_list_String *frbgen_nightshade_bridge_cst_new_list_String(int32_t len);

struct wire_cst_list_detected_star_info *frbgen_nightshade_bridge_cst_new_list_detected_star_info(int32_t len);

struct wire_cst_list_device_info *frbgen_nightshade_bridge_cst_new_list_device_info(int32_t len);

struct wire_cst_list_equipment_profile *frbgen_nightshade_bridge_cst_new_list_equipment_profile(int32_t len);

struct wire_cst_list_focus_data_point *frbgen_nightshade_bridge_cst_new_list_focus_data_point(int32_t len);

struct wire_cst_list_focus_data_point_api *frbgen_nightshade_bridge_cst_new_list_focus_data_point_api(int32_t len);

struct wire_cst_list_mosaic_panel_result *frbgen_nightshade_bridge_cst_new_list_mosaic_panel_result(int32_t len);

struct wire_cst_list_node_definition_api *frbgen_nightshade_bridge_cst_new_list_node_definition_api(int32_t len);

struct wire_cst_list_phd_2_algo_param *frbgen_nightshade_bridge_cst_new_list_phd_2_algo_param(int32_t len);

struct wire_cst_list_prim_f_32_strict *frbgen_nightshade_bridge_cst_new_list_prim_f_32_strict(int32_t len);

struct wire_cst_list_prim_i_32_strict *frbgen_nightshade_bridge_cst_new_list_prim_i_32_strict(int32_t len);

struct wire_cst_list_prim_u_16_loose *frbgen_nightshade_bridge_cst_new_list_prim_u_16_loose(int32_t len);

struct wire_cst_list_prim_u_16_strict *frbgen_nightshade_bridge_cst_new_list_prim_u_16_strict(int32_t len);

struct wire_cst_list_prim_u_32_strict *frbgen_nightshade_bridge_cst_new_list_prim_u_32_strict(int32_t len);

struct wire_cst_list_prim_u_8_strict *frbgen_nightshade_bridge_cst_new_list_prim_u_8_strict(int32_t len);

struct wire_cst_list_record_string_string *frbgen_nightshade_bridge_cst_new_list_record_string_string(int32_t len);

struct wire_cst_list_switch_info *frbgen_nightshade_bridge_cst_new_list_switch_info(int32_t len);

struct wire_cst_list_tracking_rate *frbgen_nightshade_bridge_cst_new_list_tracking_rate(int32_t len);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_app_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_autofocus_config_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_bool);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_calibrator_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_camera_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_captured_image_result);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_checkpoint_info_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_cover_calibrator_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_cover_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_dome_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_equipment_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_equipment_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_f_64);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_filter_wheel_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_fits_write_header);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_focuser_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_guiding_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_i_32);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_i_64);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_imaging_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_indi_autofocus_config_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_mount_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_observer_location);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_image_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_polar_alignment_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_rotator_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_safety_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_safety_monitor_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_sequence_definition_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_sequencer_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_shutter_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_star_detection_config_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_stretch_params_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_switch_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_system_event);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_tracking_rate);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_u_16);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_u_64);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_box_autoadd_weather_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_String);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_detected_star_info);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_device_info);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_equipment_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_focus_data_point);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_focus_data_point_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_mosaic_panel_result);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_node_definition_api);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_phd_2_algo_param);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_f_32_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_i_32_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_u_16_loose);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_u_16_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_u_32_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_record_string_string);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_switch_info);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_cst_new_list_tracking_rate);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerArcAlpacaClient);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__connect_alpaca_device);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__disconnect_alpaca_device);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__get_alpaca_client);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__alpaca_connections__is_connected);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_apply_stretch);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_auto_stretch_image);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_build_sequence);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_altitude);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_auto_stretch);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_hfr);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_histogram);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_mosaic_area);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_calculate_mosaic_panels);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_camera_cancel_exposure);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_camera_start_exposure);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cancel_autofocus);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_connect_device);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_calibrator_off);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_calibrator_on);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_close_cover);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_brightness);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_calibrator_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_cover_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_max_brightness);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_get_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_halt_cover);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_cover_calibrator_open_cover);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_autofocus_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_center_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_cool_camera_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_delay_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_dither_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_exposure_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_filter_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_loop_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_notification_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_park_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_rotator_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_script_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_slew_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_target_group_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_target_header_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_unpark_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_wait_time_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_create_warm_camera_node);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_debayer_fits_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_debayer_image);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_delete_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_detect_stars_in_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_device_supports_action);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_device_supports_version);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_disconnect_device);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_alpaca_at_address);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_alpaca_devices);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_devices);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_at_address);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_common_hosts);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_localhost);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_discover_indi_network);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_close_shutter);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_get_azimuth);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_get_shutter_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_is_slewing);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_open_shutter);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_park);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_dome_slew_to_azimuth);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_end_session);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_estimate_mosaic_time);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_event_stream);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_export_logs);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_get_names);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_by_name);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_filter_names);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_filterwheel_set_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_focuser_halt);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_focuser_move_relative);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_focuser_move_to);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_generate_filename);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_generate_fits_thumbnail);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_active_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_camera_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_camera_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_connected_devices);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_current_log_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_device_api_version);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_device_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_device_health);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_device_heartbeat_info);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_dome_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_dropped_event_count);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_filterwheel_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_filterwheel_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_focuser_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_focuser_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_heartbeat_config_for_type);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_image_stats);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_last_image);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_last_raw_image_data);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_location);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_log_directory);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_mount_capabilities);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_mount_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_next_frame_number);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_plate_solver_path);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_profiles);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_qhy_discovery_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_rotator_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_session_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_get_version);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_init);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_init_profile_storage);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_init_settings_storage);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_init_with_logging);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_invalidate_discovery_cache);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_is_device_connected);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_is_heartbeat_active);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_is_phd2_running);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_is_plate_solver_available);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_is_qhy_discovery_enabled);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_launch_phd2);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_list_log_files);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_load_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_park);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_pulse_guide);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_set_tracking);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_slew_to_coordinates);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_sync_to_coordinates);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_mount_unpark);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_clear_calibration);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_connect);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_deselect_star);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_disconnect);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_dither);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_find_star);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_flip_calibration);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_algo_param);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_algo_param_names);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_all_algo_params);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_calibration_data);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_exposure);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_lock_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_star_image);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_get_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_loop);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_algo_param);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_exposure);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_lock_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_set_paused);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_start_guiding);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_phd2_stop_guiding);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_plate_solve_blind);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_plate_solve_near);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_read_fits_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_read_log_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_read_xisf_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_rotator_halt);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_rotator_move_relative);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_rotator_move_to);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_run_autofocus);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_run_indi_autofocus);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_fits_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_jpeg_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_png_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_profile);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_tiff_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_save_xisf_file);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_clear_checkpoint);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_get_checkpoint_info);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_get_state);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_has_checkpoint);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_load);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_load_json);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_pause);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_reset);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_resume);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_resume_from_checkpoint);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_save_checkpoint);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_checkpoint_dir);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_devices);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_set_simulation_mode);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_skip);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_start);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_stop);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_sequencer_subscribe_events);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_camera_binning);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_camera_cooler);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_camera_gain);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_camera_offset);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_location);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_set_qhy_discovery_enabled);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_start_device_heartbeat);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_start_device_heartbeat_with_config);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_start_polar_alignment);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_start_session);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_stop_device_heartbeat);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_stop_polar_alignment);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__api_update_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_camera);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_focuser);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__connect_ascom_mount);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_camera_temp);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_focuser_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__get_ascom_mount_coords);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__move_ascom_focuser);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__ascom_connections__slew_ascom_mount);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__cancel_exposure);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__filter_wheel_get_config);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__filter_wheel_get_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__filter_wheel_set_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_get_details);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_get_position);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_get_temp);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_halt);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_move_abs);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__focuser_move_rel);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__get_camera_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__get_last_image);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__indi_autofocus_config_api_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_abort);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_get_coordinates);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_get_status);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_get_tracking_rate);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_move_axis);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_park);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_pulse_guide);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_set_tracking);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_set_tracking_rate);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_slew);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_sync);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__mount_unpark);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__set_camera_cooler);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__set_camera_gain);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__set_camera_offset);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__simulated_camera_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__simulated_filter_wheel_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__simulated_focuser_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__simulated_mount_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__simulated_rotator_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__star_detection_config_api_default);
    dummy_var ^= ((int64_t) (void*) frbgen_nightshade_bridge_wire__crate__api__start_exposure);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
