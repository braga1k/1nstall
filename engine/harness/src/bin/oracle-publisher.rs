//! A stand-in publisher uninstaller for the removal scenarios.
//!
//! Usage: `oracle-publisher <mode> <registration>`. It only ever touches per-user
//! registrations whose key starts with `OracleFixture`.

use std::os::windows::process::CommandExt;
use std::process::{exit, Command};
use std::time::Duration;

use oneinstall_platform::registry::{fixtures, Hive, Key};

const ARP: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.len() != 2 || !arguments[1].starts_with("OracleFixture") {
        exit(2);
    }
    let (mode, registration) = (arguments[0].as_str(), arguments[1].as_str());
    match mode {
        "cancel" => exit(1602),
        "fail" => exit(1603),
        "keep" => exit(0),
        "child" => {
            // The launcher returns at once; the real work continues in a child.
            let program = std::env::current_exe().expect("own path");
            let _ = Command::new(program).args(["leaf", registration]).creation_flags(CREATE_NO_WINDOW).spawn();
            exit(0);
        }
        "leaf" => std::thread::sleep(Duration::from_millis(1500)),
        _ => {}
    }
    let path = format!("{ARP}\\{registration}");
    let location = Key::open(Hive::CurrentUser, false, &path).ok().flatten().and_then(|key| key.text("InstallLocation", "").ok()).unwrap_or_default();
    if !location.is_empty() {
        let _ = std::fs::remove_file(format!("{location}\\editor.exe"));
    }
    let _ = fixtures::delete_tree(Hive::CurrentUser, false, &path);
    exit(if mode == "restart" { 3010 } else { 0 });
}
