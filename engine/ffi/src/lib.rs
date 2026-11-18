//! The engine as `oneinstall_engine.dll`, with a C interface, for the WPF application.
//!
//! Text crosses the boundary as NUL-terminated UTF-16 holding JSON. Every pointer this
//! library returns must be handed back to [`oi_free`]. No function panics across the
//! boundary: a failure is reported inside the returned JSON.

use std::sync::OnceLock;

use oneinstall_core::packages::installed_state;
use oneinstall_core::queue::{plan, CatalogApp};
use oneinstall_platform::packages::Packages;
use oneinstall_platform::WindowsHost;
use serde_json::{json, Value};

// The application's data, embedded as 3.6 embeds it in its executable.
const CATALOG: &str = include_str!("../../../catalog.json");
const PROFILES: &str = include_str!("../../../profiles.json");
const LOCALES: &str = include_str!("../../../locales.json");

fn without_mark(text: &'static str) -> &'static str {
    text.trim_start_matches('\u{feff}')
}

fn list(row: &Value, name: &str) -> Vec<String> {
    row[name].as_array().map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default()
}

fn catalog() -> &'static [CatalogApp] {
    static APPS: OnceLock<Vec<CatalogApp>> = OnceLock::new();
    APPS.get_or_init(|| {
        let rows: Value = serde_json::from_str(without_mark(CATALOG)).unwrap_or(Value::Null);
        rows.as_array()
            .map(|rows| {
                rows.iter()
                    .map(|row| CatalogApp {
                        key: row["Key"].as_str().unwrap_or("").to_string(),
                        name: row["Name"].as_str().unwrap_or("").to_string(),
                        ids: list(row, "Ids"),
                        url: row["Url"].as_str().unwrap_or("").to_string(),
                        requires: list(row, "Requires"),
                    })
                    .collect()
            })
            .unwrap_or_default()
    })
}

/// The install order for a selection, dependencies first, as `{Rows, Error}`.
pub fn plan_json(keys: &[String]) -> Value {
    match plan(catalog(), keys) {
        Ok(ordered) => json!({
            "Rows": ordered.iter().map(|app| json!({"Key": app.key, "Name": app.name, "Ids": app.ids, "Url": app.url})).collect::<Vec<_>>(),
            "Error": null
        }),
        Err(error) => json!({"Rows": [], "Error": error.message}),
    }
}

/// Keys of the catalog apps WinGet confirms as installed. Slow: it runs `winget export`.
pub fn installed_keys() -> Vec<String> {
    let inventory = Packages::new(&WindowsHost::new()).inventory(false);
    catalog().iter().filter(|app| installed_state(&inventory, Some(&app.ids), "winget") == "Installed").map(|app| app.key.clone()).collect()
}

fn give(text: &str) -> *mut u16 {
    let wide: Box<[u16]> = text.encode_utf16().chain(std::iter::once(0)).collect();
    Box::into_raw(wide).cast()
}

/// # Safety
/// `text` must be null or point to a NUL-terminated UTF-16 string.
unsafe fn length(text: *const u16) -> usize {
    let mut length = 0;
    while *text.add(length) != 0 {
        length += 1;
    }
    length
}

/// # Safety
/// `text` must be null or point to a NUL-terminated UTF-16 string.
unsafe fn take(text: *const u16) -> String {
    if text.is_null() {
        return String::new();
    }
    String::from_utf16_lossy(std::slice::from_raw_parts(text, length(text)))
}

#[no_mangle]
pub extern "C" fn oi_version() -> *mut u16 {
    give(env!("CARGO_PKG_VERSION"))
}

/// The app catalog, as the JSON array the card builder reads.
#[no_mangle]
pub extern "C" fn oi_catalog() -> *mut u16 {
    give(without_mark(CATALOG))
}

#[no_mangle]
pub extern "C" fn oi_profiles() -> *mut u16 {
    give(without_mark(PROFILES))
}

#[no_mangle]
pub extern "C" fn oi_locales() -> *mut u16 {
    give(without_mark(LOCALES))
}

/// The install order for a JSON array of app keys.
///
/// # Safety
/// `keys_json` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_plan(keys_json: *const u16) -> *mut u16 {
    let result = match serde_json::from_str::<Vec<String>>(&take(keys_json)) {
        Ok(keys) => plan_json(&keys),
        Err(_) => json!({"Rows": [], "Error": "The selection is not a list of app keys."}),
    };
    give(&result.to_string())
}

/// Keys of the installed catalog apps, as a JSON array. Slow: call it off the UI thread.
#[no_mangle]
pub extern "C" fn oi_installed() -> *mut u16 {
    give(&serde_json::to_string(&installed_keys()).unwrap_or_else(|_| "[]".to_string()))
}

/// # Safety
/// `text` must be null or a pointer returned by this library that was not freed yet.
#[no_mangle]
pub unsafe extern "C" fn oi_free(text: *mut u16) {
    if !text.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(text, length(text) + 1)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(result: &Value) -> Vec<&str> {
        result["Rows"].as_array().unwrap().iter().map(|row| row["Key"].as_str().unwrap()).collect()
    }

    #[test]
    fn the_embedded_data_parses() {
        assert_eq!(catalog().len(), 325);
        assert!(serde_json::from_str::<Value>(without_mark(PROFILES)).unwrap().is_array());
        assert!(serde_json::from_str::<Value>(without_mark(LOCALES)).unwrap()["en"]["Strings"].is_object());
    }

    #[test]
    fn a_plan_puts_dependencies_first_and_reports_unknown_keys() {
        assert_eq!(keys(&plan_json(&["peace".to_string()])), ["apo", "peace"]);
        assert_eq!(keys(&plan_json(&["peace".to_string(), "apo".to_string()])), ["apo", "peace"]);
        assert!(plan_json(&["no-such-app".to_string()])["Error"].is_string());
    }

    #[test]
    fn text_crosses_the_boundary_unchanged() {
        let sent = "Ação · 日本語 · \u{1F600}";
        let pointer = give(sent);
        // SAFETY: `pointer` was just returned by `give` and is freed exactly once.
        unsafe {
            assert_eq!(take(pointer), sent);
            oi_free(pointer);
            let wide: Vec<u16> = "[\"peace\"]".encode_utf16().chain(std::iter::once(0)).collect();
            let answer = oi_plan(wide.as_ptr());
            assert_eq!(keys(&serde_json::from_str(&take(answer)).unwrap()), ["apo", "peace"]);
            oi_free(answer);
            let refused = oi_plan(std::ptr::null());
            assert!(take(refused).contains("not a list"));
            oi_free(refused);
        }
    }
}
