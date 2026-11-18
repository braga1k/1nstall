//! Prototype 2 of 3: the install library screen as a web page in WebView2 (Tauri), over the Rust engine.
#![windows_subsystem = "windows"]

use std::sync::atomic::{AtomicU64, Ordering};

use prototype_model::{clock_ms, report, Library, Options};
use serde_json::Value;
use tauri::{AppHandle, State};

struct Shared {
    library: Library,
    startup_test: bool,
    select: Vec<String>,
    render_ms: AtomicU64,
}

#[tauri::command]
fn view(shared: State<Shared>) -> Value {
    let mut view = shared.library.to_json();
    view["Select"] = shared.select.clone().into();
    view
}

#[tauri::command]
fn plan(shared: State<Shared>, keys: Vec<String>) -> Value {
    shared.library.plan_json(&keys)
}

/// The slow WinGet inventory. `async` keeps it off the UI thread.
#[tauri::command(async)]
fn installed(shared: State<Shared>) -> Vec<String> {
    shared.library.installed_keys()
}

/// The page calls this from its first animation frame after the cards exist.
#[tauri::command]
fn rendered(shared: State<Shared>) {
    shared.render_ms.store(clock_ms(), Ordering::SeqCst);
}

/// The page calls this once that frame is on screen and it has nothing left to do.
#[tauri::command]
fn ready(shared: State<Shared>, app: AppHandle) -> bool {
    if shared.startup_test {
        report(shared.render_ms.load(Ordering::SeqCst), clock_ms());
        app.exit(0);
    }
    shared.startup_test
}

fn main() {
    let options = Options::from_args();
    // Keep the browser profile beside the program instead of in the user's profile.
    if let Some(folder) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|parent| parent.join("webview-data"))) {
        std::env::set_var("WEBVIEW2_USER_DATA_FOLDER", folder);
    }
    tauri::Builder::default()
        .manage(Shared { library: Library::load(&options.lang), startup_test: options.startup_test, select: options.select, render_ms: AtomicU64::new(0) })
        .invoke_handler(tauri::generate_handler![view, plan, installed, rendered, ready])
        .run(tauri::generate_context!())
        .expect("the window");
}
