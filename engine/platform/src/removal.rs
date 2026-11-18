//! Removing apps, finding what they left behind and cleaning reviewed leftovers.
//!
//! Three separate steps, as in 3.6: `remove` runs the publisher's own uninstaller and verifies
//! the registration is gone; `scan` offers leftover candidates, none selected; `clean` removes
//! only the items it is given, re-checking each one first.

use std::collections::{HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use oneinstall_core::text::eq_ignore_case;
use oneinstall_core::{uninstall, Host, InstalledApp, SpecialFolder};
use serde_json::{json, Map, Value};

use crate::inventory::{self, compare_culture, AppInventory};
use crate::json::{app_from_json, app_to_json};
use crate::process::{self, run_captured, LaunchError, RunError};
use crate::recycle::recycle_folder;
use crate::registry::{Hive, Key};

/// Live text for whoever shows progress, as 3.6 keeps it in a static queue: what is being
/// removed, checked or cleaned right now. Nothing depends on it being read.
static PROGRESS: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());
/// Ids of apps whose removal has just been verified.
static VERIFIED: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());
/// Unread entries kept at most, so a caller that never reads cannot grow the queues.
const UNREAD_LIMIT: usize = 4096;

fn push(queue: &Mutex<VecDeque<String>>, text: String) {
    if let Ok(mut queue) = queue.lock() {
        if queue.len() < UNREAD_LIMIT {
            queue.push_back(text);
        }
    }
}

fn progress(text: String) {
    push(&PROGRESS, text);
}

fn verified(app: &InstalledApp) {
    push(&VERIFIED, app.id.clone().unwrap_or_default());
}

/// The progress text reported since the last call, oldest first.
pub fn take_progress() -> Vec<String> {
    PROGRESS.lock().map(|mut queue| queue.drain(..).collect()).unwrap_or_default()
}

/// The ids of removals verified since the last call.
pub fn take_verified() -> Vec<String> {
    VERIFIED.lock().map(|mut queue| queue.drain(..).collect()).unwrap_or_default()
}

/// Limit on entries examined per root, per registry hive view and per candidate folder.
const SCAN_LIMIT: usize = 20_000;

#[derive(Debug, Clone)]
pub struct LeftoverItem {
    pub app_name: Option<String>,
    /// `Folder` or `Registry`.
    pub kind: String,
    pub path: String,
    /// Set for a single registry value; `None` for a whole key or a folder.
    pub value_name: Option<String>,
    pub display_value_name: Option<String>,
    pub reason: String,
    pub owner: InstalledApp,
    pub machine: bool,
    pub view32: bool,
    pub selected: bool,
    /// `Linked path` (recorded location or executable trace) or `Name match`.
    pub confidence: String,
    pub bytes: i64,
    pub files: i32,
}

#[derive(Debug, Clone, Default)]
pub struct RemovalOutcome {
    pub id: Option<String>,
    pub name: Option<String>,
    pub outcome: String,
    pub message: Option<String>,
    pub exit_code: i32,
    pub kind: Option<String>,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct RemovalResult {
    pub leftovers: Vec<LeftoverItem>,
    pub messages: Vec<String>,
    pub backup_folder: Option<String>,
    pub scanned_apps: i32,
    pub incomplete_checks: i32,
    pub recycled_bytes: i64,
    pub results: Vec<RemovalOutcome>,
}

/// A failure inside one step of a removal or cleanup, with the outcome it maps to.
struct Failure {
    outcome: &'static str,
    message: String,
}

impl Failure {
    fn failed(message: impl Into<String>) -> Self {
        Self { outcome: "Failed", message: message.into() }
    }
}

impl From<LaunchError> for Failure {
    fn from(error: LaunchError) -> Self {
        // 1223: the user declined the elevation prompt.
        Self { outcome: if error.code == 1223 { "Cancelled" } else { "Failed" }, message: error.message }
    }
}

fn blank(text: &Option<String>) -> bool {
    text.as_deref().is_none_or(|text| text.trim().is_empty())
}

fn name_of(app: &InstalledApp) -> &str {
    app.name.as_deref().unwrap_or("")
}

fn hive_of(machine: bool) -> Hive {
    if machine {
        Hive::LocalMachine
    } else {
        Hive::CurrentUser
    }
}

fn ordinal_key(text: &str) -> String {
    text.chars().flat_map(char::to_uppercase).collect()
}

fn state_folder(host: &dyn Host) -> String {
    format!("{}\\1nstall", host.special_folder(SpecialFolder::LocalApplicationData))
}

/// Path of the removal history file.
pub fn history_file(host: &dyn Host) -> String {
    format!("{}\\uninstall-history.json", state_folder(host))
}

/// Apps removed through 1nstall, most recent last. A missing, unreadable or over-large
/// file gives an empty list.
pub fn load_history(host: &dyn Host) -> Vec<InstalledApp> {
    let path = history_file(host);
    if std::fs::metadata(&path).map(|data| data.len() > 1_048_576).unwrap_or(true) {
        return Vec::new();
    }
    let Ok(text) = std::fs::read_to_string(&path) else { return Vec::new() };
    let Ok(rows) = serde_json::from_str::<Value>(text.trim_start_matches('\u{feff}')) else { return Vec::new() };
    rows.as_array().map(|rows| rows.iter().filter(|row| row.is_object()).map(app_from_json).collect()).unwrap_or_default()
}

/// Records apps in the history, replacing earlier entries with the same id and keeping the last 100.
fn remember(host: &dyn Host, apps: &[InstalledApp]) -> Result<(), String> {
    let mut history = load_history(host);
    for app in apps {
        history.retain(|known| known.id != app.id);
        history.push(app.clone());
    }
    let skip = history.len().saturating_sub(100);
    let rows: Vec<Value> = history.iter().skip(skip).map(app_to_json).collect();
    std::fs::create_dir_all(state_folder(host)).map_err(|error| error.to_string())?;
    let path = history_file(host);
    // Written to a temporary file first, so an interrupted write never truncates the history.
    let temporary = format!("{path}.{}.tmp", random_hex(8));
    std::fs::write(&temporary, Value::Array(rows).to_string()).map_err(|error| error.to_string())?;
    std::fs::rename(&temporary, &path).map_err(|error| {
        let _ = std::fs::remove_file(&temporary);
        error.to_string()
    })
}

fn random_hex(length: usize) -> String {
    use std::hash::{BuildHasher, Hasher};
    let mut text = String::new();
    while text.len() < length {
        let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
        hasher.write_i64(process::now_filetime());
        text.push_str(&format!("{:016x}", hasher.finish()));
    }
    text.truncate(length);
    text
}

/// A stage of one app's removal, reported as it happens.
pub struct Stage<'a> {
    pub id: Option<&'a str>,
    pub name: Option<&'a str>,
    pub state: &'a str,
}

/// Removes apps one after another with their own uninstallers.
///
/// Each app's registration is re-read just before launch, so a stale list can never run an
/// old command. Exit code zero is not success: only the absence of the exact registration
/// afterwards is. `stop` is read between apps; the running uninstaller is never interrupted.
pub fn remove(host: &dyn Host, apps: &mut [InstalledApp], stop: &AtomicBool, on_stage: &mut dyn FnMut(Stage<'_>)) -> RemovalResult {
    stop.store(false, Ordering::SeqCst);
    let mut result = RemovalResult::default();
    let _ = remember(host, apps);
    for app in apps.iter_mut() {
        let mut item = RemovalOutcome { id: app.id.clone(), name: app.name.clone(), outcome: "Unknown".to_string(), ..RemovalOutcome::default() };
        app.removal_verified = false;
        if stop.load(Ordering::SeqCst) {
            item.outcome = "Cancelled".to_string();
            item.message = Some("Not started: stop after current requested.".to_string());
            result.messages.push(format!("{}: Not started: stop after current requested.", name_of(app)));
            on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: &item.outcome });
            result.results.push(item);
            continue;
        }
        on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: "Preparing\u{2026}" });
        progress(format!("Removing {}\u{2026} Finish any publisher dialog that opens.", name_of(app)));
        if let Err(failure) = remove_one(host, app, &mut item, &mut result.messages, on_stage) {
            item.outcome = failure.outcome.to_string();
            result.messages.push(format!("{}: {} \u{b7} {}", name_of(app), item.outcome, failure.message));
            item.message = Some(failure.message);
        }
        on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: &item.outcome });
        result.results.push(item);
    }
    // Cleanup is always a separate user action, including for zero-exit uninstallers.
    let _ = remember(host, apps);
    result
}

fn remove_one(host: &dyn Host, app: &mut InstalledApp, item: &mut RemovalOutcome, messages: &mut Vec<String>, on_stage: &mut dyn FnMut(Stage<'_>)) -> Result<(), Failure> {
    let mut settle = |app: &InstalledApp, item: &mut RemovalOutcome, outcome: &str, message: String| {
        item.outcome = outcome.to_string();
        messages.push(format!("{}: {}", name_of(app), message));
        item.message = Some(message);
    };
    if app.kind.as_deref() == Some("Microsoft Store") {
        let id = app.id.clone().unwrap_or_default();
        if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')) {
            return Err(Failure::failed("Invalid package identity."));
        }
        on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: "Removing\u{2026}" });
        let script = format!(
            "Get-AppxPackage | Where-Object {{ $_.PackageFullName -eq '{}' -and -not $_.NonRemovable -and -not $_.IsFramework }} | Remove-AppxPackage -ErrorAction Stop",
            id.replace('\'', "''")
        );
        inventory::run_powershell(host, &script, Duration::from_secs(180)).map_err(|message| {
            if message.starts_with("Windows app service did not respond") {
                Failure { outcome: "Unknown", message }
            } else {
                Failure::failed(message)
            }
        })?;
    } else {
        // Re-read the registration: a stale inventory must not launch an old command.
        let mut warnings = Vec::new();
        let current = inventory::desktop(host, &mut warnings, false).into_iter().find(|candidate| candidate.id == app.id);
        let Some(current) = current else {
            settle(app, item, "Success", "Exact registration already absent; ownership cannot be established for cleanup.".to_string());
            return Ok(());
        };
        // Ownership comes from the fresh registration, never from stale history or display names.
        // A location that was only inferred (from the icon or the uninstaller) is not carried over:
        // 3.6 did carry it, and then offered the uninstaller's own folder as the installation folder.
        app.location = if current.location_inferred { Some(String::new()) } else { current.location.clone() };
        app.name = current.name.clone();
        app.publisher = current.publisher.clone();
        app.identity_verified = true;
        app.ownership_verified = !blank(&app.location) && host.directory_exists(app.location.as_deref().unwrap_or(""));
        let command = uninstall::get_command(host, &current).map_err(|error| Failure::failed(error.message))?;
        on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: "Removing\u{2026}" });
        let launched_at = process::now_filetime();
        let launched = process::launch(&command.file_name, &command.arguments, app.machine, false)?;
        process::wait_for_uninstaller(&launched, launched_at).map_err(Failure::failed)?;
        let code = launched.exit_code();
        item.exit_code = code;
        if code == 3010 || code == 1641 {
            app.restart_requested_at = process::boot_time_ticks();
            settle(app, item, "Restart required", "Restart required. Cleanup withheld until Windows restarts and removal is verified.".to_string());
            return Ok(());
        }
        if code != 0 {
            let outcome = if code == 1602 || code == 1223 { "Cancelled" } else { "Failed" };
            settle(app, item, outcome, format!("Uninstaller returned {code}. No cleanup was started."));
            return Ok(());
        }
    }
    on_stage(Stage { id: app.id.as_deref(), name: app.name.as_deref(), state: "Verifying\u{2026}" });
    let after = inventory::inventory(host);
    let message = if app.kind.as_deref() == Some("Microsoft Store") && !after.warnings.is_empty() {
        "Store inventory unavailable; removal cannot be verified. Cleanup withheld."
    } else if inventory::registered(app, &after).map_err(Failure::failed)? {
        item.outcome = "Manual action required".to_string();
        "Still registered after the uninstaller finished. Finish publisher steps or restart, then refresh. Cleanup withheld."
    } else {
        item.outcome = "Success".to_string();
        app.removal_verified = true;
        verified(app);
        "Exact registration absence verified. Cleanup remains a separate review."
    };
    item.message = Some(message.to_string());
    messages.push(format!("{}: {} \u{b7} {}", name_of(app), item.outcome, message));
    Ok(())
}

/// Size and file count of a folder tree. `Ok(None)` when it holds a reparse point or more
/// than the scan limit: such a folder is never offered.
fn measure_folder(root: &str) -> Result<Option<(i64, i32)>, String> {
    let (mut bytes, mut files, mut seen) = (0i64, 0i32, 0usize);
    let mut pending = vec![root.to_string()];
    while let Some(folder) = pending.pop() {
        for entry in std::fs::read_dir(&folder).map_err(|error| error.to_string())? {
            let entry = entry.map_err(|error| error.to_string())?;
            seen += 1;
            if seen > SCAN_LIMIT {
                return Ok(None);
            }
            let path = entry.path().to_string_lossy().into_owned();
            let Some(flags) = crate::attributes(&path) else { return Err(format!("Could not read attributes of {path}.")) };
            if flags & 0x400 != 0 {
                return Ok(None);
            }
            if flags & 0x10 != 0 {
                pending.push(path);
            } else {
                bytes += entry.metadata().map_err(|error| error.to_string())?.len() as i64;
                files += 1;
            }
        }
    }
    Ok(Some((bytes, files)))
}

struct Scan<'a> {
    host: &'a dyn Host,
    active: &'a [InstalledApp],
    result: &'a mut RemovalResult,
    seen: &'a mut HashSet<String>,
}

impl Scan<'_> {
    fn add_folder(&mut self, folder: &str, app: &InstalledApp) -> Result<(), String> {
        let Some((bytes, files)) = measure_folder(folder)? else {
            self.result.incomplete_checks += 1;
            self.result.messages.push(format!("{folder}: linked files or scan limit; folder kept."));
            return Ok(());
        };
        let full = uninstall::full(self.host, folder).ok_or_else(|| format!("{folder} is not a usable path."))?;
        let recorded = app.ownership_verified
            && !blank(&app.location)
            && uninstall::full(self.host, app.location.as_deref().unwrap_or("")).is_some_and(|location| eq_ignore_case(&full, &location));
        if self.seen.insert(ordinal_key(&full)) {
            self.result.leftovers.push(LeftoverItem {
                app_name: app.name.clone(),
                kind: "Folder".to_string(),
                path: folder.to_string(),
                value_name: None,
                display_value_name: None,
                reason: if recorded { "Recorded installation folder" } else { "Exact product name; may contain settings or saved data" }.to_string(),
                owner: app.clone(),
                machine: false,
                view32: false,
                selected: false,
                confidence: if recorded { "Linked path" } else { "Name match" }.to_string(),
                bytes,
                files,
            });
        }
        Ok(())
    }

    fn discover_folders(&mut self, root: &str, depth: u32, app: &InstalledApp, count: &mut usize) {
        if !self.host.directory_exists(root) {
            return;
        }
        if let Err(error) = self.discover_folders_in(root, depth, app, count) {
            self.result.incomplete_checks += 1;
            self.result.messages.push(format!("{}: folder discovery skipped {root}: {error}", name_of(app)));
        }
    }

    fn discover_folders_in(&mut self, root: &str, depth: u32, app: &InstalledApp, count: &mut usize) -> Result<(), String> {
        for entry in std::fs::read_dir(root).map_err(|error| error.to_string())? {
            let entry = entry.map_err(|error| error.to_string())?;
            let folder = entry.path().to_string_lossy().into_owned();
            let Some(flags) = crate::attributes(&folder) else { return Err(format!("Could not read attributes of {folder}.")) };
            if flags & 0x10 == 0 {
                continue;
            }
            *count += 1;
            if *count > SCAN_LIMIT {
                self.result.incomplete_checks += 1;
                self.result.messages.push(format!("{}: folder discovery limit reached; results may be incomplete.", name_of(app)));
                return Ok(());
            }
            if flags & 0x400 != 0 {
                continue;
            }
            if uninstall::safe_directory(self.host, &folder, app, self.active) {
                self.add_folder(&folder, app)?;
            } else if depth < 2 {
                let full = uninstall::full(self.host, &folder);
                let inside_installed = self.active.iter().any(|other| {
                    !blank(&other.location)
                        && full
                            .as_deref()
                            .is_some_and(|full| uninstall::full(self.host, other.location.as_deref().unwrap_or("")).is_some_and(|location| uninstall::inside(full, &location)))
                });
                let leaf = entry.file_name().to_string_lossy().to_lowercase();
                let reserved = matches!(leaf.as_str(), "microsoft" | "windows" | "windowsapps" | "packages" | "common files" | "1nstall");
                if !inside_installed && !reserved {
                    self.discover_folders(&folder, depth + 1, app, count);
                }
            }
            if *count > SCAN_LIMIT {
                return Ok(());
            }
        }
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn discover_keys(&mut self, root: &Key, path: &str, depth: u32, machine: bool, view32: bool, app: &InstalledApp, count: &mut usize) {
        if let Err(error) = self.discover_keys_in(root, path, depth, machine, view32, app, count) {
            self.result.incomplete_checks += 1;
            self.result.messages.push(format!("{}: registry discovery skipped {path}: {error}", name_of(app)));
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn discover_keys_in(&mut self, root: &Key, path: &str, depth: u32, machine: bool, view32: bool, app: &InstalledApp, count: &mut usize) -> Result<(), String> {
        for name in root.sub_key_names()? {
            *count += 1;
            if *count > SCAN_LIMIT {
                self.result.incomplete_checks += 1;
                self.result.messages.push(format!("{}: registry discovery limit reached; results may be incomplete.", name_of(app)));
                return Ok(());
            }
            if uninstall::reserved_registry_name(&name) {
                continue;
            }
            let key = format!("{path}\\{name}");
            let Some(child) = root.open_child(&name)? else { continue };
            if uninstall::safe_registry(self.host, Some(&key), app, self.active) {
                if self.seen.insert(ordinal_key(&format!("{}{key}", scope(machine, view32)))) {
                    self.result.leftovers.push(LeftoverItem {
                        app_name: app.name.clone(),
                        kind: "Registry".to_string(),
                        path: key,
                        value_name: None,
                        display_value_name: None,
                        reason: "Exact product key; registry backup before removal".to_string(),
                        owner: app.clone(),
                        machine,
                        view32,
                        selected: false,
                        confidence: "Name match".to_string(),
                        bytes: 0,
                        files: 0,
                    });
                }
            } else if depth < 2 {
                self.discover_keys(&child, &key, depth + 1, machine, view32, app, count);
            }
            if *count > SCAN_LIMIT {
                return Ok(());
            }
        }
        Ok(())
    }

    fn discover_traces(&mut self, machine: bool, view32: bool, app: &InstalledApp) {
        for key in uninstall::TRACE_KEYS {
            let values = match Key::open(hive_of(machine), view32, key).and_then(|trace| trace.map(|trace| trace.value_names()).transpose()) {
                Ok(Some(values)) => values,
                Ok(None) => continue,
                Err(error) => {
                    self.result.incomplete_checks += 1;
                    self.result.messages.push(format!("{}: Windows trace check skipped: {error}", name_of(app)));
                    continue;
                }
            };
            for value in values {
                if app.ownership_verified
                    && uninstall::safe_registry_value(self.host, key, Some(&value), app, self.active)
                    && self.seen.insert(ordinal_key(&format!("{}{key}::{value}", scope(machine, view32))))
                {
                    self.result.leftovers.push(LeftoverItem {
                        app_name: app.name.clone(),
                        kind: "Registry".to_string(),
                        path: key.to_string(),
                        display_value_name: Some(uninstall::trace_path(self.host, key, &value)),
                        value_name: Some(value),
                        reason: "Windows executable trace; only this value is removed".to_string(),
                        owner: app.clone(),
                        machine,
                        view32,
                        selected: false,
                        confidence: "Linked path".to_string(),
                        bytes: 0,
                        files: 0,
                    });
                }
            }
        }
    }
}

/// Deduplication scope of a registry candidate: the two views of the per-user hive count as one.
fn scope(machine: bool, view32: bool) -> String {
    if machine {
        format!("HKLM{}", if view32 { "True" } else { "False" })
    } else {
        "HKCU".to_string()
    }
}

/// The apps whose names, publishers and locations protect folders and keys from cleanup:
/// every desktop registration, hidden ones included, plus Store packages.
fn protection(host: &dyn Host, inventory: &AppInventory) -> Result<Vec<InstalledApp>, ()> {
    let mut warnings = Vec::new();
    let mut active = inventory::desktop(host, &mut warnings, true);
    if !warnings.is_empty() {
        return Err(());
    }
    active.extend(inventory.apps.iter().filter(|app| app.kind.as_deref() == Some("Microsoft Store")).cloned());
    Ok(active)
}

/// Looks for what removed apps left behind. Nothing is selected and nothing is deleted.
///
/// An app is only scanned once its registration is verifiably gone and its identity or
/// ownership was captured at removal time. Discovery is bounded: known roots, three levels,
/// a fixed number of entries. An empty result does not prove nothing was left.
pub fn scan(host: &dyn Host, owners: &mut [InstalledApp]) -> Result<RemovalResult, String> {
    let mut result = RemovalResult::default();
    let installed = inventory::inventory(host);
    let active = protection(host, &installed).map_err(|_| "Installed-app protection could not be verified. No leftover scan was offered.".to_string())?;
    let boot_time = process::boot_time_ticks();
    let mut seen: HashSet<String> = HashSet::new();
    for app in owners.iter_mut() {
        let name = name_of(app).to_string();
        progress(format!("Checking leftovers for {name}\u{2026}"));
        if uninstall::waiting_for_restart(app, boot_time) {
            result.messages.push(format!("{name}: restart Windows before scanning leftovers."));
            continue;
        }
        let store = app.kind.as_deref() == Some("Microsoft Store");
        if store && !installed.warnings.is_empty() {
            result.messages.push(format!("{name}: Store inventory unavailable; cleanup withheld."));
            continue;
        }
        if inventory::registered(app, &installed)? {
            result.messages.push(format!("{name}: still registered. Finish removal or restart, then check again."));
            continue;
        }
        // Store package data is managed by Windows; there is no manual cleanup of it.
        if store {
            result.messages.push(format!("{name}: removed; Windows manages its package data."));
            continue;
        }
        // A bootstrap uninstaller may have exited while a child still showed publisher UI.
        // A later explicit check finishes the verification from the captured identity.
        if !app.removal_verified && (app.identity_verified || app.ownership_verified) {
            app.removal_verified = true;
            let _ = remember(host, std::slice::from_ref(app));
            result.results.push(RemovalOutcome {
                id: app.id.clone(),
                name: app.name.clone(),
                outcome: "Success".to_string(),
                message: Some("Removal verified on recheck: recorded registration is absent.".to_string()),
                ..RemovalOutcome::default()
            });
            verified(app);
            result.messages.push(format!("{name}: removal now verified; the recorded registration is absent."));
        }
        if !app.removal_verified || !(app.identity_verified || app.ownership_verified) {
            result.messages.push(format!("{name}: removal evidence is unavailable. Cleanup withheld."));
            continue;
        }
        result.scanned_apps += 1;
        let app_view = app.clone();
        let mut scan = Scan { host, active: &active, result: &mut result, seen: &mut seen };
        if !blank(&app_view.location) {
            if let Some(full) = uninstall::full(host, app_view.location.as_deref().unwrap_or("")) {
                if app_view.ownership_verified && uninstall::safe_directory(host, &full, &app_view, &active) {
                    if let Err(error) = scan.add_folder(&full, &app_view) {
                        scan.result.incomplete_checks += 1;
                        scan.result.messages.push(format!("{name}: installation folder check skipped: {error}"));
                    }
                }
            }
        }
        for root in uninstall::data_roots(host) {
            progress(format!("{name} \u{b7} Disk \u{b7} {root}"));
            let mut count = 0usize;
            scan.discover_folders(&root, 0, &app_view, &mut count);
        }
        for machine in [false, true] {
            for view32 in [false, true] {
                progress(format!("{name} \u{b7} Registry \u{b7} {}{}", if machine { "HKLM" } else { "HKCU" }, if view32 { " 32-bit" } else { " 64-bit" }));
                match Key::open(hive_of(machine), view32, "Software") {
                    Ok(Some(software)) => {
                        let mut count = 0usize;
                        scan.discover_keys(&software, "Software", 0, machine, view32, &app_view, &mut count);
                    }
                    Ok(None) => {}
                    Err(error) => {
                        scan.result.incomplete_checks += 1;
                        scan.result.messages.push(format!("{name}: registry discovery skipped Software: {error}"));
                    }
                }
                scan.discover_traces(machine, view32, &app_view);
            }
        }
        result.messages.push(format!("{name}: checked installation folder, Roaming/Local/LocalLow AppData, ProgramData, Program Files, product registry keys and Windows executable traces. Name matches require your review; no matches does not prove every residue is absent."));
    }
    result.leftovers.sort_by(|left, right| {
        compare_culture(&left.kind, &right.kind, false)
            .then_with(|| compare_culture(left.app_name.as_deref().unwrap_or(""), right.app_name.as_deref().unwrap_or(""), false))
            .then_with(|| compare_culture(&left.path, &right.path, false))
    });
    Ok(result)
}

fn leftover_to_json(item: &LeftoverItem) -> Value {
    let detail = format!(
        "{}  \u{b7}  {}{}",
        item.reason,
        item.path,
        item.value_name.as_ref().map(|value| format!("  \u{2192}  {}", item.display_value_name.as_deref().unwrap_or(value))).unwrap_or_default()
    );
    let mut row = Map::new();
    row.insert("AppName".into(), json!(item.app_name));
    row.insert("Kind".into(), json!(item.kind));
    row.insert("Path".into(), json!(item.path));
    row.insert("ValueName".into(), json!(item.value_name));
    row.insert("DisplayValueName".into(), json!(item.display_value_name));
    row.insert("Reason".into(), json!(item.reason));
    row.insert("Owner".into(), app_to_json(&item.owner));
    row.insert("Machine".into(), json!(item.machine));
    row.insert("View32".into(), json!(item.view32));
    row.insert("Selected".into(), json!(item.selected));
    row.insert("Confidence".into(), json!(item.confidence));
    row.insert("Bytes".into(), json!(item.bytes));
    row.insert("Files".into(), json!(item.files));
    row.insert("Detail".into(), json!(detail));
    Value::Object(row)
}

fn outcome_to_json(outcome: &RemovalOutcome) -> Value {
    let mut row = Map::new();
    row.insert("Id".into(), json!(outcome.id));
    row.insert("Name".into(), json!(outcome.name));
    row.insert("Outcome".into(), json!(outcome.outcome));
    row.insert("Message".into(), json!(outcome.message));
    row.insert("ExitCode".into(), json!(outcome.exit_code));
    row.insert("Kind".into(), json!(outcome.kind));
    row.insert("Path".into(), json!(outcome.path));
    Value::Object(row)
}

#[link(name = "kernel32")]
extern "system" {
    fn GetLocalTime(time: *mut [u16; 8]);
}

/// Local time as `yyyyMMdd-HHmmss`.
fn local_stamp() -> String {
    let mut time = [0u16; 8];
    // SAFETY: SYSTEMTIME is eight 16-bit fields.
    unsafe { GetLocalTime(&mut time) };
    format!("{:04}{:02}{:02}-{:02}{:02}{:02}", time[0], time[1], time[3], time[4], time[5], time[6])
}

/// Removes exactly the reviewed items, each after its own fresh checks.
///
/// Folders go to the Recycle Bin. A registry key or value is exported to a `.reg` backup
/// before it is deleted, and is kept if the backup fails. One item failing does not stop
/// the others.
pub fn clean(host: &dyn Host, items: &[LeftoverItem]) -> Result<RemovalResult, String> {
    let mut result = RemovalResult::default();
    let installed = inventory::inventory(host);
    protection(host, &installed).map_err(|_| "Installed-app protection could not be verified; cleanup stopped.".to_string())?;
    let backup_folder = format!("{}\\Backups\\{}-{}", state_folder(host), local_stamp(), random_hex(8));
    std::fs::create_dir_all(&backup_folder).map_err(|error| error.to_string())?;
    std::fs::write(format!("{backup_folder}\\items.json"), Value::Array(items.iter().map(leftover_to_json).collect()).to_string()).map_err(|error| error.to_string())?;
    result.backup_folder = Some(backup_folder.clone());
    let boot_time = process::boot_time_ticks();
    for item in items {
        let mut outcome = RemovalOutcome {
            id: item.owner.id.clone(),
            name: item.app_name.clone(),
            kind: Some(item.kind.clone()),
            path: Some(item.path.clone()),
            outcome: "Unknown".to_string(),
            ..RemovalOutcome::default()
        };
        progress(format!("Removing reviewed leftover: {}", item.path));
        match clean_one(host, item, &installed, boot_time, &backup_folder, &mut result) {
            Ok(message) => {
                outcome.outcome = "Success".to_string();
                outcome.message = Some(message.to_string());
            }
            Err(failure) => {
                outcome.outcome = failure.outcome.to_string();
                result.messages.push(format!("{}: not completed \u{b7} {}", item.path, failure.message));
                outcome.message = Some(failure.message);
            }
        }
        result.results.push(outcome);
    }
    std::fs::write(format!("{backup_folder}\\results.json"), Value::Array(result.results.iter().map(outcome_to_json).collect()).to_string()).map_err(|error| error.to_string())?;
    Ok(result)
}

fn clean_one(host: &dyn Host, item: &LeftoverItem, installed: &AppInventory, boot_time: i64, backup_folder: &str, result: &mut RemovalResult) -> Result<&'static str, Failure> {
    // Other registrations are re-read after any preceding uninstaller or elevation prompt.
    let active = protection(host, installed).map_err(|_| Failure::failed("Shared-app protection could not be refreshed."))?;
    let owner = &item.owner;
    if !owner.removal_verified
        || !(owner.identity_verified || owner.ownership_verified)
        || uninstall::waiting_for_restart(owner, boot_time)
        || inventory::registered(owner, installed).map_err(Failure::failed)?
    {
        return Err(Failure::failed("Removal is unverified, the app is registered or waiting for a restart; cleanup was blocked."));
    }
    if item.kind == "Folder" {
        let measured = if uninstall::discovery_folder(host, &item.path, owner) && uninstall::safe_directory(host, &item.path, owner, &active) {
            measure_folder(&item.path).ok().flatten()
        } else {
            None
        };
        let Some((bytes, _)) = measured else { return Err(Failure::failed("Folder scope/protection changed; cleanup was blocked.")) };
        recycle_folder(&item.path).map_err(Failure::failed)?;
        result.recycled_bytes += bytes;
        result.messages.push(format!("{}: sent to Recycle Bin.", item.path));
        return Ok("Reviewed folder recycled; original location absence verified.");
    }
    if item.kind != "Registry" {
        return Err(Failure::failed("Unknown leftover kind; cleanup was blocked."));
    }
    let still_safe = match item.value_name.as_deref() {
        None => uninstall::safe_registry(host, Some(&item.path), owner, &active),
        Some(value) => owner.ownership_verified && uninstall::safe_registry_value(host, &item.path, Some(value), owner, &active),
    };
    if !still_safe {
        return Err(Failure::failed("Registry scope/protection changed; cleanup was blocked."));
    }
    let key = format!("{}\\{}", if item.machine { "HKLM" } else { "HKCU" }, item.path);
    let view = if item.view32 { "32" } else { "64" };
    let reg = format!("{}\\reg.exe", host.special_folder(SpecialFolder::System));
    let backup = format!("{backup_folder}\\{}.reg", random_hex(32));
    let exported = match run_captured(&reg, &format!("export {} {} /y /reg:{view}", uninstall::quote_argument(&key), uninstall::quote_argument(&backup)), None) {
        Ok(run) => run.exit_code == 0,
        Err(RunError::Start(_)) | Err(RunError::TimedOut) => false,
    };
    if !exported || std::fs::metadata(&backup).map(|data| data.len() < 10).unwrap_or(true) {
        return Err(Failure::failed("Registry backup failed; key was kept."));
    }
    let instructions =
        format!("{key} ({view}-bit)\r\nTo restore from Command Prompt{}:\r\nreg.exe import \"{backup}\" /reg:{view}\r\n\r\n", if item.machine { " as administrator" } else { "" });
    {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new().create(true).append(true).open(format!("{backup_folder}\\RESTORE.txt")).map_err(|error| Failure::failed(error.to_string()))?;
        file.write_all(instructions.as_bytes()).map_err(|error| Failure::failed(error.to_string()))?;
    }
    let value_argument = item.value_name.as_deref().map(|value| format!(" /v {}", uninstall::quote_argument(value))).unwrap_or_default();
    let deletion = process::launch(&reg, &format!("delete {}{value_argument} /f /reg:{view}", uninstall::quote_argument(&key)), item.machine, true)?;
    deletion.wait();
    if deletion.exit_code() != 0 {
        return Err(Failure::failed("Registry removal was cancelled or failed; backup is available."));
    }
    let remaining = Key::open(hive_of(item.machine), item.view32, &item.path).map_err(Failure::failed)?;
    let remains = match (&remaining, item.value_name.as_deref()) {
        (None, _) => false,
        (Some(_), None) => true,
        (Some(key), Some(value)) => key.value_names().map_err(Failure::failed)?.iter().any(|name| eq_ignore_case(name, value)),
    };
    if remains {
        return Err(Failure::failed("Registry item remains; cleanup was not verified. Backup is available."));
    }
    result.messages.push(format!("{key}{}: removed; .reg backup saved.", item.value_name.as_deref().map(|value| format!(" :: {value}")).unwrap_or_default()));
    Ok("Reviewed registry item absence verified; registry backup saved.")
}
