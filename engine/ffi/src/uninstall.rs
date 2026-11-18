//! Uninstalling behind the interface: reading the installed apps, removing with the
//! publisher's own uninstaller, scanning for leftovers and cleaning the reviewed ones.
//!
//! One operation runs at a time, on a thread of its own inside the engine, as the tasks of
//! `OneInstallUninstall` do in 3.6. The interface starts one, asks what happened since it last
//! asked, and may ask a removal to stop after the current app. The engine keeps the apps and
//! the leftovers it found; the interface names them by id and by position.
//!
//! In the test modes only reading the installed apps is allowed. Everything that changes the
//! machine is refused.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use oneinstall_core::uninstall::format_bytes;
use oneinstall_core::InstalledApp;
use oneinstall_platform::inventory::inventory;
use oneinstall_platform::removal::{clean, load_history, remove, scan, take_progress, take_verified, LeftoverItem, RemovalResult};
use oneinstall_platform::WindowsHost;

use crate::{flag, give, in_test_environment, packages, records, take, FIELD};

static EVENTS: Mutex<VecDeque<Vec<String>>> = Mutex::new(VecDeque::new());
static RUNNING: AtomicBool = AtomicBool::new(false);
static STOP: AtomicBool = AtomicBool::new(false);
/// The installed apps of the last inventory.
static APPS: Mutex<Vec<InstalledApp>> = Mutex::new(Vec::new());
/// The apps removed earlier, whose leftovers may be checked. `None` until first needed.
static TARGETS: Mutex<Option<Vec<InstalledApp>>> = Mutex::new(None);
/// The leftovers of the last scan.
static LEFTOVERS: Mutex<Vec<LeftoverItem>> = Mutex::new(Vec::new());

fn emit(fields: &[&str]) {
    if let Ok(mut events) = EVENTS.lock() {
        events.push_back(fields.iter().map(|field| field.to_string()).collect());
    }
}

fn text(value: &Option<String>) -> &str {
    value.as_deref().unwrap_or("")
}

fn with_targets<T>(host: &WindowsHost, action: impl FnOnce(&mut Vec<InstalledApp>) -> T) -> T {
    let mut targets = TARGETS.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let loaded = targets.get_or_insert_with(|| if in_test_environment() { Vec::new() } else { load_history(host) });
    action(loaded)
}

/// How many removed apps are on record, whose leftovers a scan may check.
pub fn targets() -> usize {
    with_targets(&WindowsHost::new(), |targets| targets.len())
}

/// Reports the messages and the per-item outcomes of an operation, and writes each outcome
/// to the operation history, as the 3.6 timer does.
fn report(action: &str, result: &RemovalResult, log: &str) {
    for message in &result.messages {
        emit(&["message", message]);
    }
    let history = packages();
    for item in &result.results {
        emit(&["result", text(&item.id), text(&item.name), &item.outcome, text(&item.message), &item.exit_code.to_string(), text(&item.kind), text(&item.path)]);
        history.record(action, item.id.as_deref(), Some("Windows registration"), item.name.as_deref(), &item.outcome, text(&item.message), item.exit_code, Some(log));
    }
}

fn run_inventory(host: &WindowsHost) {
    let found = inventory(host);
    for app in &found.apps {
        emit(&[
            "app",
            text(&app.id),
            text(&app.name),
            &flag(app.publisher.is_some()),
            text(&app.publisher),
            text(&app.version),
            text(&app.kind),
            &app.size_kb.to_string(),
            &flag(app.can_remove),
        ]);
    }
    for warning in &found.warnings {
        emit(&["warning", warning]);
    }
    if let Ok(mut apps) = APPS.lock() {
        *apps = found.apps;
    }
}

fn run_remove(host: &WindowsHost, ids: &[String], log: &str) {
    let known = APPS.lock().map(|apps| apps.clone()).unwrap_or_default();
    let mut plan: Vec<InstalledApp> = ids.iter().filter_map(|id| known.iter().find(|app| app.id.as_deref() == Some(id.as_str())).cloned()).collect();
    let result = remove(host, &mut plan, &STOP, &mut |stage| emit(&["stage", stage.id.unwrap_or(""), stage.state]));
    report("Remove", &result, log);
    // The history now holds what was just removed: read it again, as 3.6 does.
    if let Ok(mut targets) = TARGETS.lock() {
        *targets = Some(load_history(host));
    }
}

fn run_scan(host: &WindowsHost, log: &str) -> Result<(), String> {
    let result = with_targets(host, |owners| scan(host, owners))?;
    report("Remove", &result, log);
    let folders: Vec<&LeftoverItem> = result.leftovers.iter().filter(|item| item.kind == "Folder").collect();
    let keys = result.leftovers.iter().filter(|item| item.kind == "Registry").count();
    let bytes: i64 = result.leftovers.iter().map(|item| item.bytes).sum();
    let folder_bytes: i64 = folders.iter().map(|item| item.bytes).sum();
    emit(&[
        "scan",
        &result.scanned_apps.to_string(),
        &result.incomplete_checks.to_string(),
        &folders.len().to_string(),
        &keys.to_string(),
        &format_bytes(host, bytes),
        &format_bytes(host, folder_bytes),
    ]);
    for (index, item) in result.leftovers.iter().enumerate() {
        emit(&[
            "leftover",
            &index.to_string(),
            text(&item.app_name),
            &item.kind,
            &item.confidence,
            &item.reason,
            &format_bytes(host, item.bytes),
            &flag(item.machine),
            &flag(item.view32),
            &item.path,
            &flag(item.value_name.is_some()),
            text(&item.display_value_name),
        ]);
    }
    if let Ok(mut leftovers) = LEFTOVERS.lock() {
        *leftovers = result.leftovers;
    }
    Ok(())
}

fn run_clean(host: &WindowsHost, positions: &[String], log: &str) -> Result<(), String> {
    let found = LEFTOVERS.lock().map(|leftovers| leftovers.clone()).unwrap_or_default();
    let chosen: Vec<LeftoverItem> = positions
        .iter()
        .filter_map(|position| position.parse::<usize>().ok())
        .filter_map(|position| found.get(position).cloned())
        .map(|mut item| {
            item.selected = true;
            item
        })
        .collect();
    let result = clean(host, &chosen)?;
    report("Cleanup", &result, log);
    let done = |kind: &str| result.results.iter().filter(|item| item.outcome == "Success" && item.kind.as_deref() == Some(kind)).count();
    let failed = result.results.iter().filter(|item| item.outcome != "Success").count();
    emit(&["clean", text(&result.backup_folder), &done("Folder").to_string(), &done("Registry").to_string(), &failed.to_string(), &format_bytes(host, result.recycled_bytes)]);
    Ok(())
}

/// Starts an operation: `Inventory`, `Remove` (app ids), `Scan`, or `Clean` (positions of
/// leftovers from the last scan). `log` is this session's log file, named in the history.
pub fn start(operation: &str, arguments: &[String], log: &str) -> Result<(), String> {
    if !matches!(operation, "Inventory" | "Remove" | "Scan" | "Clean") {
        return Err("Unknown operation.".to_string());
    }
    if operation != "Inventory" && in_test_environment() {
        return Err("Removing and cleaning are switched off in the test modes.".to_string());
    }
    if RUNNING.swap(true, Ordering::SeqCst) {
        return Err("A removal operation is already running.".to_string());
    }
    if let Ok(mut events) = EVENTS.lock() {
        events.clear();
    }
    let (operation, arguments, log) = (operation.to_string(), arguments.to_vec(), log.to_string());
    let label = operation.clone();
    let spawned = std::thread::Builder::new().name("uninstall".to_string()).spawn(move || {
        let host = WindowsHost::new();
        let outcome = match operation.as_str() {
            "Inventory" => {
                run_inventory(&host);
                Ok(())
            }
            "Remove" => {
                run_remove(&host, &arguments, &log);
                Ok(())
            }
            "Scan" => run_scan(&host, &log),
            _ => run_clean(&host, &arguments, &log),
        };
        if let Err(message) = outcome {
            emit(&["error", &message]);
        }
        emit(&["done", &operation]);
        RUNNING.store(false, Ordering::SeqCst);
    });
    if let Err(error) = spawned {
        RUNNING.store(false, Ordering::SeqCst);
        return Err(format!("{label}: {error}"));
    }
    Ok(())
}

/// Asks a removal to stop after the app it is on. The running uninstaller is never interrupted.
pub fn stop() {
    STOP.store(true, Ordering::SeqCst);
}

/// What happened since the last call, oldest first. Live text comes as `progress`, a verified
/// removal as `verified`, then the queued events: `stage`, and at the end of an operation its
/// `app`, `warning`, `message`, `result`, `scan`, `leftover`, `clean` or `error` records,
/// closed by `done` and the operation's name.
pub fn poll() -> String {
    let mut events: Vec<Vec<String>> = take_progress().into_iter().map(|text| vec!["progress".to_string(), text]).collect();
    events.extend(take_verified().into_iter().map(|id| vec!["verified".to_string(), id]));
    if let Ok(mut queued) = EVENTS.lock() {
        events.extend(queued.drain(..));
    }
    records(events.into_iter())
}

pub fn running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

/// See [`start`]. Arguments are separated by U+001F. Empty when started, or "!" and the reason.
///
/// # Safety
/// Every argument must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_uninstall_start(operation: *const u16, arguments: *const u16, log: *const u16) -> *mut u16 {
    let arguments: Vec<String> = take(arguments).split(FIELD).filter(|argument| !argument.is_empty()).map(str::to_string).collect();
    give(&start(&take(operation), &arguments, &take(log)).err().map(|reason| format!("!{reason}")).unwrap_or_default())
}

/// See [`stop`].
#[no_mangle]
pub extern "C" fn oi_uninstall_stop() {
    stop();
}

/// See [`poll`].
#[no_mangle]
pub extern "C" fn oi_uninstall_events() -> *mut u16 {
    give(&poll())
}

/// See [`targets`].
#[no_mangle]
pub extern "C" fn oi_uninstall_targets() -> i32 {
    i32::try_from(targets()).unwrap_or(i32::MAX)
}
