//! The engine as `oneinstall_engine.dll`, with a C interface, for the WPF application.
//!
//! Text crosses the boundary as NUL-terminated UTF-16. Every pointer this library returns
//! must be handed back to [`oi_free`]. An expected failure is reported inside the returned
//! text, as "!" and the reason. An internal failure of the engine does not end the process:
//! the function returns a null pointer and [`oi_last_error`] says what went wrong.
//!
//! Large, rarely read data is JSON. What the interface needs on every start and on every
//! click is plain records instead, so the application does not have to load a JSON parser
//! before its first frame: fields end with U+001F, records with U+001E, and the items of a
//! list inside a field are separated by U+001D.

use std::sync::{Mutex, MutexGuard, Once, OnceLock, PoisonError};

use oneinstall_core::queue::{plan, CatalogApp};
use oneinstall_core::settings::{resolve_language, Settings};
use oneinstall_platform::settings::{load, save, settings_path, system_appearance};
use oneinstall_platform::WindowsHost;
use serde_json::Value;

// The application's data, embedded as 3.6 embeds it in its executable.
const CATALOG: &str = include_str!("../../../catalog.json");
const PROFILES: &str = include_str!("../../../profiles.json");
const LOCALES: &str = include_str!("../../../locales.json");

pub mod history;
pub mod library;
pub mod queue;
pub mod uninstall;

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

/// Where the test modes of the application keep data, and what they may install with.
struct TestEnvironment {
    data_root: String,
    install_program: String,
}

static TEST_ENVIRONMENT: std::sync::Mutex<Option<TestEnvironment>> = std::sync::Mutex::new(None);

/// Puts the engine in its test environment: the operation history and remembered view go to
/// `data_root` instead of the user's profile, and installing uses `install_program` in place of
/// WinGet. With no install program, installing is refused. Reading what is installed still
/// asks the real WinGet, which only reads.
pub fn set_test_environment(data_root: &str, install_program: &str) {
    if let Ok(mut environment) = TEST_ENVIRONMENT.lock() {
        *environment = Some(TestEnvironment { data_root: data_root.to_string(), install_program: install_program.to_string() });
    }
}

/// Whether the engine is in its test environment, where nothing may change the machine.
pub(crate) fn in_test_environment() -> bool {
    TEST_ENVIRONMENT.lock().map(|environment| environment.is_some()).unwrap_or(true)
}

/// The package service for reading: this machine's WinGet, and the data folder in use.
pub(crate) fn packages() -> oneinstall_platform::packages::Packages {
    let machine = oneinstall_platform::packages::Packages::new(&WindowsHost::new());
    match TEST_ENVIRONMENT.lock().ok().and_then(|environment| environment.as_ref().map(|test| test.data_root.clone())) {
        // Reading what is installed is the same in the test modes as in the real one.
        Some(data_root) => oneinstall_platform::packages::Packages::with(&data_root, &machine.winget).with_shell7(&test_shell7().unwrap_or(machine.shell7)),
        None => machine,
    }
}

/// In the test environment only, a test may name a stand-in for PowerShell 7, to give the
/// engine a complete inventory of its own making.
fn test_shell7() -> Option<String> {
    std::env::var("ONEINSTALL_TEST_SHELL7").ok().filter(|path| !path.is_empty())
}

/// The stand-in installer of the test environment, when it names one.
pub(crate) fn install_stand_in() -> Option<String> {
    TEST_ENVIRONMENT.lock().ok().and_then(|environment| environment.as_ref().map(|test| test.install_program.clone())).filter(|program| !program.is_empty())
}

/// The package service for installing. Refused in the test environment unless it names a
/// stand-in installer.
pub(crate) fn install_packages() -> Result<oneinstall_platform::packages::Packages, String> {
    let test = TEST_ENVIRONMENT.lock().ok().and_then(|environment| environment.as_ref().map(|test| (test.data_root.clone(), test.install_program.clone())));
    match test {
        Some((_, program)) if program.is_empty() => Err("Installing is switched off in the test modes.".to_string()),
        Some((data_root, program)) => Ok(oneinstall_platform::packages::Packages::with(&data_root, &program).with_shell7(&test_shell7().unwrap_or_default())),
        None => Ok(oneinstall_platform::packages::Packages::new(&WindowsHost::new())),
    }
}

/// See [`set_test_environment`].
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_test_environment(data_root: *const u16, install_program: *const u16) {
    set_test_environment(&take(data_root), &take(install_program));
}

/// Shared state, also after a thread failed while holding it: every value kept here is
/// replaced whole, so there is no half-written state to protect.
pub(crate) fn held<T>(shared: &Mutex<T>) -> MutexGuard<'_, T> {
    shared.lock().unwrap_or_else(PoisonError::into_inner)
}

static LAST_ERROR: Mutex<String> = Mutex::new(String::new());

/// Keeps what an internal failure said, and where it happened, for [`oi_last_error`].
fn watch_failures() {
    static WATCHING: Once = Once::new();
    WATCHING.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |failure| {
            let payload = failure.payload();
            let reason =
                payload.downcast_ref::<&str>().map(|text| text.to_string()).or_else(|| payload.downcast_ref::<String>().cloned()).unwrap_or_else(|| "Unknown failure".to_string());
            let place = failure
                .location()
                .map(|place| {
                    format!(" ({}:{})", place.file().replace('\\', "/").rsplit('/').take(3).collect::<Vec<_>>().into_iter().rev().collect::<Vec<_>>().join("/"), place.line())
                })
                .unwrap_or_default();
            *held(&LAST_ERROR) = format!("{reason}{place}");
            previous(failure);
        }));
    });
}

/// Runs engine code for the interface. An internal failure stops that piece of work only,
/// and comes back as its description.
pub(crate) fn guarded<T>(work: impl FnOnce() -> T) -> Result<T, String> {
    watch_failures();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(work)).map_err(|_| held(&LAST_ERROR).clone())
}

/// The body of an exported function that returns text: null after an internal failure.
pub(crate) fn guard(work: impl FnOnce() -> *mut u16) -> *mut u16 {
    guarded(work).unwrap_or(std::ptr::null_mut())
}

/// What the last internal failure said. Empty when there was none.
#[no_mangle]
pub extern "C" fn oi_last_error() -> *mut u16 {
    give(&held(&LAST_ERROR))
}

/// Fails on purpose, in the test modes only, so that the path above can be tested from the
/// application. Outside the test modes it returns empty text.
#[no_mangle]
pub extern "C" fn oi_test_failure() -> *mut u16 {
    guard(|| {
        if TEST_ENVIRONMENT.lock().map(|environment| environment.is_some()).unwrap_or(false) {
            panic!("Deliberate failure for the tests");
        }
        give("")
    })
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
    guard(|| give(env!("CARGO_PKG_VERSION")))
}

/// The app catalog, as the JSON array the card builder reads.
#[no_mangle]
pub extern "C" fn oi_catalog() -> *mut u16 {
    guard(|| give(without_mark(CATALOG)))
}

#[no_mangle]
pub extern "C" fn oi_profiles() -> *mut u16 {
    guard(|| give(without_mark(PROFILES)))
}

#[no_mangle]
pub extern "C" fn oi_locales() -> *mut u16 {
    guard(|| give(without_mark(LOCALES)))
}

/// The library cards, as records. See [`cards`].
#[no_mangle]
pub extern "C" fn oi_cards() -> *mut u16 {
    guard(|| give(&cards()))
}

/// The install order for app keys separated by U+001F, as records. See [`plan_records`].
///
/// # Safety
/// `keys` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_plan(keys: *const u16) -> *mut u16 {
    guard(|| {
        let keys: Vec<String> = take(keys).split(FIELD).filter(|key| !key.is_empty()).map(str::to_string).collect();
        give(&plan_records(&keys))
    })
}

/// The saved preferences, as [`settings_record`] gives them. With `test` non-zero, the fixed
/// preferences of the test modes instead, and no file is read.
#[no_mangle]
pub extern "C" fn oi_settings(test: i32) -> *mut u16 {
    guard(|| {
        let settings = if test != 0 { Settings::for_tests() } else { load(&settings_path(&WindowsHost::new()), &language_codes()) };
        give(&settings_record(&settings))
    })
}

/// Saves preferences given as one record. Empty on success, or "!" followed by the reason.
///
/// # Safety
/// `record` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_save_settings(record: *const u16) -> *mut u16 {
    guard(|| {
        let result = match settings_from_record(&take(record)) {
            Some(settings) => save(&settings_path(&WindowsHost::new()), &settings),
            None => Err("The settings are not valid.".to_string()),
        };
        give(&result.err().map(|reason| format!("!{reason}")).unwrap_or_default())
    })
}

/// Every language, as records. See [`languages`].
#[no_mangle]
pub extern "C" fn oi_languages() -> *mut u16 {
    guard(|| give(&languages()))
}

/// The language for a choice and the Windows display language, as records. See [`language`].
///
/// # Safety
/// `choice` and `ui_culture` must each be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_language(choice: *const u16, ui_culture: *const u16) -> *mut u16 {
    guard(|| give(&language(&take(choice), &take(ui_culture))))
}

/// What Windows reports about appearance, as one record: the accent colour as "RRGGBB",
/// transparency effects ("1" or "0"), and the light app theme ("1" or "0"). The first two are
/// empty when Windows cannot be asked. Call it on a thread with COM initialised.
#[no_mangle]
pub extern "C" fn oi_system_appearance() -> *mut u16 {
    guard(|| {
        let appearance = system_appearance();
        let accent = appearance.accent.map(|(red, green, blue)| format!("{red:02X}{green:02X}{blue:02X}")).unwrap_or_default();
        give(&records(std::iter::once(vec![accent, appearance.advanced_effects.map(flag).unwrap_or_default(), flag(appearance.light)])))
    })
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
        assert_eq!(catalog().len(), 329);
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
        assert_eq!(rows.len(), 329);
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
    fn an_internal_failure_is_reported_and_the_engine_goes_on() {
        let failure = guarded(|| -> usize { panic!("the reason {}", 7) }).unwrap_err();
        assert!(failure.starts_with("the reason 7 (") && failure.contains("lib.rs:"), "{failure}");
        // An exported function returns null, and the reason can be asked for afterwards.
        assert!(guard(|| panic!("at the boundary")).is_null());
        // SAFETY: the pointer was just returned by this library and is freed exactly once.
        unsafe {
            let reason = oi_last_error();
            assert!(take(reason).starts_with("at the boundary ("));
            oi_free(reason);
        }
        // Work that does not fail is untouched, and the engine still answers.
        assert_eq!(guarded(|| 3), Ok(3));
        assert_eq!(cards().split(RECORD).count(), catalog().len());
        // Shared state is still usable after a thread failed while holding it.
        static SHARED: Mutex<u32> = Mutex::new(1);
        let _ = std::thread::spawn(|| {
            let _held = SHARED.lock().unwrap();
            panic!("while holding shared state");
        })
        .join();
        assert!(SHARED.is_poisoned());
        *held(&SHARED) += 1;
        assert_eq!(*held(&SHARED), 2);
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
