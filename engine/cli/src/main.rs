//! Read-only command line over the engine. Every command prints JSON and changes nothing.

use oneinstall_core::packages::installed_state;
use oneinstall_core::queue::{plan, CatalogApp};
use oneinstall_core::uninstall;
use oneinstall_platform::packages::Packages;
use oneinstall_platform::{inventory, removal, WindowsHost};
use serde_json::{json, Value};

const USAGE: &str = "oneinstall <command>

Read-only commands, all printing JSON:
  apps                          installed desktop and Store apps, as the uninstall list shows them
  packages                      what WinGet reports as installed (partial inventory from export)
  state <catalog.json>          installed state of every catalog app
  plan <catalog.json> <key>...  install order for a selection, dependencies first
  history                       operation history and removal history
  version                       engine version";

fn fail(message: &str) -> ! {
    eprintln!("{message}");
    std::process::exit(2);
}

fn load_catalog(path: &str) -> Vec<CatalogApp> {
    let text = std::fs::read_to_string(path).unwrap_or_else(|error| fail(&format!("Cannot read {path}: {error}")));
    let rows: Value = serde_json::from_str(text.trim_start_matches('\u{feff}')).unwrap_or_else(|error| fail(&format!("{path} is not JSON: {error}")));
    let list =
        |row: &Value, name: &str| -> Vec<String> { row[name].as_array().map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default() };
    rows.as_array()
        .unwrap_or_else(|| fail("The catalog must be a JSON array."))
        .iter()
        .map(|row| CatalogApp {
            key: row["Key"].as_str().unwrap_or("").to_string(),
            name: row["Name"].as_str().unwrap_or("").to_string(),
            ids: list(row, "Ids"),
            url: row["Url"].as_str().unwrap_or("").to_string(),
            requires: list(row, "Requires"),
        })
        .collect()
}

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let host = WindowsHost::new();
    let output = match arguments.first().map(String::as_str) {
        Some("version") => json!({"engine": env!("CARGO_PKG_VERSION")}),
        Some("apps") => {
            let result = inventory::inventory(&host);
            let apps: Vec<Value> = result
                .apps
                .iter()
                .map(|app| {
                    json!({
                        "Id": app.id, "Name": app.name, "Publisher": app.publisher, "Version": app.version, "Kind": app.kind, "Location": app.location,
                        "LocationInferred": app.location_inferred, "Machine": app.machine, "View32": app.view32, "Msi": app.msi, "CanRemove": app.can_remove, "SizeKB": app.size_kb,
                        "Names": uninstall::names(&host, app)
                    })
                })
                .collect();
            json!({"Apps": apps, "Warnings": result.warnings})
        }
        Some("packages") => {
            let found = Packages::new(&host).inventory(false);
            json!({
                "Complete": found.complete, "Partial": found.partial, "Message": found.message,
                "Packages": found.packages.iter().map(|package| json!({"Id": package.id, "Source": package.source, "InstalledVersion": package.installed_version})).collect::<Vec<_>>()
            })
        }
        Some("state") => {
            let catalog = load_catalog(arguments.get(1).unwrap_or_else(|| fail(USAGE)));
            let found = Packages::new(&host).inventory(false);
            json!(catalog.iter().map(|app| json!({"Key": app.key, "State": installed_state(&found, Some(&app.ids), "winget")})).collect::<Vec<_>>())
        }
        Some("plan") => {
            let catalog = load_catalog(arguments.get(1).unwrap_or_else(|| fail(USAGE)));
            match plan(&catalog, &arguments[2..]) {
                Ok(ordered) => json!(ordered.iter().map(|app| json!({"Key": app.key, "Name": app.name, "Ids": app.ids, "Url": app.url})).collect::<Vec<_>>()),
                Err(error) => fail(&error.message),
            }
        }
        Some("history") => {
            let (operations, error) = Packages::new(&host).history();
            json!({
                "Operations": operations.iter().map(|row| json!({"Timestamp": row.timestamp, "Action": row.action, "Id": row.id, "Source": row.source, "Name": row.name, "Outcome": row.outcome, "ExitCode": row.exit_code})).collect::<Vec<_>>(),
                "OperationsError": error,
                "Removed": removal::load_history(&host).iter().map(|app| json!({"Id": app.id, "Name": app.name, "RemovalVerified": app.removal_verified})).collect::<Vec<_>>()
            })
        }
        _ => fail(USAGE),
    };
    println!("{output}");
}
