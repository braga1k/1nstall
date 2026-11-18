//! The history page behind the interface: the operations on record, the diagnostics text
//! and the licence notices. These are `Render-History`, `Show-Diagnostics` and
//! `Show-ThirdPartyNotices` of 3.6, without the drawing.

use std::path::Path;

use oneinstall_core::model::PackageInventory;
use oneinstall_core::packages::installed_state;
use oneinstall_platform::packages::OperationRecord;

use crate::library::inventory;
use crate::{catalog, give, guard, packages, records, take};

/// Licences and credits, as 3.6 embeds them in its executable.
const NOTICES: &str = include_str!("../../../licenses/THIRD-PARTY-NOTICES.txt");

/// How many operations the page shows, newest first.
const SHOWN: usize = 100;

/// The catalog app a failed WinGet install may be reviewed again for. Only when exactly one
/// app carries the package and the last inventory says that app is not installed.
fn retry_key(record: &OperationRecord, inventory: &PackageInventory) -> Option<String> {
    let failed_install = record.action.eq_ignore_ascii_case("Install")
        && record.outcome.eq_ignore_ascii_case("Failed")
        && record.source.as_deref().is_some_and(|source| source.eq_ignore_ascii_case("winget"));
    let id = record.id.as_deref().filter(|_| failed_install)?;
    let mut carrying = catalog().iter().filter(|app| app.ids.iter().any(|known| known.eq_ignore_ascii_case(id)));
    let app = carrying.next().filter(|_| carrying.next().is_none())?;
    (installed_state(inventory, Some(&app.ids), "winget") == "Not installed").then(|| app.key.clone())
}

/// The log of an operation, when it still exists and lies inside the application's log folder.
fn log_to_open(record: &OperationRecord, log_folder: &str) -> Option<String> {
    let log = record.log_path.as_deref().filter(|log| !log.is_empty() && Path::new(log).exists())?;
    let full = std::path::absolute(log).ok()?.display().to_string().to_uppercase();
    let folder = format!("{}\\", std::path::absolute(log_folder).ok()?.display()).to_uppercase();
    full.starts_with(&folder).then(|| log.to_string())
}

/// What the history page shows. The first record is the reason the history could not be
/// read, or empty. Each further record is one operation, newest first, at most 100: its
/// text, the key of the app to review again (or empty), and the log to open (or empty).
pub fn history_records(rows: &[OperationRecord], unreadable: Option<&str>, inventory: &PackageInventory, log_folder: &str) -> String {
    let newest_first = rows.iter().skip(rows.len().saturating_sub(SHOWN)).rev();
    records(
        std::iter::once(vec![unreadable.unwrap_or("").to_string()])
            .chain(newest_first.map(|record| vec![record.detail(), retry_key(record, inventory).unwrap_or_default(), log_to_open(record, log_folder).unwrap_or_default()])),
    )
}

/// See [`history_records`]. Reads the history on record and the last inventory.
pub fn history(log_folder: &str) -> String {
    let (rows, unreadable) = packages().history();
    history_records(&rows, unreadable.as_deref(), &inventory(), log_folder)
}

/// The diagnostics text for review: the last 100 operations, with paths, credentials and
/// addresses removed. `windows_version` is what the application reports about Windows.
pub fn diagnostics(windows_version: &str) -> String {
    packages().diagnostics(windows_version)
}

/// See [`history`].
///
/// # Safety
/// `log_folder` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_history(log_folder: *const u16) -> *mut u16 {
    guard(|| give(&history(&take(log_folder))))
}

/// See [`diagnostics`].
///
/// # Safety
/// `windows_version` must be null or point to a NUL-terminated UTF-16 string.
#[no_mangle]
pub unsafe extern "C" fn oi_diagnostics(windows_version: *const u16) -> *mut u16 {
    guard(|| give(&diagnostics(&take(windows_version))))
}

/// Licences and credits, as text.
#[no_mangle]
pub extern "C" fn oi_notices() -> *mut u16 {
    guard(|| give(NOTICES.trim_start_matches('\u{feff}')))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{FIELD, RECORD};
    use oneinstall_core::model::PackageRecord;

    fn rows(text: &str) -> Vec<Vec<&str>> {
        text.split(RECORD).map(|record| record.split(FIELD).collect()).collect()
    }

    fn operation(action: &str, id: &str, source: &str, outcome: &str) -> OperationRecord {
        OperationRecord {
            timestamp: "2026-11-18 10:00:00".to_string(),
            action: action.to_string(),
            id: Some(id.to_string()),
            source: Some(source.to_string()),
            name: Some("Some app".to_string()),
            outcome: outcome.to_string(),
            message: "What happened.".to_string(),
            log_path: None,
            exit_code: 1,
        }
    }

    fn machine(packages: Vec<PackageRecord>) -> PackageInventory {
        PackageInventory { complete: true, partial: false, packages, message: None }
    }

    fn seven_zip() -> &'static oneinstall_core::queue::CatalogApp {
        catalog().iter().find(|app| app.key == "extra_7zip").unwrap()
    }

    #[test]
    fn a_failed_install_is_offered_again_only_when_the_app_is_known_missing() {
        let id = seven_zip().ids[0].clone();
        let missing = machine(Vec::new());
        assert_eq!(retry_key(&operation("Install", &id, "winget", "Failed"), &missing).as_deref(), Some("extra_7zip"));
        // The package identity is compared as PowerShell compares it, without regard to case.
        assert_eq!(retry_key(&operation("Install", &id.to_uppercase(), "winget", "Failed"), &missing).as_deref(), Some("extra_7zip"));
        // Not a failure, not an install, not WinGet, or not in the catalog: nothing to retry.
        assert_eq!(retry_key(&operation("Install", &id, "winget", "Success"), &missing), None);
        assert_eq!(retry_key(&operation("Remove", &id, "winget", "Failed"), &missing), None);
        assert_eq!(retry_key(&operation("Install", &id, "msstore", "Failed"), &missing), None);
        assert_eq!(retry_key(&operation("Install", "No.Such.Package", "winget", "Failed"), &missing), None);
        // Installed since, or a machine whose state is unknown: the retry is withheld.
        let installed = machine(vec![PackageRecord {
            id: Some(id.clone()),
            name: Some("7-Zip".to_string()),
            source: Some("winget".to_string()),
            installed_version: Some("24.09".to_string()),
        }]);
        assert_eq!(retry_key(&operation("Install", &id, "winget", "Failed"), &installed), None);
        assert_eq!(retry_key(&operation("Install", &id, "winget", "Failed"), &PackageInventory::default()), None);
    }

    #[test]
    fn only_a_log_inside_the_log_folder_can_be_opened() {
        let folder = std::env::temp_dir().join(format!("1nstall-rust-history-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        let logs = folder.join("Logs");
        std::fs::create_dir_all(&logs).unwrap();
        let inside = logs.join("session.log");
        let outside = folder.join("elsewhere.log");
        std::fs::write(&inside, "log").unwrap();
        std::fs::write(&outside, "log").unwrap();
        let logs = logs.display().to_string();
        let with_log = |log: &str| OperationRecord { log_path: Some(log.to_string()), ..operation("Install", "x", "winget", "Success") };

        assert_eq!(log_to_open(&with_log(&inside.display().to_string()), &logs), Some(inside.display().to_string()));
        assert_eq!(
            log_to_open(&with_log(&inside.display().to_string().to_uppercase()), &logs.to_lowercase()).map(|log| log.to_lowercase()),
            Some(inside.display().to_string().to_lowercase())
        );
        assert_eq!(log_to_open(&with_log(&outside.display().to_string()), &logs), None);
        // A path that climbs out of the log folder is outside it.
        assert_eq!(log_to_open(&with_log(&format!("{logs}\\..\\elsewhere.log")), &logs), None);
        assert_eq!(log_to_open(&with_log(&format!("{logs}\\gone.log")), &logs), None);
        assert_eq!(log_to_open(&with_log(""), &logs), None);
        assert_eq!(log_to_open(&operation("Install", "x", "winget", "Success"), &logs), None);
        let _ = std::fs::remove_dir_all(&folder);
    }

    #[test]
    fn the_page_shows_the_last_hundred_newest_first() {
        let operations: Vec<OperationRecord> =
            (0..130).map(|number| OperationRecord { message: format!("operation {number}"), ..operation("Remove", "x", "winget", "Success") }).collect();
        let shown = history_records(&operations, None, &machine(Vec::new()), "");
        let shown = rows(&shown);
        assert_eq!(shown[0], [""]);
        assert_eq!(shown.len(), 101);
        assert_eq!(shown[1], ["2026-11-18 10:00:00 \u{b7} Remove \u{b7} Some app \u{b7} Success\r\noperation 129", "", ""]);
        assert_eq!(shown[100][0], "2026-11-18 10:00:00 \u{b7} Remove \u{b7} Some app \u{b7} Success\r\noperation 30");

        let nothing = history_records(&[], Some("Operation history unavailable: it is not valid."), &machine(Vec::new()), "");
        assert_eq!(rows(&nothing), [["Operation history unavailable: it is not valid."]]);
    }

    #[test]
    fn the_notices_are_embedded() {
        assert!(NOTICES.contains("1nstall"));
        assert!(NOTICES.len() > 2000);
    }
}
