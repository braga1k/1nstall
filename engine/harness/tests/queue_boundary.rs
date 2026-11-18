//! The install queue as the interface drives it, through the engine boundary crate, with a
//! stand-in WinGet that installs nothing. Only a temporary folder is written.
#![cfg(windows)]

use std::time::{Duration, Instant};

use oneinstall_engine::{queue, set_test_environment};

const FIXTURE: &str = env!("CARGO_BIN_EXE_oracle-fixture");

/// Collects events until the queue reports that it is done.
fn finish() -> Vec<Vec<String>> {
    let mut events: Vec<Vec<String>> = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let drained = queue::drain();
        if !drained.is_empty() {
            events.extend(drained.split('\u{1e}').map(|record| record.split('\u{1f}').map(str::to_string).collect()));
        }
        if events.iter().any(|event| event[0] == "done") {
            return events;
        }
        assert!(Instant::now() < deadline, "the queue did not finish");
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn statuses<'a>(events: &'a [Vec<String>], key: &str) -> Vec<&'a str> {
    events.iter().filter(|event| event[0] == "status" && event[1] == key).map(|event| event[2].as_str()).collect()
}

// One test, because the queue and its test environment are process-wide.
#[test]
fn the_queue_runs_reports_and_stops_as_the_interface_expects() {
    let folder = std::env::temp_dir().join(format!("1nstall-rust-queue-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&folder);
    std::fs::create_dir_all(&folder).unwrap();
    let data = folder.join("data").to_string_lossy().into_owned();
    let logs = folder.join("logs").to_string_lossy().into_owned();

    // Without a stand-in installer, the test environment refuses to install anything.
    set_test_environment(&data, "");
    assert!(queue::start(&["extra_7zip".to_string()], &logs).unwrap_err().contains("switched off"));

    set_test_environment(&data, FIXTURE);
    assert!(queue::start(&["no-such-app".to_string()], &logs).is_err());
    assert!(!queue::running());

    // An automatic app, and a guided app that requires another guided app.
    queue::start(&["extra_7zip".to_string(), "peace".to_string()], &logs).unwrap();
    let events = finish();
    assert!(!queue::running());
    let seven_zip = statuses(&events, "extra_7zip");
    assert_eq!(seven_zip.first(), Some(&"Preparing…"));
    assert!(seven_zip.iter().any(|status| status.starts_with("Installing ")), "{seven_zip:?}");
    // The stand-in exits with success but nothing is installed, so the outcome is not a success.
    assert_eq!(seven_zip.last(), Some(&"Unknown · refresh to verify"));
    assert_eq!(statuses(&events, "apo"), ["Preparing…", "Manual install pending · official website"]);
    assert_eq!(statuses(&events, "peace"), ["Manual action required · dependency not verified: apo"]);
    assert_eq!(events.iter().filter(|event| event[0] == "progress").count(), 3);
    assert_eq!(events.iter().filter(|event| event[0] == "url").map(|event| event[1].as_str()).collect::<Vec<_>>(), ["apo"]);
    assert_eq!(events.last().unwrap()[0], "done");
    assert!(events.iter().any(|event| event[0] == "log" && event[1] == "extra_7zip"));
    let history = std::fs::read_to_string(folder.join("data").join("operations.json")).unwrap();
    assert_eq!(history.matches("\"Action\"").count(), 3, "{history}");

    // Asked to stop before the first app, every app is reported and recorded as not started.
    queue::start(&["extra_7zip".to_string(), "extra_vlc".to_string()], &logs).unwrap();
    queue::stop();
    let stopped = finish();
    let vlc = statuses(&stopped, "extra_vlc");
    assert_eq!(vlc.last(), Some(&"Cancelled · not started"), "{stopped:?}");
    assert_eq!(stopped.iter().filter(|event| event[0] == "progress").count(), 2);

    // A stop request does not outlive its queue.
    queue::start(&["apo".to_string()], &logs).unwrap();
    assert_eq!(statuses(&finish(), "apo").last(), Some(&"Manual install pending · official website"));
    let _ = std::fs::remove_dir_all(&folder);
}
