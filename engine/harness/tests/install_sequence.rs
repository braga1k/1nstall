//! The WinGet command lines of an install, from 3.6 and from the Rust engine, side by side.
//!
//! Both install the same made-up packages with a stand-in for WinGet that installs nothing and
//! writes down every command line it receives. 3.6 runs live, through
//! `oracle\drivers\v36-install.ps1`. The outcomes must be equal, and so must the command
//! lines, but for the one declared difference: when the Rust engine verifies an install it
//! passes `--accept-source-agreements` to `winget export`, which 3.6 did not (the user has
//! accepted the source terms to install; without the flag every install on a new PC stays
//! `Unknown`).
//!
//! Only a temporary folder is written. Where PowerShell 7 and the Microsoft.WinGet.Client
//! module are installed, 3.6 verifies with them instead of `winget export`; that only reads.
#![cfg(windows)]

use std::path::Path;
use std::process::Command;

use oneinstall_platform::packages::Packages;

const FIXTURE: &str = env!("CARGO_BIN_EXE_oracle-fixture");
const IDS: [&str; 5] = ["Vendor.App", "Fixture.Failure", "Fixture.Restart", "Fixture.Cancelled", "Fixture.Offline"];

/// The command lines the stand-in wrote down, with the temporary file names replaced.
fn recorded(file: &Path) -> Vec<Vec<String>> {
    let text = std::fs::read_to_string(file).unwrap_or_default();
    text.lines()
        .map(|line| {
            let arguments: Vec<String> = serde_json::from_str(line).unwrap_or_else(|error| panic!("the stand-in wrote {line:?}: {error}"));
            let mut previous = String::new();
            arguments
                .into_iter()
                .map(|argument| {
                    let shown = if previous == "--output" { "<temporary file>".to_string() } else { argument.clone() };
                    previous = argument;
                    shown
                })
                .collect()
        })
        .collect()
}

#[test]
fn an_install_sends_winget_the_commands_3_6_sent() {
    let work = std::env::temp_dir().join(format!("1nstall-rust-sequence-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&work);
    let (rust_work, old_work) = (work.join("rust"), work.join("v36"));
    std::fs::create_dir_all(&rust_work).unwrap();
    std::fs::create_dir_all(&old_work).unwrap();

    // The Rust engine.
    let rust_record = rust_work.join("commands.jsonl");
    std::env::set_var("ORACLE_FIXTURE_RECORD", &rust_record);
    let packages = Packages::with(&rust_work.to_string_lossy(), FIXTURE);
    let logs = rust_work.join("logs").to_string_lossy().into_owned();
    let rust_outcomes: Vec<String> = IDS
        .iter()
        .map(|id| {
            let record = packages.install(id, "winget", "Fixture", &logs, None);
            format!("install {id} -> {} {}", record.outcome, record.exit_code)
        })
        .collect();
    std::env::remove_var("ORACLE_FIXTURE_RECORD");
    let rust_commands = recorded(&rust_record);

    // 3.6, live.
    let old_record = old_work.join("commands.jsonl");
    let driver = concat!(env!("CARGO_MANIFEST_DIR"), "\\..\\..\\oracle\\drivers\\v36-install.ps1");
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", driver, "-StandIn", FIXTURE, "-Work"])
        .arg(&old_work)
        .args(["-Ids", &IDS.join(",")])
        .env("ORACLE_FIXTURE_RECORD", &old_record)
        .output()
        .expect("Windows PowerShell");
    assert!(output.status.success(), "the 3.6 driver failed: {}", String::from_utf8_lossy(&output.stderr));
    let old_outcomes: Vec<String> = String::from_utf8_lossy(&output.stdout).lines().map(|line| line.trim().to_string()).filter(|line| !line.is_empty()).collect();
    let old_commands = recorded(&old_record);
    let _ = std::fs::remove_dir_all(&work);

    assert_eq!(rust_outcomes, old_outcomes, "outcomes differ");

    // The install commands, one per package, must be the same.
    let installs = |commands: &[Vec<String>]| commands.iter().filter(|command| command.first().is_some_and(|verb| verb == "install")).cloned().collect::<Vec<_>>();
    assert_eq!(installs(&rust_commands), installs(&old_commands), "install command lines differ");
    assert_eq!(installs(&rust_commands).len(), IDS.len());

    // The verification after an install that exited with success: one export.
    let exports = |commands: &[Vec<String>]| commands.iter().filter(|command| command.first().is_some_and(|verb| verb == "export")).cloned().collect::<Vec<_>>();
    let (rust_exports, old_exports) = (exports(&rust_commands), exports(&old_commands));
    assert_eq!(rust_exports.len(), 1, "only the install that exited with success is verified: {rust_commands:?}");
    let flag = "--accept-source-agreements".to_string();
    assert!(rust_exports[0].contains(&flag), "{rust_exports:?}");
    let without_flag: Vec<String> = rust_exports[0].iter().filter(|argument| **argument != flag).cloned().collect();
    if old_exports.is_empty() {
        // 3.6 found PowerShell 7 with the WinGet module here, and read the complete inventory with it.
        println!("install sequence: 3.6 verified with the Microsoft.WinGet.Client module on this machine; its export command was not exercised");
    } else {
        assert_eq!(old_exports.len(), 1, "{old_commands:?}");
        assert!(!old_exports[0].contains(&flag));
        assert_eq!(without_flag, old_exports[0], "the export differs by more than the declared flag");
    }
    assert_eq!(rust_commands.len(), IDS.len() + 1, "the Rust engine ran other commands: {rust_commands:?}");
    println!(
        "install sequence: {} installs sent WinGet the same command lines as 3.6, with the same outcomes ({}); the verifying export differs only by {flag}",
        IDS.len(),
        rust_outcomes.iter().map(|line| line.rsplit(" -> ").next().unwrap_or("")).collect::<Vec<_>>().join(", ")
    );
}
