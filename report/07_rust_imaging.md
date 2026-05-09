# 7. Rust Imaging Pipeline Audit

## Scope
- `native/nightshade_native/imaging/src/` -- 15 source files (~4,800 LOC)
- FITS/XISF reading/writing, LibRaw RAW processing, debayer, stretch, statistics, star detection, plate solving, PHD2 guiding, buffer pooling, file naming, camera abstraction, tiled processing, memory-mapped I/O

---

## Rating: B+ (Strong Foundation, Several Bugs to Fix)

The imaging pipeline is a genuinely well-architected system with real, production-quality implementations. It is **not** a stub/placeholder codebase -- every module contains substantive algorithms. The code makes excellent use of rayon parallelism, memory-mapped I/O, and buffer pooling. However, several concrete bugs, an incomplete VNG debayer, and some unsafe FFI patterns reduce the grade.

---

## Feature Inventory

### Format Support

| Format | Read | Write | Notes |
|--------|------|-------|-------|
| FITS | Full | Full | All BITPIX (8, 16, 32, -32, -64), BZERO/BSCALE, WCS headers |
| XISF | Full | Full | All sample formats, attachment-based data, FITS keyword interop |
| TIFF | Via `image` crate | Via `image` crate | 8-bit and 16-bit mono/RGB |
| PNG | Via `image` crate | Via `image` crate | 8-bit and 16-bit mono/RGB |
| JPEG | Via `image` crate | Via `image` crate | 8-bit only, quality parameter |
| RAW (CR2/CR3/NEF/ARW/RAF/PEF/ORF/RW2/etc.) | LibRaw FFI | N/A (read-only) | 600+ camera models, native X-Trans |

### Core Capabilities

| Module | File | LOC | Rating | Summary |
|--------|------|-----|--------|---------|
| **FITS I/O** | `fits.rs` | ~580 | A- | Correct big-endian handling, full read/write, WCS support |
| **XISF I/O** | `xisf.rs` | ~530 | B | Working but uses hand-rolled XML parser instead of proper XML lib |
| **Debayer** | `debayer.rs` | ~570 | B- | Bilinear is correct, VNG is a stub fallback, SuperPixel works |
| **Stretch** | `stretch.rs` | ~275 | A | Solid STF implementation with per-channel RGB support |
| **Statistics** | `stats.rs` | ~820 | A | Mean/median/stddev/MAD, star detection, HFR/FWHM/eccentricity |
| **RAW/LibRaw** | `raw.rs` | ~870 | C+ | Working but has serious unsafe FFI patterns |
| **Buffer Pool** | `buffer_pool.rs` | ~790 | A | Production-quality pooling with metrics, tests, thread safety |
| **Camera** | `camera.rs` | ~780 | A- | Clean trait-based abstraction with simulated camera |
| **Naming** | `naming.rs` | ~565 | A | Comprehensive pattern system with 15+ variables |
| **PHD2** | `phd2.rs` | ~900+ | A- | Full JSON-RPC protocol, dithering, settle monitoring |
| **Plate Solve** | `platesolve.rs` | ~470 | B+ | ASTAP integration works, WCS parsing correct |
| **Reader** | `reader.rs` | ~350 | B+ | Memory-mapped FITS, downsampling, thumbnail generation |
| **Processing** | `processing.rs` | ~400 | B | Tiled parallel processing framework, functional but limited |
| **Core types** | `lib.rs` | ~820 | A- | Solid ImageData container, format detection, write functions |

---

## Bugs Found

### BUG 1: VNG Debayer Falls Back to Bilinear (CRITICAL FUNCTIONALITY GAP)
**File:** `debayer.rs:476-509`
**Severity:** High
The `vng_interpolate()` function calculates gradients correctly but then **ignores them entirely**, falling back to simple bilinear interpolation:
```rust
fn vng_interpolate(...) -> (u16, u16, u16) {
    // For simplicity, fall back to bilinear for VNG
    // A full VNG implementation would select directions based on gradients
    match color {
        BayerColor::Red => (val, interpolate_cross(...), interpolate_diagonal(...)),
        ...
    }
}
```
The `_gradients` and `_threshold` parameters are prefixed with underscores, confirming they are unused. Users selecting VNG quality get bilinear results. This violates the CLAUDE.md rule: "You are not to EVER use stubs or placeholders."

### BUG 2: VNG Border Handling Ignores Bayer Pattern for Green Pixels
**File:** `debayer.rs:433-443`
**Severity:** Medium
In `process_border_pixel()`, green pixel handling always uses `interpolate_horizontal` for red and `interpolate_vertical` for blue, ignoring the Bayer pattern. For RGGB/BGGR, the correct assignment depends on which green position (Gr or Gb), but the border handler doesn't distinguish.

### BUG 3: LibRaw Output Params Located by Memory Scanning (UNSAFE)
**File:** `raw.rs:382-403`
**Severity:** High
The code scans raw memory to find LibRaw's output parameters structure by checking for the sRGB gamma signature:
```rust
let start_ptr = (processor as *mut u8).add(512);
let end_ptr = (processor as *mut u8).add(32768);
let mut ptr = start_ptr;
while ptr < end_ptr {
    let p = ptr as *mut libraw_output_params_t;
    if ((*p).gamm[0] - 0.45045).abs() < 0.001 ...
```
This is extremely fragile. A LibRaw version update, different compiler, or memory layout change will cause it to either miss the structure (falling back to defaults silently) or find a false positive and corrupt memory. The correct approach is to use `libraw_get_params()` or bind to the documented struct offsets.

### BUG 4: FITS Header Padding Calculation Ignores COMMENT/HISTORY Records
**File:** `fits.rs:318-324`
**Severity:** Medium
The header padding uses `header.keyword_order.len() + 1` for the record count, but COMMENT and HISTORY keywords are stored in `header.keywords` with generated keys like `COMMENT_5` -- they are NOT added to `keyword_order`. Therefore the padding calculation undercounts the actual number of 80-byte records written, potentially misaligning the data block start.

### BUG 5: `auto_stretch_stf` Assumes U16 for All Pixel Types
**File:** `stretch.rs:46-53`
**Severity:** Medium
`auto_stretch_stf()` unconditionally reads data as `chunks_exact(2)` and interprets as `u16`, but is called from `ImageData::to_display_u8()` which only gates on `PixelType::U16`. If called directly on a U8 or F32 image, it will produce garbled results. The `to_display_u8()` method handles this correctly, but `auto_stretch_stf` is public API and could be misused.

### BUG 6: JPEG Write Always Outputs Grayscale for RGB Images
**File:** `lib.rs:720-731`
**Severity:** Medium
The `write_jpeg()` function handles RGB images by writing them as `ColorType::L8` (grayscale):
```rust
} else {
    // For RGB, the display_u8 output is grayscale-stretched
    // So we output as grayscale
    encoder.write_image(&display_data, ..., image::ColorType::L8, ...)
}
```
This silently discards color information. The comment acknowledges the problem but does not fix it.

### BUG 7: XISF XML Parser Fragile with Attribute Order
**File:** `xisf.rs:197-206`
**Severity:** Low-Medium
`extract_attribute()` finds the first occurrence of the attribute name in the entire XML, not within a specific element. If a `<Property>` element has a `geometry` attribute before the `<Image>` element, it would return the wrong value. This is unlikely in practice but violates the XISF spec parsing requirements.

### BUG 8: `simple_random()` Has Race Condition
**File:** `lib.rs:508-516`
**Severity:** Low
The PRNG uses `AtomicU64` with `SeqCst` load and store, but the load-then-store is not atomic -- two threads can read the same value and compute the same "random" number. This only affects simulated images, so impact is minimal, but `fetch_update` or `compare_exchange` would be correct.

### BUG 9: PNG/TIFF Fallback Silently Drops Multi-Channel Data
**File:** `lib.rs:596-609` and `lib.rs:679-691`
**Severity:** Medium
For non-standard channel/pixel-type combinations, the fallback path converts to `GrayImage` regardless of `channels`:
```rust
_ => {
    let display_data = image.to_display_u8();
    if image.channels == 1 { ... }
    else {
        // For multi-channel, use grayscale (first channel only) as fallback
        let img: GrayImage = ImageBuffer::from_raw(...)
    }
}
```
The multi-channel case creates a GrayImage from all the bytes, which interprets channel-interleaved data as single-channel, producing a corrupted image.

### BUG 10: MappedFitsReader Header Record Count
**File:** `reader.rs:72-74`
**Severity:** Medium
Same padding bug as in fits.rs -- `header.keywords.len() + 1` doesn't account for the actual number of 80-byte records read (which includes blank records, COMMENT, HISTORY, etc. that may not all be in the keywords HashMap). The data_offset could be wrong, causing reads from the wrong position.

---

## Missing Pieces

### No Image Stacking
There is no frame stacking/integration capability. Competing software (PixInsight, DSS) provides sigma-clipping, median, average stacking. This is typically an offline operation but some users expect basic live stacking.

### No Dark/Flat Calibration in Pipeline
While the camera module has FrameType support and the naming module handles Dark/Flat/Bias frame types, there is no calibration module to actually apply dark subtraction, flat division, or bias correction to light frames.

### No XISF Compression Support
The XISF reader only handles `attachment:` location (uncompressed). XISF supports zlib, LZ4, and Zstandard compression. PixInsight files saved with compression will fail to load.

### No TIFF/PNG/JPEG Reading in `read_image()`
The `read_image()` function in `lib.rs:738-822` returns an error for TIFF, PNG, and JPEG formats ("Reading {:?} is not supported"). These formats have write support but no read path through the unified API.

### No Astrometry.net Support
While `find_astrometry()` looks for `solve-field`, the `AstapSolver` class only implements ASTAP solving. There is no `AstrometrySolver` implementation for the local astrometry.net solver.

### No Image Registration/Alignment
No star matching or image alignment capability for use in mosaics or multi-frame operations.

---

## Algorithmic Correctness Assessment

### FITS I/O: Correct
- Big-endian to little-endian conversion is properly handled for all data types
- BZERO/BSCALE applied correctly, including the common unsigned-16-bit case (BZERO=32768)
- Header keyword parsing handles FITS D-notation floats (`1.23D+05` -> `1.23E+05`)
- WCS header generation from plate solve results is mathematically correct (CD matrix from scale + rotation)

### Debayer: Mostly Correct
- Bilinear interpolation is implemented correctly with proper boundary handling
- SuperPixel (2x2 binning) is correct for all 4 Bayer patterns
- VNG is a non-implementation (see BUG 1)
- All three methods use rayon parallel row processing efficiently

### Auto Stretch (STF): Correct
- Percentile-based shadow/highlight clipping (0.1%/99.9%) is appropriate for astro images
- Midtone Transfer Function (MTF) formula matches PixInsight's STF algorithm
- Per-channel RGB stretch is available for color images

### Star Detection: Good
- Sigma-clipped background estimation is sound
- Intensity-weighted centroid gives sub-pixel accuracy
- Second-moment eccentricity calculation is mathematically correct (eigenvalue decomposition of covariance matrix)
- HFR calculation uses proper flux-weighted radius
- Multi-criteria filtering (HFR, SNR, eccentricity, sharpness, area) effectively rejects hot pixels and cosmic rays
- FWHM approximation `FWHM = 2.3548 * HFR` is correct for Gaussian profiles

### LibRaw Integration: Functional but Fragile
- The FFI struct declarations appear correct for standard LibRaw
- X-Trans detection via `filters == 9` is correct
- Memory lifecycle management (init -> open -> unpack -> process -> make_mem_image -> clear -> close) follows the correct LibRaw sequence
- The memory-scanning approach to locate output_params is the critical weakness

---

## Performance Assessment

### Strengths
- **Rayon parallelism** is used extensively and correctly: debayer, stretch, statistics, histogram calculation all use `par_chunks_exact`, `par_iter`, `par_sort_unstable`
- **Buffer pooling** avoids allocation churn during rapid capture sequences; pool supports multiple sensor sizes and tracks metrics
- **Memory-mapped FITS reader** enables region-of-interest and downsampled reads without loading full images
- **Tiled processing** framework can process large images (60MP+) without memory pressure

### Potential Bottlenecks
1. **Star detection is sequential** (`stats.rs:180-306`): The flood-fill `visited` array prevents parallelization. For 61MP images this could be slow. Consider a two-phase approach: parallel candidate detection, then sequential validation.
2. **Full image sort for STF** (`stretch.rs:61-62`): `auto_stretch_stf` clones the entire pixel array and sorts it for median/percentile calculation. For a 61MP image, this is ~470MB of copies + sort. A streaming percentile estimator (e.g., P-square or t-digest) would be much more memory-efficient.
3. **FITS writing is not parallelized** (`fits.rs:537-570`): Endian conversion during FITS write is sequential. For large images, parallel conversion followed by bulk write would be faster.

---

## Code Quality

### Positive Patterns
- Proper error types (FitsError, XisfError, RawError, CameraError) with Display and Error impls
- Comprehensive test suites for buffer_pool (9 tests) and naming (2 tests)
- Clean trait-based camera abstraction (`CameraController`) enables testing and simulation
- Builder pattern for NamingContext (`with_target()`, `with_filter()`, etc.)
- Good documentation throughout with module-level doc comments

### Negative Patterns
- The XISF parser should use `quick-xml` (already in workspace dependencies) instead of hand-rolled string searching
- Several `#[allow(dead_code)]` suppressions in camera.rs suggest unused fields
- The `simple_random()` global state is a code smell -- should use a proper PRNG or thread-local
- Some functions return `String` errors instead of typed errors (processing.rs, reader.rs)

---

## Recommendations

### Priority 1 (Bug Fixes)
1. **Implement real VNG debayer** or remove it from the enum and document that only Bilinear and SuperPixel are available. Do not advertise VNG when it doesn't work.
2. **Fix LibRaw output_params location**: Use `libraw_get_params()` API or calculate the correct struct offset from the documented ABI. The memory-scanning approach is a ticking time bomb.
3. **Fix FITS header padding**: Count actual 80-byte records written, not just keyword_order length. Include COMMENT/HISTORY records in the count.
4. **Fix JPEG RGB output**: Write as `Rgb8` instead of `L8` for 3-channel images.

### Priority 2 (Functionality)
5. **Add TIFF/PNG/JPEG read support** to `read_image()` using the `image` crate (trivial -- the write path already uses it).
6. **Add XISF compression support** (at minimum zlib, which is most common).
7. **Add basic calibration** (dark subtraction, flat division) -- this is table stakes for astrophotography software.

### Priority 3 (Performance)
8. **Use streaming percentile estimator** for auto-stretch on large images to avoid full-image sort.
9. **Parallelize FITS endian conversion** during writes using rayon.
10. **Consider two-phase star detection** to partially parallelize candidate identification.

### Priority 4 (Code Quality)
11. **Replace XISF hand-rolled XML parser** with `quick-xml` for robustness and spec compliance.
12. **Add integration tests** for FITS and XISF round-trip (write then read, verify identical).
13. **Add benchmarks** for the hot paths (debayer, stretch, star detection) using criterion.
