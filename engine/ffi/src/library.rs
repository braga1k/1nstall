//! The install library behind the interface: selection, installed states, app details,
//! profiles and saved selections. Each function returns the records the interface draws;
//! the exported `oi_*` wrappers at the end only convert text at the boundary.

use std::path::Path;
use std::sync::Mutex;

use oneinstall_core::model::PackageInventory;
use oneinstall_core::packages::{installed_state, valid_id, valid_source};
use oneinstall_core::queue::{deselect, plan, select};
use oneinstall_platform::packages::{read_setup, save_setup, Packages, SetupDraft};
use oneinstall_platform::WindowsHost;
use serde_json::{json, Value};

use crate::{catalog, catalog_rows, flag, give, profile_rows, records, take, FIELD, ITEM};

/// The last inventory WinGet reported. Empty until [`refresh_inventory`] has run.
static INVENTORY: Mutex<PackageInventory> = Mutex::new(PackageInventory { complete: false, partial: false, packages: Vec::new(), message: None });

fn inventory() -> PackageInventory {
    INVENTORY.lock().map(|inventory| inventory.clone()).unwrap_or_default()
}

fn text(row: &Value, name: &str) -> String {
    row[name].as_str().unwrap_or("").to_string()
}

fn keys_of(joined: &str) -> Vec<String> {
    joined.split(FIELD).filter(|key| !key.is_empty()).map(str::to_string).collect()
}

fn refused(reason: impl std::fmt::Display) -> String {
    format!("!{reason}")
}

/// The selection after a card is switched on: the app and everything it requires.
pub fn selection_add(selected: &[String], key: &str) -> String {
    match select(catalog(), selected, key) {
        Ok(keys) => keys.join(&FIELD.to_string()),
        Err(error) => refused(error.message),
    }
}

/// The selection after an app is removed: it leaves, and so does every app left without one
/// of its requirements.
pub fn selection_remove(selected: &[String], key: &str) -> String {
    deselect(catalog(), selected, key).join(&FIELD.to_string())
}

/// Asks WinGet what is installed and keeps the answer for the other functions here.
/// One record: the message to show, then whether the list is complete, then whether it is
/// partial. Slow: it runs `winget export`.
pub fn refresh_inventory() -> String {
    let found = Packages::new(&WindowsHost::new()).inventory(false);
    let record = vec![found.message.clone().unwrap_or_default(), flag(found.complete), flag(found.partial)];
    if let Ok(mut inventory) = INVENTORY.lock() {
        *inventory = found;
    }
    records(std::iter::once(record))
}

/// The installed state of every catalog app, from the last inventory: key, then state.
pub fn states() -> String {
    let inventory = inventory();
    records(catalog().iter().map(|app| vec![app.key.clone(), installed_state(&inventory, Some(&app.ids), "winget")]))
}

/// What the details window shows for an app (`Show-AppDetails`). The first record is the name,
/// the description, the official website, whether the website button is enabled and whether
/// the address may be opened. Each further record is a section title, a label and a value.
pub fn details(key: &str) -> String {
    let Some(row) = catalog_rows().iter().find(|row| row["Key"].as_str() == Some(key)) else {
        return refused("Unknown app.");
    };
    let Some(app) = catalog().iter().find(|app| app.key == key) else {
        return refused("Unknown app.");
    };
    let website = match (text(row, "Website"), text(row, "Url")) {
        (website, _) if !website.is_empty() => website,
        (_, url) if !url.is_empty() => url,
        _ => "Not verified in this catalog".to_string(),
    };
    let publisher = if row.get("Publisher").is_some() { text(row, "Publisher") } else { "Not verified in this catalog".to_string() };
    let license = match (text(row, "License"), text(row, "VerifiedOn")) {
        (license, checked) if !license.is_empty() && !checked.is_empty() => format!("{license} · checked {checked}"),
        _ => "Not verified; review publisher terms".to_string(),
    };
    let names: Vec<&str> = app.requires.iter().filter_map(|required| catalog().iter().find(|other| &other.key == required)).map(|other| other.name.as_str()).collect();
    let dependencies = if names.is_empty() { "None declared".to_string() } else { names.join(", ") };
    let automatic = !app.ids.is_empty();
    let row_of = |section: &str, label: &str, value: String| vec![section.to_string(), label.to_string(), value];
    let rows = vec![
        vec![
            app.name.clone(),
            text(row, "Description"),
            website.clone(),
            flag(website.starts_with("https://")),
            flag(website.starts_with("https://") && !website.contains(char::is_whitespace)),
        ],
        row_of("About", "Category", text(row, "Category")),
        row_of("About", "Publisher", publisher),
        row_of("About", "License", license),
        row_of("About", "Official website", website),
        row_of("Installation", "Method", if automatic { "Automatic · WinGet" } else { "Guided · publisher website" }.to_string()),
        row_of("Installation", "Installed state", installed_state(&inventory(), Some(&app.ids), "winget")),
        row_of("Installation", "Package IDs", if automatic { app.ids.join(", ") } else { "No verified package identity".to_string() }),
        row_of("Installation", "Scope", "WinGet aggregate; individual scopes are not reported.".to_string()),
        row_of("Installation", "Dependencies", dependencies),
    ];
    records(rows.into_iter())
}

/// The built-in profiles in menu order, one record each: group, key, name, description, and
/// the names and the keys of the apps the profile selects, dependencies included.
pub fn profiles_menu() -> String {
    let groups = ["Everyday & Work", "Create", "Files & Privacy", "PC & Tools"];
    let join = |items: Vec<String>| items.join(&ITEM.to_string());
    records(groups.iter().flat_map(|group| profile_rows().iter().filter(move |profile| profile["Group"].as_str() == Some(*group))).map(|profile| {
        let apps: Vec<String> = profile["Apps"].as_array().map(|apps| apps.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default();
        let planned = plan(catalog(), &apps).unwrap_or_default();
        vec![
            text(profile, "Group"),
            text(profile, "Key"),
            text(profile, "Name"),
            text(profile, "Description"),
            join(planned.iter().map(|app| app.name.clone()).collect()),
            join(planned.iter().map(|app| app.key.clone()).collect()),
        ]
    }))
}

/// Where WinGet is on this machine, or empty when it is missing.
pub fn winget_path() -> String {
    Packages::new(&WindowsHost::new()).winget
}

const VIEWS: [&str; 2] = ["All apps", "Installed"];

fn view_path() -> std::path::PathBuf {
    Path::new(&Packages::new(&WindowsHost::new()).data_root).join("preferences.json")
}

/// The library view 3.6 remembers in `preferences.json`: "All apps" unless a valid one is saved.
pub fn library_view_from(path: &Path) -> String {
    let saved = std::fs::metadata(path).ok().filter(|file| file.len() <= 4096).and_then(|_| std::fs::read(path).ok());
    let view = saved
        .and_then(|bytes| serde_json::from_str::<Value>(String::from_utf8_lossy(&bytes).trim_start_matches('\u{feff}')).ok())
        .and_then(|saved| saved["View"].as_str().map(str::to_string));
    view.and_then(|view| VIEWS.iter().find(|known| known.eq_ignore_ascii_case(&view))).unwrap_or(&VIEWS[0]).to_string()
}

pub fn save_library_view_to(path: &Path, view: &str) -> Result<(), String> {
    if !VIEWS.contains(&view) {
        return Err("Unknown library view.".to_string());
    }
    if let Some(folder) = path.parent() {
        std::fs::create_dir_all(folder).map_err(|error| error.to_string())?;
    }
    std::fs::write(path, serde_json::to_string_pretty(&json!({"View": view})).unwrap_or_default()).map_err(|error| error.to_string())
}

/// Saves the selected apps as a version 1 profile, the file 3.6 writes (`Save-UserProfile`).
pub fn save_selection(path: &str, keys: &[String]) -> Result<(), String> {
    if keys.is_empty() {
        return Err("Select at least one app before saving a profile.".to_string());
    }
    std::fs::write(path, serde_json::to_string_pretty(&json!({"Version": 1, "Apps": keys})).unwrap_or_default()).map_err(|error| error.to_string())
}

/// The preview of a saved selection (`Load-UserProfile`): one record per app with the key to
/// select, the name and its state here. An app this catalog cannot install has an empty key.
pub fn setup_rows(path: &str, inventory: &PackageInventory) -> Result<Vec<Vec<String>>, String> {
    let setup = read_setup(path).map_err(|error| error.message)?;
    if setup.version == 1 {
        // The whole plan is validated before anything is offered.
        let planned = plan(catalog(), &setup.keys).map_err(|error| error.message)?;
        return Ok(planned
            .iter()
            .map(|app| {
                let state = if app.ids.is_empty() { "Manual installation required".to_string() } else { installed_state(inventory, Some(&app.ids), "winget") };
                vec![app.key.clone(), app.name.clone(), state]
            })
            .collect());
    }
    Ok(setup
        .apps
        .iter()
        .map(|entry| {
            let matches: Vec<_> =
                catalog().iter().filter(|app| entry.source.eq_ignore_ascii_case("winget") && app.ids.iter().any(|id| id.eq_ignore_ascii_case(&entry.id))).collect();
            if let [app] = matches.as_slice() {
                let mut state = installed_state(inventory, Some(&app.ids), "winget");
                if state == "Not installed" {
                    state = "Missing · available in catalog".to_string();
                }
                vec![app.key.clone(), app.name.clone(), format!("{state} · recorded version {}", entry.version)]
            } else {
                let state = installed_state(inventory, Some(&[entry.id.clone()]), &entry.source);
                let shown = if state.starts_with("Installed ·") {
                    format!("Already installed · {state}")
                } else {
                    "Unavailable in this catalog · use the publisher or WinGet manually".to_string()
                };
                vec![String::new(), entry.name.clone(), shown]
            }
        })
        .collect())
}

/// The installed packages a snapshot may record: key (`source:id`), name and state. Refused,
/// with a title and a message, when there is no inventory or nothing reliably identified.
pub fn snapshot_rows(inventory: &PackageInventory) -> Result<Vec<Vec<String>>, (String, String)> {
    if !inventory.complete && !inventory.partial {
        return Err(("Inventory required".to_string(), "Refresh installed status first. A snapshot needs verified exact identities.".to_string()));
    }
    let rows: Vec<Vec<String>> = inventory
        .packages
        .iter()
        .filter_map(|package| {
            let (id, source) = (package.id.as_deref()?, package.source.as_deref()?);
            let installed = valid_id(id) && valid_source(source) && installed_state(inventory, Some(&[id.to_string()]), source).starts_with("Installed ·");
            installed.then(|| {
                vec![
                    format!("{source}:{id}"),
                    package.name.clone().unwrap_or_default(),
                    format!("Installed · {} · {source}", package.installed_version.clone().unwrap_or_default()),
                ]
            })
        })
        .collect();
    if rows.is_empty() {
        return Err(("Nothing to save".to_string(), "No reliably identified installed apps were found. Guided and ambiguous apps are excluded.".to_string()));
    }
    Ok(rows)
}

/// Saves the chosen installed packages as a version 2 setup file, with their identities.
pub fn save_snapshot(path: &str, keys: &[String], inventory: &PackageInventory) -> Result<(), String> {
    let entries: Vec<SetupDraft> = inventory
        .packages
        .iter()
        .filter_map(|package| {
            let (id, source) = (package.id.clone()?, package.source.clone()?);
            keys.contains(&format!("{source}:{id}")).then(|| SetupDraft { id, source, name: package.name.clone(), version: package.installed_version.clone() })
        })
        .collect();
    save_setup(path, &entries).map_err(|error| error.message)
}

fn answer(result: Result<(), String>) -> *mut u16 {
    give(&result.err().map(refused).unwrap_or_default())
}

/// The selection, as keys separated by U+001F, after `key` is switched on.
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_selection_add(selected: *const u16, key: *const u16) -> *mut u16 {
    give(&selection_add(&keys_of(&take(selected)), &take(key)))
}

/// The selection after `key` is removed.
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_selection_remove(selected: *const u16, key: *const u16) -> *mut u16 {
    give(&selection_remove(&keys_of(&take(selected)), &take(key)))
}

/// See [`refresh_inventory`]. Call it off the interface thread.
#[no_mangle]
pub extern "C" fn oi_refresh_inventory() -> *mut u16 {
    give(&refresh_inventory())
}

/// See [`states`].
#[no_mangle]
pub extern "C" fn oi_states() -> *mut u16 {
    give(&states())
}

/// See [`details`].
///
/// # Safety
/// `key` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_details(key: *const u16) -> *mut u16 {
    give(&details(&take(key)))
}

/// See [`profiles_menu`].
#[no_mangle]
pub extern "C" fn oi_profiles_menu() -> *mut u16 {
    give(&profiles_menu())
}

/// See [`winget_path`].
#[no_mangle]
pub extern "C" fn oi_winget() -> *mut u16 {
    give(&winget_path())
}

/// The remembered library view. With `test` non-zero nothing is read.
#[no_mangle]
pub extern "C" fn oi_library_view(test: i32) -> *mut u16 {
    give(&if test != 0 { VIEWS[0].to_string() } else { library_view_from(&view_path()) })
}

/// Remembers the library view. Empty on success, or "!" and the reason.
///
/// # Safety
/// `view` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_save_library_view(view: *const u16) -> *mut u16 {
    answer(save_library_view_to(&view_path(), &take(view)))
}

/// See [`save_selection`]. Empty on success, or "!" and the reason.
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_save_selection(path: *const u16, keys: *const u16) -> *mut u16 {
    answer(save_selection(&take(path), &keys_of(&take(keys))))
}

/// See [`setup_rows`]. Records, or "!" and the reason.
///
/// # Safety
/// `path` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_read_setup(path: *const u16) -> *mut u16 {
    give(&match setup_rows(&take(path), &inventory()) {
        Ok(rows) => records(rows.into_iter()),
        Err(reason) => refused(reason),
    })
}

/// See [`snapshot_rows`]. Records, or "!" then a title and a message separated by U+001F.
#[no_mangle]
pub extern "C" fn oi_snapshot_rows() -> *mut u16 {
    give(&match snapshot_rows(&inventory()) {
        Ok(rows) => records(rows.into_iter()),
        Err((title, message)) => refused(format!("{title}{FIELD}{message}")),
    })
}

/// See [`save_snapshot`]. Empty on success, or "!" and the reason.
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_save_snapshot(path: *const u16, keys: *const u16) -> *mut u16 {
    answer(save_snapshot(&take(path), &keys_of(&take(keys)), &inventory()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::RECORD;
    use oneinstall_core::model::PackageRecord;

    fn rows(text: &str) -> Vec<Vec<&str>> {
        text.split(RECORD).map(|record| record.split(FIELD).collect()).collect()
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let folder = std::env::temp_dir().join(format!("1nstall-rust-library-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        std::fs::create_dir_all(&folder).unwrap();
        folder
    }

    fn package(id: &str, version: &str) -> PackageRecord {
        PackageRecord { id: Some(id.to_string()), name: Some(format!("{id} name")), source: Some("winget".to_string()), installed_version: Some(version.to_string()) }
    }

    fn installed(packages: Vec<PackageRecord>) -> PackageInventory {
        PackageInventory { complete: true, partial: false, packages, message: None }
    }

    #[test]
    fn selecting_brings_requirements_and_removing_drops_dependents() {
        let peace = selection_add(&[], "peace");
        assert_eq!(peace.split(FIELD).collect::<Vec<_>>(), ["apo", "peace"]);
        let both = keys_of(&peace);
        // Removing the requirement removes the app that needs it; removing the app keeps the requirement.
        assert_eq!(selection_remove(&both, "apo"), "");
        assert_eq!(selection_remove(&both, "peace"), "apo");
        assert!(selection_add(&[], "no-such-app").starts_with('!'));
    }

    #[test]
    fn details_follow_the_catalog() {
        let shown = details("peace");
        let shown = rows(&shown);
        assert_eq!(shown[0][0], "Peace GUI");
        assert_eq!(shown.len(), 10);
        let value = |label: &str| shown.iter().find(|row| row.len() == 3 && row[1] == label).map(|row| row[2]).unwrap();
        assert_eq!(value("Method"), "Guided · publisher website");
        assert_eq!(value("Package IDs"), "No verified package identity");
        assert_eq!(value("Dependencies"), "Equalizer APO");
        assert_eq!(value("Installed state"), "Unknown");
        let seven_zip = details("extra_7zip");
        let seven_zip = rows(&seven_zip);
        assert_eq!(seven_zip.iter().find(|row| row.len() == 3 && row[1] == "Method").unwrap()[2], "Automatic · WinGet");
        assert_eq!(seven_zip.iter().find(|row| row.len() == 3 && row[1] == "Dependencies").unwrap()[2], "None declared");
        assert_eq!((seven_zip[0][3], seven_zip[0][4]), ("1", "1"));
        assert!(details("no-such-app").starts_with('!'));
    }

    #[test]
    fn every_built_in_profile_plans_and_is_listed_under_a_known_group() {
        let menu = profiles_menu();
        let menu = rows(&menu);
        assert_eq!(menu.len(), profile_rows().len());
        assert!(menu.iter().all(|profile| profile.len() == 6 && !profile[4].is_empty() && profile[4].split(ITEM).count() == profile[5].split(ITEM).count()));
    }

    #[test]
    fn the_library_view_is_remembered_and_anything_else_is_all_apps() {
        let path = scratch("view").join("preferences.json");
        assert_eq!(library_view_from(&path), "All apps");
        save_library_view_to(&path, "Installed").unwrap();
        assert_eq!(library_view_from(&path), "Installed");
        assert!(save_library_view_to(&path, "Everything").is_err());
        std::fs::write(&path, "{\"View\":\"installed\"}").unwrap();
        assert_eq!(library_view_from(&path), "Installed");
        for other in ["{\"View\":\"Everything\"}", "not json", ""] {
            std::fs::write(&path, other).unwrap();
            assert_eq!(library_view_from(&path), "All apps", "{other}");
        }
    }

    #[test]
    fn a_saved_selection_previews_with_states_and_refuses_bad_files() {
        let folder = scratch("setup");
        let file = folder.join("my-setup.json").to_string_lossy().into_owned();
        assert_eq!(save_selection(&file, &[]).unwrap_err(), "Select at least one app before saving a profile.");
        save_selection(&file, &["peace".to_string(), "extra_7zip".to_string()]).unwrap();
        let seven_zip_id = catalog().iter().find(|app| app.key == "extra_7zip").unwrap().ids[0].clone();
        let preview = setup_rows(&file, &installed(vec![package(&seven_zip_id, "24.09")])).unwrap();
        assert_eq!(preview.iter().map(|row| row[0].as_str()).collect::<Vec<_>>(), ["apo", "peace", "extra_7zip"]);
        assert_eq!(preview[0][2], "Manual installation required");
        assert!(preview[2][2].starts_with("Installed ·"), "{}", preview[2][2]);
        std::fs::write(&file, "{\"Version\":1,\"Apps\":[\"no-such-app\"]}").unwrap();
        assert!(setup_rows(&file, &PackageInventory::default()).is_err());
        std::fs::write(&file, "malformed").unwrap();
        assert!(setup_rows(&file, &PackageInventory::default()).is_err());
    }

    #[test]
    fn a_snapshot_records_identities_and_previews_against_this_catalog() {
        let folder = scratch("snapshot");
        let file = folder.join("installed-setup.json").to_string_lossy().into_owned();
        assert_eq!(snapshot_rows(&PackageInventory::default()).unwrap_err().0, "Inventory required");
        assert_eq!(snapshot_rows(&installed(Vec::new())).unwrap_err().0, "Nothing to save");
        let seven_zip_id = catalog().iter().find(|app| app.key == "extra_7zip").unwrap().ids[0].clone();
        let machine = installed(vec![package(&seven_zip_id, "24.09"), package("Example.Unlisted", "1.0")]);
        let offered = snapshot_rows(&machine).unwrap();
        assert_eq!(offered.len(), 2);
        assert_eq!(offered[0][0], format!("winget:{seven_zip_id}"));
        save_snapshot(&file, &[offered[0][0].clone(), offered[1][0].clone()], &machine).unwrap();
        // On a machine with nothing installed: the catalog app is offered, the other is not.
        let elsewhere = setup_rows(&file, &installed(Vec::new())).unwrap();
        assert_eq!((elsewhere[0][0].as_str(), elsewhere[0][2].as_str()), ("extra_7zip", "Missing · available in catalog · recorded version 24.09"));
        assert_eq!((elsewhere[1][0].as_str(), elsewhere[1][2].as_str()), ("", "Unavailable in this catalog · use the publisher or WinGet manually"));
        // On the machine it came from, the unlisted package is reported as already there.
        assert!(setup_rows(&file, &machine).unwrap()[1][2].starts_with("Already installed · Installed ·"));
    }

    #[test]
    fn states_cover_every_app_before_any_inventory() {
        let all = states();
        let all = rows(&all);
        assert_eq!(all.len(), catalog().len());
        assert!(all.iter().all(|row| row.len() == 2 && row[1] == "Unknown"));
    }
}
