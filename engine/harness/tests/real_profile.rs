//! The files a 3.6 user already has, read by the Rust engine and by the 3.6 helpers.
//!
//! With `ONEINSTALL_READ_PROFILE=1` this reads the operation history and the removal history
//! in the profile of the current Windows user with the Rust engine, runs
//! `oracle\drivers\v36-profile.ps1` to read the same files with the 3.6 helpers, and compares
//! record counts and fingerprints. It only reads, and prints no content of the files.
#![cfg(windows)]

use std::process::Command;

use oneinstall_core::host::{Host, SpecialFolder};
use oneinstall_platform::packages::Packages;
use oneinstall_platform::removal::load_history;
use oneinstall_platform::{settings, WindowsHost};

/// FNV-1a, 64 bits, over the UTF-8 bytes: the same as the PowerShell driver computes.
fn fingerprint(text: &str) -> String {
    let mut hash: u64 = 14_695_981_039_346_656_037;
    for byte in text.bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    format!("{hash:016x}")
}

fn flag(value: bool) -> &'static str {
    if value {
        "1"
    } else {
        "0"
    }
}

#[test]
fn the_files_of_a_3_6_user_read_the_same_in_rust() {
    if std::env::var("ONEINSTALL_READ_PROFILE").as_deref() != Ok("1") {
        println!("real profile: skipped; set ONEINSTALL_READ_PROFILE=1 to read this user's 1nstall files (read-only)");
        return;
    }
    let host = WindowsHost::new();
    let text = |value: &Option<String>| value.clone().unwrap_or_default();
    let (rows, unreadable) = Packages::new(&host).history();
    let lines: Vec<String> = rows
        .iter()
        .map(|row| {
            [
                row.timestamp.clone(),
                row.action.clone(),
                text(&row.id),
                text(&row.source),
                text(&row.name),
                row.outcome.clone(),
                row.message.clone(),
                text(&row.log_path),
                row.exit_code.to_string(),
            ]
            .join("\u{1f}")
        })
        .collect();
    let operations = format!("profile operations: count={} unreadable={} fingerprint={}", rows.len(), flag(unreadable.is_some()), fingerprint(&lines.join("\u{1e}")));
    let apps = load_history(&host);
    let lines: Vec<String> = apps
        .iter()
        .map(|app| {
            [
                text(&app.id),
                text(&app.name),
                text(&app.publisher),
                text(&app.version),
                text(&app.kind),
                text(&app.location),
                text(&app.command),
                text(&app.registry_path),
                text(&app.package_family),
                flag(app.machine).to_string(),
                flag(app.view32).to_string(),
                flag(app.msi).to_string(),
                flag(app.removal_verified).to_string(),
                flag(app.ownership_verified).to_string(),
                flag(app.identity_verified).to_string(),
                app.restart_requested_at.to_string(),
                flag(app.can_remove).to_string(),
                app.size_kb.to_string(),
            ]
            .join("\u{1f}")
        })
        .collect();
    let removals = format!("profile removals: count={} fingerprint={}", apps.len(), fingerprint(&lines.join("\u{1e}")));
    println!("rust {operations}\nrust {removals}");

    let driver = concat!(env!("CARGO_MANIFEST_DIR"), "\\..\\..\\oracle\\drivers\\v36-profile.ps1");
    let output = Command::new("powershell.exe").args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", driver]).output().expect("Windows PowerShell");
    let recorded = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "the 3.6 driver failed: {}", String::from_utf8_lossy(&output.stderr));
    for line in recorded.lines() {
        println!("3.6  {line}");
    }
    let recorded: Vec<&str> = recorded.lines().map(str::trim).collect();
    assert_eq!(recorded, [operations.as_str(), removals.as_str()], "3.6 and Rust read this user's files differently");

    // The settings and the remembered view must read as valid values, whatever is saved.
    let saved = settings::load(&settings::settings_path(&host), &["en", "pt-PT"]);
    assert!(["System", "Light", "Dark"].contains(&saved.theme.as_str()));
    let view =
        oneinstall_engine::library::library_view_from(&std::path::Path::new(&host.special_folder(SpecialFolder::LocalApplicationData)).join("1nstall").join("preferences.json"));
    println!(
        "real profile: settings read as theme {}, accent {}, language {}, updates {}; view {view}",
        saved.theme,
        flag(saved.windows_accent),
        saved.language,
        flag(saved.auto_update)
    );
    println!("real profile: {} operations and {} removed apps read identically by 3.6 and by Rust", rows.len(), apps.len());
}
