//! The install-side regressions of 3.6 (`tests/reliability.ps1`), against the Rust engine.
//! Only a temporary folder is written, and the "WinGet" is a stand-in that installs nothing.
#![cfg(windows)]

use std::path::PathBuf;

use oneinstall_core::packages::quote;
use oneinstall_core::uninstall::quote_argument;
use oneinstall_platform::packages::{find_winget, read_setup, run, save_setup, Packages, SetupDraft};
use oneinstall_platform::WindowsHost;

const FIXTURE: &str = env!("CARGO_BIN_EXE_oracle-fixture");

/// A fresh temporary folder, removed when dropped.
struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Self {
        let folder = std::env::temp_dir().join(format!("1nstall-rust-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        std::fs::create_dir_all(&folder).expect("scratch folder");
        Self(folder)
    }
    fn path(&self, name: &str) -> String {
        self.0.join(name).to_string_lossy().into_owned()
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn winget_is_found_at_the_explicit_path_and_then_on_path() {
    let host = WindowsHost::new();
    let scratch = Scratch::new("find");
    assert_eq!(find_winget(&host, FIXTURE, ""), FIXTURE);
    let on_path = scratch.path("winget.exe");
    std::fs::write(&on_path, "fixture").unwrap();
    assert_eq!(find_winget(&host, &scratch.path("missing.exe"), &scratch.path("")), on_path);
    assert_eq!(find_winget(&host, &scratch.path("missing.exe"), ";  ;"), "");
}

#[test]
fn quoted_arguments_reach_the_program_unchanged() {
    let arguments = ["", "path with spaces\\", "quote\" and trailing\\", "normal", "a&b", "C:\\folder\\"];
    let line = arguments.iter().map(|argument| quote(argument).unwrap()).collect::<Vec<_>>().join(" ");
    let result = run(FIXTURE, &line, 10_000).unwrap();
    let received: Vec<String> = serde_json::from_str(&result.output).unwrap();
    assert_eq!(received, arguments);
    assert_eq!(quote_argument("C:\\folder\\"), quote("C:\\folder\\").unwrap());
}

#[test]
fn both_output_pipes_are_drained_without_blocking() {
    let result = run(FIXTURE, "pipes", 10_000).unwrap();
    assert_eq!((result.output.len(), result.error.len()), (200_000, 200_000));
}

#[test]
fn an_installer_outcome_is_never_upgraded_to_success_without_verification() {
    let scratch = Scratch::new("install");
    let packages = Packages::with(&scratch.path("data"), FIXTURE);
    let logs = scratch.path("logs");
    assert_eq!(packages.install("Fixture.Failure", "winget", "Fixture", &logs, None).outcome, "Failed");
    assert_eq!(packages.install("Fixture.Restart", "winget", "Fixture", &logs, None).outcome, "Restart required");
    assert_eq!(packages.install("Fixture.Cancelled", "winget", "Fixture", &logs, None).outcome, "Cancelled");
    let offline = packages.install("Fixture.Offline", "winget", "Fixture", &logs, None);
    assert_eq!(offline.outcome, "Failed");
    assert!(offline.message.contains("connectivity"));
    // Exit code zero, but the stand-in cannot confirm an installed identity.
    assert_eq!(packages.install("Fixture.Success", "winget", "Fixture", &logs, None).outcome, "Unknown");
    let mut verifications = 0;
    let verified = packages.install("Fixture.Success", "winget", "Fixture", &logs, Some(&mut || verifications += 1));
    assert_eq!((verifications, verified.outcome.as_str()), (1, "Unknown"));
    let missing = Packages::with(&scratch.path("data"), &scratch.path("missing.exe"));
    assert_eq!(missing.install("Fixture.App", "winget", "Fixture", &logs, None).outcome, "Failed");
    let (history, error) = packages.history();
    assert_eq!((history.len(), error), (7, None));
    assert!(history.iter().all(|row| row.action == "Install" && row.log_path.is_some()));
}

#[test]
fn an_invalid_identity_fails_before_any_program_runs() {
    let scratch = Scratch::new("identity");
    let packages = Packages::with(&scratch.path("data"), FIXTURE);
    let record = packages.install("--all", "winget", "Fixture", &scratch.path("logs"), None);
    assert_eq!((record.outcome.as_str(), record.exit_code, record.message.as_str()), ("Failed", -1, "Invalid package identity."));
}

#[test]
fn a_saved_selection_round_trips_and_bad_files_are_refused() {
    let scratch = Scratch::new("setup");
    let file = scratch.path("setup.json");
    save_setup(&file, &[SetupDraft { id: "Fixture.App".to_string(), source: "winget".to_string(), name: Some("Fixture".to_string()), version: Some("1.0".to_string()) }]).unwrap();
    assert_eq!(read_setup(&file).unwrap().apps[0].id, "Fixture.App");
    save_setup(&file, &[SetupDraft { id: "Fixture.App".to_string(), source: "winget".to_string(), name: None, version: None }]).unwrap();
    let defaults = read_setup(&file).unwrap();
    assert_eq!((defaults.apps[0].name.as_str(), defaults.apps[0].version.as_str()), ("Fixture.App", "Unknown"));
    for invalid in [
        r#"{"Version":1,"Apps":["A"],"Command":"cmd.exe"}"#,
        r#"{"Version":1,"Apps":"A"}"#,
        r#"{"Version":1,"Apps":["A","A"]}"#,
        r#"{"Version":2,"Kind":"1nstall-selection","Apps":[{"Id":"--all","Source":"winget","Name":"A","Version":"1"}]}"#,
        r#"{"Version":99,"Apps":["A"]}"#,
        "malformed",
    ] {
        std::fs::write(&file, invalid).unwrap();
        assert!(read_setup(&file).is_err(), "accepted: {invalid}");
    }
    std::fs::write(&file, r#"{"Version":1,"Apps":["A"]}"#).unwrap();
    assert_eq!(read_setup(&file).unwrap().keys, ["A"]);
    std::fs::write(&file, "x".repeat(65_537)).unwrap();
    assert_eq!(read_setup(&file).unwrap_err().message, "Setup file exceeds 64 KiB.");
    assert!(save_setup(&file, &[SetupDraft { id: "--all".to_string(), source: "winget".to_string(), name: None, version: None }]).is_err());
}

#[test]
fn an_unreadable_history_is_preserved_not_overwritten() {
    let scratch = Scratch::new("history");
    let packages = Packages::with(&scratch.path("data"), FIXTURE);
    std::fs::create_dir_all(scratch.path("data")).unwrap();
    for bad in ["malformed", "[null]"] {
        std::fs::write(packages.history_path(), bad).unwrap();
        let record = packages.record("Install", Some("Fixture.App"), Some("winget"), Some("Fixture"), "Unknown", "Fixture", 0, None);
        assert!(record.message.contains("preserved"), "{}", record.message);
        assert_eq!(std::fs::read_to_string(packages.history_path()).unwrap(), bad);
        assert!(packages.history().1.is_some());
    }
}

#[test]
fn the_history_keeps_the_last_500_records() {
    let scratch = Scratch::new("limit");
    let packages = Packages::with(&scratch.path("data"), FIXTURE);
    for index in 0..503 {
        packages.record("Install", Some(&format!("Fixture.{index}")), Some("winget"), Some("Fixture"), "Unknown", "Fixture", 0, None);
    }
    let (history, error) = packages.history();
    assert_eq!((history.len(), error), (500, None));
    assert_eq!(history[0].id.as_deref(), Some("Fixture.3"));
    assert_eq!(history[499].id.as_deref(), Some("Fixture.502"));
}

#[test]
fn diagnostics_are_redacted() {
    let scratch = Scratch::new("diagnostics");
    let packages = Packages::with(&scratch.path("data"), FIXTURE);
    packages.record(
        "Install",
        Some("Fixture.App"),
        Some("winget"),
        Some("Fixture"),
        "Failed",
        "C:\\Users\\Alice\\private\\log.txt password=secret123\nBearer token123 alice@example.com https://host/?token=secret",
        1,
        None,
    );
    let text = packages.diagnostics("10.0.26100.0");
    for leaked in ["Alice", "private", "secret123", "token123", "alice@example", "token=secret"] {
        assert!(!text.contains(leaked), "diagnostics leaked {leaked}");
    }
    assert!(text.starts_with("1nstall diagnostics (review before sharing)"));
}
