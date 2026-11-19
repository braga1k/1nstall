//! A stand-in publisher uninstaller for the removal scenarios.
//!
//! Usage: `oracle-publisher <mode> <registration> [machine|machine32]`. It only ever touches
//! registrations whose key starts with `OracleFixture`: per-user ones, or, when the third
//! argument says so, machine-wide ones in the 64-bit or the 32-bit view of the registry.
//! `ORACLE_PUBLISHER_DELAY_MS` sets how long the `leaf` mode works before it removes anything.

use std::os::windows::process::CommandExt;
use std::process::{exit, Command};
use std::time::Duration;

use oneinstall_platform::registry::{fixtures, Hive, Key};

const ARP: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if !(2..=3).contains(&arguments.len()) || !arguments[1].starts_with("OracleFixture") {
        exit(2);
    }
    let (mode, registration) = (arguments[0].as_str(), arguments[1].as_str());
    let (hive, view32) = match arguments.get(2).map(String::as_str) {
        None => (Hive::CurrentUser, false),
        Some("machine") => (Hive::LocalMachine, false),
        Some("machine32") => (Hive::LocalMachine, true),
        Some(_) => exit(2),
    };
    match mode {
        "cancel" => exit(1602),
        "fail" => exit(1603),
        "keep" => exit(0),
        "child" => {
            // The launcher returns at once; the real work continues in a child.
            let program = std::env::current_exe().expect("own path");
            let mut leaf = vec!["leaf".to_string(), registration.to_string()];
            leaf.extend(arguments.get(2).cloned());
            let _ = Command::new(program).args(leaf).creation_flags(CREATE_NO_WINDOW).spawn();
            exit(0);
        }
        "leaf" => {
            let delay = std::env::var("ORACLE_PUBLISHER_DELAY_MS").ok().and_then(|text| text.parse::<u64>().ok()).unwrap_or(1500);
            std::thread::sleep(Duration::from_millis(delay.min(60_000)));
        }
        _ => {}
    }
    let path = format!("{ARP}\\{registration}");
    let location = Key::open(hive, view32, &path).ok().flatten().and_then(|key| key.text("InstallLocation", "").ok()).unwrap_or_default();
    if !location.is_empty() {
        let _ = std::fs::remove_file(format!("{location}\\editor.exe"));
    }
    let _ = fixtures::delete_tree(hive, view32, &path);
    exit(if mode == "restart" { 3010 } else { 0 });
}
