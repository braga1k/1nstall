//! Drives remove -> scan -> clean on the same eight fixture apps as `oracle/observe-machine.ps1`
//! and compares each recorded line with what 3.6 produced (`oracle/golden/v3.6.0/removal.jsonl`).
//!
//! It registers fixture apps, runs a stand-in uninstaller, recycles folders and deletes
//! registry keys, so it only runs when `ORACLE_DISPOSABLE=1` (CI runners, VMs).
//!
//! A line may differ from 3.6 only if it is listed, with its reason, in
//! `engine/oracle-removal-divergences.json`.
#![cfg(windows)]

use std::path::PathBuf;
use std::sync::atomic::AtomicBool;

use oneinstall_core::{uninstall, Host, InstalledApp, SpecialFolder};
use oneinstall_platform::inventory::{self, compare_culture, ARP};
use oneinstall_platform::registry::{fixtures, key_exists, Hive, Key};
use oneinstall_platform::removal::{self, LeftoverItem, RemovalOutcome, Stage};
use oneinstall_platform::WindowsHost;
use serde_json::{json, Map, Value};

const JUMPLIST: &str = r"Software\Microsoft\Windows\CurrentVersion\Search\JumplistData";
const VENDOR_KEY: &str = r"Software\OracleFixtureVendor";
/// Size of the stand-in uninstaller 3.6 was recorded with. The Rust stand-in is larger;
/// its size is written as this one so the recordings stay comparable.
const RECORDED_PUBLISHER_BYTES: u64 = 5120;

struct Fixture {
    variant: &'static str,
    mode: &'static str,
    install: String,
    data: String,
    tools: Option<String>,
    product_key: String,
    registry_path: String,
}

struct Paths {
    local: String,
    roaming: String,
    profile: String,
    publisher: String,
}

fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}

fn check<T>(value: Result<T, String>) -> T {
    value.unwrap_or_else(|error| panic!("fixture setup failed: {error}"))
}

fn new_fixture(paths: &Paths, variant: &'static str, mode: &'static str, with_location: bool, command_override: Option<&str>) -> Fixture {
    let registration = format!("OracleFixture{variant}");
    let product = format!("Oracle{variant} Editor");
    let install = format!("{}\\Programs\\{product}", paths.local);
    let data = format!("{}\\OracleFixtureVendor\\{product}", paths.roaming);
    let product_key = format!("{VENDOR_KEY}\\{product}");
    std::fs::create_dir_all(&install).expect("install folder");
    std::fs::create_dir_all(&data).expect("data folder");
    std::fs::write(format!("{install}\\editor.exe"), "fixture executable placeholder").expect("editor");
    std::fs::write(format!("{install}\\readme.txt"), "fixture program file").expect("readme");
    std::fs::write(format!("{data}\\settings.ini"), "fixture user settings").expect("settings");
    check(fixtures::set_text(Hive::CurrentUser, false, &product_key, "Setting", "1"));
    check(fixtures::set_number(Hive::CurrentUser, false, JUMPLIST, &format!("{install}\\editor.exe"), 1));
    check(fixtures::set_number(Hive::CurrentUser, false, JUMPLIST, &format!("{install}Sibling\\editor.exe"), 7));
    let mut uninstaller = paths.publisher.clone();
    let mut tools = None;
    if !with_location {
        // No InstallLocation: the uninstaller lives in its own folder, as with many real apps.
        let folder = format!("{}\\Programs\\Oracle{variant} Tools", paths.local);
        std::fs::create_dir_all(&folder).expect("tools folder");
        uninstaller = format!("{folder}\\publisher.exe");
        std::fs::copy(&paths.publisher, &uninstaller).expect("publisher copy");
        tools = Some(folder);
    }
    let command = command_override.map(str::to_string).unwrap_or_else(|| format!("\"{uninstaller}\" {mode} {registration}"));
    let registry_path = format!("{ARP}\\{registration}");
    check(fixtures::set_text(Hive::CurrentUser, false, &registry_path, "DisplayName", &format!("{product} 2.0 (x64)")));
    check(fixtures::set_text(Hive::CurrentUser, false, &registry_path, "Publisher", "Oracle Fixture Vendor"));
    check(fixtures::set_text(Hive::CurrentUser, false, &registry_path, "DisplayVersion", "2.0"));
    check(fixtures::set_text(Hive::CurrentUser, false, &registry_path, "UninstallString", &command));
    if with_location {
        check(fixtures::set_text(Hive::CurrentUser, false, &registry_path, "InstallLocation", &install));
    }
    Fixture { variant, mode, install, data, tools, product_key, registry_path }
}

fn remove_fixture(fixture: &Fixture) {
    let _ = fixtures::delete_tree(Hive::CurrentUser, false, &fixture.registry_path);
    let _ = fixtures::delete_tree(Hive::CurrentUser, false, &fixture.product_key);
    let _ = fixtures::delete_value(Hive::CurrentUser, false, JUMPLIST, &format!("{}\\editor.exe", fixture.install));
    let _ = fixtures::delete_value(Hive::CurrentUser, false, JUMPLIST, &format!("{}Sibling\\editor.exe", fixture.install));
    for folder in [Some(&fixture.install), Some(&fixture.data), fixture.tools.as_ref()].into_iter().flatten() {
        let _ = std::fs::remove_dir_all(folder);
    }
}

/// Files of a folder tree as `relative\path (N B)`, sorted; `"absent"` if the folder is gone.
fn tree(folder: &str) -> Value {
    if !std::path::Path::new(folder).is_dir() {
        return json!("absent");
    }
    let mut rows: Vec<(String, u64)> = Vec::new();
    let mut pending = vec![folder.to_string()];
    while let Some(current) = pending.pop() {
        for entry in std::fs::read_dir(&current).expect("fixture folder").flatten() {
            let path = entry.path().to_string_lossy().into_owned();
            if entry.path().is_dir() {
                pending.push(path);
            } else {
                let size = entry.metadata().map(|data| data.len()).unwrap_or(0);
                let size = if path.to_lowercase().ends_with("\\publisher.exe") { RECORDED_PUBLISHER_BYTES } else { size };
                rows.push((path, size));
            }
        }
    }
    rows.sort_by(|left, right| compare_culture(&left.0, &right.0, true));
    json!(rows.iter().map(|(path, size)| format!("{} ({size} B)", &path[folder.len() + 1..])).collect::<Vec<_>>())
}

fn state(fixture: &Fixture) -> Value {
    let trace = Key::open(Hive::CurrentUser, false, JUMPLIST).ok().flatten();
    let has = |name: String| trace.as_ref().is_some_and(|key| key.has_value(&name).unwrap_or(false));
    let mut row = Map::new();
    row.insert("Registration".into(), json!(key_exists(Hive::CurrentUser, false, &fixture.registry_path).unwrap_or(false)));
    row.insert("InstallFolder".into(), tree(&fixture.install));
    row.insert("DataFolder".into(), tree(&fixture.data));
    row.insert("ProductKey".into(), json!(key_exists(Hive::CurrentUser, false, &fixture.product_key).unwrap_or(false)));
    row.insert("TraceValue".into(), json!(has(format!("{}\\editor.exe", fixture.install))));
    row.insert("SiblingTraceValue".into(), json!(has(format!("{}Sibling\\editor.exe", fixture.install))));
    if let Some(tools) = &fixture.tools {
        row.insert("ToolsFolder".into(), tree(tools));
    }
    Value::Object(row)
}

fn show_app(host: &WindowsHost, app: &InstalledApp) -> Value {
    let mut row = json!({
        "Id": app.id, "Name": app.name, "Publisher": app.publisher, "Version": app.version, "Kind": app.kind, "Location": app.location,
        "Command": app.command, "RegistryPath": app.registry_path, "PackageFamily": app.package_family,
        "Machine": app.machine, "View32": app.view32, "Msi": app.msi, "CanRemove": app.can_remove, "SizeKB": app.size_kb
    });
    if app.kind.as_deref() == Some("Desktop") {
        row["Parsed"] = match uninstall::get_command(host, app) {
            Ok(command) => json!({"FileName": command.file_name, "Arguments": command.arguments}),
            Err(error) => json!({"Error": error.message}),
        };
    }
    row
}

fn show_outcome(outcome: &RemovalOutcome) -> Value {
    json!({"Name": outcome.name, "Kind": outcome.kind, "Path": outcome.path, "Outcome": outcome.outcome, "Message": outcome.message, "ExitCode": outcome.exit_code})
}

fn show_leftover(item: &LeftoverItem) -> Value {
    json!({
        "Kind": item.kind, "Path": item.path, "ValueName": item.value_name, "Confidence": item.confidence, "Reason": item.reason,
        "Machine": item.machine, "View32": item.view32, "Selected": item.selected, "Files": item.files, "Bytes": item.bytes
    })
}

fn show_flags(app: &InstalledApp) -> Value {
    json!({
        "Name": app.name, "Location": app.location, "RemovalVerified": app.removal_verified, "OwnershipVerified": app.ownership_verified,
        "IdentityVerified": app.identity_verified, "RestartPending": app.restart_requested_at != 0
    })
}

/// Structure of a JSON value: property names with their value kinds.
fn shape(value: &Value) -> Value {
    match value {
        Value::Null => json!("null"),
        Value::String(_) => json!("string"),
        Value::Bool(_) => json!("bool"),
        Value::Number(_) => json!("number"),
        Value::Array(_) => json!("array"),
        Value::Object(fields) => Value::Object(fields.iter().map(|(name, field)| (name.clone(), shape(field))).collect()),
    }
}

fn read_json_shape(path: &str) -> Value {
    let Ok(bytes) = std::fs::read(path) else { return json!("absent") };
    let bom = bytes.starts_with(&[0xEF, 0xBB, 0xBF]);
    let rows: Value = serde_json::from_slice(if bom { &bytes[3..] } else { &bytes }).unwrap_or(Value::Null);
    let rows = rows.as_array().cloned().unwrap_or_default();
    json!({"Utf8Bom": bom, "Rows": rows.len(), "FirstRowShape": rows.first().map(shape).unwrap_or(json!("null"))})
}

fn show_backup(folder: Option<&str>) -> Value {
    let Some(folder) = folder.filter(|folder| std::path::Path::new(folder).is_dir()) else { return json!("absent") };
    let mut files: Vec<String> =
        std::fs::read_dir(folder).expect("backup folder").flatten().filter(|entry| entry.path().is_file()).map(|entry| entry.file_name().to_string_lossy().into_owned()).collect();
    files.sort_by(|left, right| compare_culture(left, right, true));
    let mut exports: Vec<(String, usize, String)> = Vec::new();
    for name in files.iter().filter(|name| name.to_lowercase().ends_with(".reg")) {
        let bytes = std::fs::read(format!("{folder}\\{name}")).expect("registry backup");
        let units: Vec<u16> = bytes.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect();
        let text = String::from_utf16_lossy(&units);
        let keys: Vec<&str> = text.split("\r\n").filter(|line| line.starts_with('[')).collect();
        let first_bytes = bytes.iter().take(4).map(|byte| format!("{byte:02X}")).collect::<Vec<_>>().join("-");
        exports.push((keys.first().copied().unwrap_or("").to_string(), keys.len(), first_bytes));
    }
    exports.sort_by(|left, right| compare_culture(&left.0, &right.0, true));
    let restore = match std::fs::read_to_string(format!("{folder}\\RESTORE.txt")) {
        Ok(text) => {
            let mut lines: Vec<&str> = text.split("\r\n").collect();
            if lines.last() == Some(&"") {
                lines.pop();
            }
            json!(lines)
        }
        Err(_) => json!("absent"),
    };
    json!({
        "Folder": folder, "Files": files,
        "RegistryExports": exports.iter().map(|(key, count, bytes)| json!({"FirstKey": key, "Keys": count, "FirstBytes": bytes})).collect::<Vec<_>>(),
        "Restore": restore,
        "ItemsJson": read_json_shape(&format!("{folder}\\items.json")), "ResultsJson": read_json_shape(&format!("{folder}\\results.json"))
    })
}

fn run_variant(host: &WindowsHost, fixture: &Fixture) -> Value {
    let mut row = Map::new();
    row.insert("Variant".into(), json!(fixture.variant));
    row.insert("Mode".into(), json!(fixture.mode));
    row.insert("StateBefore".into(), state(fixture));
    let listed: Vec<InstalledApp> = inventory::inventory(host).apps.into_iter().filter(|app| app.registry_path.as_deref() == Some(fixture.registry_path.as_str())).collect();
    row.insert("Listed".into(), json!(listed.len()));
    if listed.len() != 1 {
        return Value::Object(row);
    }
    let mut apps = listed;
    row.insert("Model".into(), show_app(host, &apps[0]));
    let mut stages: Vec<String> = Vec::new();
    let removal = removal::remove(host, &mut apps, &AtomicBool::new(false), &mut |stage: Stage<'_>| stages.push(stage.state.to_string()));
    row.insert(
        "Remove".into(),
        json!({"Results": removal.results.iter().map(show_outcome).collect::<Vec<_>>(), "Messages": removal.messages, "Stages": stages, "AppAfter": show_flags(&apps[0])}),
    );
    row.insert("StateAfterRemove".into(), state(fixture));
    match removal::scan(host, &mut apps) {
        Err(error) => {
            row.insert("Error".into(), json!(format!("InvalidOperationException: {error}")));
            return Value::Object(row);
        }
        Ok(scan) => {
            let mut leftovers = scan.leftovers.clone();
            leftovers.sort_by(|left, right| {
                compare_culture(&left.kind, &right.kind, true)
                    .then_with(|| compare_culture(&left.path, &right.path, true))
                    .then_with(|| compare_culture(left.value_name.as_deref().unwrap_or(""), right.value_name.as_deref().unwrap_or(""), true))
            });
            row.insert(
                "Scan".into(),
                json!({"ScannedApps": scan.scanned_apps, "IncompleteChecks": scan.incomplete_checks, "Messages": scan.messages, "Leftovers": leftovers.iter().map(show_leftover).collect::<Vec<_>>(), "AppAfter": show_flags(&apps[0])}),
            );
            if !leftovers.is_empty() {
                match removal::clean(host, &leftovers) {
                    Err(error) => {
                        row.insert("Error".into(), json!(format!("InvalidOperationException: {error}")));
                        return Value::Object(row);
                    }
                    Ok(clean) => {
                        row.insert(
                            "Clean".into(),
                            json!({"Results": clean.results.iter().map(show_outcome).collect::<Vec<_>>(), "Messages": clean.messages, "RecycledBytes": clean.recycled_bytes, "Backup": show_backup(clean.backup_folder.as_deref())}),
                        );
                    }
                }
            }
        }
    }
    row.insert("StateAfterClean".into(), state(fixture));
    Value::Object(row)
}

fn show_history(host: &WindowsHost) -> Value {
    let path = removal::history_file(host);
    let Ok(bytes) = std::fs::read(&path) else { return json!("absent") };
    let bom = bytes.starts_with(&[0xEF, 0xBB, 0xBF]);
    let rows: Value = serde_json::from_slice(if bom { &bytes[3..] } else { &bytes }).unwrap_or(Value::Null);
    let mut rows: Vec<Value> =
        rows.as_array().cloned().unwrap_or_default().into_iter().filter(|row| row["RegistryPath"].as_str().is_some_and(|path| path.contains("OracleFixture"))).collect();
    rows.sort_by(|left, right| compare_culture(left["RegistryPath"].as_str().unwrap_or(""), right["RegistryPath"].as_str().unwrap_or(""), true));
    let fixtures: Vec<Value> = rows
        .iter()
        .map(|row| {
            json!({
                "Id": row["Id"], "Name": row["Name"], "Location": row["Location"], "Command": row["Command"], "CanRemove": row["CanRemove"],
                "RemovalVerified": row["RemovalVerified"], "OwnershipVerified": row["OwnershipVerified"], "IdentityVerified": row["IdentityVerified"],
                "RestartPending": row["RestartRequestedAt"].as_i64().unwrap_or(0) != 0
            })
        })
        .collect();
    json!({"File": path, "Utf8Bom": bom, "FixtureRows": rows.len(), "RowShape": rows.first().map(shape).unwrap_or(json!("null")), "Fixtures": fixtures})
}

/// Writes machine paths as `{LOCALAPPDATA}`, `{APPDATA}`, `{USERPROFILE}`, and backup stamps
/// and generated file names as `{STAMP}` and `{GUID}`, like the recording.
fn normalise(paths: &Paths, json: &str) -> String {
    let mut text = json.to_string();
    for (path, name) in [(&paths.local, "{LOCALAPPDATA}"), (&paths.roaming, "{APPDATA}"), (&paths.profile, "{USERPROFILE}")] {
        let escaped = regex::escape(&path.replace('\\', "\\\\"));
        text = regex::Regex::new(&format!("(?i){escaped}")).expect("path pattern").replace_all(&text, regex::NoExpand(name)).into_owned();
    }
    text = regex::Regex::new(r"\d{8}-\d{6}-[0-9a-f]{8}").expect("stamp pattern").replace_all(&text, "{STAMP}").into_owned();
    // A 32-digit generated name not adjacent to other letters or digits.
    regex::Regex::new(r"(^|[^0-9A-Za-z])[0-9a-f]{32}([^0-9A-Za-z]|$)").expect("name pattern").replace_all(&text, "${1}{GUID}${2}").into_owned()
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut text = String::new();
    for chunk in bytes.chunks(3) {
        let value = (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        text.push(ALPHABET[(value >> 18) as usize & 63] as char);
        text.push(ALPHABET[(value >> 12) as usize & 63] as char);
        text.push(if chunk.len() > 1 { ALPHABET[(value >> 6) as usize & 63] as char } else { '=' });
        text.push(if chunk.len() > 2 { ALPHABET[value as usize & 63] as char } else { '=' });
    }
    text
}

#[test]
fn rust_removal_matches_the_recorded_behaviour_of_3_6() {
    if std::env::var("ORACLE_DISPOSABLE").as_deref() != Ok("1") {
        println!("oracle removal: skipped; set ORACLE_DISPOSABLE=1 on a disposable machine to run it");
        return;
    }
    let host = WindowsHost::new();
    let local = host.special_folder(SpecialFolder::LocalApplicationData);
    let tools = format!("{local}\\OracleFixtureTools");
    std::fs::create_dir_all(&tools).expect("tools folder");
    let paths = Paths {
        publisher: format!("{tools}\\publisher.exe"),
        roaming: host.special_folder(SpecialFolder::ApplicationData),
        profile: host.special_folder(SpecialFolder::UserProfile),
        local,
    };
    std::fs::copy(env!("CARGO_BIN_EXE_oracle-publisher"), &paths.publisher).expect("stand-in uninstaller");
    let shell = format!("\"{}\\cmd.exe\" /c exit 0", host.special_folder(SpecialFolder::System));
    let variants: [(&str, &str, bool, Option<&str>); 8] = [
        ("Alpha", "clean", true, None),
        ("Bravo", "cancel", true, None),
        ("Charlie", "keep", true, None),
        ("Delta", "restart", true, None),
        ("Echo", "child", true, None),
        ("Foxtrot", "fail", true, None),
        ("Golf", "clean", false, None),
        ("Hotel", "keep", true, Some(&shell)),
    ];
    let mut lines: Vec<(String, String)> = Vec::new();
    for (variant, mode, with_location, command) in variants {
        let fixture = new_fixture(&paths, variant, mode, with_location, command);
        let row = run_variant(&host, &fixture);
        lines.push((variant.to_string(), normalise(&paths, &row.to_string())));
        remove_fixture(&fixture);
    }
    lines.push(("History".to_string(), normalise(&paths, &json!({"History": show_history(&host)}).to_string())));
    let _ = fixtures::delete_tree(Hive::CurrentUser, false, VENDOR_KEY);
    let _ = std::fs::remove_dir_all(format!("{}\\OracleFixtureVendor", paths.roaming));
    let _ = std::fs::remove_dir_all(&tools);

    let golden_path = repository().join("oracle/golden/v3.6.0/removal.jsonl");
    let golden: Vec<Value> = std::fs::read_to_string(&golden_path)
        .expect("removal golden")
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_str(line).expect("golden line"))
        .collect();
    let listed: Value =
        serde_json::from_str(&std::fs::read_to_string(repository().join("engine/oracle-removal-divergences.json")).expect("divergences")).expect("divergences json");
    assert_eq!(golden.len(), lines.len(), "the recording and this run have different numbers of lines");
    let (mut identical, mut divergent, mut unexplained) = (0usize, 0usize, 0usize);
    for (index, (name, text)) in lines.iter().enumerate() {
        let actual: Value = serde_json::from_str(text).expect("own line");
        if actual == golden[index] {
            identical += 1;
            continue;
        }
        if listed["divergences"].as_array().is_some_and(|entries| entries.iter().any(|entry| entry["line"] == json!(name) && entry["rust"] == actual)) {
            divergent += 1;
            continue;
        }
        unexplained += 1;
        // Publish the Rust line so it can be reviewed without downloading artifacts.
        let encoded = base64(text.as_bytes());
        let chunks: Vec<&str> = encoded.as_bytes().chunks(2800).map(|chunk| std::str::from_utf8(chunk).expect("ascii")).collect();
        for (part, chunk) in chunks.iter().enumerate() {
            println!("::warning title=engine removal line {name} [{}/{}]::{chunk}", part + 1, chunks.len());
        }
    }
    println!("oracle removal: {} lines; identical {identical}; listed divergences {divergent}; unexplained {unexplained}", lines.len());
    assert_eq!(unexplained, 0, "{unexplained} recorded lines differ from 3.6 without a declared reason");
}
