//! A stand-in for `winget.exe` and other programs in tests. It never installs anything.
//!
//! It prints its arguments as a JSON array and exits with a code chosen by marker arguments.

use std::io::Write;
use std::process::exit;
use std::time::Duration;

fn json_text(text: &str) -> String {
    let mut out = String::from("\"");
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let has = |marker: &str| arguments.iter().any(|argument| argument == marker);
    // A test that compares command lines asks for each one to be written down.
    if let Some(record) = std::env::var_os("ORACLE_FIXTURE_RECORD") {
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(record) {
            let _ = writeln!(file, "[{}]", arguments.iter().map(|argument| json_text(argument)).collect::<Vec<_>>().join(","));
        }
    }
    if has("Fixture.SlowFailure") {
        let folder = std::env::current_exe().ok().and_then(|path| path.parent().map(|parent| parent.to_path_buf())).expect("own folder");
        let _ = std::fs::write(folder.join("started.flag"), "fixture");
        std::thread::sleep(Duration::from_millis(750));
        exit(1603);
    }
    if has("pipes") {
        let _ = std::io::stdout().write_all("o".repeat(200_000).as_bytes());
        let _ = std::io::stderr().write_all("e".repeat(200_000).as_bytes());
        exit(0);
    }
    // A test that stops a queue midway needs a stand-in that takes a while.
    if let Some(delay) = std::env::var("ORACLE_FIXTURE_DELAY_MS").ok().and_then(|text| text.parse::<u64>().ok()) {
        std::thread::sleep(Duration::from_millis(delay.min(60_000)));
    }
    print!("[{}]", arguments.iter().map(|argument| json_text(argument)).collect::<Vec<_>>().join(","));
    let code = if has("Fixture.Failure") {
        1603
    } else if has("Fixture.Restart") {
        3010
    } else if has("Fixture.Cancelled") {
        1602
    } else if has("Fixture.Offline") {
        0x8A15_0107u32 as i32
    } else {
        0
    };
    exit(code);
}
