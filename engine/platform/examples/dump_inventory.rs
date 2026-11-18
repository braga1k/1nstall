//! Prints the installed-app inventory as JSON lines, for comparison with 3.6. Read-only.
use oneinstall_core::{uninstall, InstalledApp};
use oneinstall_platform::{inventory, WindowsHost};
use serde_json::json;

fn row(host: &WindowsHost, app: &InstalledApp) -> serde_json::Value {
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

fn main() {
    let host = WindowsHost::new();
    let mode = std::env::args().nth(1).unwrap_or_default();
    let apps = if mode == "hidden" {
        let mut warnings = Vec::new();
        let apps = inventory::desktop(&host, &mut warnings, true);
        eprintln!("warnings: {}", warnings.len());
        apps
    } else {
        let result = inventory::inventory(&host);
        eprintln!("warnings: {}", result.warnings.len());
        result.apps
    };
    for app in &apps {
        println!("{}", row(&host, app));
    }
}
