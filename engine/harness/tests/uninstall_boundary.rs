//! Uninstalling as the interface drives it, through the engine boundary crate.
//!
//! The first test only reads and runs anywhere. The second registers fixture apps (one for the
//! current user, one machine-wide in the 32-bit view of the registry), removes them with a
//! stand-in publisher uninstaller, scans for what they left and cleans it, and stops a queue
//! of two midway. It changes the registry and files of the machine, so it runs only where
//! `ORACLE_DISPOSABLE=1` says the machine is disposable: a CI runner, never a developer's PC.
#![cfg(windows)]

use std::time::{Duration, Instant};

use oneinstall_engine::{set_test_environment, uninstall};
use oneinstall_platform::registry::{self, fixtures, Hive};

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

/// Where a fixture app is registered and installed.
struct Scope {
    label: &'static str,
    hive: Hive,
    view32: bool,
    /// The third argument of the stand-in uninstaller, when the registration is machine-wide.
    publisher_scope: Option<&'static str>,
    /// How the stand-in uninstaller works: `clean` at once, or `child`, where the program that
    /// was started returns at once and a child of it does the work.
    mode: &'static str,
    registration: &'static str,
    product: &'static str,
    vendor: &'static str,
    install_root: String,
    data_root: String,
    id_prefix: &'static str,
}

/// Registers a fixture app, removes it with a stand-in publisher uninstaller, scans for what
/// it left and cleans it, all through the boundary the interface uses.
fn remove_scan_clean(scope: &Scope, log: &str) {
    let (product, registration) = (scope.product, scope.registration);
    let install = format!("{}\\{product}", scope.install_root);
    let data = format!("{}\\{}\\{product}", scope.data_root, scope.vendor);
    let registry_path = format!("{ARP}\\{registration}");
    std::fs::create_dir_all(&install).unwrap();
    std::fs::create_dir_all(&data).unwrap();
    std::fs::write(format!("{install}\\editor.exe"), "fixture executable placeholder").unwrap();
    std::fs::write(format!("{install}\\readme.txt"), "fixture program file").unwrap();
    std::fs::write(format!("{data}\\settings.ini"), "fixture user settings").unwrap();
    let set = |name: &str, value: &str| fixtures::set_text(scope.hive, scope.view32, &registry_path, name, value).unwrap();
    set("DisplayName", &format!("{product} 2.0"));
    set("Publisher", scope.vendor);
    set("DisplayVersion", "2.0");
    set("InstallLocation", &install);
    // The stand-in uninstaller removes the registration and the executable, and leaves the rest.
    let extra = scope.publisher_scope.map(|scope| format!(" {scope}")).unwrap_or_default();
    set("UninstallString", &format!("\"{PUBLISHER}\" {} {registration}{extra}", scope.mode));

    let listed = run("Inventory", &[], log);
    let fixture = of(&listed, "app").into_iter().find(|app| app[2].starts_with(product)).unwrap_or_else(|| panic!("{}: the fixture is not in the inventory", scope.label));
    assert_eq!((fixture[5].as_str(), fixture[6].as_str(), fixture[8].as_str()), ("2.0", "Desktop", "1"), "{fixture:?}");
    let id = fixture[1].clone();
    assert!(id.starts_with(scope.id_prefix), "{}: the id {id} should start with {}", scope.label, scope.id_prefix);

    let removed = run("Remove", &[id.clone()], log);
    let stages: Vec<&str> = of(&removed, "stage").iter().map(|stage| stage[2].as_str()).collect();
    println!("oracle uninstall: {} stages {}", scope.label, stages.join(" | "));
    assert_eq!(stages.first(), Some(&"Preparing…"));
    let outcome = of(&removed, "result")[0].clone();
    assert_eq!(outcome[3], "Success", "{removed:?}");
    assert!(of(&removed, "progress").iter().any(|event| event[1].starts_with(&format!("Removing {product}"))), "{removed:?}");
    assert!(of(&removed, "verified").iter().any(|event| event[1] == id));
    assert!(uninstall::targets() >= 1);
    assert_eq!(registry::key_exists(scope.hive, scope.view32, &registry_path), Ok(false), "{}: the registration should be gone", scope.label);

    let scanned = run("Scan", &[], log);
    assert!(of(&scanned, "error").is_empty(), "{scanned:?}");
    let leftovers = of(&scanned, "leftover");
    println!("oracle uninstall: {} scan found {}", scope.label, leftovers.iter().map(|item| format!("{} {} ({})", item[3], item[9], item[4])).collect::<Vec<_>>().join(" | "));
    let ours: Vec<String> =
        leftovers.iter().filter(|item| item[2].starts_with(product) && (item[9].contains(scope.vendor) || item[9].contains(product))).map(|item| item[1].clone()).collect();
    assert!(leftovers.iter().any(|item| item[9].eq_ignore_ascii_case(&install)), "{}: the install folder was not offered: {scanned:?}", scope.label);
    assert!(!ours.is_empty(), "the fixture's files were not offered: {scanned:?}");
    assert!(std::path::Path::new(&install).exists(), "a scan removes nothing");

    let cleaned = run("Clean", &ours, log);
    assert!(of(&cleaned, "error").is_empty(), "{cleaned:?}");
    let results = of(&cleaned, "result");
    println!("oracle uninstall: {} clean {}", scope.label, results.iter().map(|item| format!("{} {}", item[3], item[7])).collect::<Vec<_>>().join(" | "));
    assert!(results.iter().all(|item| item[3] == "Success"), "{cleaned:?}");
    assert!(!std::path::Path::new(&install).exists(), "the install folder should be in the Recycle Bin");
    let summary = of(&cleaned, "clean")[0].clone();
    assert!(std::path::Path::new(&summary[1]).join("items.json").exists(), "the backup folder records what was cleaned");
    println!("oracle uninstall: {} removed, scanned and cleaned through the boundary; {} leftovers cleaned", scope.label, results.len());

    let _ = fixtures::delete_tree(scope.hive, scope.view32, &registry_path);
    let _ = std::fs::remove_dir_all(format!("{}\\{}", scope.data_root, scope.vendor));
    let _ = std::fs::remove_dir_all(&install);
}

/// Two apps are queued; a stop is asked while the first uninstaller is still working. The
/// running uninstaller is never interrupted, and the next app is kept.
fn a_stop_keeps_the_next_app(log: &str) {
    let registry_path = |registration: &str| format!("{ARP}\\{registration}");
    let names = [("OracleFixtureStopFirst", "OracleStop First"), ("OracleFixtureStopSecond", "OracleStop Second")];
    // The launcher returns at once and its child works for four seconds before it removes anything.
    std::env::set_var("ORACLE_PUBLISHER_DELAY_MS", "4000");
    for (registration, product) in names {
        let set = |name: &str, value: &str| fixtures::set_text(Hive::CurrentUser, false, &registry_path(registration), name, value).unwrap();
        set("DisplayName", product);
        set("Publisher", "Oracle Stop Vendor");
        set("DisplayVersion", "1.0");
        set("UninstallString", &format!("\"{PUBLISHER}\" child {registration}"));
    }
    let listed = run("Inventory", &[], log);
    let id_of = |product: &str| of(&listed, "app").into_iter().find(|app| app[2] == product).unwrap_or_else(|| panic!("{product} is not in the inventory"))[1].clone();
    let (first, second) = (id_of(names[0].1), id_of(names[1].1));

    uninstall::start("Remove", &[first.clone(), second.clone()], log).unwrap();
    let mut events: Events = Vec::new();
    let mut asked = false;
    let started = Instant::now();
    let mut asked_at = Duration::ZERO;
    loop {
        let reported = uninstall::poll();
        if !reported.is_empty() {
            events.extend(reported.split('\u{1e}').map(|record| record.split('\u{1f}').map(str::to_string).collect::<Vec<String>>()));
        }
        // Ask to stop once the first uninstaller is running.
        if !asked && events.iter().any(|event| event[0] == "stage" && event[1] == first && event[2] == "Removing…") {
            uninstall::stop();
            asked = true;
            asked_at = started.elapsed();
        }
        if events.iter().any(|event| event[0] == "done") {
            break;
        }
        assert!(started.elapsed() < Duration::from_secs(120), "the removal did not finish: {events:?}");
        std::thread::sleep(Duration::from_millis(50));
    }
    std::env::remove_var("ORACLE_PUBLISHER_DELAY_MS");
    let finished = started.elapsed();
    let outcome = |id: &str| of(&events, "result").into_iter().find(|result| result[1] == id).map(|result| result[3].clone()).unwrap_or_default();
    println!(
        "oracle uninstall: stop asked after {} ms, removal ended after {} ms; first {}, second {}",
        asked_at.as_millis(),
        finished.as_millis(),
        outcome(&first),
        outcome(&second)
    );
    assert!(asked, "the first uninstaller never started: {events:?}");
    assert!(finished >= asked_at + Duration::from_millis(2000), "the running uninstaller was not waited for");
    assert_eq!(outcome(&first), "Success", "{events:?}");
    assert_eq!(outcome(&second), "Cancelled", "{events:?}");
    assert_eq!(registry::key_exists(Hive::CurrentUser, false, &registry_path(names[0].0)), Ok(false), "the first app should be removed");
    assert_eq!(registry::key_exists(Hive::CurrentUser, false, &registry_path(names[1].0)), Ok(true), "the second app must be kept");
    assert!(!of(&events, "stage").iter().any(|stage| stage[1] == second && stage[2] == "Removing…"), "the second uninstaller was started: {events:?}");
    for (registration, _) in names {
        let _ = fixtures::delete_tree(Hive::CurrentUser, false, &registry_path(registration));
    }
}

#[test]
fn fixture_apps_are_removed_scanned_and_cleaned() {
    if !disposable() {
        println!("oracle uninstall: skipped; set ORACLE_DISPOSABLE=1 on a disposable machine to run it");
        return;
    }
    let local = std::env::var("LOCALAPPDATA").expect("LOCALAPPDATA");
    let roaming = std::env::var("APPDATA").expect("APPDATA");
    let log = format!("{local}\\1nstall\\Logs\\boundary-test.log");
    // One operation runs at a time inside the engine, so the scenarios run one after another.
    remove_scan_clean(
        &Scope {
            label: "per-user",
            hive: Hive::CurrentUser,
            view32: false,
            publisher_scope: None,
            mode: "clean",
            registration: REGISTRATION,
            product: PRODUCT,
            vendor: "OracleBoundaryVendor",
            install_root: format!("{local}\\Programs"),
            data_root: roaming,
            id_prefix: "HKCU64:",
        },
        &log,
    );
    // Machine-wide, in the 32-bit view of the registry: the uninstaller is started elevated, as
    // Windows requires for such apps, returns at once and leaves the work to a child, which the
    // engine must wait for. A CI runner is already elevated, so no prompt appears.
    let program_files_x86 = std::env::var("ProgramFiles(x86)").expect("ProgramFiles(x86)");
    let program_data = std::env::var("ProgramData").expect("ProgramData");
    remove_scan_clean(
        &Scope {
            label: "machine-wide 32-bit",
            hive: Hive::LocalMachine,
            view32: true,
            publisher_scope: Some("machine32"),
            mode: "child",
            registration: "OracleFixtureMachine",
            product: "OracleMachine Editor",
            vendor: "OracleMachineVendor",
            install_root: program_files_x86,
            data_root: program_data,
            id_prefix: "HKLM32:",
        },
        &log,
    );
    a_stop_keeps_the_next_app(&log);
}
