//! The engine as a DLL with a C interface, for the WPF prototype. Text crosses as
//! NUL-terminated UTF-16; every returned pointer must be handed back to `oi_free`.

use std::sync::OnceLock;

use prototype_model::{catalog_json, clock_ms, report, Library};

static LIBRARY: OnceLock<Library> = OnceLock::new();

fn library() -> &'static Library {
    LIBRARY.get_or_init(|| Library::load("en"))
}

fn give(text: &str) -> *mut u16 {
    let wide: Box<[u16]> = text.encode_utf16().chain(std::iter::once(0)).collect();
    Box::into_raw(wide).cast()
}

/// # Safety
/// `text` must be null or point to a NUL-terminated UTF-16 string.
unsafe fn take(text: *const u16) -> String {
    if text.is_null() {
        return String::new();
    }
    let mut length = 0;
    while *text.add(length) != 0 {
        length += 1;
    }
    String::from_utf16_lossy(std::slice::from_raw_parts(text, length))
}

/// The raw catalog, which the 3.6 card builder parses itself.
#[no_mangle]
pub extern "C" fn oi_catalog() -> *mut u16 {
    give(catalog_json())
}

/// The install order for a JSON array of app keys, as `{Count, Rows, Error}`.
///
/// # Safety
/// `keys_json` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_plan(keys_json: *const u16) -> *mut u16 {
    let keys: Vec<String> = serde_json::from_str(&take(keys_json)).unwrap_or_default();
    give(&library().plan_json(&keys).to_string())
}

/// Keys of the installed catalog apps, as a JSON array. Slow: call it off the UI thread.
#[no_mangle]
pub extern "C" fn oi_installed() -> *mut u16 {
    give(&serde_json::to_string(&library().installed_keys()).unwrap_or_else(|_| "[]".to_string()))
}

/// # Safety
/// `text` must be null or a pointer returned by this library that was not freed yet.
#[no_mangle]
pub unsafe extern "C" fn oi_free(text: *mut u16) {
    if text.is_null() {
        return;
    }
    let mut length = 0;
    while *text.add(length) != 0 {
        length += 1;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(text, length + 1)));
}

#[no_mangle]
pub extern "C" fn oi_clock_ms() -> u64 {
    clock_ms()
}

#[no_mangle]
pub extern "C" fn oi_report(render_ms: u64, ready_ms: u64) {
    report(render_ms, ready_ms);
}
