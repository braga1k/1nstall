//! The files the engine reads from the user's profile, damaged in thousands of ways.
//!
//! 3.6 and 4.0 keep their state in a few JSON files: the settings, the remembered view, the
//! operation history, the removal history and saved selections. Anything may be in them: a
//! file cut short by a crash, edited by hand, or written by something else. Whatever is there,
//! reading must not fail the engine, and what it returns must stay inside its own rules.
//!
//! The damage is generated from a fixed seed, so a failure can be reproduced: the message
//! names the reader and the case number. This is mutation of valid files and random bytes,
//! not coverage-guided fuzzing.
#![cfg(windows)]

use std::path::{Path, PathBuf};

use oneinstall_core::model::PackageInventory;
use oneinstall_engine::library::{library_view_from, setup_rows};
use oneinstall_engine::{history, set_test_environment};
use oneinstall_platform::json::app_from_json;
use oneinstall_platform::packages::Packages;
use oneinstall_platform::settings;

/// xorshift64*: small, fast and the same on every machine.
struct Random(u64);

impl Random {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn below(&mut self, limit: usize) -> usize {
        (self.next() % limit.max(1) as u64) as usize
    }
}

const FRAGMENTS: &[&str] = &[
    "{",
    "}",
    "[",
    "]",
    ",",
    ":",
    "\"",
    "\\",
    "null",
    "true",
    "false",
    "0",
    "-1",
    "1e999",
    "9223372036854775808",
    "-9223372036854775809",
    "0.1",
    "\\u0000",
    "\\ud800",
    "\u{feff}",
    "\u{202e}",
    "\r\n",
    "\t",
    " ",
    "\"Apps\"",
    "\"Version\"",
    "\"Id\"",
    "\"Source\"",
    "\"winget\"",
    "\"..\\\\..\\\\x\"",
    "\"C:\\\\Windows\"",
    "\"HKLM64:x\"",
    "[[[[[[[[",
    "{\"a\":{\"a\":{\"a\":",
];

/// One damaged version of a valid file.
fn damage(seed: &[u8], random: &mut Random) -> Vec<u8> {
    let mut bytes = seed.to_vec();
    match random.below(9) {
        // Cut short, as an interrupted write leaves it.
        0 => bytes.truncate(random.below(bytes.len() + 1)),
        // Flipped bits.
        1 => {
            for _ in 0..=random.below(8) {
                if !bytes.is_empty() {
                    let at = random.below(bytes.len());
                    bytes[at] ^= 1 << random.below(8);
                }
            }
        }
        // Pieces of JSON in the wrong places.
        2 | 3 => {
            for _ in 0..=random.below(6) {
                let at = random.below(bytes.len() + 1);
                let fragment = FRAGMENTS[random.below(FRAGMENTS.len())].as_bytes();
                bytes.splice(at..at, fragment.iter().copied());
            }
        }
        // A stretch removed.
        4 => {
            if !bytes.is_empty() {
                let from = random.below(bytes.len());
                let to = (from + random.below(40)).min(bytes.len());
                bytes.drain(from..to);
            }
        }
        // A stretch repeated many times.
        5 => {
            if !bytes.is_empty() {
                let from = random.below(bytes.len());
                let to = (from + 1 + random.below(30)).min(bytes.len());
                let piece: Vec<u8> = bytes[from..to].to_vec();
                for _ in 0..random.below(200) {
                    bytes.splice(to..to, piece.iter().copied());
                }
            }
        }
        // Nothing but noise.
        6 => {
            bytes = (0..random.below(600)).map(|_| random.next() as u8).collect();
        }
        // Very deep nesting.
        7 => {
            let depth = 1 + random.below(3000);
            bytes = if random.below(2) == 0 { "[".repeat(depth).into_bytes() } else { "{\"a\":".repeat(depth).into_bytes() };
        }
        // Another encoding: UTF-16 with a byte order mark.
        _ => {
            let text = String::from_utf8_lossy(&bytes).into_owned();
            bytes = [0xFF, 0xFE].into_iter().chain(text.encode_utf16().flat_map(u16::to_le_bytes)).collect();
        }
    }
    bytes
}

struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Self {
        let folder = std::env::temp_dir().join(format!("1nstall-hostile-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        Scratch(folder)
    }
    fn file(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

const CASES: usize = 6000;

/// Runs one reader on every damaged version of the seeds. A panic names the case.
fn every_case(reader: &str, seeds: &[&str], mut read: impl FnMut(&[u8])) {
    let mut random = Random(0x1A57_A11E_D5EE_D001 ^ reader.len() as u64);
    for case in 0..CASES {
        let seed = seeds[case % seeds.len()].as_bytes();
        let bytes = damage(seed, &mut random);
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| read(&bytes)));
        if outcome.is_err() {
            panic!("{reader}: case {case} failed on {:?}", String::from_utf8_lossy(&bytes[..bytes.len().min(300)]));
        }
    }
    println!("hostile files: {reader} read {CASES} damaged files without failing");
}

#[test]
fn damaged_settings_give_valid_settings() {
    let scratch = Scratch::new("settings");
    let path = scratch.file("settings.json");
    let languages = ["en", "pt-PT", "ar"];
    let seeds = [
        r#"{"Theme":"Dark","WindowsAccent":true,"Language":"pt-PT","AutoUpdate":false}"#,
        r#"{"Theme":"System","WindowsAccent":false,"Language":"System","AutoUpdate":true}"#,
        "\u{feff}{\r\n  \"Theme\": \"Light\",\r\n  \"WindowsAccent\": true,\r\n  \"Language\": \"ar\",\r\n  \"AutoUpdate\": true\r\n}",
    ];
    every_case("settings.json", &seeds, |bytes| {
        std::fs::write(&path, bytes).unwrap();
        let read = settings::load(&path, &languages);
        assert!(["System", "Light", "Dark"].contains(&read.theme.as_str()), "theme {:?}", read.theme);
        assert!(read.language == "System" || languages.contains(&read.language.as_str()), "language {:?}", read.language);
    });
}

#[test]
fn a_damaged_view_gives_a_known_view() {
    let scratch = Scratch::new("view");
    let path = scratch.file("preferences.json");
    let seeds = [r#"{"View":"Installed"}"#, "{\n  \"View\": \"All apps\"\n}", "\u{feff}{\"View\":\"installed\"}"];
    every_case("preferences.json", &seeds, |bytes| {
        std::fs::write(&path, bytes).unwrap();
        let view = library_view_from(&path);
        assert!(view == "All apps" || view == "Installed", "view {view:?}");
    });
}

const OPERATIONS: &str = r#"[{"Timestamp":"2026-11-18 09:00:00","Action":"Install","Id":"7zip.7zip","Source":"winget","Name":"7-Zip","Outcome":"Success","Message":"Exact package identity verified: Installed · 24.09","LogPath":"C:\\Users\\someone\\AppData\\Local\\1nstall\\Logs\\a.log","ExitCode":0},{"Timestamp":"2026-11-18 09:05:00","Action":"Remove","Id":"HKCU64:Fixture","Source":"Windows registration","Name":"Fixture","Outcome":"Failed","Message":"Uninstaller returned 1603. No cleanup was started.","LogPath":null,"ExitCode":1603}]"#;

#[test]
fn a_damaged_operation_history_is_reported_not_fatal() {
    let scratch = Scratch::new("operations");
    let data = scratch.0.to_string_lossy().into_owned();
    let path = scratch.file("operations.json");
    // The history page and the diagnostics read through the engine boundary crate.
    set_test_environment(&data, "");
    let logs = scratch.0.join("logs").to_string_lossy().into_owned();
    let seeds = [OPERATIONS, "[]", "\u{feff}[]"];
    let mut unreadable = 0;
    every_case("operations.json", &seeds, |bytes| {
        std::fs::write(&path, bytes).unwrap();
        let (rows, reason) = Packages::with(&data, "").history();
        assert!(reason.is_none() || rows.is_empty(), "an unreadable history must be empty");
        if reason.is_some() {
            unreadable += 1;
        }
        let shown = history::history(&logs);
        let records: Vec<&str> = shown.split('\u{1e}').collect();
        assert!(records.len() <= 101, "the page shows at most 100 operations, got {}", records.len() - 1);
        assert_eq!(records[0].is_empty(), reason.is_none(), "the first record is the reason, or empty");
        assert!(records[1..].iter().all(|record| record.split('\u{1f}').count() == 3), "every operation has three fields");
        let diagnostics = history::diagnostics("10.0.1.2");
        assert!(diagnostics.starts_with("1nstall diagnostics (review before sharing)\r\nWindows 10.0.1.2"));
        // The rule of 3.6, kept as it is: a path is what starts at a drive letter or at "\\".
        // (A path that lost its drive letter to the damage is not recognised, there or here.)
        let rooted = diagnostics.as_bytes().windows(3).any(|window| window[0].is_ascii_alphabetic() && window[1] == b':' && window[2] == b'\\');
        assert!(!rooted, "a path with a drive letter survived the redaction: {diagnostics}");
        // A history that cannot be read is never replaced by a new record.
        if reason.is_some() {
            Packages::with(&data, "").record("Install", Some("Fixture.App"), Some("winget"), Some("Fixture"), "Failed", "after damage", 1, None);
            assert_eq!(std::fs::read(&path).unwrap(), bytes, "an unreadable history was overwritten");
        }
    });
    println!("hostile files: {unreadable} of {CASES} operation histories were unreadable, and none was overwritten");
    assert!(unreadable > CASES / 10, "the damage should make many histories unreadable");
}

#[test]
fn a_damaged_saved_selection_offers_only_catalog_apps() {
    let scratch = Scratch::new("setup");
    let path = scratch.file("setup.json");
    let file = path.to_string_lossy().into_owned();
    let inventory = PackageInventory::default();
    let seeds = [
        r#"{"Version":1,"Apps":["extra_7zip","peace"]}"#,
        r#"{"Version":2,"Kind":"1nstall-selection","Apps":[{"Id":"7zip.7zip","Source":"winget","Name":"7-Zip","Version":"24.09"},{"Id":"No.Such.Package","Source":"winget","Name":"Nothing","Version":"Unknown"}]}"#,
        "\u{feff}{\"Version\":1,\"Apps\":[\"apo\"]}",
    ];
    let (mut accepted, mut refused) = (0, 0);
    every_case("saved selection", &seeds, |bytes| {
        std::fs::write(&path, bytes).unwrap();
        match setup_rows(&file, &inventory) {
            Ok(rows) => {
                accepted += 1;
                for row in rows {
                    assert_eq!(row.len(), 3, "{row:?}");
                    // A key that is offered must plan: it names a catalog app.
                    if !row[0].is_empty() {
                        assert!(!oneinstall_engine::plan_records(&[row[0].clone()]).starts_with('!'), "an unknown key was offered: {row:?}");
                    }
                }
            }
            Err(reason) => {
                refused += 1;
                assert!(!reason.is_empty());
            }
        }
    });
    println!("hostile files: {accepted} damaged selections were still valid, {refused} were refused with a reason");
    assert!(refused > CASES / 10);
}

#[test]
fn a_damaged_removal_history_entry_reads_as_an_app() {
    let seeds = [
        r#"{"Id":"HKCU64:Fixture","Name":"Fixture","Publisher":"Vendor","Version":"1.0","Kind":"Desktop","Location":"C:\\Program Files\\Fixture","Command":"\"C:\\x\\u.exe\" /S","RegistryPath":"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Fixture","PackageFamily":null,"Machine":false,"View32":false,"Msi":false,"RemovalVerified":true,"OwnershipVerified":true,"IdentityVerified":true,"RestartRequestedAt":0,"CanRemove":true,"SizeKB":1024,"Detail":"x"}"#,
    ];
    let mut parsed = 0;
    every_case("uninstall-history.json entry", &seeds, |bytes| {
        // Whatever parses as JSON must read as an entry; wrong types take their defaults.
        if let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) {
            parsed += 1;
            let app = app_from_json(&value);
            assert!(app.size_kb == 0 || value.get("SizeKB").is_some());
        }
    });
    println!("hostile files: {parsed} damaged removal entries still parsed as JSON and read as entries");
    let _ = Path::new("");
}
