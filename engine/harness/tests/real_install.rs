//! A real WinGet install through the install queue, exactly as the application starts it.
//!
//! It installs software, so it runs only where `ORACLE_DISPOSABLE=1` says the machine is
//! disposable: a CI runner, never a developer's PC. Phase 1 installed the same package through
//! 3.6 on the same images; 3.6 reported "Unknown" there because its verification could not
//! read the installed list before the source agreements were accepted.
#![cfg(windows)]

use std::time::{Duration, Instant};

use oneinstall_engine::library::{refresh_inventory, states, winget_path};
use oneinstall_engine::queue;

const APP: &str = "extra_sumatra";

#[test]
fn a_real_package_installs_and_is_verified() {
    if std::env::var("ORACLE_DISPOSABLE").as_deref() != Ok("1") {
        println!("oracle install: skipped; set ORACLE_DISPOSABLE=1 on a disposable machine to run it");
        return;
    }
    if winget_path().is_empty() {
        println!("oracle install: skipped; WinGet is not on this image");
        return;
    }
    let logs = std::env::temp_dir().join("1nstall-rust-real-install-logs");
    std::fs::create_dir_all(&logs).unwrap();
    queue::start(&[APP.to_string()], &logs.to_string_lossy()).unwrap();
    let mut statuses: Vec<String> = Vec::new();
    let mut log = String::new();
    let deadline = Instant::now() + Duration::from_secs(900);
    let mut done = false;
    while !done {
        assert!(Instant::now() < deadline, "the install did not finish in 15 minutes; statuses so far: {statuses:?}");
        std::thread::sleep(Duration::from_millis(250));
        let drained = queue::drain();
        for event in drained.split('\u{1e}').filter(|event| !event.is_empty()) {
            let fields: Vec<&str> = event.split('\u{1f}').collect();
            match fields[0] {
                "status" => statuses.push(fields[2].to_string()),
                "log" => log.push_str(fields[2]),
                "done" => done = true,
                _ => {}
            }
        }
    }
    let outcome = statuses.last().cloned().unwrap_or_default();
    println!("oracle install: {APP} through the queue -> {outcome}; steps: {}", statuses.join(" | "));
    // The library must agree once it asks WinGet again, as the application does after a queue.
    refresh_inventory();
    let state = states().split('\u{1e}').find_map(|record| record.strip_prefix(&format!("{APP}\u{1f}")).map(str::to_string)).unwrap_or_default();
    println!("oracle install: {APP} state after refresh -> {state}");
    assert_eq!(outcome, "Success", "{}", log.replace(['\r', '\n'], " "));
    assert!(state.starts_with("Installed ·"), "{state}");
}
