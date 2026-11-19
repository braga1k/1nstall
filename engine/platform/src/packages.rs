//! Running WinGet, reading what is installed, the operation history and saved selections.

use std::sync::Mutex;
use std::time::Duration;

use oneinstall_core::packages::{arguments, explain, installed_state, outcome, parse_export, parse_setup, parse_structured, quote, redact};
use oneinstall_core::{EngineError, Host, PackageInventory, SetupSelection, SpecialFolder};
use serde_json::{json, Map, Value};

use crate::process::{now_filetime, run_captured, RunError};

/// Longest output kept from a program, in UTF-16 units, as in 3.6.
const OUTPUT_LIMIT: usize = 1_048_576;
const FILE_LIMIT: u64 = 4_194_304;
const UTF8_BOM: &[u8] = &[0xEF, 0xBB, 0xBF];

#[derive(Debug, Clone)]
pub struct ProcessResult {
    pub exit_code: i32,
    pub output: String,
    pub error: String,
}

/// One line of the operation history (`operations.json`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct OperationRecord {
    pub timestamp: String,
    pub action: String,
    pub id: Option<String>,
    pub source: Option<String>,
    pub name: Option<String>,
    pub outcome: String,
    pub message: String,
    pub log_path: Option<String>,
    pub exit_code: i32,
}

impl OperationRecord {
    pub fn detail(&self) -> String {
        format!("{} \u{b7} {} \u{b7} {} \u{b7} {}\r\n{}", self.timestamp, self.action, self.name.as_deref().unwrap_or(""), self.outcome, self.message)
    }

    fn to_json(&self) -> Value {
        let mut row = Map::new();
        row.insert("Timestamp".into(), json!(self.timestamp));
        row.insert("Action".into(), json!(self.action));
        row.insert("Id".into(), json!(self.id));
        row.insert("Source".into(), json!(self.source));
        row.insert("Name".into(), json!(self.name));
        row.insert("Outcome".into(), json!(self.outcome));
        row.insert("Message".into(), json!(self.message));
        row.insert("LogPath".into(), json!(self.log_path));
        row.insert("ExitCode".into(), json!(self.exit_code));
        row.insert("Detail".into(), json!(self.detail()));
        Value::Object(row)
    }

    fn from_json(row: &Value) -> Option<Self> {
        let text = |name: &str| row.get(name).and_then(Value::as_str).map(str::to_string);
        let required = |name: &str| text(name).filter(|value| !value.trim().is_empty());
        Some(Self {
            timestamp: required("Timestamp")?,
            action: required("Action")?,
            outcome: required("Outcome")?,
            id: text("Id"),
            source: text("Source"),
            name: text("Name"),
            message: text("Message").unwrap_or_default(),
            log_path: text("LogPath"),
            exit_code: row.get("ExitCode").and_then(Value::as_i64).unwrap_or(0) as i32,
        })
    }
}

fn truncate(text: String) -> String {
    if text.encode_utf16().count() <= OUTPUT_LIMIT {
        return text;
    }
    let mut kept = String::new();
    let mut units = 0usize;
    for character in text.chars() {
        units += character.len_utf16();
        if units > OUTPUT_LIMIT {
            break;
        }
        kept.push(character);
    }
    kept + "\n[truncated]"
}

/// Runs a program without a window and captures its output as UTF-8.
///
/// A `timeout_ms` of 0 waits without limit: an installer in progress is never ended.
pub fn run(exe: &str, arguments: &str, timeout_ms: u32) -> Result<ProcessResult, String> {
    let timeout = (timeout_ms > 0).then(|| Duration::from_millis(u64::from(timeout_ms)));
    match run_captured(exe, arguments, timeout) {
        Ok(result) => Ok(ProcessResult { exit_code: result.exit_code, output: truncate(result.output), error: truncate(result.error) }),
        Err(RunError::TimedOut) => Err("The package service timed out. Check connectivity and refresh.".to_string()),
        Err(RunError::Start(error)) => Err(error),
    }
}

/// Finds `winget.exe`: the per-user app alias first, then every `PATH` entry. Empty if absent.
pub fn find_winget(host: &dyn Host, preferred: &str, path_variable: &str) -> String {
    if host.file_exists(preferred) {
        return preferred.to_string();
    }
    for entry in path_variable.split(';') {
        if entry.trim().is_empty() {
            continue;
        }
        let candidate = format!("{}\\winget.exe", entry.trim().trim_matches('"').trim_end_matches('\\'));
        if host.file_exists(&candidate) {
            return candidate;
        }
    }
    String::new()
}

fn random_hex(length: usize) -> String {
    use std::hash::{BuildHasher, Hasher};
    let mut text = String::new();
    while text.len() < length {
        let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
        hasher.write_i64(now_filetime());
        text.push_str(&format!("{:016x}", hasher.finish()));
    }
    text.truncate(length);
    text
}

/// Current UTC time in the round-trip format 3.6 stored: `2026-11-18T13:45:12.1234567+00:00`.
fn timestamp() -> String {
    let ticks = now_filetime();
    let fraction = ticks.rem_euclid(10_000_000);
    let seconds = ticks.div_euclid(10_000_000);
    let (days, second_of_day) = (seconds.div_euclid(86_400), seconds.rem_euclid(86_400));
    // Days since 1601-01-01 to a civil date (Howard Hinnant's algorithm, shifted to 0000-03-01).
    let z = days + 584_694;
    let era = z.div_euclid(146_097);
    let day_of_era = z.rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{fraction:07}+00:00", second_of_day / 3600, second_of_day % 3600 / 60, second_of_day % 60)
}

fn read_text(path: &str) -> std::io::Result<String> {
    let bytes = std::fs::read(path)?;
    Ok(String::from_utf8_lossy(bytes.strip_prefix(UTF8_BOM).unwrap_or(&bytes)).into_owned())
}

fn write_with_bom(path: &str, text: &str) -> std::io::Result<()> {
    let mut bytes = UTF8_BOM.to_vec();
    bytes.extend_from_slice(text.as_bytes());
    std::fs::write(path, bytes)
}

/// The package side of the engine, bound to a data folder and a WinGet executable.
pub struct Packages {
    pub data_root: String,
    pub winget: String,
    /// PowerShell 7, which reads the complete inventory when the Microsoft.WinGet.Client
    /// module is installed. Empty when the complete inventory is not to be asked for.
    pub shell7: String,
    history_gate: Mutex<()>,
}

/// Where PowerShell 7 is installed for every user, as 3.6 looks for it.
pub fn shell7_path(host: &dyn Host) -> String {
    format!("{}\\PowerShell\\7\\pwsh.exe", host.special_folder(SpecialFolder::ProgramFiles))
}

const SHELL7_MISSING: &str = "Installed status requires PowerShell 7 and Microsoft's Microsoft.WinGet.Client module. Install them yourself; 1nstall never installs prerequisites automatically. Automatic catalog installation remains available with WinGet.";
const INVENTORY_REFRESHED: &str =
    "Inventory refreshed. WinGet reports aggregate installed versions; installation scopes are not exposed by this interface. Guided and uncorrelated apps remain Unknown.";
const STRUCTURED_QUERY: &str = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); Import-Module Microsoft.WinGet.Client -MinimumVersion 1.7.0 -ErrorAction Stop; $rows=@(Get-WinGetPackage -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Id=[string]$_.Id;Name=[string]$_.Name;Source=[string]$_.Source;InstalledVersion=[string]$_.InstalledVersion} }); ConvertTo-Json -InputObject $rows -Depth 4 -Compress";

impl Packages {
    /// Uses `%LOCALAPPDATA%\1nstall` and the WinGet found on this machine.
    pub fn new(host: &dyn Host) -> Self {
        let local = host.special_folder(SpecialFolder::LocalApplicationData);
        let preferred = format!("{local}\\Microsoft\\WindowsApps\\winget.exe");
        let winget = find_winget(host, &preferred, &std::env::var("PATH").unwrap_or_default());
        Self { data_root: format!("{local}\\1nstall"), winget, shell7: shell7_path(host), history_gate: Mutex::new(()) }
    }

    /// Uses the given data folder and WinGet executable, and only `winget export` for the
    /// inventory, unless [`Packages::with_shell7`] names a PowerShell 7 as well.
    pub fn with(data_root: &str, winget: &str) -> Self {
        Self { data_root: data_root.to_string(), winget: winget.to_string(), shell7: String::new(), history_gate: Mutex::new(()) }
    }

    /// Reads the complete inventory with this PowerShell 7.
    pub fn with_shell7(mut self, shell7: &str) -> Self {
        self.shell7 = shell7.to_string();
        self
    }

    /// The complete inventory, through PowerShell 7 and the Microsoft.WinGet.Client module
    /// (`Structured` and the first half of `Inventory` in 3.6). An error says why not.
    fn structured(&self) -> Result<PackageInventory, String> {
        if self.shell7.is_empty() || !std::path::Path::new(&self.shell7).is_file() {
            return Err(SHELL7_MISSING.to_string());
        }
        let encoded: Vec<u8> = STRUCTURED_QUERY.encode_utf16().flat_map(u16::to_le_bytes).collect();
        // "-OutputFormat Text" is not in 3.6: without it PowerShell 7 writes its errors as
        // CLIXML when it is not on a console, and the reason shown to the user was unreadable.
        let result = run(&self.shell7, &format!("-NoLogo -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand {}", crate::inventory::base64(&encoded)), 90_000)?;
        if result.exit_code != 0 {
            return Err(format!("WinGet inventory unavailable. Check the Microsoft.WinGet.Client module and connectivity. {}", result.error.trim()));
        }
        let mut complete = parse_structured(result.output.trim().trim_start_matches('\u{feff}')).map_err(|error| error.message)?;
        complete.message = Some(INVENTORY_REFRESHED.to_string());
        Ok(complete)
    }

    pub fn history_path(&self) -> String {
        format!("{}\\operations.json", self.data_root)
    }

    fn read_history(&self) -> Result<Vec<OperationRecord>, String> {
        let path = self.history_path();
        let size = match std::fs::metadata(&path) {
            Ok(data) => data.len(),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(error.to_string()),
        };
        if size > FILE_LIMIT {
            return Err("Operation history exceeds its limit.".to_string());
        }
        let text = read_text(&path).map_err(|error| error.to_string())?;
        let rows: Value = serde_json::from_str(&text).map_err(|error| error.to_string())?;
        let records: Option<Vec<OperationRecord>> = rows.as_array().and_then(|rows| rows.iter().map(OperationRecord::from_json).collect());
        records.ok_or_else(|| "Invalid operation history records.".to_string())
    }

    /// The operation history, oldest first. An unreadable history gives an empty list and
    /// the reason; it is never overwritten.
    pub fn history(&self) -> (Vec<OperationRecord>, Option<String>) {
        let _gate = self.history_gate.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        match self.read_history() {
            Ok(rows) => (rows, None),
            Err(error) => (Vec::new(), Some(format!("Operation history unavailable: {error}"))),
        }
    }

    /// Appends one record, keeping the last 500. If the existing history cannot be read it
    /// is preserved and the record's message says so.
    #[allow(clippy::too_many_arguments)]
    pub fn record(&self, action: &str, id: Option<&str>, source: Option<&str>, name: Option<&str>, outcome: &str, message: &str, code: i32, log: Option<&str>) -> OperationRecord {
        let mut record = OperationRecord {
            timestamp: timestamp(),
            action: action.to_string(),
            id: id.map(str::to_string),
            source: source.map(str::to_string),
            name: name.map(str::to_string),
            outcome: outcome.to_string(),
            message: message.to_string(),
            log_path: log.map(str::to_string),
            exit_code: code,
        };
        let _gate = self.history_gate.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let saved = (|| -> Result<(), String> {
            let mut rows = self.read_history().map_err(|error| format!("Operation history unavailable: {error} Existing history was preserved."))?;
            rows.push(record.clone());
            std::fs::create_dir_all(&self.data_root).map_err(|error| error.to_string())?;
            let skip = rows.len().saturating_sub(500);
            let text = Value::Array(rows.iter().skip(skip).map(OperationRecord::to_json).collect()).to_string();
            let path = self.history_path();
            let temporary = format!("{path}.{}.tmp", random_hex(32));
            write_with_bom(&temporary, &text).map_err(|error| error.to_string())?;
            std::fs::rename(&temporary, &path).map_err(|error| {
                let _ = std::fs::remove_file(&temporary);
                error.to_string()
            })
        })();
        if let Err(error) = saved {
            record.message.push_str(&format!(" History could not be saved: {error}"));
        }
        record
    }

    /// What WinGet reports as installed.
    ///
    /// With PowerShell 7 and the Microsoft.WinGet.Client module, which the user installs or
    /// not, this is the complete inventory: a package that is not listed is not installed.
    /// Without them it is the partial inventory from `winget export`: listed packages are
    /// installed, absent ones are unknown. `accept_source_agreements` adds that flag to the
    /// export; pass it only after the user has accepted the source terms.
    pub fn inventory(&self, accept_source_agreements: bool) -> PackageInventory {
        let structured = match self.structured() {
            Ok(complete) => return complete,
            Err(reason) => reason,
        };
        let mut result = PackageInventory { message: Some(structured.clone()), ..PackageInventory::default() };
        let temporary = format!("{}\\1nstall-inventory-{}.json", std::env::temp_dir().to_string_lossy().trim_end_matches('\\'), random_hex(32));
        let export = (|| -> Result<PackageInventory, String> {
            let unavailable = "WinGet export unavailable; check sources, source agreements and connectivity.";
            let consent = if accept_source_agreements { " --accept-source-agreements" } else { "" };
            let quoted = quote(&temporary).map_err(|error| error.message)?;
            let run = run(&self.winget, &format!("export --output {quoted} --include-versions --disable-interactivity{consent}"), 90_000)?;
            let size = std::fs::metadata(&temporary).map(|data| data.len()).ok();
            if run.exit_code != 0 || size.is_none_or(|size| size > FILE_LIMIT) {
                return Err(unavailable.to_string());
            }
            let text = read_text(&temporary).map_err(|error| error.to_string())?;
            let mut partial = parse_export(&text).map_err(|error| error.message)?;
            partial.message = Some(format!("Partial identity inventory from WinGet export. Included apps can be confirmed; omitted apps remain Unknown. {structured}"));
            Ok(partial)
        })();
        let _ = std::fs::remove_file(&temporary);
        match export {
            Ok(partial) => partial,
            Err(error) => {
                result.message = Some(format!("{structured} {error}"));
                result
            }
        }
    }

    /// Installs one package and records the outcome.
    ///
    /// Exit success alone is `Unknown`. It becomes `Success` only when a fresh inventory lists
    /// that exact identifier and source; a restart, cancellation or failure is never rewritten.
    pub fn install(&self, id: &str, source: &str, name: &str, logs: &str, verifying: Option<&mut dyn FnMut()>) -> OperationRecord {
        let mut log: Option<String> = None;
        let attempt = (|| -> Result<(String, String, i32), String> {
            std::fs::create_dir_all(logs).map_err(|error| error.to_string())?;
            let path = format!("{logs}\\{}.log", random_hex(32));
            log = Some(path.clone());
            let command = arguments(id, source).map_err(|error| error.message)?;
            let result = run(&self.winget, &command, 0)?;
            write_with_bom(&path, &format!("{}\r\n{}", result.output, result.error)).map_err(|error| error.to_string())?;
            let (mut state, mut message) = (outcome(result.exit_code).to_string(), explain(result.exit_code));
            if state == "Unknown" {
                if let Some(verifying) = verifying {
                    verifying();
                }
                // The user accepted the source terms before this install; 3.6 did not pass that on to the export.
                let inventory = self.inventory(true);
                let installed = installed_state(&inventory, Some(&[id.to_string()]), source);
                if installed.starts_with("Installed \u{b7}") {
                    state = "Success".to_string();
                    message = format!("Exact package identity verified: {installed}");
                } else {
                    message = format!("Installer finished; resulting state could not be confirmed. {installed}. {}", inventory.message.as_deref().unwrap_or(""));
                }
            }
            Ok((state, message, result.exit_code))
        })();
        match attempt {
            Ok((state, message, code)) => self.record("Install", Some(id), Some(source), Some(name), &state, &message, code, log.as_deref()),
            Err(error) => self.record("Install", Some(id), Some(source), Some(name), "Failed", &error, -1, log.as_deref()),
        }
    }

    /// The last 100 operations as text with paths, credentials and addresses removed.
    pub fn diagnostics(&self, windows_version: &str) -> String {
        let (rows, _) = self.history();
        let skip = rows.len().saturating_sub(100);
        let lines: Vec<String> = rows
            .iter()
            .skip(skip)
            .map(|row| {
                format!(
                    "{} \u{b7} {} \u{b7} {} \u{b7} {} \u{b7} {} \u{b7} {}\r\n{}",
                    row.timestamp,
                    row.action,
                    row.id.as_deref().unwrap_or(""),
                    row.source.as_deref().unwrap_or(""),
                    row.outcome,
                    row.exit_code,
                    row.message
                )
            })
            .collect();
        redact(Some(&format!("1nstall diagnostics (review before sharing)\r\nWindows {windows_version} \u{b7} x64 True\r\n{}", lines.join("\r\n"))))
    }
}

/// Reads a saved selection file of at most 64 KiB.
pub fn read_setup(file: &str) -> Result<SetupSelection, EngineError> {
    let size = std::fs::metadata(file).map_err(|error| EngineError::io(&error.to_string()))?.len();
    if size > 65536 {
        return Err(EngineError::io("Setup file exceeds 64 KiB."));
    }
    parse_setup(&read_text(file).map_err(|error| EngineError::io(&error.to_string()))?)
}

/// One package of a selection being saved. A missing version is written as `Unknown` and
/// a blank name as the identifier.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupDraft {
    pub id: String,
    pub source: String,
    pub name: Option<String>,
    pub version: Option<String>,
}

/// Saves a version 2 selection. The text is validated with the same rules as loading before
/// anything is written.
pub fn save_setup(path: &str, entries: &[SetupDraft]) -> Result<(), EngineError> {
    let apps: Vec<Value> = entries
        .iter()
        .map(|entry| {
            let name = entry.name.as_deref().filter(|name| !name.trim().is_empty()).unwrap_or(&entry.id);
            let mut row = Map::new();
            row.insert("Id".into(), json!(entry.id));
            row.insert("Source".into(), json!(entry.source));
            row.insert("Name".into(), json!(name));
            row.insert("Version".into(), json!(entry.version.as_deref().unwrap_or("Unknown")));
            Value::Object(row)
        })
        .collect();
    let mut root = Map::new();
    root.insert("Version".into(), json!(2));
    root.insert("Kind".into(), json!("1nstall-selection"));
    root.insert("Apps".into(), Value::Array(apps));
    let text = Value::Object(root).to_string();
    if text.len() > 65536 {
        return Err(EngineError::io("Selection exceeds 64 KiB."));
    }
    parse_setup(&text)?;
    write_with_bom(path, &text).map_err(|error| EngineError::io(&error.to_string()))
}
