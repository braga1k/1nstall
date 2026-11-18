//! The install queue behind the interface. The queue runs on a thread of its own inside the
//! engine; the interface starts it, asks for what happened since it last asked, and may ask
//! it to stop after the current app. This is the worker of `vexan_installers.ps1`, with the
//! queue rules themselves in `oneinstall_core::queue`.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use oneinstall_core::queue::{plan, run_queue, CatalogApp, InstallReport, Installer, QueueEvent};
use oneinstall_platform::packages::Packages;

use crate::{catalog, give, install_packages, records, take, FIELD};

static EVENTS: Mutex<VecDeque<Vec<String>>> = Mutex::new(VecDeque::new());
static RUNNING: AtomicBool = AtomicBool::new(false);
static STOP: AtomicBool = AtomicBool::new(false);

fn emit(kind: &str, key: &str, text: &str) {
    if let Ok(mut events) = EVENTS.lock() {
        events.push_back(vec![kind.to_string(), key.to_string(), text.to_string()]);
    }
}

/// Installs through WinGet and writes the operation history, as 3.6 does.
struct WinGetInstaller {
    packages: Packages,
    logs: String,
}

impl Installer for WinGetInstaller {
    fn install(&mut self, id: &str, app: &CatalogApp, verifying: &mut dyn FnMut()) -> Result<InstallReport, String> {
        let record = self.packages.install(id, "winget", &app.name, &self.logs, Some(verifying));
        Ok(InstallReport { outcome: record.outcome.clone(), detail: record.detail() })
    }

    fn record(&mut self, id: &str, source: &str, name: &str, outcome: &str, message: &str) {
        self.packages.record("Install", Some(id), Some(source), Some(name), outcome, message, 0, None);
    }
}

/// Starts installing the given apps, with what they require, in order. `logs` is the folder
/// for installer logs. Refused when a queue is already running or the plan is not valid.
pub fn start(keys: &[String], logs: &str) -> Result<(), String> {
    let packages = install_packages()?;
    let planned: Vec<CatalogApp> = plan(catalog(), keys).map_err(|error| error.message)?.into_iter().cloned().collect();
    if RUNNING.swap(true, Ordering::SeqCst) {
        return Err("A queue is already running.".to_string());
    }
    STOP.store(false, Ordering::SeqCst);
    if let Ok(mut events) = EVENTS.lock() {
        events.clear();
    }
    let mut installer = WinGetInstaller { packages, logs: logs.to_string() };
    let spawned = std::thread::Builder::new().name("install queue".to_string()).spawn(move || {
        let planned: Vec<&CatalogApp> = planned.iter().collect();
        run_queue(&planned, &|| STOP.load(Ordering::SeqCst), &mut installer, &mut |event| match event {
            QueueEvent::Status { key, text } => emit("status", &key, &text),
            QueueEvent::Progress { key } => emit("progress", &key, ""),
            QueueEvent::Url { key, url } => emit("url", &key, &url),
            QueueEvent::Log { key, text } => emit("log", &key, &text),
        });
        emit("done", "", "");
        RUNNING.store(false, Ordering::SeqCst);
    });
    if let Err(error) = spawned {
        RUNNING.store(false, Ordering::SeqCst);
        return Err(error.to_string());
    }
    Ok(())
}

/// Asks the queue to stop after the app it is on. Apps not started are recorded as cancelled.
pub fn stop() {
    STOP.store(true, Ordering::SeqCst);
}

/// What happened since the last call, oldest first, one record each: kind, app key, text.
/// The kinds are `status`, `progress`, `url`, `log` and, once, `done`.
pub fn drain() -> String {
    let events: Vec<Vec<String>> = EVENTS.lock().map(|mut events| events.drain(..).collect()).unwrap_or_default();
    records(events.into_iter())
}

pub fn running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

/// See [`start`]. Empty when started, or "!" and the reason.
///
/// # Safety
/// Both arguments must be null or point to NUL-terminated UTF-16 strings.
#[no_mangle]
pub unsafe extern "C" fn oi_queue_start(keys: *const u16, logs: *const u16) -> *mut u16 {
    let keys: Vec<String> = take(keys).split(FIELD).filter(|key| !key.is_empty()).map(str::to_string).collect();
    give(&start(&keys, &take(logs)).err().map(|reason| format!("!{reason}")).unwrap_or_default())
}

/// See [`stop`].
#[no_mangle]
pub extern "C" fn oi_queue_stop() {
    stop();
}

/// See [`drain`].
#[no_mangle]
pub extern "C" fn oi_queue_events() -> *mut u16 {
    give(&drain())
}
