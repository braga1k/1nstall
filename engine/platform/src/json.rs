//! The on-disk JSON shapes 3.6 wrote, so 3.6 and 4.0 can read each other's files.

use oneinstall_core::InstalledApp;
use serde_json::{json, Map, Value};

fn detail(app: &InstalledApp) -> String {
    let mut text =
        format!("{}  \u{b7}  {}  \u{b7}  {}", app.publisher.as_deref().unwrap_or("Unknown publisher"), app.version.as_deref().unwrap_or(""), app.kind.as_deref().unwrap_or(""));
    if app.size_kb > 0 {
        let megabytes = app.size_kb as f64 / 1024.0;
        let rounded = (megabytes * 10.0).round() / 10.0;
        text.push_str(&format!("  \u{b7}  {} MB", if rounded.fract() == 0.0 { format!("{rounded:.0}") } else { format!("{rounded:.1}") }));
    }
    text
}

/// One entry of `uninstall-history.json`, with the property names and order 3.6 used.
pub fn app_to_json(app: &InstalledApp) -> Value {
    let mut row = Map::new();
    row.insert("Id".into(), json!(app.id));
    row.insert("Name".into(), json!(app.name));
    row.insert("Publisher".into(), json!(app.publisher));
    row.insert("Version".into(), json!(app.version));
    row.insert("Kind".into(), json!(app.kind));
    row.insert("Location".into(), json!(app.location));
    row.insert("Command".into(), json!(app.command));
    row.insert("RegistryPath".into(), json!(app.registry_path));
    row.insert("PackageFamily".into(), json!(app.package_family));
    row.insert("Machine".into(), json!(app.machine));
    row.insert("View32".into(), json!(app.view32));
    row.insert("Msi".into(), json!(app.msi));
    row.insert("RemovalVerified".into(), json!(app.removal_verified));
    row.insert("OwnershipVerified".into(), json!(app.ownership_verified));
    row.insert("IdentityVerified".into(), json!(app.identity_verified));
    row.insert("RestartRequestedAt".into(), json!(app.restart_requested_at));
    row.insert("CanRemove".into(), json!(app.can_remove));
    row.insert("SizeKB".into(), json!(app.size_kb));
    row.insert("Detail".into(), json!(detail(app)));
    Value::Object(row)
}

fn text(row: &Value, name: &str) -> Option<String> {
    row.get(name).and_then(Value::as_str).map(str::to_string)
}

fn flag(row: &Value, name: &str) -> bool {
    row.get(name).and_then(Value::as_bool).unwrap_or(false)
}

fn number(row: &Value, name: &str) -> i64 {
    row.get(name).and_then(Value::as_i64).unwrap_or(0)
}

/// Reads one history entry. Unknown properties are ignored; missing ones take their defaults.
pub fn app_from_json(row: &Value) -> InstalledApp {
    InstalledApp {
        id: text(row, "Id"),
        name: text(row, "Name"),
        publisher: text(row, "Publisher"),
        version: text(row, "Version"),
        kind: text(row, "Kind"),
        location: text(row, "Location"),
        location_inferred: false,
        command: text(row, "Command"),
        registry_path: text(row, "RegistryPath"),
        package_family: text(row, "PackageFamily"),
        machine: flag(row, "Machine"),
        view32: flag(row, "View32"),
        msi: flag(row, "Msi"),
        removal_verified: flag(row, "RemovalVerified"),
        ownership_verified: flag(row, "OwnershipVerified"),
        identity_verified: flag(row, "IdentityVerified"),
        restart_requested_at: number(row, "RestartRequestedAt"),
        can_remove: flag(row, "CanRemove"),
        size_kb: number(row, "SizeKB"),
    }
}
