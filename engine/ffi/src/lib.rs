//! The engine as `oneinstall_engine.dll`, with a C interface, for the WPF application.
//!
//! Text crosses the boundary as NUL-terminated UTF-16. Every pointer this library returns
//! must be handed back to [`oi_free`]. No function panics across the boundary: a failure is
//! reported inside the returned text.
//!
//! Large, rarely read data is JSON. What the interface needs on every start and on every
//! click is plain records instead, so the application does not have to load a JSON parser
//! before its first frame: fields end with U+001F, records with U+001E, and the items of a
//! list inside a field are separated by U+001D.

use std::sync::OnceLock;

use oneinstall_core::queue::{plan, CatalogApp};
use oneinstall_core::settings::{resolve_language, Settings};
use oneinstall_platform::settings::{load, save, settings_path, system_appearance};
use oneinstall_platform::WindowsHost;
use serde_json::Value;

// The application's data, embedded as 3.6 embeds it in its executable.
const CATALOG: &str = include_str!("../../../catalog.json");
const PROFILES: &str = include_str!("../../../profiles.json");
const LOCALES: &str = include_str!("../../../locales.json");

pub mod library;

fn without_mark(text: &'static str) -> &'static str {
    text.trim_start_matches('\u{feff}')
}

fn list(row: &Value, name: &str) -> Vec<String> {
    row[name].as_array().map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default()
}

pub(crate) fn catalog() -> &'static [CatalogApp] {
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

pub(crate) const FIELD: char = '\u{1f}';
pub(crate) const RECORD: char = '\u{1e}';
pub(crate) const ITEM: char = '\u{1d}';

/// The catalog as parsed JSON, for the fields only the details window needs.
pub(crate) fn catalog_rows() -> &'static [Value] {
    static ROWS: OnceLock<Vec<Value>> = OnceLock::new();
    ROWS.get_or_init(|| serde_json::from_str(without_mark(CATALOG)).unwrap_or_default())
}

pub(crate) fn profile_rows() -> &'static [Value] {
    static ROWS: OnceLock<Vec<Value>> = OnceLock::new();
    ROWS.get_or_init(|| serde_json::from_str(without_mark(PROFILES)).unwrap_or_default())
}

pub(crate) fn records(rows: impl Iterator<Item = Vec<String>>) -> String {
    rows.map(|fields| fields.join(&FIELD.to_string())).collect::<Vec<_>>().join(&RECORD.to_string())
}

/// What a library card shows, one record per app:
/// key, name, category, category group, description, licence label, URL, WinGet ids, also-in categories.
pub fn cards() -> String {
    let rows: Value = serde_json::from_str(without_mark(CATALOG)).unwrap_or(Value::Null);
    let text = |row: &Value, name: &str| row[name].as_str().unwrap_or("").to_string();
    let items = |row: &Value, name: &str| list(row, name).join(&ITEM.to_string());
    records(rows.as_array().map(Vec::as_slice).unwrap_or_default().iter().map(|row| {
        vec![
            text(row, "Key"),
            text(row, "Name"),
            text(row, "Category"),
            text(row, "CategoryGroup"),
            text(row, "Description"),
            text(row, "LicenseLabel"),
            text(row, "Url"),
            items(row, "Ids"),
            items(row, "AlsoIn"),
        ]
    }))
}

/// The install order for a selection, dependencies first, one record per app:
/// key, name, and "1" when WinGet installs it or "0" when it is guided.
/// A refused selection gives "!" followed by the reason instead.
pub fn plan_records(keys: &[String]) -> String {
    match plan(catalog(), keys) {
        Ok(ordered) => records(ordered.iter().map(|app| vec![app.key.clone(), app.name.clone(), if app.ids.is_empty() { "0" } else { "1" }.to_string()])),
        Err(error) => format!("!{}", error.message),
    }
}

fn locales() -> &'static Value {
    static PARSED: OnceLock<Value> = OnceLock::new();
    PARSED.get_or_init(|| serde_json::from_str(without_mark(LOCALES)).unwrap_or(Value::Null))
}

fn language_codes() -> Vec<&'static str> {
    locales().as_object().map(|languages| languages.keys().map(String::as_str).collect()).unwrap_or_default()
}

pub(crate) fn flag(value: bool) -> String {
    if value { "1" } else { "0" }.to_string()
}

/// The preferences as one record: theme, Windows accent ("1" or "0"), language, automatic updates.
pub fn settings_record(settings: &Settings) -> String {
    records(std::iter::once(vec![settings.theme.clone(), flag(settings.windows_accent), settings.language.clone(), flag(settings.auto_update)]))
}

/// The reverse of [`settings_record`]. Refuses anything that would not read back unchanged.
pub fn settings_from_record(record: &str) -> Option<Settings> {
    let fields: Vec<&str> = record.split(FIELD).collect();
    let [theme, accent, language, updates] = fields.as_slice() else { return None };
    let on = |value: &str| match value {
        "1" => Some(true),
        "0" => Some(false),
        _ => None,
    };
    let settings = Settings { theme: theme.to_string(), windows_accent: on(accent)?, language: language.to_string(), auto_update: on(updates)? };
    (Settings::parse(&settings.to_json(), &language_codes()) == settings).then_some(settings)
}

/// Every language of the interface, one record each: code, own name, right-to-left ("1" or "0").
pub fn languages() -> String {
    let all = locales().as_object();
    records(
        all.into_iter()
            .flatten()
            .map(|(code, language)| vec![code.clone(), language["Name"].as_str().unwrap_or(code).to_string(), flag(language["Rtl"].as_bool().unwrap_or(false))]),
    )
}

/// The language to show for a choice and the Windows display language. The first record is
/// the language code and right-to-left ("1" or "0"); each further record is an English text
/// and its translation. English has no further records: its texts are their own keys.
pub fn language(choice: &str, ui_culture: &str) -> String {
    let code = resolve_language(choice, ui_culture, &language_codes());
    let chosen = &locales()[code.as_str()];
    let header = vec![code.clone(), flag(chosen["Rtl"].as_bool().unwrap_or(false))];
    let strings = chosen["Strings"].as_object().filter(|_| code != "en");
    records(std::iter::once(header).chain(strings.into_iter().flatten().map(|(key, value)| vec![key.clone(), value.as_str().unwrap_or(key).to_string()])))
}

pub(crate) fn give(text: &str) -> *mut u16 {
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
pub(crate) unsafe fn take(text: *const u16) -> String {
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

/// The library cards, as records. See [`cards`].
#[no_mangle]
pub extern "C" fn oi_cards() -> *mut u16 {
    give(&cards())
}

/// The install order for app keys separated by U+001F, as records. See [`plan_records`].
///
/// # Safety
/// `keys` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_plan(keys: *const u16) -> *mut u16 {
    let keys: Vec<String> = take(keys).split(FIELD).filter(|key| !key.is_empty()).map(str::to_string).collect();
    give(&plan_records(&keys))
}

/// The saved preferences, as [`settings_record`] gives them. With `test` non-zero, the fixed
/// preferences of the test modes instead, and no file is read.
#[no_mangle]
pub extern "C" fn oi_settings(test: i32) -> *mut u16 {
    let settings = if test != 0 { Settings::for_tests() } else { load(&settings_path(&WindowsHost::new()), &language_codes()) };
    give(&settings_record(&settings))
}

/// Saves preferences given as one record. Empty on success, or "!" followed by the reason.
///
/// # Safety
/// `record` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_save_settings(record: *const u16) -> *mut u16 {
    let result = match settings_from_record(&take(record)) {
        Some(settings) => save(&settings_path(&WindowsHost::new()), &settings),
        None => Err("The settings are not valid.".to_string()),
    };
    give(&result.err().map(|reason| format!("!{reason}")).unwrap_or_default())
}

/// Every language, as records. See [`languages`].
#[no_mangle]
pub extern "C" fn oi_languages() -> *mut u16 {
    give(&languages())
}

/// The language for a choice and the Windows display language, as records. See [`language`].
///
/// # Safety
/// `choice` and `ui_culture` must each be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_language(choice: *const u16, ui_culture: *const u16) -> *mut u16 {
    give(&language(&take(choice), &take(ui_culture)))
}

/// What Windows reports about appearance, as one record: the accent colour as "RRGGBB",
/// transparency effects ("1" or "0"), and the light app theme ("1" or "0"). The first two are
/// empty when Windows cannot be asked. Call it on a thread with COM initialised.
#[no_mangle]
pub extern "C" fn oi_system_appearance() -> *mut u16 {
    let appearance = system_appearance();
    let accent = appearance.accent.map(|(red, green, blue)| format!("{red:02X}{green:02X}{blue:02X}")).unwrap_or_default();
    give(&records(std::iter::once(vec![accent, appearance.advanced_effects.map(flag).unwrap_or_default(), flag(appearance.light)])))
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

    fn keys(plan: &str) -> Vec<&str> {
        plan.split(RECORD).map(|record| record.split(FIELD).next().unwrap()).collect()
    }

    #[test]
    fn the_embedded_data_parses() {
        assert_eq!(catalog().len(), 325);
        assert!(serde_json::from_str::<Value>(without_mark(PROFILES)).unwrap().is_array());
        assert!(serde_json::from_str::<Value>(without_mark(LOCALES)).unwrap()["en"]["Strings"].is_object());
    }

    #[test]
    fn a_plan_puts_dependencies_first_and_reports_unknown_keys() {
        assert_eq!(keys(&plan_records(&["peace".to_string()])), ["apo", "peace"]);
        assert_eq!(keys(&plan_records(&["peace".to_string(), "apo".to_string()])), ["apo", "peace"]);
        assert!(plan_records(&["no-such-app".to_string()]).starts_with('!'));
        assert_eq!(plan_records(&[]), "");
        assert_eq!(plan_records(&["peace".to_string()]).split(RECORD).next_back().unwrap().split(FIELD).collect::<Vec<_>>(), ["peace", "Peace GUI", "0"]);
    }

    #[test]
    fn every_card_has_nine_fields_and_no_separator_inside_its_text() {
        let cards = cards();
        let rows: Vec<Vec<&str>> = cards.split(RECORD).map(|record| record.split(FIELD).collect()).collect();
        assert_eq!(rows.len(), 325);
        assert!(rows.iter().all(|fields| fields.len() == 9 && !fields[0].is_empty() && !fields[1].is_empty()));
        // The catalog itself must not contain the separators, or records would split wrongly.
        assert!(![FIELD, RECORD, ITEM].iter().any(|separator| without_mark(CATALOG).contains(*separator)));
        let seven_zip = rows.iter().find(|fields| fields[1] == "7-Zip").unwrap();
        assert_eq!((seven_zip[0], seven_zip[2], seven_zip[3]), ("extra_7zip", "Files & Downloads", "Files & Storage"));
    }

    #[test]
    fn languages_resolve_and_translate() {
        let all = languages();
        let rows: Vec<Vec<&str>> = all.split(RECORD).map(|record| record.split(FIELD).collect()).collect();
        assert_eq!(rows.len(), 51);
        assert!(rows.iter().all(|fields| fields.len() == 3));
        let right_to_left: Vec<&str> = rows.iter().filter(|fields| fields[2] == "1").map(|fields| fields[0]).collect();
        assert_eq!(right_to_left, ["ar", "ur"]);

        let portuguese = language("System", "pt-BR");
        let mut records = portuguese.split(RECORD);
        assert_eq!(records.next().unwrap().split(FIELD).collect::<Vec<_>>(), ["pt-PT", "0"]);
        let strings: Vec<Vec<&str>> = records.map(|record| record.split(FIELD).collect()).collect();
        assert!(strings.iter().all(|fields| fields.len() == 2));
        assert!(strings.contains(&vec!["Install", "Instalar"]));
        // English needs no table, and an explicit choice ignores the Windows language.
        assert_eq!(language("System", "af-ZA"), format!("en{FIELD}0"));
        assert!(language("ar", "pt-BR").starts_with(&format!("ar{FIELD}1{RECORD}")));
        // No translation may contain a separator, or records would split wrongly.
        assert!(![FIELD, RECORD, ITEM].iter().any(|separator| without_mark(LOCALES).contains(*separator)));
    }

    #[test]
    fn settings_cross_as_one_record_and_invalid_ones_are_refused() {
        let settings = Settings { theme: "Light".to_string(), windows_accent: false, language: "ar".to_string(), auto_update: true };
        let record = settings_record(&settings);
        assert_eq!(record.split(FIELD).collect::<Vec<_>>(), ["Light", "0", "ar", "1"]);
        assert_eq!(settings_from_record(&record), Some(settings));
        assert_eq!(settings_record(&Settings::for_tests()).split(FIELD).collect::<Vec<_>>(), ["Dark", "1", "en", "0"]);
        for invalid in ["", "Neon\u{1f}1\u{1f}en\u{1f}1", "Dark\u{1f}yes\u{1f}en\u{1f}1", "Dark\u{1f}1\u{1f}xx\u{1f}1", "Dark\u{1f}1\u{1f}en"] {
            assert_eq!(settings_from_record(invalid), None, "{invalid:?}");
        }
    }

    #[test]
    fn text_crosses_the_boundary_unchanged() {
        let sent = "Ação · 日本語 · \u{1F600}";
        let pointer = give(sent);
        // SAFETY: `pointer` was just returned by `give` and is freed exactly once.
        unsafe {
            assert_eq!(take(pointer), sent);
            oi_free(pointer);
            let wide: Vec<u16> = "peace".encode_utf16().chain(std::iter::once(0)).collect();
            let answer = oi_plan(wide.as_ptr());
            assert_eq!(keys(&take(answer)), ["apo", "peace"]);
            oi_free(answer);
            let empty = oi_plan(std::ptr::null());
            assert_eq!(take(empty), "");
            oi_free(empty);
        }
    }
}
