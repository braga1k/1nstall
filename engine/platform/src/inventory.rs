//! What is installed: desktop registrations from the registry and Store packages of the current user.

use std::ffi::c_void;
use std::ptr::{null, null_mut};
use std::time::Duration;

use oneinstall_core::text::{eq_ignore_case, starts_with_ignore_case};
use oneinstall_core::{uninstall, Host, InstalledApp, SpecialFolder};
use serde_json::Value;

use crate::process::{run_captured, RunError};
use crate::registry::{self, Hive, Key};

/// Registry path of the uninstall registrations, relative to a hive.
pub const ARP: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";

#[link(name = "shlwapi")]
extern "system" {
    fn SHLoadIndirectString(source: *const u16, output: *mut u16, size: u32, reserved: *mut c_void) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn CompareStringEx(
        locale: *const u16,
        flags: u32,
        left: *const u16,
        left_length: i32,
        right: *const u16,
        right_length: i32,
        version: *const c_void,
        reserved: *const c_void,
        parameter: isize,
    ) -> i32;
}

const NORM_IGNORECASE: u32 = 1;

#[derive(Debug, Clone, Default)]
pub struct AppInventory {
    pub apps: Vec<InstalledApp>,
    pub warnings: Vec<String>,
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Ordering of two texts under the user's culture, as 3.6 sorted lists.
pub fn compare_culture(left: &str, right: &str, ignore_case: bool) -> std::cmp::Ordering {
    let (a, b): (Vec<u16>, Vec<u16>) = (left.encode_utf16().collect(), right.encode_utf16().collect());
    // SAFETY: both buffers are passed with their exact lengths; a null locale means the user default.
    let result = unsafe { CompareStringEx(null(), if ignore_case { NORM_IGNORECASE } else { 0 }, a.as_ptr(), a.len() as i32, b.as_ptr(), b.len() as i32, null(), null(), 0) };
    match result {
        1 => std::cmp::Ordering::Less,
        3 => std::cmp::Ordering::Greater,
        _ => std::cmp::Ordering::Equal,
    }
}

fn blank(text: &Option<String>) -> bool {
    text.as_deref().is_none_or(|text| text.trim().is_empty())
}

/// Directory part of an absolute path; `None` at a root.
fn directory_name(path: &str) -> Option<String> {
    uninstall::parent_directory(path).map(str::to_string)
}

/// Removes a trailing icon index such as `,0` or `, -101` from a `DisplayIcon` value.
fn strip_icon_index(icon: &str) -> &str {
    let Some(comma) = icon.rfind(',') else { return icon };
    let tail = icon[comma + 1..].trim_start();
    let digits = tail.strip_prefix('-').unwrap_or(tail);
    if !digits.is_empty() && digits.chars().all(|c| c.is_ascii_digit()) {
        &icon[..comma]
    } else {
        icon
    }
}

fn read_registration(host: &dyn Host, parent: &Key, child: &str, machine: bool, view32: bool, include_hidden: bool) -> Result<Option<InstalledApp>, String> {
    let Some(key) = parent.open_child(child)? else { return Ok(None) };
    let name = key.text("DisplayName", "")?;
    if name.trim().is_empty() {
        return Ok(None);
    }
    let flag = |value: &str| -> Result<bool, String> { Ok(key.text(value, "0")? == "1") };
    if !include_hidden {
        let release = key.text("ReleaseType", "")?.to_lowercase();
        if flag("SystemComponent")? || !key.text("ParentKeyName", "")?.is_empty() || release.contains("update") || release.contains("hotfix") {
            return Ok(None);
        }
    }
    let mut app = InstalledApp {
        id: Some(format!("{}{}{}", if machine { "HKLM" } else { "HKCU" }, if view32 { "32:" } else { "64:" }, child)),
        registry_path: Some(format!("{ARP}\\{child}")),
        name: Some(name),
        publisher: Some(key.text("Publisher", "")?),
        version: Some(key.text("DisplayVersion", "")?),
        kind: Some("Desktop".to_string()),
        location: Some(key.text("InstallLocation", "")?),
        command: Some(key.text("UninstallString", "")?),
        machine,
        view32,
        msi: flag("WindowsInstaller")?,
        size_kb: key.text("EstimatedSize", "")?.trim().parse::<i64>().unwrap_or(0),
        ..InstalledApp::default()
    };
    if blank(&app.location) {
        // Registrations often omit InstallLocation. The icon's or the uninstaller's folder
        // still protects that folder from other apps' cleanup, but it is marked as inferred.
        let icon_value = key.text("DisplayIcon", "")?;
        let icon = strip_icon_index(icon_value.trim()).trim_matches('"').to_string();
        if host.file_exists(&icon) {
            if let Some(full) = uninstall::full(host, &icon) {
                app.location = directory_name(&full);
            }
        }
        if blank(&app.location) && !app.msi {
            if let Ok(command) = uninstall::get_command(host, &app) {
                app.location = directory_name(&command.file_name);
            }
        }
        app.location_inferred = !blank(&app.location);
        if app.location.is_none() {
            app.location = Some(String::new());
        }
    }
    app.can_remove = uninstall::get_command(host, &app).is_ok();
    Ok(Some(app))
}

/// Desktop registrations from both hives and both registry views.
///
/// Without `include_hidden`, system components, child entries and updates are left out;
/// the protection inventory includes them.
pub fn desktop(host: &dyn Host, warnings: &mut Vec<String>, include_hidden: bool) -> Vec<InstalledApp> {
    let mut apps: Vec<InstalledApp> = Vec::new();
    for machine in [false, true] {
        for view32 in [false, true] {
            let hive = if machine { Hive::LocalMachine } else { Hive::CurrentUser };
            let parent = match Key::open(hive, view32, ARP) {
                Ok(Some(parent)) => parent,
                Ok(None) => continue,
                Err(error) => {
                    warnings.push(format!("Could not read an installed app: {error}"));
                    continue;
                }
            };
            let children = match parent.sub_key_names() {
                Ok(children) => children,
                Err(error) => {
                    warnings.push(format!("Could not read an installed app: {error}"));
                    continue;
                }
            };
            for child in children {
                match read_registration(host, &parent, &child, machine, view32, include_hidden) {
                    Ok(Some(app)) => apps.push(app),
                    Ok(None) => {}
                    Err(error) => warnings.push(format!("Could not read an installed app: {error}")),
                }
            }
        }
    }
    // HKCU Software is shared across views on many systems; distinct HKLM registrations are kept.
    let mut kept: Vec<InstalledApp> = Vec::new();
    let mut keys: Vec<String> = Vec::new();
    for app in apps {
        let key = if app.machine { app.id.clone().unwrap_or_default() } else { format!("HKCU:{}", app.registry_path.as_deref().unwrap_or("")) };
        if !keys.iter().any(|seen| eq_ignore_case(seen, &key)) {
            keys.push(key);
            kept.push(app);
        }
    }
    kept
}

pub(crate) fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut text = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let value = (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        text.push(ALPHABET[(value >> 18) as usize & 63] as char);
        text.push(ALPHABET[(value >> 12) as usize & 63] as char);
        text.push(if chunk.len() > 1 { ALPHABET[(value >> 6) as usize & 63] as char } else { '=' });
        text.push(if chunk.len() > 2 { ALPHABET[value as usize & 63] as char } else { '=' });
    }
    text
}

/// Runs a Windows PowerShell 5.1 snippet without a profile or window and returns its trimmed output.
pub(crate) fn run_powershell(host: &dyn Host, code: &str, timeout: Duration) -> Result<String, String> {
    let program = format!("{}\\WindowsPowerShell\\v1.0\\powershell.exe", host.special_folder(SpecialFolder::System));
    let script = format!("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); {code}");
    let encoded: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    match run_captured(&program, &format!("-NoProfile -NonInteractive -EncodedCommand {}", base64(&encoded)), Some(timeout)) {
        Err(RunError::TimedOut) => Err("Windows app service did not respond. Refresh to try again.".to_string()),
        Err(RunError::Start(error)) => Err(error),
        Ok(run) if run.exit_code != 0 => Err(run.error.trim().to_string()),
        Ok(run) => Ok(run.output.trim().to_string()),
    }
}

fn load_indirect(source: &str) -> Option<String> {
    let source = wide(source);
    let mut output = [0u16; 1024];
    // SAFETY: the source is NUL-terminated and the output buffer is passed with its size.
    let status = unsafe { SHLoadIndirectString(source.as_ptr(), output.as_mut_ptr(), output.len() as u32, null_mut()) };
    let length = output.iter().position(|unit| *unit == 0).unwrap_or(output.len());
    (status == 0 && length > 0).then(|| String::from_utf16_lossy(&output[..length]))
}

/// Display name of a Store package: its resource string when it resolves, otherwise the
/// last part of its identity with spaces inserted at case changes.
fn store_label(label: &str, package: &str, identity: &str) -> String {
    if !label.is_empty() && starts_with_ignore_case(label, "ms-resource:") {
        let resource = label[12..].trim_start_matches('/');
        for uri in [label.to_string(), format!("ms-resource://{identity}/resources/{resource}"), format!("ms-resource://{identity}/{resource}")] {
            if let Some(text) = load_indirect(&format!("@{{{package}? {uri}}}")) {
                return text;
            }
        }
    } else if !label.trim().is_empty() {
        return label.to_string();
    }
    let last = identity.rsplit('.').next().unwrap_or(identity);
    let mut spaced = String::with_capacity(last.len() + 4);
    let mut previous: Option<char> = None;
    for character in last.chars() {
        if previous.is_some_and(|before| before.is_ascii_lowercase()) && character.is_ascii_uppercase() {
            spaced.push(' ');
        }
        spaced.push(character);
        previous = Some(character);
    }
    spaced
}

fn package_name_is_plain(text: &str) -> bool {
    !text.is_empty() && text.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

const STORE_QUERY: &str = "ConvertTo-Json -Compress -InputObject @(Get-AppxPackage | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable } | ForEach-Object { $label=''; $shell=$false; try { $manifest=Get-AppxPackageManifest $_; $label=[string]$manifest.Package.Properties.DisplayName; $shell=([string]$manifest.Package.Properties.AllowExternalContent -eq 'true' -and @($manifest.Package.Applications.Application | Where-Object { $_.VisualElements.AppListEntry -ne 'none' }).Count -eq 0) } catch {}; [pscustomobject]@{Name=$label; Identity=$_.Name; Id=$_.PackageFullName; Family=$_.PackageFamilyName; Publisher=$_.Publisher; Version=[string]$_.Version; ShellComponent=$shell} })";

/// Removable Store packages of the current user. Frameworks, resource packages, non-removable
/// packages and sparse shell-integration packages are left out.
fn store_apps(host: &dyn Host) -> Result<Vec<InstalledApp>, String> {
    let data = run_powershell(host, STORE_QUERY, Duration::from_secs(60))?;
    if data.is_empty() {
        return Ok(Vec::new());
    }
    let rows: Value = serde_json::from_str(&data).map_err(|error| error.to_string())?;
    let mut apps = Vec::new();
    for row in rows.as_array().cloned().unwrap_or_default() {
        let text = |name: &str| row.get(name).and_then(Value::as_str).unwrap_or("").to_string();
        // A sparse package with no app-list entry only adds shell integration to a desktop app.
        if row.get("ShellComponent").and_then(Value::as_bool).unwrap_or(false) {
            continue;
        }
        let (id, family) = (text("Id"), text("Family"));
        if !package_name_is_plain(&id) || !package_name_is_plain(&family) {
            continue;
        }
        let publisher = text("Publisher");
        let common_name = publisher.split(',').map(str::trim_start).find_map(|part| part.strip_prefix("CN=")).map(str::to_string);
        apps.push(InstalledApp {
            id: Some(id.clone()),
            package_family: Some(family),
            name: Some(store_label(&text("Name"), &id, &text("Identity"))),
            publisher: Some(common_name.unwrap_or(publisher)),
            version: Some(text("Version")),
            kind: Some("Microsoft Store".to_string()),
            can_remove: true,
            ..InstalledApp::default()
        });
    }
    Ok(apps)
}

/// Everything installed, sorted by name. A Store failure only adds a warning.
pub fn inventory(host: &dyn Host) -> AppInventory {
    let mut result = AppInventory::default();
    result.apps = desktop(host, &mut result.warnings, false);
    match store_apps(host) {
        Ok(apps) => result.apps.extend(apps),
        Err(error) => result.warnings.push(format!("Microsoft Store apps could not be read: {error}")),
    }
    result.apps.sort_by(|left, right| compare_culture(left.name.as_deref().unwrap_or(""), right.name.as_deref().unwrap_or(""), true));
    result
}

/// Is an app still registered? A desktop app whose recorded path is not an uninstall
/// registration counts as registered, so nothing is cleaned on doubtful evidence.
pub fn registered(app: &InstalledApp, inventory: &AppInventory) -> Result<bool, String> {
    if app.kind.as_deref() == Some("Microsoft Store") {
        return Ok(inventory.apps.iter().any(|other| other.id == app.id || other.package_family == app.package_family));
    }
    let Some(path) = app.registry_path.as_deref().filter(|path| !path.is_empty() && starts_with_ignore_case(path, &format!("{ARP}\\"))) else { return Ok(true) };
    registry::key_exists(if app.machine { Hive::LocalMachine } else { Hive::CurrentUser }, app.view32, path)
}
