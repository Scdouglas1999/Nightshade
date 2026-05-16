//! VARIANT and SAFEARRAY helpers for ASCOM COM interop.
//!
//! These wrap the low-level OleAut32 primitives used to translate between
//! Rust types and the COM `VARIANT` / `SAFEARRAY` representations that
//! ASCOM drivers exchange via `IDispatch`.

use windows::Win32::System::{
    Com::{EXCEPINFO, SAFEARRAY},
    Variant::{
        VARIANT, VT_ARRAY, VT_BOOL, VT_BSTR, VT_BYREF, VT_I2, VT_I4, VT_R8, VT_UI2, VT_VARIANT,
    },
};
use windows::Win32::Foundation::VARIANT_BOOL;

// SAFEARRAY functions from OleAut32.dll
#[link(name = "oleaut32")]
extern "system" {
    pub(super) fn SafeArrayGetDim(psa: *const SAFEARRAY) -> u32;
    pub(super) fn SafeArrayGetLBound(
        psa: *const SAFEARRAY,
        nDim: u32,
        plLbound: *mut i32,
    ) -> windows::core::HRESULT;
    pub(super) fn SafeArrayGetUBound(
        psa: *const SAFEARRAY,
        nDim: u32,
        plUbound: *mut i32,
    ) -> windows::core::HRESULT;
    pub(super) fn SafeArrayAccessData(
        psa: *const SAFEARRAY,
        ppvData: *mut *mut std::ffi::c_void,
    ) -> windows::core::HRESULT;
    pub(super) fn SafeArrayUnaccessData(psa: *const SAFEARRAY) -> windows::core::HRESULT;
}

pub(super) const DISPID_PROPERTYPUT: i32 = -3;

/// Create a VARIANT with a boolean value
pub(super) fn variant_bool(value: bool) -> VARIANT {
    // SAFETY: VARIANT::default() zero-initializes the union; the `Anonymous.Anonymous`
    // tagged-union path is the documented access pattern in the `windows` crate VARIANT
    // bindings, and writing `vt` then the corresponding union field is the standard
    // VARIANT initialization sequence. No raw pointers escape the function.
    unsafe {
        let mut var = VARIANT::default();
        (*var.Anonymous.Anonymous).vt = VT_BOOL;
        (*var.Anonymous.Anonymous).Anonymous.boolVal = if value {
            VARIANT_BOOL(-1)
        } else {
            VARIANT_BOOL(0)
        };
        var
    }
}

/// Create a VARIANT with a double value
pub(super) fn variant_f64(value: f64) -> VARIANT {
    // SAFETY: same VARIANT-union initialization pattern as `variant_bool`; VARIANT::default()
    // produces a zeroed union, and we set `vt` (VT_R8) consistently with the corresponding
    // `dblVal` write so the tag/field relationship is valid before the VARIANT is observed.
    unsafe {
        let mut var = VARIANT::default();
        (*var.Anonymous.Anonymous).vt = VT_R8;
        (*var.Anonymous.Anonymous).Anonymous.dblVal = value;
        var
    }
}

/// Create a VARIANT with an i32 value
pub(super) fn variant_i32(value: i32) -> VARIANT {
    // SAFETY: same VARIANT-union initialization pattern as `variant_bool`/`variant_f64`;
    // VARIANT::default() zero-initializes the union, then we set `vt = VT_I4` and `lVal`
    // in matching positions, so the consumer sees a well-formed VT_I4 VARIANT.
    unsafe {
        let mut var = VARIANT::default();
        (*var.Anonymous.Anonymous).vt = VT_I4;
        (*var.Anonymous.Anonymous).Anonymous.lVal = value;
        var
    }
}

/// Extract boolean from VARIANT
pub(super) fn variant_to_bool(var: &VARIANT) -> Option<bool> {
    // SAFETY: `var` is a `&VARIANT` (borrowed, well-aligned). We gate the union field
    // access on `vt == VT_BOOL`, which is the canonical COM rule for reading the
    // `boolVal` variant arm; if the tag doesn't match we return None without dereferencing.
    unsafe {
        if (*var.Anonymous.Anonymous).vt == VT_BOOL {
            Some((*var.Anonymous.Anonymous).Anonymous.boolVal.0 != 0)
        } else {
            None
        }
    }
}

/// Extract f64 from VARIANT
pub(super) fn variant_to_f64(var: &VARIANT) -> Option<f64> {
    // SAFETY: `var` is a borrowed VARIANT (well-aligned). Each union-field access is gated
    // on the matching `vt` discriminant (VT_R8 / VT_I4 / VT_I2 / VT_UI2) before dereferencing
    // the corresponding union arm, per COM VARIANT tag-then-field semantics.
    unsafe {
        let vt = (*var.Anonymous.Anonymous).vt;
        if vt == VT_R8 {
            Some((*var.Anonymous.Anonymous).Anonymous.dblVal)
        } else if vt == VT_I4 {
            Some((*var.Anonymous.Anonymous).Anonymous.lVal as f64)
        } else if vt == VT_I2 {
            Some((*var.Anonymous.Anonymous).Anonymous.iVal as f64)
        } else if vt == VT_UI2 {
            Some((*var.Anonymous.Anonymous).Anonymous.uiVal as f64)
        } else {
            tracing::warn!("variant_to_f64: unexpected VARIANT type {}", vt.0);
            None
        }
    }
}

/// Extract i32 from VARIANT, handling all common COM integer types.
/// ASCOM drivers may return VT_I2 (Short), VT_I4 (Int), VT_UI2, or VT_R8.
pub(super) fn variant_to_i32(var: &VARIANT) -> Option<i32> {
    // SAFETY: `var` is borrowed (well-aligned). Each union-field access is gated on the
    // matching `vt` discriminant (VT_I4 / VT_I2 / VT_UI2 / VT_R8) before reading the
    // corresponding union arm, per COM VARIANT tag-then-field semantics.
    unsafe {
        let vt = (*var.Anonymous.Anonymous).vt;
        if vt == VT_I4 {
            Some((*var.Anonymous.Anonymous).Anonymous.lVal)
        } else if vt == VT_I2 {
            Some((*var.Anonymous.Anonymous).Anonymous.iVal as i32)
        } else if vt == VT_UI2 {
            Some((*var.Anonymous.Anonymous).Anonymous.uiVal as i32)
        } else if vt == VT_R8 {
            Some((*var.Anonymous.Anonymous).Anonymous.dblVal as i32)
        } else {
            tracing::warn!("variant_to_i32: unexpected VARIANT type {}", vt.0);
            None
        }
    }
}

/// Extract string from VARIANT
pub(super) fn variant_to_string(var: &VARIANT) -> Option<String> {
    // SAFETY: `var` is borrowed (well-aligned). The `bstrVal` union arm is only read after
    // confirming `vt == VT_BSTR`. `BSTR::to_string()` from the `windows` crate handles
    // null/empty BSTRs safely, and we guard the empty case explicitly to avoid that path.
    unsafe {
        if (*var.Anonymous.Anonymous).vt == VT_BSTR {
            let bstr = &(*var.Anonymous.Anonymous).Anonymous.bstrVal;
            // BSTR can be dereferenced to get the string
            if bstr.is_empty() {
                return Some(String::new());
            }
            Some(bstr.to_string())
        } else {
            None
        }
    }
}

/// Extract string array from VARIANT (for ASCOM SupportedActions, etc.)
#[allow(dead_code)]
pub(super) fn variant_to_string_array(var: &VARIANT) -> Option<Vec<String>> {
    // SAFETY: `extract_safearray_string` is `unsafe fn` because it dereferences the
    // SAFEARRAY pointer from inside the VARIANT; we pass an in-scope borrowed VARIANT
    // and the callee validates the variant tag, array dimensions, and bounds before
    // any dereference. Errors propagate via `Result`.
    unsafe { extract_safearray_string(var).ok() }
}

/// Extract error message from EXCEPINFO structure
/// Returns the bstrDescription if available, otherwise bstrSource, otherwise a generic message
pub(super) fn excepinfo_to_string(excep: &EXCEPINFO) -> String {
    // Try to get the description first (most useful)
    if !excep.bstrDescription.is_empty() {
        return excep.bstrDescription.to_string();
    }
    // Fall back to source
    if !excep.bstrSource.is_empty() {
        let source = excep.bstrSource.to_string();
        return format!("ASCOM error from {source}");
    }
    // Last resort: use the error code
    if excep.scode != 0 {
        return format!("ASCOM error code: 0x{:08X}", excep.scode);
    }
    if excep.wCode != 0 {
        return format!("ASCOM error code: {}", excep.wCode);
    }
    "Unknown ASCOM error".to_string()
}

/// Extract i32 array from SAFEARRAY in VARIANT
/// Handles both 1D and 2D SAFEARRAYs (some ASCOM drivers use different layouts)
pub(super) unsafe fn extract_safearray_i32(
    var: &VARIANT,
) -> Result<(Vec<i32>, usize, usize), String> {
    let vt = (*var.Anonymous.Anonymous).vt;

    // Check if this is an array variant
    if (vt.0 & VT_ARRAY.0) == 0 {
        return Err(format!("VARIANT is not an array type, got vt={}", vt.0));
    }

    let psa: *mut SAFEARRAY = (*var.Anonymous.Anonymous).Anonymous.parray;
    if psa.is_null() {
        return Err("SAFEARRAY pointer is null".to_string());
    }

    // Get array dimensions
    let dims = SafeArrayGetDim(psa);
    if dims == 0 {
        return Err("SAFEARRAY has 0 dimensions".to_string());
    }

    if dims > 2 {
        return Err(format!(
            "SAFEARRAY has {} dimensions, expected 1 or 2",
            dims
        ));
    }

    // Get bounds for each dimension
    let mut lower1: i32 = 0;
    let mut upper1: i32 = 0;
    if SafeArrayGetLBound(psa, 1, &mut lower1).is_err() {
        return Err("Failed to get lower bound for dimension 1".to_string());
    }
    if SafeArrayGetUBound(psa, 1, &mut upper1).is_err() {
        return Err("Failed to get upper bound for dimension 1".to_string());
    }

    // Validate bounds to prevent integer overflow and stack overflow
    if upper1 < lower1 {
        return Err(format!(
            "Invalid bounds: upper1 ({}) < lower1 ({})",
            upper1, lower1
        ));
    }

    // Check for reasonable dimension size (individual dimension up to 15000 pixels is generous)
    // This prevents overflow when multiplying dimensions while still supporting large sensors
    let dim1_diff = upper1.saturating_sub(lower1);
    if dim1_diff > 15_000 {
        return Err(format!(
            "Dimension 1 size {} exceeds maximum 15000 pixels per dimension",
            dim1_diff + 1
        ));
    }

    let dim1_size = (dim1_diff + 1) as usize;
    let mut dim2_size = 1;

    if dims == 2 {
        let mut lower2: i32 = 0;
        let mut upper2: i32 = 0;
        if SafeArrayGetLBound(psa, 2, &mut lower2).is_err() {
            return Err("Failed to get lower bound for dimension 2".to_string());
        }
        if SafeArrayGetUBound(psa, 2, &mut upper2).is_err() {
            return Err("Failed to get upper bound for dimension 2".to_string());
        }

        // Validate bounds for dimension 2
        if upper2 < lower2 {
            return Err(format!(
                "Invalid bounds: upper2 ({}) < lower2 ({})",
                upper2, lower2
            ));
        }

        let dim2_diff = upper2.saturating_sub(lower2);
        if dim2_diff > 15_000 {
            return Err(format!(
                "Dimension 2 size {} exceeds maximum 15000 pixels per dimension",
                dim2_diff + 1
            ));
        }

        dim2_size = (dim2_diff + 1) as usize;
    }

    // Validate total size to prevent stack overflow and excessive memory allocation
    // Support large camera sensors (e.g., 100MP = 10000x10000 = 100M pixels)
    // At 4 bytes per i32, 100M elements = 400MB which is reasonable for modern systems
    // For 16-bit sensors, we can support up to ~150M pixels (600MB)
    const MAX_ELEMENTS: usize = 150_000_000; // ~600MB for i32, supports very large sensors

    // Use checked arithmetic to prevent overflow
    let size = dim1_size.checked_mul(dim2_size).ok_or_else(|| {
        format!(
            "Array size overflow: {} x {} exceeds maximum computable size",
            dim1_size, dim2_size
        )
    })?;

    if size > MAX_ELEMENTS {
        return Err(format!(
            "Array size {} elements ({} x {}) exceeds maximum {} elements (~{}MB)",
            size,
            dim1_size,
            dim2_size,
            MAX_ELEMENTS,
            MAX_ELEMENTS * 4 / (1024 * 1024)
        ));
    }

    // Access the raw data
    let mut data_ptr: *mut std::ffi::c_void = std::ptr::null_mut();
    if SafeArrayAccessData(psa, &mut data_ptr).is_err() {
        return Err("Failed to access SAFEARRAY data".to_string());
    }

    if data_ptr.is_null() {
        let _ = SafeArrayUnaccessData(psa);
        return Err("SAFEARRAY data pointer is null".to_string());
    }

    // Determine the element type and copy data
    let base_vt = vt.0 & !VT_ARRAY.0;
    let result = if base_vt == VT_I4.0 {
        // Data is i32 array
        let slice = std::slice::from_raw_parts(data_ptr as *const i32, size);
        Ok(slice.to_vec())
    } else if base_vt == VT_I2.0 {
        // Data is i16 array (convert to i32)
        let slice = std::slice::from_raw_parts(data_ptr as *const i16, size);
        Ok(slice.iter().map(|&x| x as i32).collect())
    } else if base_vt == VT_UI2.0 {
        // Data is u16 array (convert to i32)
        let slice = std::slice::from_raw_parts(data_ptr as *const u16, size);
        Ok(slice.iter().map(|&x| x as i32).collect())
    } else if base_vt == VT_VARIANT.0 {
        // Array of variants - need to extract each one
        let slice = std::slice::from_raw_parts(data_ptr as *const VARIANT, size);
        let mut result = Vec::with_capacity(size);
        for variant in slice {
            if let Some(val) = variant_to_i32(variant) {
                result.push(val);
            } else if let Some(val) = variant_to_f64(variant) {
                result.push(val as i32);
            } else {
                // Skip invalid values or use 0
                result.push(0);
            }
        }
        Ok(result)
    } else {
        Err(format!(
            "Unsupported SAFEARRAY element type: vt={}",
            base_vt
        ))
    };

    // Unaccess the data
    let _ = SafeArrayUnaccessData(psa);

    result.map(|data| (data, dim1_size, dim2_size))
}

/// Extract string array from SAFEARRAY in VARIANT
pub(super) unsafe fn extract_safearray_string(var: &VARIANT) -> Result<Vec<String>, String> {
    let vt = (*var.Anonymous.Anonymous).vt;

    // Check if this is an array variant
    if (vt.0 & VT_ARRAY.0) == 0 {
        return Err(format!("VARIANT is not an array type, got vt={}", vt.0));
    }

    let is_byref = (vt.0 & VT_BYREF.0) != 0;
    let psa: *mut SAFEARRAY = if is_byref {
        // VT_BYREF | VT_ARRAY uses a SAFEARRAY**
        let ppsa = (*var.Anonymous.Anonymous).Anonymous.parray as *mut *mut SAFEARRAY;
        if ppsa.is_null() {
            return Err("SAFEARRAY BYREF pointer is null".to_string());
        }
        *ppsa
    } else {
        (*var.Anonymous.Anonymous).Anonymous.parray
    };
    if psa.is_null() {
        return Err("SAFEARRAY pointer is null".to_string());
    }

    // Get array dimensions
    let dims = SafeArrayGetDim(psa);
    if dims == 0 {
        return Err("SAFEARRAY has 0 dimensions".to_string());
    }
    if dims > 2 {
        return Err(format!(
            "SAFEARRAY has {} dimensions, expected 1 or 2",
            dims
        ));
    }

    // Get bounds
    let mut lower: i32 = 0;
    let mut upper: i32 = 0;
    if SafeArrayGetLBound(psa, 1, &mut lower).is_err() {
        return Err("Failed to get lower bound".to_string());
    }
    if SafeArrayGetUBound(psa, 1, &mut upper).is_err() {
        return Err("Failed to get upper bound".to_string());
    }

    let (lower2, upper2) = if dims == 2 {
        let mut l2: i32 = 0;
        let mut u2: i32 = 0;
        if SafeArrayGetLBound(psa, 2, &mut l2).is_err() {
            return Err("Failed to get lower bound for dimension 2".to_string());
        }
        if SafeArrayGetUBound(psa, 2, &mut u2).is_err() {
            return Err("Failed to get upper bound for dimension 2".to_string());
        }
        (l2, u2)
    } else {
        (0, -1)
    };

    // Validate bounds to prevent integer overflow and stack overflow
    if upper < lower {
        return Err(format!(
            "Invalid bounds: upper ({}) < lower ({})",
            upper, lower
        ));
    }
    if dims == 2 && upper2 < lower2 {
        return Err(format!(
            "Invalid bounds: upper2 ({}) < lower2 ({})",
            upper2, lower2
        ));
    }

    // Check for potential integer overflow
    let diff = upper.saturating_sub(lower);
    if diff > 10_000_000 {
        return Err(format!("Array size too large: {}", diff + 1));
    }

    // Validate total size to prevent stack overflow and excessive memory allocation
    // Limit to ~100MB for safety (assuming BSTR/VARIANT elements)
    const MAX_ELEMENTS: usize = 1_000_000; // Conservative limit for string arrays
    let size = if dims == 2 {
        let diff2 = upper2.saturating_sub(lower2);
        let dim1 = (diff + 1) as usize;
        let dim2 = (diff2 + 1) as usize;
        dim1.checked_mul(dim2)
            .ok_or_else(|| "Array size overflow".to_string())?
    } else {
        (diff + 1) as usize
    };

    if size > MAX_ELEMENTS {
        return Err(format!(
            "Array size too large: {} elements (max: {})",
            size, MAX_ELEMENTS
        ));
    }

    // Access the raw data
    let mut data_ptr: *mut std::ffi::c_void = std::ptr::null_mut();
    if SafeArrayAccessData(psa, &mut data_ptr).is_err() {
        return Err("Failed to access SAFEARRAY data".to_string());
    }

    let base_vt = vt.0 & !(VT_ARRAY.0 | VT_BYREF.0);
    let result = if base_vt == VT_BSTR.0 {
        // Array of BSTRs
        let slice = std::slice::from_raw_parts(data_ptr as *const windows::core::BSTR, size);
        let mut strings = Vec::with_capacity(size);
        for bstr in slice {
            strings.push(bstr.to_string());
        }
        Ok(strings)
    } else if base_vt == VT_VARIANT.0 {
        // Array of Variants containing strings
        let slice = std::slice::from_raw_parts(data_ptr as *const VARIANT, size);
        let mut strings = Vec::with_capacity(size);
        for variant in slice {
            if let Some(s) = variant_to_string(variant) {
                strings.push(s);
            } else {
                strings.push(String::new());
            }
        }
        Ok(strings)
    } else {
        Err(format!(
            "Unsupported SAFEARRAY element type for strings: vt={}",
            base_vt
        ))
    };

    let _ = SafeArrayUnaccessData(psa);

    result
}
