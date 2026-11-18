//! Uninstalling as the interface drives it, through the engine boundary crate.
//!
//! The first test only reads and runs anywhere. The second registers a fixture app, removes it
//! with a stand-in publisher uninstaller, scans for what it left and cleans it. It changes the
//! registry and files of the current user, so it runs only where `ORACLE_DISPOSABLE=1` says
//! the machine is disposable: a CI runner, never a developer's PC.
#![cfg(windows)]

use std::time::{Duration, Instant};

use oneinstall_engine::{set_test_environment, uninstall};
use oneinstall_platform::registry::{fixtures, Hive};

const PUBLISHER: &str = env!("CARGO_BIN_EXE_oracle-publisher");
const ARP: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";
// The stand-in uninstaller only touches registrations whose name starts with OracleFixture.
const REGISTRATION: &str = "OracleFixtureBoundary";
const PRODUCT: &str = "OracleBoundary Editor";

type Events = Vec<Vec<String>>;

/// Runs one operation to its end and returns everything it reported.
fn run(operation: &str, arguments: &[String], log: &str) -> Events {
    uninstall::start(operation, arguments, log).unwrap_or_else(|error| panic!("{operation} did not start: {error}"));
    let mut events: Events = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(300);
    loop {
        let reported = uninstall::poll();
        if !reported.is_empty() {
            events.extend(reported.split('\u{1e}').map(|record| record.split('\u{1f}').map(str::to_string).collect::<Vec<String>>()));
        }
        if events.iter().any(|event| event[0] == "done") {
            assert!(!uninstall::running());
            return events;
        }
        assert!(Instant::now() < deadline, "{operation} did not finish; so far: {events:?}");
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn of<'a>(events: &'a Events, kind: &str) -> Vec<&'a Vec<String>> {
    events.iter().filter(|event| event[0] == kind).collect()
}

fn disposable() -> bool {
    std::env::var("ORACLE_DISPOSABLE").as_deref() == Ok("1")
}

#[test]
fn the_test_modes_only_read() {
    if disposable() {
        // The other test needs the real environment, and the environment is process-wide.
        return;
    }
    let data = std::env::temp_dir().join(format!("1nstall-rust-uninstall-{}", std::process::id()));
    set_test_environment(&data.to_string_lossy(), "");
    for operation in ["Remove", "Scan", "Clean"] {
        let refused = uninstall::start(operation, &["anything".to_string()], "").unwrap_err();
        assert!(refused.contains("switched off"), "{operation}: {refused}");
    }
    assert!(uninstall::start("Format", &[], "").is_err());
    assert_eq!(uninstall::targets(), 0);
    // Reading the installed apps is allowed, and every app has an id, a name and a kind.
    let events = run("Inventory", &[], "");
    let apps = of(&events, "app");
    assert!(!apps.is_empty());
    assert!(apps.iter().all(|app| app.len() == 9 && !app[1].is_empty() && !app[2].is_empty() && (app[6] == "Desktop" || app[6] == "Microsoft Store")), "{apps:?}");
    assert_eq!(events.last().unwrap(), &vec!["done".to_string(), "Inventory".to_string()]);
    println!("uninstall boundary: inventory read {} apps, {} warnings", apps.len(), of(&events, "warning").len());
    assert!(!data.exists(), "reading must write nothing");

    // An internal failure inside the operation thread ends that operation with an error the
    // interface can show. The engine is not left busy, and the next operation runs.
    let events = run("Fail", &[], "");
    let errors = of(&events, "error");
    assert_eq!(errors.len(), 1, "{events:?}");
    assert!(errors[0][1].starts_with("1nstall could not finish this operation: Deliberate failure for the tests (") && errors[0][1].contains("uninstall.rs:"), "{errors:?}");
    assert_eq!(events.last().unwrap(), &vec!["done".to_string(), "Fail".to_string()]);
    assert_eq!(of(&run("Inventory", &[], ""), "app").len(), apps.len());
    println!("uninstall boundary: a failed operation reported \"{}\" and the next one ran", errors[0][1]);
}

#[test]
fn a_fixture_app_is_removed_scanned_and_cleaned() {
    if !disposable() {
        println!("oracle uninstall: skipped; set ORACLE_DISPOSABLE=1 on a disposable machine to run it");
        return;
    }
    let local = std::env::var("LOCALAPPDATA").expect("LOCALAPPDATA");
    let roaming = std::env::var("APPDATA").expect("APPDATA");
    let install = format!("{local}\\Programs\\{PRODUCT}");
    let data = format!("{roaming}\\OracleBoundaryVendor\\{PRODUCT}");
    let registry_path = format!("{ARP}\\{REGISTRATION}");
    let log = format!("{local}\\1nstall\\Logs\\boundary-test.log");
    std::fs::create_dir_all(&install).unwrap();
    std::fs::create_dir_all(&data).unwrap();
    std::fs::write(format!("{install}\\editor.exe"), "fixture executable placeholder").unwrap();
    std::fs::write(format!("{install}\\readme.txt"), "fixture program file").unwrap();
    std::fs::write(format!("{data}\\settings.ini"), "fixture user settings").unwrap();
    let set = |name: &str, value: &str| fixtures::set_text(Hive::CurrentUser, false, &registry_path, name, value).unwrap();
    set("DisplayName", &format!("{PRODUCT} 2.0 (x64)"));
    set("Publisher", "Oracle Boundary Vendor");
    set("DisplayVersion", "2.0");
    set("InstallLocation", &install);
    // The stand-in uninstaller removes the registration and the executable, and leaves the rest.
    set("UninstallString", &format!("\"{PUBLISHER}\" clean {REGISTRATION}"));

    let listed = run("Inventory", &[], &log);
    let fixture = of(&listed, "app").into_iter().find(|app| app[2].starts_with(PRODUCT)).unwrap_or_else(|| panic!("the fixture is not in the inventory"));
    assert_eq!((fixture[5].as_str(), fixture[6].as_str(), fixture[8].as_str()), ("2.0", "Desktop", "1"), "{fixture:?}");
    let id = fixture[1].clone();

    let removed = run("Remove", &[id.clone()], &log);
    let stages: Vec<&str> = of(&removed, "stage").iter().map(|stage| stage[2].as_str()).collect();
    println!("oracle uninstall: stages {}", stages.join(" | "));
    assert_eq!(stages.first(), Some(&"Preparing…"));
    let outcome = of(&removed, "result")[0].clone();
    assert_eq!(outcome[3], "Success", "{removed:?}");
    assert!(of(&removed, "progress").iter().any(|event| event[1].starts_with(&format!("Removing {PRODUCT}"))), "{removed:?}");
    assert!(of(&removed, "verified").iter().any(|event| event[1] == id));
    assert!(uninstall::targets() >= 1);

    let scanned = run("Scan", &[], &log);
    assert!(of(&scanned, "error").is_empty(), "{scanned:?}");
    let leftovers = of(&scanned, "leftover");
    println!("oracle uninstall: scan found {}", leftovers.iter().map(|item| format!("{} {} ({})", item[3], item[9], item[4])).collect::<Vec<_>>().join(" | "));
    let ours: Vec<String> = leftovers.iter().filter(|item| item[2].starts_with(PRODUCT) && item[9].contains("OracleBoundary")).map(|item| item[1].clone()).collect();
    assert!(!ours.is_empty(), "the fixture's files were not offered: {scanned:?}");
    assert!(std::path::Path::new(&install).exists(), "a scan removes nothing");

    let cleaned = run("Clean", &ours, &log);
    assert!(of(&cleaned, "error").is_empty(), "{cleaned:?}");
    let results = of(&cleaned, "result");
    println!("oracle uninstall: clean {}", results.iter().map(|item| format!("{} {}", item[3], item[7])).collect::<Vec<_>>().join(" | "));
    assert!(results.iter().all(|item| item[3] == "Success"), "{cleaned:?}");
    assert!(!std::path::Path::new(&install).exists(), "the install folder should be in the Recycle Bin");
    let summary = of(&cleaned, "clean")[0].clone();
    assert!(std::path::Path::new(&summary[1]).join("items.json").exists(), "the backup folder records what was cleaned");
    println!("oracle uninstall: removed, scanned and cleaned through the boundary; {} leftovers cleaned", results.len());

    let _ = fixtures::delete_tree(Hive::CurrentUser, false, &registry_path);
    let _ = std::fs::remove_dir_all(format!("{roaming}\\OracleBoundaryVendor"));
    let _ = std::fs::remove_dir_all(&install);
}
