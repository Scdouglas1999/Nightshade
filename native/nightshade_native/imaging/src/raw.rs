//! RAW image file support via LibRaw FFI
//!
//! Direct FFI bindings to libraw.dll for native X-Trans RGB support.
//! No synthetic Bayer conversion - preserves full X-Trans sharpness!
//!
//! Supports 600+ camera models including Fujifilm X-Trans sensors.

use crate::{ImageData, PixelType};
use std::path::Path;
use std::ffi::{CStr, CString};
use std::os::raw::{c_int, c_uint, c_ushort, c_void, c_char, c_float, c_double};
use image::GenericImageView;

// =============================================================================
// LibRaw FFI Declarations (matching libraw.dll structures and functions)
// =============================================================================

const LIBRAW_SUCCESS: i32 = 0;

// LibRaw image parameters structure
#[repr(C)]
struct libraw_iparams_t {
    make: [c_char; 64],
    model: [c_char; 64],
    software: [c_char; 64],
    raw_count: c_uint,
    dng_version: c_uint,
    is_foveon: c_uint,
    colors: c_int,
    filters: c_uint,
    cdesc: [c_char; 5],
}

// LibRaw other parameters (exposure, etc.)
#[repr(C)]
struct libraw_imgother_t {
    iso_speed: c_float,
    shutter: c_float,
    aperture: c_float,
    focal_len: c_float,
    timestamp: c_uint,
    shot_order: c_uint,
    gpsdata: [c_uint; 32],
    desc: [c_char; 512],
    artist: [c_char; 64],
}

// LibRaw image sizes structure
#[repr(C)]
struct libraw_image_sizes_t {
    raw_height: c_ushort,
    raw_width: c_ushort,
    height: c_ushort,
    width: c_ushort,
    top_margin: c_ushort,
    left_margin: c_ushort,
    iheight: c_ushort,
    iwidth: c_ushort,
    raw_pitch: c_uint,
    pixel_aspect: f64,
    flip: c_int,
}

// LibRaw main data structure (partial - only what we need)
#[repr(C)]
struct libraw_data_t {
    image: *mut c_void,
    sizes: libraw_image_sizes_t,
    idata: libraw_iparams_t,
    other: libraw_imgother_t,
    // ... many other fields we don't need
}

#[repr(C)]
struct libraw_processed_image_t {
    type_: c_ushort,
    height: c_ushort,
    width: c_ushort,
    colors: c_ushort,
    bits: c_ushort,
    data_size: c_uint,
    // data follows immediately after
}

#[repr(C)]
struct libraw_output_params_t {
    greybox: [c_uint; 4],
    cropbox: [c_uint; 4],
    aber: [c_double; 4],
    gamm: [c_double; 6],
    user_mul: [c_float; 4],
    shot_select: c_uint,
    bright: c_float,
    threshold: c_float,
    half_size: c_int,
    four_color_rgb: c_int,
    highlight: c_int,
    use_auto_wb: c_int,
    use_camera_wb: c_int,
    use_camera_matrix: c_int,
    output_color: c_int,
    output_profile: *mut c_char,
    camera_profile: *mut c_char,
    bad_pixels: *mut c_char,
    dark_frame: *mut c_char,
    output_bps: c_int,
    output_tiff: c_int,
    user_flip: c_int,
    user_qual: c_int,
    user_black: c_int,
    user_cblack: [c_int; 4],
    user_sat: c_int,
    med_passes: c_int,
    auto_bright_thr: c_float,
    adjust_maximum_thr: c_float,
    no_auto_bright: c_int,
    use_fuji_rotate: c_int,
    green_matching: c_int,
    dcb_iterations: c_int,
    dcb_enhance_fl: c_int,
    fbdd_noiserd: c_int,
    exp_correc: c_int,
    exp_shift: c_float,
    exp_preser: c_float,
    use_camera_wb_prior: c_int,
    auto_bright_thr_default: c_float,
}

// Platform-specific library name:
// - Windows: libraw.dll (linked as "libraw")
// - Linux/macOS: libraw.so/dylib (linked as "raw" since lib prefix is automatic)
#[cfg_attr(target_os = "windows", link(name = "libraw"))]
#[cfg_attr(not(target_os = "windows"), link(name = "raw"))]
extern "C" {
    fn libraw_init(flags: c_uint) -> *mut libraw_data_t;
    fn libraw_open_file(data: *mut libraw_data_t, path: *const c_char) -> c_int;
    fn libraw_unpack(data: *mut libraw_data_t) -> c_int;
    fn libraw_dcraw_process(data: *mut libraw_data_t) -> c_int;
    fn libraw_dcraw_make_mem_image(data: *mut libraw_data_t, errcode: *mut c_int) -> *mut libraw_processed_image_t;
    fn libraw_dcraw_make_mem_thumb(data: *mut libraw_data_t, errcode: *mut c_int) -> *mut libraw_processed_image_t;
    fn libraw_dcraw_clear_mem(image: *mut libraw_processed_image_t);
    fn libraw_close(data: *mut libraw_data_t);
    fn libraw_strerror(errorcode: c_int) -> *const c_char;
    fn libraw_unpack_thumb(data: *mut libraw_data_t) -> c_int;
}

/// RAW file error types
#[derive(Debug)]
pub enum RawError {
    Io(std::io::Error),
    LibRawError(String),
    UnsupportedFormat(String),
    InvalidPath(String),
    NullPointer,
}

impl std::fmt::Display for RawError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RawError::Io(e) => write!(f, "IO error: {}", e),
            RawError::LibRawError(s) => write!(f, "LibRaw error: {}", s),
            RawError::UnsupportedFormat(s) => write!(f, "Unsupported format: {}", s),
            RawError::InvalidPath(s) => write!(f, "Invalid path: {}", s),
            RawError::NullPointer => write!(f, "Null pointer from LibRaw"),
        }
    }
}

impl std::error::Error for RawError {}

impl From<std::io::Error> for RawError {
    fn from(e: std::io::Error) -> Self {
        RawError::Io(e)
    }
}

/// RAW file metadata
#[derive(Debug, Clone, Default)]
pub struct RawMetadata {
    pub camera_make: String,
    pub camera_model: String,
    pub iso_speed: Option<f32>,
    pub shutter_speed: Option<f32>,
    pub aperture: Option<f32>,
    pub focal_length: Option<f32>,
    pub timestamp: Option<i64>,
    pub color_desc: String,
    pub is_xtrans: bool,
    pub raw_width: u32,
    pub raw_height: u32,
}

/// White Balance Mode
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum WhiteBalanceMode {
    Camera,
    Auto,
    Custom(f32, f32, f32, f32), // R, G1, B, G2 multipliers
}

/// Output Color Space
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColorSpace {
    Raw,
    SRGB,
    AdobeRGB,
    WideGamut,
    ProPhotoRGB,
    XYZ,
    ACES,
}

/// Demosaic Algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DemosaicAlgorithm {
    Linear,
    VNG,
    PPG,
    AHD,
    DCB,
    DHT, // Best for X-Trans
    AAHD,
}

/// Highlight Recovery Mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HighlightMode {
    Clip,
    Unclip,
    Blend,
    Rebuild(u32), // 3-9
}

/// RAW Processing Parameters
#[derive(Debug, Clone)]
pub struct RawProcessingParams {
    pub white_balance: WhiteBalanceMode,
    pub output_color: ColorSpace,
    pub output_bps: u32, // 8 or 16
    pub demosaic: DemosaicAlgorithm,
    pub highlight_mode: HighlightMode,
    pub brightness: f32,
    pub user_sat: Option<i32>,
    pub gamma: Option<(f64, f64)>, // power, slope
    pub auto_bright: bool,
    pub half_size: bool,
    pub bad_pixels_path: Option<std::path::PathBuf>,
    pub dark_frame_path: Option<std::path::PathBuf>,
    pub chromatic_aberration: Option<(f64, f64)>, // (red_scale, blue_scale)
    pub max_memory_mb: Option<usize>,
}

impl Default for RawProcessingParams {
    fn default() -> Self {
        Self {
            white_balance: WhiteBalanceMode::Camera,
            output_color: ColorSpace::SRGB,
            output_bps: 8,
            demosaic: DemosaicAlgorithm::DHT, // Good default for X-Trans
            highlight_mode: HighlightMode::Clip,
            brightness: 1.0,
            user_sat: None,
            gamma: None, // Use default sRGB gamma
            auto_bright: false, // Disable auto brightness for consistency
            half_size: false,
            bad_pixels_path: None,
            dark_frame_path: None,
            chromatic_aberration: None,
            max_memory_mb: None,
        }
    }
}

/// Read a RAW file with native X-Trans support
/// 
/// Returns 3-channel RGB image data with NO synthetic Bayer conversion!
/// Read a RAW file with native X-Trans support
/// 
/// Returns 3-channel RGB image data with NO synthetic Bayer conversion!
pub fn read_raw(path: &Path, params: Option<&RawProcessingParams>) -> Result<(ImageData, RawMetadata), RawError> {
    let default_params = RawProcessingParams::default();
    let params = params.unwrap_or(&default_params);
    // Validate path
    let path_str = path.to_str()
        .ok_or_else(|| RawError::InvalidPath("Path contains invalid UTF-8".to_string()))?;
    
    if !path.exists() {
        return Err(RawError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "File not found",
        )));
    }

    tracing::info!("Reading RAW file: {}", path_str);

    // SAFETY: Calling FFI functions from LibRaw C library. The processor lifecycle is managed
    // carefully: init returns a valid pointer or null (checked), and we ensure cleanup via
    // libraw_close in all code paths (error and success).
    unsafe {
        // Initialize LibRaw processor
        let processor = libraw_init(0);
        if processor.is_null() {
            return Err(RawError::NullPointer);
        }

        // Open file
        let c_path = CString::new(path_str).map_err(|_| {
            RawError::InvalidPath("Path contains null bytes".to_string())
        })?;
        
        let ret = libraw_open_file(processor, c_path.as_ptr());
        if ret != LIBRAW_SUCCESS {
            let err_msg = get_error_string(ret);
            libraw_close(processor);
            return Err(RawError::LibRawError(format!(
                "libraw_open_file failed: {}",
                err_msg
            )));
        }

        // Access the data structure to extract metadata
        let data = &*processor;
        
        // Extract camera info
        let camera_make = CStr::from_ptr(data.idata.make.as_ptr())
            .to_string_lossy()
            .trim()
            .to_string();
        
        let camera_model = CStr::from_ptr(data.idata.model.as_ptr())
            .to_string_lossy()
            .trim()
            .to_string();
        
        let color_desc = CStr::from_ptr(data.idata.cdesc.as_ptr())
            .to_string_lossy()
            .to_string();
        
        // Detect X-Trans (filters == 9 indicates X-Trans)
        let is_xtrans = data.idata.filters == 9;
        
        // Extract exposure metadata
        let iso_speed = if data.other.iso_speed > 0.0 {
            Some(data.other.iso_speed)
        } else {
            None
        };
        
        let shutter_speed = if data.other.shutter > 0.0 {
            Some(data.other.shutter)
        } else {
            None
        };
        
        let aperture = if data.other.aperture > 0.0 {
            Some(data.other.aperture)
        } else {
            None
        };
        
        let focal_length = if data.other.focal_len > 0.0 {
            Some(data.other.focal_len)
        } else {
            None
        };
        
        let timestamp = if data.other.timestamp > 0 {
            Some(data.other.timestamp as i64)
        } else {
            None
        };
        // We scan for the sRGB gamma signature: 0.45045 (1/2.222) and 4.5
        let mut params_ptr: *mut libraw_output_params_t = std::ptr::null_mut();
        
        // Keep CStrings alive until processing is done
        let mut _bad_pixels_c_str: Option<CString> = None;
        let mut _dark_frame_c_str: Option<CString> = None;
        
        let start_ptr = (processor as *mut u8).add(512); // Skip header
        let end_ptr = (processor as *mut u8).add(32768); // Search 32KB
        
        let mut ptr = start_ptr;
        while ptr < end_ptr {
            let p = ptr as *mut libraw_output_params_t;
            // Check signature
            if ((*p).gamm[0] - 0.45045).abs() < 0.001 && 
               ((*p).gamm[1] - 4.5).abs() < 0.001 &&
               (*p).output_color == 1 {
                params_ptr = p;
                break;
            }
            ptr = ptr.add(8); // 8-byte alignment
        }
        
        if !params_ptr.is_null() {
            tracing::info!("Found LibRaw output params at offset {}", ptr.offset_from(processor as *mut u8));
            let out = &mut *params_ptr;
            
            // 1. White Balance
            match params.white_balance {
                WhiteBalanceMode::Camera => {
                    out.use_camera_wb = 1;
                    out.use_auto_wb = 0;
                },
                WhiteBalanceMode::Auto => {
                    out.use_camera_wb = 0;
                    out.use_auto_wb = 1;
                },
                WhiteBalanceMode::Custom(r, g1, b, g2) => {
                    out.use_camera_wb = 0;
                    out.use_auto_wb = 0;
                    out.user_mul[0] = r;
                    out.user_mul[1] = g1;
                    out.user_mul[2] = b;
                    out.user_mul[3] = g2;
                }
            }
            
            // 2. Color Space
            out.output_color = match params.output_color {
                ColorSpace::Raw => 0,
                ColorSpace::SRGB => 1,
                ColorSpace::AdobeRGB => 2,
                ColorSpace::WideGamut => 3,
                ColorSpace::ProPhotoRGB => 4,
                ColorSpace::XYZ => 5,
                ColorSpace::ACES => 6,
            };
            
            // 3. Bit Depth
            out.output_bps = params.output_bps as c_int;
            
            // 4. Demosaic Algorithm
            out.user_qual = match params.demosaic {
                DemosaicAlgorithm::Linear => 0,
                DemosaicAlgorithm::VNG => 1,
                DemosaicAlgorithm::PPG => 2,
                DemosaicAlgorithm::AHD => 3,
                DemosaicAlgorithm::DCB => 4,
                DemosaicAlgorithm::DHT => 11,
                DemosaicAlgorithm::AAHD => 12,
            };
            
            // 5. Highlight Mode
            out.highlight = match params.highlight_mode {
                HighlightMode::Clip => 0,
                HighlightMode::Unclip => 1,
                HighlightMode::Blend => 2,
                HighlightMode::Rebuild(n) => (3 + n).min(9) as c_int,
            };
            
            // 6. Brightness / Gamma
            out.bright = params.brightness;
            out.no_auto_bright = if params.auto_bright { 0 } else { 1 };
            
            if let Some((power, slope)) = params.gamma {
                out.gamm[0] = 1.0 / power;
                out.gamm[1] = slope;
            }
            
            if let Some(sat) = params.user_sat {
                out.user_sat = sat;
            }
            
            out.half_size = if params.half_size { 1 } else { 0 };
            
            // 7. Bad Pixels
            if let Some(path) = &params.bad_pixels_path {
                if let Some(s) = path.to_str() {
                     if let Ok(c_str) = CString::new(s) {
                         out.bad_pixels = c_str.as_ptr() as *mut c_char;
                         _bad_pixels_c_str = Some(c_str);
                     }
                }
            }
            
            // 8. Dark Frame
            if let Some(path) = &params.dark_frame_path {
                if let Some(s) = path.to_str() {
                     if let Ok(c_str) = CString::new(s) {
                         out.dark_frame = c_str.as_ptr() as *mut c_char;
                         _dark_frame_c_str = Some(c_str);
                     }
                }
            }
            
            // 9. Chromatic Aberration
            if let Some((r, b)) = params.chromatic_aberration {
                out.aber[0] = r;
                out.aber[2] = b;
                out.aber[1] = 1.0;
                out.aber[3] = 1.0;
            }
            
        } else {
            tracing::warn!("Could not locate LibRaw output params in memory! Using defaults.");
        }

        let metadata = RawMetadata {
            camera_make,
            camera_model,
            iso_speed,
            shutter_speed,
            aperture,
            focal_length,
            timestamp,
            color_desc,
            is_xtrans,
            raw_width: data.sizes.raw_width as u32,
            raw_height: data.sizes.raw_height as u32,
        };

        // Unpack the RAW data
        let ret = libraw_unpack(processor);
        if ret != LIBRAW_SUCCESS {
            let err_msg = get_error_string(ret);
            libraw_close(processor);
            return Err(RawError::LibRawError(format!(
                "libraw_unpack failed: {}",
                err_msg
            )));
        }

        // Process to RGB (LibRaw automatically handles X-Trans demosaicing!)
        let ret = libraw_dcraw_process(processor);
        if ret != LIBRAW_SUCCESS {
            let err_msg = get_error_string(ret);
            libraw_close(processor);
            return Err(RawError::LibRawError(format!(
                "libraw_dcraw_process failed: {}",
                err_msg
            )));
        }

        // Get processed RGB image
        let mut errcode = 0;
        let processed_image = libraw_dcraw_make_mem_image(processor, &mut errcode);
        if processed_image.is_null() {
            libraw_close(processor);
            return Err(RawError::LibRawError(format!(
                "libraw_dcraw_make_mem_image failed: {}",
                errcode
            )));
        }

        // Extract image data from the processed image structure
        let img = &*processed_image;
        let img_width = img.width as u32;
        let img_height = img.height as u32;
        let channels = img.colors as u32;  // Should be 3 for RGB
        let bits = img.bits as u32;

        tracing::info!(
            "Processed: {}x{}, {} channels, {} bits - Native RGB!",
            img_width, img_height, channels, bits
        );

        // Calculate data size
        let pixel_count = (img_width * img_height * channels) as usize;
        
        // Get pointer to image data (located right after the struct header)
        let header_size = std::mem::size_of::<libraw_processed_image_t>();
        let data_ptr = (processed_image as *const u8).add(header_size);

        // Copy RGB data
        let mut rgb_data = vec![0u16; pixel_count];
        
        if bits == 16 {
            // 16-bit data - direct copy
            std::ptr::copy_nonoverlapping(
                data_ptr as *const u16,
                rgb_data.as_mut_ptr(),
                pixel_count
            );
        } else if bits == 8 {
            // 8-bit data - scale to 16-bit
            for i in 0..pixel_count {
                let val = *data_ptr.add(i);
                rgb_data[i] = (val as u16) * 257; // Scale 0-255 to 0-65535
            }
        } else {
            libraw_dcraw_clear_mem(processed_image);
            libraw_close(processor);
            return Err(RawError::UnsupportedFormat(format!("Unsupported bit depth: {}", bits)));
        }

        // Convert to byte array for ImageData
        let data: Vec<u8> = rgb_data.iter()
            .flat_map(|&val| val.to_le_bytes())
            .collect();

        // Cleanup
        libraw_dcraw_clear_mem(processed_image);
        libraw_close(processor);

        // Create ImageData with 3 channels (native RGB!)
        let image = ImageData {
            width: img_width,
            height: img_height,
            channels,  // 3 for RGB - NO synthetic Bayer conversion!
            pixel_type: PixelType::U16,
            data,
        };

        Ok((image, metadata))
    }
}

/// Get LibRaw error string
/// SAFETY: Calls libraw_strerror FFI function which returns a static string pointer.
/// The pointer is checked for null and converted to a Rust String.
unsafe fn get_error_string(code: c_int) -> String {
    let ptr = libraw_strerror(code);
    if ptr.is_null() {
        format!("Unknown error code: {}", code)
    } else {
        CStr::from_ptr(ptr)
            .to_string_lossy()
            .to_string()
    }
}

/// Extract thumbnail from RAW file (Fast Preview)
pub fn extract_thumbnail(path: &Path) -> Result<ImageData, RawError> {
    // Validate path
    let path_str = path.to_str()
        .ok_or_else(|| RawError::InvalidPath("Path contains invalid UTF-8".to_string()))?;
    
    if !path.exists() {
        return Err(RawError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "File not found",
        )));
    }

    // SAFETY: Calling FFI functions from LibRaw C library. The processor lifecycle is managed
    // carefully: init returns a valid pointer or null (checked), and we ensure cleanup via
    // libraw_close in all code paths (error and success).
    unsafe {
        // Initialize LibRaw processor
        let processor = libraw_init(0);
        if processor.is_null() {
            return Err(RawError::NullPointer);
        }

        // Open file
        let c_path = CString::new(path_str).map_err(|_| {
            RawError::InvalidPath("Path contains null bytes".to_string())
        })?;
        
        let ret = libraw_open_file(processor, c_path.as_ptr());
        if ret != LIBRAW_SUCCESS {
            libraw_close(processor);
            return Err(RawError::LibRawError("Failed to open file".to_string()));
        }

        // Unpack thumbnail
        let ret = libraw_unpack_thumb(processor);
        if ret != LIBRAW_SUCCESS {
            libraw_close(processor);
            return Err(RawError::LibRawError("Failed to unpack thumbnail".to_string()));
        }

        // Make memory thumbnail
        let mut err = 0;
        let processed = libraw_dcraw_make_mem_thumb(processor, &mut err);
        
        if processed.is_null() || err != LIBRAW_SUCCESS {
            libraw_close(processor);
            return Err(RawError::LibRawError(format!("Failed to create memory thumbnail: {}", err)));
        }

        // Convert to ImageData
        let width = (*processed).width as u32;
        let height = (*processed).height as u32;
        let colors = (*processed).colors as u32;
        let bits = (*processed).bits as u32;
        let data_size = (*processed).data_size as usize;
        
        let data_ptr = (processed as *mut u8).add(std::mem::size_of::<libraw_processed_image_t>());
        let data_slice = std::slice::from_raw_parts(data_ptr, data_size);
        
        // Thumbnails are usually JPEG (compressed) or RGB bitmap
        let type_ = (*processed).type_;
        
        let image = if type_ == 1 {
            // Bitmap (RGB)
            let mut pixels = Vec::with_capacity(data_size);
            pixels.extend_from_slice(data_slice);
            
            ImageData {
                width,
                height,
                channels: colors,
                pixel_type: if bits == 16 { PixelType::U16 } else { PixelType::U8 },
                data: pixels,
            }
        } else if type_ == 2 || type_ == 4 { // JPEG or KODAK_THUMB (usually JPEG)
            // Decode JPEG from memory
            let img = image::load_from_memory(data_slice)
                .map_err(|e| RawError::UnsupportedFormat(format!("Failed to decode thumbnail: {}", e)))?;
            
            let (w, h) = img.dimensions();
            let rgba = img.to_rgba8();
            let pixels = rgba.into_raw();
            
            // Convert RGBA to RGB if needed, or keep RGBA
            // ImageData supports 4 channels
            ImageData {
                width: w,
                height: h,
                channels: 4,
                pixel_type: PixelType::U8,
                data: pixels,
            }
        } else {
            // Other format
            libraw_dcraw_clear_mem(processed);
            libraw_close(processor);
            return Err(RawError::UnsupportedFormat(format!("Unsupported thumbnail type: {}", type_)));
        };

        libraw_dcraw_clear_mem(processed);
        libraw_close(processor);
        
        Ok(image)
    }
}

/// Process multiple RAW files in parallel
pub fn process_raw_batch(
    paths: &[std::path::PathBuf],
    params: Option<&RawProcessingParams>,
) -> Vec<Result<(ImageData, RawMetadata), RawError>> {
    use rayon::prelude::*;
    
    paths.par_iter()
        .map(|path| read_raw(path, params))
        .collect()
}

/// Detect if a file is a supported RAW format
pub fn is_raw_file(path: &Path) -> bool {
    if let Some(ext) = path.extension() {
        if let Some(ext_str) = ext.to_str() {
            return matches!(
                ext_str.to_lowercase().as_str(),
                "cr2" | "cr3" | "crw"  // Canon
                | "nef" | "nrw"        // Nikon
                | "arw" | "srf" | "sr2" // Sony
                | "raf"                 // Fujifilm (X-Trans!)
                | "pef" | "dng"         // Pentax
                | "orf"                 // Olympus
                | "rw2"                 // Panasonic
                | "raw" | "rwl"         // Leica
                | "mrw"                 // Minolta
                | "erf"                 // Epson
                | "3fr"                 // Hasselblad
                | "ari"                 // ARRI
                | "bay"                 // Casio
                | "cap" | "iiq"         // Phase One
                | "dcs" | "dcr" | "drf" | "k25" | "kdc" // Kodak
                | "mef"                 // Mamiya
                | "mos"                 // Leaf
                | "ptx" | "pxn"         // Pentax
                | "r3d"                 // RED
                | "srw"                 // Samsung
                | "x3f"                 // Sigma
            );
        }
    }
    false
}


/// Read a RAW file from in-memory bytes
///
/// Since LibRaw requires file access, this writes to a temp file.
/// Used for processing DSLR images received via INDI BLOBs.
pub fn read_raw_from_bytes(
    data: &[u8],
    extension: &str,
    params: Option<&RawProcessingParams>,
) -> Result<(ImageData, RawMetadata), RawError> {
    use std::io::Write;

    // Create temp file with appropriate extension (LibRaw uses extension for format hints)
    let temp_dir = std::env::temp_dir();
    let temp_path = temp_dir.join(format!("nightshade_raw_{}.{}",
        std::process::id(),
        extension.trim_start_matches('.')
    ));

    // Write data to temp file
    let mut file = std::fs::File::create(&temp_path)
        .map_err(RawError::Io)?;
    file.write_all(data)
        .map_err(RawError::Io)?;
    file.flush()
        .map_err(RawError::Io)?;
    drop(file); // Close file before LibRaw opens it

    // Process with LibRaw
    let result = read_raw(&temp_path, params);

    // Clean up temp file (ignore errors)
    let _ = std::fs::remove_file(&temp_path);

    result
}

/// Get appropriate file extension for a detected RAW format
pub fn raw_format_extension(data: &[u8]) -> Option<&'static str> {
    use crate::ImageFormat;

    match ImageFormat::from_magic_bytes(data) {
        Some(ImageFormat::CanonCR2) => Some("cr2"),
        Some(ImageFormat::CanonCR3) => Some("cr3"),
        Some(ImageFormat::NikonNEF) => Some("nef"),
        Some(ImageFormat::SonyARW) => Some("arw"),
        Some(ImageFormat::FujifilmRAF) => Some("raf"),
        Some(ImageFormat::PentaxPEF) => Some("pef"),
        Some(ImageFormat::OlympusORF) => Some("orf"),
        Some(ImageFormat::PanasonicRW2) => Some("rw2"),
        Some(ImageFormat::GenericRAW) => Some("raw"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_raw_file() {
        assert!(is_raw_file(Path::new("test.cr2")));
        assert!(is_raw_file(Path::new("test.NEF")));
        assert!(is_raw_file(Path::new("test.raf")));  // Fujifilm X-Trans!
        assert!(!is_raw_file(Path::new("test.fits")));
        assert!(!is_raw_file(Path::new("test.jpg")));
    }
}
